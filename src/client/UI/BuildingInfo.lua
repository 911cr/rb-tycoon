--!strict
--[[
    BuildingInfo.lua

    Panel showing details about a selected building.
    Allows upgrading, collecting resources, and viewing stats.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Components = require(script.Parent.Components)
local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local BuildingInfo = {}
BuildingInfo.__index = BuildingInfo

-- Events
BuildingInfo.UpgradeRequested = Signal.new()
BuildingInfo.CollectRequested = Signal.new()
BuildingInfo.SpeedUpRequested = Signal.new()
BuildingInfo.Closed = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _panel: Frame
local _currentBuildingId: string?
local _currentBuildingData: any?
local _isVisible = false
local _initialized = false
local _updateConnection: RBXScriptConnection?

-- UI element references
local _titleLabel: TextLabel
local _levelLabel: TextLabel
local _descLabel: TextLabel
local _upgradeButton: TextButton
local _collectButton: TextButton
local _speedUpButton: TextButton
local _timerLabel: TextLabel
local _progressBar: Frame
local _statsContainer: Frame

--[[
    Formats time for display.
]]
local function formatTime(seconds: number): string
    if seconds <= 0 then
        return "Ready"
    end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)

    if hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, secs)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
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
    Creates a stat row.
]]
local function createStatRow(name: string, value: string, parent: GuiObject): Frame
    local row = Components.CreateFrame({
        Name = name .. "Row",
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local nameLabel = Components.CreateLabel({
        Name = "Name",
        Text = name,
        Size = UDim2.new(0.5, 0, 1, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = row,
    })

    local valueLabel = Components.CreateLabel({
        Name = "Value",
        Text = value,
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row,
    })

    return row
end

--[[
    Updates the panel with building data.
]]
local function updatePanel()
    if not _currentBuildingData or not _currentBuildingId then
        return
    end

    local building = _currentBuildingData
    local buildingDef = BuildingData.GetByType(building.type)

    if not buildingDef then
        return
    end

    local levelData = buildingDef.levels[building.level]
    local nextLevelData = buildingDef.levels[building.level + 1]

    -- Update title and level
    _titleLabel.Text = buildingDef.name
    _levelLabel.Text = "Level " .. building.level

    -- Update description
    _descLabel.Text = buildingDef.description or ""

    -- Update stats
    for _, child in _statsContainer:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    if levelData.production then
        createStatRow("Production", formatNumber(levelData.production) .. "/hr", _statsContainer)
    end
    if levelData.capacity then
        createStatRow("Capacity", formatNumber(levelData.capacity), _statsContainer)
    end
    if levelData.hitpoints then
        createStatRow("Hitpoints", formatNumber(levelData.hitpoints), _statsContainer)
    end
    if levelData.damage then
        createStatRow("Damage", formatNumber(levelData.damage), _statsContainer)
    end
    if levelData.range then
        createStatRow("Range", tostring(levelData.range), _statsContainer)
    end

    -- Update buttons based on state
    local now = os.time()
    local isUpgrading = building.upgradeCompletesAt and building.upgradeCompletesAt > now
    local hasResources = building.storedResources and (building.storedResources.gold or 0) > 0

    -- Upgrade button
    if isUpgrading then
        _upgradeButton.Visible = false
        _speedUpButton.Visible = true
        _timerLabel.Visible = true

        local remaining = building.upgradeCompletesAt - now
        _timerLabel.Text = formatTime(remaining)

        -- Update progress bar
        if levelData.buildTime then
            local total = levelData.buildTime
            local elapsed = total - remaining
            local progress = math.clamp(elapsed / total, 0, 1)
            local fill = _progressBar:FindFirstChild("Fill") :: Frame
            if fill then
                fill.Size = UDim2.new(progress, 0, 1, 0)
            end
        end
        _progressBar.Visible = true
    else
        _upgradeButton.Visible = true
        _speedUpButton.Visible = false
        _timerLabel.Visible = false
        _progressBar.Visible = false

        if nextLevelData then
            local costText = ""
            if nextLevelData.cost.gold then
                costText = formatNumber(nextLevelData.cost.gold) .. " Gold"
            end
            _upgradeButton.Text = "Upgrade (" .. costText .. ")"
        else
            _upgradeButton.Text = "Max Level"
            _upgradeButton.BackgroundColor3 = Components.Colors.ButtonDisabled
        end
    end

    -- Collect button
    if hasResources and buildingDef.category == "Resources" then
        _collectButton.Visible = true
        local stored = building.storedResources.gold or building.storedResources.wood or building.storedResources.food or 0
        _collectButton.Text = "Collect (" .. formatNumber(stored) .. ")"
    else
        _collectButton.Visible = false
    end
end

--[[
    Shows the panel for a building.
]]
function BuildingInfo:Show(buildingId: string, buildingData: any)
    _currentBuildingId = buildingId
    _currentBuildingData = buildingData
    _isVisible = true

    updatePanel()

    _screenGui.Enabled = true
    Components.SlideIn(_panel, "bottom")

    -- Start update loop for timers
    _updateConnection = RunService.Heartbeat:Connect(function()
        if _isVisible then
            updatePanel()
        end
    end)
end

--[[
    Hides the panel.
]]
function BuildingInfo:Hide()
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

    _currentBuildingId = nil
    _currentBuildingData = nil

    BuildingInfo.Closed:Fire()
end

--[[
    Updates building data while panel is open.
]]
function BuildingInfo:UpdateBuilding(buildingData: any)
    if not _isVisible then return end
    _currentBuildingData = buildingData
    updatePanel()
end

--[[
    Checks if panel is visible.
]]
function BuildingInfo:IsVisible(): boolean
    return _isVisible
end

--[[
    Gets the current building ID.
]]
function BuildingInfo:GetCurrentBuildingId(): string?
    return _currentBuildingId
end

--[[
    Initializes the BuildingInfo panel.
]]
function BuildingInfo:Init()
    if _initialized then
        warn("BuildingInfo already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "BuildingInfo"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Main panel
    _panel = Components.CreatePanel({
        Name = "BuildingInfoPanel",
        Title = "Building",
        Size = UDim2.new(0, 320, 0, 360),
        Position = UDim2.new(0.5, 0, 1, -100),
        AnchorPoint = Vector2.new(0.5, 1),
        ShowCloseButton = true,
        OnClose = function()
            self:Hide()
        end,
        Parent = _screenGui,
    })

    local content = _panel:FindFirstChild("Content") :: Frame
    local titleBar = _panel:FindFirstChild("TitleBar") :: Frame

    -- Title label (replaces default)
    _titleLabel = titleBar:FindFirstChild("Title") :: TextLabel

    -- Level label
    _levelLabel = Components.CreateLabel({
        Name = "Level",
        Text = "Level 1",
        Size = UDim2.new(0, 80, 0, 24),
        Position = UDim2.new(1, -56, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = titleBar,
    })

    -- Description
    _descLabel = Components.CreateLabel({
        Name = "Description",
        Text = "",
        Size = UDim2.new(1, 0, 0, 36),
        Position = UDim2.new(0, 0, 0, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = content,
    })
    _descLabel.TextWrapped = true

    -- Stats container
    _statsContainer = Components.CreateFrame({
        Name = "Stats",
        Size = UDim2.new(1, 0, 0, 100),
        Position = UDim2.new(0, 0, 0, 44),
        BackgroundTransparency = 1,
        Parent = content,
    })

    local statsLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 4),
        Parent = _statsContainer,
    })

    -- Progress bar for upgrades
    _progressBar = Components.CreateProgressBar({
        Name = "UpgradeProgress",
        Size = UDim2.new(1, 0, 0, 8),
        Position = UDim2.new(0, 0, 0, 152),
        FillColor = Components.Colors.Secondary,
        Parent = content,
    })
    _progressBar.Visible = false

    -- Timer label
    _timerLabel = Components.CreateLabel({
        Name = "Timer",
        Text = "",
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 0, 164),
        TextColor = Components.Colors.Warning,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = content,
    })
    _timerLabel.Visible = false

    -- Action buttons container
    local actionsContainer = Components.CreateFrame({
        Name = "Actions",
        Size = UDim2.new(1, 0, 0, 50),
        Position = UDim2.new(0, 0, 1, 0),
        AnchorPoint = Vector2.new(0, 1),
        BackgroundTransparency = 1,
        Parent = content,
    })

    local actionsLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 8),
        Parent = actionsContainer,
    })

    -- Upgrade button
    _upgradeButton = Components.CreateButton({
        Name = "UpgradeButton",
        Text = "Upgrade",
        Size = UDim2.new(0, 140, 0, 40),
        BackgroundColor = Components.Colors.Secondary,
        OnClick = function()
            if _currentBuildingId then
                ClientAPI.UpgradeBuilding(_currentBuildingId)
                BuildingInfo.UpgradeRequested:Fire(_currentBuildingId)
            end
        end,
        Parent = actionsContainer,
    })

    -- Speed up button
    _speedUpButton = Components.CreateButton({
        Name = "SpeedUpButton",
        Text = "Speed Up",
        Size = UDim2.new(0, 100, 0, 40),
        BackgroundColor = Components.Colors.Gems,
        OnClick = function()
            if _currentBuildingId then
                ClientAPI.SpeedUpUpgrade(_currentBuildingId)
                BuildingInfo.SpeedUpRequested:Fire(_currentBuildingId)
            end
        end,
        Parent = actionsContainer,
    })
    _speedUpButton.Visible = false

    -- Collect button
    _collectButton = Components.CreateButton({
        Name = "CollectButton",
        Text = "Collect",
        Size = UDim2.new(0, 100, 0, 40),
        BackgroundColor = Components.Colors.Gold,
        TextColor = Color3.new(0, 0, 0),
        OnClick = function()
            if _currentBuildingId then
                ClientAPI.CollectResources(_currentBuildingId)
                BuildingInfo.CollectRequested:Fire(_currentBuildingId)
            end
        end,
        Parent = actionsContainer,
    })
    _collectButton.Visible = false

    _initialized = true
    print("BuildingInfo initialized")
end

return BuildingInfo
