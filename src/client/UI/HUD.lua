--!strict
--[[
    HUD.lua

    Main heads-up display showing resources, builders, and navigation.
    Always visible during gameplay (except during battles).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local HUD = {}
HUD.__index = HUD

-- Events
HUD.BuildMenuRequested = Signal.new()
HUD.AttackRequested = Signal.new()
HUD.ShopRequested = Signal.new()
HUD.QuestsRequested = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _resourceDisplays: {[string]: Frame} = {}
local _builderDisplay: Frame
local _initialized = false

-- Cache UI references
local _goldLabel: TextLabel
local _woodLabel: TextLabel
local _foodLabel: TextLabel
local _gemsLabel: TextLabel
local _buildersLabel: TextLabel
local _trophyLabel: TextLabel

--[[
    Creates the resource bar at the top of the screen.
]]
local function createResourceBar(parent: ScreenGui): Frame
    local bar = Components.CreateFrame({
        Name = "ResourceBar",
        Size = UDim2.new(1, 0, 0, 50),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor = Components.Colors.Background,
        BackgroundTransparency = 0.3,
        Parent = parent,
    })

    -- Add gradient for polish
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    gradient.Parent = bar

    -- Resource container (left side)
    local resourceContainer = Components.CreateFrame({
        Name = "Resources",
        Size = UDim2.new(0.7, 0, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1,
        Parent = bar,
    })

    local listLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = resourceContainer,
    })

    -- Gold display
    local goldDisplay = Components.CreateResourceDisplay({
        Name = "GoldDisplay",
        ResourceType = "Gold",
        Size = UDim2.new(0, 100, 0, 36),
        Parent = resourceContainer,
    })
    _goldLabel = goldDisplay:FindFirstChild("Amount", true) :: TextLabel
    _resourceDisplays["Gold"] = goldDisplay

    -- Wood display
    local woodDisplay = Components.CreateResourceDisplay({
        Name = "WoodDisplay",
        ResourceType = "Wood",
        Size = UDim2.new(0, 100, 0, 36),
        Parent = resourceContainer,
    })
    _woodLabel = woodDisplay:FindFirstChild("Amount", true) :: TextLabel
    _resourceDisplays["Wood"] = woodDisplay

    -- Food display
    local foodDisplay = Components.CreateResourceDisplay({
        Name = "FoodDisplay",
        ResourceType = "Food",
        Size = UDim2.new(0, 100, 0, 36),
        Parent = resourceContainer,
    })
    _foodLabel = foodDisplay:FindFirstChild("Amount", true) :: TextLabel
    _resourceDisplays["Food"] = foodDisplay

    -- Gems display (right side, premium currency)
    local gemsDisplay = Components.CreateResourceDisplay({
        Name = "GemsDisplay",
        ResourceType = "Gems",
        Size = UDim2.new(0, 90, 0, 36),
        Position = UDim2.new(1, -100, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        Parent = bar,
    })
    _gemsLabel = gemsDisplay:FindFirstChild("Amount", true) :: TextLabel
    _resourceDisplays["Gems"] = gemsDisplay

    return bar
end

--[[
    Creates the builder status display.
]]
local function createBuilderDisplay(parent: ScreenGui): Frame
    local container = Components.CreateFrame({
        Name = "BuilderDisplay",
        Size = UDim2.new(0, 100, 0, 36),
        Position = UDim2.new(0, 8, 0, 58),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = Components.Colors.Secondary,
        Parent = parent,
    })

    -- Builder icon
    local iconBg = Components.CreateFrame({
        Name = "IconBg",
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(0, 4, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = Components.Colors.Secondary,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = container,
    })

    local iconLabel = Components.CreateLabel({
        Name = "Icon",
        Text = "B",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Builder count
    _buildersLabel = Components.CreateLabel({
        Name = "Count",
        Text = "0/1",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 36, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        Parent = container,
    })

    return container
end

--[[
    Creates the trophy display.
]]
local function createTrophyDisplay(parent: ScreenGui): Frame
    local container = Components.CreateFrame({
        Name = "TrophyDisplay",
        Size = UDim2.new(0, 90, 0, 36),
        Position = UDim2.new(0, 116, 0, 58),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = Components.Colors.Warning,
        Parent = parent,
    })

    -- Trophy icon
    local iconBg = Components.CreateFrame({
        Name = "IconBg",
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(0, 4, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = Components.Colors.Warning,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = container,
    })

    local iconLabel = Components.CreateLabel({
        Name = "Icon",
        Text = "T",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Trophy count
    _trophyLabel = Components.CreateLabel({
        Name = "Count",
        Text = "0",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 36, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        Parent = container,
    })

    return container
end

--[[
    Creates the bottom action bar with main buttons.
]]
local function createActionBar(parent: ScreenGui): Frame
    local bar = Components.CreateFrame({
        Name = "ActionBar",
        Size = UDim2.new(1, 0, 0, 80),
        Position = UDim2.new(0, 0, 1, 0),
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor = Components.Colors.Background,
        BackgroundTransparency = 0.3,
        Parent = parent,
    })

    -- Add gradient
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = -90
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    gradient.Parent = bar

    -- Button container
    local buttonContainer = Components.CreateFrame({
        Name = "Buttons",
        Size = UDim2.new(1, -32, 0, 60),
        Position = UDim2.new(0.5, 0, 0, 10),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Parent = bar,
    })

    local listLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 16),
        Parent = buttonContainer,
    })

    -- Quests button
    local questsButton = Components.CreateButton({
        Name = "QuestsButton",
        Text = "Quests",
        Size = UDim2.new(0, 80, 0, 50),
        BackgroundColor = Components.Colors.Warning,
        OnClick = function()
            HUD.QuestsRequested:Fire()
        end,
        Parent = buttonContainer,
    })

    -- Shop button
    local shopButton = Components.CreateButton({
        Name = "ShopButton",
        Text = "Shop",
        Size = UDim2.new(0, 80, 0, 50),
        BackgroundColor = Components.Colors.Gems,
        OnClick = function()
            HUD.ShopRequested:Fire()
        end,
        Parent = buttonContainer,
    })

    -- Build button
    local buildButton = Components.CreateButton({
        Name = "BuildButton",
        Text = "Build",
        Size = UDim2.new(0, 100, 0, 50),
        BackgroundColor = Components.Colors.Secondary,
        OnClick = function()
            HUD.BuildMenuRequested:Fire()
        end,
        Parent = buttonContainer,
    })

    -- Attack button
    local attackButton = Components.CreateButton({
        Name = "AttackButton",
        Text = "Attack!",
        Size = UDim2.new(0, 100, 0, 50),
        BackgroundColor = Components.Colors.Danger,
        OnClick = function()
            HUD.AttackRequested:Fire()
        end,
        Parent = buttonContainer,
    })

    return bar
end

--[[
    Updates the resource displays with current values.
]]
function HUD:UpdateResources(resources: {gold: number, wood: number, food: number, gems: number})
    if _goldLabel then
        _goldLabel.Text = formatNumber(resources.gold or 0)
    end
    if _woodLabel then
        _woodLabel.Text = formatNumber(resources.wood or 0)
    end
    if _foodLabel then
        _foodLabel.Text = formatNumber(resources.food or 0)
    end
    if _gemsLabel then
        _gemsLabel.Text = tostring(resources.gems or 0)
    end
end

--[[
    Updates the builder display.
]]
function HUD:UpdateBuilders(freeBuilders: number, maxBuilders: number)
    if _buildersLabel then
        _buildersLabel.Text = string.format("%d/%d", freeBuilders, maxBuilders)
    end
end

--[[
    Updates the trophy display.
]]
function HUD:UpdateTrophies(trophies: number)
    if _trophyLabel then
        _trophyLabel.Text = formatNumber(trophies)
    end
end

--[[
    Shows or hides the HUD.
]]
function HUD:SetVisible(visible: boolean)
    if _screenGui then
        _screenGui.Enabled = visible
    end
end

--[[
    Formats a number for display.
]]
function formatNumber(value: number): string
    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fK", value / 1000)
    else
        return tostring(math.floor(value))
    end
end

--[[
    Initializes the HUD.
]]
function HUD:Init()
    if _initialized then
        warn("HUD already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create main ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "HUD"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.IgnoreGuiInset = true
    _screenGui.Parent = playerGui

    -- Create UI elements
    createResourceBar(_screenGui)
    _builderDisplay = createBuilderDisplay(_screenGui)
    createTrophyDisplay(_screenGui)
    createActionBar(_screenGui)

    -- Listen for data updates
    local Events = ReplicatedStorage:WaitForChild("Events")
    Events.SyncPlayerData.OnClientEvent:Connect(function(data)
        if data.resources then
            self:UpdateResources(data.resources)
        end
        if data.builders then
            local freeBuilders = 0
            for _, builder in data.builders do
                if not builder.busy then
                    freeBuilders += 1
                end
            end
            self:UpdateBuilders(freeBuilders, #data.builders)
        end
        if data.trophies then
            self:UpdateTrophies(data.trophies.current or 0)
        end
    end)

    _initialized = true
    print("HUD initialized")
end

return HUD
