--!strict
--[[
    LootCarryUI.lua

    HUD element showing carried loot and "Bank at base!" indicator.
    Appears when player is carrying loot from wilderness encounters.
    Shows gold/wood/food/gems amounts and a pulsing reminder to bank.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local LootCarryUI = {}
LootCarryUI.__index = LootCarryUI

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _player = Players.LocalPlayer
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _goldLabel: TextLabel? = nil
local _woodLabel: TextLabel? = nil
local _foodLabel: TextLabel? = nil
local _gemsLabel: TextLabel? = nil
local _bankReminder: TextLabel? = nil
local _initialized = false

-- ============================================================================
-- UI CONSTRUCTION
-- ============================================================================

local function createUI()
    local playerGui = _player:WaitForChild("PlayerGui")

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "LootCarryUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui
    _screenGui = screenGui

    -- Main container (bottom-center)
    local main = Instance.new("Frame")
    main.Name = "LootCarryFrame"
    main.Size = UDim2.new(0, 300, 0, 100)
    main.Position = UDim2.new(0.5, -150, 1, -130)
    main.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
    main.BackgroundTransparency = 0.2
    main.BorderSizePixel = 0
    main.Visible = false
    main.Parent = screenGui
    _mainFrame = main

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = main

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(200, 170, 50)
    stroke.Thickness = 2
    stroke.Parent = main

    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 20)
    title.BackgroundTransparency = 1
    title.Text = "Carried Loot"
    title.TextColor3 = Color3.fromRGB(255, 215, 0)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = main

    -- Resource labels (horizontal row)
    local function createResourceLabel(name: string, color: Color3, xPos: number): TextLabel
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Size = UDim2.new(0.25, -4, 0, 25)
        label.Position = UDim2.new(xPos, 2, 0, 24)
        label.BackgroundTransparency = 1
        label.Text = "0"
        label.TextColor3 = color
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = main
        return label
    end

    _goldLabel = createResourceLabel("Gold", Color3.fromRGB(255, 215, 0), 0)
    _woodLabel = createResourceLabel("Wood", Color3.fromRGB(139, 90, 43), 0.25)
    _foodLabel = createResourceLabel("Food", Color3.fromRGB(50, 180, 50), 0.5)
    _gemsLabel = createResourceLabel("Gems", Color3.fromRGB(100, 200, 255), 0.75)

    -- Bank reminder (pulsing)
    local reminder = Instance.new("TextLabel")
    reminder.Name = "BankReminder"
    reminder.Size = UDim2.new(1, 0, 0, 30)
    reminder.Position = UDim2.new(0, 0, 0, 55)
    reminder.BackgroundTransparency = 1
    reminder.Text = "Return to your base to bank loot!"
    reminder.TextColor3 = Color3.fromRGB(255, 200, 50)
    reminder.TextScaled = true
    reminder.Font = Enum.Font.GothamBold
    reminder.Parent = main
    _bankReminder = reminder

    -- Pulse animation
    task.spawn(function()
        while true do
            if reminder and reminder.Parent then
                local tween = TweenService:Create(reminder, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    TextTransparency = 0.5,
                })
                tween:Play()
                tween.Completed:Wait()

                local tween2 = TweenService:Create(reminder, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    TextTransparency = 0,
                })
                tween2:Play()
                tween2.Completed:Wait()
            else
                break
            end
        end
    end)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function LootCarryUI:Init()
    if _initialized then return end
    _initialized = true
    createUI()

    -- Listen for loot sync from server
    local Events = ReplicatedStorage:WaitForChild("Events")
    local LootCarrySync = Events:WaitForChild("LootCarrySync") :: RemoteEvent
    local LootBanked = Events:WaitForChild("LootBanked") :: RemoteEvent

    LootCarrySync.OnClientEvent:Connect(function(loot)
        self:UpdateDisplay(loot)
    end)

    LootBanked.OnClientEvent:Connect(function(loot)
        self:ShowBankedNotification(loot)
        self:Hide()
    end)
end

function LootCarryUI:UpdateDisplay(loot: {gold: number, wood: number, food: number, gems: number})
    if not _mainFrame then return end

    local total = loot.gold + loot.wood + loot.food + loot.gems * 100
    if total <= 0 then
        _mainFrame.Visible = false
        return
    end

    _mainFrame.Visible = true
    if _goldLabel then _goldLabel.Text = tostring(loot.gold) .. "g" end
    if _woodLabel then _woodLabel.Text = tostring(loot.wood) .. "w" end
    if _foodLabel then _foodLabel.Text = tostring(loot.food) .. "f" end
    if _gemsLabel then _gemsLabel.Text = tostring(loot.gems) .. " gems" end
end

function LootCarryUI:Hide()
    if _mainFrame then
        _mainFrame.Visible = false
    end
end

function LootCarryUI:ShowBankedNotification(loot: {gold: number, wood: number, food: number, gems: number})
    if not _screenGui then return end

    local notification = Instance.new("TextLabel")
    notification.Size = UDim2.new(0, 300, 0, 40)
    notification.Position = UDim2.new(0.5, -150, 0.4, 0)
    notification.BackgroundColor3 = Color3.fromRGB(30, 80, 30)
    notification.BackgroundTransparency = 0.3
    notification.Text = string.format("Loot Banked! +%dg +%dw +%df +%d gems",
        loot.gold, loot.wood, loot.food, loot.gems)
    notification.TextColor3 = Color3.fromRGB(100, 255, 100)
    notification.TextScaled = true
    notification.Font = Enum.Font.GothamBold
    notification.BorderSizePixel = 0
    notification.Parent = _screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = notification

    -- Fade out after 3 seconds
    task.delay(3, function()
        if notification and notification.Parent then
            local tween = TweenService:Create(notification, TweenInfo.new(1), { BackgroundTransparency = 1, TextTransparency = 1 })
            tween:Play()
            tween.Completed:Wait()
            notification:Destroy()
        end
    end)
end

function LootCarryUI:Destroy()
    if _screenGui then
        _screenGui:Destroy()
        _screenGui = nil
    end
    _initialized = false
end

return LootCarryUI
