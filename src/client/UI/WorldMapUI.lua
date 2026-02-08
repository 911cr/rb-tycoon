--!strict
--[[
    WorldMapUI.lua

    World map interface for finding opponents to attack.
    Shows opponent bases with their resources and trophies.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local WorldMapUI = {}
WorldMapUI.__index = WorldMapUI

-- Events
WorldMapUI.Closed = Signal.new()
WorldMapUI.AttackRequested = Signal.new()
WorldMapUI.NextOpponentRequested = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _mainContainer: Frame
local _opponentCard: Frame
local _isVisible = false
local _initialized = false
local _currentOpponent: any = nil
local _searchCost = 0

-- UI References
local _opponentNameLabel: TextLabel
local _opponentTrophyLabel: TextLabel
local _goldLabel: TextLabel
local _woodLabel: TextLabel
local _foodLabel: TextLabel
local _thLevelLabel: TextLabel

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
    Creates the opponent info card.
]]
local function createOpponentCard(parent: Frame): Frame
    local card = Components.CreateFrame({
        Name = "OpponentCard",
        Size = UDim2.new(1, -32, 0, 280),
        Position = UDim2.new(0.5, 0, 0, 60),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.Panel,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        BorderColor = Components.Colors.PanelBorder,
        Parent = parent,
    })

    -- Opponent header
    local header = Components.CreateFrame({
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 60),
        BackgroundTransparency = 1,
        Parent = card,
    })

    -- Avatar placeholder
    local avatar = Components.CreateFrame({
        Name = "Avatar",
        Size = UDim2.new(0, 50, 0, 50),
        Position = UDim2.new(0, 16, 0.5, 0),
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
        Text = "Searching...",
        Size = UDim2.new(0.5, -80, 0, 24),
        Position = UDim2.new(0, 76, 0, 12),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        Parent = header,
    })

    -- Trophies
    _opponentTrophyLabel = Components.CreateLabel({
        Name = "Trophies",
        Text = "0 Trophies",
        Size = UDim2.new(0.5, -80, 0, 18),
        Position = UDim2.new(0, 76, 0, 36),
        TextColor = Components.Colors.Warning,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = header,
    })

    -- Town Hall level
    _thLevelLabel = Components.CreateLabel({
        Name = "THLevel",
        Text = "TH 1",
        Size = UDim2.new(0, 60, 0, 30),
        Position = UDim2.new(1, -16, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeMedium,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = header,
    })

    -- Available loot section
    local lootLabel = Components.CreateLabel({
        Name = "LootLabel",
        Text = "Available Loot",
        Size = UDim2.new(1, -32, 0, 20),
        Position = UDim2.new(0, 16, 0, 68),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = card,
    })

    -- Loot container
    local lootContainer = Components.CreateFrame({
        Name = "LootContainer",
        Size = UDim2.new(1, -32, 0, 44),
        Position = UDim2.new(0, 16, 0, 90),
        BackgroundTransparency = 1,
        Parent = card,
    })

    local lootLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        Parent = lootContainer,
    })

    -- Loot rows
    local goldRow = createLootRow("Gold", Components.Colors.Gold, lootContainer)
    _goldLabel = goldRow:FindFirstChild("Amount") :: TextLabel

    local woodRow = createLootRow("Wood", Components.Colors.Wood, lootContainer)
    _woodLabel = woodRow:FindFirstChild("Amount") :: TextLabel

    local foodRow = createLootRow("Food", Components.Colors.Food, lootContainer)
    _foodLabel = foodRow:FindFirstChild("Amount") :: TextLabel

    -- Base preview placeholder
    local previewFrame = Components.CreateFrame({
        Name = "Preview",
        Size = UDim2.new(1, -32, 0, 80),
        Position = UDim2.new(0, 16, 0, 145),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = card,
    })

    local previewLabel = Components.CreateLabel({
        Name = "PreviewText",
        Text = "Base Preview",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextMuted,
        TextSize = Components.Sizes.FontSizeMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = previewFrame,
    })

    -- Attack button
    local attackButton = Components.CreateButton({
        Name = "AttackButton",
        Text = "Attack!",
        Size = UDim2.new(0.5, -24, 0, 44),
        Position = UDim2.new(0.75, 0, 1, -16),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = Components.Colors.Danger,
        TextSize = Components.Sizes.FontSizeLarge,
        OnClick = function()
            if _currentOpponent then
                WorldMapUI.AttackRequested:Fire(_currentOpponent.userId)
            end
        end,
        Parent = card,
    })

    -- Next button
    local nextButton = Components.CreateButton({
        Name = "NextButton",
        Text = "Next (Free)",
        Size = UDim2.new(0.5, -24, 0, 44),
        Position = UDim2.new(0.25, 0, 1, -16),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = Components.Colors.Primary,
        TextSize = Components.Sizes.FontSizeMedium,
        OnClick = function()
            WorldMapUI.NextOpponentRequested:Fire()
            WorldMapUI:SearchForOpponent()
        end,
        Parent = card,
    })

    return card
end

--[[
    Updates the opponent display.
]]
function WorldMapUI:UpdateOpponent(opponent: any)
    _currentOpponent = opponent

    if not opponent then
        _opponentNameLabel.Text = "No opponent found"
        _opponentTrophyLabel.Text = ""
        _thLevelLabel.Text = ""
        _goldLabel.Text = "0"
        _woodLabel.Text = "0"
        _foodLabel.Text = "0"
        return
    end

    _opponentNameLabel.Text = opponent.username or "Unknown"
    _opponentTrophyLabel.Text = formatNumber(opponent.trophies or 0) .. " Trophies"
    _thLevelLabel.Text = "TH " .. (opponent.townHallLevel or 1)

    -- Calculate available loot (simplified - would come from server)
    local lootPercent = 0.2 -- 20% lootable
    _goldLabel.Text = formatNumber((opponent.resources and opponent.resources.gold or 0) * lootPercent)
    _woodLabel.Text = formatNumber((opponent.resources and opponent.resources.wood or 0) * lootPercent)
    _foodLabel.Text = formatNumber((opponent.resources and opponent.resources.food or 0) * lootPercent)

    -- Update avatar initial
    local avatar = _opponentCard:FindFirstChild("Header"):FindFirstChild("Avatar")
    local avatarLabel = avatar:FindFirstChild("Initial") :: TextLabel
    avatarLabel.Text = string.sub(opponent.username or "?", 1, 1):upper()
end

--[[
    Simulates searching for an opponent.
]]
function WorldMapUI:SearchForOpponent()
    -- Show searching state
    _opponentNameLabel.Text = "Searching..."
    _opponentTrophyLabel.Text = ""

    -- Simulate finding opponent (in real game, this would be a server call)
    task.delay(0.5, function()
        -- Generate fake opponent for demo
        local fakeOpponent = {
            userId = math.random(1000000, 9999999),
            username = "Player" .. math.random(1000, 9999),
            trophies = math.random(0, 2000),
            townHallLevel = math.random(1, 8),
            resources = {
                gold = math.random(10000, 500000),
                wood = math.random(10000, 500000),
                food = math.random(5000, 200000),
            },
        }
        self:UpdateOpponent(fakeOpponent)
    end)
end

--[[
    Shows the world map UI.
]]
function WorldMapUI:Show()
    if _isVisible then return end
    _isVisible = true

    _screenGui.Enabled = true
    Components.SlideIn(_mainContainer, "bottom")

    -- Start searching for opponent
    self:SearchForOpponent()
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
    WorldMapUI.Closed:Fire()
end

--[[
    Checks if visible.
]]
function WorldMapUI:IsVisible(): boolean
    return _isVisible
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
        Text = "Find Opponent",
        Size = UDim2.new(1, -100, 1, 0),
        Position = UDim2.new(0, 16, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        Parent = header,
    })

    -- Back button
    local backButton = Components.CreateButton({
        Name = "BackButton",
        Text = "< Back",
        Size = UDim2.new(0, 80, 0, 36),
        Position = UDim2.new(1, -16, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor = Components.Colors.Danger,
        TextSize = Components.Sizes.FontSizeSmall,
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

    -- Create opponent card
    _opponentCard = createOpponentCard(_mainContainer)

    -- Army preview section
    local armySection = Components.CreateFrame({
        Name = "ArmySection",
        Size = UDim2.new(1, -32, 0, 100),
        Position = UDim2.new(0.5, 0, 1, -16),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = Components.Colors.Panel,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = _mainContainer,
    })

    local armyLabel = Components.CreateLabel({
        Name = "ArmyLabel",
        Text = "Your Army",
        Size = UDim2.new(1, -16, 0, 24),
        Position = UDim2.new(0, 8, 0, 8),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = armySection,
    })

    local armyScroll = Components.CreateScrollFrame({
        Name = "ArmyScroll",
        Size = UDim2.new(1, -16, 0, 60),
        Position = UDim2.new(0, 8, 0, 32),
        Parent = armySection,
    })
    armyScroll.ScrollingDirection = Enum.ScrollingDirection.X

    local armyLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 4),
        Parent = armyScroll,
    })

    _initialized = true
    print("WorldMapUI initialized")
end

return WorldMapUI
