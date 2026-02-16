--!strict
--[[
    AutoClashUI.lua

    Combat results screen for overworld auto-clash battles.
    Shows troops lost, HP percentages, winner, and loot gained.
    Triggered by AutoClashResult RemoteEvent from server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local AutoClashUI = {}
AutoClashUI.__index = AutoClashUI

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _player = Players.LocalPlayer
local _screenGui: ScreenGui? = nil
local _resultFrame: Frame? = nil
local _initialized = false

-- ============================================================================
-- UI CONSTRUCTION
-- ============================================================================

local function createUI()
    local playerGui = _player:WaitForChild("PlayerGui")

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoClashUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 10
    screenGui.Parent = playerGui
    _screenGui = screenGui
end

local function showResult(result: any)
    if not _screenGui then return end

    -- Remove previous result
    if _resultFrame then
        _resultFrame:Destroy()
        _resultFrame = nil
    end

    -- Overlay background
    local overlay = Instance.new("Frame")
    overlay.Name = "ClashOverlay"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.5
    overlay.BorderSizePixel = 0
    overlay.Parent = _screenGui
    _resultFrame = overlay

    -- Result panel
    local panel = Instance.new("Frame")
    panel.Name = "ResultPanel"
    panel.Size = UDim2.new(0, 400, 0, 350)
    panel.Position = UDim2.new(0.5, -200, 0.5, -175)
    panel.BackgroundColor3 = Color3.fromRGB(25, 20, 30)
    panel.BackgroundTransparency = 0.1
    panel.BorderSizePixel = 0
    panel.Parent = overlay

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = panel

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Parent = panel

    -- Winner text
    local winnerColor
    local winnerText
    if result.winner == "attacker" then
        winnerText = "VICTORY!"
        winnerColor = Color3.fromRGB(100, 255, 100)
        stroke.Color = Color3.fromRGB(100, 255, 100)
    elseif result.winner == "defender" then
        winnerText = "DEFEAT"
        winnerColor = Color3.fromRGB(255, 80, 80)
        stroke.Color = Color3.fromRGB(255, 80, 80)
    else
        winnerText = "DRAW"
        winnerColor = Color3.fromRGB(200, 200, 100)
        stroke.Color = Color3.fromRGB(200, 200, 100)
    end

    local winLabel = Instance.new("TextLabel")
    winLabel.Size = UDim2.new(1, 0, 0, 50)
    winLabel.Position = UDim2.new(0, 0, 0, 10)
    winLabel.BackgroundTransparency = 1
    winLabel.Text = winnerText
    winLabel.TextColor3 = winnerColor
    winLabel.TextScaled = true
    winLabel.Font = Enum.Font.GothamBold
    winLabel.Parent = panel

    -- Duration
    local durLabel = Instance.new("TextLabel")
    durLabel.Size = UDim2.new(1, 0, 0, 20)
    durLabel.Position = UDim2.new(0, 0, 0, 60)
    durLabel.BackgroundTransparency = 1
    durLabel.Text = string.format("Battle Duration: %.1fs", result.duration or 0)
    durLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    durLabel.TextScaled = true
    durLabel.Font = Enum.Font.Gotham
    durLabel.Parent = panel

    -- HP bars
    local function createHPBar(label: string, percent: number, yPos: number, color: Color3)
        local barLabel = Instance.new("TextLabel")
        barLabel.Size = UDim2.new(0.3, 0, 0, 20)
        barLabel.Position = UDim2.new(0.05, 0, 0, yPos)
        barLabel.BackgroundTransparency = 1
        barLabel.Text = label
        barLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        barLabel.TextScaled = true
        barLabel.TextXAlignment = Enum.TextXAlignment.Left
        barLabel.Font = Enum.Font.Gotham
        barLabel.Parent = panel

        local barBg = Instance.new("Frame")
        barBg.Size = UDim2.new(0.55, 0, 0, 16)
        barBg.Position = UDim2.new(0.35, 0, 0, yPos + 2)
        barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        barBg.BorderSizePixel = 0
        barBg.Parent = panel

        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0.3, 0)
        barCorner.Parent = barBg

        local barFill = Instance.new("Frame")
        barFill.Size = UDim2.new(math.clamp(percent / 100, 0, 1), 0, 1, 0)
        barFill.BackgroundColor3 = color
        barFill.BorderSizePixel = 0
        barFill.Parent = barBg

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0.3, 0)
        fillCorner.Parent = barFill

        local pctLabel = Instance.new("TextLabel")
        pctLabel.Size = UDim2.new(1, 0, 1, 0)
        pctLabel.BackgroundTransparency = 1
        pctLabel.Text = tostring(math.floor(percent)) .. "%"
        pctLabel.TextColor3 = Color3.new(1, 1, 1)
        pctLabel.TextScaled = true
        pctLabel.Font = Enum.Font.GothamBold
        pctLabel.Parent = barBg
    end

    createHPBar("Your HP:", result.attackerHpPercent or 0, 90, Color3.fromRGB(80, 180, 80))
    createHPBar("Enemy HP:", result.defenderHpPercent or 0, 115, Color3.fromRGB(180, 80, 80))

    -- Troop losses
    local lossesTitle = Instance.new("TextLabel")
    lossesTitle.Size = UDim2.new(1, 0, 0, 20)
    lossesTitle.Position = UDim2.new(0, 0, 0, 145)
    lossesTitle.BackgroundTransparency = 1
    lossesTitle.Text = "Your Troop Losses:"
    lossesTitle.TextColor3 = Color3.fromRGB(255, 150, 100)
    lossesTitle.TextScaled = true
    lossesTitle.Font = Enum.Font.GothamBold
    lossesTitle.Parent = panel

    local yOffset = 170
    if result.attackerLosses then
        for _, loss in result.attackerLosses do
            if loss.lost > 0 then
                local lossLabel = Instance.new("TextLabel")
                lossLabel.Size = UDim2.new(0.9, 0, 0, 16)
                lossLabel.Position = UDim2.new(0.05, 0, 0, yOffset)
                lossLabel.BackgroundTransparency = 1
                lossLabel.Text = string.format("%s: -%d (remaining: %d)", loss.troopType, loss.lost, loss.remaining)
                lossLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
                lossLabel.TextScaled = true
                lossLabel.TextXAlignment = Enum.TextXAlignment.Left
                lossLabel.Font = Enum.Font.Gotham
                lossLabel.Parent = panel
                yOffset += 18
            end
        end
    end

    -- Loot gained
    if result.loot and result.winner == "attacker" then
        local lootTitle = Instance.new("TextLabel")
        lootTitle.Size = UDim2.new(1, 0, 0, 20)
        lootTitle.Position = UDim2.new(0, 0, 0, yOffset + 5)
        lootTitle.BackgroundTransparency = 1
        lootTitle.Text = "Loot Gained (Carried):"
        lootTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
        lootTitle.TextScaled = true
        lootTitle.Font = Enum.Font.GothamBold
        lootTitle.Parent = panel

        local lootText = string.format("%dg  %dw  %df  %d gems",
            result.loot.gold or 0, result.loot.wood or 0,
            result.loot.food or 0, result.loot.gems or 0)
        local lootLabel = Instance.new("TextLabel")
        lootLabel.Size = UDim2.new(0.9, 0, 0, 18)
        lootLabel.Position = UDim2.new(0.05, 0, 0, yOffset + 28)
        lootLabel.BackgroundTransparency = 1
        lootLabel.Text = lootText
        lootLabel.TextColor3 = Color3.fromRGB(255, 230, 100)
        lootLabel.TextScaled = true
        lootLabel.Font = Enum.Font.Gotham
        lootLabel.Parent = panel
    end

    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseBtn"
    closeBtn.Size = UDim2.new(0.4, 0, 0, 35)
    closeBtn.Position = UDim2.new(0.3, 0, 1, -45)
    closeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    closeBtn.Text = "Continue"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.TextScaled = true
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = panel

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = closeBtn

    closeBtn.MouseButton1Click:Connect(function()
        if _resultFrame then
            _resultFrame:Destroy()
            _resultFrame = nil
        end
    end)

    -- Scale-in animation
    panel.Size = UDim2.new(0, 0, 0, 0)
    panel.Position = UDim2.new(0.5, 0, 0.5, 0)
    local tween = TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 400, 0, 350),
        Position = UDim2.new(0.5, -200, 0.5, -175),
    })
    tween:Play()
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function AutoClashUI:Init()
    if _initialized then return end
    _initialized = true
    createUI()

    local Events = ReplicatedStorage:WaitForChild("Events")
    local AutoClashResultEvent = Events:WaitForChild("AutoClashResult") :: RemoteEvent

    AutoClashResultEvent.OnClientEvent:Connect(function(result)
        showResult(result)
    end)
end

function AutoClashUI:Destroy()
    if _screenGui then
        _screenGui:Destroy()
        _screenGui = nil
    end
    _initialized = false
end

return AutoClashUI
