--!strict
--[[
    Components.lua

    Reusable UI component factory.
    Creates consistent UI elements with proper styling.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Components = {}

-- Color palette
Components.Colors = {
    -- Primary colors
    Primary = Color3.fromRGB(59, 130, 246),      -- Blue
    PrimaryDark = Color3.fromRGB(37, 99, 235),
    Secondary = Color3.fromRGB(34, 197, 94),     -- Green
    SecondaryDark = Color3.fromRGB(22, 163, 74),

    -- Resource colors
    Gold = Color3.fromRGB(234, 179, 8),
    Wood = Color3.fromRGB(139, 90, 43),
    Food = Color3.fromRGB(34, 197, 94),
    Gems = Color3.fromRGB(168, 85, 247),

    -- UI colors
    Background = Color3.fromRGB(30, 30, 40),
    BackgroundLight = Color3.fromRGB(45, 45, 60),
    Panel = Color3.fromRGB(40, 40, 55),
    PanelBorder = Color3.fromRGB(70, 70, 90),

    -- Text colors
    TextPrimary = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(180, 180, 200),
    TextMuted = Color3.fromRGB(120, 120, 140),

    -- Status colors
    Success = Color3.fromRGB(34, 197, 94),
    Warning = Color3.fromRGB(234, 179, 8),
    Danger = Color3.fromRGB(239, 68, 68),

    -- Button states
    ButtonHover = Color3.fromRGB(70, 70, 90),
    ButtonPressed = Color3.fromRGB(50, 50, 70),
    ButtonDisabled = Color3.fromRGB(60, 60, 75),
}

-- Standard sizes
Components.Sizes = {
    CornerRadius = UDim.new(0, 8),
    CornerRadiusSmall = UDim.new(0, 4),
    CornerRadiusLarge = UDim.new(0, 12),

    PaddingSmall = UDim.new(0, 4),
    PaddingMedium = UDim.new(0, 8),
    PaddingLarge = UDim.new(0, 16),

    FontSizeSmall = 12,
    FontSizeMedium = 14,
    FontSizeLarge = 18,
    FontSizeXLarge = 24,
    FontSizeTitle = 32,
}

-- Animation presets
local TWEEN_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MEDIUM = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SLOW = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--[[
    Creates a basic frame with optional corner radius.
]]
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
        local stroke = Instance.new("UIStroke")
        stroke.Color = props.BorderColor
        stroke.Thickness = 1
        stroke.Parent = frame
    end

    if props.Parent then
        frame.Parent = props.Parent
    end

    return frame
end

--[[
    Creates a text label with consistent styling.
]]
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

    if props.Parent then
        label.Parent = props.Parent
    end

    return label
end

--[[
    Creates a button with hover and press effects.
]]
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
    Parent: GuiObject?,
    OnClick: (() -> ())?,
}): TextButton
    local button = Instance.new("TextButton")
    button.Name = props.Name or "Button"
    button.Text = props.Text or "Button"
    button.Size = props.Size or UDim2.new(0, 120, 0, 40)
    button.Position = props.Position or UDim2.new(0, 0, 0, 0)
    button.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
    button.BackgroundColor3 = props.BackgroundColor or Components.Colors.Primary
    button.TextColor3 = props.TextColor or Components.Colors.TextPrimary
    button.TextSize = props.TextSize or Components.Sizes.FontSizeMedium
    button.Font = Enum.Font.GothamBold
    button.BorderSizePixel = 0
    button.AutoButtonColor = false

    local corner = Instance.new("UICorner")
    corner.CornerRadius = props.CornerRadius or Components.Sizes.CornerRadius
    corner.Parent = button

    -- Hover effects
    local originalColor = button.BackgroundColor3

    button.MouseEnter:Connect(function()
        TweenService:Create(button, TWEEN_FAST, {
            BackgroundColor3 = originalColor:Lerp(Color3.new(1, 1, 1), 0.1)
        }):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(button, TWEEN_FAST, {
            BackgroundColor3 = originalColor
        }):Play()
    end)

    button.MouseButton1Down:Connect(function()
        TweenService:Create(button, TWEEN_FAST, {
            BackgroundColor3 = originalColor:Lerp(Color3.new(0, 0, 0), 0.1)
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

--[[
    Creates a resource display (icon + amount).
]]
function Components.CreateResourceDisplay(props: {
    Name: string?,
    ResourceType: string, -- "Gold" | "Wood" | "Food" | "Gems"
    Size: UDim2?,
    Position: UDim2?,
    AnchorPoint: Vector2?,
    ShowCapacity: boolean?,
    Parent: GuiObject?,
}): Frame
    local colors = {
        Gold = Components.Colors.Gold,
        Wood = Components.Colors.Wood,
        Food = Components.Colors.Food,
        Gems = Components.Colors.Gems,
    }

    local color = colors[props.ResourceType] or Components.Colors.Gold

    local container = Components.CreateFrame({
        Name = props.Name or (props.ResourceType .. "Display"),
        Size = props.Size or UDim2.new(0, 120, 0, 36),
        Position = props.Position,
        AnchorPoint = props.AnchorPoint,
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = color,
        Parent = props.Parent,
    })

    -- Icon background
    local iconBg = Components.CreateFrame({
        Name = "IconBg",
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(0, 4, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = color,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = container,
    })

    -- Icon label (placeholder - would be ImageLabel in production)
    local iconLabel = Components.CreateLabel({
        Name = "Icon",
        Text = string.sub(props.ResourceType, 1, 1),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Amount label
    local amountLabel = Components.CreateLabel({
        Name = "Amount",
        Text = "0",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 36, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container,
    })

    return container
end

--[[
    Creates a progress bar.
]]
function Components.CreateProgressBar(props: {
    Name: string?,
    Size: UDim2?,
    Position: UDim2?,
    AnchorPoint: Vector2?,
    FillColor: Color3?,
    BackgroundColor: Color3?,
    Progress: number?, -- 0 to 1
    Parent: GuiObject?,
}): Frame
    local container = Components.CreateFrame({
        Name = props.Name or "ProgressBar",
        Size = props.Size or UDim2.new(1, 0, 0, 8),
        Position = props.Position,
        AnchorPoint = props.AnchorPoint,
        BackgroundColor = props.BackgroundColor or Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = props.Parent,
    })

    local fill = Components.CreateFrame({
        Name = "Fill",
        Size = UDim2.new(props.Progress or 0, 0, 1, 0),
        BackgroundColor = props.FillColor or Components.Colors.Primary,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = container,
    })

    return container
end

--[[
    Creates a panel with title bar.
]]
function Components.CreatePanel(props: {
    Name: string?,
    Title: string?,
    Size: UDim2?,
    Position: UDim2?,
    AnchorPoint: Vector2?,
    ShowCloseButton: boolean?,
    OnClose: (() -> ())?,
    Parent: GuiObject?,
}): Frame
    local panel = Components.CreateFrame({
        Name = props.Name or "Panel",
        Size = props.Size or UDim2.new(0, 300, 0, 400),
        Position = props.Position or UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
        BackgroundColor = Components.Colors.Panel,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        BorderColor = Components.Colors.PanelBorder,
        Parent = props.Parent,
    })

    -- Title bar
    local titleBar = Components.CreateFrame({
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor = Components.Colors.BackgroundLight,
        BackgroundTransparency = 1,
        Parent = panel,
    })

    local titleLabel = Components.CreateLabel({
        Name = "Title",
        Text = props.Title or "Panel",
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 16, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        Parent = titleBar,
    })

    if props.ShowCloseButton then
        local closeButton = Components.CreateButton({
            Name = "CloseButton",
            Text = "X",
            Size = UDim2.new(0, 32, 0, 32),
            Position = UDim2.new(1, -8, 0.5, 0),
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundColor = Components.Colors.Danger,
            TextSize = Components.Sizes.FontSizeMedium,
            OnClick = props.OnClose,
            Parent = titleBar,
        })
    end

    -- Content area
    local content = Components.CreateFrame({
        Name = "Content",
        Size = UDim2.new(1, -32, 1, -60),
        Position = UDim2.new(0, 16, 0, 52),
        BackgroundTransparency = 1,
        Parent = panel,
    })

    return panel
end

--[[
    Creates a scrolling frame.
]]
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
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Components.Colors.TextMuted
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    if props.Parent then
        scroll.Parent = props.Parent
    end

    return scroll
end

--[[
    Creates a grid/list layout.
]]
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

--[[
    Creates a list layout.
]]
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

--[[
    Animates a frame sliding in.
]]
function Components.SlideIn(frame: GuiObject, direction: string?, duration: number?)
    direction = direction or "bottom"
    duration = duration or 0.3

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

--[[
    Animates a frame sliding out.
]]
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

--[[
    Animates a frame fading in.
]]
function Components.FadeIn(frame: GuiObject, duration: number?)
    duration = duration or 0.2

    frame.Visible = true

    -- Find all descendants and fade them
    local function setTransparency(obj, value)
        if obj:IsA("Frame") or obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("ImageLabel") then
            if obj:IsA("Frame") then
                TweenService:Create(obj, TweenInfo.new(duration), {
                    BackgroundTransparency = value
                }):Play()
            end
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                TweenService:Create(obj, TweenInfo.new(duration), {
                    TextTransparency = value
                }):Play()
            end
        end
    end

    -- Simple approach: just make visible
    return nil
end

return Components
