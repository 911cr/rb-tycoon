--!strict
--[[
    ShopUI.lua

    In-game shop for purchasing gems, resources, and special items.
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
local _currentCategory = "Gems"

-- Shop categories
local Categories = {
    { id = "Gems", name = "Gems", icon = "G" },
    { id = "Resources", name = "Resources", icon = "R" },
    { id = "Builders", name = "Builders", icon = "B" },
    { id = "Special", name = "Special", icon = "S" },
}

-- Shop items
local ShopItems = {
    Gems = {
        { id = "gems_100", name = "Pile of Gems", gems = 100, price = "$0.99", featured = false },
        { id = "gems_500", name = "Bag of Gems", gems = 500, price = "$4.99", featured = false },
        { id = "gems_1200", name = "Box of Gems", gems = 1200, price = "$9.99", featured = true },
        { id = "gems_2500", name = "Chest of Gems", gems = 2500, price = "$19.99", featured = false },
        { id = "gems_6500", name = "Vault of Gems", gems = 6500, price = "$49.99", featured = false },
        { id = "gems_14000", name = "Mountain of Gems", gems = 14000, price = "$99.99", featured = true },
    },
    Resources = {
        { id = "gold_10k", name = "Gold Pack", resource = "gold", amount = 10000, gems = 50 },
        { id = "gold_50k", name = "Gold Chest", resource = "gold", amount = 50000, gems = 200 },
        { id = "gold_200k", name = "Gold Vault", resource = "gold", amount = 200000, gems = 700 },
        { id = "wood_10k", name = "Wood Pack", resource = "wood", amount = 10000, gems = 50 },
        { id = "wood_50k", name = "Wood Chest", resource = "wood", amount = 50000, gems = 200 },
        { id = "food_5k", name = "Food Pack", resource = "food", amount = 5000, gems = 30 },
        { id = "food_25k", name = "Food Chest", resource = "food", amount = 25000, gems = 120 },
    },
    Builders = {
        { id = "builder_2", name = "2nd Builder", gems = 250, permanent = true },
        { id = "builder_3", name = "3rd Builder", gems = 500, permanent = true },
        { id = "builder_4", name = "4th Builder", gems = 1000, permanent = true },
        { id = "builder_5", name = "5th Builder", gems = 2000, permanent = true },
    },
    Special = {
        { id = "shield_1d", name = "1-Day Shield", gems = 100, duration = "24h" },
        { id = "shield_2d", name = "2-Day Shield", gems = 150, duration = "48h" },
        { id = "shield_7d", name = "Week Shield", gems = 400, duration = "7 days" },
        { id = "vip_week", name = "VIP (1 Week)", gems = 200, duration = "7 days", bonus = "+20% Resources" },
        { id = "vip_month", name = "VIP (1 Month)", gems = 600, duration = "30 days", bonus = "+20% Resources" },
        { id = "starter_pack", name = "Starter Pack", price = "$4.99", featured = true, contents = "500 Gems + 50K Gold + Shield" },
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
        return Components.Colors.Gems
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
    local iconColor = Components.Colors.Gems
    if item.resource then
        iconColor = getResourceColor(item.resource)
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

    local iconText = item.gems and formatNumber(item.gems) or (item.amount and formatNumber(item.amount) or "?")
    local iconLabel = Components.CreateLabel({
        Name = "IconText",
        Text = iconText,
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = item.gems and item.gems > 1000 and 12 or 14,
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

    -- Description or contents
    local descText = ""
    if item.contents then
        descText = item.contents
    elseif item.duration then
        descText = item.duration
        if item.bonus then
            descText = descText .. " • " .. item.bonus
        end
    elseif item.permanent then
        descText = "Permanent unlock"
    elseif item.resource then
        descText = formatNumber(item.amount) .. " " .. item.resource:gsub("^%l", string.upper)
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

    -- Price button
    local priceText = item.price or (item.gems and formatNumber(item.gems) .. " Gems" or "Free")
    local priceColor = item.price and Components.Colors.Secondary or Components.Colors.Gems

    local buyButton = Components.CreateButton({
        Name = "BuyButton",
        Text = priceText,
        Size = UDim2.new(0, 90, 0, 36),
        Position = UDim2.new(1, -16, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor = priceColor,
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
            Size = UDim2.new(0, 80, 0, 32),
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

    -- Gems display at top
    local gemsDisplay = Components.CreateResourceDisplay({
        Name = "GemsDisplay",
        ResourceType = "Gems",
        Size = UDim2.new(0, 100, 0, 36),
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
