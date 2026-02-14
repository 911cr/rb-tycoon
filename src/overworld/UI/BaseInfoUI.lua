--!strict
--[[
    BaseInfoUI.lua

    Displays information about a base when the player approaches it.
    Shows player name, trophies, TH level, and action buttons.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local BaseInfoUI = {}
BaseInfoUI.__index = BaseInfoUI

-- ============================================================================
-- SIGNALS
-- ============================================================================

BaseInfoUI.EnterClicked = Signal.new()
BaseInfoUI.EnterBaseClicked = Signal.new()
BaseInfoUI.AttackClicked = Signal.new()
BaseInfoUI.TradeClicked = Signal.new()

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _initialized = false
local _player = Players.LocalPlayer
local _playerGui: PlayerGui? = nil

local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _currentBaseData: any? = nil
local _isVisible = false

-- Events
local _events: Folder? = nil
local _requestTeleportToVillage: RemoteEvent? = nil
local _requestBattle: RemoteEvent? = nil

-- ============================================================================
-- UI CREATION
-- ============================================================================

--[[
    Creates the base info UI.
]]
local function createUI(): ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BaseInfoUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    -- Main container frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 320, 0, 280)
    mainFrame.Position = UDim2.new(0.5, -160, 0, -300) -- Start off-screen
    mainFrame.AnchorPoint = Vector2.new(0, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 28, 25)
    mainFrame.BackgroundTransparency = 0.05
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(120, 100, 60)
    mainStroke.Thickness = 2
    mainStroke.Parent = mainFrame

    -- Header with player name
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 45)
    header.BackgroundColor3 = Color3.fromRGB(50, 45, 40)
    header.BorderSizePixel = 0
    header.Parent = mainFrame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 12)
    headerCorner.Parent = header

    -- Cover bottom corners of header
    local headerFix = Instance.new("Frame")
    headerFix.Name = "HeaderFix"
    headerFix.Size = UDim2.new(1, 0, 0, 12)
    headerFix.Position = UDim2.new(0, 0, 1, -12)
    headerFix.BackgroundColor3 = Color3.fromRGB(50, 45, 40)
    headerFix.BorderSizePixel = 0
    headerFix.Parent = header

    -- Online indicator
    local onlineIndicator = Instance.new("Frame")
    onlineIndicator.Name = "OnlineIndicator"
    onlineIndicator.Size = UDim2.new(0, 10, 0, 10)
    onlineIndicator.Position = UDim2.new(0, 15, 0.5, -5)
    onlineIndicator.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    onlineIndicator.Parent = header

    local onlineCorner = Instance.new("UICorner")
    onlineCorner.CornerRadius = UDim.new(1, 0)
    onlineCorner.Parent = onlineIndicator

    -- Player name label
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, -40, 1, 0)
    nameLabel.Position = UDim2.new(0, 35, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = "Player Name"
    nameLabel.TextColor3 = Color3.fromRGB(240, 230, 200)
    nameLabel.TextSize = 18
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Parent = header

    -- Stats container
    local statsFrame = Instance.new("Frame")
    statsFrame.Name = "StatsFrame"
    statsFrame.Size = UDim2.new(1, -20, 0, 50)
    statsFrame.Position = UDim2.new(0, 10, 0, 50)
    statsFrame.BackgroundTransparency = 1
    statsFrame.Parent = mainFrame

    local statsLayout = Instance.new("UIListLayout")
    statsLayout.FillDirection = Enum.FillDirection.Horizontal
    statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    statsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    statsLayout.Padding = UDim.new(0, 20)
    statsLayout.Parent = statsFrame

    -- TH Level stat
    local thFrame = Instance.new("Frame")
    thFrame.Name = "THFrame"
    thFrame.Size = UDim2.new(0, 80, 1, 0)
    thFrame.BackgroundTransparency = 1
    thFrame.Parent = statsFrame

    local thLabel = Instance.new("TextLabel")
    thLabel.Name = "Value"
    thLabel.Size = UDim2.new(1, 0, 0.6, 0)
    thLabel.BackgroundTransparency = 1
    thLabel.Text = "1"
    thLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
    thLabel.TextSize = 24
    thLabel.Font = Enum.Font.GothamBold
    thLabel.Parent = thFrame

    local thTitle = Instance.new("TextLabel")
    thTitle.Name = "Title"
    thTitle.Size = UDim2.new(1, 0, 0.4, 0)
    thTitle.Position = UDim2.new(0, 0, 0.6, 0)
    thTitle.BackgroundTransparency = 1
    thTitle.Text = "Town Hall"
    thTitle.TextColor3 = Color3.fromRGB(150, 140, 120)
    thTitle.TextSize = 12
    thTitle.Font = Enum.Font.Gotham
    thTitle.Parent = thFrame

    -- Trophies stat
    local trophyFrame = Instance.new("Frame")
    trophyFrame.Name = "TrophyFrame"
    trophyFrame.Size = UDim2.new(0, 80, 1, 0)
    trophyFrame.BackgroundTransparency = 1
    trophyFrame.Parent = statsFrame

    local trophyLabel = Instance.new("TextLabel")
    trophyLabel.Name = "Value"
    trophyLabel.Size = UDim2.new(1, 0, 0.6, 0)
    trophyLabel.BackgroundTransparency = 1
    trophyLabel.Text = "0"
    trophyLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
    trophyLabel.TextSize = 24
    trophyLabel.Font = Enum.Font.GothamBold
    trophyLabel.Parent = trophyFrame

    local trophyTitle = Instance.new("TextLabel")
    trophyTitle.Name = "Title"
    trophyTitle.Size = UDim2.new(1, 0, 0.4, 0)
    trophyTitle.Position = UDim2.new(0, 0, 0.6, 0)
    trophyTitle.BackgroundTransparency = 1
    trophyTitle.Text = "Trophies"
    trophyTitle.TextColor3 = Color3.fromRGB(150, 140, 120)
    trophyTitle.TextSize = 12
    trophyTitle.Font = Enum.Font.Gotham
    trophyTitle.Parent = trophyFrame

    -- Difficulty indicator
    local difficultyFrame = Instance.new("Frame")
    difficultyFrame.Name = "DifficultyFrame"
    difficultyFrame.Size = UDim2.new(1, -20, 0, 25)
    difficultyFrame.Position = UDim2.new(0, 10, 0, 105)
    difficultyFrame.BackgroundColor3 = Color3.fromRGB(230, 180, 50)
    difficultyFrame.Parent = mainFrame

    local diffCorner = Instance.new("UICorner")
    diffCorner.CornerRadius = UDim.new(0, 4)
    diffCorner.Parent = difficultyFrame

    local diffLabel = Instance.new("TextLabel")
    diffLabel.Name = "DifficultyLabel"
    diffLabel.Size = UDim2.new(1, 0, 1, 0)
    diffLabel.BackgroundTransparency = 1
    diffLabel.Text = "MEDIUM"
    diffLabel.TextColor3 = Color3.fromRGB(40, 35, 30)
    diffLabel.TextSize = 12
    diffLabel.Font = Enum.Font.GothamBold
    diffLabel.Parent = difficultyFrame

    -- Loot preview (for enemy bases only, hidden by default)
    local lootFrame = Instance.new("Frame")
    lootFrame.Name = "LootFrame"
    lootFrame.Size = UDim2.new(1, -20, 0, 65)
    lootFrame.Position = UDim2.new(0, 10, 0, 135)
    lootFrame.BackgroundColor3 = Color3.fromRGB(40, 38, 33)
    lootFrame.BorderSizePixel = 0
    lootFrame.Visible = false
    lootFrame.Parent = mainFrame

    local lootCorner = Instance.new("UICorner")
    lootCorner.CornerRadius = UDim.new(0, 4)
    lootCorner.Parent = lootFrame

    local lootTitle = Instance.new("TextLabel")
    lootTitle.Name = "LootTitle"
    lootTitle.Size = UDim2.new(1, 0, 0, 18)
    lootTitle.Position = UDim2.new(0, 0, 0, 2)
    lootTitle.BackgroundTransparency = 1
    lootTitle.Text = "AVAILABLE LOOT"
    lootTitle.TextColor3 = Color3.fromRGB(150, 140, 120)
    lootTitle.TextSize = 10
    lootTitle.Font = Enum.Font.GothamBold
    lootTitle.Parent = lootFrame

    local lootRow = Instance.new("Frame")
    lootRow.Name = "LootRow"
    lootRow.Size = UDim2.new(1, -10, 0, 40)
    lootRow.Position = UDim2.new(0, 5, 0, 20)
    lootRow.BackgroundTransparency = 1
    lootRow.Parent = lootFrame

    local lootLayout = Instance.new("UIListLayout")
    lootLayout.FillDirection = Enum.FillDirection.Horizontal
    lootLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    lootLayout.Padding = UDim.new(0, 8)
    lootLayout.Parent = lootRow

    local function createLootLabel(name: string, color: Color3): TextLabel
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Size = UDim2.new(0, 85, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = "0"
        label.TextColor3 = color
        label.TextSize = 16
        label.Font = Enum.Font.GothamBold
        label.Parent = lootRow
        return label
    end

    createLootLabel("GoldLoot", Color3.fromRGB(255, 200, 80))
    createLootLabel("WoodLoot", Color3.fromRGB(139, 90, 43))
    createLootLabel("FoodLoot", Color3.fromRGB(120, 190, 80))

    -- Buttons container
    local buttonsFrame = Instance.new("Frame")
    buttonsFrame.Name = "ButtonsFrame"
    buttonsFrame.Size = UDim2.new(1, -20, 0, 45)
    buttonsFrame.Position = UDim2.new(0, 10, 1, -55)
    buttonsFrame.BackgroundTransparency = 1
    buttonsFrame.Parent = mainFrame

    local buttonsLayout = Instance.new("UIListLayout")
    buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
    buttonsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    buttonsLayout.Padding = UDim.new(0, 10)
    buttonsLayout.Parent = buttonsFrame

    -- Enter button (for own base)
    local enterButton = Instance.new("TextButton")
    enterButton.Name = "EnterButton"
    enterButton.Size = UDim2.new(0, 130, 0, 40)
    enterButton.BackgroundColor3 = Color3.fromRGB(80, 150, 80)
    enterButton.Text = "ENTER VILLAGE"
    enterButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    enterButton.TextSize = 14
    enterButton.Font = Enum.Font.GothamBold
    enterButton.Visible = false
    enterButton.Parent = buttonsFrame

    local enterCorner = Instance.new("UICorner")
    enterCorner.CornerRadius = UDim.new(0, 8)
    enterCorner.Parent = enterButton

    -- Attack button (for enemy base)
    local attackButton = Instance.new("TextButton")
    attackButton.Name = "AttackButton"
    attackButton.Size = UDim2.new(0, 100, 0, 40)
    attackButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
    attackButton.Text = "ATTACK"
    attackButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    attackButton.TextSize = 14
    attackButton.Font = Enum.Font.GothamBold
    attackButton.Visible = false
    attackButton.Parent = buttonsFrame

    local attackCorner = Instance.new("UICorner")
    attackCorner.CornerRadius = UDim.new(0, 8)
    attackCorner.Parent = attackButton

    -- Enter Base button (visit another player's base)
    local enterBaseButton = Instance.new("TextButton")
    enterBaseButton.Name = "EnterBaseButton"
    enterBaseButton.Size = UDim2.new(0, 80, 0, 40)
    enterBaseButton.BackgroundColor3 = Color3.fromRGB(80, 120, 180)
    enterBaseButton.Text = "VISIT"
    enterBaseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    enterBaseButton.TextSize = 14
    enterBaseButton.Font = Enum.Font.GothamBold
    enterBaseButton.Visible = false
    enterBaseButton.Parent = buttonsFrame

    local enterBaseCorner = Instance.new("UICorner")
    enterBaseCorner.CornerRadius = UDim.new(0, 8)
    enterBaseCorner.Parent = enterBaseButton

    -- Trade button (for other players' bases)
    local tradeButton = Instance.new("TextButton")
    tradeButton.Name = "TradeButton"
    tradeButton.Size = UDim2.new(0, 80, 0, 40)
    tradeButton.BackgroundColor3 = Color3.fromRGB(40, 140, 120)
    tradeButton.Text = "TRADE"
    tradeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    tradeButton.TextSize = 14
    tradeButton.Font = Enum.Font.GothamBold
    tradeButton.Visible = false
    tradeButton.Parent = buttonsFrame

    local tradeCorner = Instance.new("UICorner")
    tradeCorner.CornerRadius = UDim.new(0, 8)
    tradeCorner.Parent = tradeButton

    -- Hint text
    local hintLabel = Instance.new("TextLabel")
    hintLabel.Name = "HintLabel"
    hintLabel.Size = UDim2.new(1, 0, 0, 20)
    hintLabel.Position = UDim2.new(0, 0, 1, -20)
    hintLabel.BackgroundTransparency = 1
    hintLabel.Text = "Walk closer to interact"
    hintLabel.TextColor3 = Color3.fromRGB(120, 110, 100)
    hintLabel.TextSize = 11
    hintLabel.Font = Enum.Font.Gotham
    hintLabel.Parent = mainFrame

    _mainFrame = mainFrame

    return screenGui
end

--[[
    Updates the UI with base data.
]]
local function updateUI(baseData: any)
    if not _mainFrame then return end

    -- Update name
    local header = _mainFrame:FindFirstChild("Header") :: Frame?
    if header then
        local nameLabel = header:FindFirstChild("NameLabel") :: TextLabel?
        if nameLabel then
            nameLabel.Text = baseData.username or "Unknown"
        end

        local onlineIndicator = header:FindFirstChild("OnlineIndicator") :: Frame?
        if onlineIndicator then
            onlineIndicator.BackgroundColor3 = baseData.isOnline
                and Color3.fromRGB(50, 200, 50)
                or Color3.fromRGB(100, 100, 100)
        end
    end

    -- Update stats
    local statsFrame = _mainFrame:FindFirstChild("StatsFrame") :: Frame?
    if statsFrame then
        local thFrame = statsFrame:FindFirstChild("THFrame") :: Frame?
        if thFrame then
            local value = thFrame:FindFirstChild("Value") :: TextLabel?
            if value then
                value.Text = tostring(baseData.townHallLevel or 1)
            end
        end

        local trophyFrame = statsFrame:FindFirstChild("TrophyFrame") :: Frame?
        if trophyFrame then
            local value = trophyFrame:FindFirstChild("Value") :: TextLabel?
            if value then
                value.Text = tostring(baseData.trophies or 0)
            end
        end
    end

    -- Update difficulty (using real TH comparison)
    local difficultyFrame = _mainFrame:FindFirstChild("DifficultyFrame") :: Frame?
    if difficultyFrame then
        local diffLabel = difficultyFrame:FindFirstChild("DifficultyLabel") :: TextLabel?

        local difficulty = "MEDIUM"
        local diffColor = OverworldConfig.Visuals.DifficultyColors.Medium

        if baseData.isOwnBase then
            difficulty = "YOUR BASE"
            diffColor = OverworldConfig.Visuals.OwnBaseColor
        elseif baseData.isFriend then
            difficulty = "FRIEND"
            diffColor = OverworldConfig.Visuals.FriendColor
        else
            -- Calculate difficulty from TH difference
            local viewerTH = baseData.viewerTownHallLevel or 1
            local defenderTH = baseData.townHallLevel or 1
            local thDiff = defenderTH - viewerTH

            diffColor = OverworldConfig.GetDifficultyColor(thDiff)

            if thDiff <= -2 then
                difficulty = "EASY"
            elseif thDiff <= 0 then
                difficulty = "MEDIUM"
            else
                difficulty = "HARD"
            end
        end

        if diffLabel then
            diffLabel.Text = difficulty
        end
        difficultyFrame.BackgroundColor3 = diffColor
    end

    -- Update loot preview
    local lootFrame = _mainFrame:FindFirstChild("LootFrame") :: Frame?
    if lootFrame then
        local showLoot = not (baseData.isOwnBase or false) and baseData.lootEstimate ~= nil
        lootFrame.Visible = showLoot

        -- Resize panel based on whether loot is shown
        if showLoot then
            _mainFrame.Size = UDim2.new(0, 320, 0, 280)
        else
            _mainFrame.Size = UDim2.new(0, 320, 0, 200)
        end

        if showLoot and baseData.lootEstimate then
            local lootRow = lootFrame:FindFirstChild("LootRow") :: Frame?
            if lootRow then
                local goldLoot = lootRow:FindFirstChild("GoldLoot") :: TextLabel?
                local woodLoot = lootRow:FindFirstChild("WoodLoot") :: TextLabel?
                local foodLoot = lootRow:FindFirstChild("FoodLoot") :: TextLabel?

                local function formatLoot(amount: number): string
                    if amount >= 1000 then
                        return string.format("%.1fK", amount / 1000)
                    end
                    return tostring(amount)
                end

                if goldLoot then goldLoot.Text = formatLoot(baseData.lootEstimate.gold or 0) .. " g" end
                if woodLoot then woodLoot.Text = formatLoot(baseData.lootEstimate.wood or 0) .. " w" end
                if foodLoot then foodLoot.Text = formatLoot(baseData.lootEstimate.food or 0) .. " f" end
            end
        end
    end

    -- Update buttons visibility
    local buttonsFrame = _mainFrame:FindFirstChild("ButtonsFrame") :: Frame?
    if buttonsFrame then
        local enterButton = buttonsFrame:FindFirstChild("EnterButton") :: TextButton?
        local attackButton = buttonsFrame:FindFirstChild("AttackButton") :: TextButton?
        local enterBaseButton = buttonsFrame:FindFirstChild("EnterBaseButton") :: TextButton?
        local tradeButton = buttonsFrame:FindFirstChild("TradeButton") :: TextButton?

        local isOwnBase = baseData.isOwnBase or false
        local hasShield = baseData.hasShield or false

        if enterButton then
            enterButton.Visible = isOwnBase
        end

        if attackButton then
            attackButton.Visible = not isOwnBase and not hasShield
        end

        if enterBaseButton then
            enterBaseButton.Visible = not isOwnBase
        end

        if tradeButton then
            tradeButton.Visible = not isOwnBase
        end
    end

    -- Update hint
    local hintLabel = _mainFrame:FindFirstChild("HintLabel") :: TextLabel?
    if hintLabel then
        if baseData.isOwnBase then
            hintLabel.Text = "Press E to enter your village"
        elseif baseData.hasShield then
            hintLabel.Text = "This base is shielded"
        else
            hintLabel.Text = "Press E to attack, or Visit first"
        end
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Initializes the BaseInfoUI.
]]
function BaseInfoUI:Init()
    if _initialized then
        warn("[BaseInfoUI] Already initialized")
        return
    end

    _playerGui = _player:WaitForChild("PlayerGui") :: PlayerGui

    -- Create UI
    _screenGui = createUI()
    _screenGui.Parent = _playerGui

    -- Get events
    _events = ReplicatedStorage:WaitForChild("Events", 5) :: Folder?
    if _events then
        _requestTeleportToVillage = _events:FindFirstChild("RequestTeleportToVillage") :: RemoteEvent?
        _requestBattle = _events:FindFirstChild("RequestBattle") :: RemoteEvent?
    end

    -- Connect button clicks
    if _mainFrame then
        local buttonsFrame = _mainFrame:FindFirstChild("ButtonsFrame") :: Frame?
        if buttonsFrame then
            local enterButton = buttonsFrame:FindFirstChild("EnterButton") :: TextButton?
            if enterButton then
                enterButton.MouseButton1Click:Connect(function()
                    if _requestTeleportToVillage then
                        _requestTeleportToVillage:FireServer()
                    end
                    self.EnterClicked:Fire()
                end)
            end

            local attackButton = buttonsFrame:FindFirstChild("AttackButton") :: TextButton?
            if attackButton then
                attackButton.MouseButton1Click:Connect(function()
                    if _currentBaseData and _requestBattle then
                        _requestBattle:FireServer(_currentBaseData.userId)
                    end
                    self.AttackClicked:Fire(_currentBaseData)
                end)
            end

            local enterBaseButton = buttonsFrame:FindFirstChild("EnterBaseButton") :: TextButton?
            if enterBaseButton then
                enterBaseButton.MouseButton1Click:Connect(function()
                    self.EnterBaseClicked:Fire(_currentBaseData)
                end)
            end

            local tradeButton = buttonsFrame:FindFirstChild("TradeButton") :: TextButton?
            if tradeButton then
                tradeButton.MouseButton1Click:Connect(function()
                    self.TradeClicked:Fire(_currentBaseData)
                end)
            end
        end
    end

    _initialized = true
    print("[BaseInfoUI] Initialized")
end

--[[
    Shows the base info UI with data.

    @param baseData table - The base data to display
]]
function BaseInfoUI:Show(baseData: any)
    if not _mainFrame or not _screenGui then return end

    _currentBaseData = baseData
    updateUI(baseData)

    -- Animate in
    _mainFrame.Position = UDim2.new(0.5, -160, 0, -220)
    _screenGui.Enabled = true
    _isVisible = true

    local tween = TweenService:Create(
        _mainFrame,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, -160, 0, 20)}
    )
    tween:Play()
end

--[[
    Hides the base info UI.
]]
function BaseInfoUI:Hide()
    if not _mainFrame or not _screenGui then return end

    _isVisible = false

    local tween = TweenService:Create(
        _mainFrame,
        TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {Position = UDim2.new(0.5, -160, 0, -220)}
    )
    tween:Play()
    tween.Completed:Connect(function()
        if not _isVisible then
            _currentBaseData = nil
        end
    end)
end

--[[
    Checks if UI is visible.

    @return boolean - True if visible
]]
function BaseInfoUI:IsVisible(): boolean
    return _isVisible
end

--[[
    Gets current base data being displayed.

    @return table? - Base data or nil
]]
function BaseInfoUI:GetCurrentBaseData(): any?
    return _currentBaseData
end

return BaseInfoUI
