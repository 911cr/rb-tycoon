--!strict
--[[
    SpellBrewingUI.lua

    UI for brewing spells at the Spell Factory.
    Shows available spells, brewing queue, and spell inventory.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local SpellBrewingUI = {}
SpellBrewingUI.__index = SpellBrewingUI

-- Events
SpellBrewingUI.CloseRequested = Signal.new()
SpellBrewingUI.SpellSelected = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _spellListContainer: ScrollingFrame? = nil
local _queueContainer: Frame? = nil
local _inventoryContainer: Frame? = nil
local _initialized = false

-- Spell definitions (client-side display data)
local SpellInfo = {
    Lightning = {
        name = "Lightning Spell",
        description = "Deals damage to buildings and troops in an area",
        icon = "⚡",
        color = Color3.fromRGB(255, 255, 100),
        housingSpace = 2,
        brewTime = 360,
    },
    Heal = {
        name = "Healing Spell",
        description = "Heals friendly troops over time",
        icon = "💚",
        color = Color3.fromRGB(100, 255, 100),
        housingSpace = 2,
        brewTime = 360,
    },
    Rage = {
        name = "Rage Spell",
        description = "Boosts troop speed and damage",
        icon = "🔥",
        color = Color3.fromRGB(255, 100, 100),
        housingSpace = 2,
        brewTime = 360,
    },
    Freeze = {
        name = "Freeze Spell",
        description = "Freezes enemy defenses and troops",
        icon = "❄️",
        color = Color3.fromRGB(100, 200, 255),
        housingSpace = 1,
        brewTime = 180,
    },
    Jump = {
        name = "Jump Spell",
        description = "Allows troops to jump over walls",
        icon = "⬆️",
        color = Color3.fromRGB(255, 200, 100),
        housingSpace = 2,
        brewTime = 360,
    },
    Clone = {
        name = "Clone Spell",
        description = "Clones troops that enter the radius",
        icon = "👥",
        color = Color3.fromRGB(200, 100, 255),
        housingSpace = 3,
        brewTime = 540,
    },
    Invisibility = {
        name = "Invisibility Spell",
        description = "Makes troops invisible to defenses",
        icon = "👻",
        color = Color3.fromRGB(200, 200, 255),
        housingSpace = 1,
        brewTime = 180,
    },
}

--[[
    Formats time for display.
]]
local function formatTime(seconds: number): string
    if seconds <= 0 then return "Ready" end

    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60

    if minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

--[[
    Creates a spell card for the available spells list.
]]
local function createSpellCard(spellType: string, parent: ScrollingFrame): Frame
    local info = SpellInfo[spellType]
    if not info then return Instance.new("Frame") end

    local card = Components.CreateFrame({
        Name = spellType,
        Size = UDim2.new(1, -16, 0, 80),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- Spell icon
    local iconBg = Components.CreateFrame({
        Name = "IconBg",
        Size = UDim2.new(0, 60, 0, 60),
        Position = UDim2.new(0, 10, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = info.color,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = card,
    })

    local iconLabel = Components.CreateLabel({
        Name = "Icon",
        Text = info.icon,
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 28,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Spell name
    local nameLabel = Components.CreateLabel({
        Name = "Name",
        Text = info.name,
        Size = UDim2.new(0.4, 0, 0, 24),
        Position = UDim2.new(0, 80, 0, 12),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    -- Description
    local descLabel = Components.CreateLabel({
        Name = "Description",
        Text = info.description,
        Size = UDim2.new(0.4, 0, 0, 20),
        Position = UDim2.new(0, 80, 0, 36),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Parent = card,
    })

    -- Brew time
    local timeLabel = Components.CreateLabel({
        Name = "BrewTime",
        Text = "Brew: " .. formatTime(info.brewTime),
        Size = UDim2.new(0, 100, 0, 18),
        Position = UDim2.new(0, 80, 0, 56),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    -- Housing space
    local spaceLabel = Components.CreateLabel({
        Name = "Space",
        Text = "Space: " .. info.housingSpace,
        Size = UDim2.new(0, 80, 0, 18),
        Position = UDim2.new(0, 190, 0, 56),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    -- Brew button
    local brewButton = Components.CreateButton({
        Name = "BrewButton",
        Text = "Brew",
        Size = UDim2.new(0, 80, 0, 40),
        Position = UDim2.new(1, -20, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor = info.color,
        OnClick = function()
            ClientAPI.BrewSpell(spellType)
            SpellBrewingUI.SpellSelected:Fire(spellType)
        end,
        Parent = card,
    })

    return card
end

--[[
    Creates the brewing queue display.
]]
local function createQueueDisplay(parent: Frame): Frame
    local container = Components.CreateFrame({
        Name = "QueueContainer",
        Size = UDim2.new(1, -32, 0, 100),
        Position = UDim2.new(0.5, 0, 0, 60),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- Queue label
    local queueLabel = Components.CreateLabel({
        Name = "QueueLabel",
        Text = "Brewing Queue",
        Size = UDim2.new(1, -16, 0, 24),
        Position = UDim2.new(0, 8, 0, 8),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container,
    })

    -- Queue slots container
    local slotsContainer = Components.CreateFrame({
        Name = "Slots",
        Size = UDim2.new(1, -16, 0, 50),
        Position = UDim2.new(0, 8, 0, 36),
        BackgroundTransparency = 1,
        Parent = container,
    })

    local listLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        Parent = slotsContainer,
    })

    return container
end

--[[
    Creates the spell inventory display.
]]
local function createInventoryDisplay(parent: Frame): Frame
    local container = Components.CreateFrame({
        Name = "InventoryContainer",
        Size = UDim2.new(1, -32, 0, 80),
        Position = UDim2.new(0.5, 0, 0, 170),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- Inventory label
    local invLabel = Components.CreateLabel({
        Name = "InventoryLabel",
        Text = "Spell Inventory (0/0)",
        Size = UDim2.new(1, -16, 0, 24),
        Position = UDim2.new(0, 8, 0, 8),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container,
    })

    -- Spell slots
    local slotsContainer = Components.CreateFrame({
        Name = "Slots",
        Size = UDim2.new(1, -16, 0, 40),
        Position = UDim2.new(0, 8, 0, 34),
        BackgroundTransparency = 1,
        Parent = container,
    })

    local listLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 4),
        Parent = slotsContainer,
    })

    return container
end

--[[
    Creates a queue slot item.
]]
local function createQueueSlot(spellType: string, timeRemaining: number, index: number, parent: Frame): Frame
    local info = SpellInfo[spellType]
    if not info then return Instance.new("Frame") end

    local slot = Components.CreateFrame({
        Name = "Slot_" .. index,
        Size = UDim2.new(0, 50, 0, 50),
        BackgroundColor = info.color,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    local iconLabel = Components.CreateLabel({
        Name = "Icon",
        Text = info.icon,
        Size = UDim2.new(1, 0, 0.6, 0),
        TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = slot,
    })

    local timeLabel = Components.CreateLabel({
        Name = "Time",
        Text = formatTime(timeRemaining),
        Size = UDim2.new(1, 0, 0.4, 0),
        Position = UDim2.new(0, 0, 0.6, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = slot,
    })

    -- Cancel button (small X)
    local cancelButton = Instance.new("TextButton")
    cancelButton.Name = "Cancel"
    cancelButton.Size = UDim2.new(0, 16, 0, 16)
    cancelButton.Position = UDim2.new(1, -2, 0, 2)
    cancelButton.AnchorPoint = Vector2.new(1, 0)
    cancelButton.BackgroundColor3 = Components.Colors.Danger
    cancelButton.TextColor3 = Color3.new(1, 1, 1)
    cancelButton.Text = "X"
    cancelButton.TextSize = 10
    cancelButton.Font = Enum.Font.GothamBold
    cancelButton.Parent = slot

    local cancelCorner = Instance.new("UICorner")
    cancelCorner.CornerRadius = UDim.new(0.5, 0)
    cancelCorner.Parent = cancelButton

    cancelButton.MouseButton1Click:Connect(function()
        ClientAPI.CancelSpellBrewing(index)
    end)

    return slot
end

--[[
    Creates an inventory spell slot.
]]
local function createInventorySlot(spellType: string, count: number, parent: Frame): Frame
    local info = SpellInfo[spellType]
    if not info then return Instance.new("Frame") end

    local slot = Components.CreateFrame({
        Name = spellType,
        Size = UDim2.new(0, 40, 0, 40),
        BackgroundColor = info.color,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    local iconLabel = Components.CreateLabel({
        Name = "Icon",
        Text = info.icon,
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = slot,
    })

    -- Count badge
    local countBadge = Components.CreateFrame({
        Name = "Count",
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(1, -2, 1, -2),
        AnchorPoint = Vector2.new(1, 1),
        BackgroundColor = Components.Colors.Background,
        CornerRadius = UDim.new(0.5, 0),
        Parent = slot,
    })

    local countLabel = Components.CreateLabel({
        Name = "CountText",
        Text = tostring(count),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = 10,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = countBadge,
    })

    return slot
end

--[[
    Refreshes the queue display.
]]
function SpellBrewingUI:RefreshQueue()
    if not _queueContainer then return end

    local slotsContainer = _queueContainer:FindFirstChild("Slots")
    if not slotsContainer then return end

    -- Clear existing slots
    for _, child in slotsContainer:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    -- Get queue from server
    local queue = ClientAPI.GetSpellQueue()
    if queue then
        local now = os.time()
        for i, item in queue do
            local elapsed = now - item.startTime
            local remaining = math.max(0, item.brewTime - elapsed)
            createQueueSlot(item.spellType, remaining, i, slotsContainer)
        end
    end
end

--[[
    Refreshes the inventory display.
]]
function SpellBrewingUI:RefreshInventory()
    if not _inventoryContainer then return end

    local slotsContainer = _inventoryContainer:FindFirstChild("Slots")
    local invLabel = _inventoryContainer:FindFirstChild("InventoryLabel") :: TextLabel?
    if not slotsContainer then return end

    -- Clear existing slots
    for _, child in slotsContainer:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    -- Get player data for spells
    local playerData = ClientAPI.GetPlayerData()
    if playerData and playerData.spells then
        local totalSpace = 0
        local maxSpace = 10 -- Would come from spell factory level

        for spellType, count in playerData.spells do
            if count > 0 then
                createInventorySlot(spellType, count, slotsContainer)
                local info = SpellInfo[spellType]
                if info then
                    totalSpace += info.housingSpace * count
                end
            end
        end

        if invLabel then
            invLabel.Text = string.format("Spell Inventory (%d/%d)", totalSpace, maxSpace)
        end
    end
end

--[[
    Refreshes all UI elements.
]]
function SpellBrewingUI:Refresh()
    self:RefreshQueue()
    self:RefreshInventory()
end

--[[
    Shows the spell brewing UI.
]]
function SpellBrewingUI:Show()
    if _screenGui then
        _screenGui.Enabled = true

        -- Animate in
        if _mainFrame then
            _mainFrame.Position = UDim2.new(0.5, 0, 1.5, 0)
            TweenService:Create(_mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Position = UDim2.new(0.5, 0, 0.5, 0)
            }):Play()
        end

        self:Refresh()
    end
end

--[[
    Hides the spell brewing UI.
]]
function SpellBrewingUI:Hide()
    if _screenGui and _mainFrame then
        local tween = TweenService:Create(_mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, 0, 1.5, 0)
        })
        tween:Play()
        tween.Completed:Connect(function()
            if _screenGui then
                _screenGui.Enabled = false
            end
        end)
    end
end

--[[
    Checks if the UI is visible.
]]
function SpellBrewingUI:IsVisible(): boolean
    return _screenGui and _screenGui.Enabled or false
end

--[[
    Initializes the SpellBrewingUI.
]]
function SpellBrewingUI:Init()
    if _initialized then
        warn("SpellBrewingUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "SpellBrewingUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.DisplayOrder = 50
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Create main panel
    _mainFrame = Components.CreateFrame({
        Name = "MainFrame",
        Size = UDim2.new(0.7, 0, 0.8, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor = Components.Colors.Background,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        Parent = _screenGui,
    })

    -- Add border
    local stroke = Instance.new("UIStroke")
    stroke.Color = Components.Colors.Primary
    stroke.Thickness = 2
    stroke.Parent = _mainFrame

    -- Header
    local header = Components.CreateLabel({
        Name = "Header",
        Text = "Spell Factory",
        Size = UDim2.new(1, 0, 0, 50),
        Position = UDim2.new(0, 0, 0, 8),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = _mainFrame,
    })

    -- Close button
    local closeButton = Components.CreateButton({
        Name = "CloseButton",
        Text = "X",
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(1, -12, 0, 12),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor = Components.Colors.Danger,
        OnClick = function()
            self:Hide()
            SpellBrewingUI.CloseRequested:Fire()
        end,
        Parent = _mainFrame,
    })

    -- Queue display
    _queueContainer = createQueueDisplay(_mainFrame)

    -- Inventory display
    _inventoryContainer = createInventoryDisplay(_mainFrame)

    -- Spell list container
    local listContainer = Components.CreateFrame({
        Name = "SpellListContainer",
        Size = UDim2.new(1, -32, 1, -290),
        Position = UDim2.new(0.5, 0, 0, 260),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = _mainFrame,
    })

    _spellListContainer = Instance.new("ScrollingFrame")
    _spellListContainer.Name = "SpellList"
    _spellListContainer.Size = UDim2.new(1, -8, 1, -8)
    _spellListContainer.Position = UDim2.new(0, 4, 0, 4)
    _spellListContainer.BackgroundTransparency = 1
    _spellListContainer.BorderSizePixel = 0
    _spellListContainer.ScrollBarThickness = 6
    _spellListContainer.ScrollBarImageColor3 = Components.Colors.Secondary
    _spellListContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    _spellListContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    _spellListContainer.Parent = listContainer

    local listLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 8),
        Parent = _spellListContainer,
    })

    -- Create spell cards
    for spellType in SpellInfo do
        createSpellCard(spellType, _spellListContainer)
    end

    -- Listen for spell brewing complete
    local Events = ReplicatedStorage:WaitForChild("Events")
    Events.SpellBrewingComplete.OnClientEvent:Connect(function(data)
        if self:IsVisible() then
            self:Refresh()
        end
    end)

    Events.ServerResponse.OnClientEvent:Connect(function(action, result)
        if (action == "BrewSpell" or action == "CancelSpellBrewing") and self:IsVisible() then
            self:Refresh()
        end
    end)

    -- Auto-refresh queue timer
    task.spawn(function()
        while true do
            task.wait(1)
            if self:IsVisible() then
                self:RefreshQueue()
            end
        end
    end)

    _initialized = true
    print("SpellBrewingUI initialized")
end

return SpellBrewingUI
