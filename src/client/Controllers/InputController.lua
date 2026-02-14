--!strict
--[[
    InputController.lua

    Handles all player input for city and battle modes.
    Manages mouse, touch, and keyboard input.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local InputController = {}
InputController.__index = InputController

-- Events
InputController.PrimaryAction = Signal.new() -- Left click / tap
InputController.SecondaryAction = Signal.new() -- Right click / long press
InputController.CancelAction = Signal.new() -- Escape / back
InputController.WorldPositionClicked = Signal.new() -- 3D world position clicked

-- Private state
local _initialized = false
local _player = Players.LocalPlayer
local _mouse = _player:GetMouse()
local _camera = workspace.CurrentCamera

-- Input mode
local _inputMode: "mouse" | "touch" | "gamepad" = "mouse"
local _isEnabled = true

-- Touch state
local _touchStartPosition: Vector2? = nil
local _touchStartTime: number = 0
local _longPressThreshold = 0.5 -- seconds
local _longPressTriggered = false

-- Grid settings (must match CityRenderer/BattleRenderer)
local CELL_SIZE = 3

--[[
    Gets the current input mode.
]]
function InputController:GetInputMode(): string
    return _inputMode
end

--[[
    Enables or disables input processing.
]]
function InputController:SetEnabled(enabled: boolean)
    _isEnabled = enabled
end

--[[
    Checks if input is enabled.
]]
function InputController:IsEnabled(): boolean
    return _isEnabled
end

--[[
    Raycasts from screen position to world.
]]
local function screenToWorld(screenPosition: Vector2): Vector3?
    local camera = workspace.CurrentCamera
    if not camera then return nil end

    local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)

    -- Raycast against ground plane (Y = 0)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {_player.Character}

    local result = workspace:Raycast(ray.Origin, ray.Direction * 500, params)

    if result then
        return result.Position
    else
        -- Calculate intersection with Y=0 plane
        if ray.Direction.Y ~= 0 then
            local t = -ray.Origin.Y / ray.Direction.Y
            if t > 0 then
                return ray.Origin + ray.Direction * t
            end
        end
    end

    return nil
end

--[[
    Converts world position to grid position.
]]
function InputController:WorldToGrid(worldPos: Vector3): (number, number)
    local gridX = math.floor(worldPos.X / CELL_SIZE)
    local gridZ = math.floor(worldPos.Z / CELL_SIZE)
    return gridX, gridZ
end

--[[
    Converts grid position to world position (center of cell).
]]
function InputController:GridToWorld(gridX: number, gridZ: number): Vector3
    return Vector3.new(
        gridX * CELL_SIZE + CELL_SIZE / 2,
        0,
        gridZ * CELL_SIZE + CELL_SIZE / 2
    )
end

--[[
    Gets the world position under the mouse/touch.
]]
function InputController:GetWorldPositionUnderCursor(): Vector3?
    if _inputMode == "touch" then
        -- For touch, we need active touch position
        local touches = UserInputService:GetTouchPositions()
        if #touches > 0 then
            return screenToWorld(touches[1])
        end
    else
        -- For mouse
        return screenToWorld(Vector2.new(_mouse.X, _mouse.Y))
    end
    return nil
end

--[[
    Gets the grid position under the cursor.
]]
function InputController:GetGridPositionUnderCursor(): (number?, number?)
    local worldPos = self:GetWorldPositionUnderCursor()
    if worldPos then
        return self:WorldToGrid(worldPos)
    end
    return nil
end

--[[
    Handles mouse button input.
]]
local function handleMouseButton(input: InputObject, gameProcessed: boolean)
    if gameProcessed or not _isEnabled then return end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if input.UserInputState == Enum.UserInputState.Begin then
            local worldPos = screenToWorld(Vector2.new(input.Position.X, input.Position.Y))
            if worldPos then
                InputController.WorldPositionClicked:Fire(worldPos)
                InputController.PrimaryAction:Fire(worldPos)
            end
        end
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        if input.UserInputState == Enum.UserInputState.Begin then
            local worldPos = screenToWorld(Vector2.new(input.Position.X, input.Position.Y))
            if worldPos then
                InputController.SecondaryAction:Fire(worldPos)
            end
        end
    end
end

--[[
    Handles touch input.
]]
local function handleTouchInput(input: InputObject, gameProcessed: boolean)
    if gameProcessed or not _isEnabled then return end

    if input.UserInputType == Enum.UserInputType.Touch then
        if input.UserInputState == Enum.UserInputState.Begin then
            _touchStartPosition = Vector2.new(input.Position.X, input.Position.Y)
            _touchStartTime = tick()
            _longPressTriggered = false
        elseif input.UserInputState == Enum.UserInputState.End then
            if _touchStartPosition and not _longPressTriggered then
                local endPosition = Vector2.new(input.Position.X, input.Position.Y)
                local distance = (endPosition - _touchStartPosition).Magnitude

                -- Only trigger tap if finger didn't move much
                if distance < 20 then
                    local worldPos = screenToWorld(endPosition)
                    if worldPos then
                        InputController.WorldPositionClicked:Fire(worldPos)
                        InputController.PrimaryAction:Fire(worldPos)
                    end
                end
            end

            _touchStartPosition = nil
            _longPressTriggered = false
        end
    end
end

--[[
    Handles keyboard input.
]]
local function handleKeyboard(input: InputObject, gameProcessed: boolean)
    if gameProcessed or not _isEnabled then return end

    if input.UserInputState == Enum.UserInputState.Begin then
        if input.KeyCode == Enum.KeyCode.Escape then
            InputController.CancelAction:Fire()
        end
    end
end

--[[
    Checks for long press (called every frame).
]]
local function checkLongPress()
    if _touchStartPosition and not _longPressTriggered then
        local elapsed = tick() - _touchStartTime
        if elapsed >= _longPressThreshold then
            _longPressTriggered = true

            local worldPos = screenToWorld(_touchStartPosition)
            if worldPos then
                InputController.SecondaryAction:Fire(worldPos)
            end
        end
    end
end

--[[
    Detects input mode based on last input.
]]
local function detectInputMode(input: InputObject)
    if input.UserInputType == Enum.UserInputType.Touch then
        _inputMode = "touch"
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.MouseButton2 or
           input.UserInputType == Enum.UserInputType.MouseMovement then
        _inputMode = "mouse"
    elseif input.UserInputType == Enum.UserInputType.Gamepad1 then
        _inputMode = "gamepad"
    end
end

--[[
    Initializes the InputController.
]]
function InputController:Init()
    if _initialized then
        warn("InputController already initialized")
        return
    end

    -- Detect initial input mode
    if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
        _inputMode = "touch"
    elseif UserInputService.GamepadEnabled then
        _inputMode = "gamepad"
    else
        _inputMode = "mouse"
    end

    -- Connect input handlers
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        detectInputMode(input)
        handleMouseButton(input, gameProcessed)
        handleTouchInput(input, gameProcessed)
        handleKeyboard(input, gameProcessed)
    end)

    UserInputService.InputEnded:Connect(function(input, gameProcessed)
        handleTouchInput(input, gameProcessed)
    end)

    -- Long press check
    RunService.Heartbeat:Connect(checkLongPress)

    _initialized = true
    print("InputController initialized - Mode:", _inputMode)
end

return InputController
