--!strict
--[[
    QuestsUI.lua

    Displays daily quests and achievements.
    Shows progress, rewards, and allows claiming completed quests.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local QuestsUI = {}
QuestsUI.__index = QuestsUI

-- Events
QuestsUI.CloseRequested = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _questsContainer: Frame? = nil
local _achievementsContainer: Frame? = nil
local _currentTab = "daily"
local _initialized = false

-- Tab constants
local TAB_DAILY = "daily"
local TAB_ACHIEVEMENTS = "achievements"

--[[
    Formats a reward for display.
]]
local function formatReward(reward: {gold: number?, gems: number?, xp: number?}): string
    local parts = {}
    if reward.gold and reward.gold > 0 then
        table.insert(parts, reward.gold .. " Gold")
    end
    if reward.gems and reward.gems > 0 then
        table.insert(parts, reward.gems .. " Gems")
    end
    if reward.xp and reward.xp > 0 then
        table.insert(parts, reward.xp .. " XP")
    end
    return table.concat(parts, " + ")
end

--[[
    Creates a quest card widget.
]]
local function createQuestCard(questData: any, parent: Frame): Frame
    local quest = questData.quest
    local progress = questData.progress or 0
    local completed = questData.completed or false
    local claimed = questData.claimed or false

    local card = Components.CreateFrame({
        Name = quest.id,
        Size = UDim2.new(1, -16, 0, 80),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- Add border based on status
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    if claimed then
        stroke.Color = Components.Colors.Secondary
        stroke.Transparency = 0.5
    elseif completed then
        stroke.Color = Components.Colors.Success
    else
        stroke.Color = Components.Colors.BackgroundLight
        stroke.Transparency = 0.8
    end
    stroke.Parent = card

    -- Left icon container
    local iconContainer = Components.CreateFrame({
        Name = "Icon",
        Size = UDim2.new(0, 60, 0, 60),
        Position = UDim2.new(0, 10, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = completed and Components.Colors.Success or Components.Colors.Secondary,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = card,
    })

    local iconLabel = Components.CreateLabel({
        Name = "IconText",
        Text = completed and "✓" or "Q",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = 24,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconContainer,
    })

    -- Quest info
    local titleLabel = Components.CreateLabel({
        Name = "Title",
        Text = quest.title,
        Size = UDim2.new(0.5, 0, 0, 24),
        Position = UDim2.new(0, 80, 0, 10),
        TextColor = claimed and Color3.fromRGB(128, 128, 128) or Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    local descLabel = Components.CreateLabel({
        Name = "Description",
        Text = quest.description,
        Size = UDim2.new(0.5, 0, 0, 20),
        Position = UDim2.new(0, 80, 0, 34),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    -- Progress bar
    local progressBarBg = Components.CreateFrame({
        Name = "ProgressBarBg",
        Size = UDim2.new(0.4, 0, 0, 8),
        Position = UDim2.new(0, 80, 0, 58),
        BackgroundColor = Components.Colors.Background,
        CornerRadius = UDim.new(0, 4),
        Parent = card,
    })

    local progressPercent = math.clamp(progress / quest.target, 0, 1)
    local progressBar = Components.CreateFrame({
        Name = "ProgressBar",
        Size = UDim2.new(progressPercent, 0, 1, 0),
        BackgroundColor = completed and Components.Colors.Success or Components.Colors.Primary,
        CornerRadius = UDim.new(0, 4),
        Parent = progressBarBg,
    })

    local progressLabel = Components.CreateLabel({
        Name = "ProgressText",
        Text = string.format("%d/%d", math.min(progress, quest.target), quest.target),
        Size = UDim2.new(0, 60, 0, 16),
        Position = UDim2.new(1, 8, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = progressBarBg,
    })

    -- Reward display
    local rewardLabel = Components.CreateLabel({
        Name = "Reward",
        Text = formatReward(quest.reward),
        Size = UDim2.new(0, 120, 0, 20),
        Position = UDim2.new(1, -140, 0, 12),
        TextColor = Components.Colors.Warning,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = card,
    })

    -- Claim button (if completed but not claimed)
    if completed and not claimed then
        local claimButton = Components.CreateButton({
            Name = "ClaimButton",
            Text = "Claim",
            Size = UDim2.new(0, 80, 0, 32),
            Position = UDim2.new(1, -20, 0.5, 0),
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundColor = Components.Colors.Success,
            OnClick = function()
                ClientAPI.ClaimQuestReward(quest.id)
            end,
            Parent = card,
        })
    elseif claimed then
        local claimedLabel = Components.CreateLabel({
            Name = "ClaimedLabel",
            Text = "Claimed",
            Size = UDim2.new(0, 80, 0, 32),
            Position = UDim2.new(1, -20, 0.5, 0),
            AnchorPoint = Vector2.new(1, 0.5),
            TextColor = Components.Colors.TextSecondary,
            TextSize = Components.Sizes.FontSizeSmall,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = card,
        })
    end

    return card
end

--[[
    Creates the tab buttons.
]]
local function createTabs(parent: Frame): Frame
    local tabContainer = Components.CreateFrame({
        Name = "Tabs",
        Size = UDim2.new(1, -32, 0, 44),
        Position = UDim2.new(0.5, 0, 0, 60),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local listLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 8),
        Parent = tabContainer,
    })

    -- Daily tab
    local dailyTab = Components.CreateButton({
        Name = "DailyTab",
        Text = "Daily Quests",
        Size = UDim2.new(0, 140, 0, 40),
        BackgroundColor = _currentTab == TAB_DAILY and Components.Colors.Primary or Components.Colors.BackgroundLight,
        OnClick = function()
            QuestsUI:SwitchTab(TAB_DAILY)
        end,
        Parent = tabContainer,
    })

    -- Achievements tab
    local achievementsTab = Components.CreateButton({
        Name = "AchievementsTab",
        Text = "Achievements",
        Size = UDim2.new(0, 140, 0, 40),
        BackgroundColor = _currentTab == TAB_ACHIEVEMENTS and Components.Colors.Primary or Components.Colors.BackgroundLight,
        OnClick = function()
            QuestsUI:SwitchTab(TAB_ACHIEVEMENTS)
        end,
        Parent = tabContainer,
    })

    return tabContainer
end

--[[
    Creates the quests content container.
]]
local function createQuestsContainer(parent: Frame): Frame
    local container = Components.CreateFrame({
        Name = "QuestsContainer",
        Size = UDim2.new(1, -32, 1, -180),
        Position = UDim2.new(0.5, 0, 0, 120),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.Background,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- Add scrolling frame
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "ScrollFrame"
    scrollFrame.Size = UDim2.new(1, -8, 1, -8)
    scrollFrame.Position = UDim2.new(0, 4, 0, 4)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 6
    scrollFrame.ScrollBarImageColor3 = Components.Colors.Secondary
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollFrame.Parent = container

    local listLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 8),
        Parent = scrollFrame,
    })

    return scrollFrame
end

--[[
    Refreshes the quest list.
]]
function QuestsUI:RefreshQuests()
    if not _questsContainer then return end

    -- Clear existing cards
    for _, child in _questsContainer:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    -- Get daily quests
    local quests = ClientAPI.GetDailyQuests()
    if quests then
        for questId, questData in quests do
            createQuestCard(questData, _questsContainer)
        end
    end
end

--[[
    Refreshes the achievements list.
]]
function QuestsUI:RefreshAchievements()
    if not _achievementsContainer then return end

    -- Clear existing cards
    for _, child in _achievementsContainer:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    -- Get achievements
    local achievements = ClientAPI.GetAchievements()
    if achievements then
        for achId, achData in achievements do
            createQuestCard(achData, _achievementsContainer)
        end
    end
end

--[[
    Switches between tabs.
]]
function QuestsUI:SwitchTab(tab: string)
    _currentTab = tab

    if _questsContainer then
        _questsContainer.Visible = tab == TAB_DAILY
    end
    if _achievementsContainer then
        _achievementsContainer.Visible = tab == TAB_ACHIEVEMENTS
    end

    -- Update tab button colors
    if _mainFrame then
        local tabs = _mainFrame:FindFirstChild("Tabs")
        if tabs then
            local dailyTab = tabs:FindFirstChild("DailyTab") :: TextButton?
            local achTab = tabs:FindFirstChild("AchievementsTab") :: TextButton?

            if dailyTab then
                dailyTab.BackgroundColor3 = tab == TAB_DAILY and Components.Colors.Primary or Components.Colors.BackgroundLight
            end
            if achTab then
                achTab.BackgroundColor3 = tab == TAB_ACHIEVEMENTS and Components.Colors.Primary or Components.Colors.BackgroundLight
            end
        end
    end

    -- Refresh the visible tab
    if tab == TAB_DAILY then
        self:RefreshQuests()
    else
        self:RefreshAchievements()
    end
end

--[[
    Shows the quests UI.
]]
function QuestsUI:Show()
    if _screenGui then
        _screenGui.Enabled = true

        -- Animate in
        if _mainFrame then
            _mainFrame.Position = UDim2.new(0.5, 0, 1.5, 0)
            TweenService:Create(_mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Position = UDim2.new(0.5, 0, 0.5, 0)
            }):Play()
        end

        -- Refresh current tab
        if _currentTab == TAB_DAILY then
            self:RefreshQuests()
        else
            self:RefreshAchievements()
        end
    end
end

--[[
    Hides the quests UI.
]]
function QuestsUI:Hide()
    if _screenGui and _mainFrame then
        -- Animate out
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
function QuestsUI:IsVisible(): boolean
    return _screenGui and _screenGui.Enabled or false
end

--[[
    Initializes the QuestsUI.
]]
function QuestsUI:Init()
    if _initialized then
        warn("QuestsUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "QuestsUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.DisplayOrder = 50
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Create main panel
    _mainFrame = Components.CreateFrame({
        Name = "MainFrame",
        Size = UDim2.new(0.7, 0, 0.75, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor = Components.Colors.Background,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        Parent = _screenGui,
    })

    -- Add border
    local stroke = Instance.new("UIStroke")
    stroke.Color = Components.Colors.Secondary
    stroke.Thickness = 2
    stroke.Parent = _mainFrame

    -- Header
    local header = Components.CreateLabel({
        Name = "Header",
        Text = "Quests & Achievements",
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
            QuestsUI.CloseRequested:Fire()
        end,
        Parent = _mainFrame,
    })

    -- Create tabs
    createTabs(_mainFrame)

    -- Create containers
    _questsContainer = createQuestsContainer(_mainFrame)
    _achievementsContainer = createQuestsContainer(_mainFrame)
    _achievementsContainer.Name = "AchievementsContainer"
    _achievementsContainer.Visible = false

    -- Listen for quest updates
    local Events = ReplicatedStorage:WaitForChild("Events")

    Events.QuestCompleted.OnClientEvent:Connect(function(data)
        -- Refresh the list when a quest is completed
        if _currentTab == TAB_DAILY and not data.isAchievement then
            self:RefreshQuests()
        elseif _currentTab == TAB_ACHIEVEMENTS and data.isAchievement then
            self:RefreshAchievements()
        end
    end)

    Events.ServerResponse.OnClientEvent:Connect(function(action, result)
        if action == "ClaimQuestReward" and result.success then
            -- Refresh after claiming
            if _currentTab == TAB_DAILY then
                self:RefreshQuests()
            else
                self:RefreshAchievements()
            end
        end
    end)

    _initialized = true
    print("QuestsUI initialized")
end

return QuestsUI
