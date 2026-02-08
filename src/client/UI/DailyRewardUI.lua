--!strict
--[[
    DailyRewardUI.lua

    Displays the daily login reward calendar and streak bonuses.
    Shows 7-day reward cycle and allows claiming daily reward.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local DailyRewardUI = {}
DailyRewardUI.__index = DailyRewardUI

-- Events
DailyRewardUI.CloseRequested = Signal.new()
DailyRewardUI.RewardClaimed = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _calendarFrame: Frame? = nil
local _claimButton: TextButton? = nil
local _streakLabel: TextLabel? = nil
local _initialized = false

-- Reward cycle (matches server DailyRewardService)
local DailyRewards = {
    [1] = { gold = 1000, gems = 0, description = "Day 1" },
    [2] = { gold = 2000, gems = 0, description = "Day 2" },
    [3] = { gold = 0, gems = 5, description = "Day 3" },
    [4] = { gold = 3000, gems = 0, description = "Day 4" },
    [5] = { gold = 2000, gems = 3, description = "Day 5" },
    [6] = { gold = 0, gems = 10, description = "Day 6" },
    [7] = { gold = 5000, gems = 20, description = "Day 7 Jackpot!" },
}

--[[
    Formats a reward for display.
]]
local function formatReward(reward: {gold: number?, gems: number?}): string
    local parts = {}
    if reward.gold and reward.gold > 0 then
        if reward.gold >= 1000 then
            table.insert(parts, string.format("%.0fK Gold", reward.gold / 1000))
        else
            table.insert(parts, reward.gold .. " Gold")
        end
    end
    if reward.gems and reward.gems > 0 then
        table.insert(parts, reward.gems .. " Gems")
    end
    return table.concat(parts, "\n")
end

--[[
    Creates a reward card for a day in the cycle.
]]
local function createRewardCard(day: number, parent: Frame, currentDay: number, canClaim: boolean): Frame
    local reward = DailyRewards[day]
    local isPast = day < currentDay
    local isToday = day == currentDay
    local isFuture = day > currentDay

    local card = Components.CreateFrame({
        Name = "Day" .. day,
        Size = UDim2.new(0, 90, 0, 110),
        BackgroundColor = isToday and Components.Colors.Primary or Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- Add glow for today
    if isToday and canClaim then
        local glow = Instance.new("UIStroke")
        glow.Color = Components.Colors.Warning
        glow.Thickness = 3
        glow.Parent = card

        -- Pulse animation
        task.spawn(function()
            while card.Parent and isToday do
                TweenService:Create(glow, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    Transparency = 0.5
                }):Play()
                task.wait(0.8)
                TweenService:Create(glow, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    Transparency = 0
                }):Play()
                task.wait(0.8)
            end
        end)
    elseif isPast then
        local stroke = Instance.new("UIStroke")
        stroke.Color = Components.Colors.Success
        stroke.Thickness = 2
        stroke.Parent = card
    end

    -- Day label
    local dayLabel = Components.CreateLabel({
        Name = "DayLabel",
        Text = "Day " .. day,
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 0, 6),
        TextColor = isPast and Components.Colors.TextSecondary or Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = card,
    })

    -- Reward icon/display
    local iconBg = Components.CreateFrame({
        Name = "IconBg",
        Size = UDim2.new(0, 50, 0, 50),
        Position = UDim2.new(0.5, 0, 0, 28),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = isPast and Components.Colors.Success or (reward.gems > 0 and Components.Colors.Gems or Components.Colors.Gold),
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = card,
    })

    local iconText = Components.CreateLabel({
        Name = "IconText",
        Text = isPast and "✓" or (reward.gems > 0 and "G" or "C"),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = 20,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Reward amount
    local rewardLabel = Components.CreateLabel({
        Name = "RewardLabel",
        Text = formatReward(reward),
        Size = UDim2.new(1, -4, 0, 28),
        Position = UDim2.new(0.5, 0, 1, -4),
        AnchorPoint = Vector2.new(0.5, 1),
        TextColor = isPast and Components.Colors.TextSecondary or Components.Colors.TextPrimary,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextWrapped = true,
        Parent = card,
    })

    return card
end

--[[
    Creates the streak display.
]]
local function createStreakDisplay(parent: Frame): Frame
    local container = Components.CreateFrame({
        Name = "StreakDisplay",
        Size = UDim2.new(1, -32, 0, 60),
        Position = UDim2.new(0.5, 0, 0, 60),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- Streak icon
    local iconBg = Components.CreateFrame({
        Name = "StreakIcon",
        Size = UDim2.new(0, 44, 0, 44),
        Position = UDim2.new(0, 10, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = Components.Colors.Warning,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = container,
    })

    local fireLabel = Components.CreateLabel({
        Name = "FireIcon",
        Text = "🔥",
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 24,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Streak info
    local titleLabel = Components.CreateLabel({
        Name = "Title",
        Text = "Login Streak",
        Size = UDim2.new(0, 200, 0, 20),
        Position = UDim2.new(0, 64, 0, 10),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container,
    })

    _streakLabel = Components.CreateLabel({
        Name = "StreakCount",
        Text = "0 Days",
        Size = UDim2.new(0, 200, 0, 28),
        Position = UDim2.new(0, 64, 0, 28),
        TextColor = Components.Colors.Warning,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container,
    })

    -- Next milestone
    local milestoneLabel = Components.CreateLabel({
        Name = "Milestone",
        Text = "Next: 7-day bonus",
        Size = UDim2.new(0, 200, 0, 20),
        Position = UDim2.new(1, -20, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = container,
    })

    return container
end

--[[
    Creates the calendar grid.
]]
local function createCalendar(parent: Frame): Frame
    local container = Components.CreateFrame({
        Name = "Calendar",
        Size = UDim2.new(1, -32, 0, 130),
        Position = UDim2.new(0.5, 0, 0, 130),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local listLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),
        Parent = container,
    })

    return container
end

--[[
    Refreshes the UI with current reward info.
]]
function DailyRewardUI:Refresh()
    local info = ClientAPI.GetDailyRewardInfo()
    if not info then return end

    -- Update streak display
    if _streakLabel then
        _streakLabel.Text = info.streak .. " Days"
    end

    -- Update milestone display
    if _mainFrame then
        local streakDisplay = _mainFrame:FindFirstChild("StreakDisplay")
        if streakDisplay then
            local milestoneLabel = streakDisplay:FindFirstChild("Milestone") :: TextLabel?
            if milestoneLabel then
                if info.nextMilestone then
                    milestoneLabel.Text = "Next bonus: Day " .. info.nextMilestone
                else
                    milestoneLabel.Text = "Max streak reached!"
                end
            end
        end
    end

    -- Rebuild calendar
    if _calendarFrame then
        for _, child in _calendarFrame:GetChildren() do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end

        local currentDayInCycle = ((info.streak - 1) % 7) + 1
        if info.canClaim then
            -- If can claim, show the day they would claim
            currentDayInCycle = info.streak > 0 and (info.streak % 7) or 0
            currentDayInCycle = currentDayInCycle == 0 and 7 or currentDayInCycle
        end

        for i = 1, 7 do
            createRewardCard(i, _calendarFrame, currentDayInCycle, info.canClaim and i == currentDayInCycle)
        end
    end

    -- Update claim button
    if _claimButton then
        _claimButton.Visible = info.canClaim
        if info.canClaim and info.todayReward then
            local rewardText = ""
            if info.todayReward.gold then
                rewardText = info.todayReward.gold .. " Gold"
            end
            if info.todayReward.gems then
                if #rewardText > 0 then rewardText = rewardText .. " + " end
                rewardText = rewardText .. info.todayReward.gems .. " Gems"
            end
            _claimButton.Text = "Claim: " .. rewardText
        end
    end
end

--[[
    Shows the daily reward UI.
]]
function DailyRewardUI:Show()
    if _screenGui then
        _screenGui.Enabled = true

        -- Animate in
        if _mainFrame then
            _mainFrame.Position = UDim2.new(0.5, 0, -0.5, 0)
            TweenService:Create(_mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Position = UDim2.new(0.5, 0, 0.5, 0)
            }):Play()
        end

        self:Refresh()
    end
end

--[[
    Hides the daily reward UI.
]]
function DailyRewardUI:Hide()
    if _screenGui and _mainFrame then
        local tween = TweenService:Create(_mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, 0, -0.5, 0)
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
function DailyRewardUI:IsVisible(): boolean
    return _screenGui and _screenGui.Enabled or false
end

--[[
    Shows the UI automatically if player can claim reward.
]]
function DailyRewardUI:CheckAndShow()
    local info = ClientAPI.GetDailyRewardInfo()
    if info and info.canClaim then
        task.delay(2, function() -- Short delay after login
            self:Show()
        end)
    end
end

--[[
    Initializes the DailyRewardUI.
]]
function DailyRewardUI:Init()
    if _initialized then
        warn("DailyRewardUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "DailyRewardUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.DisplayOrder = 100 -- High priority (shows on login)
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Create main panel
    _mainFrame = Components.CreateFrame({
        Name = "MainFrame",
        Size = UDim2.new(0, 720, 0, 380),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor = Components.Colors.Background,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        Parent = _screenGui,
    })

    -- Add border
    local stroke = Instance.new("UIStroke")
    stroke.Color = Components.Colors.Warning
    stroke.Thickness = 3
    stroke.Parent = _mainFrame

    -- Header
    local header = Components.CreateLabel({
        Name = "Header",
        Text = "Daily Rewards",
        Size = UDim2.new(1, 0, 0, 50),
        Position = UDim2.new(0, 0, 0, 8),
        TextColor = Components.Colors.Warning,
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
            DailyRewardUI.CloseRequested:Fire()
        end,
        Parent = _mainFrame,
    })

    -- Create streak display
    createStreakDisplay(_mainFrame)

    -- Create calendar
    _calendarFrame = createCalendar(_mainFrame)

    -- Claim button
    _claimButton = Components.CreateButton({
        Name = "ClaimButton",
        Text = "Claim Reward",
        Size = UDim2.new(0, 200, 0, 50),
        Position = UDim2.new(0.5, 0, 1, -25),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = Components.Colors.Success,
        OnClick = function()
            ClientAPI.ClaimDailyReward()
        end,
        Parent = _mainFrame,
    }) :: TextButton

    -- Listen for reward claimed
    local Events = ReplicatedStorage:WaitForChild("Events")
    Events.DailyRewardClaimed.OnClientEvent:Connect(function(data)
        -- Refresh UI after claiming
        self:Refresh()

        -- Auto-hide after a delay
        task.delay(2, function()
            if self:IsVisible() then
                self:Hide()
            end
        end)

        DailyRewardUI.RewardClaimed:Fire(data)
    end)

    _initialized = true
    print("DailyRewardUI initialized")
end

return DailyRewardUI
