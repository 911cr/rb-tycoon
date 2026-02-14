--!strict
--[[
    OverworldController.lua

    Client-side controller for the overworld experience.
    Manages camera, player movement, and base rendering.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local OverworldController = {}
OverworldController.__index = OverworldController

-- ============================================================================
-- SIGNALS
-- ============================================================================

OverworldController.PositionChanged = Signal.new()
OverworldController.BaseApproached = Signal.new()
OverworldController.BaseLeft = Signal.new()

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _initialized = false
local _player = Players.LocalPlayer
local _camera = workspace.CurrentCamera

local _humanoidRootPart: Part? = nil
local _lastPosition: Vector3 = Vector3.new(0, 0, 0)
local _updateConnection: RBXScriptConnection? = nil
local _positionUpdateInterval = 0.5 -- seconds
local _lastPositionUpdate = 0

-- Base tracking
local _spawnedBases: {[number]: Model} = {} -- userId -> base model
local _nearbyBases: {[number]: any} = {} -- userId -> base data

-- Camera state
local _cameraOffset = OverworldConfig.Camera.DefaultOffset
local _cameraZoom = 40

-- Events reference
local _events: Folder? = nil
local _updatePosition: RemoteEvent? = nil

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Gets the Events folder.
]]
local function getEvents(): Folder?
    if _events then return _events end
    _events = ReplicatedStorage:WaitForChild("Events", 5) :: Folder?
    return _events
end

--[[
    Gets the MiniBaseBuilder from ServerScriptService (client can't, so we recreate)
]]
local function createClientMiniBase(baseData: any): Model
    local base = Instance.new("Model")
    base.Name = "Base_" .. baseData.userId

    local config = OverworldConfig.Base
    local keepHeight = OverworldConfig.GetKeepHeight(baseData.townHallLevel)

    -- Determine color
    local color: Color3
    if baseData.isOwnBase then
        color = OverworldConfig.Visuals.OwnBaseColor
    elseif baseData.isFriend then
        color = OverworldConfig.Visuals.FriendColor
    else
        local playerTH = 1 -- Would need to get from player data
        local thDiff = baseData.townHallLevel - playerTH
        color = OverworldConfig.GetDifficultyColor(thDiff)
    end

    -- Simple keep
    local keep = Instance.new("Part")
    keep.Name = "Keep"
    keep.Size = Vector3.new(8, keepHeight, 8)
    keep.Position = baseData.position + Vector3.new(0, keepHeight / 2 + 0.5, 0)
    keep.Anchored = true
    keep.Material = Enum.Material.Brick
    keep.Color = Color3.fromRGB(150, 140, 130)
    keep.Parent = base

    -- Color accent
    local accent = Instance.new("Part")
    accent.Name = "Accent"
    accent.Size = Vector3.new(8.1, 1, 8.1)
    accent.Position = baseData.position + Vector3.new(0, keepHeight * 0.3, 0)
    accent.Anchored = true
    accent.Material = Enum.Material.Fabric
    accent.Color = color
    accent.Parent = base

    -- Wall ring
    local wallRadius = config.WallRadius
    local wallHeight = config.WallHeight

    for i = 0, 3 do
        local angle = i * math.pi / 2
        local wallPos = baseData.position + Vector3.new(
            math.cos(angle) * wallRadius,
            wallHeight / 2,
            math.sin(angle) * wallRadius
        )

        local wall = Instance.new("Part")
        wall.Name = "Wall" .. i
        wall.Size = Vector3.new(wallRadius * 1.5, wallHeight, 1)
        wall.CFrame = CFrame.new(wallPos) * CFrame.Angles(0, angle + math.pi / 2, 0)
        wall.Anchored = true
        wall.Material = Enum.Material.Rock
        wall.Color = Color3.fromRGB(130, 125, 120)
        wall.Parent = base
    end

    -- Ground
    local ground = Instance.new("Part")
    ground.Name = "Ground"
    ground.Size = Vector3.new(config.Size + 4, 0.2, config.Size + 4)
    ground.Position = baseData.position + Vector3.new(0, 0.1, 0)
    ground.Anchored = true
    ground.Material = Enum.Material.Cobblestone
    ground.Color = Color3.fromRGB(95, 85, 65)
    ground.Parent = base

    -- Banner GUI
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Banner"
    billboard.Size = UDim2.new(0, 200, 0, 80)
    billboard.StudsOffset = Vector3.new(0, keepHeight + 4, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 120
    billboard.Adornee = keep
    billboard.Parent = keep

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(40, 35, 30)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Parent = billboard

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.1, 0)
    corner.Parent = frame

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = baseData.username
    nameLabel.TextColor3 = baseData.isOnline and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(220, 210, 180)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = frame

    local statsLabel = Instance.new("TextLabel")
    statsLabel.Size = UDim2.new(1, 0, 0.4, 0)
    statsLabel.Position = UDim2.new(0, 0, 0.5, 0)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Text = string.format("TH %d | %d Trophies", baseData.townHallLevel, baseData.trophies)
    statsLabel.TextColor3 = Color3.fromRGB(180, 160, 120)
    statsLabel.TextScaled = true
    statsLabel.Font = Enum.Font.Gotham
    statsLabel.Parent = frame

    -- Store data as attributes
    base:SetAttribute("UserId", baseData.userId)
    base:SetAttribute("IsOwnBase", baseData.isOwnBase or false)

    -- Parent to bases folder
    local overworldFolder = workspace:FindFirstChild("Overworld")
    if overworldFolder then
        local basesFolder = overworldFolder:FindFirstChild("Bases")
        if not basesFolder then
            basesFolder = Instance.new("Folder")
            basesFolder.Name = "Bases"
            basesFolder.Parent = overworldFolder
        end
        base.Parent = basesFolder
    else
        base.Parent = workspace
    end

    return base
end

--[[
    Updates the camera position to follow the player.
]]
local function updateCamera()
    if not _humanoidRootPart or not _camera then return end

    local playerPos = _humanoidRootPart.Position
    local cameraPos = playerPos + _cameraOffset

    -- Smooth camera follow
    local currentPos = _camera.CFrame.Position
    local newPos = currentPos:Lerp(cameraPos, 0.1)

    _camera.CameraType = Enum.CameraType.Scriptable
    _camera.CFrame = CFrame.new(newPos, playerPos + Vector3.new(0, 2, 0))
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Initializes the OverworldController.
]]
function OverworldController:Init()
    if _initialized then
        warn("[OverworldController] Already initialized")
        return
    end

    -- Get events
    local events = getEvents()
    if events then
        _updatePosition = events:FindFirstChild("UpdatePosition") :: RemoteEvent?
    end

    -- Use default Roblox camera (Custom) so players can look around freely
    _camera = workspace.CurrentCamera
    if _camera then
        _camera.CameraType = Enum.CameraType.Custom
    end

    _initialized = true
    print("[OverworldController] Initialized")
end

--[[
    Starts the position update loop.

    @param humanoidRootPart Part - The player's HumanoidRootPart
]]
function OverworldController:StartPositionUpdates(humanoidRootPart: Part)
    _humanoidRootPart = humanoidRootPart
    _lastPosition = humanoidRootPart.Position

    -- Disconnect existing connection
    if _updateConnection then
        _updateConnection:Disconnect()
    end

    -- Start update loop
    _updateConnection = RunService.Heartbeat:Connect(function(dt)
        if not _humanoidRootPart then return end

        -- Check if position changed significantly
        local currentPos = _humanoidRootPart.Position
        local distance = (currentPos - _lastPosition).Magnitude

        -- Send position update to server periodically
        local now = os.clock()
        if now - _lastPositionUpdate >= _positionUpdateInterval then
            if distance > 1 then -- Only update if moved more than 1 stud
                _lastPosition = currentPos
                _lastPositionUpdate = now

                if _updatePosition then
                    _updatePosition:FireServer(currentPos)
                end

                self.PositionChanged:Fire(currentPos)
            end
        end
    end)

    print("[OverworldController] Position updates started")
end

--[[
    Stops position updates.
]]
function OverworldController:StopPositionUpdates()
    if _updateConnection then
        _updateConnection:Disconnect()
        _updateConnection = nil
    end
end

--[[
    Called when server spawns a new base.

    @param baseData table - The base data from server
]]
function OverworldController:OnBaseSpawned(baseData: any)
    if not baseData or not baseData.userId then return end

    -- Check if base already exists
    local existingBase = _spawnedBases[baseData.userId]
    if existingBase then
        existingBase:Destroy()
    end

    -- Create new base model
    local baseModel = createClientMiniBase(baseData)
    _spawnedBases[baseData.userId] = baseModel
    _nearbyBases[baseData.userId] = baseData

    print(string.format("[OverworldController] Base spawned for: %s", baseData.username))
end

--[[
    Called when server removes a base.

    @param userId number - The user ID of the removed base
]]
function OverworldController:OnBaseRemoved(userId: number)
    local baseModel = _spawnedBases[userId]
    if baseModel then
        baseModel:Destroy()
        _spawnedBases[userId] = nil
        _nearbyBases[userId] = nil

        print(string.format("[OverworldController] Base removed: %d", userId))
    end
end

--[[
    Called when server sends position sync update.

    @param nearbyBases table - Array of nearby base data
]]
function OverworldController:OnPositionSync(nearbyBases: {any})
    -- Update nearby bases cache
    local newNearbyIds = {}

    for _, baseData in nearbyBases do
        newNearbyIds[baseData.userId] = true

        -- Spawn if not already spawned
        if not _spawnedBases[baseData.userId] then
            self:OnBaseSpawned(baseData)
        else
            -- Update existing base data
            _nearbyBases[baseData.userId] = baseData
        end
    end

    -- Remove bases that are no longer nearby
    for userId, _ in _spawnedBases do
        if not newNearbyIds[userId] and not _nearbyBases[userId].isOwnBase then
            self:OnBaseRemoved(userId)
        end
    end
end

--[[
    Gets the current player position.

    @return Vector3 - Current position
]]
function OverworldController:GetCurrentPosition(): Vector3
    if _humanoidRootPart then
        return _humanoidRootPart.Position
    end
    return Vector3.new(0, 0, 0)
end

--[[
    Gets nearby base data.

    @return table - Map of userId to base data
]]
function OverworldController:GetNearbyBases(): {[number]: any}
    return _nearbyBases
end

--[[
    Gets a specific base's data.

    @param userId number - The user ID
    @return table? - Base data or nil
]]
function OverworldController:GetBaseData(userId: number): any?
    return _nearbyBases[userId]
end

--[[
    Sets the camera zoom level.

    @param zoom number - Zoom level (studs distance)
]]
function OverworldController:SetCameraZoom(zoom: number)
    _cameraZoom = math.clamp(zoom, OverworldConfig.Camera.MinZoom, OverworldConfig.Camera.MaxZoom)
    _cameraOffset = Vector3.new(0, _cameraZoom * 0.75, _cameraZoom)
end

--[[
    Highlights a base.

    @param userId number - The user ID of the base
    @param highlighted boolean - Whether to highlight
]]
function OverworldController:HighlightBase(userId: number, highlighted: boolean)
    local baseModel = _spawnedBases[userId]
    if not baseModel then return end

    local existingHighlight = baseModel:FindFirstChild("SelectionHighlight")

    if highlighted and not existingHighlight then
        local highlight = Instance.new("Highlight")
        highlight.Name = "SelectionHighlight"
        highlight.FillColor = Color3.fromRGB(255, 255, 100)
        highlight.FillTransparency = 0.7
        highlight.OutlineColor = Color3.fromRGB(255, 200, 50)
        highlight.OutlineTransparency = 0
        highlight.Parent = baseModel
    elseif not highlighted and existingHighlight then
        existingHighlight:Destroy()
    end
end

return OverworldController
