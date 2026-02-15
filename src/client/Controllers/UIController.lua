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
local Notifications
local SettingsUI
local WorldMapUI
local ShopUI
local QuestsUI
local DailyRewardUI
local LeaderboardUI
local SpellBrewingUI
local ProfileUI

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
    Shows settings UI.
]]
function UIController:ShowSettings()
    if SettingsUI then
        SettingsUI:Show()
    end
end

--[[
    Hides settings UI.
]]
function UIController:HideSettings()
    if SettingsUI then
        SettingsUI:Hide()
    end
end

--[[
    Shows a notification.
]]
function UIController:Notify(message: string, notifType: string?)
    if Notifications then
        Notifications:Show(message, notifType :: any)
    end
end

--[[
    Shows a notification with specific type (for external access).
]]
function UIController:ShowNotification(message: string, notifType: string?)
    if Notifications then
        if notifType == "success" then
            Notifications:Success(message)
        elseif notifType == "error" then
            Notifications:Error(message)
        elseif notifType == "warning" then
            Notifications:Warning(message)
        else
            Notifications:Info(message)
        end
    end
end

--[[
    Shows quests UI.
]]
function UIController:ShowQuests()
    if QuestsUI then
        QuestsUI:Show()
    end
end

--[[
    Hides quests UI.
]]
function UIController:HideQuests()
    if QuestsUI then
        QuestsUI:Hide()
    end
end

--[[
    Shows daily reward UI.
]]
function UIController:ShowDailyReward()
    if DailyRewardUI then
        DailyRewardUI:Show()
    end
end

--[[
    Hides daily reward UI.
]]
function UIController:HideDailyReward()
    if DailyRewardUI then
        DailyRewardUI:Hide()
    end
end

--[[
    Shows leaderboard UI.
]]
function UIController:ShowLeaderboard()
    if LeaderboardUI then
        LeaderboardUI:Show()
    end
end

--[[
    Hides leaderboard UI.
]]
function UIController:HideLeaderboard()
    if LeaderboardUI then
        LeaderboardUI:Hide()
    end
end

--[[
    Shows spell brewing UI.
]]
function UIController:ShowSpellBrewing()
    if SpellBrewingUI then
        SpellBrewingUI:Show()
    end
end

--[[
    Hides spell brewing UI.
]]
function UIController:HideSpellBrewing()
    if SpellBrewingUI then
        SpellBrewingUI:Hide()
    end
end

--[[
    Shows profile UI.
]]
function UIController:ShowProfile()
    if ProfileUI then
        ProfileUI:Show()
    end
end

--[[
    Hides profile UI.
]]
function UIController:HideProfile()
    if ProfileUI then
        ProfileUI:Hide()
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
        Notifications = require(UI:WaitForChild("Notifications"))
        SettingsUI = require(UI:WaitForChild("SettingsUI"))
        WorldMapUI = require(UI:WaitForChild("WorldMapUI"))
        ShopUI = require(UI:WaitForChild("ShopUI"))
        QuestsUI = require(UI:WaitForChild("QuestsUI"))
        DailyRewardUI = require(UI:WaitForChild("DailyRewardUI"))
        LeaderboardUI = require(UI:WaitForChild("LeaderboardUI"))
        SpellBrewingUI = require(UI:WaitForChild("SpellBrewingUI"))
        ProfileUI = require(UI:WaitForChild("ProfileUI"))
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
                Notifications = require(UI:WaitForChild("Notifications"))
                SettingsUI = require(UI:WaitForChild("SettingsUI"))
                WorldMapUI = require(UI:WaitForChild("WorldMapUI"))
                ShopUI = require(UI:WaitForChild("ShopUI"))
                QuestsUI = require(UI:WaitForChild("QuestsUI"))
                DailyRewardUI = require(UI:WaitForChild("DailyRewardUI"))
                LeaderboardUI = require(UI:WaitForChild("LeaderboardUI"))
                SpellBrewingUI = require(UI:WaitForChild("SpellBrewingUI"))
                ProfileUI = require(UI:WaitForChild("ProfileUI"))
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
            if WorldMapUI then
                WorldMapUI:Show()
            end
            print("[UI] Attack requested - showing world map")
        end)

        HUD.ShopRequested:Connect(function()
            self:SwitchScreen("Market")
            if ShopUI then
                ShopUI:Show()
            end
            print("[UI] Shop requested - showing shop")
        end)

        HUD.QuestsRequested:Connect(function()
            if QuestsUI then
                QuestsUI:Show()
            end
            print("[UI] Quests requested - showing quests")
        end)

        HUD.LeaderboardRequested:Connect(function()
            if LeaderboardUI then
                LeaderboardUI:Show()
            end
            print("[UI] Leaderboard requested - showing leaderboard")
        end)

        HUD.ProfileRequested:Connect(function()
            if ProfileUI then
                ProfileUI:Show()
            end
            print("[UI] Profile requested - showing profile")
        end)
    end

    if BuildMenu then
        BuildMenu:Init()

        -- Connect BuildMenu events
        BuildMenu.BuildingSelected:Connect(function(buildingType, farmNumber)
            BuildMenu:Hide()

            -- For walk-through tycoon, handle Farm building directly
            if buildingType == "Farm" and farmNumber then
                print("[UIController] Building Farm " .. farmNumber)

                -- Request server to build the farm via RemoteFunction
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                if remotes then
                    local buildFarm = remotes:FindFirstChild("BuildFarm")
                    if buildFarm then
                        local success, result = pcall(function()
                            return buildFarm:InvokeServer(farmNumber)
                        end)
                        if success and result and result.success then
                            -- Show success notification
                            if HUD and HUD.ShowNotification then
                                HUD:ShowNotification("Farm " .. farmNumber .. " built!", "success")
                            end
                            print("[UIController] Farm " .. farmNumber .. " built successfully!")
                        else
                            -- Show error notification
                            local errorMsg = (result and result.error) or "Failed to build farm"
                            if HUD and HUD.ShowNotification then
                                HUD:ShowNotification(errorMsg, "error")
                            end
                            warn("[UIController] Failed to build farm: " .. errorMsg)
                        end
                    else
                        warn("[UIController] BuildFarm remote not found")
                    end
                else
                    warn("[UIController] Remotes folder not found")
                end
            else
                -- Legacy: city builder placement mode (not used in walk-through tycoon)
                local CityController = require(script.Parent.CityController)
                if CityController and CityController.EnterPlacementMode then
                    CityController:EnterPlacementMode(buildingType)
                end
            end
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

    if Notifications then
        Notifications:Init()
    end

    if SettingsUI then
        SettingsUI:Init()
    end

    if WorldMapUI then
        WorldMapUI:Init()

        -- Connect WorldMapUI events
        WorldMapUI.AttackRequested:Connect(function(opponentId)
            local BattleController = require(script.Parent.BattleController)
            BattleController:StartBattle(opponentId)
        end)

        WorldMapUI.Closed:Connect(function()
            self:SwitchScreen("City")
        end)
    end

    if ShopUI then
        ShopUI:Init()

        -- Connect ShopUI events
        ShopUI.PurchaseRequested:Connect(function(item)
            -- Send purchase request to server
            local Events = ReplicatedStorage:WaitForChild("Events")
            if item.price then
                -- Real money purchase - would go through Roblox MarketplaceService
                print("[UI] Real money purchase requested:", item.id)
            elseif item.expansion then
                -- Farm plot expansion purchase
                print("[UI] Farm plot purchase requested:", item.id)
                Events.PurchaseFarmPlot:FireServer()
            else
                -- Gold purchase (builders, resources, boosts)
                Events.ShopPurchase:FireServer(item.id)
            end
        end)

        ShopUI.Closed:Connect(function()
            self:SwitchScreen("City")
        end)
    end

    if QuestsUI then
        QuestsUI:Init()

        -- Connect QuestsUI events
        QuestsUI.CloseRequested:Connect(function()
            print("[UI] Quests UI closed")
        end)
    end

    if DailyRewardUI then
        DailyRewardUI:Init()

        -- Connect DailyRewardUI events
        DailyRewardUI.CloseRequested:Connect(function()
            print("[UI] Daily Reward UI closed")
        end)

        DailyRewardUI.RewardClaimed:Connect(function(data)
            if Notifications then
                Notifications:Success("Daily reward claimed!")
            end
        end)

        -- Auto-show daily reward on login if available
        task.defer(function()
            task.wait(3) -- Wait for data to load
            DailyRewardUI:CheckAndShow()
        end)
    end

    if LeaderboardUI then
        LeaderboardUI:Init()

        -- Connect LeaderboardUI events
        LeaderboardUI.CloseRequested:Connect(function()
            print("[UI] Leaderboard UI closed")
        end)
    end

    if SpellBrewingUI then
        SpellBrewingUI:Init()

        -- Connect SpellBrewingUI events
        SpellBrewingUI.CloseRequested:Connect(function()
            print("[UI] Spell Brewing UI closed")
        end)
    end

    if ProfileUI then
        ProfileUI:Init()

        -- Connect ProfileUI events
        ProfileUI.CloseRequested:Connect(function()
            print("[UI] Profile UI closed")
        end)
    end

    -- Connect notifications to server responses
    local Events = ReplicatedStorage:WaitForChild("Events")
    Events.ServerResponse.OnClientEvent:Connect(function(action: string, result: any)
        if Notifications then
            if result.success then
                if action == "PlaceBuilding" then
                    Notifications:Success("Building placed!")
                elseif action == "UpgradeBuilding" then
                    Notifications:Success("Upgrade started!")
                elseif action == "CollectResources" then
                    Notifications:Success("Resources collected!")
                elseif action == "TrainTroop" then
                    Notifications:Success("Training started!")
                elseif action == "CreateAlliance" then
                    Notifications:Success("Alliance created!")
                elseif action == "JoinAlliance" then
                    Notifications:Success("Joined alliance!")
                elseif action == "ShopPurchase" then
                    Notifications:Success("Purchase complete!")
                elseif action == "PurchaseFarmPlot" then
                    Notifications:Success("Farm plot purchased! You can now build another farm.")
                elseif action == "ClaimQuestReward" then
                    Notifications:Success("Quest reward claimed!")
                elseif action == "ClaimDailyReward" then
                    Notifications:Success("Daily reward claimed!")
                elseif action == "BrewSpell" then
                    Notifications:Success("Spell brewing started!")
                elseif action == "CancelSpellBrewing" then
                    Notifications:Info("Spell brewing cancelled")
                elseif action == "HireWorker" then
                    Notifications:Success(result.message or "Worker hired!")
                end
            else
                local errorMsg = result.error or "Action failed"
                if errorMsg == "RATE_LIMITED" then
                    Notifications:Warning("Too many requests, slow down!")
                elseif errorMsg == "INSUFFICIENT_RESOURCES" then
                    Notifications:Error("Not enough resources!")
                elseif errorMsg == "INSUFFICIENT_GEMS" then
                    Notifications:Error("Not enough gems!")
                elseif errorMsg == "NO_BUILDER_AVAILABLE" then
                    Notifications:Warning("No builder available!")
                elseif errorMsg == "ALREADY_OWNED" then
                    Notifications:Info("You already own this!")
                elseif errorMsg == "PURCHASE_PREVIOUS_FIRST" then
                    Notifications:Warning("Purchase previous builder first!")
                elseif errorMsg == "NOT_COMPLETED" then
                    Notifications:Warning("Quest not completed yet!")
                elseif errorMsg == "ALREADY_CLAIMED" then
                    Notifications:Info("Already claimed!")
                elseif errorMsg == "QUEST_NOT_FOUND" then
                    Notifications:Error("Quest not found!")
                elseif errorMsg == "NO_SPELL_FACTORY" then
                    Notifications:Warning("Build a Spell Factory first!")
                elseif errorMsg == "NO_CAPACITY" then
                    Notifications:Warning("Spell storage full!")
                elseif errorMsg == "FACTORY_LEVEL_TOO_LOW" then
                    Notifications:Warning("Upgrade your Spell Factory!")
                elseif errorMsg == "NEED_MORE_FARM_PLOTS" then
                    Notifications:Warning("Buy a farm plot first! Check the Expand tab in Shop.")
                    -- Auto-open shop to Expansion tab
                    task.defer(function()
                        task.wait(0.5)
                        if ShopUI then
                            ShopUI:SwitchCategory("Expansion")
                            ShopUI:Show()
                        end
                    end)
                elseif errorMsg == "MAX_FARM_PLOTS_FOR_TH" then
                    Notifications:Warning("Upgrade Town Hall to unlock more farm plots!")
                elseif errorMsg == "MAX_FARM_PLOTS_REACHED" then
                    Notifications:Info("You have the maximum number of farm plots!")
                elseif errorMsg == "Not enough gold" then
                    Notifications:Error("Not enough gold!")
                elseif action == "HireWorker" then
                    Notifications:Warning(errorMsg)
                else
                    Notifications:Error(action .. " failed")
                end
            end
        end
    end)

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
