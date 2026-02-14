--!strict
--[[
    ResearchUI.lua

    Full-screen research panel showing research tree with categories,
    status indicators, and ability to start new research.

    Opened by: OpenResearchUI RemoteEvent (from server via ProximityPrompt)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ResearchUI = {}
ResearchUI.__index = ResearchUI

-- Private state
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _categoryTabs: Frame? = nil
local _contentArea: ScrollingFrame? = nil
local _detailPanel: Frame? = nil
local _isVisible = false
local _initialized = false
local _currentCategory = "Mining"
local _researchData = nil
local _selectedResearchId = nil

-- Colors
local COLORS = {
    background = Color3.fromRGB(25, 22, 20),
    panel = Color3.fromRGB(40, 35, 30),
    header = Color3.fromRGB(55, 48, 40),
    border = Color3.fromRGB(120, 100, 60),
    text = Color3.fromRGB(220, 210, 190),
    textDim = Color3.fromRGB(150, 140, 120),
    completed = Color3.fromRGB(60, 160, 60),
    available = Color3.fromRGB(200, 180, 60),
    inProgress = Color3.fromRGB(60, 140, 220),
    locked = Color3.fromRGB(80, 70, 60),
    button = Color3.fromRGB(80, 150, 80),
    buttonHover = Color3.fromRGB(100, 180, 100),
    close = Color3.fromRGB(180, 60, 60),
    gold = Color3.fromRGB(255, 215, 0),
    wood = Color3.fromRGB(139, 90, 43),
    food = Color3.fromRGB(76, 153, 0),
}

local CATEGORIES = {"Mining", "Forestry", "Agriculture", "Military", "Defense", "Universal"}

-- Helper to create UI elements
local function createFrame(props): Frame
    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = props.color or COLORS.panel
    frame.BorderSizePixel = 0
    frame.Size = props.size or UDim2.new(1, 0, 1, 0)
    frame.Position = props.position or UDim2.new(0, 0, 0, 0)
    if props.name then frame.Name = props.name end
    if props.parent then frame.Parent = props.parent end
    if props.cornerRadius then
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, props.cornerRadius)
        corner.Parent = frame
    end
    return frame
end

local function createLabel(props): TextLabel
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.TextColor3 = props.color or COLORS.text
    label.Font = props.font or Enum.Font.GothamBold
    label.TextSize = props.textSize or 14
    label.Text = props.text or ""
    label.Size = props.size or UDim2.new(1, 0, 0, 20)
    label.Position = props.position or UDim2.new(0, 0, 0, 0)
    label.TextXAlignment = props.align or Enum.TextXAlignment.Left
    if props.name then label.Name = props.name end
    if props.parent then label.Parent = props.parent end
    return label
end

local function createButton(props): TextButton
    local btn = Instance.new("TextButton")
    btn.BackgroundColor3 = props.color or COLORS.button
    btn.TextColor3 = props.textColor or Color3.new(1, 1, 1)
    btn.Font = props.font or Enum.Font.GothamBold
    btn.TextSize = props.textSize or 14
    btn.Text = props.text or "Button"
    btn.Size = props.size or UDim2.new(0, 120, 0, 36)
    btn.Position = props.position or UDim2.new(0, 0, 0, 0)
    btn.BorderSizePixel = 0
    if props.name then btn.Name = props.name end
    if props.parent then btn.Parent = props.parent end
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn
    return btn
end

local function formatTime(seconds: number): string
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    if m > 0 then
        return string.format("%dm %ds", m, s)
    end
    return string.format("%ds", s)
end

local function formatCost(cost): string
    local parts = {}
    if cost.gold then table.insert(parts, string.format("%d Gold", cost.gold)) end
    if cost.wood then table.insert(parts, string.format("%d Wood", cost.wood)) end
    if cost.food then table.insert(parts, string.format("%d Food", cost.food)) end
    return table.concat(parts, "  |  ")
end

-- Forward declarations for mutually referencing functions
local buildCategoryTabs
local buildResearchContent

-- Build the category tabs sidebar
buildCategoryTabs = function()
    if not _categoryTabs then return end
    -- Clear existing
    for _, child in _categoryTabs:GetChildren() do
        if child:IsA("TextButton") then child:Destroy() end
    end

    for idx, category in ipairs(CATEGORIES) do
        local tab = createButton({
            text = category,
            size = UDim2.new(1, -10, 0, 36),
            position = UDim2.new(0, 5, 0, 5 + (idx - 1) * 42),
            color = category == _currentCategory and COLORS.border or COLORS.panel,
            textColor = category == _currentCategory and Color3.new(0, 0, 0) or COLORS.text,
            name = "Tab_" .. category,
            parent = _categoryTabs,
        })

        tab.MouseButton1Click:Connect(function()
            _currentCategory = category
            buildCategoryTabs()
            buildResearchContent()
        end)
    end
end

-- Build research content area for current category
buildResearchContent = function()
    if not _contentArea or not _researchData then return end
    -- Clear existing
    for _, child in _contentArea:GetChildren() do
        if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
    end

    -- In-progress banner
    if _researchData.inProgress then
        local banner = createFrame({
            size = UDim2.new(1, -20, 0, 50),
            position = UDim2.new(0, 10, 0, 5),
            color = COLORS.inProgress,
            cornerRadius = 8,
            name = "InProgressBanner",
            parent = _contentArea,
        })
        createLabel({
            text = "IN PROGRESS: " .. _researchData.inProgress.name,
            size = UDim2.new(1, -10, 0, 20),
            position = UDim2.new(0, 10, 0, 5),
            font = Enum.Font.GothamBold,
            textSize = 14,
            color = Color3.new(1, 1, 1),
            parent = banner,
        })
        createLabel({
            text = formatTime(_researchData.inProgress.remaining) .. " remaining",
            size = UDim2.new(1, -10, 0, 20),
            position = UDim2.new(0, 10, 0, 25),
            font = Enum.Font.Gotham,
            textSize = 12,
            color = Color3.fromRGB(200, 220, 255),
            parent = banner,
        })
    end

    -- Collect research items for current category
    local categoryItems = {}
    if _researchData.allResearch then
        for id, data in pairs(_researchData.allResearch) do
            if data.category == _currentCategory then
                table.insert(categoryItems, data)
            end
        end
    end

    -- Sort: completed first, then available, then locked
    table.sort(categoryItems, function(a, b)
        local orderA = a.completed and 1 or (a.available and 2 or 3)
        local orderB = b.completed and 1 or (b.available and 2 or 3)
        if orderA ~= orderB then return orderA < orderB end
        return a.name < b.name
    end)

    local yOffset = _researchData.inProgress and 65 or 10

    if #categoryItems == 0 then
        createLabel({
            text = "No research in this category",
            size = UDim2.new(1, -20, 0, 30),
            position = UDim2.new(0, 10, 0, yOffset),
            color = COLORS.textDim,
            align = Enum.TextXAlignment.Center,
            parent = _contentArea,
        })
        return
    end

    for _, item in ipairs(categoryItems) do
        -- Determine status
        local status = "locked"
        local statusColor = COLORS.locked
        local statusText = "LOCKED"
        local isInProgress = _researchData.inProgress and _researchData.inProgress.id == item.id

        if item.completed then
            status = "completed"
            statusColor = COLORS.completed
            statusText = "COMPLETED"
        elseif isInProgress then
            status = "inProgress"
            statusColor = COLORS.inProgress
            statusText = "IN PROGRESS"
        elseif item.available then
            status = "available"
            statusColor = COLORS.available
            statusText = "AVAILABLE"
        end

        local card = createFrame({
            size = UDim2.new(1, -20, 0, 80),
            position = UDim2.new(0, 10, 0, yOffset),
            color = COLORS.panel,
            cornerRadius = 8,
            name = "Card_" .. item.id,
            parent = _contentArea,
        })

        -- Status indicator strip on left
        local strip = createFrame({
            size = UDim2.new(0, 4, 1, -8),
            position = UDim2.new(0, 4, 0, 4),
            color = statusColor,
            cornerRadius = 2,
            parent = card,
        })

        -- Name
        createLabel({
            text = item.name,
            size = UDim2.new(0.6, -20, 0, 22),
            position = UDim2.new(0, 16, 0, 6),
            font = Enum.Font.GothamBold,
            textSize = 15,
            color = item.completed and COLORS.completed or COLORS.text,
            parent = card,
        })

        -- Status badge
        createLabel({
            text = statusText,
            size = UDim2.new(0, 100, 0, 18),
            position = UDim2.new(1, -110, 0, 8),
            font = Enum.Font.GothamBold,
            textSize = 11,
            color = statusColor,
            align = Enum.TextXAlignment.Right,
            parent = card,
        })

        -- Description
        createLabel({
            text = item.description,
            size = UDim2.new(1, -20, 0, 18),
            position = UDim2.new(0, 16, 0, 28),
            font = Enum.Font.Gotham,
            textSize = 12,
            color = COLORS.textDim,
            parent = card,
        })

        -- Cost + Time row
        local costText = formatCost(item.cost) .. "  |  " .. formatTime(item.duration)
        createLabel({
            text = costText,
            size = UDim2.new(0.7, -20, 0, 16),
            position = UDim2.new(0, 16, 0, 50),
            font = Enum.Font.Gotham,
            textSize = 11,
            color = COLORS.textDim,
            parent = card,
        })

        -- TH requirement
        createLabel({
            text = "TH " .. tostring(item.thRequired),
            size = UDim2.new(0, 40, 0, 16),
            position = UDim2.new(1, -55, 0, 50),
            font = Enum.Font.GothamBold,
            textSize = 11,
            color = COLORS.textDim,
            align = Enum.TextXAlignment.Right,
            parent = card,
        })

        -- Research button (only for available items when nothing in progress)
        if status == "available" and not _researchData.inProgress then
            local researchBtn = createButton({
                text = "RESEARCH",
                size = UDim2.new(0, 90, 0, 26),
                position = UDim2.new(1, -100, 1, -32),
                color = COLORS.button,
                textSize = 12,
                parent = card,
            })

            researchBtn.MouseButton1Click:Connect(function()
                -- Send research request to server
                local events = ReplicatedStorage:FindFirstChild("Events")
                if events then
                    local startEvent = events:FindFirstChild("StartResearchRequest")
                    if startEvent then
                        startEvent:FireServer(item.id)
                    end
                end
            end)
        end

        yOffset = yOffset + 90
    end

    -- Set content size for scrolling
    _contentArea.CanvasSize = UDim2.new(0, 0, 0, yOffset + 10)
end

-- Create the main UI structure
local function createUI()
    -- Screen GUI
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "ResearchUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.Enabled = false

    -- Background overlay
    local overlay = createFrame({
        size = UDim2.new(1, 0, 1, 0),
        color = Color3.new(0, 0, 0),
        name = "Overlay",
        parent = _screenGui,
    })
    overlay.BackgroundTransparency = 0.4

    -- Main panel (centered, 700x500)
    _mainFrame = createFrame({
        size = UDim2.new(0, 700, 0, 500),
        position = UDim2.new(0.5, -350, 0.5, -250),
        color = COLORS.background,
        cornerRadius = 12,
        name = "MainPanel",
        parent = _screenGui,
    })

    -- Border
    local border = Instance.new("UIStroke")
    border.Color = COLORS.border
    border.Thickness = 2
    border.Parent = _mainFrame

    -- Header bar
    local header = createFrame({
        size = UDim2.new(1, 0, 0, 45),
        color = COLORS.header,
        cornerRadius = 12,
        name = "Header",
        parent = _mainFrame,
    })

    createLabel({
        text = "RESEARCH STATION",
        size = UDim2.new(1, -60, 1, 0),
        position = UDim2.new(0, 15, 0, 0),
        font = Enum.Font.GothamBold,
        textSize = 18,
        color = COLORS.gold,
        parent = header,
    })

    -- Resources display in header
    local resourceLabel = createLabel({
        text = "",
        size = UDim2.new(0, 300, 1, 0),
        position = UDim2.new(1, -350, 0, 0),
        font = Enum.Font.Gotham,
        textSize = 12,
        color = COLORS.text,
        align = Enum.TextXAlignment.Right,
        name = "ResourceLabel",
        parent = header,
    })

    -- Close button
    local closeBtn = createButton({
        text = "X",
        size = UDim2.new(0, 36, 0, 36),
        position = UDim2.new(1, -42, 0, 5),
        color = COLORS.close,
        textSize = 16,
        name = "CloseButton",
        parent = header,
    })

    closeBtn.MouseButton1Click:Connect(function()
        ResearchUI:Hide()
    end)

    -- Category tabs (left sidebar)
    _categoryTabs = createFrame({
        size = UDim2.new(0, 130, 1, -55),
        position = UDim2.new(0, 5, 0, 50),
        color = COLORS.background,
        name = "CategoryTabs",
        parent = _mainFrame,
    })

    -- Content area (scrolling frame)
    local contentContainer = createFrame({
        size = UDim2.new(1, -145, 1, -55),
        position = UDim2.new(0, 140, 0, 50),
        color = Color3.fromRGB(30, 27, 24),
        cornerRadius = 8,
        name = "ContentContainer",
        parent = _mainFrame,
    })

    _contentArea = Instance.new("ScrollingFrame")
    _contentArea.Name = "ContentScroll"
    _contentArea.Size = UDim2.new(1, 0, 1, 0)
    _contentArea.BackgroundTransparency = 1
    _contentArea.ScrollBarThickness = 6
    _contentArea.ScrollBarImageColor3 = COLORS.border
    _contentArea.CanvasSize = UDim2.new(0, 0, 0, 0)
    _contentArea.Parent = contentContainer

    _screenGui.Parent = playerGui
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function ResearchUI:Init()
    if _initialized then return end

    createUI()

    -- Listen for server events
    local events = ReplicatedStorage:WaitForChild("Events", 10)
    if events then
        local openEvent = events:WaitForChild("OpenResearchUI", 5)
        if openEvent then
            openEvent.OnClientEvent:Connect(function(data)
                _researchData = data
                ResearchUI:Show()
            end)
        end

        local updateEvent = events:WaitForChild("ResearchUpdate", 5)
        if updateEvent then
            updateEvent.OnClientEvent:Connect(function(data)
                if data.action == "started" then
                    -- Update local state
                    if _researchData and _researchData.allResearch and _researchData.allResearch[data.researchId] then
                        -- Mark as in progress
                        _researchData.inProgress = {
                            id = data.researchId,
                            name = _researchData.allResearch[data.researchId].name,
                            description = _researchData.allResearch[data.researchId].description,
                            category = _researchData.allResearch[data.researchId].category,
                            remaining = data.remaining,
                            duration = _researchData.allResearch[data.researchId].duration,
                        }
                        -- Update resources
                        if data.resources then
                            _researchData.resources = data.resources
                        end
                        -- Refresh UI
                        buildCategoryTabs()
                        buildResearchContent()
                        -- Update resource label
                        if _mainFrame then
                            local header = _mainFrame:FindFirstChild("Header")
                            if header then
                                local resLabel = header:FindFirstChild("ResourceLabel")
                                if resLabel then
                                    (resLabel :: TextLabel).Text = string.format("Gold: %d  |  Wood: %d  |  Food: %d",
                                        _researchData.resources.gold or 0,
                                        _researchData.resources.wood or 0,
                                        _researchData.resources.food or 0)
                                end
                            end
                        end
                    end
                elseif data.action == "completed" then
                    -- Mark research as completed locally
                    if _researchData and _researchData.allResearch and data.researchId then
                        if _researchData.allResearch[data.researchId] then
                            _researchData.allResearch[data.researchId].completed = true
                        end
                        _researchData.inProgress = nil
                        -- Refresh if visible
                        if _isVisible then
                            buildCategoryTabs()
                            buildResearchContent()
                        end
                    end
                elseif data.action == "failed" then
                    -- Show error (could add a toast notification)
                    warn("[ResearchUI] Research failed:", data.error or "Unknown error")
                end
            end)
        end
    end

    _initialized = true
    print("[ResearchUI] Initialized")
end

function ResearchUI:Show()
    if not _screenGui or not _mainFrame then return end
    if not _researchData then return end

    -- Update resource label
    local header = _mainFrame:FindFirstChild("Header")
    if header then
        local resLabel = header:FindFirstChild("ResourceLabel") :: TextLabel?
        if resLabel and _researchData.resources then
            resLabel.Text = string.format("Gold: %d  |  Wood: %d  |  Food: %d",
                _researchData.resources.gold or 0,
                _researchData.resources.wood or 0,
                _researchData.resources.food or 0)
        end
    end

    -- Build tabs and content
    _currentCategory = "Mining" -- Reset to first tab
    buildCategoryTabs()
    buildResearchContent()

    -- Show with animation
    _mainFrame.Position = UDim2.new(0.5, -350, 1, 100) -- Start off screen
    _screenGui.Enabled = true
    _isVisible = true

    local tween = TweenService:Create(
        _mainFrame,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, -350, 0.5, -250)}
    )
    tween:Play()
end

function ResearchUI:Hide()
    if not _screenGui or not _mainFrame then return end

    _isVisible = false

    local tween = TweenService:Create(
        _mainFrame,
        TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {Position = UDim2.new(0.5, -350, 1, 100)}
    )
    tween:Play()
    tween.Completed:Connect(function()
        if not _isVisible then
            _screenGui.Enabled = false
        end
    end)
end

function ResearchUI:IsVisible(): boolean
    return _isVisible
end

function ResearchUI:IsInitialized(): boolean
    return _initialized
end

return ResearchUI
