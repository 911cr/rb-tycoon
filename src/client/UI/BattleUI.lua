--!strict
--[[
    BattleUI.lua

    Combat HUD for deploying troops during battle.
    Shows top bar (timer, destruction, stars, defender info),
    bottom troop selection bar, phase overlays (scout/deploy),
    and post-battle results screen.

    RemoteEvents:
    - BattleArenaReady   -> Show HUD, initialize troop selection
    - BattleStateUpdate  -> Update timer, destruction %, stars, troops
    - BattleComplete     -> Switch to end screen
    - ReturnToOverworld  -> Client fires when clicking return button

    Dependencies:
    - Components (UI factory)
    - TroopData (troop definitions)
    - Signal (event system)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Components)
local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)
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
local _selectedTroopType: string? = nil

-- UI References - Top Bar
local _timerLabel: TextLabel
local _destructionLabel: TextLabel
local _destructionBar: Frame
local _destructionBarFill: Frame
local _starFrames: {Frame} = {}
local _defenderNameLabel: TextLabel
local _defenderTHLabel: TextLabel

-- UI References - Phase overlay
local _phaseOverlay: Frame
local _phaseLabel: TextLabel
local _phaseSubLabel: TextLabel

-- UI References - End screen
local _endScreenOverlay: Frame
local _endScreenPanel: Frame
local _endScreenVisible = false

-- Tween presets
local TWEEN_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MEDIUM = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SLOW = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_BOUNCE = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_STAR = TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

-- Colors
local COLOR_GOLD = Color3.fromRGB(255, 200, 50)
local COLOR_GOLD_DARK = Color3.fromRGB(184, 134, 11)
local COLOR_STAR_EARNED = Color3.fromRGB(255, 215, 0)
local COLOR_STAR_EMPTY = Color3.fromRGB(80, 75, 65)
local COLOR_DESTRUCTION_BAR = Color3.fromRGB(220, 60, 40)
local COLOR_DESTRUCTION_BG = Color3.fromRGB(50, 45, 38)
local COLOR_VICTORY = Color3.fromRGB(80, 200, 80)
local COLOR_DEFEAT = Color3.fromRGB(200, 60, 60)
local COLOR_TROOP_SELECTED = Color3.fromRGB(255, 200, 50)
local COLOR_TROOP_NORMAL = Components.Colors.BackgroundLight

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Formats seconds into M:SS display for battle timer.
]]
local function formatBattleTime(seconds: number): string
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", mins, secs)
end

--[[
    Formats a large number with commas for readability.
    Example: 12500 -> "12,500"
]]
local function formatNumber(n: number): string
    local s = tostring(math.floor(n))
    local result = ""
    local count = 0
    for i = #s, 1, -1 do
        count += 1
        result = string.sub(s, i, i) .. result
        if count % 3 == 0 and i > 1 then
            result = "," .. result
        end
    end
    return result
end

--[[
    Gets a short display code for a troop type (first 2 chars or abbreviation).
]]
local function getTroopAbbreviation(troopType: string): string
    local abbreviations: {[string]: string} = {
        Barbarian = "Ba",
        Archer = "Ar",
        Giant = "Gi",
        WallBreaker = "WB",
        Wizard = "Wi",
        Dragon = "Dr",
        PEKKA = "PK",
    }
    return abbreviations[troopType] or string.sub(troopType, 1, 2)
end

--[[
    Gets a color for a troop type icon background.
]]
local function getTroopColor(troopType: string): Color3
    local colors: {[string]: Color3} = {
        Barbarian = Color3.fromRGB(200, 160, 60),
        Archer = Color3.fromRGB(180, 60, 180),
        Giant = Color3.fromRGB(200, 140, 50),
        WallBreaker = Color3.fromRGB(100, 100, 180),
        Wizard = Color3.fromRGB(100, 60, 200),
        Dragon = Color3.fromRGB(200, 60, 40),
        PEKKA = Color3.fromRGB(60, 60, 140),
    }
    return colors[troopType] or Components.Colors.Primary
end

-- ============================================================================
-- TOP BAR CREATION
-- ============================================================================

--[[
    Creates the top battle info bar with timer, stars, destruction, defender info.
]]
local function createTopBar(parent: ScreenGui): Frame
    local bar = Components.CreateFrame({
        Name = "TopBar",
        Size = UDim2.new(1, 0, 0, 80),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor = Components.Colors.Background,
        BackgroundTransparency = 0.2,
        Parent = parent,
    })

    -- Gradient fade at bottom
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.7, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    gradient.Parent = bar

    -- === TIMER (center top) ===
    local timerContainer = Components.CreateFrame({
        Name = "TimerContainer",
        Size = UDim2.new(0, 110, 0, 44),
        Position = UDim2.new(0.5, 0, 0, 6),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = Components.Colors.PanelBorder,
        Parent = bar,
    })

    _timerLabel = Components.CreateLabel({
        Name = "TimerText",
        Text = "3:00",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeXLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = timerContainer,
    })

    -- === STARS (left of timer) ===
    local starsContainer = Components.CreateFrame({
        Name = "StarsContainer",
        Size = UDim2.new(0, 130, 0, 36),
        Position = UDim2.new(0, 12, 0, 10),
        BackgroundTransparency = 1,
        Parent = bar,
    })

    local starsLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = starsContainer,
    })

    for i = 1, 3 do
        local starFrame = Components.CreateFrame({
            Name = "Star" .. i,
            Size = UDim2.new(0, 36, 0, 36),
            BackgroundColor = COLOR_STAR_EMPTY,
            CornerRadius = UDim.new(0.5, 0),
            Parent = starsContainer,
        })

        -- Gold border for star
        local starBorder = Instance.new("UIStroke")
        starBorder.Color = COLOR_GOLD_DARK
        starBorder.Thickness = 2
        starBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        starBorder.Parent = starFrame

        local starLabel = Components.CreateLabel({
            Name = "Icon",
            Text = "★",
            Size = UDim2.new(1, 0, 1, 0),
            TextColor = Components.Colors.TextMuted,
            TextSize = 22,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = starFrame,
        })

        _starFrames[i] = starFrame
    end

    -- === DESTRUCTION % (right of timer) ===
    local destructionContainer = Components.CreateFrame({
        Name = "DestructionContainer",
        Size = UDim2.new(0, 160, 0, 44),
        Position = UDim2.new(1, -12, 0, 6),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = Components.Colors.PanelBorder,
        Parent = bar,
    })

    -- Destruction label above bar
    _destructionLabel = Components.CreateLabel({
        Name = "DestructionText",
        Text = "0%",
        Size = UDim2.new(1, -8, 0, 18),
        Position = UDim2.new(0, 4, 0, 2),
        TextColor = Components.Colors.Danger,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = destructionContainer,
    })

    -- Destruction progress bar
    _destructionBar = Components.CreateFrame({
        Name = "DestructionBar",
        Size = UDim2.new(1, -12, 0, 14),
        Position = UDim2.new(0.5, 0, 1, -18),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = COLOR_DESTRUCTION_BG,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = destructionContainer,
    })

    local barBorder = Instance.new("UIStroke")
    barBorder.Color = Components.Colors.PanelBorder
    barBorder.Thickness = 1
    barBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    barBorder.Parent = _destructionBar

    _destructionBarFill = Components.CreateFrame({
        Name = "Fill",
        Size = UDim2.new(0, 0, 1, -2),
        Position = UDim2.new(0, 1, 0, 1),
        BackgroundColor = COLOR_DESTRUCTION_BAR,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = _destructionBar,
    })

    -- Shine effect on fill bar
    local shine = Instance.new("Frame")
    shine.Name = "Shine"
    shine.Size = UDim2.new(1, 0, 0.4, 0)
    shine.BackgroundColor3 = Color3.new(1, 1, 1)
    shine.BackgroundTransparency = 0.7
    shine.BorderSizePixel = 0
    shine.Parent = _destructionBarFill

    local shineCorner = Instance.new("UICorner")
    shineCorner.CornerRadius = Components.Sizes.CornerRadiusSmall
    shineCorner.Parent = shine

    -- === DEFENDER INFO (below timer) ===
    local defenderContainer = Components.CreateFrame({
        Name = "DefenderInfo",
        Size = UDim2.new(0, 200, 0, 20),
        Position = UDim2.new(0.5, 0, 0, 54),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Parent = bar,
    })

    _defenderNameLabel = Components.CreateLabel({
        Name = "DefenderName",
        Text = "",
        Size = UDim2.new(0.65, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = defenderContainer,
    })

    _defenderTHLabel = Components.CreateLabel({
        Name = "DefenderTH",
        Text = "",
        Size = UDim2.new(0.35, 0, 1, 0),
        Position = UDim2.new(0.65, 4, 0, 0),
        TextColor = COLOR_GOLD,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = defenderContainer,
    })

    return bar
end

-- ============================================================================
-- TROOP BAR CREATION
-- ============================================================================

--[[
    Creates a troop selection button for the bottom bar.
]]
local function createTroopButton(troopType: string, count: number, parent: GuiObject): Frame
    local troopDef = TroopData.GetByType(troopType)

    local button = Components.CreateFrame({
        Name = troopType,
        Size = UDim2.new(0, 72, 0, 84),
        BackgroundColor = COLOR_TROOP_NORMAL,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = Components.Colors.PanelBorder,
        Parent = parent,
    })

    -- Icon background
    local iconBg = Components.CreateFrame({
        Name = "IconBg",
        Size = UDim2.new(0, 48, 0, 48),
        Position = UDim2.new(0.5, 0, 0, 4),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = getTroopColor(troopType),
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = button,
    })

    -- Icon gradient for depth
    local iconGradient = Instance.new("UIGradient")
    iconGradient.Rotation = -45
    iconGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.7, 0.7, 0.7)),
    })
    iconGradient.Parent = iconBg

    -- Troop abbreviation text
    local iconLabel = Components.CreateLabel({
        Name = "IconText",
        Text = getTroopAbbreviation(troopType),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Troop name label
    local nameLabel = Components.CreateLabel({
        Name = "TroopName",
        Text = if troopDef then troopDef.displayName else troopType,
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.new(0, 0, 0, 54),
        TextColor = Components.Colors.TextSecondary,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = button,
    })

    -- Count badge (top-right corner)
    local countBadge = Components.CreateFrame({
        Name = "CountBadge",
        Size = UDim2.new(0, 26, 0, 18),
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

    -- Count in larger text at bottom
    local countBigLabel = Components.CreateLabel({
        Name = "CountBig",
        Text = "x" .. tostring(count),
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.new(0, 0, 1, -16),
        TextColor = Components.Colors.TextPrimary,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = button,
    })

    -- Clickable area
    local clickButton = Instance.new("TextButton")
    clickButton.Name = "ClickArea"
    clickButton.Size = UDim2.new(1, 0, 1, 0)
    clickButton.BackgroundTransparency = 1
    clickButton.Text = ""
    clickButton.Parent = button

    clickButton.MouseButton1Click:Connect(function()
        -- Deselect previous
        if _selectedTroopType and _troopButtons[_selectedTroopType] then
            local prevBtn = _troopButtons[_selectedTroopType]
            TweenService:Create(prevBtn, TWEEN_FAST, {
                BackgroundColor3 = COLOR_TROOP_NORMAL,
            }):Play()
            local prevStroke = prevBtn:FindFirstChildOfClass("UIStroke")
            if prevStroke then
                TweenService:Create(prevStroke, TWEEN_FAST, {
                    Color = Components.Colors.PanelBorder,
                    Thickness = 2,
                }):Play()
            end
        end

        -- Select this troop
        _selectedTroopType = troopType
        TweenService:Create(button, TWEEN_FAST, {
            BackgroundColor3 = COLOR_TROOP_NORMAL:Lerp(COLOR_TROOP_SELECTED, 0.2),
        }):Play()
        local stroke = button:FindFirstChildOfClass("UIStroke")
        if stroke then
            TweenService:Create(stroke, TWEEN_FAST, {
                Color = COLOR_TROOP_SELECTED,
                Thickness = 3,
            }):Play()
        end

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
        Size = UDim2.new(1, 0, 0, 110),
        Position = UDim2.new(0, 0, 1, 0),
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor = Components.Colors.Background,
        BackgroundTransparency = 0.2,
        Parent = parent,
    })

    -- Gradient fade at top
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = -90
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.7, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    gradient.Parent = bar

    -- Troop scroll container
    local troopScroll = Components.CreateScrollFrame({
        Name = "TroopScroll",
        Size = UDim2.new(1, -100, 0, 96),
        Position = UDim2.new(0, 8, 0, 7),
        Parent = bar,
    })
    troopScroll.ScrollingDirection = Enum.ScrollingDirection.X
    troopScroll.AutomaticCanvasSize = Enum.AutomaticSize.X

    local troopLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = troopScroll,
    })

    -- Surrender / End Battle button
    local surrenderButton = Components.CreateButton({
        Name = "SurrenderButton",
        Text = "END",
        Size = UDim2.new(0, 70, 0, 50),
        Position = UDim2.new(1, -12, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        Style = "danger",
        OnClick = function()
            BattleUI.SurrenderRequested:Fire()
        end,
        Parent = bar,
    })

    return bar
end

-- ============================================================================
-- PHASE OVERLAY CREATION
-- ============================================================================

--[[
    Creates the scout/deploy phase overlay that shows at the center of screen.
]]
local function createPhaseOverlay(parent: ScreenGui): Frame
    local overlay = Components.CreateFrame({
        Name = "PhaseOverlay",
        Size = UDim2.new(0, 360, 0, 80),
        Position = UDim2.new(0.5, 0, 0.15, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor = Components.Colors.Background,
        BackgroundTransparency = 0.3,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        Parent = parent,
    })
    overlay.Visible = false

    -- Border
    local border = Instance.new("UIStroke")
    border.Color = COLOR_GOLD_DARK
    border.Thickness = 2
    border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    border.Parent = overlay

    _phaseLabel = Components.CreateLabel({
        Name = "PhaseTitle",
        Text = "SCOUTING",
        Size = UDim2.new(1, 0, 0, 36),
        Position = UDim2.new(0, 0, 0, 8),
        TextColor = COLOR_GOLD,
        TextSize = Components.Sizes.FontSizeTitle,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = overlay,
    })

    _phaseSubLabel = Components.CreateLabel({
        Name = "PhaseSub",
        Text = "30s",
        Size = UDim2.new(1, 0, 0, 24),
        Position = UDim2.new(0, 0, 0, 44),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = overlay,
    })

    return overlay
end

-- ============================================================================
-- END SCREEN CREATION
-- ============================================================================

--[[
    Creates a resource loot row for the end screen.
]]
local function createLootRow(name: string, amount: number, color: Color3, parent: GuiObject, layoutOrder: number): Frame
    local row = Components.CreateFrame({
        Name = "Loot_" .. name,
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    row.LayoutOrder = layoutOrder

    local nameLabel = Components.CreateLabel({
        Name = "Name",
        Text = name,
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local amountLabel = Components.CreateLabel({
        Name = "Amount",
        Text = (if amount >= 0 then "+" else "") .. formatNumber(amount),
        Size = UDim2.new(0.5, -8, 1, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        TextColor = color,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row,
    })

    return row
end

--[[
    Creates the full end screen overlay and panel.
]]
local function createEndScreen(parent: ScreenGui): (Frame, Frame)
    -- Full screen dark overlay
    local overlay = Components.CreateFrame({
        Name = "EndScreenOverlay",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.5,
        Parent = parent,
    })
    overlay.Visible = false

    -- Results panel (centered)
    local panel = Components.CreateFrame({
        Name = "EndScreenPanel",
        Size = UDim2.new(0, 380, 0, 480),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor = Components.Colors.Background,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        BorderColor = Components.Colors.GoldTrim,
        Parent = overlay,
    })

    -- Ornate outer border
    local outerBorder = Instance.new("UIStroke")
    outerBorder.Color = Components.Colors.WoodFrame
    outerBorder.Thickness = 4
    outerBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    outerBorder.Parent = panel

    return overlay, panel
end

-- ============================================================================
-- PUBLIC UPDATE METHODS
-- ============================================================================

--[[
    Updates the star display based on earned stars.
    Animates newly earned stars with a scale+color tween.
]]
function BattleUI:UpdateStars(starsEarned: number)
    for i, frame in _starFrames do
        local label = frame:FindFirstChild("Icon") :: TextLabel
        if not label then continue end

        if i <= starsEarned then
            -- Check if this star was not already earned (to animate)
            if label.TextColor3 ~= COLOR_STAR_EARNED then
                -- Animate earning this star
                frame.BackgroundColor3 = COLOR_STAR_EMPTY
                label.TextColor3 = COLOR_STAR_EARNED

                TweenService:Create(frame, TWEEN_STAR, {
                    BackgroundColor3 = COLOR_GOLD_DARK,
                }):Play()

                -- Scale bounce animation
                local origSize = frame.Size
                frame.Size = UDim2.new(0, 28, 0, 28)
                TweenService:Create(frame, TWEEN_STAR, {
                    Size = origSize,
                }):Play()
            end
        else
            frame.BackgroundColor3 = COLOR_STAR_EMPTY
            label.TextColor3 = Components.Colors.TextMuted
        end
    end
end

--[[
    Updates the destruction percentage text and progress bar.
]]
function BattleUI:UpdateDestruction(percent: number)
    local clamped = math.clamp(percent, 0, 100)

    if _destructionLabel then
        _destructionLabel.Text = math.floor(clamped) .. "%"
    end

    if _destructionBarFill then
        TweenService:Create(_destructionBarFill, TWEEN_FAST, {
            Size = UDim2.new(clamped / 100, 0, 1, -2),
        }):Play()

        -- Color shift: orange -> red as destruction increases
        if clamped > 75 then
            TweenService:Create(_destructionBarFill, TWEEN_FAST, {
                BackgroundColor3 = Color3.fromRGB(220, 40, 40),
            }):Play()
        elseif clamped > 50 then
            TweenService:Create(_destructionBarFill, TWEEN_FAST, {
                BackgroundColor3 = Color3.fromRGB(220, 120, 30),
            }):Play()
        else
            _destructionBarFill.BackgroundColor3 = COLOR_DESTRUCTION_BAR
        end
    end
end

--[[
    Updates the battle timer display.
]]
function BattleUI:UpdateTimer(secondsRemaining: number)
    if not _timerLabel then return end

    _timerLabel.Text = formatBattleTime(math.max(0, secondsRemaining))

    -- Change color when time is running low
    if secondsRemaining <= 10 then
        _timerLabel.TextColor3 = Components.Colors.Danger
    elseif secondsRemaining <= 30 then
        _timerLabel.TextColor3 = Components.Colors.Warning
    else
        _timerLabel.TextColor3 = Components.Colors.TextPrimary
    end
end

--[[
    Updates the troop bar with current available troops.
    Rebuilds troop cards to reflect remaining counts.
]]
function BattleUI:UpdateTroops(troops: {[string]: number})
    local troopScroll = _troopBar:FindFirstChild("TroopScroll") :: ScrollingFrame
    if not troopScroll then return end

    -- Clear existing troop buttons
    for _, child in troopScroll:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    _troopButtons = {}

    -- Create buttons for each troop type that has remaining count
    for troopType, count in troops do
        if count > 0 then
            local button = createTroopButton(troopType, count, troopScroll)
            _troopButtons[troopType] = button

            -- Re-highlight selected troop if it still has count
            if troopType == _selectedTroopType then
                button.BackgroundColor3 = COLOR_TROOP_NORMAL:Lerp(COLOR_TROOP_SELECTED, 0.2)
                local stroke = button:FindFirstChildOfClass("UIStroke")
                if stroke then
                    stroke.Color = COLOR_TROOP_SELECTED
                    stroke.Thickness = 3
                end
            end
        end
    end

    -- If selected troop is depleted, clear selection
    if _selectedTroopType and (not troops[_selectedTroopType] or troops[_selectedTroopType] <= 0) then
        _selectedTroopType = nil
    end
end

--[[
    Updates the phase overlay to show current battle phase.
]]
function BattleUI:UpdatePhase(phase: string, timeRemaining: number?)
    if not _phaseOverlay then return end

    if phase == "scout" then
        _phaseOverlay.Visible = true
        _phaseLabel.Text = "SCOUTING"
        _phaseSubLabel.Text = if timeRemaining then formatBattleTime(timeRemaining) else "30s"
        _phaseLabel.TextColor3 = Components.Colors.Primary
    elseif phase == "deploy" or phase == "battle" then
        -- Show deploy prompt briefly, then hide
        _phaseOverlay.Visible = true
        _phaseLabel.Text = "DEPLOY YOUR TROOPS"
        _phaseSubLabel.Text = ""
        _phaseLabel.TextColor3 = COLOR_GOLD

        -- Auto-hide after 2 seconds during battle phase
        if phase == "battle" then
            task.delay(2, function()
                if _phaseOverlay and _phaseOverlay.Visible and _phaseLabel.Text == "DEPLOY YOUR TROOPS" then
                    TweenService:Create(_phaseOverlay, TWEEN_MEDIUM, {
                        BackgroundTransparency = 1,
                    }):Play()
                    task.delay(0.3, function()
                        if _phaseOverlay then
                            _phaseOverlay.Visible = false
                            _phaseOverlay.BackgroundTransparency = 0.3
                        end
                    end)
                end
            end)
        end
    else
        _phaseOverlay.Visible = false
    end
end

--[[
    Receives a full state update from the server and dispatches updates.

    @param stateData table - The BattleStateUpdate payload:
        {battleId, destruction, starsEarned, phase, timeRemaining, buildings, troops}
]]
function BattleUI:UpdateState(stateData: any)
    if not _isVisible then return end
    if stateData.battleId ~= _currentBattleId then return end

    -- Update timer
    self:UpdateTimer(stateData.timeRemaining or 0)

    -- Update destruction
    self:UpdateDestruction(stateData.destruction or 0)

    -- Update stars
    self:UpdateStars(stateData.starsEarned or 0)

    -- Update phase overlay
    if stateData.phase then
        self:UpdatePhase(stateData.phase, stateData.timeRemaining)
    end

    -- Update remaining troops if provided
    if stateData.remainingTroops then
        self:UpdateTroops(stateData.remainingTroops)
    end
end

-- ============================================================================
-- RESULTS SCREEN
-- ============================================================================

--[[
    Populates and displays the end-of-battle results screen.

    @param resultData table - The BattleComplete payload:
        {battleId, victory, destruction, stars, loot, trophiesGained, xpGained, ...}
]]
function BattleUI:ShowResults(resultData: any)
    if not _endScreenOverlay or not _endScreenPanel then return end

    _endScreenVisible = true

    -- Clear previous content from panel
    for _, child in _endScreenPanel:GetChildren() do
        if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton") then
            child:Destroy()
        end
    end
    -- Keep UICorner and UIStroke

    local isVictory = resultData.victory == true
    local headerColor = if isVictory then COLOR_VICTORY else COLOR_DEFEAT

    -- === HEADER: VICTORY / DEFEAT ===
    local headerBg = Components.CreateFrame({
        Name = "HeaderBg",
        Size = UDim2.new(1, 0, 0, 60),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor = headerColor,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        Parent = _endScreenPanel,
    })

    -- Clip bottom corners of header by adding another frame
    local headerClip = Components.CreateFrame({
        Name = "HeaderClip",
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 1, -20),
        BackgroundColor = headerColor,
        Parent = headerBg,
    })

    local headerLabel = Components.CreateLabel({
        Name = "HeaderText",
        Text = if isVictory then "VICTORY" else "DEFEAT",
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 8),
        TextColor = Components.Colors.TextPrimary,
        TextSize = 32,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = headerBg,
    })

    -- === STARS ROW ===
    local starsRow = Components.CreateFrame({
        Name = "StarsRow",
        Size = UDim2.new(1, 0, 0, 50),
        Position = UDim2.new(0, 0, 0, 66),
        BackgroundTransparency = 1,
        Parent = _endScreenPanel,
    })

    local starsRowLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 12),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = starsRow,
    })

    local starsEarned = resultData.stars or 0
    for i = 1, 3 do
        local starResult = Components.CreateFrame({
            Name = "ResultStar" .. i,
            Size = UDim2.new(0, 44, 0, 44),
            BackgroundColor = if i <= starsEarned then COLOR_GOLD_DARK else COLOR_STAR_EMPTY,
            CornerRadius = UDim.new(0.5, 0),
            Parent = starsRow,
        })

        local starBorder = Instance.new("UIStroke")
        starBorder.Color = if i <= starsEarned then COLOR_GOLD else Components.Colors.PanelBorder
        starBorder.Thickness = 2
        starBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        starBorder.Parent = starResult

        local starIcon = Components.CreateLabel({
            Name = "Icon",
            Text = "★",
            Size = UDim2.new(1, 0, 1, 0),
            TextColor = if i <= starsEarned then COLOR_STAR_EARNED else Components.Colors.TextMuted,
            TextSize = 28,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = starResult,
        })

        -- Animate stars appearing with delay
        if i <= starsEarned then
            starResult.Size = UDim2.new(0, 0, 0, 0)
            task.delay(0.3 + (i * 0.25), function()
                if starResult and starResult.Parent then
                    TweenService:Create(starResult, TWEEN_STAR, {
                        Size = UDim2.new(0, 44, 0, 44),
                    }):Play()
                end
            end)
        end
    end

    -- === DESTRUCTION % ===
    local destructionRow = Components.CreateFrame({
        Name = "DestructionRow",
        Size = UDim2.new(1, -40, 0, 30),
        Position = UDim2.new(0.5, 0, 0, 122),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Parent = _endScreenPanel,
    })

    local destructionText = Components.CreateLabel({
        Name = "DestructionLabel",
        Text = "Destruction",
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = destructionRow,
    })

    local destructionValue = Components.CreateLabel({
        Name = "DestructionValue",
        Text = math.floor(resultData.destruction or 0) .. "%",
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        TextColor = Components.Colors.Danger,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = destructionRow,
    })

    -- === DIVIDER ===
    local divider1 = Components.CreateDivider({
        Size = UDim2.new(1, -40, 0, 1),
        Position = UDim2.new(0.5, 0, 0, 158),
        Color = Components.Colors.PanelBorder,
        Parent = _endScreenPanel,
    })

    -- === LOOT SECTION ===
    local lootHeader = Components.CreateLabel({
        Name = "LootHeader",
        Text = "LOOT",
        Size = UDim2.new(1, -40, 0, 24),
        Position = UDim2.new(0, 20, 0, 166),
        TextColor = COLOR_GOLD,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = _endScreenPanel,
    })

    local lootContainer = Components.CreateFrame({
        Name = "LootContainer",
        Size = UDim2.new(1, -40, 0, 100),
        Position = UDim2.new(0.5, 0, 0, 192),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Parent = _endScreenPanel,
    })

    local lootLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 2),
        Parent = lootContainer,
    })

    local loot = resultData.loot or {}
    local layoutOrder = 0

    if loot.gold and loot.gold ~= 0 then
        layoutOrder += 1
        createLootRow("Gold", loot.gold, Components.Colors.Gold, lootContainer, layoutOrder)
    end
    if loot.wood and loot.wood ~= 0 then
        layoutOrder += 1
        createLootRow("Wood", loot.wood, Components.Colors.Wood, lootContainer, layoutOrder)
    end
    if loot.food and loot.food ~= 0 then
        layoutOrder += 1
        createLootRow("Food", loot.food, Components.Colors.Food, lootContainer, layoutOrder)
    end

    -- === DIVIDER ===
    local divider2 = Components.CreateDivider({
        Size = UDim2.new(1, -40, 0, 1),
        Position = UDim2.new(0.5, 0, 0, 298),
        Color = Components.Colors.PanelBorder,
        Parent = _endScreenPanel,
    })

    -- === STATS SECTION (Trophies, XP) ===
    local statsContainer = Components.CreateFrame({
        Name = "StatsContainer",
        Size = UDim2.new(1, -40, 0, 70),
        Position = UDim2.new(0.5, 0, 0, 306),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Parent = _endScreenPanel,
    })

    local statsLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 2),
        Parent = statsContainer,
    })

    local trophies = resultData.trophiesGained or 0
    local trophyColor = if trophies >= 0 then COLOR_GOLD else Components.Colors.Danger
    createLootRow("Trophies", trophies, trophyColor, statsContainer, 1)

    local xp = resultData.xpGained or 0
    createLootRow("Experience", xp, Components.Colors.Primary, statsContainer, 2)

    -- === RETURN BUTTON ===
    local returnButton = Components.CreateButton({
        Name = "ReturnButton",
        Text = "Return to Overworld",
        Size = UDim2.new(0, 240, 0, 48),
        Position = UDim2.new(0.5, 0, 1, -30),
        AnchorPoint = Vector2.new(0.5, 1),
        Style = "gold",
        TextSize = Components.Sizes.FontSizeLarge,
        Parent = _endScreenPanel,
    })

    returnButton.MouseButton1Click:Connect(function()
        -- Fire ReturnToOverworld to server
        local Events = ReplicatedStorage:FindFirstChild("Events")
        if Events then
            local returnEvent = Events:FindFirstChild("ReturnToOverworld")
            if returnEvent then
                returnEvent:FireServer({ battleId = _currentBattleId })
            end
        end

        -- Hide the end screen and the entire HUD
        self:HideResults()
        self:Hide()
    end)

    -- Show with animation
    _endScreenOverlay.Visible = true
    _endScreenPanel.Position = UDim2.new(0.5, 0, 1.5, 0)

    TweenService:Create(_endScreenOverlay, TWEEN_MEDIUM, {
        BackgroundTransparency = 0.5,
    }):Play()

    TweenService:Create(_endScreenPanel, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0.5, 0),
    }):Play()
end

--[[
    Hides the results overlay with animation.
]]
function BattleUI:HideResults()
    if not _endScreenOverlay then return end
    _endScreenVisible = false

    TweenService:Create(_endScreenPanel, TWEEN_MEDIUM, {
        Position = UDim2.new(0.5, 0, 1.5, 0),
    }):Play()

    TweenService:Create(_endScreenOverlay, TWEEN_MEDIUM, {
        BackgroundTransparency = 1,
    }):Play()

    task.delay(0.35, function()
        if _endScreenOverlay and not _endScreenVisible then
            _endScreenOverlay.Visible = false
        end
    end)
end

-- ============================================================================
-- SHOW / HIDE / INIT
-- ============================================================================

--[[
    Shows the battle UI with initial battle data.

    @param battleData table - The BattleArenaReady payload:
        {battleId, arenaCenter, arenaSize, buildings, defenderName, defenderTownHallLevel}
        OR a simple string battleId for backwards compatibility.
]]
function BattleUI:Show(battleData: any)
    if type(battleData) == "string" then
        -- Backwards compatibility: just a battleId string
        _currentBattleId = battleData
    elseif type(battleData) == "table" then
        _currentBattleId = battleData.battleId

        -- Set defender info
        if _defenderNameLabel and battleData.defenderName then
            _defenderNameLabel.Text = tostring(battleData.defenderName)
        end
        if _defenderTHLabel and battleData.defenderTownHallLevel then
            _defenderTHLabel.Text = "TH " .. tostring(battleData.defenderTownHallLevel)
        end
    end

    _isVisible = true
    _endScreenVisible = false
    _selectedTroopType = nil

    -- Reset display state
    self:UpdateStars(0)
    self:UpdateDestruction(0)
    self:UpdateTimer(180) -- 3 minutes default

    -- Show scout phase initially
    self:UpdatePhase("scout", 30)

    -- Enable and animate in
    _screenGui.Enabled = true
    if _endScreenOverlay then
        _endScreenOverlay.Visible = false
    end

    Components.SlideIn(_topBar, "top")
    Components.SlideIn(_troopBar, "bottom")
end

--[[
    Hides the battle UI with slide-out animation.
]]
function BattleUI:Hide()
    if not _isVisible then return end
    _isVisible = false

    -- Hide phase overlay
    if _phaseOverlay then
        _phaseOverlay.Visible = false
    end

    -- Slide out bars
    Components.SlideOut(_topBar, "top")
    Components.SlideOut(_troopBar, "bottom")

    task.delay(0.35, function()
        if not _isVisible then
            _screenGui.Enabled = false
        end
    end)

    _currentBattleId = nil
    _selectedTroopType = nil
end

--[[
    Returns whether the battle HUD is visible.
]]
function BattleUI:IsVisible(): boolean
    return _isVisible
end

--[[
    Returns the currently selected troop type for deployment, or nil.
]]
function BattleUI:GetSelectedTroop(): string?
    return _selectedTroopType
end

--[[
    Initializes the BattleUI module.
    Creates all UI elements and connects RemoteEvent listeners.
]]
function BattleUI:Init()
    if _initialized then
        warn("BattleUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "BattleHUD"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.IgnoreGuiInset = true
    _screenGui.DisplayOrder = 10 -- Above most other UI
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Create UI sections
    _topBar = createTopBar(_screenGui)
    _troopBar = createTroopBar(_screenGui)
    _phaseOverlay = createPhaseOverlay(_screenGui)
    _endScreenOverlay, _endScreenPanel = createEndScreen(_screenGui)

    -- ================================================================
    -- REMOTE EVENT CONNECTIONS
    -- ================================================================

    local Events = ReplicatedStorage:WaitForChild("Events", 10)
    if not Events then
        warn("[BattleUI] Events folder not found, cannot connect RemoteEvents")
        _initialized = true
        return
    end

    -- BattleArenaReady: Show the HUD when arena is ready
    local arenaReadyEvent = Events:FindFirstChild("BattleArenaReady")

    if arenaReadyEvent then
        arenaReadyEvent.OnClientEvent:Connect(function(data)
            if data.error then
                warn("[BattleUI] Arena creation failed:", data.error)
                return
            end
            self:Show(data)
        end)
    else
        warn("[BattleUI] BattleArenaReady event not found")
    end

    -- BattleStateUpdate: Per-tick state updates during battle
    local stateUpdateEvent = Events:FindFirstChild("BattleStateUpdate")

    if stateUpdateEvent then
        stateUpdateEvent.OnClientEvent:Connect(function(state)
            if _isVisible and state.battleId == _currentBattleId then
                self:UpdateState(state)
            end
        end)
    else
        warn("[BattleUI] BattleStateUpdate event not found")
    end

    -- BattleComplete: Show end screen with results
    local battleCompleteEvent = Events:FindFirstChild("BattleComplete")

    if battleCompleteEvent then
        battleCompleteEvent.OnClientEvent:Connect(function(result)
            if _isVisible then
                -- Update final state
                self:UpdateStars(result.stars or 0)
                self:UpdateDestruction(result.destruction or 0)

                -- Hide phase overlay
                if _phaseOverlay then
                    _phaseOverlay.Visible = false
                end

                -- Show results screen after a brief delay
                task.delay(0.5, function()
                    if _isVisible then
                        self:ShowResults(result)
                    end
                end)
            end
        end)
    else
        warn("[BattleUI] BattleComplete event not found")
    end

    -- ReturnToOverworld: Server may also fire this to force-return
    local returnEvent = Events:FindFirstChild("ReturnToOverworld")

    if returnEvent then
        returnEvent.OnClientEvent:Connect(function(data)
            -- Server forced return (e.g., timeout cleanup)
            if _isVisible then
                self:HideResults()
                self:Hide()
            end
        end)
    end

    _initialized = true
    print("[BattleUI] Initialized (BattleHUD)")
end

return BattleUI
