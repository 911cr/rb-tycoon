--!strict
--[[
    SettingsUI.lua

    Game settings interface.
    Allows players to adjust music, SFX, and notifications.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local SettingsUI = {}
SettingsUI.__index = SettingsUI

-- Events
SettingsUI.Closed = Signal.new()
SettingsUI.SettingChanged = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _panel: Frame
local _isVisible = false
local _initialized = false

-- Local settings cache
local _settings = {
    musicEnabled = true,
    sfxEnabled = true,
    notificationsEnabled = true,
    musicVolume = 0.5,
    sfxVolume = 0.7,
}

--[[
    Creates a toggle setting row.
]]
local function createToggle(name: string, label: string, defaultValue: boolean, parent: GuiObject, onChange: (boolean) -> ()): Frame
    local row = Components.CreateFrame({
        Name = name .. "Row",
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local labelText = Components.CreateLabel({
        Name = "Label",
        Text = label,
        Size = UDim2.new(0.6, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Parent = row,
    })

    -- Toggle button
    local toggleBg = Components.CreateFrame({
        Name = "ToggleBg",
        Size = UDim2.new(0, 50, 0, 28),
        Position = UDim2.new(1, 0, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor = defaultValue and Components.Colors.Secondary or Components.Colors.BackgroundLight,
        CornerRadius = UDim.new(0.5, 0),
        Parent = row,
    })

    local toggleKnob = Components.CreateFrame({
        Name = "Knob",
        Size = UDim2.new(0, 22, 0, 22),
        Position = defaultValue and UDim2.new(1, -3, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        AnchorPoint = Vector2.new(defaultValue and 1 or 0, 0.5),
        BackgroundColor = Components.Colors.TextPrimary,
        CornerRadius = UDim.new(0.5, 0),
        Parent = toggleBg,
    })

    local isOn = defaultValue

    local toggleButton = Instance.new("TextButton")
    toggleButton.Name = "ToggleBtn"
    toggleButton.Size = UDim2.new(1, 0, 1, 0)
    toggleButton.BackgroundTransparency = 1
    toggleButton.Text = ""
    toggleButton.Parent = toggleBg

    toggleButton.MouseButton1Click:Connect(function()
        isOn = not isOn

        -- Animate toggle
        local TweenService = game:GetService("TweenService")
        TweenService:Create(toggleBg, TweenInfo.new(0.2), {
            BackgroundColor3 = isOn and Components.Colors.Secondary or Components.Colors.BackgroundLight
        }):Play()

        TweenService:Create(toggleKnob, TweenInfo.new(0.2), {
            Position = isOn and UDim2.new(1, -3, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            AnchorPoint = Vector2.new(isOn and 1 or 0, 0.5)
        }):Play()

        onChange(isOn)
    end)

    return row
end

--[[
    Creates a slider setting row.
]]
local function createSlider(name: string, label: string, defaultValue: number, parent: GuiObject, onChange: (number) -> ()): Frame
    local row = Components.CreateFrame({
        Name = name .. "Row",
        Size = UDim2.new(1, 0, 0, 60),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local labelText = Components.CreateLabel({
        Name = "Label",
        Text = label,
        Size = UDim2.new(1, 0, 0, 20),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Parent = row,
    })

    -- Slider track
    local sliderTrack = Components.CreateFrame({
        Name = "Track",
        Size = UDim2.new(1, 0, 0, 8),
        Position = UDim2.new(0, 0, 0, 36),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = row,
    })

    -- Slider fill
    local sliderFill = Components.CreateFrame({
        Name = "Fill",
        Size = UDim2.new(defaultValue, 0, 1, 0),
        BackgroundColor = Components.Colors.Primary,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = sliderTrack,
    })

    -- Slider knob
    local sliderKnob = Components.CreateFrame({
        Name = "Knob",
        Size = UDim2.new(0, 20, 0, 20),
        Position = UDim2.new(defaultValue, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor = Components.Colors.TextPrimary,
        CornerRadius = UDim.new(0.5, 0),
        Parent = sliderTrack,
    })

    -- Value label
    local valueLabel = Components.CreateLabel({
        Name = "Value",
        Text = math.floor(defaultValue * 100) .. "%",
        Size = UDim2.new(0, 40, 0, 20),
        Position = UDim2.new(1, 0, 0, 0),
        AnchorPoint = Vector2.new(1, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row,
    })

    -- Drag functionality
    local dragging = false
    local currentValue = defaultValue

    local sliderButton = Instance.new("TextButton")
    sliderButton.Name = "SliderBtn"
    sliderButton.Size = UDim2.new(1, 0, 1, 20)
    sliderButton.Position = UDim2.new(0, 0, 0, -6)
    sliderButton.BackgroundTransparency = 1
    sliderButton.Text = ""
    sliderButton.Parent = sliderTrack

    local function updateSlider(inputPos: Vector2)
        local trackPos = sliderTrack.AbsolutePosition
        local trackSize = sliderTrack.AbsoluteSize

        local relativeX = math.clamp((inputPos.X - trackPos.X) / trackSize.X, 0, 1)
        currentValue = relativeX

        sliderFill.Size = UDim2.new(relativeX, 0, 1, 0)
        sliderKnob.Position = UDim2.new(relativeX, 0, 0.5, 0)
        valueLabel.Text = math.floor(relativeX * 100) .. "%"

        onChange(relativeX)
    end

    sliderButton.MouseButton1Down:Connect(function()
        dragging = true
    end)

    game:GetService("UserInputService").InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            updateSlider(Vector2.new(input.Position.X, input.Position.Y))
        end
    end)

    sliderButton.MouseButton1Click:Connect(function()
        local mouse = game:GetService("Players").LocalPlayer:GetMouse()
        updateSlider(Vector2.new(mouse.X, mouse.Y))
    end)

    return row
end

--[[
    Shows the settings UI.
]]
function SettingsUI:Show()
    if _isVisible then return end
    _isVisible = true

    _screenGui.Enabled = true
    Components.SlideIn(_panel, "bottom")
end

--[[
    Hides the settings UI.
]]
function SettingsUI:Hide()
    if not _isVisible then return end
    _isVisible = false

    Components.SlideOut(_panel, "bottom")
    task.delay(0.3, function()
        if not _isVisible then
            _screenGui.Enabled = false
        end
    end)

    SettingsUI.Closed:Fire()
end

--[[
    Toggles visibility.
]]
function SettingsUI:Toggle()
    if _isVisible then
        self:Hide()
    else
        self:Show()
    end
end

--[[
    Gets current settings.
]]
function SettingsUI:GetSettings(): typeof(_settings)
    return _settings
end

--[[
    Checks if visible.
]]
function SettingsUI:IsVisible(): boolean
    return _isVisible
end

--[[
    Initializes the SettingsUI.
]]
function SettingsUI:Init()
    if _initialized then
        warn("SettingsUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Load settings from player data
    local playerData = ClientAPI.GetPlayerData()
    if playerData and playerData.settings then
        _settings.musicEnabled = playerData.settings.musicEnabled ~= false
        _settings.sfxEnabled = playerData.settings.sfxEnabled ~= false
        _settings.notificationsEnabled = playerData.settings.notificationsEnabled ~= false
    end

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "SettingsUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Background overlay
    local overlay = Components.CreateFrame({
        Name = "Overlay",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.5,
        Parent = _screenGui,
    })

    local overlayButton = Instance.new("TextButton")
    overlayButton.Size = UDim2.new(1, 0, 1, 0)
    overlayButton.BackgroundTransparency = 1
    overlayButton.Text = ""
    overlayButton.Parent = overlay
    overlayButton.MouseButton1Click:Connect(function()
        self:Hide()
    end)

    -- Main panel
    _panel = Components.CreatePanel({
        Name = "SettingsPanel",
        Title = "Settings",
        Size = UDim2.new(0, 320, 0, 380),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        ShowCloseButton = true,
        OnClose = function()
            self:Hide()
        end,
        Parent = _screenGui,
    })

    local content = _panel:FindFirstChild("Content") :: Frame

    -- Settings list
    local settingsList = Components.CreateFrame({
        Name = "SettingsList",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Parent = content,
    })

    local listLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 8),
        Parent = settingsList,
    })

    -- Sound section header
    local soundHeader = Components.CreateLabel({
        Name = "SoundHeader",
        Text = "Sound",
        Size = UDim2.new(1, 0, 0, 24),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamBold,
        Parent = settingsList,
    })

    -- Music toggle
    createToggle("Music", "Music", _settings.musicEnabled, settingsList, function(enabled)
        _settings.musicEnabled = enabled
        SettingsUI.SettingChanged:Fire("musicEnabled", enabled)
    end)

    -- Music volume
    createSlider("MusicVolume", "Music Volume", _settings.musicVolume, settingsList, function(value)
        _settings.musicVolume = value
        SettingsUI.SettingChanged:Fire("musicVolume", value)
    end)

    -- SFX toggle
    createToggle("SFX", "Sound Effects", _settings.sfxEnabled, settingsList, function(enabled)
        _settings.sfxEnabled = enabled
        SettingsUI.SettingChanged:Fire("sfxEnabled", enabled)
    end)

    -- SFX volume
    createSlider("SFXVolume", "SFX Volume", _settings.sfxVolume, settingsList, function(value)
        _settings.sfxVolume = value
        SettingsUI.SettingChanged:Fire("sfxVolume", value)
    end)

    -- Notifications section
    local notifHeader = Components.CreateLabel({
        Name = "NotifHeader",
        Text = "Notifications",
        Size = UDim2.new(1, 0, 0, 24),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamBold,
        Parent = settingsList,
    })

    -- Notifications toggle
    createToggle("Notifications", "Push Notifications", _settings.notificationsEnabled, settingsList, function(enabled)
        _settings.notificationsEnabled = enabled
        SettingsUI.SettingChanged:Fire("notificationsEnabled", enabled)
    end)

    _initialized = true
    print("SettingsUI initialized")
end

return SettingsUI
