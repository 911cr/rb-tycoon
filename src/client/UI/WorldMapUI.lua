--!strict
--[[
    WorldMapUI.lua

    World map interface for Battle Tycoon: Conquest.
    Displays a visual map with player bases, handles opponent selection,
    base relocation, and travel time for attacks.

    Features:
    - Visual 2D map with base markers
    - Distance-based color coding (Easy/Medium/Hard)
    - Base relocation with 24h cooldown
    - Travel time preview before attacks
    - Friend base highlighting
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local WorldMapData = require(ReplicatedStorage.Shared.Constants.WorldMapData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local WorldMapUI = {}
WorldMapUI.__index = WorldMapUI

-- Events
WorldMapUI.Closed = Signal.new()
WorldMapUI.AttackRequested = Signal.new()
WorldMapUI.NextOpponentRequested = Signal.new()
WorldMapUI.BaseRelocated = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _mainContainer: Frame
local _mapViewport: Frame
local _opponentCard: Frame
local _relocatePanel: Frame
local _travelPanel: Frame
local _isVisible = false
local _initialized = false
local _currentOpponent: any = nil
local _searchCost = 0
local _mapPlayers: {any} = {}
local _baseMarkers: {[number]: Frame} = {}
local _playerPosition: {x: number, z: number}? = nil
local _isRelocateMode = false
local _selectedPosition: {x: number, z: number}? = nil

-- View state
local _viewMode = "map" -- "map" | "opponent" | "relocate"

-- UI References
local _opponentNameLabel: TextLabel
local _opponentTrophyLabel: TextLabel
local _goldLabel: TextLabel
local _woodLabel: TextLabel
local _foodLabel: TextLabel
local _thLevelLabel: TextLabel
local _distanceLabel: TextLabel
local _travelTimeLabel: TextLabel
local _difficultyLabel: TextLabel
local _relocateCostLabel: TextLabel
local _relocateCooldownLabel: TextLabel
local _mapContainer: Frame

-- Map scale (map units to screen pixels)
local MAP_SCALE = 0.5 -- 1 map unit = 0.5 pixels
local MAP_SIZE = Vector2.new(500, 500)

--[[
    Formats a number for display.
]]
local function formatNumber(value: number): string
    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fK", value / 1000)
    else
        return tostring(math.floor(value))
    end
end

--[[
    Formats time in seconds to readable string.
]]
local function formatTime(seconds: number): string
    if seconds <= 0 then
        return "Instant"
    elseif seconds < 60 then
        return string.format("%ds", math.floor(seconds))
    elseif seconds < 3600 then
        local mins = math.floor(seconds / 60)
        local secs = math.floor(seconds % 60)
        return string.format("%dm %ds", mins, secs)
    else
        local hours = math.floor(seconds / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, mins)
    end
end

--[[
    Converts map position to screen position.
]]
local function mapToScreen(mapPos: {x: number, z: number}): Vector2
    local mapConfig = WorldMapData.Map
    local screenX = (mapPos.x / mapConfig.Width) * MAP_SIZE.X
    local screenY = (mapPos.z / mapConfig.Height) * MAP_SIZE.Y
    return Vector2.new(screenX, screenY)
end

--[[
    Converts screen position to map position.
]]
local function screenToMap(screenPos: Vector2): {x: number, z: number}
    local mapConfig = WorldMapData.Map
    return {
        x = (screenPos.X / MAP_SIZE.X) * mapConfig.Width,
        z = (screenPos.Y / MAP_SIZE.Y) * mapConfig.Height,
    }
end

--[[
    Creates a base marker on the map.
]]
local function createBaseMarker(playerInfo: any, isPlayer: boolean): Frame
    local screenPos = mapToScreen(playerInfo.position)

    local markerSize = isPlayer and 24 or 18
    local markerColor = Components.Colors.Secondary

    if isPlayer then
        markerColor = Components.Colors.Primary
    elseif playerInfo.isFriend then
        markerColor = WorldMapData.Friends.HighlightColor
    elseif playerInfo.isShielded then
        markerColor = Components.Colors.TextMuted
    else
        -- Use difficulty color
        if _playerPosition then
            local playerData = ClientAPI:GetPlayerData()
            if playerData then
                markerColor = WorldMapData.GetDifficultyColor(
                    playerData.townHallLevel or 1,
                    playerData.trophies and playerData.trophies.current or 0,
                    playerInfo.townHallLevel or 1,
                    playerInfo.trophies or 0
                )
            end
        end
    end

    local marker = Components.CreateFrame({
        Name = "Marker_" .. tostring(playerInfo.userId),
        Size = UDim2.new(0, markerSize, 0, markerSize),
        Position = UDim2.new(0, screenPos.X, 0, screenPos.Y),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor = markerColor,
        CornerRadius = UDim.new(0.5, 0),
        BorderColor = isPlayer and Components.Colors.GoldTrim or nil,
        Parent = _mapContainer,
    })

    -- Castle icon placeholder
    local iconLabel = Components.CreateLabel({
        Name = "Icon",
        Text = isPlayer and "H" or (playerInfo.isFriend and "F" or ""),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = isPlayer and 14 or 10,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = marker,
    })

    -- Shield indicator
    if playerInfo.isShielded then
        local shield = Components.CreateFrame({
            Name = "Shield",
            Size = UDim2.new(1, 6, 1, 6),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 0.5,
            BackgroundColor = Components.Colors.TextMuted,
            CornerRadius = UDim.new(0.5, 0),
            Parent = marker,
        })
        shield.ZIndex = marker.ZIndex - 1
    end

    -- Click handler for non-player markers
    if not isPlayer then
        local button = Instance.new("TextButton")
        button.Name = "ClickArea"
        button.Size = UDim2.new(1, 10, 1, 10)
        button.Position = UDim2.new(0.5, 0, 0.5, 0)
        button.AnchorPoint = Vector2.new(0.5, 0.5)
        button.BackgroundTransparency = 1
        button.Text = ""
        button.Parent = marker

        button.MouseButton1Click:Connect(function()
            if not playerInfo.isShielded then
                WorldMapUI:SelectOpponent(playerInfo)
            end
        end)

        -- Hover effect
        button.MouseEnter:Connect(function()
            TweenService:Create(marker, TweenInfo.new(0.1), {
                Size = UDim2.new(0, markerSize + 4, 0, markerSize + 4)
            }):Play()
        end)

        button.MouseLeave:Connect(function()
            TweenService:Create(marker, TweenInfo.new(0.1), {
                Size = UDim2.new(0, markerSize, 0, markerSize)
            }):Play()
        end)
    end

    return marker
end

--[[
    Refreshes base markers on the map.
]]
local function refreshMapMarkers()
    -- Clear existing markers
    for _, marker in _baseMarkers do
        marker:Destroy()
    end
    _baseMarkers = {}

    -- Add player marker
    if _playerPosition then
        local playerData = ClientAPI:GetPlayerData()
        if playerData then
            local playerMarker = createBaseMarker({
                userId = _player.UserId,
                username = _player.Name,
                position = _playerPosition,
                trophies = playerData.trophies and playerData.trophies.current or 0,
                townHallLevel = playerData.townHallLevel or 1,
                isShielded = false,
                isFriend = false,
            }, true)
            _baseMarkers[_player.UserId] = playerMarker
        end
    end

    -- Add other player markers
    for _, playerInfo in _mapPlayers do
        if playerInfo.userId ~= _player.UserId then
            local marker = createBaseMarker(playerInfo, false)
            _baseMarkers[playerInfo.userId] = marker
        end
    end
end

--[[
    Creates a loot display row.
]]
local function createLootRow(resourceType: string, color: Color3, parent: GuiObject): Frame
    local row = Components.CreateFrame({
        Name = resourceType .. "Row",
        Size = UDim2.new(0.33, -8, 0, 40),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = parent,
    })

    -- Icon
    local iconBg = Components.CreateFrame({
        Name = "Icon",
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(0, 6, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = color,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = row,
    })

    local iconLabel = Components.CreateLabel({
        Name = "IconText",
        Text = string.sub(resourceType, 1, 1),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Amount
    local amountLabel = Components.CreateLabel({
        Name = "Amount",
        Text = "0",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 38, 0, 0),
        TextColor = color,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    return row
end

--[[
    Creates the map viewport.
]]
local function createMapView(parent: Frame): Frame
    local mapFrame = Components.CreateFrame({
        Name = "MapView",
        Size = UDim2.new(1, -32, 0, MAP_SIZE.Y),
        Position = UDim2.new(0.5, 0, 0, 60),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Color3.fromRGB(40, 60, 40), -- Dark green terrain
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = Components.Colors.GoldTrim,
        Parent = parent,
    })

    -- Grid overlay
    local gridSize = 50
    for i = 1, math.floor(MAP_SIZE.X / gridSize) - 1 do
        local vLine = Instance.new("Frame")
        vLine.Name = "VLine_" .. i
        vLine.Size = UDim2.new(0, 1, 1, 0)
        vLine.Position = UDim2.new(0, i * gridSize, 0, 0)
        vLine.BackgroundColor3 = Color3.new(0.3, 0.4, 0.3)
        vLine.BackgroundTransparency = 0.7
        vLine.BorderSizePixel = 0
        vLine.Parent = mapFrame
    end

    for i = 1, math.floor(MAP_SIZE.Y / gridSize) - 1 do
        local hLine = Instance.new("Frame")
        hLine.Name = "HLine_" .. i
        hLine.Size = UDim2.new(1, 0, 0, 1)
        hLine.Position = UDim2.new(0, 0, 0, i * gridSize)
        hLine.BackgroundColor3 = Color3.new(0.3, 0.4, 0.3)
        hLine.BackgroundTransparency = 0.7
        hLine.BorderSizePixel = 0
        hLine.Parent = mapFrame
    end

    -- Map container for markers
    _mapContainer = Components.CreateFrame({
        Name = "Markers",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Parent = mapFrame,
    })

    -- Click handler for relocation
    local clickArea = Instance.new("TextButton")
    clickArea.Name = "ClickArea"
    clickArea.Size = UDim2.new(1, 0, 1, 0)
    clickArea.BackgroundTransparency = 1
    clickArea.Text = ""
    clickArea.ZIndex = 0
    clickArea.Parent = mapFrame

    clickArea.MouseButton1Click:Connect(function(x, y)
        if _isRelocateMode then
            local absolutePos = mapFrame.AbsolutePosition
            local relativeX = x - absolutePos.X
            local relativeY = y - absolutePos.Y
            _selectedPosition = screenToMap(Vector2.new(relativeX, relativeY))
            WorldMapUI:ShowRelocationConfirm()
        end
    end)

    return mapFrame
end

--[[
    Creates the opponent info card.
]]
local function createOpponentCard(parent: Frame): Frame
    local card = Components.CreateFrame({
        Name = "OpponentCard",
        Size = UDim2.new(1, -32, 0, 240),
        Position = UDim2.new(0.5, 0, 1, -16),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = Components.Colors.Panel,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        BorderColor = Components.Colors.PanelBorder,
        Parent = parent,
    })
    card.Visible = false

    -- Opponent header
    local header = Components.CreateFrame({
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundTransparency = 1,
        Parent = card,
    })

    -- Avatar placeholder
    local avatar = Components.CreateFrame({
        Name = "Avatar",
        Size = UDim2.new(0, 42, 0, 42),
        Position = UDim2.new(0, 12, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = Components.Colors.Primary,
        CornerRadius = UDim.new(0.5, 0),
        Parent = header,
    })

    local avatarLabel = Components.CreateLabel({
        Name = "Initial",
        Text = "?",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = avatar,
    })

    -- Name
    _opponentNameLabel = Components.CreateLabel({
        Name = "Name",
        Text = "Select Target",
        Size = UDim2.new(0.5, -60, 0, 22),
        Position = UDim2.new(0, 62, 0, 8),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        Parent = header,
    })

    -- Trophies
    _opponentTrophyLabel = Components.CreateLabel({
        Name = "Trophies",
        Text = "",
        Size = UDim2.new(0.5, -60, 0, 16),
        Position = UDim2.new(0, 62, 0, 30),
        TextColor = Components.Colors.Warning,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = header,
    })

    -- Town Hall level
    _thLevelLabel = Components.CreateLabel({
        Name = "THLevel",
        Text = "",
        Size = UDim2.new(0, 50, 0, 24),
        Position = UDim2.new(1, -12, 0, 8),
        AnchorPoint = Vector2.new(1, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = header,
    })

    -- Difficulty
    _difficultyLabel = Components.CreateLabel({
        Name = "Difficulty",
        Text = "",
        Size = UDim2.new(0, 60, 0, 16),
        Position = UDim2.new(1, -12, 0, 32),
        AnchorPoint = Vector2.new(1, 0),
        TextColor = Components.Colors.Success,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = header,
    })

    -- Loot section
    local lootLabel = Components.CreateLabel({
        Name = "LootLabel",
        Text = "Available Loot",
        Size = UDim2.new(1, -24, 0, 16),
        Position = UDim2.new(0, 12, 0, 54),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = card,
    })

    -- Loot container
    local lootContainer = Components.CreateFrame({
        Name = "LootContainer",
        Size = UDim2.new(1, -24, 0, 44),
        Position = UDim2.new(0, 12, 0, 72),
        BackgroundTransparency = 1,
        Parent = card,
    })

    local lootLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        Parent = lootContainer,
    })

    -- Loot rows
    local goldRow = createLootRow("Gold", Components.Colors.Gold, lootContainer)
    _goldLabel = goldRow:FindFirstChild("Amount") :: TextLabel

    local woodRow = createLootRow("Wood", Components.Colors.Wood, lootContainer)
    _woodLabel = woodRow:FindFirstChild("Amount") :: TextLabel

    local foodRow = createLootRow("Food", Components.Colors.Food, lootContainer)
    _foodLabel = foodRow:FindFirstChild("Amount") :: TextLabel

    -- Travel info
    local travelInfo = Components.CreateFrame({
        Name = "TravelInfo",
        Size = UDim2.new(1, -24, 0, 36),
        Position = UDim2.new(0, 12, 0, 122),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = card,
    })

    _distanceLabel = Components.CreateLabel({
        Name = "Distance",
        Text = "Distance: --",
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = travelInfo,
    })

    _travelTimeLabel = Components.CreateLabel({
        Name = "TravelTime",
        Text = "Travel: Instant",
        Size = UDim2.new(0.5, -8, 1, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        TextColor = Components.Colors.Success,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = travelInfo,
    })

    -- Buttons
    local attackButton = Components.CreateButton({
        Name = "AttackButton",
        Text = "Attack!",
        Size = UDim2.new(0.48, 0, 0, 42),
        Position = UDim2.new(0.75, 0, 1, -12),
        AnchorPoint = Vector2.new(0.5, 1),
        Style = "danger",
        TextSize = Components.Sizes.FontSizeLarge,
        OnClick = function()
            if _currentOpponent then
                WorldMapUI.AttackRequested:Fire(_currentOpponent.userId)
            end
        end,
        Parent = card,
    })

    local closeButton = Components.CreateButton({
        Name = "CloseButton",
        Text = "< Back",
        Size = UDim2.new(0.48, 0, 0, 42),
        Position = UDim2.new(0.25, 0, 1, -12),
        AnchorPoint = Vector2.new(0.5, 1),
        Style = "secondary",
        TextSize = Components.Sizes.FontSizeMedium,
        OnClick = function()
            _opponentCard.Visible = false
            _currentOpponent = nil
        end,
        Parent = card,
    })

    return card
end

--[[
    Creates the relocation panel.
]]
local function createRelocatePanel(parent: Frame): Frame
    local panel = Components.CreateFrame({
        Name = "RelocatePanel",
        Size = UDim2.new(1, -32, 0, 120),
        Position = UDim2.new(0.5, 0, 1, -16),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = Components.Colors.Panel,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        BorderColor = Components.Colors.PanelBorder,
        Parent = parent,
    })
    panel.Visible = false

    local title = Components.CreateLabel({
        Name = "Title",
        Text = "Relocate Base",
        Size = UDim2.new(1, -24, 0, 24),
        Position = UDim2.new(0, 12, 0, 8),
        TextColor = Components.Colors.TextGold,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        Parent = panel,
    })

    local infoText = Components.CreateLabel({
        Name = "Info",
        Text = "Tap on the map to select a new location for your base.",
        Size = UDim2.new(1, -24, 0, 20),
        Position = UDim2.new(0, 12, 0, 34),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = panel,
    })

    _relocateCooldownLabel = Components.CreateLabel({
        Name = "Cooldown",
        Text = "Free relocation available!",
        Size = UDim2.new(0.5, -12, 0, 18),
        Position = UDim2.new(0, 12, 0, 56),
        TextColor = Components.Colors.Success,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = panel,
    })

    _relocateCostLabel = Components.CreateLabel({
        Name = "Cost",
        Text = "",
        Size = UDim2.new(0.5, -12, 0, 18),
        Position = UDim2.new(0.5, 0, 0, 56),
        TextColor = Components.Colors.Gold,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = panel,
    })

    local cancelButton = Components.CreateButton({
        Name = "CancelButton",
        Text = "Cancel",
        Size = UDim2.new(1, -24, 0, 36),
        Position = UDim2.new(0.5, 0, 1, -8),
        AnchorPoint = Vector2.new(0.5, 1),
        Style = "secondary",
        OnClick = function()
            _isRelocateMode = false
            _relocatePanel.Visible = false
        end,
        Parent = panel,
    })

    return panel
end

--[[
    Updates the opponent display.
]]
function WorldMapUI:UpdateOpponent(opponent: any)
    _currentOpponent = opponent

    if not opponent then
        _opponentNameLabel.Text = "Select a target"
        _opponentTrophyLabel.Text = ""
        _thLevelLabel.Text = ""
        _goldLabel.Text = "0"
        _woodLabel.Text = "0"
        _foodLabel.Text = "0"
        _distanceLabel.Text = "Distance: --"
        _travelTimeLabel.Text = "Travel: --"
        _difficultyLabel.Text = ""
        return
    end

    _opponentNameLabel.Text = opponent.username or "Unknown"
    _opponentTrophyLabel.Text = formatNumber(opponent.trophies or 0) .. " Trophies"
    _thLevelLabel.Text = "TH " .. (opponent.townHallLevel or 1)

    -- Calculate available loot
    local lootPercent = 0.2 -- 20% lootable
    _goldLabel.Text = formatNumber((opponent.resources and opponent.resources.gold or 0) * lootPercent)
    _woodLabel.Text = formatNumber((opponent.resources and opponent.resources.wood or 0) * lootPercent)
    _foodLabel.Text = formatNumber((opponent.resources and opponent.resources.food or 0) * lootPercent)

    -- Update avatar initial
    local avatar = _opponentCard:FindFirstChild("Header"):FindFirstChild("Avatar")
    local avatarLabel = avatar:FindFirstChild("Initial") :: TextLabel
    avatarLabel.Text = string.sub(opponent.username or "?", 1, 1):upper()

    -- Calculate distance and travel time
    if _playerPosition and opponent.position then
        local distance = WorldMapData.CalculateDistance(_playerPosition, opponent.position)
        local travelTime, travelDesc = WorldMapData.CalculateTravelTime(distance)

        _distanceLabel.Text = string.format("Distance: %d", math.floor(distance))
        _travelTimeLabel.Text = "Travel: " .. formatTime(travelTime)

        if travelTime == 0 then
            _travelTimeLabel.TextColor3 = Components.Colors.Success
        else
            _travelTimeLabel.TextColor3 = Components.Colors.Warning
        end

        -- Get difficulty
        local playerData = ClientAPI:GetPlayerData()
        if playerData then
            local _, difficultyLevel = WorldMapData.GetDifficultyColor(
                playerData.townHallLevel or 1,
                playerData.trophies and playerData.trophies.current or 0,
                opponent.townHallLevel or 1,
                opponent.trophies or 0
            )
            _difficultyLabel.Text = difficultyLevel

            if difficultyLevel == "Easy" then
                _difficultyLabel.TextColor3 = Components.Colors.Success
            elseif difficultyLevel == "Medium" then
                _difficultyLabel.TextColor3 = Components.Colors.Warning
            else
                _difficultyLabel.TextColor3 = Components.Colors.Danger
            end
        end
    end
end

--[[
    Selects an opponent from the map.
]]
function WorldMapUI:SelectOpponent(opponent: any)
    self:UpdateOpponent(opponent)
    _opponentCard.Visible = true
end

--[[
    Loads map players from server.
]]
function WorldMapUI:LoadMapPlayers()
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if not Events then return end

    local GetMapPlayers = Events:FindFirstChild("GetMapPlayers") :: RemoteFunction
    if not GetMapPlayers then return end

    local success, result = pcall(function()
        return GetMapPlayers:InvokeServer(nil, WorldMapData.Map.MaxVisibleBases)
    end)

    if success and result then
        _mapPlayers = result
        refreshMapMarkers()
    end
end

--[[
    Updates relocation status display.
]]
function WorldMapUI:UpdateRelocationStatus()
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if not Events then return end

    local GetRelocationStatus = Events:FindFirstChild("GetRelocationStatus") :: RemoteFunction
    if not GetRelocationStatus then return end

    local success, result = pcall(function()
        return GetRelocationStatus:InvokeServer()
    end)

    if success and result then
        if result.canRelocateFree then
            _relocateCooldownLabel.Text = "Free relocation available!"
            _relocateCooldownLabel.TextColor3 = Components.Colors.Success
            _relocateCostLabel.Text = ""
        else
            _relocateCooldownLabel.Text = "Cooldown: " .. formatTime(result.cooldownRemaining)
            _relocateCooldownLabel.TextColor3 = Components.Colors.Warning
            _relocateCostLabel.Text = "Cost: " .. formatNumber(result.costIfNow) .. " Gold"
        end
    end
end

--[[
    Shows relocation confirmation.
]]
function WorldMapUI:ShowRelocationConfirm()
    if not _selectedPosition then return end

    -- Validate position
    if not WorldMapData.IsValidPosition(_selectedPosition) then
        warn("Invalid position selected")
        return
    end

    -- Show confirmation UI (simplified - just relocate)
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if not Events then return end

    local RelocateBase = Events:FindFirstChild("RelocateBase") :: RemoteEvent
    if not RelocateBase then return end

    RelocateBase:FireServer(_selectedPosition)

    -- Exit relocate mode
    _isRelocateMode = false
    _relocatePanel.Visible = false
    _selectedPosition = nil

    -- Refresh map
    task.delay(0.5, function()
        self:LoadMapPlayers()
    end)
end

--[[
    Enters relocation mode.
]]
function WorldMapUI:EnterRelocateMode()
    _isRelocateMode = true
    _opponentCard.Visible = false
    _relocatePanel.Visible = true
    self:UpdateRelocationStatus()
end

--[[
    Shows the world map UI.
]]
function WorldMapUI:Show()
    if _isVisible then return end
    _isVisible = true

    _screenGui.Enabled = true
    Components.SlideIn(_mainContainer, "bottom")

    -- Load player position
    local playerData = ClientAPI:GetPlayerData()
    if playerData and playerData.mapPosition then
        _playerPosition = playerData.mapPosition
    end

    -- Load map players
    self:LoadMapPlayers()
end

--[[
    Hides the world map UI.
]]
function WorldMapUI:Hide()
    if not _isVisible then return end
    _isVisible = false

    Components.SlideOut(_mainContainer, "bottom")
    task.delay(0.3, function()
        if not _isVisible then
            _screenGui.Enabled = false
        end
    end)

    _currentOpponent = nil
    _isRelocateMode = false
    WorldMapUI.Closed:Fire()
end

--[[
    Checks if visible.
]]
function WorldMapUI:IsVisible(): boolean
    return _isVisible
end

--[[
    Checks if initialized.
]]
function WorldMapUI:IsInitialized(): boolean
    return _initialized
end

--[[
    Initializes the WorldMapUI.
]]
function WorldMapUI:Init()
    if _initialized then
        warn("WorldMapUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "WorldMapUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Background
    local background = Components.CreateFrame({
        Name = "Background",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor = Components.Colors.Background,
        Parent = _screenGui,
    })

    -- Header
    local header = Components.CreateFrame({
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor = Components.Colors.BackgroundLight,
        Parent = background,
    })

    local titleLabel = Components.CreateLabel({
        Name = "Title",
        Text = "World Map",
        Size = UDim2.new(1, -200, 1, 0),
        Position = UDim2.new(0, 16, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        Parent = header,
    })

    -- Relocate button
    local relocateButton = Components.CreateButton({
        Name = "RelocateButton",
        Text = "Move Base",
        Size = UDim2.new(0, 90, 0, 36),
        Position = UDim2.new(1, -106, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        Style = "gold",
        TextSize = Components.Sizes.FontSizeSmall,
        OnClick = function()
            self:EnterRelocateMode()
        end,
        Parent = header,
    })

    -- Back button
    local backButton = Components.CreateButton({
        Name = "BackButton",
        Text = "X",
        Size = UDim2.new(0, 36, 0, 36),
        Position = UDim2.new(1, -8, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        Style = "danger",
        TextSize = Components.Sizes.FontSizeMedium,
        OnClick = function()
            self:Hide()
        end,
        Parent = header,
    })

    -- Main container
    _mainContainer = Components.CreateFrame({
        Name = "MainContainer",
        Size = UDim2.new(1, 0, 1, -50),
        Position = UDim2.new(0, 0, 0, 50),
        BackgroundTransparency = 1,
        Parent = background,
    })

    -- Create map view
    _mapViewport = createMapView(_mainContainer)

    -- Create opponent card
    _opponentCard = createOpponentCard(_mainContainer)

    -- Create relocate panel
    _relocatePanel = createRelocatePanel(_mainContainer)

    -- Listen for server response
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if Events then
        local ServerResponse = Events:FindFirstChild("ServerResponse") :: RemoteEvent
        if ServerResponse then
            ServerResponse.OnClientEvent:Connect(function(eventName, result)
                if eventName == "RelocateBase" then
                    if result.success then
                        _playerPosition = result.newPosition
                        self:LoadMapPlayers()
                        WorldMapUI.BaseRelocated:Fire(result.newPosition)
                    else
                        warn("Relocation failed:", result.error)
                    end
                end
            end)
        end
    end

    _initialized = true
    print("WorldMapUI initialized")
end

return WorldMapUI
