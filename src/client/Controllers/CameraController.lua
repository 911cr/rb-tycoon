--!strict
--[[
    CameraController.lua

    Manages camera behavior for city and battle views.
    Handles panning, zooming, and rotation.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CameraController = {}
CameraController.__index = CameraController

-- Private state
local _initialized = false
local _player = Players.LocalPlayer
local _camera = workspace.CurrentCamera

-- Camera mode: "city" | "battle" | "free"
local _mode = "city"

-- Camera settings by mode
local ModeSettings = {
    city = {
        minZoom = 20,
        maxZoom = 80,
        defaultZoom = 50,
        angle = 60, -- degrees from horizontal
        panSpeed = 0.5,
        zoomSpeed = 5,
        bounds = { minX = -50, maxX = 150, minZ = -50, maxZ = 150 },
    },
    battle = {
        minZoom = 30,
        maxZoom = 100,
        defaultZoom = 60,
        angle = 55,
        panSpeed = 0.6,
        zoomSpeed = 6,
        bounds = { minX = -20, maxX = 140, minZ = -20, maxZ = 140 },
    },
}

-- Current camera state
local _targetPosition = Vector3.new(60, 0, 60) -- Center of grid
local _currentZoom = 50
local _isDragging = false
local _lastMousePosition = Vector2.zero
local _touchIds: {[number]: Vector2} = {}
local _initialPinchDistance: number? = nil

--[[
    Gets the current camera mode.
]]
function CameraController:GetMode(): string
    return _mode
end

--[[
    Sets the camera mode.
]]
function CameraController:SetMode(mode: string)
    local settings = ModeSettings[mode]
    if not settings then
        warn("Invalid camera mode:", mode)
        return
    end

    _mode = mode
    _currentZoom = settings.defaultZoom

    print("[Camera] Mode set to:", mode)
end

--[[
    Sets the camera focus position.
]]
function CameraController:SetFocus(position: Vector3)
    _targetPosition = Vector3.new(position.X, 0, position.Z)
end

--[[
    Focuses camera on a specific building or position.
]]
function CameraController:FocusOn(position: Vector3, instant: boolean?)
    local newTarget = Vector3.new(position.X, 0, position.Z)

    if instant then
        _targetPosition = newTarget
    else
        -- Smooth transition
        local startPos = _targetPosition
        local elapsed = 0
        local duration = 0.5

        local connection
        connection = RunService.Heartbeat:Connect(function(dt)
            elapsed += dt
            local alpha = math.min(elapsed / duration, 1)
            alpha = 1 - (1 - alpha) ^ 3 -- Ease out cubic

            _targetPosition = startPos:Lerp(newTarget, alpha)

            if alpha >= 1 then
                connection:Disconnect()
            end
        end)
    end
end

--[[
    Zooms the camera.
]]
function CameraController:Zoom(delta: number)
    local settings = ModeSettings[_mode]
    if not settings then return end

    _currentZoom = math.clamp(_currentZoom - delta * settings.zoomSpeed, settings.minZoom, settings.maxZoom)
end

--[[
    Pans the camera.
]]
function CameraController:Pan(deltaX: number, deltaZ: number)
    local settings = ModeSettings[_mode]
    if not settings then return end

    -- Adjust pan speed based on zoom level
    local zoomFactor = _currentZoom / settings.defaultZoom
    local scaledSpeed = settings.panSpeed * zoomFactor

    local newX = _targetPosition.X + deltaX * scaledSpeed
    local newZ = _targetPosition.Z + deltaZ * scaledSpeed

    -- Clamp to bounds
    newX = math.clamp(newX, settings.bounds.minX, settings.bounds.maxX)
    newZ = math.clamp(newZ, settings.bounds.minZ, settings.bounds.maxZ)

    _targetPosition = Vector3.new(newX, 0, newZ)
end

--[[
    Resets camera to default position.
]]
function CameraController:Reset()
    local settings = ModeSettings[_mode]
    if not settings then return end

    _currentZoom = settings.defaultZoom
    _targetPosition = Vector3.new(60, 0, 60) -- Center of grid
end

--[[
    Updates the camera transform.
]]
local function updateCamera()
    local settings = ModeSettings[_mode]
    if not settings then return end

    -- Calculate camera position based on target, zoom, and angle
    local angleRad = math.rad(settings.angle)
    local height = _currentZoom * math.sin(angleRad)
    local distance = _currentZoom * math.cos(angleRad)

    local cameraPosition = Vector3.new(
        _targetPosition.X,
        height,
        _targetPosition.Z + distance
    )

    -- Look at target
    _camera.CameraType = Enum.CameraType.Scriptable
    _camera.CFrame = CFrame.lookAt(cameraPosition, _targetPosition)
end

--[[
    Handles mouse wheel scrolling for zoom.
]]
local function handleMouseWheel(input: InputObject)
    if input.UserInputType == Enum.UserInputType.MouseWheel then
        CameraController:Zoom(input.Position.Z)
    end
end

--[[
    Handles mouse button input for panning.
]]
local function handleMouseButton(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end

    if input.UserInputType == Enum.UserInputType.MouseButton2 or
       input.UserInputType == Enum.UserInputType.MouseButton3 then
        if input.UserInputState == Enum.UserInputState.Begin then
            _isDragging = true
            _lastMousePosition = Vector2.new(input.Position.X, input.Position.Y)
        end
    end
end

--[[
    Handles mouse button release.
]]
local function handleMouseButtonRelease(input: InputObject)
    if input.UserInputType == Enum.UserInputType.MouseButton2 or
       input.UserInputType == Enum.UserInputType.MouseButton3 then
        _isDragging = false
    end
end

--[[
    Handles mouse movement for panning.
]]
local function handleMouseMovement(input: InputObject)
    if not _isDragging then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement then
        local currentPosition = Vector2.new(input.Position.X, input.Position.Y)
        local delta = currentPosition - _lastMousePosition

        -- Convert screen space delta to world space pan
        CameraController:Pan(-delta.X, -delta.Y)

        _lastMousePosition = currentPosition
    end
end

--[[
    Handles touch input for mobile.
]]
local function handleTouchInput(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end

    if input.UserInputType == Enum.UserInputType.Touch then
        if input.UserInputState == Enum.UserInputState.Begin then
            _touchIds[input.Position.X + input.Position.Y * 10000] = Vector2.new(input.Position.X, input.Position.Y)
        elseif input.UserInputState == Enum.UserInputState.End then
            _touchIds[input.Position.X + input.Position.Y * 10000] = nil
            _initialPinchDistance = nil
        elseif input.UserInputState == Enum.UserInputState.Change then
            local touchCount = 0
            local touches = {}
            for _, pos in _touchIds do
                touchCount += 1
                table.insert(touches, pos)
            end

            if touchCount == 1 then
                -- Single finger pan
                local oldPos = _touchIds[input.Position.X + input.Position.Y * 10000]
                if oldPos then
                    local delta = Vector2.new(input.Position.X, input.Position.Y) - oldPos
                    CameraController:Pan(-delta.X, -delta.Y)
                    _touchIds[input.Position.X + input.Position.Y * 10000] = Vector2.new(input.Position.X, input.Position.Y)
                end
            elseif touchCount == 2 then
                -- Two finger pinch zoom
                local dist = (touches[1] - touches[2]).Magnitude
                if _initialPinchDistance then
                    local zoomDelta = (dist - _initialPinchDistance) * 0.01
                    CameraController:Zoom(zoomDelta)
                end
                _initialPinchDistance = dist
            end
        end
    end
end

--[[
    Initializes the CameraController.
]]
function CameraController:Init()
    if _initialized then
        warn("CameraController already initialized")
        return
    end

    -- Set default mode
    _mode = "city"
    local settings = ModeSettings[_mode]
    _currentZoom = settings.defaultZoom

    -- Connect input handlers
    UserInputService.InputBegan:Connect(handleMouseButton)
    UserInputService.InputEnded:Connect(handleMouseButtonRelease)
    UserInputService.InputChanged:Connect(function(input)
        handleMouseWheel(input)
        handleMouseMovement(input)
    end)
    UserInputService.TouchStarted:Connect(handleTouchInput)
    UserInputService.TouchMoved:Connect(handleTouchInput)
    UserInputService.TouchEnded:Connect(handleTouchInput)

    -- Update camera every frame
    RunService.RenderStepped:Connect(updateCamera)

    _initialized = true
    print("CameraController initialized")
end

return CameraController
