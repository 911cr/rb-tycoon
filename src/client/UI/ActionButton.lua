--!strict
--[[
    ActionButton.lua

    Fixed-position action button near the jump button for mobile-friendly
    instant interactions. Detects nearby ProximityPrompts via
    ProximityPromptService and fires ActionButtonPressed RemoteEvent on tap.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local ActionButton = {}

-- State
local _currentPrompt: ProximityPrompt? = nil
local _promptStack: {ProximityPrompt} = {} -- track multiple in-range prompts
local _screenGui: ScreenGui? = nil
local _buttonFrame: Frame? = nil
local _clickBtn: TextButton? = nil
local _actionLabel: TextLabel? = nil
local _iconLabel: TextLabel? = nil
local _visible = false

-- Colors (matching Components.Colors medieval theme)
local COLORS = {
    Background = Color3.fromRGB(50, 45, 38),      -- BackgroundLight
    Border = Color3.fromRGB(184, 134, 11),         -- GoldDark
    Text = Color3.fromRGB(245, 235, 215),          -- TextPrimary
    TextGold = Color3.fromRGB(255, 215, 0),        -- TextGold
    Pressed = Color3.fromRGB(35, 30, 25),          -- Background (darker on press)
}

-- Action text to short icon label (Roblox doesn't render emoji)
local ACTION_ICONS: {[string]: string} = {
    ["Mine"] = "[*]",
    ["Mine Ore"] = "[*]",
    ["Chop"] = "[/]",
    ["Chop Tree"] = "[/]",
    ["Harvest"] = "{~}",
    ["Plant"] = "{.}",
    ["Plant Seeds"] = "{.}",
    ["Collect"] = "[$]",
    ["Enter"] = "[>]",
    ["Interact"] = "[!]",
    ["Upgrade"] = "[^]",
    ["Hire"] = "[+]",
}

local function getIconForAction(actionText: string): string
    -- Check exact match first
    if ACTION_ICONS[actionText] then
        return ACTION_ICONS[actionText]
    end
    -- Check partial match (case insensitive)
    local lowerAction = string.lower(actionText)
    for key, icon in ACTION_ICONS do
        if string.find(lowerAction, string.lower(key)) then
            return icon
        end
    end
    return "[!]" -- default
end

local function setVisible(show: boolean)
    if show == _visible then return end
    _visible = show

    local frame = _buttonFrame
    if not frame then return end

    if show then
        frame.Visible = true
        -- Fade in: tween from transparent to opaque
        TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0.1,
        }):Play()
        if _iconLabel then
            TweenService:Create(_iconLabel, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
        end
        if _actionLabel then
            TweenService:Create(_actionLabel, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
        end
        if _clickBtn then
            _clickBtn.Active = true
        end
    else
        -- Fade out
        TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            BackgroundTransparency = 1,
        }):Play()
        if _iconLabel then
            TweenService:Create(_iconLabel, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
        end
        if _actionLabel then
            TweenService:Create(_actionLabel, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
        end
        if _clickBtn then
            _clickBtn.Active = false
        end
        task.delay(0.25, function()
            if not _visible and _buttonFrame then
                _buttonFrame.Visible = false
            end
        end)
    end
end

local function updateDisplay()
    if _currentPrompt then
        local actionText = _currentPrompt.ActionText or "Interact"
        if _actionLabel then
            _actionLabel.Text = actionText
        end
        if _iconLabel then
            _iconLabel.Text = getIconForAction(actionText)
        end
        setVisible(true)
    else
        setVisible(false)
    end
end

local function refreshCurrentPrompt()
    -- Pick the top of the stack (most recently shown)
    if #_promptStack > 0 then
        _currentPrompt = _promptStack[#_promptStack]
    else
        _currentPrompt = nil
    end
    updateDisplay()
end

function ActionButton:Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ActionButtonGui"
    screenGui.DisplayOrder = 10
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui
    _screenGui = screenGui

    -- Main container frame (visible background)
    local buttonFrame = Instance.new("Frame")
    buttonFrame.Name = "ActionButton"
    buttonFrame.Size = UDim2.new(0, 70, 0, 70)
    buttonFrame.Position = UDim2.new(1, -180, 1, -90)
    buttonFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    buttonFrame.BackgroundColor3 = COLORS.Background
    buttonFrame.BackgroundTransparency = 1 -- start invisible
    buttonFrame.Visible = false
    buttonFrame.Parent = screenGui
    _buttonFrame = buttonFrame

    -- Rounded corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = buttonFrame

    -- Gold border
    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.Border
    stroke.Thickness = 3
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = buttonFrame

    -- Icon label (top area)
    local iconLabel = Instance.new("TextLabel")
    iconLabel.Name = "Icon"
    iconLabel.Size = UDim2.new(1, 0, 0, 32)
    iconLabel.Position = UDim2.new(0, 0, 0, 4)
    iconLabel.BackgroundTransparency = 1
    iconLabel.Text = "[!]"
    iconLabel.TextTransparency = 1 -- start invisible
    iconLabel.TextSize = 22
    iconLabel.Font = Enum.Font.GothamBold
    iconLabel.TextColor3 = COLORS.TextGold
    iconLabel.Parent = buttonFrame
    _iconLabel = iconLabel

    -- Action text label (bottom area)
    local actionLabel = Instance.new("TextLabel")
    actionLabel.Name = "ActionText"
    actionLabel.Size = UDim2.new(1, -6, 0, 28)
    actionLabel.Position = UDim2.new(0, 3, 1, -30)
    actionLabel.BackgroundTransparency = 1
    actionLabel.Text = "Interact"
    actionLabel.TextTransparency = 1 -- start invisible
    actionLabel.TextSize = 11
    actionLabel.Font = Enum.Font.GothamBold
    actionLabel.TextColor3 = COLORS.Text
    actionLabel.TextTruncate = Enum.TextTruncate.AtEnd
    actionLabel.TextScaled = false
    actionLabel.Parent = buttonFrame
    _actionLabel = actionLabel

    -- Clickable button overlay (transparent, captures input)
    local clickBtn = Instance.new("TextButton")
    clickBtn.Name = "ClickCatcher"
    clickBtn.Size = UDim2.new(1, 0, 1, 0)
    clickBtn.BackgroundTransparency = 1
    clickBtn.Text = ""
    clickBtn.Active = false
    clickBtn.Parent = buttonFrame
    _clickBtn = clickBtn

    -- Handle tap/click
    clickBtn.MouseButton1Click:Connect(function()
        if not _currentPrompt then return end
        local targetPart = _currentPrompt.Parent
        if not targetPart then return end

        -- Visual press feedback
        buttonFrame.BackgroundColor3 = COLORS.Pressed
        task.delay(0.12, function()
            if _buttonFrame then
                _buttonFrame.BackgroundColor3 = COLORS.Background
            end
        end)

        -- Fire RemoteEvent to server
        local Events = ReplicatedStorage:FindFirstChild("Events")
        if not Events then return end
        local ActionButtonPressed = Events:FindFirstChild("ActionButtonPressed")
        if not ActionButtonPressed then return end
        (ActionButtonPressed :: RemoteEvent):FireServer(targetPart)
        print("[ActionButton] Fired action for:", _currentPrompt.ActionText)
    end)

    -- Connect ProximityPromptService to detect in-range prompts
    ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, _inputType)
        table.insert(_promptStack, prompt)
        refreshCurrentPrompt()
        print("[ActionButton] Prompt shown:", prompt.ActionText, "Stack size:", #_promptStack)
    end)

    ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
        local idx = table.find(_promptStack, prompt)
        if idx then
            table.remove(_promptStack, idx)
        end
        refreshCurrentPrompt()
    end)

    print("[ActionButton] Initialized - button ready, waiting for proximity prompts")
end

return ActionButton
