--!strict
--[[
    TroopTraining.lua

    Troop training interface for barracks buildings.
    Shows available troops and training queue.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Components = require(script.Parent.Components)
local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local TroopTraining = {}
TroopTraining.__index = TroopTraining

-- Events
TroopTraining.Closed = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _panel: Frame
local _troopGrid: ScrollingFrame
local _queueContainer: Frame
local _isVisible = false
local _initialized = false
local _updateConnection: RBXScriptConnection?

-- Cache
local _troopCards: {Frame} = {}
local _queueItems: {Frame} = {}

--[[
    Formats time for display.
]]
local function formatTime(seconds: number): string
    if seconds <= 0 then return "Ready" end

    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)

    if mins > 0 then
        return string.format("%dm %ds", mins, secs)
    else
        return string.format("%ds", secs)
    end
end

--[[
    Formats a number for display.
]]
local function formatNumber(value: number): string
    if value >= 1000 then
        return string.format("%.1fK", value / 1000)
    else
        return tostring(math.floor(value))
    end
end

--[[
    Creates a troop card for selection.
]]
local function createTroopCard(troopDef: any, parent: GuiObject): Frame
    local card = Components.CreateFrame({
        Name = troopDef.type,
        Size = UDim2.new(0, 90, 0, 120),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = Components.Colors.PanelBorder,
        Parent = parent,
    })

    -- Icon
    local iconBg = Components.CreateFrame({
        Name = "Icon",
        Size = UDim2.new(0, 50, 0, 50),
        Position = UDim2.new(0.5, 0, 0, 8),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.Primary,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = card,
    })

    local iconLabel = Components.CreateLabel({
        Name = "IconText",
        Text = string.sub(troopDef.name, 1, 2),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Name
    local nameLabel = Components.CreateLabel({
        Name = "Name",
        Text = troopDef.name,
        Size = UDim2.new(1, -8, 0, 16),
        Position = UDim2.new(0, 4, 0, 62),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = card,
    })

    -- Cost
    local levelData = troopDef.levels[1]
    local costText = ""
    if levelData.cost.food then
        costText = formatNumber(levelData.cost.food) .. " F"
    end

    local costLabel = Components.CreateLabel({
        Name = "Cost",
        Text = costText,
        Size = UDim2.new(1, -8, 0, 14),
        Position = UDim2.new(0, 4, 0, 78),
        TextColor = Components.Colors.Food,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = card,
    })

    -- Train button
    local trainButton = Components.CreateButton({
        Name = "TrainButton",
        Text = "Train",
        Size = UDim2.new(1, -16, 0, 22),
        Position = UDim2.new(0.5, 0, 1, -8),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = Components.Colors.Secondary,
        TextSize = Components.Sizes.FontSizeSmall,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        OnClick = function()
            ClientAPI.TrainTroop(troopDef.type, 1)
        end,
        Parent = card,
    })

    return card
end

--[[
    Creates a queue item display.
]]
local function createQueueItem(queueData: any, index: number, parent: GuiObject): Frame
    local troopDef = TroopData.GetByType(queueData.troopType)
    local name = troopDef and troopDef.name or queueData.troopType

    local item = Components.CreateFrame({
        Name = "QueueItem" .. index,
        Size = UDim2.new(0, 60, 0, 70),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = parent,
    })

    -- Icon
    local iconBg = Components.CreateFrame({
        Name = "Icon",
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0.5, 0, 0, 4),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.Primary,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = item,
    })

    local iconLabel = Components.CreateLabel({
        Name = "IconText",
        Text = string.sub(name, 1, 2),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Quantity badge
    if queueData.quantity > 1 then
        local qtyBadge = Components.CreateFrame({
            Name = "Qty",
            Size = UDim2.new(0, 20, 0, 16),
            Position = UDim2.new(1, -2, 0, 2),
            AnchorPoint = Vector2.new(1, 0),
            BackgroundColor = Components.Colors.Secondary,
            CornerRadius = Components.Sizes.CornerRadiusSmall,
            Parent = item,
        })

        local qtyLabel = Components.CreateLabel({
            Name = "QtyText",
            Text = "x" .. queueData.quantity,
            Size = UDim2.new(1, 0, 1, 0),
            TextColor = Components.Colors.TextPrimary,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = qtyBadge,
        })
    end

    -- Progress or time
    local timeRemaining = queueData.completesAt - os.time()
    local timeLabel = Components.CreateLabel({
        Name = "Time",
        Text = formatTime(math.max(0, timeRemaining)),
        Size = UDim2.new(1, -4, 0, 14),
        Position = UDim2.new(0, 2, 1, -2),
        AnchorPoint = Vector2.new(0, 1),
        TextColor = timeRemaining > 0 and Components.Colors.Warning or Components.Colors.Success,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = item,
    })

    -- Cancel button (only for first item)
    if index == 1 then
        local cancelButton = Instance.new("TextButton")
        cancelButton.Name = "Cancel"
        cancelButton.Size = UDim2.new(0, 16, 0, 16)
        cancelButton.Position = UDim2.new(0, 2, 0, 2)
        cancelButton.BackgroundColor3 = Components.Colors.Danger
        cancelButton.Text = "X"
        cancelButton.TextColor3 = Components.Colors.TextPrimary
        cancelButton.TextSize = 10
        cancelButton.Font = Enum.Font.GothamBold
        cancelButton.BorderSizePixel = 0
        cancelButton.Parent = item

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = cancelButton

        cancelButton.MouseButton1Click:Connect(function()
            ClientAPI.CancelTraining(index)
        end)
    end

    return item
end

--[[
    Populates the troop grid.
]]
local function populateTroopGrid()
    -- Clear existing
    for _, card in _troopCards do
        card:Destroy()
    end
    _troopCards = {}

    -- Get all available troops
    local allTroops = TroopData.GetAll()

    for _, troopDef in allTroops do
        local card = createTroopCard(troopDef, _troopGrid)
        table.insert(_troopCards, card)
    end
end

--[[
    Updates the training queue display.
]]
function TroopTraining:UpdateQueue(queue: {any})
    -- Clear existing
    for _, item in _queueItems do
        item:Destroy()
    end
    _queueItems = {}

    if not queue or #queue == 0 then
        local emptyLabel = Components.CreateLabel({
            Name = "Empty",
            Text = "No troops training",
            Size = UDim2.new(1, 0, 1, 0),
            TextColor = Components.Colors.TextMuted,
            TextSize = Components.Sizes.FontSizeSmall,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = _queueContainer,
        })
        table.insert(_queueItems, emptyLabel :: any)
        return
    end

    for i, queueData in queue do
        local item = createQueueItem(queueData, i, _queueContainer)
        table.insert(_queueItems, item)
    end
end

--[[
    Shows the training UI.
]]
function TroopTraining:Show()
    if _isVisible then return end
    _isVisible = true

    populateTroopGrid()

    _screenGui.Enabled = true
    Components.SlideIn(_panel, "bottom")

    -- Start update loop
    _updateConnection = RunService.Heartbeat:Connect(function()
        if _isVisible then
            -- Refresh queue times
            local playerData = ClientAPI.GetPlayerData()
            if playerData then
                -- Get training queue from player data if available
                -- For now, just keep the UI responsive
            end
        end
    end)
end

--[[
    Hides the training UI.
]]
function TroopTraining:Hide()
    if not _isVisible then return end
    _isVisible = false

    if _updateConnection then
        _updateConnection:Disconnect()
        _updateConnection = nil
    end

    Components.SlideOut(_panel, "bottom")
    task.delay(0.3, function()
        if not _isVisible then
            _screenGui.Enabled = false
        end
    end)

    TroopTraining.Closed:Fire()
end

--[[
    Toggles visibility.
]]
function TroopTraining:Toggle()
    if _isVisible then
        self:Hide()
    else
        self:Show()
    end
end

--[[
    Checks if visible.
]]
function TroopTraining:IsVisible(): boolean
    return _isVisible
end

--[[
    Initializes the TroopTraining UI.
]]
function TroopTraining:Init()
    if _initialized then
        warn("TroopTraining already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "TroopTraining"
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
        Name = "TrainingPanel",
        Title = "Train Troops",
        Size = UDim2.new(1, -32, 0, 450),
        Position = UDim2.new(0.5, 0, 1, -16),
        AnchorPoint = Vector2.new(0.5, 1),
        ShowCloseButton = true,
        OnClose = function()
            self:Hide()
        end,
        Parent = _screenGui,
    })

    local content = _panel:FindFirstChild("Content") :: Frame

    -- Army info bar
    local armyBar = Components.CreateFrame({
        Name = "ArmyBar",
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = content,
    })

    local armyLabel = Components.CreateLabel({
        Name = "ArmyInfo",
        Text = "Army: 0/20",
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = armyBar,
    })

    -- Queue section
    local queueLabel = Components.CreateLabel({
        Name = "QueueTitle",
        Text = "Training Queue",
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 0, 38),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = content,
    })

    _queueContainer = Components.CreateFrame({
        Name = "Queue",
        Size = UDim2.new(1, 0, 0, 80),
        Position = UDim2.new(0, 0, 0, 58),
        BackgroundTransparency = 1,
        Parent = content,
    })

    local queueLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 4),
        Parent = _queueContainer,
    })

    -- Available troops section
    local availableLabel = Components.CreateLabel({
        Name = "AvailableTitle",
        Text = "Available Troops",
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 0, 146),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = content,
    })

    _troopGrid = Components.CreateScrollFrame({
        Name = "TroopGrid",
        Size = UDim2.new(1, 0, 1, -176),
        Position = UDim2.new(0, 0, 0, 166),
        Parent = content,
    })

    local gridLayout = Components.CreateGridLayout({
        CellSize = UDim2.new(0, 90, 0, 120),
        CellPadding = UDim2.new(0, 8, 0, 8),
        Parent = _troopGrid,
    })

    _initialized = true
    print("TroopTraining initialized")
end

return TroopTraining
