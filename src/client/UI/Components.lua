--!strict
--[[
    Components.lua

    Fantasy-Medieval themed UI component factory.
    Creates immersive, polished UI elements with proper styling.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Components = {}

-- ============================================================================
-- FANTASY-MEDIEVAL COLOR PALETTE
-- ============================================================================

Components.Colors = {
    -- Primary UI colors (parchment/leather theme)
    Background = Color3.fromRGB(35, 30, 25),           -- Dark leather
    BackgroundLight = Color3.fromRGB(50, 45, 38),      -- Light leather
    Panel = Color3.fromRGB(45, 40, 32),                -- Panel background
    PanelBorder = Color3.fromRGB(139, 115, 85),        -- Wood/leather border
    Parchment = Color3.fromRGB(215, 200, 170),         -- Parchment color

    -- Accent colors
    Primary = Color3.fromRGB(65, 105, 160),            -- Steel blue
    PrimaryDark = Color3.fromRGB(45, 75, 120),
    Secondary = Color3.fromRGB(76, 142, 76),           -- Forest green
    SecondaryDark = Color3.fromRGB(55, 110, 55),

    -- Resource colors (rich fantasy tones)
    Gold = Color3.fromRGB(255, 200, 50),               -- Bright gold
    GoldDark = Color3.fromRGB(184, 134, 11),           -- Dark gold
    Wood = Color3.fromRGB(139, 90, 43),                -- Rich wood brown
    Food = Color3.fromRGB(100, 180, 70),               -- Fresh green
    Gems = Color3.fromRGB(148, 80, 210),               -- Purple crystal

    -- Text colors
    TextPrimary = Color3.fromRGB(245, 235, 215),       -- Warm white
    TextSecondary = Color3.fromRGB(180, 170, 150),     -- Muted parchment
    TextMuted = Color3.fromRGB(120, 115, 100),         -- Faded text
    TextGold = Color3.fromRGB(255, 215, 0),            -- Gold text
    TextDark = Color3.fromRGB(40, 35, 30),             -- Dark text for light backgrounds

    -- Status colors
    Success = Color3.fromRGB(76, 175, 80),             -- Verdant green
    Warning = Color3.fromRGB(255, 183, 77),            -- Amber warning
    Danger = Color3.fromRGB(183, 65, 65),              -- Blood red

    -- Button states
    ButtonHover = Color3.fromRGB(70, 65, 55),
    ButtonPressed = Color3.fromRGB(55, 50, 42),
    ButtonDisabled = Color3.fromRGB(60, 55, 48),

    -- Decorative
    MetalTrim = Color3.fromRGB(140, 135, 130),         -- Iron/steel
    GoldTrim = Color3.fromRGB(218, 165, 32),           -- Gold trim
    WoodFrame = Color3.fromRGB(101, 67, 33),           -- Dark wood
}

-- ============================================================================
-- STANDARD SIZES
-- ============================================================================

Components.Sizes = {
    CornerRadius = UDim.new(0, 6),
    CornerRadiusSmall = UDim.new(0, 3),
    CornerRadiusLarge = UDim.new(0, 10),

    PaddingSmall = UDim.new(0, 4),
    PaddingMedium = UDim.new(0, 8),
    PaddingLarge = UDim.new(0, 16),

    FontSizeSmall = 12,
    FontSizeMedium = 14,
    FontSizeLarge = 18,
    FontSizeXLarge = 24,
    FontSizeTitle = 28,

    BorderThickness = 2,
    BorderThicknessThick = 3,
}

-- ============================================================================
-- ANIMATION PRESETS
-- ============================================================================

local TWEEN_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MEDIUM = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SLOW = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_BOUNCE = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Creates ornate border decoration for a frame.
]]
local function addOrnateBorder(parent: GuiObject, borderColor: Color3?, thickness: number?)
    local color = borderColor or Components.Colors.GoldTrim
    local thick = thickness or Components.Sizes.BorderThickness

    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thick
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = parent

    return stroke
end

--[[
    Creates a subtle inner glow effect.
]]
local function addInnerGlow(parent: Frame, glowColor: Color3?)
    local color = glowColor or Components.Colors.GoldTrim

    local glow = Instance.new("Frame")
    glow.Name = "InnerGlow"
    glow.Size = UDim2.new(1, -4, 1, -4)
    glow.Position = UDim2.new(0, 2, 0, 2)
    glow.BackgroundTransparency = 0.95
    glow.BackgroundColor3 = color
    glow.BorderSizePixel = 0
    glow.ZIndex = parent.ZIndex
    glow.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = Components.Sizes.CornerRadiusSmall
    corner.Parent = glow

    return glow
end

--[[
    Creates decorative corner pieces.
]]
local function addCornerDecorations(parent: Frame, cornerColor: Color3?)
    local color = cornerColor or Components.Colors.GoldTrim

    local corners = {"TopLeft", "TopRight", "BottomLeft", "BottomRight"}
    local positions = {
        TopLeft = {UDim2.new(0, 0, 0, 0), Vector2.new(0, 0)},
        TopRight = {UDim2.new(1, 0, 0, 0), Vector2.new(1, 0)},
        BottomLeft = {UDim2.new(0, 0, 1, 0), Vector2.new(0, 1)},
        BottomRight = {UDim2.new(1, 0, 1, 0), Vector2.new(1, 1)},
    }

    for _, cornerName in corners do
        local cornerPiece = Instance.new("Frame")
        cornerPiece.Name = "Corner_" .. cornerName
        cornerPiece.Size = UDim2.new(0, 12, 0, 12)
        cornerPiece.Position = positions[cornerName][1]
        cornerPiece.AnchorPoint = positions[cornerName][2]
        cornerPiece.BackgroundColor3 = color
        cornerPiece.BorderSizePixel = 0
        cornerPiece.ZIndex = parent.ZIndex + 1
        cornerPiece.Parent = parent

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 3)
        corner.Parent = cornerPiece
    end
end

-- ============================================================================
-- BASIC FRAME COMPONENT
-- ============================================================================

function Components.CreateFrame(props: {
    Name: string?,
    Size: UDim2?,
    Position: UDim2?,
    AnchorPoint: Vector2?,
    BackgroundColor: Color3?,
    BackgroundTransparency: number?,
    BorderColor: Color3?,
    CornerRadius: UDim?,
    Parent: GuiObject?,
}): Frame
    local frame = Instance.new("Frame")
    frame.Name = props.Name or "Frame"
    frame.Size = props.Size or UDim2.new(1, 0, 1, 0)
    frame.Position = props.Position or UDim2.new(0, 0, 0, 0)
    frame.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
    frame.BackgroundColor3 = props.BackgroundColor or Components.Colors.Panel
    frame.BackgroundTransparency = props.BackgroundTransparency or 0
    frame.BorderSizePixel = 0

    if props.CornerRadius then
        local corner = Instance.new("UICorner")
        corner.CornerRadius = props.CornerRadius
        corner.Parent = frame
    end

    if props.BorderColor then
        addOrnateBorder(frame, props.BorderColor)
    end

    if props.Parent then
        frame.Parent = props.Parent
    end

    return frame
end

-- ============================================================================
-- TEXT LABEL COMPONENT
-- ============================================================================

function Components.CreateLabel(props: {
    Name: string?,
    Text: string?,
    Size: UDim2?,
    Position: UDim2?,
    AnchorPoint: Vector2?,
    TextColor: Color3?,
    TextSize: number?,
    Font: Enum.Font?,
    TextXAlignment: Enum.TextXAlignment?,
    TextYAlignment: Enum.TextYAlignment?,
    TextShadow: boolean?,
    Parent: GuiObject?,
}): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = props.Name or "Label"
    label.Text = props.Text or ""
    label.Size = props.Size or UDim2.new(1, 0, 1, 0)
    label.Position = props.Position or UDim2.new(0, 0, 0, 0)
    label.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
    label.TextColor3 = props.TextColor or Components.Colors.TextPrimary
    label.TextSize = props.TextSize or Components.Sizes.FontSizeMedium
    label.Font = props.Font or Enum.Font.GothamMedium
    label.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    label.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
    label.BackgroundTransparency = 1
    label.TextScaled = false

    -- Add text shadow for better readability
    if props.TextShadow ~= false then
        label.TextStrokeTransparency = 0.7
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
    end

    if props.Parent then
        label.Parent = props.Parent
    end

    return label
end

-- ============================================================================
-- BUTTON COMPONENT (Fantasy Styled)
-- ============================================================================

function Components.CreateButton(props: {
    Name: string?,
    Text: string?,
    Size: UDim2?,
    Position: UDim2?,
    AnchorPoint: Vector2?,
    BackgroundColor: Color3?,
    TextColor: Color3?,
    TextSize: number?,
    CornerRadius: UDim?,
    Style: string?, -- "primary" | "secondary" | "danger" | "gold" | "wood"
    Parent: GuiObject?,
    OnClick: (() -> ())?,
}): TextButton
    local style = props.Style or "primary"

    -- Style presets
    local stylePresets = {
        primary = {bg = Components.Colors.Primary, text = Components.Colors.TextPrimary, border = Components.Colors.PrimaryDark},
        secondary = {bg = Components.Colors.Secondary, text = Components.Colors.TextPrimary, border = Components.Colors.SecondaryDark},
        danger = {bg = Components.Colors.Danger, text = Components.Colors.TextPrimary, border = Color3.fromRGB(140, 50, 50)},
        gold = {bg = Components.Colors.GoldDark, text = Components.Colors.TextDark, border = Components.Colors.Gold},
        wood = {bg = Components.Colors.WoodFrame, text = Components.Colors.TextPrimary, border = Color3.fromRGB(70, 45, 20)},
    }

    local preset = stylePresets[style] or stylePresets.primary

    local button = Instance.new("TextButton")
    button.Name = props.Name or "Button"
    button.Text = props.Text or "Button"
    button.Size = props.Size or UDim2.new(0, 120, 0, 40)
    button.Position = props.Position or UDim2.new(0, 0, 0, 0)
    button.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
    button.BackgroundColor3 = props.BackgroundColor or preset.bg
    button.TextColor3 = props.TextColor or preset.text
    button.TextSize = props.TextSize or Components.Sizes.FontSizeMedium
    button.Font = Enum.Font.GothamBold
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.TextStrokeTransparency = 0.7
    button.TextStrokeColor3 = Color3.new(0, 0, 0)

    local corner = Instance.new("UICorner")
    corner.CornerRadius = props.CornerRadius or Components.Sizes.CornerRadius
    corner.Parent = button

    -- Add border
    local stroke = Instance.new("UIStroke")
    stroke.Color = preset.border
    stroke.Thickness = 2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = button

    -- Gradient for depth
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(0.5, Color3.new(0.9, 0.9, 0.9)),
        ColorSequenceKeypoint.new(1, Color3.new(0.7, 0.7, 0.7)),
    })
    gradient.Parent = button

    -- Hover effects
    local originalColor = button.BackgroundColor3

    button.MouseEnter:Connect(function()
        TweenService:Create(button, TWEEN_FAST, {
            BackgroundColor3 = originalColor:Lerp(Color3.new(1, 1, 1), 0.15)
        }):Play()
        TweenService:Create(stroke, TWEEN_FAST, {
            Thickness = 3
        }):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(button, TWEEN_FAST, {
            BackgroundColor3 = originalColor
        }):Play()
        TweenService:Create(stroke, TWEEN_FAST, {
            Thickness = 2
        }):Play()
    end)

    button.MouseButton1Down:Connect(function()
        TweenService:Create(button, TWEEN_FAST, {
            BackgroundColor3 = originalColor:Lerp(Color3.new(0, 0, 0), 0.15)
        }):Play()
    end)

    button.MouseButton1Up:Connect(function()
        TweenService:Create(button, TWEEN_FAST, {
            BackgroundColor3 = originalColor
        }):Play()
    end)

    if props.OnClick then
        button.MouseButton1Click:Connect(props.OnClick)
    end

    if props.Parent then
        button.Parent = props.Parent
    end

    return button
end

-- ============================================================================
-- RESOURCE DISPLAY COMPONENT (Fantasy Styled)
-- ============================================================================

function Components.CreateResourceDisplay(props: {
    Name: string?,
    ResourceType: string, -- "Gold" | "Wood" | "Food" | "Gems"
    Size: UDim2?,
    Position: UDim2?,
    AnchorPoint: Vector2?,
    ShowCapacity: boolean?,
    Parent: GuiObject?,
}): Frame
    -- Resource configurations with image asset IDs
    -- Using free Roblox asset images that represent each resource
    local resourceConfigs = {
        Gold = {
            color = Components.Colors.Gold,
            darkColor = Components.Colors.GoldDark,
            -- Gold coins pile
            imageId = "rbxassetid://132769554", -- Gold coins pile
            fallbackText = "🪙",
        },
        Wood = {
            color = Components.Colors.Wood,
            darkColor = Color3.fromRGB(100, 65, 30),
            -- Three wood logs
            imageId = "rbxassetid://16537944090", -- Three wood logs
            fallbackText = "🌲",
        },
        Food = {
            color = Components.Colors.Food,
            darkColor = Color3.fromRGB(70, 130, 50),
            -- Red apple
            imageId = "rbxassetid://2958706766", -- Red apple
            fallbackText = "🍎",
        },
        Gems = {
            color = Components.Colors.Gems,
            darkColor = Color3.fromRGB(110, 60, 160),
            -- Gem/crystal image (keeping for backwards compatibility)
            imageId = "rbxassetid://6034684930", -- Gem/diamond icon
            fallbackText = "💎",
        },
    }

    local config = resourceConfigs[props.ResourceType] or resourceConfigs.Gold

    local container = Components.CreateFrame({
        Name = props.Name or (props.ResourceType .. "Display"),
        Size = props.Size or UDim2.new(0, 110, 0, 36),
        Position = props.Position,
        AnchorPoint = props.AnchorPoint,
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = config.color,
        Parent = props.Parent,
    })

    -- Inner gradient for depth
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.85, 0.85, 0.85)),
    })
    gradient.Parent = container

    -- Icon background (circular for coin/gem look)
    local iconBg = Components.CreateFrame({
        Name = "IconBg",
        Size = UDim2.new(0, 30, 0, 30),
        Position = UDim2.new(0, 3, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = config.color,
        CornerRadius = UDim.new(0.5, 0),
        Parent = container,
    })

    -- Icon gradient for 3D effect
    local iconGradient = Instance.new("UIGradient")
    iconGradient.Rotation = -45
    iconGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(0.5, Color3.new(0.95, 0.95, 0.95)),
        ColorSequenceKeypoint.new(1, Color3.new(0.7, 0.7, 0.7)),
    })
    iconGradient.Parent = iconBg

    -- Resource icon emoji text (replaces ImageLabel — asset IDs were unreliable)
    local iconText = Instance.new("TextLabel")
    iconText.Name = "IconText"
    iconText.Size = UDim2.new(1, 0, 1, 0)
    iconText.BackgroundTransparency = 1
    iconText.Text = config.fallbackText
    iconText.TextSize = 18
    iconText.Font = Enum.Font.GothamBold
    iconText.TextColor3 = Color3.new(1, 1, 1)
    iconText.Parent = iconBg

    -- Amount label
    local amountLabel = Components.CreateLabel({
        Name = "Amount",
        Text = "0",
        Size = UDim2.new(1, -42, 1, 0),
        Position = UDim2.new(0, 38, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container,
    })

    return container
end

-- ============================================================================
-- PROGRESS BAR COMPONENT
-- ============================================================================

function Components.CreateProgressBar(props: {
    Name: string?,
    Size: UDim2?,
    Position: UDim2?,
    AnchorPoint: Vector2?,
    FillColor: Color3?,
    BackgroundColor: Color3?,
    Progress: number?,
    ShowLabel: boolean?,
    Parent: GuiObject?,
}): Frame
    local container = Components.CreateFrame({
        Name = props.Name or "ProgressBar",
        Size = props.Size or UDim2.new(1, 0, 0, 12),
        Position = props.Position,
        AnchorPoint = props.AnchorPoint,
        BackgroundColor = props.BackgroundColor or Components.Colors.Background,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        BorderColor = Components.Colors.PanelBorder,
        Parent = props.Parent,
    })

    local fill = Components.CreateFrame({
        Name = "Fill",
        Size = UDim2.new(props.Progress or 0, 0, 1, -4),
        Position = UDim2.new(0, 2, 0, 2),
        BackgroundColor = props.FillColor or Components.Colors.Primary,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = container,
    })

    -- Shine effect on fill
    local shine = Instance.new("Frame")
    shine.Name = "Shine"
    shine.Size = UDim2.new(1, 0, 0.4, 0)
    shine.BackgroundColor3 = Color3.new(1, 1, 1)
    shine.BackgroundTransparency = 0.7
    shine.BorderSizePixel = 0
    shine.Parent = fill

    local shineCorner = Instance.new("UICorner")
    shineCorner.CornerRadius = Components.Sizes.CornerRadiusSmall
    shineCorner.Parent = shine

    if props.ShowLabel then
        local label = Components.CreateLabel({
            Name = "Label",
            Text = math.floor((props.Progress or 0) * 100) .. "%",
            Size = UDim2.new(1, 0, 1, 0),
            TextColor = Components.Colors.TextPrimary,
            TextSize = 10,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = container,
        })
    end

    return container
end

-- ============================================================================
-- PANEL COMPONENT (Ornate Fantasy Style)
-- ============================================================================

function Components.CreatePanel(props: {
    Name: string?,
    Title: string?,
    Size: UDim2?,
    Position: UDim2?,
    AnchorPoint: Vector2?,
    ShowCloseButton: boolean?,
    ShowCornerDecorations: boolean?,
    OnClose: (() -> ())?,
    Parent: GuiObject?,
}): Frame
    local panel = Components.CreateFrame({
        Name = props.Name or "Panel",
        Size = props.Size or UDim2.new(0, 320, 0, 420),
        Position = props.Position or UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
        BackgroundColor = Components.Colors.Panel,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        BorderColor = Components.Colors.GoldTrim,
        Parent = props.Parent,
    })

    -- Outer frame effect
    local outerStroke = Instance.new("UIStroke")
    outerStroke.Color = Components.Colors.WoodFrame
    outerStroke.Thickness = 4
    outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    outerStroke.Parent = panel

    -- Add corner decorations
    if props.ShowCornerDecorations ~= false then
        addCornerDecorations(panel, Components.Colors.GoldTrim)
    end

    -- Title bar
    local titleBar = Components.CreateFrame({
        Name = "TitleBar",
        Size = UDim2.new(1, -20, 0, 48),
        Position = UDim2.new(0.5, 0, 0, 10),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = Components.Colors.GoldDark,
        Parent = panel,
    })

    -- Title gradient
    local titleGradient = Instance.new("UIGradient")
    titleGradient.Rotation = 90
    titleGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.9, 0.9, 0.9)),
    })
    titleGradient.Parent = titleBar

    local titleLabel = Components.CreateLabel({
        Name = "Title",
        Text = props.Title or "Panel",
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 16, 0, 0),
        TextColor = Components.Colors.TextGold,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar,
    })

    if props.ShowCloseButton then
        local closeButton = Components.CreateButton({
            Name = "CloseButton",
            Text = "X",
            Size = UDim2.new(0, 36, 0, 36),
            Position = UDim2.new(1, -6, 0.5, 0),
            AnchorPoint = Vector2.new(1, 0.5),
            Style = "danger",
            OnClick = props.OnClose,
            Parent = titleBar,
        })
    end

    -- Content area
    local content = Components.CreateFrame({
        Name = "Content",
        Size = UDim2.new(1, -32, 1, -80),
        Position = UDim2.new(0.5, 0, 0, 66),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Parent = panel,
    })

    return panel
end

-- ============================================================================
-- SCROLLING FRAME COMPONENT
-- ============================================================================

function Components.CreateScrollFrame(props: {
    Name: string?,
    Size: UDim2?,
    Position: UDim2?,
    CanvasSize: UDim2?,
    Parent: GuiObject?,
}): ScrollingFrame
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = props.Name or "ScrollFrame"
    scroll.Size = props.Size or UDim2.new(1, 0, 1, 0)
    scroll.Position = props.Position or UDim2.new(0, 0, 0, 0)
    scroll.CanvasSize = props.CanvasSize or UDim2.new(0, 0, 0, 0)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.ScrollBarImageColor3 = Components.Colors.GoldDark
    scroll.ScrollBarImageTransparency = 0.3
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
    scroll.MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
    scroll.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"

    if props.Parent then
        scroll.Parent = props.Parent
    end

    return scroll
end

-- ============================================================================
-- LAYOUT COMPONENTS
-- ============================================================================

function Components.CreateGridLayout(props: {
    CellSize: UDim2?,
    CellPadding: UDim2?,
    SortOrder: Enum.SortOrder?,
    Parent: GuiObject?,
}): UIGridLayout
    local grid = Instance.new("UIGridLayout")
    grid.CellSize = props.CellSize or UDim2.new(0, 80, 0, 80)
    grid.CellPadding = props.CellPadding or UDim2.new(0, 8, 0, 8)
    grid.SortOrder = props.SortOrder or Enum.SortOrder.LayoutOrder
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center

    if props.Parent then
        grid.Parent = props.Parent
    end

    return grid
end

function Components.CreateListLayout(props: {
    Padding: UDim?,
    FillDirection: Enum.FillDirection?,
    HorizontalAlignment: Enum.HorizontalAlignment?,
    VerticalAlignment: Enum.VerticalAlignment?,
    SortOrder: Enum.SortOrder?,
    Parent: GuiObject?,
}): UIListLayout
    local list = Instance.new("UIListLayout")
    list.Padding = props.Padding or UDim.new(0, 8)
    list.FillDirection = props.FillDirection or Enum.FillDirection.Vertical
    list.HorizontalAlignment = props.HorizontalAlignment or Enum.HorizontalAlignment.Left
    list.VerticalAlignment = props.VerticalAlignment or Enum.VerticalAlignment.Top
    list.SortOrder = props.SortOrder or Enum.SortOrder.LayoutOrder

    if props.Parent then
        list.Parent = props.Parent
    end

    return list
end

-- ============================================================================
-- ANIMATION UTILITIES
-- ============================================================================

function Components.SlideIn(frame: GuiObject, direction: string?, duration: number?)
    direction = direction or "bottom"
    duration = duration or 0.35

    local startPos
    local endPos = frame.Position

    if direction == "bottom" then
        startPos = UDim2.new(endPos.X.Scale, endPos.X.Offset, 1.2, 0)
    elseif direction == "top" then
        startPos = UDim2.new(endPos.X.Scale, endPos.X.Offset, -0.2, 0)
    elseif direction == "left" then
        startPos = UDim2.new(-0.2, 0, endPos.Y.Scale, endPos.Y.Offset)
    elseif direction == "right" then
        startPos = UDim2.new(1.2, 0, endPos.Y.Scale, endPos.Y.Offset)
    end

    frame.Position = startPos
    frame.Visible = true

    local tween = TweenService:Create(
        frame,
        TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Position = endPos }
    )
    tween:Play()

    return tween
end

function Components.SlideOut(frame: GuiObject, direction: string?, duration: number?)
    direction = direction or "bottom"
    duration = duration or 0.25

    local startPos = frame.Position
    local endPos

    if direction == "bottom" then
        endPos = UDim2.new(startPos.X.Scale, startPos.X.Offset, 1.2, 0)
    elseif direction == "top" then
        endPos = UDim2.new(startPos.X.Scale, startPos.X.Offset, -0.2, 0)
    elseif direction == "left" then
        endPos = UDim2.new(-0.2, 0, startPos.Y.Scale, startPos.Y.Offset)
    elseif direction == "right" then
        endPos = UDim2.new(1.2, 0, startPos.Y.Scale, startPos.Y.Offset)
    end

    local tween = TweenService:Create(
        frame,
        TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        { Position = endPos }
    )
    tween:Play()

    tween.Completed:Connect(function()
        frame.Visible = false
        frame.Position = startPos
    end)

    return tween
end

function Components.ScaleIn(frame: GuiObject, duration: number?)
    duration = duration or 0.3

    frame.Size = UDim2.new(0, 0, 0, 0)
    frame.Visible = true

    local targetSize = frame:GetAttribute("TargetSize") or UDim2.new(0, 200, 0, 200)

    local tween = TweenService:Create(
        frame,
        TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = targetSize }
    )
    tween:Play()

    return tween
end

function Components.PulseGlow(frame: GuiObject, glowColor: Color3?, duration: number?)
    glowColor = glowColor or Components.Colors.Gold
    duration = duration or 1

    -- Find or create glow frame
    local glow = frame:FindFirstChild("PulseGlow")
    if not glow then
        glow = Instance.new("Frame")
        glow.Name = "PulseGlow"
        glow.Size = UDim2.new(1, 8, 1, 8)
        glow.Position = UDim2.new(0.5, 0, 0.5, 0)
        glow.AnchorPoint = Vector2.new(0.5, 0.5)
        glow.BackgroundColor3 = glowColor
        glow.BackgroundTransparency = 0.9
        glow.BorderSizePixel = 0
        glow.ZIndex = frame.ZIndex - 1
        glow.Parent = frame

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = glow
    end

    -- Pulse animation
    local pulseIn = TweenService:Create(
        glow,
        TweenInfo.new(duration / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
        { BackgroundTransparency = 0.6, Size = UDim2.new(1, 12, 1, 12) }
    )

    local pulseOut = TweenService:Create(
        glow,
        TweenInfo.new(duration / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
        { BackgroundTransparency = 0.9, Size = UDim2.new(1, 8, 1, 8) }
    )

    pulseIn:Play()
    pulseIn.Completed:Connect(function()
        pulseOut:Play()
    end)

    return pulseIn
end

-- ============================================================================
-- TOOLTIP COMPONENT
-- ============================================================================

function Components.CreateTooltip(props: {
    Text: string,
    Target: GuiObject,
    Parent: GuiObject?,
}): Frame
    local tooltip = Components.CreateFrame({
        Name = "Tooltip",
        Size = UDim2.new(0, 0, 0, 32),
        Position = UDim2.new(0.5, 0, 0, -40),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = Components.Colors.Background,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = Components.Colors.GoldDark,
        Parent = props.Parent or props.Target.Parent,
    })
    tooltip.Visible = false
    tooltip.AutomaticSize = Enum.AutomaticSize.X

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)
    padding.Parent = tooltip

    local label = Components.CreateLabel({
        Name = "Text",
        Text = props.Text,
        Size = UDim2.new(0, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = tooltip,
    })
    label.AutomaticSize = Enum.AutomaticSize.X

    -- Show/hide on hover
    props.Target.MouseEnter:Connect(function()
        tooltip.Visible = true
        TweenService:Create(tooltip, TWEEN_FAST, {
            BackgroundTransparency = 0
        }):Play()
    end)

    props.Target.MouseLeave:Connect(function()
        TweenService:Create(tooltip, TWEEN_FAST, {
            BackgroundTransparency = 1
        }):Play()
        task.delay(0.15, function()
            if tooltip then
                tooltip.Visible = false
            end
        end)
    end)

    return tooltip
end

-- ============================================================================
-- DIVIDER COMPONENT
-- ============================================================================

function Components.CreateDivider(props: {
    Size: UDim2?,
    Position: UDim2?,
    Color: Color3?,
    Parent: GuiObject?,
}): Frame
    local divider = Instance.new("Frame")
    divider.Name = "Divider"
    divider.Size = props.Size or UDim2.new(1, -16, 0, 2)
    divider.Position = props.Position or UDim2.new(0.5, 0, 0, 0)
    divider.AnchorPoint = Vector2.new(0.5, 0)
    divider.BackgroundColor3 = props.Color or Components.Colors.PanelBorder
    divider.BorderSizePixel = 0

    -- Gradient fade on edges
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(0.1, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(0.9, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
    })
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.1, 0),
        NumberSequenceKeypoint.new(0.9, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    gradient.Parent = divider

    if props.Parent then
        divider.Parent = props.Parent
    end

    return divider
end

return Components
