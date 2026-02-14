--!strict
--[[
    OverworldHUD.lua

    Heads-up display for the overworld showing:
    - Mini-map
    - Player resources
    - Nearby player count
    - Teleport loading screen
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local OverworldHUD = {}
OverworldHUD.__index = OverworldHUD

-- Signal for Go to City button
OverworldHUD.GoToCityClicked = Signal.new()

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _initialized = false
local _player = Players.LocalPlayer
local _playerGui: PlayerGui? = nil

local _screenGui: ScreenGui? = nil
local _resourcesFrame: Frame? = nil
local _miniMapFrame: Frame? = nil
local _loadingFrame: Frame? = nil
local _errorFrame: Frame? = nil
local _goToCityButton: TextButton? = nil

-- ============================================================================
-- UI CREATION
-- ============================================================================

--[[
    Creates a resource display bar.
]]
local function createResourceBar(name: string, color: Color3, imageId: string, parent: Frame): Frame
    local frame = Instance.new("Frame")
    frame.Name = name .. "Bar"
    frame.Size = UDim2.new(0, 120, 0, 35)
    frame.BackgroundColor3 = Color3.fromRGB(40, 38, 35)
    frame.BorderSizePixel = 0
    frame.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame

    -- Icon
    local icon = Instance.new("Frame")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 25, 0, 25)
    icon.Position = UDim2.new(0, 5, 0.5, -12)
    icon.BackgroundColor3 = color
    icon.Parent = frame

    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(0, 4)
    iconCorner.Parent = icon

    local iconImage = Instance.new("ImageLabel")
    iconImage.Name = "IconImage"
    iconImage.Size = UDim2.new(0, 19, 0, 19)
    iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
    iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
    iconImage.BackgroundTransparency = 1
    iconImage.Image = imageId
    iconImage.ImageColor3 = Color3.new(1, 1, 1)
    iconImage.ScaleType = Enum.ScaleType.Fit
    iconImage.Parent = icon

    -- Value
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "Value"
    valueLabel.Size = UDim2.new(1, -40, 1, 0)
    valueLabel.Position = UDim2.new(0, 35, 0, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = "0"
    valueLabel.TextColor3 = Color3.fromRGB(240, 230, 200)
    valueLabel.TextSize = 16
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextXAlignment = Enum.TextXAlignment.Left
    valueLabel.Parent = frame

    return frame
end

--[[
    Creates the HUD UI.
]]
local function createHUD(): ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "OverworldHUD"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    -- Resources container (top-left)
    local resourcesFrame = Instance.new("Frame")
    resourcesFrame.Name = "Resources"
    resourcesFrame.Size = UDim2.new(0, 130, 0, 120)
    resourcesFrame.Position = UDim2.new(0, 15, 0, 15)
    resourcesFrame.BackgroundTransparency = 1
    resourcesFrame.Parent = screenGui

    local resourcesLayout = Instance.new("UIListLayout")
    resourcesLayout.FillDirection = Enum.FillDirection.Vertical
    resourcesLayout.Padding = UDim.new(0, 5)
    resourcesLayout.Parent = resourcesFrame

    -- Gold bar
    createResourceBar("Gold", Color3.fromRGB(255, 200, 50), "rbxassetid://132769554", resourcesFrame)

    -- Wood bar
    createResourceBar("Wood", Color3.fromRGB(139, 100, 60), "rbxassetid://16537944090", resourcesFrame)

    -- Food bar
    createResourceBar("Food", Color3.fromRGB(100, 180, 80), "rbxassetid://2958706766", resourcesFrame)

    _resourcesFrame = resourcesFrame

    -- Mini-map container (top-right)
    local miniMapFrame = Instance.new("Frame")
    miniMapFrame.Name = "MiniMap"
    miniMapFrame.Size = UDim2.new(0, 150, 0, 150)
    miniMapFrame.Position = UDim2.new(1, -165, 0, 15)
    miniMapFrame.BackgroundColor3 = Color3.fromRGB(30, 45, 25)
    miniMapFrame.BorderSizePixel = 0
    miniMapFrame.Parent = screenGui

    local miniMapCorner = Instance.new("UICorner")
    miniMapCorner.CornerRadius = UDim.new(0, 8)
    miniMapCorner.Parent = miniMapFrame

    local miniMapStroke = Instance.new("UIStroke")
    miniMapStroke.Color = Color3.fromRGB(80, 100, 60)
    miniMapStroke.Thickness = 2
    miniMapStroke.Parent = miniMapFrame

    -- Mini-map title
    local miniMapTitle = Instance.new("TextLabel")
    miniMapTitle.Name = "Title"
    miniMapTitle.Size = UDim2.new(1, 0, 0, 20)
    miniMapTitle.BackgroundTransparency = 1
    miniMapTitle.Text = "WORLD MAP"
    miniMapTitle.TextColor3 = Color3.fromRGB(150, 180, 130)
    miniMapTitle.TextSize = 10
    miniMapTitle.Font = Enum.Font.GothamBold
    miniMapTitle.Parent = miniMapFrame

    -- Player position indicator
    local playerDot = Instance.new("Frame")
    playerDot.Name = "PlayerDot"
    playerDot.Size = UDim2.new(0, 8, 0, 8)
    playerDot.Position = UDim2.new(0.5, -4, 0.5, -4)
    playerDot.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
    playerDot.Parent = miniMapFrame

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = playerDot

    -- Nearby count label
    local nearbyLabel = Instance.new("TextLabel")
    nearbyLabel.Name = "NearbyCount"
    nearbyLabel.Size = UDim2.new(1, 0, 0, 20)
    nearbyLabel.Position = UDim2.new(0, 0, 1, -20)
    nearbyLabel.BackgroundTransparency = 1
    nearbyLabel.Text = "0 players nearby"
    nearbyLabel.TextColor3 = Color3.fromRGB(120, 150, 100)
    nearbyLabel.TextSize = 10
    nearbyLabel.Font = Enum.Font.Gotham
    nearbyLabel.Parent = miniMapFrame

    _miniMapFrame = miniMapFrame

    -- Go to City button (bottom center)
    local goToCityButton = Instance.new("TextButton")
    goToCityButton.Name = "GoToCityButton"
    goToCityButton.Size = UDim2.new(0, 200, 0, 50)
    goToCityButton.Position = UDim2.new(0.5, -100, 1, -70)
    goToCityButton.BackgroundColor3 = Color3.fromRGB(80, 60, 40)
    goToCityButton.BorderSizePixel = 0
    goToCityButton.Text = "Go to City"
    goToCityButton.TextColor3 = Color3.fromRGB(255, 230, 180)
    goToCityButton.TextSize = 22
    goToCityButton.Font = Enum.Font.GothamBold
    goToCityButton.Parent = screenGui

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 10)
    buttonCorner.Parent = goToCityButton

    local buttonStroke = Instance.new("UIStroke")
    buttonStroke.Color = Color3.fromRGB(139, 100, 60)
    buttonStroke.Thickness = 3
    buttonStroke.Parent = goToCityButton

    -- Hover effect
    goToCityButton.MouseEnter:Connect(function()
        TweenService:Create(goToCityButton, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(100, 80, 50)
        }):Play()
    end)

    goToCityButton.MouseLeave:Connect(function()
        TweenService:Create(goToCityButton, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(80, 60, 40)
        }):Play()
    end)

    -- Click handler
    goToCityButton.MouseButton1Click:Connect(function()
        OverworldHUD.GoToCityClicked:Fire()
    end)

    _goToCityButton = goToCityButton

    -- Loading screen (for teleports)
    local loadingFrame = Instance.new("Frame")
    loadingFrame.Name = "LoadingScreen"
    loadingFrame.Size = UDim2.new(1, 0, 1, 0)
    loadingFrame.BackgroundColor3 = Color3.fromRGB(15, 12, 10)
    loadingFrame.BackgroundTransparency = 0
    loadingFrame.Visible = false
    loadingFrame.ZIndex = 100
    loadingFrame.Parent = screenGui

    local loadingLabel = Instance.new("TextLabel")
    loadingLabel.Name = "LoadingText"
    loadingLabel.Size = UDim2.new(1, 0, 0, 50)
    loadingLabel.Position = UDim2.new(0, 0, 0.5, -25)
    loadingLabel.BackgroundTransparency = 1
    loadingLabel.Text = "Teleporting..."
    loadingLabel.TextColor3 = Color3.fromRGB(200, 180, 140)
    loadingLabel.TextSize = 28
    loadingLabel.Font = Enum.Font.GothamBold
    loadingLabel.Parent = loadingFrame

    -- Loading spinner
    local spinner = Instance.new("Frame")
    spinner.Name = "Spinner"
    spinner.Size = UDim2.new(0, 40, 0, 40)
    spinner.Position = UDim2.new(0.5, -20, 0.5, 40)
    spinner.BackgroundColor3 = Color3.fromRGB(200, 180, 140)
    spinner.Parent = loadingFrame

    local spinnerCorner = Instance.new("UICorner")
    spinnerCorner.CornerRadius = UDim.new(1, 0)
    spinnerCorner.Parent = spinner

    _loadingFrame = loadingFrame

    -- Error notification
    local errorFrame = Instance.new("Frame")
    errorFrame.Name = "ErrorNotification"
    errorFrame.Size = UDim2.new(0, 300, 0, 50)
    errorFrame.Position = UDim2.new(0.5, -150, 0, -60)
    errorFrame.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
    errorFrame.Visible = false
    errorFrame.Parent = screenGui

    local errorCorner = Instance.new("UICorner")
    errorCorner.CornerRadius = UDim.new(0, 8)
    errorCorner.Parent = errorFrame

    local errorLabel = Instance.new("TextLabel")
    errorLabel.Name = "ErrorText"
    errorLabel.Size = UDim2.new(1, -20, 1, 0)
    errorLabel.Position = UDim2.new(0, 10, 0, 0)
    errorLabel.BackgroundTransparency = 1
    errorLabel.Text = "Error message"
    errorLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    errorLabel.TextSize = 14
    errorLabel.Font = Enum.Font.GothamBold
    errorLabel.TextXAlignment = Enum.TextXAlignment.Left
    errorLabel.Parent = errorFrame

    _errorFrame = errorFrame

    return screenGui
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Initializes the OverworldHUD.
]]
function OverworldHUD:Init()
    if _initialized then
        warn("[OverworldHUD] Already initialized")
        return
    end

    _playerGui = _player:WaitForChild("PlayerGui") :: PlayerGui

    -- Create UI
    _screenGui = createHUD()
    _screenGui.Parent = _playerGui

    _initialized = true
    print("[OverworldHUD] Initialized")
end

--[[
    Updates the resource display.

    @param resources table - Resource values {gold, wood, food}
]]
function OverworldHUD:UpdateResources(resources: {gold: number, wood: number, food: number})
    if not _resourcesFrame then return end

    local goldBar = _resourcesFrame:FindFirstChild("GoldBar") :: Frame?
    if goldBar then
        local value = goldBar:FindFirstChild("Value") :: TextLabel?
        if value then
            value.Text = tostring(resources.gold or 0)
        end
    end

    local woodBar = _resourcesFrame:FindFirstChild("WoodBar") :: Frame?
    if woodBar then
        local value = woodBar:FindFirstChild("Value") :: TextLabel?
        if value then
            value.Text = tostring(resources.wood or 0)
        end
    end

    local foodBar = _resourcesFrame:FindFirstChild("FoodBar") :: Frame?
    if foodBar then
        local value = foodBar:FindFirstChild("Value") :: TextLabel?
        if value then
            value.Text = tostring(resources.food or 0)
        end
    end
end

--[[
    Updates the mini-map player position.

    @param position Vector3 - World position
]]
function OverworldHUD:UpdatePlayerPosition(position: Vector3)
    if not _miniMapFrame then return end

    local playerDot = _miniMapFrame:FindFirstChild("PlayerDot") :: Frame?
    if not playerDot then return end

    local mapConfig = OverworldConfig.Map

    -- Convert world position to mini-map position
    local normalizedX = position.X / mapConfig.Width
    local normalizedZ = position.Z / mapConfig.Height

    -- Clamp to map bounds
    normalizedX = math.clamp(normalizedX, 0, 1)
    normalizedZ = math.clamp(normalizedZ, 0, 1)

    -- Position on mini-map (with padding)
    local padding = 0.1
    local mapX = padding + normalizedX * (1 - 2 * padding)
    local mapZ = padding + normalizedZ * (1 - 2 * padding)

    playerDot.Position = UDim2.new(mapX, -4, mapZ, -4)
end

--[[
    Updates the nearby player count.

    @param count number - Number of nearby players
]]
function OverworldHUD:UpdateNearbyCount(count: number)
    if not _miniMapFrame then return end

    local nearbyLabel = _miniMapFrame:FindFirstChild("NearbyCount") :: TextLabel?
    if nearbyLabel then
        nearbyLabel.Text = string.format("%d player%s nearby", count, count == 1 and "" or "s")
    end
end

--[[
    Shows the teleport loading screen.

    @param destination string - Where teleporting to
]]
function OverworldHUD:ShowTeleportLoading(destination: string)
    if not _loadingFrame then return end

    local loadingText = _loadingFrame:FindFirstChild("LoadingText") :: TextLabel?
    if loadingText then
        loadingText.Text = string.format("Teleporting to %s...", destination)
    end

    _loadingFrame.Visible = true
    _loadingFrame.BackgroundTransparency = 1

    -- Fade in
    local tween = TweenService:Create(
        _loadingFrame,
        TweenInfo.new(0.5),
        {BackgroundTransparency = 0}
    )
    tween:Play()

    -- Animate spinner
    local spinner = _loadingFrame:FindFirstChild("Spinner") :: Frame?
    if spinner then
        task.spawn(function()
            while _loadingFrame and _loadingFrame.Visible do
                local rotateTween = TweenService:Create(
                    spinner,
                    TweenInfo.new(1, Enum.EasingStyle.Linear),
                    {Rotation = spinner.Rotation + 360}
                )
                rotateTween:Play()
                task.wait(1)
            end
        end)
    end
end

--[[
    Hides the teleport loading screen.
]]
function OverworldHUD:HideTeleportLoading()
    if not _loadingFrame then return end

    local tween = TweenService:Create(
        _loadingFrame,
        TweenInfo.new(0.3),
        {BackgroundTransparency = 1}
    )
    tween:Play()
    tween.Completed:Connect(function()
        _loadingFrame.Visible = false
    end)
end

--[[
    Shows an error message.

    @param message string - Error message to display
]]
function OverworldHUD:ShowError(message: string)
    if not _errorFrame then return end

    local errorText = _errorFrame:FindFirstChild("ErrorText") :: TextLabel?
    if errorText then
        errorText.Text = message
    end

    -- Show and animate
    _errorFrame.Position = UDim2.new(0.5, -150, 0, -60)
    _errorFrame.Visible = true

    local slideIn = TweenService:Create(
        _errorFrame,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, -150, 0, 20)}
    )
    slideIn:Play()

    -- Auto-hide after 3 seconds
    task.delay(3, function()
        if not _errorFrame then return end

        local slideOut = TweenService:Create(
            _errorFrame,
            TweenInfo.new(0.2),
            {Position = UDim2.new(0.5, -150, 0, -60)}
        )
        slideOut:Play()
        slideOut.Completed:Connect(function()
            _errorFrame.Visible = false
        end)
    end)
end

--[[
    Hides the HUD.
]]
function OverworldHUD:Hide()
    if _screenGui then
        _screenGui.Enabled = false
    end
end

--[[
    Shows the HUD.
]]
function OverworldHUD:Show()
    if _screenGui then
        _screenGui.Enabled = true
    end
end

return OverworldHUD
