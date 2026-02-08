--!strict
--[[
    UIController.lua

    Main UI orchestration controller.
    Manages all UI screens and transitions.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local UIController = {}
UIController.__index = UIController

-- Events
UIController.ScreenChanged = Signal.new()
UIController.PopupOpened = Signal.new()
UIController.PopupClosed = Signal.new()

-- Private state
local _currentScreen = "City"
local _initialized = false
local _player = Players.LocalPlayer

-- Screen definitions
local Screens = {
    "City",
    "WorldMap",
    "Battle",
    "Alliance",
    "Market",
    "Profile",
}

--[[
    Gets the current active screen.
]]
function UIController:GetCurrentScreen(): string
    return _currentScreen
end

--[[
    Switches to a different screen.
]]
function UIController:SwitchScreen(screenName: string): boolean
    if not table.find(Screens, screenName) then
        warn("Invalid screen:", screenName)
        return false
    end

    if screenName == _currentScreen then
        return true
    end

    local previousScreen = _currentScreen
    _currentScreen = screenName

    -- Fire event for UI updates
    UIController.ScreenChanged:Fire(screenName, previousScreen)

    print(string.format("[UI] Switched from %s to %s", previousScreen, screenName))
    return true
end

--[[
    Opens a popup overlay.
]]
function UIController:OpenPopup(popupName: string, data: any?)
    UIController.PopupOpened:Fire(popupName, data)
end

--[[
    Closes the current popup.
]]
function UIController:ClosePopup(popupName: string)
    UIController.PopupClosed:Fire(popupName)
end

--[[
    Formats a number for display (e.g., 1500 -> "1.5K")
]]
function UIController.FormatNumber(value: number): string
    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fK", value / 1000)
    else
        return tostring(math.floor(value))
    end
end

--[[
    Formats time remaining for display.
]]
function UIController.FormatTime(seconds: number): string
    if seconds <= 0 then
        return "Ready"
    end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

--[[
    Initializes the UIController.
]]
function UIController:Init()
    if _initialized then
        warn("UIController already initialized")
        return
    end

    -- Setup player GUI
    local playerGui = _player:WaitForChild("PlayerGui")

    -- TODO: Create main UI screens
    -- TODO: Setup navigation buttons
    -- TODO: Setup resource display HUD

    _initialized = true
    print("UIController initialized")
end

return UIController
