--!strict
--[[
    ShopUI.lua

    In-game shop for purchasing builders, shields, and resource conversions.
    All purchases use gold (earned through gameplay).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local ShopUI = {}
ShopUI.__index = ShopUI

-- Events
ShopUI.Closed = Signal.new()
ShopUI.PurchaseRequested = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _panel: Frame
local _contentContainer: ScrollingFrame
local _isVisible = false
local _initialized = false
local _currentCategory = "Builders"

-- Shop categories (no more Gems category)
local Categories = {
    { id = "Builders", name = "Builders", icon = "B" },
    { id = "Expansion", name = "Expand", icon = "E" },
    { id = "Resources", name = "Resources", icon = "R" },
    { id = "Boosts", name = "Boosts", icon = "S" },
}

-- Shop items (all priced in gold)
local ShopItems = {
    Builders = {
        { id = "builder_2", name = "2nd Builder", goldCost = 25000, permanent = true, description = "Build 2 things at once!" },
        { id = "builder_3", name = "3rd Builder", goldCost = 75000, permanent = true, description = "Build 3 things at once!" },
        { id = "builder_4", name = "4th Builder", goldCost = 200000, permanent = true, description = "Build 4 things at once!", featured = true },
        { id = "builder_5", name = "5th Builder", goldCost = 500000, permanent = true, description = "Maximum building speed!" },
    },
    Expansion = {
        { id = "farm_plot_2", name = "2nd Farm Plot", goldCost = 1000, woodCost = 500, expansion = true, plotNumber = 2, description = "Build a second farm!" },
        { id = "farm_plot_3", name = "3rd Farm Plot", goldCost = 3000, woodCost = 1500, expansion = true, plotNumber = 3, description = "More food production!" },
        { id = "farm_plot_4", name = "4th Farm Plot", goldCost = 10000, woodCost = 5000, expansion = true, plotNumber = 4, description = "Expand your farms!", featured = true },
        { id = "farm_plot_5", name = "5th Farm Plot", goldCost = 30000, woodCost = 15000, expansion = true, plotNumber = 5, description = "Feed a larger army!" },
        { id = "farm_plot_6", name = "6th Farm Plot", goldCost = 75000, woodCost = 35000, expansion = true, plotNumber = 6, description = "Maximum farm capacity!", featured = true },
    },
    Resources = {
        { id = "wood_5k", name = "Wood Pack", resource = "wood", amount = 5000, goldCost = 7500, description = "Quick wood boost" },
        { id = "wood_20k", name = "Wood Crate", resource = "wood", amount = 20000, goldCost = 25000, description = "Large wood shipment" },
        { id = "wood_50k", name = "Wood Warehouse", resource = "wood", amount = 50000, goldCost = 55000, description = "Massive wood delivery", featured = true },
        { id = "food_2k", name = "Food Pack", resource = "food", amount = 2000, goldCost = 5000, description = "Quick food boost" },
        { id = "food_10k", name = "Food Crate", resource = "food", amount = 10000, goldCost = 20000, description = "Large food shipment" },
        { id = "food_25k", name = "Food Warehouse", resource = "food", amount = 25000, goldCost = 45000, description = "Massive food delivery", featured = true },
    },
    Boosts = {
        { id = "shield_1d", name = "1-Day Shield", goldCost = 10000, duration = "24 hours", description = "Protection from attacks" },
        { id = "shield_2d", name = "2-Day Shield", goldCost = 18000, duration = "48 hours", description = "Extended protection" },
        { id = "shield_7d", name = "Week Shield", goldCost = 50000, duration = "7 days", description = "Maximum protection", featured = true },
    },
}

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
    Gets the color for a resource type.
]]
local function getResourceColor(resource: string): Color3
    if resource == "gold" then
        return Components.Colors.Gold
    elseif resource == "wood" then
        return Components.Colors.Wood
    elseif resource == "food" then
        return Components.Colors.Food
    else
        return Components.Colors.Primary
    end
end

--[[
    Creates a shop item card.
]]
local function createItemCard(item: any, parent: GuiObject): Frame
    local isFeatured = item.featured == true
    local cardHeight = isFeatured and 140 or 100

    local card = Components.CreateFrame({
        Name = item.id,
        Size = UDim2.new(1, 0, 0, cardHeight),
        BackgroundColor = isFeatured and Components.Colors.Primary or Components.Colors.BackgroundLight,
        BackgroundTransparency = isFeatured and 0.8 or 0,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = isFeatured and Components.Colors.Warning or Components.Colors.PanelBorder,
        Parent = parent,
    })

    -- Featured badge
    if isFeatured then
        local badge = Components.CreateFrame({
            Name = "FeaturedBadge",
            Size = UDim2.new(0, 70, 0, 20),
            Position = UDim2.new(1, -8, 0, 8),
            AnchorPoint = Vector2.new(1, 0),
            BackgroundColor = Components.Colors.Warning,
            CornerRadius = Components.Sizes.CornerRadiusSmall,
            Parent = card,
        })

        local badgeLabel = Components.CreateLabel({
            Name = "BadgeText",
            Text = "BEST VALUE",
            Size = UDim2.new(1, 0, 1, 0),
            TextColor = Color3.new(0, 0, 0),
            TextSize = 10,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = badge,
        })
    end

    -- Icon
    local iconColor = Components.Colors.Gold
    if item.resource then
        iconColor = getResourceColor(item.resource)
    elseif item.expansion then
        iconColor = Components.Colors.Food -- Green for farm plots
    elseif item.permanent then
        iconColor = Components.Colors.Secondary
    elseif item.duration then
        iconColor = Components.Colors.Primary
    end

    local iconBg = Components.CreateFrame({
        Name = "Icon",
        Size = UDim2.new(0, 50, 0, 50),
        Position = UDim2.new(0, 16, 0, isFeatured and 35 or 25),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = iconColor,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = card,
    })

    -- Icon content (amount or symbol)
    local iconText = "?"
    if item.amount then
        iconText = formatNumber(item.amount)
    elseif item.expansion then
        iconText = "#" .. (item.plotNumber or "?")
    elseif item.permanent then
        iconText = "+" .. (item.id:match("%d+") or "1")
    elseif item.duration then
        iconText = "🛡️"
    end

    local iconLabel = Components.CreateLabel({
        Name = "IconText",
        Text = iconText,
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Name
    local nameLabel = Components.CreateLabel({
        Name = "Name",
        Text = item.name,
        Size = UDim2.new(0.5, -80, 0, 20),
        Position = UDim2.new(0, 76, 0, isFeatured and 20 or 15),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        Parent = card,
    })

    -- Description
    local descText = item.description or ""
    if item.duration then
        descText = item.duration .. (item.description and " • " .. item.description or "")
    end

    if descText ~= "" then
        local descLabel = Components.CreateLabel({
            Name = "Description",
            Text = descText,
            Size = UDim2.new(0.5, -80, 0, 16),
            Position = UDim2.new(0, 76, 0, isFeatured and 42 or 35),
            TextColor = Components.Colors.TextSecondary,
            TextSize = Components.Sizes.FontSizeSmall,
            Parent = card,
        })
    end

    -- Price button - show gold + wood for expansions
    local priceText = formatNumber(item.goldCost) .. " Gold"
    local buttonWidth = 100

    if item.woodCost then
        priceText = formatNumber(item.goldCost) .. "G + " .. formatNumber(item.woodCost) .. "W"
        buttonWidth = 130
    end

    local buyButton = Components.CreateButton({
        Name = "BuyButton",
        Text = priceText,
        Size = UDim2.new(0, buttonWidth, 0, 36),
        Position = UDim2.new(1, -16, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor = item.expansion and Components.Colors.Secondary or Components.Colors.Gold,
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeSmall,
        OnClick = function()
            ShopUI.PurchaseRequested:Fire(item)
        end,
        Parent = card,
    })

    return card
end

--[[
    Creates category tabs.
]]
local function createCategoryTabs(parent: Frame): Frame
    local tabContainer = Components.CreateFrame({
        Name = "CategoryTabs",
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local tabLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 4),
        Parent = tabContainer,
    })

    for _, category in Categories do
        local isActive = category.id == _currentCategory

        local tabButton = Components.CreateButton({
            Name = category.id .. "Tab",
            Text = category.name,
            Size = UDim2.new(0, 90, 0, 32),
            BackgroundColor = isActive and Components.Colors.Primary or Components.Colors.BackgroundLight,
            TextSize = Components.Sizes.FontSizeSmall,
            CornerRadius = Components.Sizes.CornerRadiusSmall,
            OnClick = function()
                ShopUI:SwitchCategory(category.id)
            end,
            Parent = tabContainer,
        })
    end

    return tabContainer
end

--[[
    Populates the shop with items from current category.
]]
local function populateShop()
    -- Clear existing items
    for _, child in _contentContainer:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    -- Get items for current category
    local items = ShopItems[_currentCategory]
    if not items then return end

    for _, item in items do
        createItemCard(item, _contentContainer)
    end
end

--[[
    Switches to a different category.
]]
function ShopUI:SwitchCategory(categoryId: string)
    if _currentCategory == categoryId then return end
    _currentCategory = categoryId

    -- Update tab visuals (would need to store references)
    populateShop()
end

--[[
    Shows the shop UI.
]]
function ShopUI:Show()
    if _isVisible then return end
    _isVisible = true

    populateShop()

    _screenGui.Enabled = true
    Components.SlideIn(_panel, "bottom")
end

--[[
    Hides the shop UI.
]]
function ShopUI:Hide()
    if not _isVisible then return end
    _isVisible = false

    Components.SlideOut(_panel, "bottom")
    task.delay(0.3, function()
        if not _isVisible then
            _screenGui.Enabled = false
        end
    end)

    ShopUI.Closed:Fire()
end

--[[
    Toggles visibility.
]]
function ShopUI:Toggle()
    if _isVisible then
        self:Hide()
    else
        self:Show()
    end
end

--[[
    Checks if visible.
]]
function ShopUI:IsVisible(): boolean
    return _isVisible
end

--[[
    Initializes the ShopUI.
]]
function ShopUI:Init()
    if _initialized then
        warn("ShopUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "ShopUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Background overlay
    local overlay = Components.CreateFrame({
        Name = "Overlay",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.5,
        Parent = _screenGui,
    })

    local overlayButton = Instance.new("TextButton")
    overlayButton.Size = UDim2.new(1, 0, 1, 0)
    overlayButton.BackgroundTransparency = 1
    overlayButton.Text = ""
    overlayButton.Parent = overlay
    overlayButton.MouseButton1Click:Connect(function()
        self:Hide()
    end)

    -- Main panel
    _panel = Components.CreatePanel({
        Name = "ShopPanel",
        Title = "Shop",
        Size = UDim2.new(1, -32, 0.8, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        ShowCloseButton = true,
        OnClose = function()
            self:Hide()
        end,
        Parent = _screenGui,
    })

    local content = _panel:FindFirstChild("Content") :: Frame

    -- Gold display at top (shows current gold)
    local goldDisplay = Components.CreateResourceDisplay({
        Name = "GoldDisplay",
        ResourceType = "Gold",
        Size = UDim2.new(0, 110, 0, 36),
        Position = UDim2.new(1, -8, 0, -44),
        AnchorPoint = Vector2.new(1, 0),
        Parent = _panel,
    })

    -- Category tabs
    createCategoryTabs(content)

    -- Scrolling content
    _contentContainer = Components.CreateScrollFrame({
        Name = "ShopContent",
        Size = UDim2.new(1, 0, 1, -50),
        Position = UDim2.new(0, 0, 0, 48),
        Parent = content,
    })

    local listLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 8),
        Parent = _contentContainer,
    })

    _initialized = true
    print("ShopUI initialized")
end

return ShopUI
