--!strict
--[[
    BuildMenu.lua

    Building selection menu for placing new structures.
    Shows available buildings organized by category.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Components)
local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local BuildMenu = {}
BuildMenu.__index = BuildMenu

-- Events
BuildMenu.BuildingSelected = Signal.new()
BuildMenu.Closed = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _mainPanel: Frame
local _categoryButtons: {[string]: TextButton} = {}
local _buildingCards: {Frame} = {}
local _currentCategory = "Farms"
local _isVisible = false
local _initialized = false

-- Building categories (simplified for walk-through tycoon)
-- Only Farm is buildable - all other buildings are single-instance starting buildings
local Categories = {
    { id = "Farms", name = "Farms", icon = "F" },
}

--[[
    Gets the color for a building category.
]]
local function getCategoryColor(category: string): Color3
    if category == "Resources" or category == "resource" or category == "storage" then
        return Components.Colors.Gold
    elseif category == "Defense" or category == "defense" or category == "wall" then
        return Components.Colors.Danger
    elseif category == "Army" or category == "military" then
        return Components.Colors.Primary
    else
        return Components.Colors.TextMuted
    end
end

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
    Formats a cost table for display.
]]
local function formatCost(cost: {gold: number?, wood: number?, food: number?}): string
    local parts = {}
    if cost.gold and cost.gold > 0 then
        table.insert(parts, formatNumber(cost.gold) .. " G")
    end
    if cost.wood and cost.wood > 0 then
        table.insert(parts, formatNumber(cost.wood) .. " W")
    end
    if cost.food and cost.food > 0 then
        table.insert(parts, formatNumber(cost.food) .. " F")
    end
    return table.concat(parts, " ")
end

--[[
    Creates a building card for the grid.
]]
local function createBuildingCard(buildingDef: any, parent: GuiObject): Frame
    local card = Components.CreateFrame({
        Name = buildingDef.type,
        Size = UDim2.new(0, 100, 0, 130),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = Components.Colors.PanelBorder,
        Parent = parent,
    })

    -- Building icon (placeholder)
    local iconBg = Components.CreateFrame({
        Name = "Icon",
        Size = UDim2.new(0, 60, 0, 60),
        Position = UDim2.new(0.5, 0, 0, 8),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = getCategoryColor(buildingDef.category),
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = card,
    })

    local iconLabel = Components.CreateLabel({
        Name = "IconText",
        Text = string.sub(buildingDef.displayName or buildingDef.type, 1, 2),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeXLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Building name
    local nameLabel = Components.CreateLabel({
        Name = "Name",
        Text = buildingDef.displayName or buildingDef.type,
        Size = UDim2.new(1, -8, 0, 18),
        Position = UDim2.new(0, 4, 0, 72),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = card,
    })

    -- Cost display
    local costLabel = Components.CreateLabel({
        Name = "Cost",
        Text = formatCost(buildingDef.levels[1].cost),
        Size = UDim2.new(1, -8, 0, 16),
        Position = UDim2.new(0, 4, 0, 90),
        TextColor = Components.Colors.Gold,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = card,
    })

    -- Build button
    local buildButton = Components.CreateButton({
        Name = "BuildButton",
        Text = "Build",
        Size = UDim2.new(1, -16, 0, 24),
        Position = UDim2.new(0.5, 0, 1, -8),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = Components.Colors.Secondary,
        TextSize = Components.Sizes.FontSizeSmall,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        OnClick = function()
            BuildMenu.BuildingSelected:Fire(buildingDef.type)
        end,
        Parent = card,
    })

    return card
end

--[[
    Creates the category tabs.
]]
local function createCategoryTabs(parent: Frame): Frame
    local tabContainer = Components.CreateFrame({
        Name = "CategoryTabs",
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local listLayout = Components.CreateListLayout({
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
                BuildMenu:SwitchCategory(category.id)
            end,
            Parent = tabContainer,
        })

        _categoryButtons[category.id] = tabButton
    end

    return tabContainer
end

--[[
    Creates a farm slot card showing available/locked farm slots.
]]
local function createFarmSlotCard(farmNumber: number, isUnlocked: boolean, isBuilt: boolean, parent: GuiObject): Frame
    local card = Components.CreateFrame({
        Name = "Farm" .. farmNumber,
        Size = UDim2.new(0, 100, 0, 130),
        BackgroundColor = isBuilt and Components.Colors.BackgroundLight or (isUnlocked and Components.Colors.Secondary or Components.Colors.BackgroundDark),
        BackgroundTransparency = isBuilt and 0 or 0.3,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = isBuilt and Components.Colors.Secondary or Components.Colors.PanelBorder,
        Parent = parent,
    })

    -- Farm icon
    local iconBg = Components.CreateFrame({
        Name = "Icon",
        Size = UDim2.new(0, 60, 0, 60),
        Position = UDim2.new(0.5, 0, 0, 8),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = isBuilt and Components.Colors.Food or (isUnlocked and Components.Colors.Secondary or Components.Colors.TextMuted),
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = card,
    })

    local iconLabel = Components.CreateLabel({
        Name = "IconText",
        Text = farmNumber == 1 and "🌾" or tostring(farmNumber),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeXLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Farm name
    local nameLabel = Components.CreateLabel({
        Name = "Name",
        Text = "Farm " .. farmNumber,
        Size = UDim2.new(1, -8, 0, 18),
        Position = UDim2.new(0, 4, 0, 72),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = card,
    })

    -- Status/cost display
    local statusText = ""
    if isBuilt then
        statusText = "✓ Built"
    elseif isUnlocked then
        statusText = "Ready to Build"
    else
        -- Show cost from BuildingData
        local plotCost = BuildingData.FarmPlotCosts[farmNumber]
        if plotCost then
            statusText = formatNumber(plotCost.gold) .. "G + " .. formatNumber(plotCost.wood) .. "W"
        else
            statusText = "Locked"
        end
    end

    local statusLabel = Components.CreateLabel({
        Name = "Status",
        Text = statusText,
        Size = UDim2.new(1, -8, 0, 16),
        Position = UDim2.new(0, 4, 0, 90),
        TextColor = isBuilt and Components.Colors.Secondary or (isUnlocked and Components.Colors.Gold or Components.Colors.TextMuted),
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = card,
    })

    -- Action button
    local buttonText = ""
    local buttonColor = Components.Colors.BackgroundLight
    local buttonEnabled = false

    if isBuilt then
        buttonText = "Enter"
        buttonColor = Components.Colors.Primary
        buttonEnabled = true
    elseif isUnlocked then
        buttonText = "Build"
        buttonColor = Components.Colors.Secondary
        buttonEnabled = true
    else
        buttonText = "Buy Plot"
        buttonColor = Components.Colors.Gold
        buttonEnabled = true
    end

    local actionButton = Components.CreateButton({
        Name = "ActionButton",
        Text = buttonText,
        Size = UDim2.new(1, -16, 0, 24),
        Position = UDim2.new(0.5, 0, 1, -8),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = buttonColor,
        TextSize = Components.Sizes.FontSizeSmall,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        OnClick = function()
            if isBuilt then
                -- TODO: Teleport to farm interior
                print("[BuildMenu] Enter Farm " .. farmNumber)
            elseif isUnlocked then
                -- Build the farm
                BuildMenu.BuildingSelected:Fire("Farm", farmNumber)
            else
                -- Open shop to buy farm plot
                BuildMenu.Closed:Fire()
                -- Signal to open shop expansion tab
                local ShopUI = require(script.Parent.ShopUI)
                if ShopUI then
                    ShopUI:Show()
                    ShopUI:SwitchCategory("Expansion")
                end
            end
        end,
        Parent = card,
    })

    return card
end

--[[
    Populates the building grid with farm slots.
]]
local function populateBuildingGrid(parent: Frame)
    -- Clear existing cards
    for _, card in _buildingCards do
        card:Destroy()
    end
    _buildingCards = {}

    -- For walk-through tycoon, we show farm slots (1-6)
    -- Farm 1 is always built by default
    -- Other farms depend on purchased plots

    -- Get player's farm data from server via RemoteFunction
    local farmPlots = 1
    local builtFarms = { [1] = true }

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local getFarmData = remotes:FindFirstChild("GetFarmData")
        if getFarmData then
            local success, farmData = pcall(function()
                return getFarmData:InvokeServer()
            end)
            if success and farmData then
                farmPlots = farmData.farmPlots or 1
                builtFarms = farmData.builtFarms or { [1] = true }
            end
        end
    end

    -- Create cards for each farm slot (1-6)
    for farmNumber = 1, 6 do
        local isUnlocked = farmNumber <= farmPlots
        local isBuilt = builtFarms[farmNumber] == true

        local card = createFarmSlotCard(farmNumber, isUnlocked, isBuilt, parent)
        table.insert(_buildingCards, card)
    end
end

--[[
    Switches to a different category.
]]
function BuildMenu:SwitchCategory(categoryId: string)
    if _currentCategory == categoryId then
        return
    end

    -- Update button states
    for id, button in _categoryButtons do
        if id == categoryId then
            button.BackgroundColor3 = Components.Colors.Primary
        else
            button.BackgroundColor3 = Components.Colors.BackgroundLight
        end
    end

    _currentCategory = categoryId

    -- Repopulate grid
    local content = _mainPanel:FindFirstChild("Content", true)
    local scrollFrame = content:FindFirstChild("BuildingScroll") :: ScrollingFrame
    if scrollFrame then
        populateBuildingGrid(scrollFrame)
    end
end

--[[
    Shows the build menu.
]]
function BuildMenu:Show()
    if _isVisible then return end
    _isVisible = true

    _screenGui.Enabled = true
    Components.SlideIn(_mainPanel, "bottom")
end

--[[
    Hides the build menu.
]]
function BuildMenu:Hide()
    if not _isVisible then return end
    _isVisible = false

    Components.SlideOut(_mainPanel, "bottom")
    task.delay(0.3, function()
        if not _isVisible then
            _screenGui.Enabled = false
        end
    end)

    BuildMenu.Closed:Fire()
end

--[[
    Toggles the build menu visibility.
]]
function BuildMenu:Toggle()
    if _isVisible then
        self:Hide()
    else
        self:Show()
    end
end

--[[
    Checks if menu is visible.
]]
function BuildMenu:IsVisible(): boolean
    return _isVisible
end

--[[
    Initializes the BuildMenu.
]]
function BuildMenu:Init()
    if _initialized then
        warn("BuildMenu already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "BuildMenu"
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

    -- Close on overlay click
    local overlayButton = Instance.new("TextButton")
    overlayButton.Name = "OverlayButton"
    overlayButton.Size = UDim2.new(1, 0, 1, 0)
    overlayButton.BackgroundTransparency = 1
    overlayButton.Text = ""
    overlayButton.Parent = overlay
    overlayButton.MouseButton1Click:Connect(function()
        self:Hide()
    end)

    -- Main panel
    _mainPanel = Components.CreatePanel({
        Name = "BuildPanel",
        Title = "Build",
        Size = UDim2.new(1, -32, 0, 400),
        Position = UDim2.new(0.5, 0, 1, -16),
        AnchorPoint = Vector2.new(0.5, 1),
        ShowCloseButton = true,
        OnClose = function()
            self:Hide()
        end,
        Parent = _screenGui,
    })

    -- Get content area
    local content = _mainPanel:FindFirstChild("Content") :: Frame

    -- Create category tabs
    createCategoryTabs(content)

    -- Create scrolling grid
    local scrollFrame = Components.CreateScrollFrame({
        Name = "BuildingScroll",
        Size = UDim2.new(1, 0, 1, -48),
        Position = UDim2.new(0, 0, 0, 44),
        Parent = content,
    })

    -- Grid layout for building cards
    local gridLayout = Components.CreateGridLayout({
        CellSize = UDim2.new(0, 100, 0, 130),
        CellPadding = UDim2.new(0, 8, 0, 8),
        Parent = scrollFrame,
    })

    -- Initial population
    populateBuildingGrid(scrollFrame)

    _initialized = true
    print("BuildMenu initialized")
end

return BuildMenu
