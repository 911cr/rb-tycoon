--!strict
--[[
    TradeUI.lua

    Trading interface for player-to-player resource and troop exchanges.
    4-column layout:
      Col 1: Your Resources (read-only)
      Col 2: You Give (input)
      Col 3: You Request (input)
      Col 4: Their Resources (read-only)

    Two modes:
    1. Proposal mode: Player fills in what they offer and request, then proposes.
    2. Incoming mode: Player sees what another player offers/requests, and accepts or declines.

    Dependencies:
    - Signal (for events)
    - TroopData (for troop display names)

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
local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)

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
local _playerTroops: {[string]: number} = {}
local _targetTroops: {[string]: number} = {}

-- Proposal panel input values
local _offerValues = { gold = 0, wood = 0, food = 0 }
local _requestValues = { gold = 0, wood = 0, food = 0 }
local _offerTroops: {[string]: number} = {}
local _requestTroops: {[string]: number} = {}

-- Incoming panel countdown
local _incomingCountdownThread: thread? = nil

-- Result panel auto-hide
local _resultHideThread: thread? = nil

-- Content frame references for dynamic population
local _col1Content: Frame? = nil
local _col2Content: Frame? = nil
local _col3Content: Frame? = nil
local _col4Content: Frame? = nil
local _proposalPanelInner: TextButton? = nil

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
    troopColor = Color3.fromRGB(140, 120, 200),   -- Troops (purple)
    acceptGreen = Color3.fromRGB(60, 160, 60),    -- Accept button
    declineRed = Color3.fromRGB(180, 60, 60),     -- Decline button
    cancelGray = Color3.fromRGB(100, 90, 80),     -- Cancel button
    successGreen = Color3.fromRGB(50, 180, 80),   -- Success result
    failureRed = Color3.fromRGB(200, 60, 60),     -- Failure result
    separatorColor = Color3.fromRGB(70, 65, 55),  -- Section divider
}

local RESOURCE_STEP = 100
local RESOURCE_STEP_SHIFT = 1000
local TROOP_STEP = 1
local TROOP_STEP_SHIFT = 10
local TRADE_TIMEOUT = 60

-- Ordered list of troop types for consistent display
local TROOP_ORDER = { "Barbarian", "Archer", "Giant", "WallBreaker", "Wizard", "Dragon", "PEKKA" }

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function formatNumber(num: number): string
    local formatted = tostring(math.floor(num))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

local function isShiftHeld(): boolean
    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function getTroopDisplayName(troopType: string): string
    local data = TroopData.GetByType(troopType)
    return if data then data.displayName else troopType
end

local function hasAnyTradeValue(): boolean
    if _offerValues.gold > 0 or _offerValues.wood > 0 or _offerValues.food > 0 then return true end
    if _requestValues.gold > 0 or _requestValues.wood > 0 or _requestValues.food > 0 then return true end
    for _, count in _offerTroops do if count > 0 then return true end end
    for _, count in _requestTroops do if count > 0 then return true end end
    return false
end

local function updateProposeButton()
    if not _proposalPanelInner then return end
    local proposeBtn = _proposalPanelInner:FindFirstChild("ProposeButton", true) :: TextButton?
    if proposeBtn then
        proposeBtn.BackgroundColor3 = if hasAnyTradeValue() then TRADE_THEME.primary else TRADE_THEME.cancelGray
    end
end

-- ============================================================================
-- UI ROW CREATION HELPERS
-- ============================================================================

--[[
    Creates a read-only resource/troop display row.
]]
local function createDisplayRow(
    name: string,
    color: Color3,
    parent: Frame,
    value: number,
    zIndex: number
): Frame
    local row = Instance.new("Frame")
    row.Name = name:gsub("%.", "") .. "DisplayRow"
    row.Size = UDim2.new(1, -8, 0, 26)
    row.BackgroundTransparency = 1
    row.ZIndex = zIndex
    row.Parent = parent

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(0, 70, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = name .. ":"
    label.TextColor3 = color
    label.TextSize = 12
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.ZIndex = zIndex
    label.Parent = row

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "Value"
    valueLabel.Size = UDim2.new(1, -75, 1, 0)
    valueLabel.Position = UDim2.new(0, 75, 0, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = formatNumber(value)
    valueLabel.TextColor3 = TRADE_THEME.textPrimary
    valueLabel.TextSize = 13
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextXAlignment = Enum.TextXAlignment.Left
    valueLabel.ZIndex = zIndex
    valueLabel.Parent = row

    return row
end

--[[
    Creates an input row with +/- buttons.
]]
local function createInputRow(
    name: string,
    color: Color3,
    parent: Frame,
    onChanged: (number) -> (),
    stepSize: number,
    shiftStepSize: number,
    zIndex: number
): Frame
    local clampMax = 99999999999999

    local row = Instance.new("Frame")
    row.Name = name:gsub("%.", "") .. "InputRow"
    row.Size = UDim2.new(1, -4, 0, 30)
    row.BackgroundTransparency = 1
    row.ZIndex = zIndex
    row.Parent = parent

    -- Label
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(0, 50, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = name .. ":"
    label.TextColor3 = color
    label.TextSize = 11
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.ZIndex = zIndex
    label.Parent = row

    -- Minus button
    local minusButton = Instance.new("TextButton")
    minusButton.Name = "MinusButton"
    minusButton.Size = UDim2.new(0, 26, 0, 26)
    minusButton.Position = UDim2.new(0, 52, 0.5, -13)
    minusButton.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
    minusButton.Text = "-"
    minusButton.TextColor3 = Color3.fromRGB(255, 180, 180)
    minusButton.TextSize = 16
    minusButton.Font = Enum.Font.GothamBold
    minusButton.BorderSizePixel = 0
    minusButton.ZIndex = zIndex
    minusButton.Parent = row

    local minusCorner = Instance.new("UICorner")
    minusCorner.CornerRadius = UDim.new(0, 5)
    minusCorner.Parent = minusButton

    -- Value display (TextBox)
    local valueLabel = Instance.new("TextBox")
    valueLabel.Name = "Value"
    valueLabel.Size = UDim2.new(0, 55, 0, 24)
    valueLabel.Position = UDim2.new(0, 80, 0.5, -12)
    valueLabel.BackgroundColor3 = Color3.fromRGB(50, 48, 42)
    valueLabel.BackgroundTransparency = 0.3
    valueLabel.Text = "0"
    valueLabel.PlaceholderText = "0"
    valueLabel.TextColor3 = TRADE_THEME.textPrimary
    valueLabel.TextSize = 13
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.ClearTextOnFocus = false
    valueLabel.BorderSizePixel = 0
    valueLabel.ZIndex = zIndex
    valueLabel.Parent = row

    local valueCorner = Instance.new("UICorner")
    valueCorner.CornerRadius = UDim.new(0, 4)
    valueCorner.Parent = valueLabel

    -- Plus button
    local plusButton = Instance.new("TextButton")
    plusButton.Name = "PlusButton"
    plusButton.Size = UDim2.new(0, 26, 0, 26)
    plusButton.Position = UDim2.new(0, 137, 0.5, -13)
    plusButton.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
    plusButton.Text = "+"
    plusButton.TextColor3 = Color3.fromRGB(180, 255, 180)
    plusButton.TextSize = 16
    plusButton.Font = Enum.Font.GothamBold
    plusButton.BorderSizePixel = 0
    plusButton.ZIndex = zIndex
    plusButton.Parent = row

    local plusCorner = Instance.new("UICorner")
    plusCorner.CornerRadius = UDim.new(0, 5)
    plusCorner.Parent = plusButton

    -- Handle typed input
    valueLabel.FocusLost:Connect(function(_enterPressed)
        local parsed = tonumber(valueLabel.Text:gsub(",", "")) or 0
        parsed = math.clamp(math.floor(parsed), 0, clampMax)
        valueLabel.Text = formatNumber(parsed)
        onChanged(parsed)
        updateProposeButton()
    end)

    -- Wire buttons
    minusButton.MouseButton1Click:Connect(function()
        local step = if isShiftHeld() then shiftStepSize else stepSize
        local current = tonumber(valueLabel.Text:gsub(",", "")) or 0
        local newVal = math.clamp(current - step, 0, clampMax)
        valueLabel.Text = formatNumber(newVal)
        onChanged(newVal)
        updateProposeButton()
    end)

    plusButton.MouseButton1Click:Connect(function()
        local step = if isShiftHeld() then shiftStepSize else stepSize
        local current = tonumber(valueLabel.Text:gsub(",", "")) or 0
        local newVal = math.clamp(current + step, 0, clampMax)
        valueLabel.Text = formatNumber(newVal)
        onChanged(newVal)
        updateProposeButton()
    end)

    return row
end

--[[
    Creates a separator label inside a content frame.
]]
local function createSeparator(text: string, parent: Frame, zIndex: number): TextLabel
    local sep = Instance.new("TextLabel")
    sep.Name = "Separator_" .. text
    sep.Size = UDim2.new(1, -8, 0, 20)
    sep.BackgroundTransparency = 1
    sep.Text = "— " .. text .. " —"
    sep.TextColor3 = TRADE_THEME.separatorColor
    sep.TextSize = 10
    sep.Font = Enum.Font.GothamBold
    sep.ZIndex = zIndex
    sep.Parent = parent
    return sep
end

--[[
    Creates a column section frame for the 4-column layout.
]]
local function createColumnSection(
    title: string,
    parent: Frame,
    posX: number,
    width: number,
    height: number,
    titleColor: Color3,
    titleBg: Color3,
    borderColor: Color3,
    zIndex: number
): (Frame, Frame)
    local section = Instance.new("Frame")
    section.Name = title:gsub(" ", "") .. "Section"
    section.Size = UDim2.new(0, width, 0, height)
    section.Position = UDim2.new(0, posX, 0, 52)
    section.BackgroundColor3 = TRADE_THEME.sectionBg
    section.BorderSizePixel = 0
    section.ZIndex = zIndex
    section.Parent = parent

    local sectionCorner = Instance.new("UICorner")
    sectionCorner.CornerRadius = UDim.new(0, 8)
    sectionCorner.Parent = section

    local sectionStroke = Instance.new("UIStroke")
    sectionStroke.Color = borderColor
    sectionStroke.Thickness = 1
    sectionStroke.Parent = section

    -- Section title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, 26)
    titleLabel.BackgroundColor3 = titleBg
    titleLabel.Text = title
    titleLabel.TextColor3 = titleColor
    titleLabel.TextSize = 11
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.ZIndex = zIndex
    titleLabel.Parent = section

    local titleCornerEl = Instance.new("UICorner")
    titleCornerEl.CornerRadius = UDim.new(0, 8)
    titleCornerEl.Parent = titleLabel

    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 8)
    titleFix.Position = UDim2.new(0, 0, 1, -8)
    titleFix.BackgroundColor3 = titleBg
    titleFix.BorderSizePixel = 0
    titleFix.ZIndex = zIndex
    titleFix.Parent = titleLabel

    -- Scrollable content area
    local content = Instance.new("ScrollingFrame")
    content.Name = "Content"
    content.Size = UDim2.new(1, 0, 1, -30)
    content.Position = UDim2.new(0, 0, 0, 30)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ScrollBarThickness = 3
    content.ScrollBarImageColor3 = TRADE_THEME.primaryDark
    content.CanvasSize = UDim2.new(0, 0, 0, 0) -- auto-sized by layout
    content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    content.ZIndex = zIndex
    content.Parent = section

    local contentLayout = Instance.new("UIListLayout")
    contentLayout.FillDirection = Enum.FillDirection.Vertical
    contentLayout.Padding = UDim.new(0, 3)
    contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    contentLayout.Parent = content

    local contentPadding = Instance.new("UIPadding")
    contentPadding.PaddingTop = UDim.new(0, 4)
    contentPadding.PaddingLeft = UDim.new(0, 4)
    contentPadding.PaddingRight = UDim.new(0, 4)
    contentPadding.Parent = content

    return section, content :: Frame
end

-- ============================================================================
-- UI CREATION - PROPOSAL PANEL (4-column layout)
-- ============================================================================

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

    -- Main panel (TextButton to absorb clicks)
    local panel = Instance.new("TextButton")
    panel.Name = "ProposalPanel"
    panel.Size = UDim2.new(0, 780, 0, 500)
    panel.Position = UDim2.new(0.5, 0, 0.5, 0)
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.BackgroundColor3 = TRADE_THEME.panelBg
    panel.BorderSizePixel = 0
    panel.ZIndex = 11
    panel.Text = ""
    panel.AutoButtonColor = false
    panel.Parent = overlay
    _proposalPanelInner = panel

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
    title.Size = UDim2.new(1, 0, 0, 42)
    title.BackgroundColor3 = TRADE_THEME.headerBg
    title.Text = "TRADE WITH Player"
    title.TextColor3 = TRADE_THEME.textPrimary
    title.TextSize = 18
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

    -- Column dimensions
    local colHeight = 355
    local displayW = 155
    local inputW = 195
    local gap = 8
    local leftPad = 15

    -- Col 1: YOUR RESOURCES (read-only display)
    local _, col1 = createColumnSection(
        "YOUR RESOURCES", panel, leftPad, displayW, colHeight,
        TRADE_THEME.textSecondary, Color3.fromRGB(35, 40, 38), TRADE_THEME.primaryDark, 12
    )
    _col1Content = col1

    -- Col 2: YOU GIVE (input)
    local _, col2 = createColumnSection(
        "YOU GIVE", panel, leftPad + displayW + gap, inputW, colHeight,
        TRADE_THEME.primaryLight, TRADE_THEME.headerBg, TRADE_THEME.primary, 12
    )
    _col2Content = col2

    -- Col 3: YOU REQUEST (input)
    local _, col3 = createColumnSection(
        "YOU REQUEST", panel, leftPad + displayW + gap + inputW + gap, inputW, colHeight,
        Color3.fromRGB(255, 180, 100), Color3.fromRGB(50, 40, 30), Color3.fromRGB(180, 130, 60), 12
    )
    _col3Content = col3

    -- Col 4: THEIR RESOURCES (read-only display)
    local _, col4 = createColumnSection(
        "THEIR RESOURCES", panel, leftPad + displayW + gap + inputW + gap + inputW + gap, displayW, colHeight,
        TRADE_THEME.textSecondary, Color3.fromRGB(35, 40, 38), TRADE_THEME.primaryDark, 12
    )
    _col4Content = col4

    -- Buttons row at bottom
    local buttonsFrame = Instance.new("Frame")
    buttonsFrame.Name = "Buttons"
    buttonsFrame.Size = UDim2.new(1, -30, 0, 42)
    buttonsFrame.Position = UDim2.new(0, 15, 1, -55)
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
    proposeButton.Size = UDim2.new(0, 200, 0, 40)
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
    cancelButton.Size = UDim2.new(0, 120, 0, 40)
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
    shiftHint.Size = UDim2.new(1, 0, 0, 14)
    shiftHint.Position = UDim2.new(0, 0, 1, -14)
    shiftHint.BackgroundTransparency = 1
    shiftHint.Text = "Click value to type. Shift+click +/- for 1,000 (resources) or 10 (troops)"
    shiftHint.TextColor3 = TRADE_THEME.textMuted
    shiftHint.TextSize = 9
    shiftHint.Font = Enum.Font.Gotham
    shiftHint.ZIndex = 12
    shiftHint.Parent = panel

    -- Wire propose button
    proposeButton.MouseButton1Click:Connect(function()
        if not hasAnyTradeValue() then return end
        if not _targetData then return end

        -- Disable button and show proposing state
        proposeButton.Active = false
        proposeButton.Text = "Proposing..."
        proposeButton.BackgroundColor3 = TRADE_THEME.cancelGray

        -- Build troop tables (only include non-zero)
        local offerTroopsCopy: {[string]: number} = {}
        for troopType, count in _offerTroops do
            if count > 0 then offerTroopsCopy[troopType] = count end
        end
        local requestTroopsCopy: {[string]: number} = {}
        for troopType, count in _requestTroops do
            if count > 0 then requestTroopsCopy[troopType] = count end
        end

        -- Fire the signal
        TradeUI.TradeProposed:Fire(
            _targetData.userId,
            { gold = _offerValues.gold, wood = _offerValues.wood, food = _offerValues.food, troops = offerTroopsCopy },
            { gold = _requestValues.gold, wood = _requestValues.wood, food = _requestValues.food, troops = requestTroopsCopy }
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
    panel.Size = UDim2.new(0, 500, 0, 400)
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
    offerSection.Size = UDim2.new(0, 220, 0, 240)
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

    local offerContent = Instance.new("ScrollingFrame")
    offerContent.Name = "Content"
    offerContent.Size = UDim2.new(1, 0, 1, -35)
    offerContent.Position = UDim2.new(0, 0, 0, 35)
    offerContent.BackgroundTransparency = 1
    offerContent.BorderSizePixel = 0
    offerContent.ScrollBarThickness = 3
    offerContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
    offerContent.ZIndex = 22
    offerContent.Parent = offerSection

    local offerLayout = Instance.new("UIListLayout")
    offerLayout.FillDirection = Enum.FillDirection.Vertical
    offerLayout.Padding = UDim.new(0, 4)
    offerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    offerLayout.Parent = offerContent

    local offerPaddingEl = Instance.new("UIPadding")
    offerPaddingEl.PaddingTop = UDim.new(0, 8)
    offerPaddingEl.PaddingLeft = UDim.new(0, 8)
    offerPaddingEl.Parent = offerContent

    -- THEY WANT section (right)
    local wantSection = Instance.new("Frame")
    wantSection.Name = "TheyWantSection"
    wantSection.Size = UDim2.new(0, 220, 0, 240)
    wantSection.Position = UDim2.new(0, 260, 0, 68)
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

    local wantContent = Instance.new("ScrollingFrame")
    wantContent.Name = "Content"
    wantContent.Size = UDim2.new(1, 0, 1, -35)
    wantContent.Position = UDim2.new(0, 0, 0, 35)
    wantContent.BackgroundTransparency = 1
    wantContent.BorderSizePixel = 0
    wantContent.ScrollBarThickness = 3
    wantContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
    wantContent.ZIndex = 22
    wantContent.Parent = wantSection

    local wantLayout = Instance.new("UIListLayout")
    wantLayout.FillDirection = Enum.FillDirection.Vertical
    wantLayout.Padding = UDim.new(0, 4)
    wantLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    wantLayout.Parent = wantContent

    local wantPadding = Instance.new("UIPadding")
    wantPadding.PaddingTop = UDim.new(0, 8)
    wantPadding.PaddingLeft = UDim.new(0, 8)
    wantPadding.Parent = wantContent

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

        if _incomingCountdownThread then
            task.cancel(_incomingCountdownThread)
            _incomingCountdownThread = nil
        end

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
-- DYNAMIC CONTENT POPULATION
-- ============================================================================

--[[
    Clears a content frame of all non-layout children (rows, separators).
]]
local function clearContent(content: Frame)
    for _, child in content:GetChildren() do
        if child:IsA("Frame") or (child:IsA("TextLabel") and child.Name:find("Separator")) then
            child:Destroy()
        end
    end
end

--[[
    Gets the list of troop types that either player has.
]]
local function getActiveTroopTypes(): {string}
    local types = {}
    for _, troopType in TROOP_ORDER do
        local playerCount = _playerTroops[troopType] or 0
        local targetCount = _targetTroops[troopType] or 0
        if playerCount > 0 or targetCount > 0 then
            table.insert(types, troopType)
        end
    end
    return types
end

--[[
    Populates a display column (columns 1 or 4) with resource and troop values.
]]
local function populateDisplayColumn(
    content: Frame,
    resources: {gold: number, wood: number, food: number},
    troops: {[string]: number},
    activeTroopTypes: {string},
    zIndex: number
)
    clearContent(content)

    -- Resources
    createDisplayRow("Gold", TRADE_THEME.goldColor, content, resources.gold, zIndex)
    createDisplayRow("Wood", TRADE_THEME.woodColor, content, resources.wood, zIndex)
    createDisplayRow("Food", TRADE_THEME.foodColor, content, resources.food, zIndex)

    -- Troop separator and rows (only if troops exist)
    if #activeTroopTypes > 0 then
        createSeparator("TROOPS", content, zIndex)
        for _, troopType in activeTroopTypes do
            local displayName = getTroopDisplayName(troopType)
            local count = troops[troopType] or 0
            createDisplayRow(displayName, TRADE_THEME.troopColor, content, count, zIndex)
        end
    end
end

--[[
    Populates an input column (columns 2 or 3) with resource and troop inputs.
]]
local function populateInputColumn(
    content: Frame,
    valueTable: {gold: number, wood: number, food: number},
    troopTable: {[string]: number},
    isOfferSide: boolean,
    activeTroopTypes: {string},
    zIndex: number
)
    clearContent(content)

    -- Resource inputs
    createInputRow("Gold", TRADE_THEME.goldColor, content, function(val)
        valueTable.gold = val
    end, RESOURCE_STEP, RESOURCE_STEP_SHIFT, zIndex)

    createInputRow("Wood", TRADE_THEME.woodColor, content, function(val)
        valueTable.wood = val
    end, RESOURCE_STEP, RESOURCE_STEP_SHIFT, zIndex)

    createInputRow("Food", TRADE_THEME.foodColor, content, function(val)
        valueTable.food = val
    end, RESOURCE_STEP, RESOURCE_STEP_SHIFT, zIndex)

    -- Troop inputs (only if troops exist)
    if #activeTroopTypes > 0 then
        createSeparator("TROOPS", content, zIndex)
        for _, troopType in activeTroopTypes do
            local displayName = getTroopDisplayName(troopType)
            troopTable[troopType] = 0 -- Initialize
            createInputRow(displayName, TRADE_THEME.troopColor, content, function(val)
                troopTable[troopType] = val
            end, TROOP_STEP, TROOP_STEP_SHIFT, zIndex)
        end
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

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

    @param baseData table - Target player data with .userId, .username, .resources, .troops
    @param playerResources table - Current player's resources {gold, wood, food, troops}
]]
function TradeUI:ShowProposalPanel(baseData: any, playerResources: any)
    if not _proposalPanel then return end

    _targetData = baseData
    _playerResources = {
        gold = (playerResources and playerResources.gold) or 0,
        wood = (playerResources and playerResources.wood) or 0,
        food = (playerResources and playerResources.food) or 0,
    }
    _targetResources = {
        gold = (baseData and baseData.resources and baseData.resources.gold) or 0,
        wood = (baseData and baseData.resources and baseData.resources.wood) or 0,
        food = (baseData and baseData.resources and baseData.resources.food) or 0,
    }
    _playerTroops = (playerResources and playerResources.troops) or {}
    _targetTroops = (baseData and baseData.troops) or {}

    -- Reset values
    _offerValues = { gold = 0, wood = 0, food = 0 }
    _requestValues = { gold = 0, wood = 0, food = 0 }
    _offerTroops = {}
    _requestTroops = {}

    -- Update title
    local panel = _proposalPanelInner
    if panel then
        local titleEl = panel:FindFirstChild("Title") :: TextLabel?
        if titleEl then
            titleEl.Text = "TRADE WITH " .. (baseData and baseData.username or "Unknown")
        end

        -- Reset propose button
        local proposeBtn = panel:FindFirstChild("ProposeButton", true) :: TextButton?
        if proposeBtn then
            proposeBtn.Active = true
            proposeBtn.Text = "PROPOSE TRADE"
            proposeBtn.BackgroundColor3 = TRADE_THEME.cancelGray
        end
    end

    -- Get which troop types to show
    local activeTroopTypes = getActiveTroopTypes()

    -- Populate all 4 columns
    if _col1Content then
        populateDisplayColumn(_col1Content, _playerResources, _playerTroops, activeTroopTypes, 12)
    end
    if _col2Content then
        populateInputColumn(_col2Content, _offerValues, _offerTroops, true, activeTroopTypes, 12)
    end
    if _col3Content then
        populateInputColumn(_col3Content, _requestValues, _requestTroops, false, activeTroopTypes, 12)
    end
    if _col4Content then
        populateDisplayColumn(_col4Content, _targetResources, _targetTroops, activeTroopTypes, 12)
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

    local panel = _incomingPanel:FindFirstChild("IncomingPanel") :: Frame?
    if not panel then return end

    local title = panel:FindFirstChild("Title") :: TextLabel?
    if title then
        title.Text = (tradeData.proposerName or "Someone") .. " wants to trade!"
    end

    -- Populate offer section
    local offerSection = panel:FindFirstChild("TheyOfferSection") :: Frame?
    if offerSection then
        local content = offerSection:FindFirstChild("Content") :: Frame?
        if content then
            clearContent(content)
            local offering = tradeData.offering or {}
            createDisplayRow("Gold", TRADE_THEME.goldColor, content, offering.gold or 0, 22)
            createDisplayRow("Wood", TRADE_THEME.woodColor, content, offering.wood or 0, 22)
            createDisplayRow("Food", TRADE_THEME.foodColor, content, offering.food or 0, 22)

            -- Troop rows
            if offering.troops then
                local hasTroops = false
                for _, count in offering.troops do
                    if count > 0 then hasTroops = true break end
                end
                if hasTroops then
                    createSeparator("TROOPS", content, 22)
                    for _, troopType in TROOP_ORDER do
                        local count = offering.troops[troopType]
                        if count and count > 0 then
                            createDisplayRow(getTroopDisplayName(troopType), TRADE_THEME.troopColor, content, count, 22)
                        end
                    end
                end
            end
        end
    end

    -- Populate want section
    local wantSection = panel:FindFirstChild("TheyWantSection") :: Frame?
    if wantSection then
        local content = wantSection:FindFirstChild("Content") :: Frame?
        if content then
            clearContent(content)
            local requesting = tradeData.requesting or {}
            createDisplayRow("Gold", TRADE_THEME.goldColor, content, requesting.gold or 0, 22)
            createDisplayRow("Wood", TRADE_THEME.woodColor, content, requesting.wood or 0, 22)
            createDisplayRow("Food", TRADE_THEME.foodColor, content, requesting.food or 0, 22)

            -- Troop rows
            if requesting.troops then
                local hasTroops = false
                for _, count in requesting.troops do
                    if count > 0 then hasTroops = true break end
                end
                if hasTroops then
                    createSeparator("TROOPS", content, 22)
                    for _, troopType in TROOP_ORDER do
                        local count = requesting.troops[troopType]
                        if count and count > 0 then
                            createDisplayRow(getTroopDisplayName(troopType), TRADE_THEME.troopColor, content, count, 22)
                        end
                    end
                end
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

                if remaining <= 10 then
                    countdownLabel.TextColor3 = TRADE_THEME.declineRed
                elseif remaining <= 30 then
                    countdownLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
                else
                    countdownLabel.TextColor3 = TRADE_THEME.textSecondary
                end
            end

            if remaining <= 0 then
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

function TradeUI:Hide()
    if _proposalPanel then
        _proposalPanel.Visible = false
    end
    if _incomingPanel then
        _incomingPanel.Visible = false
    end

    if _incomingCountdownThread then
        task.cancel(_incomingCountdownThread)
        _incomingCountdownThread = nil
    end

    _currentTradeId = nil
    _targetData = nil
end

function TradeUI:ShowResult(message: string, isSuccess: boolean)
    if not _resultPanel then return end

    if _proposalPanel then _proposalPanel.Visible = false end
    if _incomingPanel then _incomingPanel.Visible = false end

    if _resultHideThread then
        task.cancel(_resultHideThread)
        _resultHideThread = nil
    end

    local resultText = _resultPanel:FindFirstChild("ResultText") :: TextLabel?
    if resultText then
        resultText.Text = message
        resultText.TextColor3 = if isSuccess then TRADE_THEME.successGreen else TRADE_THEME.failureRed
    end

    local resultStroke = _resultPanel:FindFirstChild("ResultStroke") :: UIStroke?
    if resultStroke then
        resultStroke.Color = if isSuccess then TRADE_THEME.successGreen else TRADE_THEME.failureRed
    end

    _resultPanel.Position = UDim2.new(0.5, 0, 0, -60)
    _resultPanel.Visible = true

    local slideIn = TweenService:Create(
        _resultPanel,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, 0, 0, 20)}
    )
    slideIn:Play()

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
