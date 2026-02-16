--!strict
--[[
    EventBannerUI.lua

    Server event announcement banner.
    Shows active random events (Gold Rush, Bandit Invasion, etc.)
    with a colored banner at the top of the screen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local EventBannerUI = {}
EventBannerUI.__index = EventBannerUI

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _player = Players.LocalPlayer
local _screenGui: ScreenGui? = nil
local _bannerFrame: Frame? = nil
local _bannerLabel: TextLabel? = nil
local _timerLabel: TextLabel? = nil
local _initialized = false
local _activeEventEnd: number = 0

-- ============================================================================
-- UI CONSTRUCTION
-- ============================================================================

local function createUI()
    local playerGui = _player:WaitForChild("PlayerGui")

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EventBannerUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 5
    screenGui.Parent = playerGui
    _screenGui = screenGui

    -- Banner frame (top of screen, hidden by default)
    local banner = Instance.new("Frame")
    banner.Name = "EventBanner"
    banner.Size = UDim2.new(0.5, 0, 0, 40)
    banner.Position = UDim2.new(0.25, 0, 0, -50) -- Hidden above screen
    banner.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
    banner.BackgroundTransparency = 0.15
    banner.BorderSizePixel = 0
    banner.Parent = screenGui
    _bannerFrame = banner

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = banner

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(200, 200, 255)
    stroke.Thickness = 1
    stroke.Parent = banner

    -- Event name label
    local label = Instance.new("TextLabel")
    label.Name = "EventName"
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0.02, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = ""
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.GothamBold
    label.Parent = banner
    _bannerLabel = label

    -- Timer label
    local timer = Instance.new("TextLabel")
    timer.Name = "Timer"
    timer.Size = UDim2.new(0.25, 0, 1, 0)
    timer.Position = UDim2.new(0.73, 0, 0, 0)
    timer.BackgroundTransparency = 1
    timer.Text = ""
    timer.TextColor3 = Color3.fromRGB(200, 200, 200)
    timer.TextScaled = true
    timer.TextXAlignment = Enum.TextXAlignment.Right
    timer.Font = Enum.Font.Gotham
    timer.Parent = banner
    _timerLabel = timer
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function EventBannerUI:Init()
    if _initialized then return end
    _initialized = true
    createUI()

    local Events = ReplicatedStorage:WaitForChild("Events")
    local EventAnnouncement = Events:WaitForChild("EventAnnouncement") :: RemoteEvent

    EventAnnouncement.OnClientEvent:Connect(function(data)
        if data.action == "start" then
            self:ShowEvent(data.data)
        elseif data.action == "end" then
            self:HideEvent()
        end
    end)

    -- Timer update loop
    task.spawn(function()
        while true do
            task.wait(1)
            if _timerLabel and _activeEventEnd > 0 then
                local remaining = math.max(0, _activeEventEnd - os.time())
                if remaining > 0 then
                    local mins = math.floor(remaining / 60)
                    local secs = remaining % 60
                    _timerLabel.Text = string.format("%d:%02d", mins, secs)
                else
                    self:HideEvent()
                end
            end
        end
    end)
end

function EventBannerUI:ShowEvent(eventData: any)
    if not _bannerFrame or not _bannerLabel then return end

    _bannerLabel.Text = eventData.name .. " - " .. eventData.description
    _bannerLabel.TextColor3 = eventData.color or Color3.new(1, 1, 1)
    _activeEventEnd = eventData.endsAt or (os.time() + (eventData.duration or 600))

    -- Update stroke color to match event
    local stroke = _bannerFrame:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Color = eventData.color or Color3.fromRGB(200, 200, 255)
    end

    -- Slide in from top
    local tween = TweenService:Create(_bannerFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.25, 0, 0, 10),
    })
    tween:Play()
end

function EventBannerUI:HideEvent()
    if not _bannerFrame then return end

    _activeEventEnd = 0

    local tween = TweenService:Create(_bannerFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Position = UDim2.new(0.25, 0, 0, -50),
    })
    tween:Play()
end

function EventBannerUI:Destroy()
    if _screenGui then
        _screenGui:Destroy()
        _screenGui = nil
    end
    _initialized = false
end

return EventBannerUI
