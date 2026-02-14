--!strict
--[[
    Client Entry Point

    Initializes all client controllers and sets up UI.
    This script runs when a player joins.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

print("Battle Tycoon: Conquest - Client Starting...")

-- Village is built server-side in WorldSetup.server.lua for reliability

-- Wait for shared modules
repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Shared")

-- Wait for server events to be ready (with timeout)
local eventsWaitStart = tick()
repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Events") or (tick() - eventsWaitStart > 5)

local Events = ReplicatedStorage:FindFirstChild("Events")
if not Events then
    warn("[CLIENT] Events folder not found, waiting longer...")
    -- Wait a bit longer for server to create events
    local extendedWait = tick()
    repeat
        task.wait(0.5)
        Events = ReplicatedStorage:FindFirstChild("Events")
    until Events or (tick() - extendedWait > 10)

    if not Events then
        warn("[CLIENT] Events folder still not found after extended wait, game features will not work")
        return -- Exit early, can't run without events
    end
end

print("[CLIENT] Events folder found")

local ClientAPI = nil
local clientAPIModule = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Modules") and ReplicatedStorage.Shared.Modules:FindFirstChild("ClientAPI")
if clientAPIModule then
    ClientAPI = require(clientAPIModule)
end

-- Client state
local PlayerData = nil

-- Wait for specific events to exist
local function waitForEvent(eventName: string): RemoteEvent?
    local event = Events:FindFirstChild(eventName)
    if not event then
        local waitStart = tick()
        repeat
            task.wait(0.1)
            event = Events:FindFirstChild(eventName)
        until event or (tick() - waitStart > 5)
    end
    return event
end

-- Get required events
local SyncPlayerData = waitForEvent("SyncPlayerData")
local ServerResponse = waitForEvent("ServerResponse")

if not SyncPlayerData or not ServerResponse then
    warn("[CLIENT] Required events not found")
    return
end

-- Request initial data sync
SyncPlayerData:FireServer()

-- Handle data sync from server
SyncPlayerData.OnClientEvent:Connect(function(data)
    PlayerData = data
    print("[CLIENT] Player data synced")

    -- TODO: Update UI with new data
end)

-- Handle server responses
ServerResponse.OnClientEvent:Connect(function(action: string, result: any)
    if result and result.success then
        print(string.format("[CLIENT] %s succeeded", action))

        -- Request data refresh after successful action
        SyncPlayerData:FireServer()
    else
        warn(string.format("[CLIENT] %s failed: %s", action, result.error or "Unknown"))

        -- TODO: Show error UI to player
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- REGISTER CLIENT ACTIONS WITH ClientAPI
-- ═══════════════════════════════════════════════════════════════════════════════

-- Building actions
ClientAPI.RegisterAction("PlaceBuilding", function(buildingType: string, position: Vector3)
    Events.PlaceBuilding:FireServer(buildingType, position)
end)

ClientAPI.RegisterAction("UpgradeBuilding", function(buildingId: string)
    Events.UpgradeBuilding:FireServer(buildingId)
end)

ClientAPI.RegisterAction("CollectResources", function(buildingId: string)
    Events.CollectResources:FireServer(buildingId)
end)

ClientAPI.RegisterAction("SpeedUpUpgrade", function(buildingId: string)
    Events.SpeedUpUpgrade:FireServer(buildingId)
end)

-- Troop actions
ClientAPI.RegisterAction("TrainTroop", function(troopType: string, quantity: number)
    Events.TrainTroop:FireServer(troopType, quantity)
end)

ClientAPI.RegisterAction("CancelTraining", function(queueIndex: number)
    Events.CancelTraining:FireServer(queueIndex)
end)

-- Combat actions
ClientAPI.RegisterAction("StartBattle", function(defenderUserId: number)
    Events.StartBattle:FireServer(defenderUserId)
end)

ClientAPI.RegisterAction("DeployTroop", function(battleId: string, troopType: string, position: Vector3)
    Events.DeployTroop:FireServer(battleId, troopType, position)
end)

ClientAPI.RegisterAction("DeploySpell", function(battleId: string, spellType: string, position: Vector3)
    Events.DeploySpell:FireServer(battleId, spellType, position)
end)

-- Alliance actions
ClientAPI.RegisterAction("CreateAlliance", function(name: string, description: string?)
    Events.CreateAlliance:FireServer(name, description or "")
end)

ClientAPI.RegisterAction("JoinAlliance", function(allianceId: string)
    Events.JoinAlliance:FireServer(allianceId)
end)

ClientAPI.RegisterAction("LeaveAlliance", function()
    Events.LeaveAlliance:FireServer()
end)

ClientAPI.RegisterAction("DonateTroops", function(recipientUserId: number, troopType: string, count: number)
    Events.DonateTroops:FireServer(recipientUserId, troopType, count)
end)

-- Shop actions
ClientAPI.RegisterAction("ShopPurchase", function(itemId: string)
    Events.ShopPurchase:FireServer(itemId)
end)

-- Matchmaking actions
ClientAPI.RegisterAction("FindOpponent", function()
    Events.FindOpponent:FireServer()
end)

ClientAPI.RegisterAction("NextOpponent", function()
    Events.NextOpponent:FireServer()
end)

-- Tutorial actions
ClientAPI.RegisterAction("CompleteTutorial", function()
    Events.CompleteTutorial:FireServer()
end)

-- Quest actions
ClientAPI.RegisterAction("GetDailyQuests", function()
    return Events.GetDailyQuests:InvokeServer()
end)

ClientAPI.RegisterAction("GetAchievements", function()
    return Events.GetAchievements:InvokeServer()
end)

ClientAPI.RegisterAction("ClaimQuestReward", function(questId: string)
    Events.ClaimQuestReward:FireServer(questId)
end)

-- Daily reward actions
ClientAPI.RegisterAction("GetDailyRewardInfo", function()
    return Events.GetDailyRewardInfo:InvokeServer()
end)

ClientAPI.RegisterAction("ClaimDailyReward", function()
    Events.ClaimDailyReward:FireServer()
end)

-- Spell actions
ClientAPI.RegisterAction("BrewSpell", function(spellType: string)
    Events.BrewSpell:FireServer(spellType)
end)

ClientAPI.RegisterAction("CancelSpellBrewing", function(queueIndex: number)
    Events.CancelSpellBrewing:FireServer(queueIndex)
end)

ClientAPI.RegisterAction("GetSpellQueue", function()
    return Events.GetSpellQueue:InvokeServer()
end)

-- Leaderboard actions
ClientAPI.RegisterAction("GetLeaderboard", function(count: number?)
    return Events.GetLeaderboard:InvokeServer(count or 100)
end)

ClientAPI.RegisterAction("GetPlayerRank", function()
    return Events.GetPlayerRank:InvokeServer()
end)

ClientAPI.RegisterAction("GetLeaderboardInfo", function()
    return Events.GetLeaderboardInfo:InvokeServer()
end)

-- Data access
ClientAPI.RegisterAction("GetPlayerData", function()
    return PlayerData
end)

ClientAPI.RegisterAction("RequestDataSync", function()
    SyncPlayerData:FireServer()
end)

-- Mark API as ready
ClientAPI.SetReady()

-- ═══════════════════════════════════════════════════════════════════════════════
-- RENDERER INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- With Rojo init.client.lua pattern, child folders are direct children of script
local Rendering = script:FindFirstChild("Rendering")

local CityRenderer, BattleRenderer

if Rendering then
    -- Initialize renderers
    local cityRendererModule = Rendering:FindFirstChild("CityRenderer")
    if cityRendererModule then
        local success, err = pcall(function()
            CityRenderer = require(cityRendererModule)
            CityRenderer:Init()
        end)
        if success then
            print("[CLIENT] CityRenderer initialized")
        else
            warn("[CLIENT] Failed to initialize CityRenderer:", err)
        end
    end

    local battleRendererModule = Rendering:FindFirstChild("BattleRenderer")
    if battleRendererModule then
        local success, err = pcall(function()
            BattleRenderer = require(battleRendererModule)
            BattleRenderer:Init()
        end)
        if success then
            print("[CLIENT] BattleRenderer initialized")
        else
            warn("[CLIENT] Failed to initialize BattleRenderer:", err)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- CONTROLLER INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- With Rojo init.client.lua pattern, Controllers folder is a child of script
local Controllers = script:FindFirstChild("Controllers")

if Controllers then
    local initOrder = {
        "CameraController", -- First so camera is ready for other controllers
        "InputController", -- Input before controllers that need it
        "AudioController", -- Audio before UI so sounds can play on UI load
        "UIController",
        "CityController",
        "BattleController",
        "TutorialController", -- Last so UI is ready for tutorial overlays
    }

    for _, controllerName in initOrder do
        local controllerModule = Controllers:FindFirstChild(controllerName)
        if controllerModule then
            local success, err = pcall(function()
                local controller = require(controllerModule)
                if controller.Init then
                    controller:Init()
                end
            end)

            if success then
                print(string.format("[CLIENT] %s initialized", controllerName))
            else
                warn(string.format("[CLIENT] Failed to initialize %s: %s", controllerName, err))
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- INITIALIZE RESEARCH UI
-- ═══════════════════════════════════════════════════════════════════════════════

do
    local uiFolder = script:FindFirstChild("UI")
    if uiFolder then
        local researchUIModule = uiFolder:FindFirstChild("ResearchUI")
        if researchUIModule then
            local success, err = pcall(function()
                local ResearchUI = require(researchUIModule)
                ResearchUI:Init()
            end)
            if success then
                print("[CLIENT] ResearchUI initialized")
            else
                warn("[CLIENT] Failed to initialize ResearchUI:", err)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- INITIALIZE BATTLE UI (HUD)
-- ═══════════════════════════════════════════════════════════════════════════════

do
    local uiFolder = script:FindFirstChild("UI")
    if uiFolder then
        local battleUIModule = uiFolder:FindFirstChild("BattleUI")
        if battleUIModule then
            local success, err = pcall(function()
                local BattleUI = require(battleUIModule)
                BattleUI:Init()
            end)
            if success then
                print("[CLIENT] BattleUI initialized")
            else
                warn("[CLIENT] Failed to initialize BattleUI:", err)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- WIRE UP RENDERERS TO DATA AND CONTROLLERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Render buildings when player data is synced
SyncPlayerData.OnClientEvent:Connect(function(data)
    if CityRenderer and data and data.buildings then
        CityRenderer:RenderAllBuildings(data.buildings)
    end
end)

-- Connect CityRenderer to CityController
if CityRenderer and Controllers then
    local cityControllerModule = Controllers:FindFirstChild("CityController")
    if cityControllerModule then
        local CityController = require(cityControllerModule)

        -- Building click -> select
        CityRenderer.BuildingClicked:Connect(function(buildingId)
            CityController:SelectBuilding(buildingId)
        end)

        -- Placement mode updates
        CityController.PlacementModeEntered:Connect(function(buildingType)
            CityRenderer:ShowPlacementPreview(buildingType)
        end)

        CityController.PlacementModeExited:Connect(function()
            CityRenderer:HidePlacementPreview()
        end)

        -- Building selection for highlight
        CityController.BuildingSelected:Connect(function(buildingId)
            CityRenderer:SelectBuilding(buildingId)
        end)

        CityController.BuildingDeselected:Connect(function()
            CityRenderer:DeselectBuilding()
        end)
    end
end

-- Connect BattleRenderer to BattleController
if BattleRenderer and Controllers then
    local battleControllerModule = Controllers:FindFirstChild("BattleController")
    if battleControllerModule then
        local BattleController = require(battleControllerModule)

        -- Battle start -> activate renderer
        BattleController.BattleStarted:Connect(function(battleId)
            BattleRenderer:Activate()
        end)

        -- Battle end -> deactivate renderer
        BattleController.BattleEnded:Connect(function(result)
            BattleRenderer:Deactivate()
        end)

        -- Deploy click from renderer
        BattleRenderer.DeployPositionClicked:Connect(function(position)
            BattleController:HandleDeployInput(position)
        end)
    end

    -- Update battle visuals from server state
    local BattleTick = Events:FindFirstChild("BattleTick")
    if BattleTick then
        BattleTick.OnClientEvent:Connect(function(state)
            if not BattleRenderer then return end

            -- Update troop positions
            if state.troops then
                for id, troopData in state.troops do
                    if troopData.health and troopData.health <= 0 then
                        BattleRenderer:RemoveTroop(id)
                    elseif troopData.position then
                        -- Check if troop exists
                        local existingTroop = BattleRenderer:UpdateTroopPosition(id, troopData.position)
                        if not existingTroop then
                            BattleRenderer:RenderTroop(id, troopData)
                        end
                        if troopData.healthPercent then
                            BattleRenderer:UpdateTroopHealth(id, troopData.healthPercent)
                        end
                    end
                end
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- WIRE UP INPUT CONTROLLER
-- ═══════════════════════════════════════════════════════════════════════════════

if Controllers then
    local inputControllerModule = Controllers:FindFirstChild("InputController")
    local cityControllerModule = Controllers:FindFirstChild("CityController")

    if inputControllerModule and cityControllerModule then
        local InputController = require(inputControllerModule)
        local CityController = require(cityControllerModule)

        -- World click handling for city
        InputController.WorldPositionClicked:Connect(function(worldPos)
            if CityController:IsInPlacementMode() then
                -- Placement mode - confirm building placement
                local gridX, gridZ = InputController:WorldToGrid(worldPos)
                CityController:ConfirmPlacement(gridX, gridZ)
            else
                -- Normal mode - check for building click (handled by CityRenderer)
                -- If no building at position, deselect
                if CityRenderer then
                    local buildingId = CityRenderer:GetBuildingAtPosition(worldPos)
                    if buildingId then
                        CityController:SelectBuilding(buildingId)
                    else
                        CityController:DeselectBuilding()
                    end
                end
            end
        end)

        -- Cancel action (escape key)
        InputController.CancelAction:Connect(function()
            if CityController:IsInPlacementMode() then
                CityController:ExitPlacementMode()
            else
                CityController:DeselectBuilding()
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- WIRE UP GATE -> WORLD MAP
-- ═══════════════════════════════════════════════════════════════════════════════

if Controllers then
    local cityControllerModule = Controllers:FindFirstChild("CityController")
    if cityControllerModule then
        local CityController = require(cityControllerModule)

        -- When player reaches the gate, open the World Map
        CityController.GateReached:Connect(function()
            -- Find WorldMapUI in the UI folder
            local uiFolder = script:FindFirstChild("UI")
            if uiFolder then
                local worldMapUIModule = uiFolder:FindFirstChild("WorldMapUI")
                if worldMapUIModule then
                    local WorldMapUI = require(worldMapUIModule)

                    -- Initialize if not already
                    if not WorldMapUI:IsVisible() then
                        if not WorldMapUI:IsInitialized() then
                            WorldMapUI:Init()
                        end
                        WorldMapUI:Show()
                        print("[CLIENT] Opened World Map from gate")
                    end
                end
            end
        end)

        print("[CLIENT] Gate -> World Map connection established")
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- WIRE UP MATCHMAKING
-- ═══════════════════════════════════════════════════════════════════════════════

-- Helper to safely connect to events
local function safeConnect(eventName: string, handler: (...any) -> ())
    local event = Events:FindFirstChild(eventName)
    if event then
        event.OnClientEvent:Connect(handler)
    else
        warn("[CLIENT] Event not found: " .. eventName)
    end
end

-- Listen for opponent found from server
safeConnect("OpponentFound", function(opponent, skipCost)
    -- Notify WorldMapUI with real opponent data
    local uiControllerModule = Controllers and Controllers:FindFirstChild("UIController")
    if uiControllerModule then
        local UIController = require(uiControllerModule)
        -- The WorldMapUI will receive this via the UI system
    end

    print("[CLIENT] Opponent found:", opponent.username, "Trophies:", opponent.trophies)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- WIRE UP QUESTS AND DAILY REWARDS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Listen for quest completion
safeConnect("QuestCompleted", function(data)
    local uiControllerModule = Controllers and Controllers:FindFirstChild("UIController")
    if uiControllerModule then
        local UIController = require(uiControllerModule)
        if UIController.ShowNotification then
            local prefix = data.isAchievement and "Achievement Unlocked: " or "Quest Complete: "
            UIController:ShowNotification(prefix .. data.title, "success")
        end
    end

    print("[CLIENT] Quest/Achievement completed:", data.questId, data.title)
end)

-- Listen for quest progress
safeConnect("QuestProgress", function(data)
    print(string.format("[CLIENT] Quest progress: %s - %d/%d", data.questId, data.progress, data.target))
end)

-- Listen for daily reward claimed
safeConnect("DailyRewardClaimed", function(data)
    local uiControllerModule = Controllers and Controllers:FindFirstChild("UIController")
    if uiControllerModule then
        local UIController = require(uiControllerModule)
        if UIController.ShowNotification then
            local rewardText = ""
            if data.reward and data.reward.gold then
                rewardText = rewardText .. data.reward.gold .. " Gold "
            end
            if data.reward and data.reward.gems then
                rewardText = rewardText .. data.reward.gems .. " Gems "
            end
            UIController:ShowNotification("Daily Reward: " .. rewardText, "success")

            -- Show streak bonus if applicable
            if data.streakBonus then
                local bonusText = ""
                if data.streakBonus.gems then
                    bonusText = data.streakBonus.gems .. " Gems"
                end
                UIController:ShowNotification("Streak Bonus: " .. bonusText .. " (Day " .. data.newStreak .. ")", "success")
            end
        end
    end

    print(string.format("[CLIENT] Daily reward claimed! Streak: %d", data.newStreak))
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- WIRE UP SPELLS AND LEADERBOARD
-- ═══════════════════════════════════════════════════════════════════════════════

-- Listen for spell brewing complete
safeConnect("SpellBrewingComplete", function(data)
    local uiControllerModule = Controllers and Controllers:FindFirstChild("UIController")
    if uiControllerModule then
        local UIController = require(uiControllerModule)
        if UIController.ShowNotification then
            UIController:ShowNotification(data.spellType .. " spell ready!", "success")
        end
    end

    print("[CLIENT] Spell brewing complete:", data.spellType)
end)

-- Listen for league changes
safeConnect("LeagueChanged", function(data)
    local uiControllerModule = Controllers and Controllers:FindFirstChild("UIController")
    if uiControllerModule then
        local UIController = require(uiControllerModule)
        if UIController.ShowNotification then
            if data.newLeague.minTrophies > data.oldLeague.minTrophies then
                UIController:ShowNotification("Promoted to " .. data.newLeague.name .. "!", "success")
            else
                UIController:ShowNotification("Demoted to " .. data.newLeague.name, "warning")
            end
        end
    end

    print("[CLIENT] League changed:", data.oldLeague.name, "->", data.newLeague.name)
end)

print("Battle Tycoon: Conquest - Client Ready!")
