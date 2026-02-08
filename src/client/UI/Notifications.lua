--!strict
--[[
    Notifications.lua

    Toast notification system for player feedback.
    Shows success, error, and info messages.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Components)

local Notifications = {}
Notifications.__index = Notifications

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _container: Frame
local _notifications: {Frame} = {}
local _initialized = false

-- Constants
local MAX_NOTIFICATIONS = 5
local NOTIFICATION_DURATION = 3
local SLIDE_DURATION = 0.3

-- Notification types
export type NotificationType = "success" | "error" | "warning" | "info"

--[[
    Gets the color for a notification type.
]]
local function getTypeColor(notifType: NotificationType): Color3
    if notifType == "success" then
        return Components.Colors.Success
    elseif notifType == "error" then
        return Components.Colors.Danger
    elseif notifType == "warning" then
        return Components.Colors.Warning
    else
        return Components.Colors.Primary
    end
end

--[[
    Gets the icon for a notification type.
]]
local function getTypeIcon(notifType: NotificationType): string
    if notifType == "success" then
        return "✓"
    elseif notifType == "error" then
        return "✗"
    elseif notifType == "warning" then
        return "!"
    else
        return "i"
    end
end

--[[
    Repositions all notifications after one is removed.
]]
local function repositionNotifications()
    for i, notif in _notifications do
        local targetY = (i - 1) * 60
        TweenService:Create(notif, TweenInfo.new(SLIDE_DURATION, Enum.EasingStyle.Quad), {
            Position = UDim2.new(1, -16, 0, 60 + targetY)
        }):Play()
    end
end

--[[
    Removes a notification.
]]
local function removeNotification(notif: Frame)
    local index = table.find(_notifications, notif)
    if index then
        table.remove(_notifications, index)
    end

    -- Slide out
    local tween = TweenService:Create(notif, TweenInfo.new(SLIDE_DURATION, Enum.EasingStyle.Quad), {
        Position = UDim2.new(1, 20, notif.Position.Y.Scale, notif.Position.Y.Offset)
    })
    tween:Play()
    tween.Completed:Connect(function()
        notif:Destroy()
        repositionNotifications()
    end)
end

--[[
    Shows a notification.
]]
function Notifications:Show(message: string, notifType: NotificationType?, duration: number?)
    if not _initialized then
        warn("Notifications not initialized")
        return
    end

    notifType = notifType or "info"
    duration = duration or NOTIFICATION_DURATION

    -- Limit notifications
    while #_notifications >= MAX_NOTIFICATIONS do
        local oldest = _notifications[1]
        if oldest then
            removeNotification(oldest)
        end
    end

    -- Calculate position
    local yOffset = #_notifications * 60

    -- Create notification
    local notif = Components.CreateFrame({
        Name = "Notification",
        Size = UDim2.new(0, 280, 0, 52),
        Position = UDim2.new(1, 20, 0, 60 + yOffset), -- Start off-screen
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor = Components.Colors.Panel,
        CornerRadius = Components.Sizes.CornerRadius,
        BorderColor = getTypeColor(notifType),
        Parent = _container,
    })

    -- Add shadow effect
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 16, 1, 16)
    shadow.Position = UDim2.new(0.5, 0, 0.5, 4)
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.BackgroundTransparency = 1
    shadow.ImageColor3 = Color3.new(0, 0, 0)
    shadow.ImageTransparency = 0.7
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(16, 16, 16, 16)
    shadow.ZIndex = -1
    shadow.Parent = notif

    -- Type indicator
    local indicator = Components.CreateFrame({
        Name = "Indicator",
        Size = UDim2.new(0, 4, 1, -8),
        Position = UDim2.new(0, 4, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = getTypeColor(notifType),
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = notif,
    })

    -- Icon
    local iconBg = Components.CreateFrame({
        Name = "IconBg",
        Size = UDim2.new(0, 32, 0, 32),
        Position = UDim2.new(0, 16, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = getTypeColor(notifType),
        CornerRadius = UDim.new(0.5, 0),
        Parent = notif,
    })

    local iconLabel = Components.CreateLabel({
        Name = "Icon",
        Text = getTypeIcon(notifType),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = iconBg,
    })

    -- Message
    local messageLabel = Components.CreateLabel({
        Name = "Message",
        Text = message,
        Size = UDim2.new(1, -64, 1, -8),
        Position = UDim2.new(0, 56, 0, 4),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Parent = notif,
    })
    messageLabel.TextWrapped = true

    -- Add to list
    table.insert(_notifications, notif)

    -- Slide in
    TweenService:Create(notif, TweenInfo.new(SLIDE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(1, -16, 0, 60 + yOffset)
    }):Play()

    -- Auto-remove after duration
    task.delay(duration, function()
        if notif and notif.Parent then
            removeNotification(notif)
        end
    end)
end

--[[
    Shows a success notification.
]]
function Notifications:Success(message: string)
    self:Show(message, "success")
end

--[[
    Shows an error notification.
]]
function Notifications:Error(message: string)
    self:Show(message, "error")
end

--[[
    Shows a warning notification.
]]
function Notifications:Warning(message: string)
    self:Show(message, "warning")
end

--[[
    Shows an info notification.
]]
function Notifications:Info(message: string)
    self:Show(message, "info")
end

--[[
    Initializes the notification system.
]]
function Notifications:Init()
    if _initialized then
        warn("Notifications already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "Notifications"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.IgnoreGuiInset = true
    _screenGui.DisplayOrder = 100 -- Above other UIs
    _screenGui.Parent = playerGui

    -- Container for notifications
    _container = Components.CreateFrame({
        Name = "Container",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Parent = _screenGui,
    })

    _initialized = true
    print("Notifications initialized")
end

return Notifications
