--!strict
--[[
    DefenseLogUI.lua

    Displays the history of attacks on the player's base.
    Shows attacker info, stars earned, and loot stolen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local DefenseLogUI = {}
DefenseLogUI.__index = DefenseLogUI

-- Events
DefenseLogUI.CloseRequested = Signal.new()
DefenseLogUI.RevengeRequested = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _logContainer: ScrollingFrame? = nil
local _initialized = false

--[[
    Formats a number with commas.
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
    Formats a timestamp to relative time.
]]
local function formatTimeAgo(timestamp: number): string
    local now = os.time()
    local diff = now - timestamp

    if diff < 60 then
        return "Just now"
    elseif diff < 3600 then
        local mins = math.floor(diff / 60)
        return mins .. "m ago"
    elseif diff < 86400 then
        local hours = math.floor(diff / 3600)
        return hours .. "h ago"
    else
        local days = math.floor(diff / 86400)
        return days .. "d ago"
    end
end

--[[
    Creates a star display.
]]
local function createStars(parent: Frame, stars: number): Frame
    local container = Components.CreateFrame({
        Name = "Stars",
        Size = UDim2.new(0, 60, 0, 20),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local listLayout = Instance.new("UIListLayout")
    listLayout.FillDirection = Enum.FillDirection.Horizontal
    listLayout.Padding = UDim.new(0, 2)
    listLayout.Parent = container

    for i = 1, 3 do
        local starLabel = Components.CreateLabel({
            Name = "Star" .. i,
            Text = i <= stars and "★" or "☆",
            Size = UDim2.new(0, 18, 0, 20),
            TextColor = i <= stars and Components.Colors.Warning or Components.Colors.TextSecondary,
            TextSize = 16,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = container,
        })
    end

    return container
end

--[[
    Creates a defense log entry.
]]
local function createLogEntry(data: {
    attackerName: string,
    attackerId: number,
    stars: number,
    destruction: number,
    goldStolen: number,
    trophyChange: number,
    timestamp: number,
    canRevenge: boolean?,
}, parent: ScrollingFrame): Frame
    local entry = Components.CreateFrame({
        Name = "Entry_" .. data.timestamp,
        Size = UDim2.new(1, -16, 0, 90),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- Result indicator (red for loss, orange for draw, etc)
    local resultIndicator = Components.CreateFrame({
        Name = "ResultIndicator",
        Size = UDim2.new(0, 6, 1, 0),
        BackgroundColor = data.stars >= 2 and Components.Colors.Danger or Components.Colors.Warning,
        CornerRadius = UDim.new(0, 3),
        Parent = entry,
    })

    -- Attacker info
    local attackerLabel = Components.CreateLabel({
        Name = "Attacker",
        Text = data.attackerName,
        Size = UDim2.new(0.4, 0, 0, 24),
        Position = UDim2.new(0, 20, 0, 10),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = entry,
    })

    -- Time ago
    local timeLabel = Components.CreateLabel({
        Name = "Time",
        Text = formatTimeAgo(data.timestamp),
        Size = UDim2.new(0, 80, 0, 18),
        Position = UDim2.new(0, 20, 0, 34),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = entry,
    })

    -- Stars earned against player
    local starsContainer = createStars(entry, data.stars)
    starsContainer.Position = UDim2.new(0, 20, 0, 56)

    -- Destruction percentage
    local destructionLabel = Components.CreateLabel({
        Name = "Destruction",
        Text = math.floor(data.destruction) .. "%",
        Size = UDim2.new(0, 50, 0, 20),
        Position = UDim2.new(0, 90, 0, 56),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = entry,
    })

    -- Loot stolen
    local lootContainer = Components.CreateFrame({
        Name = "Loot",
        Size = UDim2.new(0, 100, 0, 50),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Parent = entry,
    })

    local goldLostLabel = Components.CreateLabel({
        Name = "GoldLost",
        Text = "-" .. formatNumber(data.goldStolen) .. " Gold",
        Size = UDim2.new(1, 0, 0, 18),
        TextColor = Components.Colors.Danger,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = lootContainer,
    })

    -- Trophy change
    local trophyColor = data.trophyChange >= 0 and Components.Colors.Success or Components.Colors.Danger
    local trophyPrefix = data.trophyChange >= 0 and "+" or ""

    local trophyLabel = Components.CreateLabel({
        Name = "Trophies",
        Text = trophyPrefix .. data.trophyChange .. " Trophies",
        Size = UDim2.new(1, 0, 0, 18),
        Position = UDim2.new(0, 0, 0, 22),
        TextColor = trophyColor,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = lootContainer,
    })

    -- Revenge button (if available)
    if data.canRevenge then
        local revengeButton = Components.CreateButton({
            Name = "RevengeButton",
            Text = "Revenge!",
            Size = UDim2.new(0, 80, 0, 36),
            Position = UDim2.new(1, -16, 0.5, 0),
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundColor = Components.Colors.Danger,
            OnClick = function()
                DefenseLogUI.RevengeRequested:Fire(data.attackerId)
            end,
            Parent = entry,
        })
    else
        local revengedLabel = Components.CreateLabel({
            Name = "RevengedLabel",
            Text = "Revenged",
            Size = UDim2.new(0, 80, 0, 36),
            Position = UDim2.new(1, -16, 0.5, 0),
            AnchorPoint = Vector2.new(1, 0.5),
            TextColor = Components.Colors.TextSecondary,
            TextSize = Components.Sizes.FontSizeSmall,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = entry,
        })
    end

    return entry
end

--[[
    Refreshes the defense log.
]]
function DefenseLogUI:Refresh()
    if not _logContainer then return end

    -- Clear existing entries
    for _, child in _logContainer:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    -- Get player data for defense log
    local playerData = ClientAPI.GetPlayerData()
    if playerData and playerData.defenseLog then
        -- Sort by timestamp descending (most recent first)
        local sortedLog = table.clone(playerData.defenseLog)
        table.sort(sortedLog, function(a, b)
            return a.timestamp > b.timestamp
        end)

        for _, entry in sortedLog do
            createLogEntry(entry, _logContainer)
        end

        if #sortedLog == 0 then
            local emptyLabel = Components.CreateLabel({
                Name = "Empty",
                Text = "No attacks on your base yet!",
                Size = UDim2.new(1, 0, 0, 50),
                TextColor = Components.Colors.TextSecondary,
                TextSize = Components.Sizes.FontSizeMedium,
                Font = Enum.Font.Gotham,
                TextXAlignment = Enum.TextXAlignment.Center,
                Parent = _logContainer,
            })
        end
    else
        local emptyLabel = Components.CreateLabel({
            Name = "Empty",
            Text = "No attacks on your base yet!",
            Size = UDim2.new(1, 0, 0, 50),
            TextColor = Components.Colors.TextSecondary,
            TextSize = Components.Sizes.FontSizeMedium,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = _logContainer,
        })
    end
end

--[[
    Shows the defense log UI.
]]
function DefenseLogUI:Show()
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
    Hides the defense log UI.
]]
function DefenseLogUI:Hide()
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
function DefenseLogUI:IsVisible(): boolean
    return _screenGui and _screenGui.Enabled or false
end

--[[
    Initializes the DefenseLogUI.
]]
function DefenseLogUI:Init()
    if _initialized then
        warn("DefenseLogUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "DefenseLogUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.DisplayOrder = 50
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Create main panel
    _mainFrame = Components.CreateFrame({
        Name = "MainFrame",
        Size = UDim2.new(0.6, 0, 0.7, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor = Components.Colors.Background,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        Parent = _screenGui,
    })

    -- Add border
    local stroke = Instance.new("UIStroke")
    stroke.Color = Components.Colors.Danger
    stroke.Thickness = 2
    stroke.Parent = _mainFrame

    -- Header
    local header = Components.CreateLabel({
        Name = "Header",
        Text = "Defense Log",
        Size = UDim2.new(1, 0, 0, 50),
        Position = UDim2.new(0, 0, 0, 8),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = _mainFrame,
    })

    -- Subheader
    local subheader = Components.CreateLabel({
        Name = "Subheader",
        Text = "Recent attacks on your base",
        Size = UDim2.new(1, 0, 0, 24),
        Position = UDim2.new(0, 0, 0, 48),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
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
            DefenseLogUI.CloseRequested:Fire()
        end,
        Parent = _mainFrame,
    })

    -- Log container
    local logContainerFrame = Components.CreateFrame({
        Name = "LogContainerFrame",
        Size = UDim2.new(1, -32, 1, -120),
        Position = UDim2.new(0.5, 0, 0, 85),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = _mainFrame,
    })

    _logContainer = Instance.new("ScrollingFrame")
    _logContainer.Name = "LogContainer"
    _logContainer.Size = UDim2.new(1, -8, 1, -8)
    _logContainer.Position = UDim2.new(0, 4, 0, 4)
    _logContainer.BackgroundTransparency = 1
    _logContainer.BorderSizePixel = 0
    _logContainer.ScrollBarThickness = 6
    _logContainer.ScrollBarImageColor3 = Components.Colors.Secondary
    _logContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    _logContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    _logContainer.Parent = logContainerFrame

    local listLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 8),
        Parent = _logContainer,
    })

    _initialized = true
    print("DefenseLogUI initialized")
end

return DefenseLogUI
