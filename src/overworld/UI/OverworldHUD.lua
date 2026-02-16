--!strict
--[[
    OverworldHUD.lua

    Heads-up display for the overworld showing:
    - Mini-map (bird's eye view centered on player with base dots)
    - Player resources
    - Nearby player count
    - Teleport loading screen
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local OverworldHUD = {}
OverworldHUD.__index = OverworldHUD

-- Signals
OverworldHUD.GoToCityClicked = Signal.new()
OverworldHUD.FindBattleClicked = Signal.new()
OverworldHUD.DefenseLogClicked = Signal.new()

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _initialized = false
local _player = Players.LocalPlayer
local _playerGui: PlayerGui? = nil

local _screenGui: ScreenGui? = nil
local _resourcesFrame: Frame? = nil
local _riskLabel: TextLabel? = nil
local _miniMapFrame: Frame? = nil
local _loadingFrame: Frame? = nil
local _errorFrame: Frame? = nil
local _goToCityButton: TextButton? = nil
local _findBattleButton: TextButton? = nil
local _defenseLogButton: TextButton? = nil
local _shieldFrame: Frame? = nil
local _shieldTimerLabel: TextLabel? = nil
local _shieldWarningLabel: TextLabel? = nil
local _shieldPulseActive = false

-- Minimap state
local _baseDots: {[number]: Frame} = {} -- userId -> dot Frame
local _homeDot: Frame? = nil
local _basesData: {any} = {} -- latest nearby bases from server
local _playerWorldPos: Vector3? = nil -- player's current world position
local _ownBasePosition: Vector3? = nil -- player's own base position
local _zoneLabel: TextLabel? = nil

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local LOOT_AVAILABLE_PERCENT = 0.85 -- 85% of stored resources exposed to raids
local MINIMAP_VIEW_RADIUS = 300 -- studs visible from center to edge
local MINIMAP_SIZE = 200 -- pixels

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Formats a number with comma separators for readability.
    e.g., 4250 -> "4,250"
]]
local function formatNumber(num: number): string
    local formatted = tostring(math.floor(num))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

--[[
    Creates or reuses a base dot on the minimap.
]]
local function getOrCreateBaseDot(userId: number, parent: Frame): Frame
    if _baseDots[userId] then
        return _baseDots[userId]
    end

    local dot = Instance.new("Frame")
    dot.Name = "BaseDot_" .. userId
    dot.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
    dot.BorderSizePixel = 0
    dot.ZIndex = 3
    dot.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = dot

    _baseDots[userId] = dot
    return dot
end

--[[
    Refreshes all base dot positions relative to player position on the minimap.
]]
local function refreshBaseDotPositions()
    if not _miniMapFrame or not _playerWorldPos then return end

    local playerX = _playerWorldPos.X
    local playerZ = _playerWorldPos.Z

    -- Track which dots are still active
    local activeIds: {[number]: boolean} = {}

    -- Render nearby base dots
    for _, baseData in _basesData do
        local bx = baseData.position.X
        local bz = baseData.position.Z
        local dx = bx - playerX
        local dz = bz - playerZ

        -- Normalize to minimap coordinates (0..1)
        local mapX = 0.5 + (dx / MINIMAP_VIEW_RADIUS) * 0.5
        local mapZ = 0.5 + (dz / MINIMAP_VIEW_RADIUS) * 0.5

        -- Skip if outside visible area (with small margin)
        if mapX < -0.02 or mapX > 1.02 or mapZ < -0.02 or mapZ > 1.02 then
            -- Hide dot if exists
            if _baseDots[baseData.userId] then
                _baseDots[baseData.userId].Visible = false
            end
            continue
        end

        mapX = math.clamp(mapX, 0, 1)
        mapZ = math.clamp(mapZ, 0, 1)

        local dot = getOrCreateBaseDot(baseData.userId, _miniMapFrame)
        activeIds[baseData.userId] = true

        -- Color and size based on relationship
        local dotSize = 6
        local dotColor: Color3

        if baseData.isFriend then
            dotColor = OverworldConfig.Visuals.FriendColor
            dotSize = 7
        elseif baseData.hasShield then
            dotColor = OverworldConfig.Visuals.ShieldColor
        else
            -- Difficulty color
            dotColor = OverworldConfig.GetDifficultyColor(
                baseData.townHallLevel - (baseData.viewerTownHallLevel or 1)
            )
        end

        dot.Size = UDim2.new(0, dotSize, 0, dotSize)
        dot.Position = UDim2.new(mapX, -dotSize / 2, mapZ, -dotSize / 2)
        dot.BackgroundColor3 = dotColor
        dot.Visible = true
    end

    -- Render own base "home" dot
    if _ownBasePosition then
        local dx = _ownBasePosition.X - playerX
        local dz = _ownBasePosition.Z - playerZ
        local mapX = 0.5 + (dx / MINIMAP_VIEW_RADIUS) * 0.5
        local mapZ = 0.5 + (dz / MINIMAP_VIEW_RADIUS) * 0.5

        if not _homeDot then
            _homeDot = Instance.new("Frame")
            _homeDot.Name = "HomeDot"
            _homeDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            _homeDot.BorderSizePixel = 0
            _homeDot.ZIndex = 4
            _homeDot.Parent = _miniMapFrame

            local hCorner = Instance.new("UICorner")
            hCorner.CornerRadius = UDim.new(1, 0)
            hCorner.Parent = _homeDot

            -- "H" label on home dot
            local hLabel = Instance.new("TextLabel")
            hLabel.Name = "HomeLabel"
            hLabel.Size = UDim2.new(1, 0, 1, 0)
            hLabel.BackgroundTransparency = 1
            hLabel.Text = "H"
            hLabel.TextColor3 = Color3.fromRGB(40, 30, 50)
            hLabel.TextSize = 7
            hLabel.Font = Enum.Font.GothamBold
            hLabel.ZIndex = 5
            hLabel.Parent = _homeDot
        end

        if mapX >= -0.02 and mapX <= 1.02 and mapZ >= -0.02 and mapZ <= 1.02 then
            mapX = math.clamp(mapX, 0, 1)
            mapZ = math.clamp(mapZ, 0, 1)
            _homeDot.Size = UDim2.new(0, 10, 0, 10)
            _homeDot.Position = UDim2.new(mapX, -5, mapZ, -5)
            _homeDot.Visible = true
        else
            _homeDot.Visible = false
        end
    end

    -- Remove dots for bases no longer in data
    for userId, dot in _baseDots do
        if not activeIds[userId] then
            dot:Destroy()
            _baseDots[userId] = nil
        end
    end

    -- Update zone label
    if _zoneLabel and _playerWorldPos then
        local zone = OverworldConfig.GetZone(playerX, playerZ)
        if zone == "safe" then
            _zoneLabel.Text = "Safe Zone"
            _zoneLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
        elseif zone == "forbidden" then
            _zoneLabel.Text = "Forbidden Zone"
            _zoneLabel.TextColor3 = Color3.fromRGB(200, 80, 80)
        else
            _zoneLabel.Text = "Wilderness"
            _zoneLabel.TextColor3 = Color3.fromRGB(220, 180, 80)
        end
    end
end

-- ============================================================================
-- UI CREATION
-- ============================================================================

--[[
    Creates a resource display bar.
]]
local function createResourceBar(name: string, color: Color3, imageId: string, parent: Frame): Frame
    local frame = Instance.new("Frame")
    frame.Name = name .. "Bar"
    frame.Size = UDim2.new(0, 120, 0, 35)
    frame.BackgroundColor3 = Color3.fromRGB(40, 38, 35)
    frame.BorderSizePixel = 0
    frame.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame

    -- Icon
    local icon = Instance.new("Frame")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 25, 0, 25)
    icon.Position = UDim2.new(0, 5, 0.5, -12)
    icon.BackgroundColor3 = color
    icon.Parent = frame

    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(0, 4)
    iconCorner.Parent = icon

    local iconImage = Instance.new("ImageLabel")
    iconImage.Name = "IconImage"
    iconImage.Size = UDim2.new(0, 19, 0, 19)
    iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
    iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
    iconImage.BackgroundTransparency = 1
    iconImage.Image = imageId
    iconImage.ImageColor3 = Color3.new(1, 1, 1)
    iconImage.ScaleType = Enum.ScaleType.Fit
    iconImage.Parent = icon

    -- Value
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "Value"
    valueLabel.Size = UDim2.new(1, -40, 1, 0)
    valueLabel.Position = UDim2.new(0, 35, 0, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = "0"
    valueLabel.TextColor3 = Color3.fromRGB(240, 230, 200)
    valueLabel.TextSize = 16
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextXAlignment = Enum.TextXAlignment.Left
    valueLabel.Parent = frame

    return frame
end

--[[
    Creates the HUD UI.
]]
local function createHUD(): ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "OverworldHUD"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    -- Resources container (top-left)
    local resourcesFrame = Instance.new("Frame")
    resourcesFrame.Name = "Resources"
    resourcesFrame.Size = UDim2.new(0, 220, 0, 150)
    resourcesFrame.Position = UDim2.new(0, 15, 0, 15)
    resourcesFrame.BackgroundTransparency = 1
    resourcesFrame.Parent = screenGui

    local resourcesLayout = Instance.new("UIListLayout")
    resourcesLayout.FillDirection = Enum.FillDirection.Vertical
    resourcesLayout.Padding = UDim.new(0, 5)
    resourcesLayout.Parent = resourcesFrame

    -- Gold bar
    createResourceBar("Gold", Color3.fromRGB(255, 200, 50), "rbxassetid://132769554", resourcesFrame)

    -- Wood bar
    createResourceBar("Wood", Color3.fromRGB(139, 100, 60), "rbxassetid://16537944090", resourcesFrame)

    -- Food bar
    createResourceBar("Food", Color3.fromRGB(100, 180, 80), "rbxassetid://2958706766", resourcesFrame)

    -- Raid risk indicator (below resource bars)
    local riskLabel = Instance.new("TextLabel")
    riskLabel.Name = "RiskIndicator"
    riskLabel.Size = UDim2.new(0, 220, 0, 18)
    riskLabel.BackgroundTransparency = 1
    riskLabel.Text = ""
    riskLabel.TextColor3 = Color3.fromRGB(200, 130, 80)
    riskLabel.TextSize = 10
    riskLabel.Font = Enum.Font.Gotham
    riskLabel.TextXAlignment = Enum.TextXAlignment.Left
    riskLabel.TextTransparency = 0.2
    riskLabel.Parent = resourcesFrame

    _riskLabel = riskLabel
    _resourcesFrame = resourcesFrame

    -- ================================================================
    -- Mini-map container (top-right) — 200x200 bird's eye view
    -- ================================================================
    local miniMapFrame = Instance.new("Frame")
    miniMapFrame.Name = "MiniMap"
    miniMapFrame.Size = UDim2.new(0, MINIMAP_SIZE, 0, MINIMAP_SIZE)
    miniMapFrame.Position = UDim2.new(1, -(MINIMAP_SIZE + 15), 0, 15)
    miniMapFrame.BackgroundColor3 = Color3.fromRGB(30, 45, 25)
    miniMapFrame.BorderSizePixel = 0
    miniMapFrame.ClipsDescendants = true
    miniMapFrame.Parent = screenGui

    local miniMapCorner = Instance.new("UICorner")
    miniMapCorner.CornerRadius = UDim.new(0, 8)
    miniMapCorner.Parent = miniMapFrame

    local miniMapStroke = Instance.new("UIStroke")
    miniMapStroke.Color = Color3.fromRGB(80, 100, 60)
    miniMapStroke.Thickness = 2
    miniMapStroke.Parent = miniMapFrame

    -- Compass "N" indicator at top center
    local compassLabel = Instance.new("TextLabel")
    compassLabel.Name = "Compass"
    compassLabel.Size = UDim2.new(0, 16, 0, 14)
    compassLabel.Position = UDim2.new(0.5, -8, 0, 2)
    compassLabel.BackgroundTransparency = 1
    compassLabel.Text = "N"
    compassLabel.TextColor3 = Color3.fromRGB(200, 200, 180)
    compassLabel.TextSize = 10
    compassLabel.Font = Enum.Font.GothamBold
    compassLabel.ZIndex = 5
    compassLabel.Parent = miniMapFrame

    -- Player position indicator (always centered)
    local playerDot = Instance.new("Frame")
    playerDot.Name = "PlayerDot"
    playerDot.Size = UDim2.new(0, 8, 0, 8)
    playerDot.Position = UDim2.new(0.5, -4, 0.5, -4)
    playerDot.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
    playerDot.ZIndex = 6
    playerDot.Parent = miniMapFrame

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = playerDot

    -- Player dot glow ring
    local dotGlow = Instance.new("Frame")
    dotGlow.Name = "DotGlow"
    dotGlow.Size = UDim2.new(0, 14, 0, 14)
    dotGlow.Position = UDim2.new(0.5, -7, 0.5, -7)
    dotGlow.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
    dotGlow.BackgroundTransparency = 0.7
    dotGlow.ZIndex = 5
    dotGlow.Parent = miniMapFrame

    local glowCorner = Instance.new("UICorner")
    glowCorner.CornerRadius = UDim.new(1, 0)
    glowCorner.Parent = dotGlow

    -- Zone label at bottom
    local zoneLabel = Instance.new("TextLabel")
    zoneLabel.Name = "ZoneLabel"
    zoneLabel.Size = UDim2.new(1, 0, 0, 16)
    zoneLabel.Position = UDim2.new(0, 0, 1, -34)
    zoneLabel.BackgroundTransparency = 1
    zoneLabel.Text = "Safe Zone"
    zoneLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
    zoneLabel.TextSize = 9
    zoneLabel.Font = Enum.Font.GothamBold
    zoneLabel.ZIndex = 5
    zoneLabel.Parent = miniMapFrame

    _zoneLabel = zoneLabel

    -- Nearby count label
    local nearbyLabel = Instance.new("TextLabel")
    nearbyLabel.Name = "NearbyCount"
    nearbyLabel.Size = UDim2.new(1, 0, 0, 16)
    nearbyLabel.Position = UDim2.new(0, 0, 1, -18)
    nearbyLabel.BackgroundTransparency = 1
    nearbyLabel.Text = "0 players nearby"
    nearbyLabel.TextColor3 = Color3.fromRGB(120, 150, 100)
    nearbyLabel.TextSize = 9
    nearbyLabel.Font = Enum.Font.Gotham
    nearbyLabel.ZIndex = 5
    nearbyLabel.Parent = miniMapFrame

    _miniMapFrame = miniMapFrame

    -- Shield timer display (below mini-map, top-right area)
    local shieldFrame = Instance.new("Frame")
    shieldFrame.Name = "ShieldDisplay"
    shieldFrame.Size = UDim2.new(0, MINIMAP_SIZE, 0, 60)
    shieldFrame.Position = UDim2.new(1, -(MINIMAP_SIZE + 15), 0, MINIMAP_SIZE + 25)
    shieldFrame.BackgroundColor3 = Color3.fromRGB(20, 40, 60)
    shieldFrame.BorderSizePixel = 0
    shieldFrame.Visible = false
    shieldFrame.Parent = screenGui

    local shieldCorner = Instance.new("UICorner")
    shieldCorner.CornerRadius = UDim.new(0, 8)
    shieldCorner.Parent = shieldFrame

    local shieldStroke = Instance.new("UIStroke")
    shieldStroke.Name = "ShieldStroke"
    shieldStroke.Color = Color3.fromRGB(60, 150, 220)
    shieldStroke.Thickness = 2
    shieldStroke.Parent = shieldFrame

    -- Shield icon/label
    local shieldIconLabel = Instance.new("TextLabel")
    shieldIconLabel.Name = "ShieldIcon"
    shieldIconLabel.Size = UDim2.new(0, 30, 0, 30)
    shieldIconLabel.Position = UDim2.new(0, 8, 0, 5)
    shieldIconLabel.BackgroundTransparency = 1
    shieldIconLabel.Text = "SHIELD"
    shieldIconLabel.TextColor3 = Color3.fromRGB(80, 180, 255)
    shieldIconLabel.TextSize = 8
    shieldIconLabel.Font = Enum.Font.GothamBold
    shieldIconLabel.Parent = shieldFrame

    -- Shield timer label
    local shieldTimerLabel = Instance.new("TextLabel")
    shieldTimerLabel.Name = "TimerLabel"
    shieldTimerLabel.Size = UDim2.new(1, -45, 0, 22)
    shieldTimerLabel.Position = UDim2.new(0, 40, 0, 6)
    shieldTimerLabel.BackgroundTransparency = 1
    shieldTimerLabel.Text = "Shield: --:--"
    shieldTimerLabel.TextColor3 = Color3.fromRGB(80, 200, 255)
    shieldTimerLabel.TextSize = 14
    shieldTimerLabel.Font = Enum.Font.GothamBold
    shieldTimerLabel.TextXAlignment = Enum.TextXAlignment.Left
    shieldTimerLabel.Parent = shieldFrame

    _shieldTimerLabel = shieldTimerLabel

    -- Shield warning text
    local shieldWarningLabel = Instance.new("TextLabel")
    shieldWarningLabel.Name = "WarningLabel"
    shieldWarningLabel.Size = UDim2.new(1, -12, 0, 18)
    shieldWarningLabel.Position = UDim2.new(0, 6, 0, 34)
    shieldWarningLabel.BackgroundTransparency = 1
    shieldWarningLabel.Text = "Attacking breaks your shield!"
    shieldWarningLabel.TextColor3 = Color3.fromRGB(200, 180, 140)
    shieldWarningLabel.TextSize = 9
    shieldWarningLabel.Font = Enum.Font.Gotham
    shieldWarningLabel.TextXAlignment = Enum.TextXAlignment.Center
    shieldWarningLabel.Parent = shieldFrame

    _shieldWarningLabel = shieldWarningLabel
    _shieldFrame = shieldFrame

    -- Go to City button (bottom center)
    local goToCityButton = Instance.new("TextButton")
    goToCityButton.Name = "GoToCityButton"
    goToCityButton.Size = UDim2.new(0, 200, 0, 50)
    goToCityButton.Position = UDim2.new(0.5, -100, 1, -70)
    goToCityButton.BackgroundColor3 = Color3.fromRGB(80, 60, 40)
    goToCityButton.BorderSizePixel = 0
    goToCityButton.Text = "Go to City"
    goToCityButton.TextColor3 = Color3.fromRGB(255, 230, 180)
    goToCityButton.TextSize = 22
    goToCityButton.Font = Enum.Font.GothamBold
    goToCityButton.Parent = screenGui

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 10)
    buttonCorner.Parent = goToCityButton

    local buttonStroke = Instance.new("UIStroke")
    buttonStroke.Color = Color3.fromRGB(139, 100, 60)
    buttonStroke.Thickness = 3
    buttonStroke.Parent = goToCityButton

    -- Hover effect
    goToCityButton.MouseEnter:Connect(function()
        TweenService:Create(goToCityButton, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(100, 80, 50)
        }):Play()
    end)

    goToCityButton.MouseLeave:Connect(function()
        TweenService:Create(goToCityButton, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(80, 60, 40)
        }):Play()
    end)

    -- Click handler
    goToCityButton.MouseButton1Click:Connect(function()
        OverworldHUD.GoToCityClicked:Fire()
    end)

    _goToCityButton = goToCityButton

    -- Find Battle button (bottom center, to the right of Go to City)
    local findBattleButton = Instance.new("TextButton")
    findBattleButton.Name = "FindBattleButton"
    findBattleButton.Size = UDim2.new(0, 160, 0, 50)
    findBattleButton.Position = UDim2.new(0.5, 110, 1, -70)
    findBattleButton.BackgroundColor3 = Color3.fromRGB(140, 50, 50)
    findBattleButton.BorderSizePixel = 0
    findBattleButton.Text = "Find Battle"
    findBattleButton.TextColor3 = Color3.fromRGB(255, 230, 200)
    findBattleButton.TextSize = 20
    findBattleButton.Font = Enum.Font.GothamBold
    findBattleButton.Parent = screenGui

    local fbCorner = Instance.new("UICorner")
    fbCorner.CornerRadius = UDim.new(0, 10)
    fbCorner.Parent = findBattleButton

    local fbStroke = Instance.new("UIStroke")
    fbStroke.Color = Color3.fromRGB(180, 80, 60)
    fbStroke.Thickness = 3
    fbStroke.Parent = findBattleButton

    -- Hover effect
    findBattleButton.MouseEnter:Connect(function()
        TweenService:Create(findBattleButton, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(170, 65, 65)
        }):Play()
    end)

    findBattleButton.MouseLeave:Connect(function()
        TweenService:Create(findBattleButton, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(140, 50, 50)
        }):Play()
    end)

    -- Click handler
    findBattleButton.MouseButton1Click:Connect(function()
        OverworldHUD.FindBattleClicked:Fire()
    end)

    _findBattleButton = findBattleButton

    -- Defense Log button (bottom center, to the left of Go to City)
    local defenseLogButton = Instance.new("TextButton")
    defenseLogButton.Name = "DefenseLogButton"
    defenseLogButton.Size = UDim2.new(0, 160, 0, 50)
    defenseLogButton.Position = UDim2.new(0.5, -270, 1, -70)
    defenseLogButton.BackgroundColor3 = Color3.fromRGB(100, 40, 40)
    defenseLogButton.BorderSizePixel = 0
    defenseLogButton.Text = "Defense Log"
    defenseLogButton.TextColor3 = Color3.fromRGB(255, 220, 200)
    defenseLogButton.TextSize = 20
    defenseLogButton.Font = Enum.Font.GothamBold
    defenseLogButton.Parent = screenGui

    local dlCorner = Instance.new("UICorner")
    dlCorner.CornerRadius = UDim.new(0, 10)
    dlCorner.Parent = defenseLogButton

    local dlStroke = Instance.new("UIStroke")
    dlStroke.Color = Color3.fromRGB(160, 60, 60)
    dlStroke.Thickness = 3
    dlStroke.Parent = defenseLogButton

    -- Hover effect
    defenseLogButton.MouseEnter:Connect(function()
        TweenService:Create(defenseLogButton, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(130, 55, 55)
        }):Play()
    end)

    defenseLogButton.MouseLeave:Connect(function()
        TweenService:Create(defenseLogButton, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(100, 40, 40)
        }):Play()
    end)

    -- Click handler
    defenseLogButton.MouseButton1Click:Connect(function()
        OverworldHUD.DefenseLogClicked:Fire()
    end)

    _defenseLogButton = defenseLogButton

    -- Loading screen (for teleports)
    local loadingFrame = Instance.new("Frame")
    loadingFrame.Name = "LoadingScreen"
    loadingFrame.Size = UDim2.new(1, 0, 1, 0)
    loadingFrame.BackgroundColor3 = Color3.fromRGB(15, 12, 10)
    loadingFrame.BackgroundTransparency = 0
    loadingFrame.Visible = false
    loadingFrame.ZIndex = 100
    loadingFrame.Parent = screenGui

    local loadingLabel = Instance.new("TextLabel")
    loadingLabel.Name = "LoadingText"
    loadingLabel.Size = UDim2.new(1, 0, 0, 50)
    loadingLabel.Position = UDim2.new(0, 0, 0.5, -25)
    loadingLabel.BackgroundTransparency = 1
    loadingLabel.Text = "Teleporting..."
    loadingLabel.TextColor3 = Color3.fromRGB(200, 180, 140)
    loadingLabel.TextSize = 28
    loadingLabel.Font = Enum.Font.GothamBold
    loadingLabel.Parent = loadingFrame

    -- Loading spinner
    local spinner = Instance.new("Frame")
    spinner.Name = "Spinner"
    spinner.Size = UDim2.new(0, 40, 0, 40)
    spinner.Position = UDim2.new(0.5, -20, 0.5, 40)
    spinner.BackgroundColor3 = Color3.fromRGB(200, 180, 140)
    spinner.Parent = loadingFrame

    local spinnerCorner = Instance.new("UICorner")
    spinnerCorner.CornerRadius = UDim.new(1, 0)
    spinnerCorner.Parent = spinner

    _loadingFrame = loadingFrame

    -- Error notification
    local errorFrame = Instance.new("Frame")
    errorFrame.Name = "ErrorNotification"
    errorFrame.Size = UDim2.new(0, 300, 0, 50)
    errorFrame.Position = UDim2.new(0.5, -150, 0, -60)
    errorFrame.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
    errorFrame.Visible = false
    errorFrame.Parent = screenGui

    local errorCorner = Instance.new("UICorner")
    errorCorner.CornerRadius = UDim.new(0, 8)
    errorCorner.Parent = errorFrame

    local errorLabel = Instance.new("TextLabel")
    errorLabel.Name = "ErrorText"
    errorLabel.Size = UDim2.new(1, -20, 1, 0)
    errorLabel.Position = UDim2.new(0, 10, 0, 0)
    errorLabel.BackgroundTransparency = 1
    errorLabel.Text = "Error message"
    errorLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    errorLabel.TextSize = 14
    errorLabel.Font = Enum.Font.GothamBold
    errorLabel.TextXAlignment = Enum.TextXAlignment.Left
    errorLabel.Parent = errorFrame

    _errorFrame = errorFrame

    return screenGui
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Initializes the OverworldHUD.
]]
function OverworldHUD:Init()
    if _initialized then
        warn("[OverworldHUD] Already initialized")
        return
    end

    _playerGui = _player:WaitForChild("PlayerGui") :: PlayerGui

    -- Create UI
    _screenGui = createHUD()
    _screenGui.Parent = _playerGui

    _initialized = true
    print("[OverworldHUD] Initialized")
end

--[[
    Updates the resource display.

    @param resources table - Resource values {gold, wood, food}
]]
function OverworldHUD:UpdateResources(resources: {gold: number, wood: number, food: number})
    if not _resourcesFrame then return end

    local gold = resources.gold or 0
    local wood = resources.wood or 0
    local food = resources.food or 0

    local goldBar = _resourcesFrame:FindFirstChild("GoldBar") :: Frame?
    if goldBar then
        local value = goldBar:FindFirstChild("Value") :: TextLabel?
        if value then
            value.Text = tostring(gold)
        end
    end

    local woodBar = _resourcesFrame:FindFirstChild("WoodBar") :: Frame?
    if woodBar then
        local value = woodBar:FindFirstChild("Value") :: TextLabel?
        if value then
            value.Text = tostring(wood)
        end
    end

    local foodBar = _resourcesFrame:FindFirstChild("FoodBar") :: Frame?
    if foodBar then
        local value = foodBar:FindFirstChild("Value") :: TextLabel?
        if value then
            value.Text = tostring(food)
        end
    end

    -- Update raid risk indicator
    if _riskLabel then
        local exposedGold = math.floor(gold * LOOT_AVAILABLE_PERCENT)
        local exposedWood = math.floor(wood * LOOT_AVAILABLE_PERCENT)
        local exposedFood = math.floor(food * LOOT_AVAILABLE_PERCENT)

        if exposedGold > 0 or exposedWood > 0 or exposedFood > 0 then
            _riskLabel.Text = string.format(
                "At risk: %sg  %sw  %sf",
                formatNumber(exposedGold),
                formatNumber(exposedWood),
                formatNumber(exposedFood)
            )
        else
            _riskLabel.Text = ""
        end
    end
end

--[[
    Updates the mini-map player position (center-on-player view).
    Player dot stays at center; base dots shift relative to player.

    @param position Vector3 - World position
]]
function OverworldHUD:UpdatePlayerPosition(position: Vector3)
    if not _miniMapFrame then return end

    _playerWorldPos = position

    -- Player dot always stays at center (set in createHUD)
    -- Refresh base dot positions since player moved
    refreshBaseDotPositions()
end

--[[
    Updates the minimap with nearby base data.

    @param nearbyBases table - Array of base data from server
    @param ownBasePosition Vector3? - Player's own base position
]]
function OverworldHUD:UpdateMinimapBases(nearbyBases: {any}, ownBasePosition: Vector3?)
    _basesData = nearbyBases or {}
    if ownBasePosition then
        _ownBasePosition = ownBasePosition
    end
    refreshBaseDotPositions()
end

--[[
    Sets the player's own base position for the "home" dot.

    @param position Vector3 - Base world position
]]
function OverworldHUD:SetOwnBasePosition(position: Vector3)
    _ownBasePosition = position
    refreshBaseDotPositions()
end

--[[
    Updates the nearby player count.

    @param count number - Number of nearby players
]]
function OverworldHUD:UpdateNearbyCount(count: number)
    if not _miniMapFrame then return end

    local nearbyLabel = _miniMapFrame:FindFirstChild("NearbyCount") :: TextLabel?
    if nearbyLabel then
        nearbyLabel.Text = string.format("%d player%s nearby", count, count == 1 and "" or "s")
    end
end

--[[
    Shows the teleport loading screen.

    @param destination string - Where teleporting to
]]
function OverworldHUD:ShowTeleportLoading(destination: string)
    if not _loadingFrame then return end

    local loadingText = _loadingFrame:FindFirstChild("LoadingText") :: TextLabel?
    if loadingText then
        loadingText.Text = string.format("Teleporting to %s...", destination)
    end

    _loadingFrame.Visible = true
    _loadingFrame.BackgroundTransparency = 1

    -- Fade in
    local tween = TweenService:Create(
        _loadingFrame,
        TweenInfo.new(0.5),
        {BackgroundTransparency = 0}
    )
    tween:Play()

    -- Animate spinner
    local spinner = _loadingFrame:FindFirstChild("Spinner") :: Frame?
    if spinner then
        task.spawn(function()
            while _loadingFrame and _loadingFrame.Visible do
                local rotateTween = TweenService:Create(
                    spinner,
                    TweenInfo.new(1, Enum.EasingStyle.Linear),
                    {Rotation = spinner.Rotation + 360}
                )
                rotateTween:Play()
                task.wait(1)
            end
        end)
    end
end

--[[
    Hides the teleport loading screen.
]]
function OverworldHUD:HideTeleportLoading()
    if not _loadingFrame then return end

    local tween = TweenService:Create(
        _loadingFrame,
        TweenInfo.new(0.3),
        {BackgroundTransparency = 1}
    )
    tween:Play()
    tween.Completed:Connect(function()
        _loadingFrame.Visible = false
    end)
end

--[[
    Shows an error message.

    @param message string - Error message to display
]]
function OverworldHUD:ShowError(message: string)
    if not _errorFrame then return end

    local errorText = _errorFrame:FindFirstChild("ErrorText") :: TextLabel?
    if errorText then
        errorText.Text = message
    end

    -- Show and animate
    _errorFrame.Position = UDim2.new(0.5, -150, 0, -60)
    _errorFrame.Visible = true

    local slideIn = TweenService:Create(
        _errorFrame,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, -150, 0, 20)}
    )
    slideIn:Play()

    -- Auto-hide after 3 seconds
    task.delay(3, function()
        if not _errorFrame then return end

        local slideOut = TweenService:Create(
            _errorFrame,
            TweenInfo.new(0.2),
            {Position = UDim2.new(0.5, -150, 0, -60)}
        )
        slideOut:Play()
        slideOut.Completed:Connect(function()
            _errorFrame.Visible = false
        end)
    end)
end

--[[
    Formats seconds into a human-readable time string.
    e.g., 28920 -> "8h 02m", 540 -> "9m 00s"
]]
local function formatShieldTime(seconds: number): string
    if seconds <= 0 then
        return "0s"
    end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)

    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm %02ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

--[[
    Updates the shield timer display.

    @param shieldData table - Shield status data
        { active: boolean, expiresAt: number?, remainingSeconds: number? }
    If active is false or remainingSeconds <= 0, hides the shield display.
]]
function OverworldHUD:UpdateShield(shieldData: {active: boolean, expiresAt: number?, remainingSeconds: number?})
    if not _shieldFrame then return end

    if not shieldData or not shieldData.active then
        _shieldFrame.Visible = false
        _shieldPulseActive = false
        return
    end

    -- Calculate remaining time
    local remaining = shieldData.remainingSeconds or 0
    if shieldData.expiresAt then
        remaining = math.max(0, shieldData.expiresAt - os.time())
    end

    if remaining <= 0 then
        _shieldFrame.Visible = false
        _shieldPulseActive = false
        return
    end

    _shieldFrame.Visible = true

    -- Update timer text
    if _shieldTimerLabel then
        _shieldTimerLabel.Text = "Shield: " .. formatShieldTime(remaining)
    end

    -- Apply color based on remaining time
    local timerColor: Color3
    local strokeColor: Color3
    local bgColor: Color3

    if remaining < 600 then
        -- Less than 10 minutes: red + pulse
        timerColor = Color3.fromRGB(255, 80, 60)
        strokeColor = Color3.fromRGB(220, 60, 40)
        bgColor = Color3.fromRGB(50, 20, 20)

        -- Start pulse effect if not already running
        if not _shieldPulseActive then
            _shieldPulseActive = true
            task.spawn(function()
                while _shieldPulseActive and _shieldFrame and _shieldFrame.Visible do
                    -- Pulse to bright
                    local pulseIn = TweenService:Create(
                        _shieldFrame,
                        TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                        {BackgroundTransparency = 0.3}
                    )
                    pulseIn:Play()
                    pulseIn.Completed:Wait()

                    if not _shieldPulseActive then break end

                    -- Pulse back
                    local pulseOut = TweenService:Create(
                        _shieldFrame,
                        TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                        {BackgroundTransparency = 0}
                    )
                    pulseOut:Play()
                    pulseOut.Completed:Wait()
                end
                -- Reset transparency when done pulsing
                if _shieldFrame then
                    _shieldFrame.BackgroundTransparency = 0
                end
            end)
        end
    elseif remaining < 3600 then
        -- Less than 1 hour: yellow/orange warning
        timerColor = Color3.fromRGB(255, 200, 50)
        strokeColor = Color3.fromRGB(200, 160, 40)
        bgColor = Color3.fromRGB(50, 40, 15)
        _shieldPulseActive = false
    else
        -- Normal: blue/cyan
        timerColor = Color3.fromRGB(80, 200, 255)
        strokeColor = Color3.fromRGB(60, 150, 220)
        bgColor = Color3.fromRGB(20, 40, 60)
        _shieldPulseActive = false
    end

    if _shieldTimerLabel then
        _shieldTimerLabel.TextColor3 = timerColor
    end

    _shieldFrame.BackgroundColor3 = bgColor

    local shieldStroke = _shieldFrame:FindFirstChild("ShieldStroke") :: UIStroke?
    if shieldStroke then
        shieldStroke.Color = strokeColor
    end

    local shieldIcon = _shieldFrame:FindFirstChild("ShieldIcon") :: TextLabel?
    if shieldIcon then
        shieldIcon.TextColor3 = timerColor
    end
end

--[[
    Hides the HUD.
]]
function OverworldHUD:Hide()
    if _screenGui then
        _screenGui.Enabled = false
    end
end

--[[
    Shows the HUD.
]]
function OverworldHUD:Show()
    if _screenGui then
        _screenGui.Enabled = true
    end
end

return OverworldHUD
