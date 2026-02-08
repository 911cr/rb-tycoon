--!strict
--[[
    TutorialController.lua

    Manages the new player tutorial and onboarding experience.
    Guides players through building, upgrading, and combat.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)

local TutorialController = {}
TutorialController.__index = TutorialController

-- Events
TutorialController.StepCompleted = Signal.new()
TutorialController.TutorialCompleted = Signal.new()
TutorialController.TutorialSkipped = Signal.new()

-- Private state
local _initialized = false
local _player = Players.LocalPlayer
local _isActive = false
local _currentStep = 0
local _tutorialUI: ScreenGui? = nil
local _highlightFrame: Frame? = nil
local _dialogFrame: Frame? = nil
local _arrowFrame: ImageLabel? = nil

-- Tutorial steps
local TutorialSteps = {
    {
        id = "welcome",
        title = "Welcome, Chief!",
        message = "Welcome to Battle Tycoon: Conquest! Let's build your empire together.",
        action = "continue",
        highlight = nil,
    },
    {
        id = "build_goldmine",
        title = "Build Resources",
        message = "Tap the BUILD button to open the building menu. Then select a Gold Mine to start earning gold!",
        action = "build",
        highlight = "BuildButton",
        requiredBuilding = "GoldMine",
    },
    {
        id = "place_building",
        title = "Place Your Building",
        message = "Tap on the grid to place your Gold Mine. Choose a good spot!",
        action = "place",
        highlight = "grid",
    },
    {
        id = "collect_resources",
        title = "Collect Resources",
        message = "Great! Your Gold Mine is producing gold. Tap on it to collect resources when ready.",
        action = "collect",
        highlight = "building",
    },
    {
        id = "upgrade_building",
        title = "Upgrade Buildings",
        message = "Select a building and tap UPGRADE to make it more powerful!",
        action = "upgrade",
        highlight = "UpgradeButton",
    },
    {
        id = "train_troops",
        title = "Train Your Army",
        message = "Build a Barracks to train troops. Troops are used to attack other players!",
        action = "build",
        requiredBuilding = "Barracks",
    },
    {
        id = "attack_intro",
        title = "Attack Enemies",
        message = "Tap the ATTACK button to find an opponent and raid their resources!",
        action = "continue",
        highlight = "AttackButton",
    },
    {
        id = "tutorial_complete",
        title = "You're Ready!",
        message = "Congratulations! You've learned the basics. Now go conquer the world!",
        action = "complete",
        reward = { gems = 50 },
    },
}

--[[
    Creates the tutorial UI.
]]
local function createTutorialUI()
    local playerGui = _player:WaitForChild("PlayerGui")

    -- Main ScreenGui
    _tutorialUI = Instance.new("ScreenGui")
    _tutorialUI.Name = "TutorialUI"
    _tutorialUI.ResetOnSpawn = false
    _tutorialUI.DisplayOrder = 200 -- Above everything
    _tutorialUI.IgnoreGuiInset = true
    _tutorialUI.Enabled = false
    _tutorialUI.Parent = playerGui

    -- Dim overlay (with hole for highlight)
    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 0.7
    overlay.BorderSizePixel = 0
    overlay.Parent = _tutorialUI

    -- Highlight frame (transparent hole)
    _highlightFrame = Instance.new("Frame")
    _highlightFrame.Name = "Highlight"
    _highlightFrame.Size = UDim2.new(0, 100, 0, 50)
    _highlightFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    _highlightFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    _highlightFrame.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
    _highlightFrame.BackgroundTransparency = 0.5
    _highlightFrame.BorderSizePixel = 0
    _highlightFrame.Visible = false
    _highlightFrame.Parent = _tutorialUI

    local highlightCorner = Instance.new("UICorner")
    highlightCorner.CornerRadius = UDim.new(0, 8)
    highlightCorner.Parent = _highlightFrame

    local highlightStroke = Instance.new("UIStroke")
    highlightStroke.Color = Color3.fromRGB(255, 220, 0)
    highlightStroke.Thickness = 3
    highlightStroke.Parent = _highlightFrame

    -- Arrow indicator
    _arrowFrame = Instance.new("ImageLabel")
    _arrowFrame.Name = "Arrow"
    _arrowFrame.Size = UDim2.new(0, 40, 0, 40)
    _arrowFrame.Position = UDim2.new(0.5, 0, 0, -50)
    _arrowFrame.AnchorPoint = Vector2.new(0.5, 1)
    _arrowFrame.BackgroundTransparency = 1
    _arrowFrame.Image = "rbxassetid://0" -- Would be arrow asset
    _arrowFrame.ImageColor3 = Color3.fromRGB(255, 220, 0)
    _arrowFrame.Visible = false
    _arrowFrame.Parent = _highlightFrame

    -- Dialog box
    _dialogFrame = Instance.new("Frame")
    _dialogFrame.Name = "Dialog"
    _dialogFrame.Size = UDim2.new(0.8, 0, 0, 140)
    _dialogFrame.Position = UDim2.new(0.5, 0, 0.75, 0)
    _dialogFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    _dialogFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    _dialogFrame.BorderSizePixel = 0
    _dialogFrame.Parent = _tutorialUI

    local dialogCorner = Instance.new("UICorner")
    dialogCorner.CornerRadius = UDim.new(0, 12)
    dialogCorner.Parent = _dialogFrame

    local dialogStroke = Instance.new("UIStroke")
    dialogStroke.Color = Color3.fromRGB(255, 200, 0)
    dialogStroke.Thickness = 2
    dialogStroke.Parent = _dialogFrame

    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -32, 0, 30)
    titleLabel.Position = UDim2.new(0, 16, 0, 12)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
    titleLabel.TextSize = 22
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Text = "Tutorial"
    titleLabel.Parent = _dialogFrame

    -- Message
    local messageLabel = Instance.new("TextLabel")
    messageLabel.Name = "Message"
    messageLabel.Size = UDim2.new(1, -32, 0, 50)
    messageLabel.Position = UDim2.new(0, 16, 0, 44)
    messageLabel.BackgroundTransparency = 1
    messageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    messageLabel.TextSize = 16
    messageLabel.Font = Enum.Font.Gotham
    messageLabel.TextXAlignment = Enum.TextXAlignment.Left
    messageLabel.TextYAlignment = Enum.TextYAlignment.Top
    messageLabel.TextWrapped = true
    messageLabel.Text = ""
    messageLabel.Parent = _dialogFrame

    -- Continue button
    local continueButton = Instance.new("TextButton")
    continueButton.Name = "ContinueButton"
    continueButton.Size = UDim2.new(0, 100, 0, 36)
    continueButton.Position = UDim2.new(1, -16, 1, -12)
    continueButton.AnchorPoint = Vector2.new(1, 1)
    continueButton.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
    continueButton.TextColor3 = Color3.new(1, 1, 1)
    continueButton.TextSize = 16
    continueButton.Font = Enum.Font.GothamBold
    continueButton.Text = "Continue"
    continueButton.Parent = _dialogFrame

    local continueCorner = Instance.new("UICorner")
    continueCorner.CornerRadius = UDim.new(0, 8)
    continueCorner.Parent = continueButton

    continueButton.MouseButton1Click:Connect(function()
        TutorialController:NextStep()
    end)

    -- Skip button
    local skipButton = Instance.new("TextButton")
    skipButton.Name = "SkipButton"
    skipButton.Size = UDim2.new(0, 80, 0, 36)
    skipButton.Position = UDim2.new(0, 16, 1, -12)
    skipButton.AnchorPoint = Vector2.new(0, 1)
    skipButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    skipButton.TextColor3 = Color3.new(1, 1, 1)
    skipButton.TextSize = 14
    skipButton.Font = Enum.Font.Gotham
    skipButton.Text = "Skip"
    skipButton.Parent = _dialogFrame

    local skipCorner = Instance.new("UICorner")
    skipCorner.CornerRadius = UDim.new(0, 8)
    skipCorner.Parent = skipButton

    skipButton.MouseButton1Click:Connect(function()
        TutorialController:Skip()
    end)
end

--[[
    Shows a tutorial step.
]]
local function showStep(step: any)
    if not _tutorialUI or not _dialogFrame then return end

    local titleLabel = _dialogFrame:FindFirstChild("Title") :: TextLabel
    local messageLabel = _dialogFrame:FindFirstChild("Message") :: TextLabel
    local continueButton = _dialogFrame:FindFirstChild("ContinueButton") :: TextButton

    if titleLabel then titleLabel.Text = step.title end
    if messageLabel then messageLabel.Text = step.message end

    -- Update continue button text based on action
    if continueButton then
        if step.action == "complete" then
            continueButton.Text = "Finish!"
            continueButton.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
        elseif step.action == "continue" then
            continueButton.Text = "Continue"
            continueButton.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
        else
            continueButton.Text = "Got it!"
            continueButton.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
        end
    end

    -- Handle highlight
    if _highlightFrame then
        if step.highlight then
            _highlightFrame.Visible = true
            -- TODO: Position highlight over the target element
        else
            _highlightFrame.Visible = false
        end
    end

    -- Animate dialog in
    _dialogFrame.Position = UDim2.new(0.5, 0, 1.2, 0)
    TweenService:Create(_dialogFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0.75, 0)
    }):Play()
end

--[[
    Starts the tutorial.
]]
function TutorialController:Start()
    if _isActive then return end

    _isActive = true
    _currentStep = 1

    if _tutorialUI then
        _tutorialUI.Enabled = true
    end

    local step = TutorialSteps[_currentStep]
    if step then
        showStep(step)
    end

    print("[Tutorial] Started")
end

--[[
    Advances to the next step.
]]
function TutorialController:NextStep()
    if not _isActive then return end

    local previousStep = TutorialSteps[_currentStep]
    if previousStep then
        TutorialController.StepCompleted:Fire(previousStep.id)
    end

    _currentStep += 1

    if _currentStep > #TutorialSteps then
        self:Complete()
        return
    end

    local step = TutorialSteps[_currentStep]
    if step then
        showStep(step)
    end
end

--[[
    Completes the tutorial.
]]
function TutorialController:Complete()
    _isActive = false

    if _tutorialUI then
        -- Fade out
        TweenService:Create(_tutorialUI:FindFirstChild("Overlay") :: Frame, TweenInfo.new(0.3), {
            BackgroundTransparency = 1
        }):Play()

        if _dialogFrame then
            TweenService:Create(_dialogFrame, TweenInfo.new(0.3), {
                Position = UDim2.new(0.5, 0, 1.2, 0)
            }):Play()
        end

        task.delay(0.3, function()
            if _tutorialUI then
                _tutorialUI.Enabled = false
            end
        end)
    end

    -- Grant reward
    local lastStep = TutorialSteps[#TutorialSteps]
    if lastStep and lastStep.reward then
        -- Would trigger server reward
        print("[Tutorial] Completed - Reward:", lastStep.reward)
    end

    TutorialController.TutorialCompleted:Fire()
    print("[Tutorial] Completed")
end

--[[
    Skips the tutorial.
]]
function TutorialController:Skip()
    _isActive = false

    if _tutorialUI then
        _tutorialUI.Enabled = false
    end

    TutorialController.TutorialSkipped:Fire()
    print("[Tutorial] Skipped")
end

--[[
    Checks if tutorial is active.
]]
function TutorialController:IsActive(): boolean
    return _isActive
end

--[[
    Gets the current step.
]]
function TutorialController:GetCurrentStep(): number
    return _currentStep
end

--[[
    Notifies the tutorial that an action was performed.
]]
function TutorialController:OnAction(actionType: string, data: any?)
    if not _isActive then return end

    local step = TutorialSteps[_currentStep]
    if not step then return end

    -- Check if action matches step requirement
    if step.action == "build" and actionType == "building_placed" then
        if step.requiredBuilding then
            if data and data.buildingType == step.requiredBuilding then
                self:NextStep()
            end
        else
            self:NextStep()
        end
    elseif step.action == "collect" and actionType == "resources_collected" then
        self:NextStep()
    elseif step.action == "upgrade" and actionType == "upgrade_started" then
        self:NextStep()
    elseif step.action == "place" and actionType == "building_placed" then
        self:NextStep()
    end
end

--[[
    Initializes the TutorialController.
]]
function TutorialController:Init()
    if _initialized then
        warn("TutorialController already initialized")
        return
    end

    createTutorialUI()

    -- Check if player needs tutorial
    task.defer(function()
        local playerData = ClientAPI.GetPlayerData()
        if playerData then
            local completedTutorial = playerData.tutorialCompleted or false
            if not completedTutorial then
                -- Start tutorial after a short delay
                task.delay(2, function()
                    self:Start()
                end)
            end
        end
    end)

    _initialized = true
    print("TutorialController initialized")
end

return TutorialController
