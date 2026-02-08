--!strict
--[[
    UIController.lua

    Main UI orchestration controller.
    Manages all UI screens, transitions, and module initialization.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)

-- UI Modules (lazy loaded)
local HUD
local BuildMenu
local BuildingInfo
local BattleUI
local TroopTraining
local AllianceUI

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

    -- Update UI visibility based on screen
    if HUD then
        if screenName == "Battle" then
            HUD:SetVisible(false)
        else
            HUD:SetVisible(true)
        end
    end

    -- Close open menus on screen change
    if BuildMenu and BuildMenu:IsVisible() then
        BuildMenu:Hide()
    end
    if BuildingInfo and BuildingInfo:IsVisible() then
        BuildingInfo:Hide()
    end

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
    Shows the build menu.
]]
function UIController:ShowBuildMenu()
    if BuildMenu then
        BuildMenu:Show()
    end
end

--[[
    Hides the build menu.
]]
function UIController:HideBuildMenu()
    if BuildMenu then
        BuildMenu:Hide()
    end
end

--[[
    Shows building info for a building.
]]
function UIController:ShowBuildingInfo(buildingId: string, buildingData: any)
    if BuildingInfo then
        BuildingInfo:Show(buildingId, buildingData)
    end
end

--[[
    Hides building info.
]]
function UIController:HideBuildingInfo()
    if BuildingInfo then
        BuildingInfo:Hide()
    end
end

--[[
    Shows troop training UI.
]]
function UIController:ShowTroopTraining()
    if TroopTraining then
        TroopTraining:Show()
    end
end

--[[
    Hides troop training UI.
]]
function UIController:HideTroopTraining()
    if TroopTraining then
        TroopTraining:Hide()
    end
end

--[[
    Shows battle UI.
]]
function UIController:ShowBattleUI(battleId: string)
    if BattleUI then
        BattleUI:Show(battleId)
    end
end

--[[
    Hides battle UI.
]]
function UIController:HideBattleUI()
    if BattleUI then
        BattleUI:Hide()
    end
end

--[[
    Shows alliance UI.
]]
function UIController:ShowAllianceUI()
    if AllianceUI then
        AllianceUI:Show()
    end
end

--[[
    Hides alliance UI.
]]
function UIController:HideAllianceUI()
    if AllianceUI then
        AllianceUI:Hide()
    end
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

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Get UI modules from client scripts
    local clientScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
    local uiFolder = clientScripts:FindFirstChild("UI")

    if not uiFolder then
        -- UI folder might be in the player's scripts after spawn
        uiFolder = _player:WaitForChild("PlayerScripts"):FindFirstChild("UI")
    end

    -- Load UI modules from ReplicatedStorage approach instead
    -- Since Rojo maps our UI folder, we need to require from the right place
    local success, err = pcall(function()
        -- These are loaded relative to the script location
        local UI = script.Parent.Parent:WaitForChild("UI")
        HUD = require(UI:WaitForChild("HUD"))
        BuildMenu = require(UI:WaitForChild("BuildMenu"))
        BuildingInfo = require(UI:WaitForChild("BuildingInfo"))
        BattleUI = require(UI:WaitForChild("BattleUI"))
        TroopTraining = require(UI:WaitForChild("TroopTraining"))
        AllianceUI = require(UI:WaitForChild("AllianceUI"))
    end)

    if not success then
        warn("[UI] Failed to load UI modules:", err)
        -- Try alternative path
        pcall(function()
            local UI = _player:WaitForChild("PlayerScripts"):FindFirstChild("UI")
            if UI then
                HUD = require(UI:WaitForChild("HUD"))
                BuildMenu = require(UI:WaitForChild("BuildMenu"))
                BuildingInfo = require(UI:WaitForChild("BuildingInfo"))
                BattleUI = require(UI:WaitForChild("BattleUI"))
                TroopTraining = require(UI:WaitForChild("TroopTraining"))
                AllianceUI = require(UI:WaitForChild("AllianceUI"))
            end
        end)
    end

    -- Initialize UI modules
    if HUD then
        HUD:Init()

        -- Connect HUD events
        HUD.BuildMenuRequested:Connect(function()
            self:ShowBuildMenu()
        end)

        HUD.AttackRequested:Connect(function()
            self:SwitchScreen("WorldMap")
            print("[UI] Attack requested - switching to world map")
        end)

        HUD.ShopRequested:Connect(function()
            self:SwitchScreen("Market")
            print("[UI] Shop requested")
        end)
    end

    if BuildMenu then
        BuildMenu:Init()

        -- Connect BuildMenu events
        BuildMenu.BuildingSelected:Connect(function(buildingType)
            BuildMenu:Hide()

            -- Get CityController to enter placement mode
            local CityController = require(script.Parent.CityController)
            CityController:EnterPlacementMode(buildingType)
        end)
    end

    if BuildingInfo then
        BuildingInfo:Init()

        -- Connect BuildingInfo events
        BuildingInfo.Closed:Connect(function()
            -- Deselect building in CityController
            local CityController = require(script.Parent.CityController)
            CityController:DeselectBuilding()
        end)
    end

    if BattleUI then
        BattleUI:Init()

        -- Connect BattleUI events
        BattleUI.TroopSelected:Connect(function(troopType)
            local BattleController = require(script.Parent.BattleController)
            BattleController:SelectTroop(troopType)
        end)

        BattleUI.SurrenderRequested:Connect(function()
            local BattleController = require(script.Parent.BattleController)
            BattleController:Surrender()
        end)
    end

    if TroopTraining then
        TroopTraining:Init()
    end

    if AllianceUI then
        AllianceUI:Init()
    end

    -- Connect to BattleController events
    local BattleController = require(script.Parent.BattleController)

    BattleController.BattleStarted:Connect(function(battleId)
        self:SwitchScreen("Battle")
        if BattleUI then
            -- Get player troops for the battle UI
            local playerData = ClientAPI.GetPlayerData()
            if playerData and playerData.troops then
                BattleUI:UpdateTroops(playerData.troops)
            end
            BattleUI:Show(battleId)
        end
        if HUD then
            HUD:SetVisible(false)
        end
    end)

    BattleController.BattleEnded:Connect(function(result)
        self:SwitchScreen("City")
        if HUD then
            HUD:SetVisible(true)
        end
        -- BattleUI hides itself after showing results
    end)

    -- Connect to CityController events
    local CityController = require(script.Parent.CityController)

    CityController.BuildingSelected:Connect(function(buildingId)
        -- Get building data and show info panel
        local playerData = ClientAPI.GetPlayerData()
        if playerData and playerData.buildings then
            for _, building in playerData.buildings do
                if building.id == buildingId then
                    self:ShowBuildingInfo(buildingId, building)
                    break
                end
            end
        end
    end)

    CityController.BuildingDeselected:Connect(function()
        self:HideBuildingInfo()
    end)

    CityController.PlacementModeEntered:Connect(function(buildingType)
        -- Could show placement UI hints here
        print("[UI] Placement mode for:", buildingType)
    end)

    CityController.PlacementModeExited:Connect(function()
        -- Could hide placement UI hints here
        print("[UI] Placement mode exited")
    end)

    _initialized = true
    print("UIController initialized")
end

return UIController
