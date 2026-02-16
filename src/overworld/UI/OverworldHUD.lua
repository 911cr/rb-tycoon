--!strict
--[[
    OverworldHUD.lua

    Heads-up display for the overworld showing:
    - Mini-map (bird's eye view centered on player with base dots)
    - Player resources
    - Nearby player count
    - Teleport loading screen

    Uses the Components design system for fantasy-medieval themed styling.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local Components = require(script.Parent.Components)

local C = Components.Colors
local S = Components.Sizes

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
local _shieldStroke: UIStroke? = nil
local _shieldIconLabel: TextLabel? = nil
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
            _homeDot.BackgroundColor3 = Color3.new(1, 1, 1)
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
            _zoneLabel.TextColor3 = C.Success
        elseif zone == "forbidden" then
            _zoneLabel.Text = "Forbidden Zone"
            _zoneLabel.TextColor3 = C.Danger
        else
            _zoneLabel.Text = "Wilderness"
            _zoneLabel.TextColor3 = C.Warning
        end
    end
end

-- ============================================================================
-- UI CREATION
-- ============================================================================

--[[
    Creates the HUD UI using the Components design system.
]]
local function createHUD(): ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "OverworldHUD"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    -- ================================================================
    -- Resources panel (top-left) — ornate fantasy panel
    -- ================================================================
    local resourcesPanel = Components.CreateFrame({
        Name = "Resources",
        Size = UDim2.new(0, 160, 0, 170),
        Position = UDim2.new(0, 15, 0, 15),
        BackgroundColor = C.Panel,
        CornerRadius = S.CornerRadiusLarge,
        BorderColor = C.PanelBorder,
        Parent = screenGui,
    })

    -- Panel gradient for depth
    local resGradient = Instance.new("UIGradient")
    resGradient.Rotation = 90
    resGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.85, 0.85, 0.85)),
    })
    resGradient.Parent = resourcesPanel

    local resPadding = Instance.new("UIPadding")
    resPadding.PaddingTop = UDim.new(0, 8)
    resPadding.PaddingBottom = UDim.new(0, 8)
    resPadding.PaddingLeft = UDim.new(0, 8)
    resPadding.PaddingRight = UDim.new(0, 8)
    resPadding.Parent = resourcesPanel

    Components.CreateListLayout({
        Padding = UDim.new(0, 6),
        Parent = resourcesPanel,
    })

    -- Resource displays using Components design system
    Components.CreateResourceDisplay({
        ResourceType = "Gold",
        Size = UDim2.new(1, 0, 0, 38),
        Parent = resourcesPanel,
    })

    Components.CreateResourceDisplay({
        ResourceType = "Wood",
        Size = UDim2.new(1, 0, 0, 38),
        Parent = resourcesPanel,
    })

    Components.CreateResourceDisplay({
        ResourceType = "Food",
        Size = UDim2.new(1, 0, 0, 38),
        Parent = resourcesPanel,
    })

    -- Raid risk indicator
    local riskLabel = Components.CreateLabel({
        Name = "RiskIndicator",
        Text = "",
        Size = UDim2.new(1, 0, 0, 16),
        TextColor = C.Warning,
        TextSize = S.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = resourcesPanel,
    })
    riskLabel.TextTransparency = 0.2

    _riskLabel = riskLabel
    _resourcesFrame = resourcesPanel

    -- ================================================================
    -- Mini-map (top-right) — ornate framed bird's eye view
    -- ================================================================
    local miniMapFrame = Components.CreateFrame({
        Name = "MiniMap",
        Size = UDim2.new(0, MINIMAP_SIZE, 0, MINIMAP_SIZE),
        Position = UDim2.new(1, -(MINIMAP_SIZE + 15), 0, 15),
        BackgroundColor = Color3.fromRGB(30, 45, 25),
        CornerRadius = S.CornerRadius,
        BorderColor = C.GoldTrim,
        Parent = screenGui,
    })
    miniMapFrame.ClipsDescendants = true

    -- Compass "N" indicator at top center
    local compassLabel = Components.CreateLabel({
        Name = "Compass",
        Text = "N",
        Size = UDim2.new(0, 16, 0, 14),
        Position = UDim2.new(0.5, -8, 0, 2),
        TextColor = C.Parchment,
        TextSize = 10,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = miniMapFrame,
    })
    compassLabel.ZIndex = 5

    -- Player position indicator (always centered)
    local playerDot = Components.CreateFrame({
        Name = "PlayerDot",
        Size = UDim2.new(0, 8, 0, 8),
        Position = UDim2.new(0.5, -4, 0.5, -4),
        BackgroundColor = Color3.fromRGB(100, 200, 255),
        CornerRadius = UDim.new(1, 0),
        Parent = miniMapFrame,
    })
    playerDot.ZIndex = 6

    -- Player dot glow ring
    local dotGlow = Components.CreateFrame({
        Name = "DotGlow",
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(0.5, -7, 0.5, -7),
        BackgroundColor = Color3.fromRGB(100, 200, 255),
        CornerRadius = UDim.new(1, 0),
        Parent = miniMapFrame,
    })
    dotGlow.BackgroundTransparency = 0.7
    dotGlow.ZIndex = 5

    -- Zone label at bottom of minimap
    local zoneLabel = Components.CreateLabel({
        Name = "ZoneLabel",
        Text = "Safe Zone",
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.new(0, 0, 1, -34),
        TextColor = C.Success,
        TextSize = 9,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = miniMapFrame,
    })
    zoneLabel.ZIndex = 5
    _zoneLabel = zoneLabel

    -- Nearby count label
    local nearbyLabel = Components.CreateLabel({
        Name = "NearbyCount",
        Text = "0 players nearby",
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.new(0, 0, 1, -18),
        TextColor = C.TextMuted,
        TextSize = 9,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = miniMapFrame,
    })
    nearbyLabel.ZIndex = 5

    _miniMapFrame = miniMapFrame

    -- ================================================================
    -- Shield timer display (below minimap)
    -- ================================================================
    local shieldFrame = Components.CreateFrame({
        Name = "ShieldDisplay",
        Size = UDim2.new(0, MINIMAP_SIZE, 0, 60),
        Position = UDim2.new(1, -(MINIMAP_SIZE + 15), 0, MINIMAP_SIZE + 25),
        BackgroundColor = Color3.fromRGB(20, 40, 60),
        CornerRadius = S.CornerRadius,
        Parent = screenGui,
    })
    shieldFrame.Visible = false

    -- Shield stroke (stored for dynamic color changes)
    local shieldStroke = Instance.new("UIStroke")
    shieldStroke.Name = "ShieldStroke"
    shieldStroke.Color = Color3.fromRGB(60, 150, 220)
    shieldStroke.Thickness = 2
    shieldStroke.Parent = shieldFrame
    _shieldStroke = shieldStroke

    -- Shield icon/label
    local shieldIconLabel = Components.CreateLabel({
        Name = "ShieldIcon",
        Text = "SHIELD",
        Size = UDim2.new(0, 30, 0, 30),
        Position = UDim2.new(0, 8, 0, 5),
        TextColor = Color3.fromRGB(80, 180, 255),
        TextSize = 8,
        Font = Enum.Font.GothamBold,
        Parent = shieldFrame,
    })
    _shieldIconLabel = shieldIconLabel

    -- Shield timer label
    local shieldTimerLabel = Components.CreateLabel({
        Name = "TimerLabel",
        Text = "Shield: --:--",
        Size = UDim2.new(1, -45, 0, 22),
        Position = UDim2.new(0, 40, 0, 6),
        TextColor = Color3.fromRGB(80, 200, 255),
        TextSize = S.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = shieldFrame,
    })
    _shieldTimerLabel = shieldTimerLabel

    -- Shield warning text
    local shieldWarningLabel = Components.CreateLabel({
        Name = "WarningLabel",
        Text = "Attacking breaks your shield!",
        Size = UDim2.new(1, -12, 0, 18),
        Position = UDim2.new(0, 6, 0, 34),
        TextColor = C.TextSecondary,
        TextSize = 9,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = shieldFrame,
    })
    _shieldWarningLabel = shieldWarningLabel
    _shieldFrame = shieldFrame

    -- ================================================================
    -- Bottom action bar — ornate panel with centered buttons
    -- ================================================================
    local actionBar = Components.CreateFrame({
        Name = "ActionBar",
        Size = UDim2.new(0, 560, 0, 60),
        Position = UDim2.new(0.5, 0, 1, -15),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = C.Panel,
        CornerRadius = S.CornerRadiusLarge,
        BorderColor = C.PanelBorder,
        Parent = screenGui,
    })

    -- Action bar gradient for depth
    local actionGradient = Instance.new("UIGradient")
    actionGradient.Rotation = 90
    actionGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.85, 0.85, 0.85)),
    })
    actionGradient.Parent = actionBar

    local actionPadding = Instance.new("UIPadding")
    actionPadding.PaddingTop = UDim.new(0, 8)
    actionPadding.PaddingBottom = UDim.new(0, 8)
    actionPadding.PaddingLeft = UDim.new(0, 10)
    actionPadding.PaddingRight = UDim.new(0, 10)
    actionPadding.Parent = actionBar

    Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 12),
        Parent = actionBar,
    })

    -- Defense Log button
    local defenseLogButton = Components.CreateButton({
        Name = "DefenseLogButton",
        Text = "Defense Log",
        Size = UDim2.new(0, 160, 0, 44),
        Style = "danger",
        OnClick = function()
            OverworldHUD.DefenseLogClicked:Fire()
        end,
        Parent = actionBar,
    })
    defenseLogButton.LayoutOrder = 1
    _defenseLogButton = defenseLogButton

    -- Go to City button (prominent center)
    local goToCityButton = Components.CreateButton({
        Name = "GoToCityButton",
        Text = "Go to City",
        Size = UDim2.new(0, 190, 0, 44),
        Style = "wood",
        TextSize = S.FontSizeLarge,
        OnClick = function()
            OverworldHUD.GoToCityClicked:Fire()
        end,
        Parent = actionBar,
    })
    goToCityButton.LayoutOrder = 2
    _goToCityButton = goToCityButton

    -- Find Battle button
    local findBattleButton = Components.CreateButton({
        Name = "FindBattleButton",
        Text = "Find Battle",
        Size = UDim2.new(0, 160, 0, 44),
        Style = "danger",
        OnClick = function()
            OverworldHUD.FindBattleClicked:Fire()
        end,
        Parent = actionBar,
    })
    findBattleButton.LayoutOrder = 3
    _findBattleButton = findBattleButton

    -- ================================================================
    -- Loading screen (for teleports)
    -- ================================================================
    local loadingFrame = Instance.new("Frame")
    loadingFrame.Name = "LoadingScreen"
    loadingFrame.Size = UDim2.new(1, 0, 1, 0)
    loadingFrame.BackgroundColor3 = C.Background
    loadingFrame.BackgroundTransparency = 0
    loadingFrame.Visible = false
    loadingFrame.ZIndex = 100
    loadingFrame.Parent = screenGui

    Components.CreateLabel({
        Name = "LoadingText",
        Text = "Teleporting...",
        Size = UDim2.new(1, 0, 0, 50),
        Position = UDim2.new(0, 0, 0.5, -25),
        TextColor = C.TextGold,
        TextSize = S.FontSizeTitle,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = loadingFrame,
    })

    -- Loading spinner
    local spinner = Components.CreateFrame({
        Name = "Spinner",
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0.5, -20, 0.5, 40),
        BackgroundColor = C.GoldTrim,
        CornerRadius = UDim.new(1, 0),
        Parent = loadingFrame,
    })

    _loadingFrame = loadingFrame

    -- ================================================================
    -- Error notification
    -- ================================================================
    local errorFrame = Components.CreateFrame({
        Name = "ErrorNotification",
        Size = UDim2.new(0, 300, 0, 50),
        Position = UDim2.new(0.5, -150, 0, -60),
        BackgroundColor = C.Danger,
        CornerRadius = S.CornerRadius,
        BorderColor = Color3.fromRGB(140, 50, 50),
        Parent = screenGui,
    })
    errorFrame.Visible = false

    Components.CreateLabel({
        Name = "ErrorText",
        Text = "Error message",
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        TextColor = C.TextPrimary,
        TextSize = S.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = errorFrame,
    })

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

    -- Components.CreateResourceDisplay names: "GoldDisplay" > "Amount"
    local goldDisplay = _resourcesFrame:FindFirstChild("GoldDisplay") :: Frame?
    if goldDisplay then
        local amount = goldDisplay:FindFirstChild("Amount") :: TextLabel?
        if amount then
            amount.Text = formatNumber(gold)
        end
    end

    local woodDisplay = _resourcesFrame:FindFirstChild("WoodDisplay") :: Frame?
    if woodDisplay then
        local amount = woodDisplay:FindFirstChild("Amount") :: TextLabel?
        if amount then
            amount.Text = formatNumber(wood)
        end
    end

    local foodDisplay = _resourcesFrame:FindFirstChild("FoodDisplay") :: Frame?
    if foodDisplay then
        local amount = foodDisplay:FindFirstChild("Amount") :: TextLabel?
        if amount then
            amount.Text = formatNumber(food)
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

    if _shieldStroke then
        _shieldStroke.Color = strokeColor
    end

    if _shieldIconLabel then
        _shieldIconLabel.TextColor3 = timerColor
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
