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

-- Wait for shared modules
repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Shared")

-- Wait for server events to be ready
repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Events")

local Events = ReplicatedStorage.Events
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)

-- Client state
local PlayerData = nil

-- Request initial data sync
Events.SyncPlayerData:FireServer()

-- Handle data sync from server
Events.SyncPlayerData.OnClientEvent:Connect(function(data)
    PlayerData = data
    print("[CLIENT] Player data synced")

    -- TODO: Update UI with new data
end)

-- Handle server responses
Events.ServerResponse.OnClientEvent:Connect(function(action: string, result: any)
    if result.success then
        print(string.format("[CLIENT] %s succeeded", action))

        -- Request data refresh after successful action
        Events.SyncPlayerData:FireServer()
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

-- Data access
ClientAPI.RegisterAction("GetPlayerData", function()
    return PlayerData
end)

ClientAPI.RegisterAction("RequestDataSync", function()
    Events.SyncPlayerData:FireServer()
end)

-- Mark API as ready
ClientAPI.SetReady()

-- ═══════════════════════════════════════════════════════════════════════════════
-- RENDERER INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════════

local Rendering = player:WaitForChild("PlayerScripts"):FindFirstChild("Rendering")
    or script.Parent:FindFirstChild("Rendering")

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

-- In runtime, scripts are in PlayerScripts (copied from StarterPlayerScripts)
local Controllers = player:WaitForChild("PlayerScripts"):FindFirstChild("Controllers")
    or script.Parent:FindFirstChild("Controllers")

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
-- WIRE UP RENDERERS TO DATA AND CONTROLLERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Render buildings when player data is synced
Events.SyncPlayerData.OnClientEvent:Connect(function(data)
    if CityRenderer and data.buildings then
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
    Events.BattleTick.OnClientEvent:Connect(function(state)
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
-- WIRE UP MATCHMAKING
-- ═══════════════════════════════════════════════════════════════════════════════

-- Listen for opponent found from server
Events.OpponentFound.OnClientEvent:Connect(function(opponent, skipCost)
    -- Notify WorldMapUI with real opponent data
    local uiControllerModule = Controllers and Controllers:FindFirstChild("UIController")
    if uiControllerModule then
        local UIController = require(uiControllerModule)
        -- The WorldMapUI will receive this via the UI system
    end

    print("[CLIENT] Opponent found:", opponent.username, "Trophies:", opponent.trophies)
end)

print("Battle Tycoon: Conquest - Client Ready!")
