--!strict
--[[
    BattleUI.lua

    Combat interface for deploying troops and casting spells.
    Shows battle progress, timer, and troop selection bar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Components)
local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local BattleUI = {}
BattleUI.__index = BattleUI

-- Events
BattleUI.TroopSelected = Signal.new()
BattleUI.SpellSelected = Signal.new()
BattleUI.SurrenderRequested = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _topBar: Frame
local _troopBar: Frame
local _troopButtons: {[string]: Frame} = {}
local _isVisible = false
local _initialized = false
local _currentBattleId: string?

-- UI References
local _destructionLabel: TextLabel
local _timerLabel: TextLabel
local _starFrames: {Frame} = {}

--[[
    Formats time for battle timer.
]]
local function formatBattleTime(seconds: number): string
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", mins, secs)
end

--[[
    Creates the top battle info bar.
]]
local function createTopBar(parent: ScreenGui): Frame
    local bar = Components.CreateFrame({
        Name = "TopBar",
        Size = UDim2.new(1, 0, 0, 70),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor = Components.Colors.Background,
        BackgroundTransparency = 0.3,
        Parent = parent,
    })

    -- Gradient
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    gradient.Parent = bar

    -- Timer display
    local timerContainer = Components.CreateFrame({
        Name = "Timer",
        Size = UDim2.new(0, 100, 0, 50),
        Position = UDim2.new(0.5, 0, 0, 10),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = bar,
    })

    _timerLabel = Components.CreateLabel({
        Name = "Time",
        Text = "3:00",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeXLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = timerContainer,
    })

    -- Stars display
    local starsContainer = Components.CreateFrame({
        Name = "Stars",
        Size = UDim2.new(0, 120, 0, 40),
        Position = UDim2.new(0.5, 0, 0, 10),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Parent = bar,
    })
    starsContainer.Position = UDim2.new(0, 16, 0, 15)

    local starsLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 4),
        Parent = starsContainer,
    })

    for i = 1, 3 do
        local starFrame = Components.CreateFrame({
            Name = "Star" .. i,
            Size = UDim2.new(0, 32, 0, 32),
            BackgroundColor = Components.Colors.BackgroundLight,
            CornerRadius = UDim.new(0.5, 0),
            Parent = starsContainer,
        })

        local starLabel = Components.CreateLabel({
            Name = "Icon",
            Text = "★",
            Size = UDim2.new(1, 0, 1, 0),
            TextColor = Components.Colors.TextMuted,
            TextSize = Components.Sizes.FontSizeLarge,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = starFrame,
        })

        _starFrames[i] = starFrame
    end

    -- Destruction percentage
    local destructionContainer = Components.CreateFrame({
        Name = "Destruction",
        Size = UDim2.new(0, 80, 0, 40),
        Position = UDim2.new(1, -16, 0, 15),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = bar,
    })

    _destructionLabel = Components.CreateLabel({
        Name = "Percent",
        Text = "0%",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.Danger,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = destructionContainer,
    })

    return bar
end

--[[
    Creates a troop button for the troop bar.
]]
local function createTroopButton(troopType: string, count: number, parent: GuiObject): Frame
    local troopDef = TroopData.GetByType(troopType)
    if not troopDef then
        return Instance.new("Frame") -- Return empty frame
    end

    local button = Components.CreateFrame({
        Name = troopType,
        Size = UDim2.new(0, 70, 0, 80),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = Components.Colors.PanelBorder,
        Parent = parent,
    })

    -- Icon
    local iconBg = Components.CreateFrame({
        Name = "Icon",
        Size = UDim2.new(0, 50, 0, 50),
        Position = UDim2.new(0.5, 0, 0, 4),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.Primary,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = button,
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

    -- Count badge
    local countBadge = Components.CreateFrame({
        Name = "Count",
        Size = UDim2.new(0, 24, 0, 18),
        Position = UDim2.new(1, -2, 0, 2),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor = Components.Colors.Secondary,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = button,
    })

    local countLabel = Components.CreateLabel({
        Name = "CountText",
        Text = tostring(count),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = countBadge,
    })

    -- Make clickable
    local clickButton = Instance.new("TextButton")
    clickButton.Name = "ClickArea"
    clickButton.Size = UDim2.new(1, 0, 1, 0)
    clickButton.BackgroundTransparency = 1
    clickButton.Text = ""
    clickButton.Parent = button

    clickButton.MouseButton1Click:Connect(function()
        BattleUI.TroopSelected:Fire(troopType)
    end)

    return button
end

--[[
    Creates the bottom troop selection bar.
]]
local function createTroopBar(parent: ScreenGui): Frame
    local bar = Components.CreateFrame({
        Name = "TroopBar",
        Size = UDim2.new(1, 0, 0, 100),
        Position = UDim2.new(0, 0, 1, 0),
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor = Components.Colors.Background,
        BackgroundTransparency = 0.3,
        Parent = parent,
    })

    -- Gradient
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = -90
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    gradient.Parent = bar

    -- Troop scroll container
    local troopScroll = Components.CreateScrollFrame({
        Name = "TroopScroll",
        Size = UDim2.new(1, -100, 0, 90),
        Position = UDim2.new(0, 8, 0, 5),
        Parent = bar,
    })
    troopScroll.ScrollingDirection = Enum.ScrollingDirection.X

    local troopLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = troopScroll,
    })

    -- Surrender button
    local surrenderButton = Components.CreateButton({
        Name = "SurrenderButton",
        Text = "End",
        Size = UDim2.new(0, 70, 0, 50),
        Position = UDim2.new(1, -16, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor = Components.Colors.Danger,
        OnClick = function()
            BattleUI.SurrenderRequested:Fire()
        end,
        Parent = bar,
    })

    return bar
end

--[[
    Updates the star display based on earned stars.
]]
function BattleUI:UpdateStars(starsEarned: number)
    for i, frame in _starFrames do
        local label = frame:FindFirstChild("Icon") :: TextLabel
        if label then
            if i <= starsEarned then
                label.TextColor3 = Components.Colors.Warning
            else
                label.TextColor3 = Components.Colors.TextMuted
            end
        end
    end
end

--[[
    Updates the destruction percentage.
]]
function BattleUI:UpdateDestruction(percent: number)
    if _destructionLabel then
        _destructionLabel.Text = math.floor(percent) .. "%"
    end
end

--[[
    Updates the battle timer.
]]
function BattleUI:UpdateTimer(secondsRemaining: number)
    if _timerLabel then
        _timerLabel.Text = formatBattleTime(secondsRemaining)

        -- Change color when low
        if secondsRemaining <= 30 then
            _timerLabel.TextColor3 = Components.Colors.Danger
        else
            _timerLabel.TextColor3 = Components.Colors.TextPrimary
        end
    end
end

--[[
    Updates the troop bar with available troops.
]]
function BattleUI:UpdateTroops(troops: {[string]: number})
    -- Clear existing buttons
    local troopScroll = _troopBar:FindFirstChild("TroopScroll") :: ScrollingFrame
    if not troopScroll then return end

    for _, child in troopScroll:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    _troopButtons = {}

    -- Create buttons for each troop type
    for troopType, count in troops do
        if count > 0 then
            local button = createTroopButton(troopType, count, troopScroll)
            _troopButtons[troopType] = button
        end
    end
end

--[[
    Shows the battle UI.
]]
function BattleUI:Show(battleId: string)
    _currentBattleId = battleId
    _isVisible = true

    -- Reset display
    self:UpdateStars(0)
    self:UpdateDestruction(0)
    self:UpdateTimer(180) -- 3 minutes default

    _screenGui.Enabled = true
    Components.SlideIn(_topBar, "top")
    Components.SlideIn(_troopBar, "bottom")
end

--[[
    Hides the battle UI.
]]
function BattleUI:Hide()
    if not _isVisible then return end
    _isVisible = false

    Components.SlideOut(_topBar, "top")
    Components.SlideOut(_troopBar, "bottom")

    task.delay(0.3, function()
        if not _isVisible then
            _screenGui.Enabled = false
        end
    end)

    _currentBattleId = nil
end

--[[
    Checks if UI is visible.
]]
function BattleUI:IsVisible(): boolean
    return _isVisible
end

--[[
    Initializes the BattleUI.
]]
function BattleUI:Init()
    if _initialized then
        warn("BattleUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "BattleUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Create UI elements
    _topBar = createTopBar(_screenGui)
    _troopBar = createTroopBar(_screenGui)

    -- Listen for battle state updates
    local Events = ReplicatedStorage:WaitForChild("Events")

    Events.BattleTick.OnClientEvent:Connect(function(state)
        if _isVisible and state.battleId == _currentBattleId then
            self:UpdateTimer(state.timeRemaining or 0)
            self:UpdateDestruction(state.destruction or 0)
            self:UpdateStars(state.starsEarned or 0)
        end
    end)

    Events.BattleEnded.OnClientEvent:Connect(function(result)
        if _isVisible then
            -- Show final state briefly before hiding
            self:UpdateStars(result.stars or 0)
            self:UpdateDestruction(result.destruction or 0)

            task.delay(2, function()
                self:Hide()
            end)
        end
    end)

    _initialized = true
    print("BattleUI initialized")
end

return BattleUI
