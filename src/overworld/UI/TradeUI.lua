--!strict
--[[
    TradeUI.lua

    Trading interface for player-to-player resource exchanges.
    Split-screen panel: left side = your offer, right side = your request.

    Two modes:
    1. Proposal mode: Player fills in what they offer and request, then proposes.
    2. Incoming mode: Player sees what another player offers/requests, and accepts or declines.

    Dependencies:
    - Signal (for events)

    Events:
    - TradeProposed(targetUserId, offering, requesting)
    - TradeAccepted(tradeId)
    - TradeDeclined(tradeId)
    - TradeCancelled(tradeId)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local TradeUI = {}
TradeUI.__index = TradeUI

-- ============================================================================
-- SIGNALS
-- ============================================================================

TradeUI.TradeProposed = Signal.new()  -- (targetUserId, offering, requesting)
TradeUI.TradeAccepted = Signal.new()  -- (tradeId)
TradeUI.TradeDeclined = Signal.new()  -- (tradeId)
TradeUI.TradeCancelled = Signal.new() -- (tradeId)

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _initialized = false
local _player = Players.LocalPlayer
local _playerGui: PlayerGui? = nil

local _screenGui: ScreenGui? = nil
local _proposalPanel: Frame? = nil
local _incomingPanel: Frame? = nil
local _resultPanel: Frame? = nil
local _currentTradeId: string? = nil
local _targetData: any? = nil
local _playerResources = { gold = 0, wood = 0, food = 0 }
local _targetResources = { gold = 0, wood = 0, food = 0 }

-- Proposal panel input values
local _offerValues = { gold = 0, wood = 0, food = 0 }
local _requestValues = { gold = 0, wood = 0, food = 0 }

-- Incoming panel countdown
local _incomingCountdownThread: thread? = nil

-- Result panel auto-hide
local _resultHideThread: thread? = nil

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local TRADE_THEME = {
    primary = Color3.fromRGB(40, 160, 140),      -- Teal primary
    primaryDark = Color3.fromRGB(25, 100, 90),    -- Teal dark
    primaryLight = Color3.fromRGB(60, 200, 170),  -- Teal light
    panelBg = Color3.fromRGB(30, 28, 25),         -- Dark panel background
    sectionBg = Color3.fromRGB(40, 38, 33),       -- Section background
    headerBg = Color3.fromRGB(35, 50, 48),        -- Header background
    textPrimary = Color3.fromRGB(240, 230, 200),  -- Primary text
    textSecondary = Color3.fromRGB(150, 140, 120),-- Secondary text
    textMuted = Color3.fromRGB(100, 95, 85),      -- Muted text
    goldColor = Color3.fromRGB(255, 200, 80),     -- Gold
    woodColor = Color3.fromRGB(139, 100, 60),     -- Wood
    foodColor = Color3.fromRGB(100, 180, 80),     -- Food
    acceptGreen = Color3.fromRGB(60, 160, 60),    -- Accept button
    declineRed = Color3.fromRGB(180, 60, 60),     -- Decline button
    cancelGray = Color3.fromRGB(100, 90, 80),     -- Cancel button
    successGreen = Color3.fromRGB(50, 180, 80),   -- Success result
    failureRed = Color3.fromRGB(200, 60, 60),     -- Failure result
}

local RESOURCE_STEP = 100
local RESOURCE_STEP_SHIFT = 1000
local TRADE_TIMEOUT = 60

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Formats a number with comma separators for readability.
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
    Checks if shift key is currently held.
]]
local function isShiftHeld(): boolean
    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

-- ============================================================================
-- UI CREATION - PROPOSAL PANEL
-- ============================================================================

--[[
    Creates a +/- resource input row.
    Returns the frame and a table with refs to update values.
]]
local function createResourceInput(
    name: string,
    color: Color3,
    parent: Frame,
    onChanged: (number) -> (),
    maxValue: number?
): (Frame, TextBox, TextLabel?)
    local clampMax = maxValue or 99999999999999

    local row = Instance.new("Frame")
    row.Name = name .. "Row"
    row.Size = UDim2.new(1, -16, 0, 36)
    row.BackgroundTransparency = 1
    row.Parent = parent

    -- Resource label
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(0, 50, 1, 0)
    label.Position = UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name .. ":"
    label.TextColor3 = color
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    -- Minus button
    local minusButton = Instance.new("TextButton")
    minusButton.Name = "MinusButton"
    minusButton.Size = UDim2.new(0, 30, 0, 30)
    minusButton.Position = UDim2.new(0, 55, 0.5, -15)
    minusButton.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
    minusButton.Text = "-"
    minusButton.TextColor3 = Color3.fromRGB(255, 180, 180)
    minusButton.TextSize = 18
    minusButton.Font = Enum.Font.GothamBold
    minusButton.BorderSizePixel = 0
    minusButton.Parent = row

    local minusCorner = Instance.new("UICorner")
    minusCorner.CornerRadius = UDim.new(0, 6)
    minusCorner.Parent = minusButton

    -- Value display (TextBox for direct typing)
    local valueLabel = Instance.new("TextBox")
    valueLabel.Name = "Value"
    valueLabel.Size = UDim2.new(0, 70, 0, 28)
    valueLabel.Position = UDim2.new(0, 90, 0.5, -14)
    valueLabel.BackgroundColor3 = Color3.fromRGB(50, 48, 42)
    valueLabel.BackgroundTransparency = 0.3
    valueLabel.Text = "0"
    valueLabel.PlaceholderText = "0"
    valueLabel.TextColor3 = TRADE_THEME.textPrimary
    valueLabel.TextSize = 16
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.ClearTextOnFocus = false
    valueLabel.BorderSizePixel = 0
    valueLabel.Parent = row

    local valueCorner = Instance.new("UICorner")
    valueCorner.CornerRadius = UDim.new(0, 4)
    valueCorner.Parent = valueLabel

    -- Plus button
    local plusButton = Instance.new("TextButton")
    plusButton.Name = "PlusButton"
    plusButton.Size = UDim2.new(0, 30, 0, 30)
    plusButton.Position = UDim2.new(0, 165, 0.5, -15)
    plusButton.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
    plusButton.Text = "+"
    plusButton.TextColor3 = Color3.fromRGB(180, 255, 180)
    plusButton.TextSize = 18
    plusButton.Font = Enum.Font.GothamBold
    plusButton.BorderSizePixel = 0
    plusButton.Parent = row

    local plusCorner = Instance.new("UICorner")
    plusCorner.CornerRadius = UDim.new(0, 6)
    plusCorner.Parent = plusButton

    -- Handle typed input
    valueLabel.FocusLost:Connect(function(_enterPressed)
        local parsed = tonumber(valueLabel.Text:gsub(",", "")) or 0
        parsed = math.clamp(math.floor(parsed), 0, clampMax)
        valueLabel.Text = formatNumber(parsed)
        onChanged(parsed)
    end)

    -- Wire buttons
    minusButton.MouseButton1Click:Connect(function()
        local step = if isShiftHeld() then RESOURCE_STEP_SHIFT else RESOURCE_STEP
        local current = tonumber(valueLabel.Text:gsub(",", "")) or 0
        local newVal = math.clamp(current - step, 0, clampMax)
        valueLabel.Text = formatNumber(newVal)
        onChanged(newVal)
    end)

    plusButton.MouseButton1Click:Connect(function()
        local step = if isShiftHeld() then RESOURCE_STEP_SHIFT else RESOURCE_STEP
        local current = tonumber(valueLabel.Text:gsub(",", "")) or 0
        local newVal = math.clamp(current + step, 0, clampMax)
        valueLabel.Text = formatNumber(newVal)
        onChanged(newVal)
    end)

    return row, valueLabel, nil
end

--[[
    Creates a resource display row (read-only, for incoming trades).
]]
local function createResourceDisplay(
    name: string,
    color: Color3,
    parent: Frame
): (Frame, TextLabel)
    local row = Instance.new("Frame")
    row.Name = name .. "Row"
    row.Size = UDim2.new(1, -16, 0, 30)
    row.BackgroundTransparency = 1
    row.Parent = parent

    -- Resource label
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(0, 60, 1, 0)
    label.Position = UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name .. ":"
    label.TextColor3 = color
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    -- Value display
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "Value"
    valueLabel.Size = UDim2.new(1, -70, 1, 0)
    valueLabel.Position = UDim2.new(0, 65, 0, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = "0"
    valueLabel.TextColor3 = TRADE_THEME.textPrimary
    valueLabel.TextSize = 16
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextXAlignment = Enum.TextXAlignment.Left
    valueLabel.Parent = row

    return row, valueLabel
end

--[[
    Creates a section frame (left or right column).
]]
local function createSection(title: string, parent: Frame, posX: number, width: number): Frame
    local section = Instance.new("Frame")
    section.Name = title:gsub(" ", "") .. "Section"
    section.Size = UDim2.new(0, width, 0, 220)
    section.Position = UDim2.new(0, posX, 0, 55)
    section.BackgroundColor3 = TRADE_THEME.sectionBg
    section.BorderSizePixel = 0
    section.Parent = parent

    local sectionCorner = Instance.new("UICorner")
    sectionCorner.CornerRadius = UDim.new(0, 8)
    sectionCorner.Parent = section

    local sectionStroke = Instance.new("UIStroke")
    sectionStroke.Color = TRADE_THEME.primaryDark
    sectionStroke.Thickness = 1
    sectionStroke.Parent = section

    -- Section title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, 30)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundColor3 = TRADE_THEME.headerBg
    titleLabel.Text = title
    titleLabel.TextColor3 = TRADE_THEME.primary
    titleLabel.TextSize = 13
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Parent = section

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 8)
    titleCorner.Parent = titleLabel

    -- Fix bottom corners of title
    local titleFix = Instance.new("Frame")
    titleFix.Name = "TitleFix"
    titleFix.Size = UDim2.new(1, 0, 0, 8)
    titleFix.Position = UDim2.new(0, 0, 1, -8)
    titleFix.BackgroundColor3 = TRADE_THEME.headerBg
    titleFix.BorderSizePixel = 0
    titleFix.Parent = titleLabel

    -- Content area
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, 0, 1, -35)
    content.Position = UDim2.new(0, 0, 0, 35)
    content.BackgroundTransparency = 1
    content.Parent = section

    local contentLayout = Instance.new("UIListLayout")
    contentLayout.FillDirection = Enum.FillDirection.Vertical
    contentLayout.Padding = UDim.new(0, 4)
    contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    contentLayout.Parent = content

    local contentPadding = Instance.new("UIPadding")
    contentPadding.PaddingTop = UDim.new(0, 6)
    contentPadding.PaddingLeft = UDim.new(0, 8)
    contentPadding.PaddingRight = UDim.new(0, 8)
    contentPadding.Parent = content

    return section
end

--[[
    Creates the proposal panel (for initiating a trade).
]]
local function createProposalPanel(parent: ScreenGui): Frame
    local overlay = Instance.new("Frame")
    overlay.Name = "ProposalOverlay"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 0.4
    overlay.Visible = false
    overlay.ZIndex = 10
    overlay.Parent = parent

    -- Close on overlay click
    local overlayButton = Instance.new("TextButton")
    overlayButton.Size = UDim2.new(1, 0, 1, 0)
    overlayButton.BackgroundTransparency = 1
    overlayButton.Text = ""
    overlayButton.ZIndex = 10
    overlayButton.Parent = overlay

    -- Main panel (TextButton to absorb clicks and prevent fall-through to overlay)
    local panel = Instance.new("TextButton")
    panel.Name = "ProposalPanel"
    panel.Size = UDim2.new(0, 520, 0, 380)
    panel.Position = UDim2.new(0.5, 0, 0.5, 0)
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.BackgroundColor3 = TRADE_THEME.panelBg
    panel.BorderSizePixel = 0
    panel.ZIndex = 11
    panel.Text = ""
    panel.AutoButtonColor = false
    panel.Parent = overlay

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 12)
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = TRADE_THEME.primary
    panelStroke.Thickness = 2
    panelStroke.Parent = panel

    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 45)
    title.BackgroundColor3 = TRADE_THEME.headerBg
    title.Text = "TRADE WITH Player"
    title.TextColor3 = TRADE_THEME.textPrimary
    title.TextSize = 20
    title.Font = Enum.Font.GothamBold
    title.ZIndex = 12
    title.Parent = panel

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 12)
    titleCorner.Parent = title

    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 12)
    titleFix.Position = UDim2.new(0, 0, 1, -12)
    titleFix.BackgroundColor3 = TRADE_THEME.headerBg
    titleFix.BorderSizePixel = 0
    titleFix.ZIndex = 12
    titleFix.Parent = title

    -- YOUR OFFER section (left)
    local offerSection = createSection("YOUR OFFER", panel, 15, 235)
    offerSection.ZIndex = 12

    -- Set ZIndex for all children
    for _, child in offerSection:GetDescendants() do
        if child:IsA("GuiObject") then
            child.ZIndex = 12
        end
    end

    local offerContent = offerSection:FindFirstChild("Content") :: Frame
    if offerContent then
        -- Gold input (maxValue = player's gold, resolved dynamically)
        local _, goldVal = createResourceInput("Gold", TRADE_THEME.goldColor, offerContent, function(newVal)
            _offerValues.gold = newVal
            local proposeBtn = panel:FindFirstChild("ProposeButton", true) :: TextButton?
            if proposeBtn then
                local hasValue = _offerValues.gold > 0 or _offerValues.wood > 0 or _offerValues.food > 0
                    or _requestValues.gold > 0 or _requestValues.wood > 0 or _requestValues.food > 0
                proposeBtn.BackgroundColor3 = if hasValue then TRADE_THEME.primary else TRADE_THEME.cancelGray
            end
        end)
        for _, c in goldVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 12 end end
        goldVal.Parent.ZIndex = 12

        -- Wood input
        local _, woodVal = createResourceInput("Wood", TRADE_THEME.woodColor, offerContent, function(newVal)
            _offerValues.wood = newVal
            local proposeBtn = panel:FindFirstChild("ProposeButton", true) :: TextButton?
            if proposeBtn then
                local hasValue = _offerValues.gold > 0 or _offerValues.wood > 0 or _offerValues.food > 0
                    or _requestValues.gold > 0 or _requestValues.wood > 0 or _requestValues.food > 0
                proposeBtn.BackgroundColor3 = if hasValue then TRADE_THEME.primary else TRADE_THEME.cancelGray
            end
        end)
        for _, c in woodVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 12 end end
        woodVal.Parent.ZIndex = 12

        -- Food input
        local _, foodVal = createResourceInput("Food", TRADE_THEME.foodColor, offerContent, function(newVal)
            _offerValues.food = newVal
            local proposeBtn = panel:FindFirstChild("ProposeButton", true) :: TextButton?
            if proposeBtn then
                local hasValue = _offerValues.gold > 0 or _offerValues.wood > 0 or _offerValues.food > 0
                    or _requestValues.gold > 0 or _requestValues.wood > 0 or _requestValues.food > 0
                proposeBtn.BackgroundColor3 = if hasValue then TRADE_THEME.primary else TRADE_THEME.cancelGray
            end
        end)
        for _, c in foodVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 12 end end
        foodVal.Parent.ZIndex = 12

        -- "You have" reference labels
        local haveLabel = Instance.new("TextLabel")
        haveLabel.Name = "HaveLabel"
        haveLabel.Size = UDim2.new(1, -16, 0, 40)
        haveLabel.BackgroundTransparency = 1
        haveLabel.Text = "You have: 0g / 0w / 0f"
        haveLabel.TextColor3 = TRADE_THEME.textMuted
        haveLabel.TextSize = 11
        haveLabel.Font = Enum.Font.Gotham
        haveLabel.TextWrapped = true
        haveLabel.ZIndex = 12
        haveLabel.Parent = offerContent
    end

    -- YOU REQUEST section (right)
    local requestSection = createSection("YOU REQUEST", panel, 270, 235)
    requestSection.ZIndex = 12

    for _, child in requestSection:GetDescendants() do
        if child:IsA("GuiObject") then
            child.ZIndex = 12
        end
    end

    local requestContent = requestSection:FindFirstChild("Content") :: Frame
    if requestContent then
        -- Gold input (request side - clamped to target's resources)
        local _, goldReqVal = createResourceInput("Gold", TRADE_THEME.goldColor, requestContent, function(newVal)
            _requestValues.gold = newVal
            local proposeBtn = panel:FindFirstChild("ProposeButton", true) :: TextButton?
            if proposeBtn then
                local hasValue = _offerValues.gold > 0 or _offerValues.wood > 0 or _offerValues.food > 0
                    or _requestValues.gold > 0 or _requestValues.wood > 0 or _requestValues.food > 0
                proposeBtn.BackgroundColor3 = if hasValue then TRADE_THEME.primary else TRADE_THEME.cancelGray
            end
        end)
        for _, c in goldReqVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 12 end end
        goldReqVal.Parent.ZIndex = 12

        -- Wood input
        local _, woodReqVal = createResourceInput("Wood", TRADE_THEME.woodColor, requestContent, function(newVal)
            _requestValues.wood = newVal
            local proposeBtn = panel:FindFirstChild("ProposeButton", true) :: TextButton?
            if proposeBtn then
                local hasValue = _offerValues.gold > 0 or _offerValues.wood > 0 or _offerValues.food > 0
                    or _requestValues.gold > 0 or _requestValues.wood > 0 or _requestValues.food > 0
                proposeBtn.BackgroundColor3 = if hasValue then TRADE_THEME.primary else TRADE_THEME.cancelGray
            end
        end)
        for _, c in woodReqVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 12 end end
        woodReqVal.Parent.ZIndex = 12

        -- Food input
        local _, foodReqVal = createResourceInput("Food", TRADE_THEME.foodColor, requestContent, function(newVal)
            _requestValues.food = newVal
            local proposeBtn = panel:FindFirstChild("ProposeButton", true) :: TextButton?
            if proposeBtn then
                local hasValue = _offerValues.gold > 0 or _offerValues.wood > 0 or _offerValues.food > 0
                    or _requestValues.gold > 0 or _requestValues.wood > 0 or _requestValues.food > 0
                proposeBtn.BackgroundColor3 = if hasValue then TRADE_THEME.primary else TRADE_THEME.cancelGray
            end
        end)
        for _, c in foodReqVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 12 end end
        foodReqVal.Parent.ZIndex = 12

        -- "They have" reference labels
        local theyHaveLabel = Instance.new("TextLabel")
        theyHaveLabel.Name = "TheyHaveLabel"
        theyHaveLabel.Size = UDim2.new(1, -16, 0, 40)
        theyHaveLabel.BackgroundTransparency = 1
        theyHaveLabel.Text = "They have: 0g / 0w / 0f"
        theyHaveLabel.TextColor3 = TRADE_THEME.textMuted
        theyHaveLabel.TextSize = 11
        theyHaveLabel.Font = Enum.Font.Gotham
        theyHaveLabel.TextWrapped = true
        theyHaveLabel.ZIndex = 12
        theyHaveLabel.Parent = requestContent
    end

    -- Buttons row at bottom
    local buttonsFrame = Instance.new("Frame")
    buttonsFrame.Name = "Buttons"
    buttonsFrame.Size = UDim2.new(1, -30, 0, 45)
    buttonsFrame.Position = UDim2.new(0, 15, 1, -60)
    buttonsFrame.BackgroundTransparency = 1
    buttonsFrame.ZIndex = 12
    buttonsFrame.Parent = panel

    local buttonsLayout = Instance.new("UIListLayout")
    buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
    buttonsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    buttonsLayout.Padding = UDim.new(0, 15)
    buttonsLayout.Parent = buttonsFrame

    -- Propose button
    local proposeButton = Instance.new("TextButton")
    proposeButton.Name = "ProposeButton"
    proposeButton.Size = UDim2.new(0, 200, 0, 42)
    proposeButton.BackgroundColor3 = TRADE_THEME.cancelGray -- Starts disabled
    proposeButton.Text = "PROPOSE TRADE"
    proposeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    proposeButton.TextSize = 16
    proposeButton.Font = Enum.Font.GothamBold
    proposeButton.BorderSizePixel = 0
    proposeButton.ZIndex = 12
    proposeButton.Parent = buttonsFrame

    local proposeCorner = Instance.new("UICorner")
    proposeCorner.CornerRadius = UDim.new(0, 8)
    proposeCorner.Parent = proposeButton

    local proposeStroke = Instance.new("UIStroke")
    proposeStroke.Color = TRADE_THEME.primaryLight
    proposeStroke.Thickness = 1
    proposeStroke.Parent = proposeButton

    -- Cancel button
    local cancelButton = Instance.new("TextButton")
    cancelButton.Name = "CancelButton"
    cancelButton.Size = UDim2.new(0, 120, 0, 42)
    cancelButton.BackgroundColor3 = TRADE_THEME.cancelGray
    cancelButton.Text = "CANCEL"
    cancelButton.TextColor3 = Color3.fromRGB(220, 210, 190)
    cancelButton.TextSize = 14
    cancelButton.Font = Enum.Font.GothamBold
    cancelButton.BorderSizePixel = 0
    cancelButton.ZIndex = 12
    cancelButton.Parent = buttonsFrame

    local cancelCorner = Instance.new("UICorner")
    cancelCorner.CornerRadius = UDim.new(0, 8)
    cancelCorner.Parent = cancelButton

    -- Shift hint
    local shiftHint = Instance.new("TextLabel")
    shiftHint.Name = "ShiftHint"
    shiftHint.Size = UDim2.new(1, 0, 0, 16)
    shiftHint.Position = UDim2.new(0, 0, 1, -18)
    shiftHint.BackgroundTransparency = 1
    shiftHint.Text = "Click a value to type. Shift+click +/- for 1,000"
    shiftHint.TextColor3 = TRADE_THEME.textMuted
    shiftHint.TextSize = 10
    shiftHint.Font = Enum.Font.Gotham
    shiftHint.ZIndex = 12
    shiftHint.Parent = panel

    -- Wire propose button
    proposeButton.MouseButton1Click:Connect(function()
        local hasValue = _offerValues.gold > 0 or _offerValues.wood > 0 or _offerValues.food > 0
            or _requestValues.gold > 0 or _requestValues.wood > 0 or _requestValues.food > 0
        if not hasValue then return end
        if not _targetData then return end

        -- Disable button and show proposing state
        proposeButton.Active = false
        proposeButton.Text = "Proposing..."
        proposeButton.BackgroundColor3 = TRADE_THEME.cancelGray

        -- Fire the signal
        TradeUI.TradeProposed:Fire(
            _targetData.userId,
            { gold = _offerValues.gold, wood = _offerValues.wood, food = _offerValues.food },
            { gold = _requestValues.gold, wood = _requestValues.wood, food = _requestValues.food }
        )

        -- Hide panel after a brief delay
        task.delay(0.5, function()
            if overlay.Visible then
                overlay.Visible = false
            end
        end)
    end)

    -- Wire cancel button
    cancelButton.MouseButton1Click:Connect(function()
        overlay.Visible = false
    end)

    -- Wire overlay close
    overlayButton.MouseButton1Click:Connect(function()
        overlay.Visible = false
    end)

    return overlay
end

-- ============================================================================
-- UI CREATION - INCOMING PANEL
-- ============================================================================

--[[
    Creates the incoming trade proposal panel.
]]
local function createIncomingPanel(parent: ScreenGui): Frame
    local overlay = Instance.new("Frame")
    overlay.Name = "IncomingOverlay"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 0.4
    overlay.Visible = false
    overlay.ZIndex = 20
    overlay.Parent = parent

    -- Main panel
    local panel = Instance.new("Frame")
    panel.Name = "IncomingPanel"
    panel.Size = UDim2.new(0, 480, 0, 340)
    panel.Position = UDim2.new(0.5, 0, 0.5, 0)
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.BackgroundColor3 = TRADE_THEME.panelBg
    panel.BorderSizePixel = 0
    panel.ZIndex = 21
    panel.Parent = overlay

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 12)
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = TRADE_THEME.primary
    panelStroke.Thickness = 2
    panelStroke.Parent = panel

    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 30)
    title.Position = UDim2.new(0, 0, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = "PlayerName wants to trade!"
    title.TextColor3 = TRADE_THEME.textPrimary
    title.TextSize = 20
    title.Font = Enum.Font.GothamBold
    title.ZIndex = 22
    title.Parent = panel

    -- Countdown timer
    local countdown = Instance.new("TextLabel")
    countdown.Name = "Countdown"
    countdown.Size = UDim2.new(1, 0, 0, 20)
    countdown.Position = UDim2.new(0, 0, 0, 38)
    countdown.BackgroundTransparency = 1
    countdown.Text = "Expires in: 60s"
    countdown.TextColor3 = TRADE_THEME.textSecondary
    countdown.TextSize = 13
    countdown.Font = Enum.Font.Gotham
    countdown.ZIndex = 22
    countdown.Parent = panel

    -- THEY OFFER section (left)
    local offerSection = Instance.new("Frame")
    offerSection.Name = "TheyOfferSection"
    offerSection.Size = UDim2.new(0, 210, 0, 170)
    offerSection.Position = UDim2.new(0, 15, 0, 68)
    offerSection.BackgroundColor3 = TRADE_THEME.sectionBg
    offerSection.BorderSizePixel = 0
    offerSection.ZIndex = 22
    offerSection.Parent = panel

    local offerCorner = Instance.new("UICorner")
    offerCorner.CornerRadius = UDim.new(0, 8)
    offerCorner.Parent = offerSection

    local offerStroke = Instance.new("UIStroke")
    offerStroke.Color = TRADE_THEME.acceptGreen
    offerStroke.Thickness = 1
    offerStroke.Parent = offerSection

    local offerTitle = Instance.new("TextLabel")
    offerTitle.Name = "Title"
    offerTitle.Size = UDim2.new(1, 0, 0, 28)
    offerTitle.BackgroundColor3 = Color3.fromRGB(30, 50, 35)
    offerTitle.Text = "THEY OFFER"
    offerTitle.TextColor3 = TRADE_THEME.acceptGreen
    offerTitle.TextSize = 13
    offerTitle.Font = Enum.Font.GothamBold
    offerTitle.ZIndex = 22
    offerTitle.Parent = offerSection

    local offerTitleCorner = Instance.new("UICorner")
    offerTitleCorner.CornerRadius = UDim.new(0, 8)
    offerTitleCorner.Parent = offerTitle

    local offerTitleFix = Instance.new("Frame")
    offerTitleFix.Size = UDim2.new(1, 0, 0, 8)
    offerTitleFix.Position = UDim2.new(0, 0, 1, -8)
    offerTitleFix.BackgroundColor3 = Color3.fromRGB(30, 50, 35)
    offerTitleFix.BorderSizePixel = 0
    offerTitleFix.ZIndex = 22
    offerTitleFix.Parent = offerTitle

    local offerContent = Instance.new("Frame")
    offerContent.Name = "Content"
    offerContent.Size = UDim2.new(1, 0, 1, -35)
    offerContent.Position = UDim2.new(0, 0, 0, 35)
    offerContent.BackgroundTransparency = 1
    offerContent.ZIndex = 22
    offerContent.Parent = offerSection

    local offerLayout = Instance.new("UIListLayout")
    offerLayout.FillDirection = Enum.FillDirection.Vertical
    offerLayout.Padding = UDim.new(0, 6)
    offerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    offerLayout.Parent = offerContent

    local offerPadding = Instance.new("UIPadding")
    offerPadding.PaddingTop = UDim.new(0, 10)
    offerPadding.PaddingLeft = UDim.new(0, 10)
    offerPadding.Parent = offerContent

    local _, offerGoldVal = createResourceDisplay("Gold", TRADE_THEME.goldColor, offerContent)
    offerGoldVal.ZIndex = 22
    for _, c in offerGoldVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 22 end end
    offerGoldVal.Parent.ZIndex = 22

    local _, offerWoodVal = createResourceDisplay("Wood", TRADE_THEME.woodColor, offerContent)
    offerWoodVal.ZIndex = 22
    for _, c in offerWoodVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 22 end end
    offerWoodVal.Parent.ZIndex = 22

    local _, offerFoodVal = createResourceDisplay("Food", TRADE_THEME.foodColor, offerContent)
    offerFoodVal.ZIndex = 22
    for _, c in offerFoodVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 22 end end
    offerFoodVal.Parent.ZIndex = 22

    -- THEY WANT section (right)
    local wantSection = Instance.new("Frame")
    wantSection.Name = "TheyWantSection"
    wantSection.Size = UDim2.new(0, 210, 0, 170)
    wantSection.Position = UDim2.new(0, 250, 0, 68)
    wantSection.BackgroundColor3 = TRADE_THEME.sectionBg
    wantSection.BorderSizePixel = 0
    wantSection.ZIndex = 22
    wantSection.Parent = panel

    local wantCorner = Instance.new("UICorner")
    wantCorner.CornerRadius = UDim.new(0, 8)
    wantCorner.Parent = wantSection

    local wantStroke = Instance.new("UIStroke")
    wantStroke.Color = TRADE_THEME.declineRed
    wantStroke.Thickness = 1
    wantStroke.Parent = wantSection

    local wantTitle = Instance.new("TextLabel")
    wantTitle.Name = "Title"
    wantTitle.Size = UDim2.new(1, 0, 0, 28)
    wantTitle.BackgroundColor3 = Color3.fromRGB(50, 30, 30)
    wantTitle.Text = "THEY WANT"
    wantTitle.TextColor3 = TRADE_THEME.declineRed
    wantTitle.TextSize = 13
    wantTitle.Font = Enum.Font.GothamBold
    wantTitle.ZIndex = 22
    wantTitle.Parent = wantSection

    local wantTitleCorner = Instance.new("UICorner")
    wantTitleCorner.CornerRadius = UDim.new(0, 8)
    wantTitleCorner.Parent = wantTitle

    local wantTitleFix = Instance.new("Frame")
    wantTitleFix.Size = UDim2.new(1, 0, 0, 8)
    wantTitleFix.Position = UDim2.new(0, 0, 1, -8)
    wantTitleFix.BackgroundColor3 = Color3.fromRGB(50, 30, 30)
    wantTitleFix.BorderSizePixel = 0
    wantTitleFix.ZIndex = 22
    wantTitleFix.Parent = wantTitle

    local wantContent = Instance.new("Frame")
    wantContent.Name = "Content"
    wantContent.Size = UDim2.new(1, 0, 1, -35)
    wantContent.Position = UDim2.new(0, 0, 0, 35)
    wantContent.BackgroundTransparency = 1
    wantContent.ZIndex = 22
    wantContent.Parent = wantSection

    local wantLayout = Instance.new("UIListLayout")
    wantLayout.FillDirection = Enum.FillDirection.Vertical
    wantLayout.Padding = UDim.new(0, 6)
    wantLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    wantLayout.Parent = wantContent

    local wantPadding = Instance.new("UIPadding")
    wantPadding.PaddingTop = UDim.new(0, 10)
    wantPadding.PaddingLeft = UDim.new(0, 10)
    wantPadding.Parent = wantContent

    local _, wantGoldVal = createResourceDisplay("Gold", TRADE_THEME.goldColor, wantContent)
    wantGoldVal.ZIndex = 22
    for _, c in wantGoldVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 22 end end
    wantGoldVal.Parent.ZIndex = 22

    local _, wantWoodVal = createResourceDisplay("Wood", TRADE_THEME.woodColor, wantContent)
    wantWoodVal.ZIndex = 22
    for _, c in wantWoodVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 22 end end
    wantWoodVal.Parent.ZIndex = 22

    local _, wantFoodVal = createResourceDisplay("Food", TRADE_THEME.foodColor, wantContent)
    wantFoodVal.ZIndex = 22
    for _, c in wantFoodVal.Parent:GetDescendants() do if c:IsA("GuiObject") then c.ZIndex = 22 end end
    wantFoodVal.Parent.ZIndex = 22

    -- Buttons row
    local buttonsFrame = Instance.new("Frame")
    buttonsFrame.Name = "Buttons"
    buttonsFrame.Size = UDim2.new(1, -30, 0, 45)
    buttonsFrame.Position = UDim2.new(0, 15, 1, -60)
    buttonsFrame.BackgroundTransparency = 1
    buttonsFrame.ZIndex = 22
    buttonsFrame.Parent = panel

    local buttonsLayout = Instance.new("UIListLayout")
    buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
    buttonsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    buttonsLayout.Padding = UDim.new(0, 20)
    buttonsLayout.Parent = buttonsFrame

    -- Accept button
    local acceptButton = Instance.new("TextButton")
    acceptButton.Name = "AcceptButton"
    acceptButton.Size = UDim2.new(0, 180, 0, 42)
    acceptButton.BackgroundColor3 = TRADE_THEME.acceptGreen
    acceptButton.Text = "ACCEPT"
    acceptButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    acceptButton.TextSize = 18
    acceptButton.Font = Enum.Font.GothamBold
    acceptButton.BorderSizePixel = 0
    acceptButton.ZIndex = 22
    acceptButton.Parent = buttonsFrame

    local acceptCorner = Instance.new("UICorner")
    acceptCorner.CornerRadius = UDim.new(0, 8)
    acceptCorner.Parent = acceptButton

    local acceptStroke = Instance.new("UIStroke")
    acceptStroke.Color = Color3.fromRGB(80, 200, 80)
    acceptStroke.Thickness = 1
    acceptStroke.Parent = acceptButton

    -- Decline button
    local declineButton = Instance.new("TextButton")
    declineButton.Name = "DeclineButton"
    declineButton.Size = UDim2.new(0, 140, 0, 42)
    declineButton.BackgroundColor3 = TRADE_THEME.declineRed
    declineButton.Text = "DECLINE"
    declineButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    declineButton.TextSize = 16
    declineButton.Font = Enum.Font.GothamBold
    declineButton.BorderSizePixel = 0
    declineButton.ZIndex = 22
    declineButton.Parent = buttonsFrame

    local declineCorner = Instance.new("UICorner")
    declineCorner.CornerRadius = UDim.new(0, 8)
    declineCorner.Parent = declineButton

    -- Wire accept button
    acceptButton.MouseButton1Click:Connect(function()
        if not _currentTradeId then return end

        acceptButton.Active = false
        acceptButton.Text = "Accepting..."
        acceptButton.BackgroundColor3 = TRADE_THEME.cancelGray

        TradeUI.TradeAccepted:Fire(_currentTradeId)

        -- Stop countdown
        if _incomingCountdownThread then
            task.cancel(_incomingCountdownThread)
            _incomingCountdownThread = nil
        end

        -- Hide panel
        task.delay(0.5, function()
            if overlay.Visible then
                overlay.Visible = false
            end
        end)
    end)

    -- Wire decline button
    declineButton.MouseButton1Click:Connect(function()
        if not _currentTradeId then return end

        TradeUI.TradeDeclined:Fire(_currentTradeId)

        -- Stop countdown
        if _incomingCountdownThread then
            task.cancel(_incomingCountdownThread)
            _incomingCountdownThread = nil
        end

        overlay.Visible = false
    end)

    return overlay
end

-- ============================================================================
-- UI CREATION - RESULT PANEL
-- ============================================================================

--[[
    Creates the result notification panel.
]]
local function createResultPanel(parent: ScreenGui): Frame
    local frame = Instance.new("Frame")
    frame.Name = "ResultPanel"
    frame.Size = UDim2.new(0, 320, 0, 50)
    frame.Position = UDim2.new(0.5, 0, 0, -60)
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.BackgroundColor3 = TRADE_THEME.panelBg
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.ZIndex = 30
    frame.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Name = "ResultStroke"
    stroke.Color = TRADE_THEME.primary
    stroke.Thickness = 2
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Name = "ResultText"
    label.Size = UDim2.new(1, -20, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = "Trade result"
    label.TextColor3 = TRADE_THEME.textPrimary
    label.TextSize = 16
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.ZIndex = 31
    label.Parent = frame

    return frame
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Initializes the TradeUI.
]]
function TradeUI:Init()
    if _initialized then
        warn("[TradeUI] Already initialized")
        return
    end

    _playerGui = _player:WaitForChild("PlayerGui") :: PlayerGui

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "TradeUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.DisplayOrder = 40
    _screenGui.Parent = _playerGui

    -- Create panels
    _proposalPanel = createProposalPanel(_screenGui)
    _incomingPanel = createIncomingPanel(_screenGui)
    _resultPanel = createResultPanel(_screenGui)

    _initialized = true
    print("[TradeUI] Initialized")
end

--[[
    Shows the proposal panel for initiating a trade with a target player.

    @param baseData table - Target player data with .userId, .username, .resources (target's resources)
    @param playerResources table - Current player's resources {gold, wood, food}
]]
function TradeUI:ShowProposalPanel(baseData: any, playerResources: {gold: number, wood: number, food: number})
    if not _proposalPanel then return end

    _targetData = baseData
    _playerResources = playerResources or { gold = 0, wood = 0, food = 0 }
    _targetResources = (baseData and baseData.resources) or { gold = 0, wood = 0, food = 0 }

    -- Reset values
    _offerValues = { gold = 0, wood = 0, food = 0 }
    _requestValues = { gold = 0, wood = 0, food = 0 }

    -- Update title
    local panel = _proposalPanel:FindFirstChild("ProposalPanel") :: Frame?
    if panel then
        local title = panel:FindFirstChild("Title") :: TextLabel?
        if title then
            title.Text = "TRADE WITH " .. (baseData.username or "Unknown")
        end

        -- Reset all value displays
        local offerSection = panel:FindFirstChild("YOUROFFERSection") :: Frame?
        if offerSection then
            local content = offerSection:FindFirstChild("Content") :: Frame?
            if content then
                for _, row in content:GetChildren() do
                    if row:IsA("Frame") and row.Name:find("Row") then
                        local val = row:FindFirstChild("Value") :: TextLabel?
                        if val then val.Text = "0" end
                    end
                end

                -- Update "You have" label
                local haveLabel = content:FindFirstChild("HaveLabel") :: TextLabel?
                if haveLabel then
                    haveLabel.Text = string.format(
                        "You have: %sg / %sw / %sf",
                        formatNumber(_playerResources.gold),
                        formatNumber(_playerResources.wood),
                        formatNumber(_playerResources.food)
                    )
                end
            end
        end

        local requestSection = panel:FindFirstChild("YOUREQUESTSection") :: Frame?
        if requestSection then
            local content = requestSection:FindFirstChild("Content") :: Frame?
            if content then
                for _, row in content:GetChildren() do
                    if row:IsA("Frame") and row.Name:find("Row") then
                        local val = row:FindFirstChild("Value") :: TextLabel?
                        if val then val.Text = "0" end
                    end
                end

                -- Update "They have" label
                local theyHaveLabel = content:FindFirstChild("TheyHaveLabel") :: TextLabel?
                if theyHaveLabel then
                    theyHaveLabel.Text = string.format(
                        "They have: %sg / %sw / %sf",
                        formatNumber(_targetResources.gold),
                        formatNumber(_targetResources.wood),
                        formatNumber(_targetResources.food)
                    )
                end
            end
        end

        -- Reset propose button
        local buttonsFrame = panel:FindFirstChild("Buttons") :: Frame?
        if buttonsFrame then
            local proposeBtn = buttonsFrame:FindFirstChild("ProposeButton") :: TextButton?
            if proposeBtn then
                proposeBtn.Active = true
                proposeBtn.Text = "PROPOSE TRADE"
                proposeBtn.BackgroundColor3 = TRADE_THEME.cancelGray
            end
        end
    end

    -- Show
    _proposalPanel.Visible = true
end

--[[
    Shows the incoming trade proposal panel.

    @param tradeData table - Trade data from server
        { tradeId, proposerName, proposerUserId, offering, requesting, expiresAt }
]]
function TradeUI:ShowIncomingTrade(tradeData: any)
    if not _incomingPanel then return end
    if not tradeData then return end

    _currentTradeId = tradeData.tradeId

    -- Update title
    local panel = _incomingPanel:FindFirstChild("IncomingPanel") :: Frame?
    if not panel then return end

    local title = panel:FindFirstChild("Title") :: TextLabel?
    if title then
        title.Text = (tradeData.proposerName or "Someone") .. " wants to trade!"
    end

    -- Update offer values
    local offerSection = panel:FindFirstChild("TheyOfferSection") :: Frame?
    if offerSection then
        local content = offerSection:FindFirstChild("Content") :: Frame?
        if content then
            local goldRow = content:FindFirstChild("GoldRow") :: Frame?
            if goldRow then
                local val = goldRow:FindFirstChild("Value") :: TextLabel?
                if val then val.Text = formatNumber(tradeData.offering and tradeData.offering.gold or 0) end
            end
            local woodRow = content:FindFirstChild("WoodRow") :: Frame?
            if woodRow then
                local val = woodRow:FindFirstChild("Value") :: TextLabel?
                if val then val.Text = formatNumber(tradeData.offering and tradeData.offering.wood or 0) end
            end
            local foodRow = content:FindFirstChild("FoodRow") :: Frame?
            if foodRow then
                local val = foodRow:FindFirstChild("Value") :: TextLabel?
                if val then val.Text = formatNumber(tradeData.offering and tradeData.offering.food or 0) end
            end
        end
    end

    -- Update want values
    local wantSection = panel:FindFirstChild("TheyWantSection") :: Frame?
    if wantSection then
        local content = wantSection:FindFirstChild("Content") :: Frame?
        if content then
            local goldRow = content:FindFirstChild("GoldRow") :: Frame?
            if goldRow then
                local val = goldRow:FindFirstChild("Value") :: TextLabel?
                if val then val.Text = formatNumber(tradeData.requesting and tradeData.requesting.gold or 0) end
            end
            local woodRow = content:FindFirstChild("WoodRow") :: Frame?
            if woodRow then
                local val = woodRow:FindFirstChild("Value") :: TextLabel?
                if val then val.Text = formatNumber(tradeData.requesting and tradeData.requesting.wood or 0) end
            end
            local foodRow = content:FindFirstChild("FoodRow") :: Frame?
            if foodRow then
                local val = foodRow:FindFirstChild("Value") :: TextLabel?
                if val then val.Text = formatNumber(tradeData.requesting and tradeData.requesting.food or 0) end
            end
        end
    end

    -- Reset accept button
    local buttonsFrame = panel:FindFirstChild("Buttons") :: Frame?
    if buttonsFrame then
        local acceptBtn = buttonsFrame:FindFirstChild("AcceptButton") :: TextButton?
        if acceptBtn then
            acceptBtn.Active = true
            acceptBtn.Text = "ACCEPT"
            acceptBtn.BackgroundColor3 = TRADE_THEME.acceptGreen
        end
    end

    -- Show panel
    _incomingPanel.Visible = true

    -- Start countdown
    if _incomingCountdownThread then
        task.cancel(_incomingCountdownThread)
        _incomingCountdownThread = nil
    end

    local countdownLabel = panel:FindFirstChild("Countdown") :: TextLabel?
    local expiresAt = tradeData.expiresAt or (os.time() + TRADE_TIMEOUT)

    _incomingCountdownThread = task.spawn(function()
        while _incomingPanel and _incomingPanel.Visible do
            local remaining = math.max(0, expiresAt - os.time())

            if countdownLabel then
                countdownLabel.Text = "Expires in: " .. remaining .. "s"

                -- Color changes as time runs out
                if remaining <= 10 then
                    countdownLabel.TextColor3 = TRADE_THEME.declineRed
                elseif remaining <= 30 then
                    countdownLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
                else
                    countdownLabel.TextColor3 = TRADE_THEME.textSecondary
                end
            end

            if remaining <= 0 then
                -- Auto-decline
                if _currentTradeId then
                    TradeUI.TradeDeclined:Fire(_currentTradeId)
                end
                _incomingPanel.Visible = false
                break
            end

            task.wait(1)
        end
    end)
end

--[[
    Hides both panels.
]]
function TradeUI:Hide()
    if _proposalPanel then
        _proposalPanel.Visible = false
    end
    if _incomingPanel then
        _incomingPanel.Visible = false
    end

    -- Stop countdown
    if _incomingCountdownThread then
        task.cancel(_incomingCountdownThread)
        _incomingCountdownThread = nil
    end

    _currentTradeId = nil
    _targetData = nil
end

--[[
    Shows a result notification.

    @param message string - Result message to display
    @param isSuccess boolean - Whether the result is positive
]]
function TradeUI:ShowResult(message: string, isSuccess: boolean)
    if not _resultPanel then return end

    -- Hide any open panels
    if _proposalPanel then _proposalPanel.Visible = false end
    if _incomingPanel then _incomingPanel.Visible = false end

    -- Cancel any existing hide thread
    if _resultHideThread then
        task.cancel(_resultHideThread)
        _resultHideThread = nil
    end

    -- Update text and color
    local resultText = _resultPanel:FindFirstChild("ResultText") :: TextLabel?
    if resultText then
        resultText.Text = message
        resultText.TextColor3 = if isSuccess then TRADE_THEME.successGreen else TRADE_THEME.failureRed
    end

    local resultStroke = _resultPanel:FindFirstChild("ResultStroke") :: UIStroke?
    if resultStroke then
        resultStroke.Color = if isSuccess then TRADE_THEME.successGreen else TRADE_THEME.failureRed
    end

    -- Show and animate in
    _resultPanel.Position = UDim2.new(0.5, 0, 0, -60)
    _resultPanel.Visible = true

    local slideIn = TweenService:Create(
        _resultPanel,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, 0, 0, 20)}
    )
    slideIn:Play()

    -- Auto-hide after 3 seconds
    _resultHideThread = task.delay(3, function()
        if not _resultPanel then return end

        local slideOut = TweenService:Create(
            _resultPanel,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {Position = UDim2.new(0.5, 0, 0, -60)}
        )
        slideOut:Play()
        slideOut.Completed:Connect(function()
            if _resultPanel then
                _resultPanel.Visible = false
            end
        end)
    end)
end

return TradeUI
