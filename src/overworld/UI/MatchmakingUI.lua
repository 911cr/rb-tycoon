--!strict
--[[
    MatchmakingUI.lua

    Client-side matchmaking interface for finding and attacking opponents.
    Shows a searching spinner, opponent preview with stats and loot,
    and action buttons (Attack, Next, Cancel).

    SECURITY: All matchmaking logic is server-authoritative.
    This UI only displays server-provided data and sends requests.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local MatchmakingUI = {}
MatchmakingUI.__index = MatchmakingUI

-- ============================================================================
-- SIGNALS
-- ============================================================================

MatchmakingUI.AttackClicked = Signal.new()
MatchmakingUI.NextClicked = Signal.new()
MatchmakingUI.CancelClicked = Signal.new()

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _initialized = false
local _player = Players.LocalPlayer
local _playerGui: PlayerGui? = nil

local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _searchingFrame: Frame? = nil
local _opponentFrame: Frame? = nil
local _isVisible = false
local _isSearching = false
local _spinnerConnection: RBXScriptConnection? = nil

-- Events
local _requestMatchmaking: RemoteEvent? = nil
local _matchmakingResult: RemoteEvent? = nil
local _confirmMatchmaking: RemoteEvent? = nil
local _resultConnection: RBXScriptConnection? = nil

-- Current opponent data from server
local _currentOpponent: any? = nil
local _currentSkipCost: number = 0

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Formats a number with commas for readability.
    e.g. 12500 -> "12,500"
]]
local function formatNumber(num: number): string
    local formatted = tostring(math.floor(num))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

-- ============================================================================
-- UI CREATION
-- ============================================================================

--[[
    Creates a stat display with label and value.
]]
local function createStatDisplay(name: string, label: string, color: Color3, parent: Frame): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.Size = UDim2.new(0, 90, 0, 50)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "Value"
    valueLabel.Size = UDim2.new(1, 0, 0.6, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = "0"
    valueLabel.TextColor3 = color
    valueLabel.TextSize = 22
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.Parent = frame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0.4, 0)
    titleLabel.Position = UDim2.new(0, 0, 0.6, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = label
    titleLabel.TextColor3 = Color3.fromRGB(150, 140, 120)
    titleLabel.TextSize = 11
    titleLabel.Font = Enum.Font.Gotham
    titleLabel.Parent = frame

    return frame
end

--[[
    Creates a loot row showing resource icon + amount.
]]
local function createLootRow(name: string, label: string, color: Color3, parent: Frame): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.Size = UDim2.new(1, 0, 0, 22)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    -- Color indicator
    local colorDot = Instance.new("Frame")
    colorDot.Name = "ColorDot"
    colorDot.Size = UDim2.new(0, 14, 0, 14)
    colorDot.Position = UDim2.new(0, 0, 0.5, -7)
    colorDot.BackgroundColor3 = color
    colorDot.Parent = frame

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(0, 3)
    dotCorner.Parent = colorDot

    -- Resource name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "Label"
    nameLabel.Size = UDim2.new(0, 60, 1, 0)
    nameLabel.Position = UDim2.new(0, 20, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = label
    nameLabel.TextColor3 = Color3.fromRGB(180, 170, 150)
    nameLabel.TextSize = 13
    nameLabel.Font = Enum.Font.Gotham
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Parent = frame

    -- Resource amount
    local amountLabel = Instance.new("TextLabel")
    amountLabel.Name = "Amount"
    amountLabel.Size = UDim2.new(1, -90, 1, 0)
    amountLabel.Position = UDim2.new(0, 85, 0, 0)
    amountLabel.BackgroundTransparency = 1
    amountLabel.Text = "0"
    amountLabel.TextColor3 = Color3.fromRGB(240, 230, 200)
    amountLabel.TextSize = 14
    amountLabel.Font = Enum.Font.GothamBold
    amountLabel.TextXAlignment = Enum.TextXAlignment.Left
    amountLabel.Parent = frame

    return frame
end

--[[
    Creates a styled button.
]]
local function createButton(name: string, text: string, color: Color3, size: UDim2, parent: Frame): TextButton
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = size
    button.BackgroundColor3 = color
    button.Text = text
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 15
    button.Font = Enum.Font.GothamBold
    button.BorderSizePixel = 0
    button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    -- Hover effects
    local originalColor = color
    button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.new(
                math.min(originalColor.R * 1.2, 1),
                math.min(originalColor.G * 1.2, 1),
                math.min(originalColor.B * 1.2, 1)
            ),
        }):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.15), {
            BackgroundColor3 = originalColor,
        }):Play()
    end)

    return button
end

--[[
    Creates the searching overlay (spinner + text).
]]
local function createSearchingFrame(parent: Frame): Frame
    local frame = Instance.new("Frame")
    frame.Name = "SearchingFrame"
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.Visible = false
    frame.ZIndex = 5
    frame.Parent = parent

    -- Spinner circle
    local spinner = Instance.new("Frame")
    spinner.Name = "Spinner"
    spinner.Size = UDim2.new(0, 50, 0, 50)
    spinner.Position = UDim2.new(0.5, -25, 0.35, -25)
    spinner.BackgroundColor3 = Color3.fromRGB(200, 180, 100)
    spinner.BackgroundTransparency = 0.3
    spinner.Parent = frame

    local spinnerCorner = Instance.new("UICorner")
    spinnerCorner.CornerRadius = UDim.new(1, 0)
    spinnerCorner.Parent = spinner

    -- Spinner inner dot
    local innerDot = Instance.new("Frame")
    innerDot.Name = "InnerDot"
    innerDot.Size = UDim2.new(0, 14, 0, 14)
    innerDot.Position = UDim2.new(0.5, -7, 0, -2)
    innerDot.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
    innerDot.Parent = spinner

    local innerCorner = Instance.new("UICorner")
    innerCorner.CornerRadius = UDim.new(1, 0)
    innerCorner.Parent = innerDot

    -- Searching text
    local searchLabel = Instance.new("TextLabel")
    searchLabel.Name = "SearchLabel"
    searchLabel.Size = UDim2.new(1, 0, 0, 30)
    searchLabel.Position = UDim2.new(0, 0, 0.55, 0)
    searchLabel.BackgroundTransparency = 1
    searchLabel.Text = "Searching for opponent..."
    searchLabel.TextColor3 = Color3.fromRGB(220, 210, 180)
    searchLabel.TextSize = 16
    searchLabel.Font = Enum.Font.GothamBold
    searchLabel.Parent = frame

    -- Sub-text
    local subLabel = Instance.new("TextLabel")
    subLabel.Name = "SubLabel"
    subLabel.Size = UDim2.new(1, 0, 0, 20)
    subLabel.Position = UDim2.new(0, 0, 0.55, 30)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = "Finding a worthy opponent..."
    subLabel.TextColor3 = Color3.fromRGB(140, 130, 110)
    subLabel.TextSize = 12
    subLabel.Font = Enum.Font.Gotham
    subLabel.Parent = frame

    -- Cancel button during search
    local cancelBtn = createButton(
        "CancelSearchButton",
        "CANCEL",
        Color3.fromRGB(120, 60, 60),
        UDim2.new(0, 120, 0, 35),
        frame
    )
    cancelBtn.Position = UDim2.new(0.5, -60, 0.75, 0)

    return frame
end

--[[
    Creates the opponent preview frame (shown after opponent is found).
]]
local function createOpponentFrame(parent: Frame): Frame
    local frame = Instance.new("Frame")
    frame.Name = "OpponentFrame"
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.Visible = false
    frame.Parent = parent

    -- Opponent name header
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "OpponentName"
    nameLabel.Size = UDim2.new(1, -20, 0, 30)
    nameLabel.Position = UDim2.new(0, 10, 0, 50)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = "Opponent Name"
    nameLabel.TextColor3 = Color3.fromRGB(255, 230, 180)
    nameLabel.TextSize = 20
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.Parent = frame

    -- Stats row
    local statsFrame = Instance.new("Frame")
    statsFrame.Name = "StatsFrame"
    statsFrame.Size = UDim2.new(1, -20, 0, 55)
    statsFrame.Position = UDim2.new(0, 10, 0, 85)
    statsFrame.BackgroundTransparency = 1
    statsFrame.Parent = frame

    local statsLayout = Instance.new("UIListLayout")
    statsLayout.FillDirection = Enum.FillDirection.Horizontal
    statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    statsLayout.Padding = UDim.new(0, 25)
    statsLayout.Parent = statsFrame

    createStatDisplay("THLevel", "Town Hall", Color3.fromRGB(255, 200, 80), statsFrame)
    createStatDisplay("Trophies", "Trophies", Color3.fromRGB(255, 200, 80), statsFrame)

    -- Divider line
    local divider = Instance.new("Frame")
    divider.Name = "Divider"
    divider.Size = UDim2.new(0.8, 0, 0, 1)
    divider.Position = UDim2.new(0.1, 0, 0, 148)
    divider.BackgroundColor3 = Color3.fromRGB(80, 70, 60)
    divider.BorderSizePixel = 0
    divider.Parent = frame

    -- Loot section header
    local lootHeader = Instance.new("TextLabel")
    lootHeader.Name = "LootHeader"
    lootHeader.Size = UDim2.new(1, -20, 0, 22)
    lootHeader.Position = UDim2.new(0, 10, 0, 155)
    lootHeader.BackgroundTransparency = 1
    lootHeader.Text = "AVAILABLE LOOT"
    lootHeader.TextColor3 = Color3.fromRGB(130, 120, 100)
    lootHeader.TextSize = 11
    lootHeader.Font = Enum.Font.GothamBold
    lootHeader.TextXAlignment = Enum.TextXAlignment.Left
    lootHeader.Parent = frame

    -- Loot container
    local lootFrame = Instance.new("Frame")
    lootFrame.Name = "LootFrame"
    lootFrame.Size = UDim2.new(1, -20, 0, 75)
    lootFrame.Position = UDim2.new(0, 10, 0, 178)
    lootFrame.BackgroundTransparency = 1
    lootFrame.Parent = frame

    local lootLayout = Instance.new("UIListLayout")
    lootLayout.FillDirection = Enum.FillDirection.Vertical
    lootLayout.Padding = UDim.new(0, 3)
    lootLayout.Parent = lootFrame

    createLootRow("GoldLoot", "Gold", Color3.fromRGB(255, 200, 50), lootFrame)
    createLootRow("WoodLoot", "Wood", Color3.fromRGB(139, 100, 60), lootFrame)
    createLootRow("FoodLoot", "Food", Color3.fromRGB(100, 180, 80), lootFrame)

    -- Buttons row
    local buttonsFrame = Instance.new("Frame")
    buttonsFrame.Name = "ButtonsFrame"
    buttonsFrame.Size = UDim2.new(1, -20, 0, 45)
    buttonsFrame.Position = UDim2.new(0, 10, 1, -60)
    buttonsFrame.BackgroundTransparency = 1
    buttonsFrame.Parent = frame

    local buttonsLayout = Instance.new("UIListLayout")
    buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
    buttonsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    buttonsLayout.Padding = UDim.new(0, 10)
    buttonsLayout.Parent = buttonsFrame

    -- Attack button
    createButton(
        "AttackButton",
        "ATTACK",
        Color3.fromRGB(180, 60, 60),
        UDim2.new(0, 110, 0, 40),
        buttonsFrame
    )

    -- Next button
    local nextBtn = createButton(
        "NextButton",
        "NEXT",
        Color3.fromRGB(80, 120, 180),
        UDim2.new(0, 90, 0, 40),
        buttonsFrame
    )

    -- Cost label under Next button
    local costLabel = Instance.new("TextLabel")
    costLabel.Name = "SkipCostLabel"
    costLabel.Size = UDim2.new(1, 0, 0, 14)
    costLabel.Position = UDim2.new(0, 0, 1, 1)
    costLabel.BackgroundTransparency = 1
    costLabel.Text = "Free"
    costLabel.TextColor3 = Color3.fromRGB(120, 200, 80)
    costLabel.TextSize = 10
    costLabel.Font = Enum.Font.Gotham
    costLabel.Parent = nextBtn

    -- Cancel button
    createButton(
        "CancelButton",
        "CANCEL",
        Color3.fromRGB(100, 90, 80),
        UDim2.new(0, 90, 0, 40),
        buttonsFrame
    )

    return frame
end

--[[
    Creates the full matchmaking UI.
]]
local function createUI(): ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MatchmakingUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 10
    screenGui.Enabled = false

    -- Backdrop (semi-transparent dark overlay)
    local backdrop = Instance.new("Frame")
    backdrop.Name = "Backdrop"
    backdrop.Size = UDim2.new(1, 0, 1, 0)
    backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    backdrop.BackgroundTransparency = 0.5
    backdrop.BorderSizePixel = 0
    backdrop.ZIndex = 1
    backdrop.Parent = screenGui

    -- Main panel
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 360, 0, 380)
    mainFrame.Position = UDim2.new(0.5, -180, 0.5, -190)
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 28, 25)
    mainFrame.BackgroundTransparency = 0.02
    mainFrame.BorderSizePixel = 0
    mainFrame.ZIndex = 2
    mainFrame.Parent = screenGui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(120, 100, 60)
    mainStroke.Thickness = 2
    mainStroke.Parent = mainFrame

    -- Title header
    local headerFrame = Instance.new("Frame")
    headerFrame.Name = "Header"
    headerFrame.Size = UDim2.new(1, 0, 0, 45)
    headerFrame.BackgroundColor3 = Color3.fromRGB(50, 45, 40)
    headerFrame.BorderSizePixel = 0
    headerFrame.ZIndex = 3
    headerFrame.Parent = mainFrame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 12)
    headerCorner.Parent = headerFrame

    -- Cover bottom corners of header
    local headerFix = Instance.new("Frame")
    headerFix.Name = "HeaderFix"
    headerFix.Size = UDim2.new(1, 0, 0, 12)
    headerFix.Position = UDim2.new(0, 0, 1, -12)
    headerFix.BackgroundColor3 = Color3.fromRGB(50, 45, 40)
    headerFix.BorderSizePixel = 0
    headerFix.ZIndex = 3
    headerFix.Parent = headerFrame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(1, 0, 1, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "FIND BATTLE"
    titleLabel.TextColor3 = Color3.fromRGB(240, 220, 180)
    titleLabel.TextSize = 18
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.ZIndex = 4
    titleLabel.Parent = headerFrame

    -- Content area (holds searching and opponent frames)
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "ContentFrame"
    contentFrame.Size = UDim2.new(1, 0, 1, -45)
    contentFrame.Position = UDim2.new(0, 0, 0, 45)
    contentFrame.BackgroundTransparency = 1
    contentFrame.ZIndex = 2
    contentFrame.Parent = mainFrame

    -- Create sub-frames
    local searchingFrame = createSearchingFrame(contentFrame)
    local opponentFrame = createOpponentFrame(contentFrame)

    _mainFrame = mainFrame
    _searchingFrame = searchingFrame
    _opponentFrame = opponentFrame

    return screenGui
end

-- ============================================================================
-- ANIMATION
-- ============================================================================

--[[
    Starts the spinner rotation animation.
]]
local function startSpinner()
    if _spinnerConnection then
        _spinnerConnection:Disconnect()
    end

    if not _searchingFrame then return end

    local spinner = _searchingFrame:FindFirstChild("Spinner") :: Frame?
    if not spinner then return end

    _spinnerConnection = task.spawn(function()
        while _isSearching and _searchingFrame and _searchingFrame.Visible do
            local tween = TweenService:Create(
                spinner,
                TweenInfo.new(1, Enum.EasingStyle.Linear),
                { Rotation = spinner.Rotation + 360 }
            )
            tween:Play()
            task.wait(1)
        end
    end) :: any
end

--[[
    Stops the spinner rotation animation.
]]
local function stopSpinner()
    _isSearching = false
    -- The spinner loop checks _isSearching and will exit
end

-- ============================================================================
-- UI UPDATE FUNCTIONS
-- ============================================================================

--[[
    Shows the searching state (spinner + searching text).
]]
local function showSearching()
    if _searchingFrame then
        _searchingFrame.Visible = true
    end
    if _opponentFrame then
        _opponentFrame.Visible = false
    end

    _isSearching = true
    startSpinner()
end

--[[
    Shows the opponent preview with data from the server.
]]
local function showOpponent(data: any)
    stopSpinner()

    if _searchingFrame then
        _searchingFrame.Visible = false
    end
    if not _opponentFrame then return end

    _opponentFrame.Visible = true

    -- Update opponent name
    local nameLabel = _opponentFrame:FindFirstChild("OpponentName") :: TextLabel?
    if nameLabel then
        nameLabel.Text = data.username or "Unknown"
    end

    -- Update stats
    local statsFrame = _opponentFrame:FindFirstChild("StatsFrame") :: Frame?
    if statsFrame then
        local thLevel = statsFrame:FindFirstChild("THLevel") :: Frame?
        if thLevel then
            local value = thLevel:FindFirstChild("Value") :: TextLabel?
            if value then
                value.Text = tostring(data.townHallLevel or 1)
            end
        end

        local trophies = statsFrame:FindFirstChild("Trophies") :: Frame?
        if trophies then
            local value = trophies:FindFirstChild("Value") :: TextLabel?
            if value then
                value.Text = formatNumber(data.trophies or 0)
            end
        end
    end

    -- Update loot
    local lootFrame = _opponentFrame:FindFirstChild("LootFrame") :: Frame?
    if lootFrame and data.lootAvailable then
        local goldLoot = lootFrame:FindFirstChild("GoldLoot") :: Frame?
        if goldLoot then
            local amount = goldLoot:FindFirstChild("Amount") :: TextLabel?
            if amount then
                amount.Text = formatNumber(data.lootAvailable.gold or 0)
            end
        end

        local woodLoot = lootFrame:FindFirstChild("WoodLoot") :: Frame?
        if woodLoot then
            local amount = woodLoot:FindFirstChild("Amount") :: TextLabel?
            if amount then
                amount.Text = formatNumber(data.lootAvailable.wood or 0)
            end
        end

        local foodLoot = lootFrame:FindFirstChild("FoodLoot") :: Frame?
        if foodLoot then
            local amount = foodLoot:FindFirstChild("Amount") :: TextLabel?
            if amount then
                amount.Text = formatNumber(data.lootAvailable.food or 0)
            end
        end
    end
end

--[[
    Updates the skip cost label on the Next button.
]]
local function updateSkipCost(cost: number)
    if not _opponentFrame then return end

    local buttonsFrame = _opponentFrame:FindFirstChild("ButtonsFrame") :: Frame?
    if not buttonsFrame then return end

    local nextButton = buttonsFrame:FindFirstChild("NextButton") :: TextButton?
    if not nextButton then return end

    local costLabel = nextButton:FindFirstChild("SkipCostLabel") :: TextLabel?
    if costLabel then
        if cost <= 0 then
            costLabel.Text = "Free"
            costLabel.TextColor3 = Color3.fromRGB(120, 200, 80)
        else
            costLabel.Text = formatNumber(cost) .. " gold"
            costLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
        end
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Initializes the MatchmakingUI.
]]
function MatchmakingUI:Init()
    if _initialized then
        warn("[MatchmakingUI] Already initialized")
        return
    end

    _playerGui = _player:WaitForChild("PlayerGui") :: PlayerGui

    -- Create UI
    _screenGui = createUI()
    _screenGui.Parent = _playerGui

    -- Get events
    local events = ReplicatedStorage:WaitForChild("Events", 10) :: Folder?
    if events then
        _requestMatchmaking = events:FindFirstChild("RequestMatchmaking") :: RemoteEvent?
        _matchmakingResult = events:FindFirstChild("MatchmakingResult") :: RemoteEvent?
        _confirmMatchmaking = events:FindFirstChild("ConfirmMatchmaking") :: RemoteEvent?
    end

    -- Connect matchmaking result from server
    if _matchmakingResult then
        _resultConnection = _matchmakingResult.OnClientEvent:Connect(function(result)
            if not _isVisible then return end

            if result.success and result.target then
                _currentOpponent = result.target
                _currentSkipCost = result.skipCost or 0
                showOpponent(result.target)
                updateSkipCost(_currentSkipCost)
            else
                -- Search failed - show error and return to searching or close
                local errorMsg = result.error or "Search failed"
                print("[MatchmakingUI] Search failed:", errorMsg)

                -- Show a brief error in the searching frame
                if _searchingFrame then
                    local subLabel = _searchingFrame:FindFirstChild("SubLabel") :: TextLabel?
                    if subLabel then
                        subLabel.Text = "No opponents found. Try again..."
                        subLabel.TextColor3 = Color3.fromRGB(200, 120, 80)
                    end
                end

                -- Stay visible so player can cancel or wait
                stopSpinner()
            end
        end)
    end

    -- Connect button clicks
    -- Attack button in opponent frame
    if _opponentFrame then
        local buttonsFrame = _opponentFrame:FindFirstChild("ButtonsFrame") :: Frame?
        if buttonsFrame then
            local attackButton = buttonsFrame:FindFirstChild("AttackButton") :: TextButton?
            if attackButton then
                attackButton.MouseButton1Click:Connect(function()
                    if _currentOpponent and _confirmMatchmaking then
                        _confirmMatchmaking:FireServer(_currentOpponent.userId)
                        self.AttackClicked:Fire(_currentOpponent)
                        self:Hide()
                    end
                end)
            end

            local nextButton = buttonsFrame:FindFirstChild("NextButton") :: TextButton?
            if nextButton then
                nextButton.MouseButton1Click:Connect(function()
                    -- Request next opponent
                    showSearching()
                    if _requestMatchmaking then
                        _requestMatchmaking:FireServer()
                    end
                    self.NextClicked:Fire()
                end)
            end

            local cancelButton = buttonsFrame:FindFirstChild("CancelButton") :: TextButton?
            if cancelButton then
                cancelButton.MouseButton1Click:Connect(function()
                    self:Hide()
                    self.CancelClicked:Fire()
                end)
            end
        end
    end

    -- Cancel button in searching frame
    if _searchingFrame then
        local cancelSearchButton = _searchingFrame:FindFirstChild("CancelSearchButton") :: TextButton?
        if cancelSearchButton then
            cancelSearchButton.MouseButton1Click:Connect(function()
                self:Hide()
                self.CancelClicked:Fire()
            end)
        end
    end

    -- Close on backdrop click
    if _screenGui then
        local backdrop = _screenGui:FindFirstChild("Backdrop") :: Frame?
        if backdrop then
            local backdropButton = Instance.new("TextButton")
            backdropButton.Name = "BackdropButton"
            backdropButton.Size = UDim2.new(1, 0, 1, 0)
            backdropButton.BackgroundTransparency = 1
            backdropButton.Text = ""
            backdropButton.ZIndex = 1
            backdropButton.Parent = backdrop

            backdropButton.MouseButton1Click:Connect(function()
                self:Hide()
                self.CancelClicked:Fire()
            end)
        end
    end

    _initialized = true
    print("[MatchmakingUI] Initialized")
end

--[[
    Shows the matchmaking UI and starts a search.
]]
function MatchmakingUI:Show()
    if not _screenGui then return end

    _isVisible = true
    _currentOpponent = nil
    _currentSkipCost = 0

    _screenGui.Enabled = true
    showSearching()

    -- Fire initial matchmaking request
    if _requestMatchmaking then
        _requestMatchmaking:FireServer()
    end

    -- Animate in
    if _mainFrame then
        _mainFrame.Position = UDim2.new(0.5, -180, 0.5, -220)
        _mainFrame.BackgroundTransparency = 0.5

        local tween = TweenService:Create(
            _mainFrame,
            TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {
                Position = UDim2.new(0.5, -180, 0.5, -190),
                BackgroundTransparency = 0.02,
            }
        )
        tween:Play()
    end

    print("[MatchmakingUI] Shown - searching for opponent")
end

--[[
    Hides the matchmaking UI and stops searching.
]]
function MatchmakingUI:Hide()
    if not _screenGui then return end

    _isVisible = false
    stopSpinner()
    _currentOpponent = nil
    _currentSkipCost = 0

    -- Animate out
    if _mainFrame then
        local tween = TweenService:Create(
            _mainFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                Position = UDim2.new(0.5, -180, 0.5, -220),
                BackgroundTransparency = 0.5,
            }
        )
        tween:Play()
        tween.Completed:Connect(function()
            if not _isVisible and _screenGui then
                _screenGui.Enabled = false
            end
        end)
    else
        _screenGui.Enabled = false
    end

    print("[MatchmakingUI] Hidden")
end

--[[
    Checks if the UI is currently visible.
]]
function MatchmakingUI:IsVisible(): boolean
    return _isVisible
end

--[[
    Checks if the UI has been initialized.
]]
function MatchmakingUI:IsInitialized(): boolean
    return _initialized
end

return MatchmakingUI
