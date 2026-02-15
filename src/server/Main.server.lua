--!strict
--[[
    Main.server.lua - Battle Tycoon: Conquest Server Entry Point

    This script initializes all server services and creates the networking
    infrastructure (RemoteEvents) for client-server communication.

    Runs automatically when the game starts.
]]

print("========================================")
print("BATTLE TYCOON: CONQUEST - SERVER STARTING")
print("========================================")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 1: Wait for Shared modules to be available
-- ═══════════════════════════════════════════════════════════════════════════════
print("[SERVER] Waiting for Shared modules...")

repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Shared")

print("[SERVER] Shared modules found")

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 2: Create Events folder with all RemoteEvents and RemoteFunctions
-- ═══════════════════════════════════════════════════════════════════════════════
print("[SERVER] Creating Events folder...")

local Events = Instance.new("Folder")
Events.Name = "Events"
Events.Parent = ReplicatedStorage

-- Helper to create events
local function createRemoteEvent(name: string): RemoteEvent
    local event = Instance.new("RemoteEvent")
    event.Name = name
    event.Parent = Events
    return event
end

local function createRemoteFunction(name: string): RemoteFunction
    local func = Instance.new("RemoteFunction")
    func.Name = name
    func.Parent = Events
    return func
end

-- Data sync events
local SyncPlayerData = createRemoteEvent("SyncPlayerData")
local ServerResponse = createRemoteEvent("ServerResponse")
local FoodSupplyUpdate = createRemoteEvent("FoodSupplyUpdate")

-- Building events
local PlaceBuilding = createRemoteEvent("PlaceBuilding")
local UpgradeBuilding = createRemoteEvent("UpgradeBuilding")
local MoveBuilding = createRemoteEvent("MoveBuilding")
local CollectResources = createRemoteEvent("CollectResources")
local SpeedUpUpgrade = createRemoteEvent("SpeedUpUpgrade")
local PurchaseFarmPlot = createRemoteEvent("PurchaseFarmPlot")

-- Troop events
local TrainTroop = createRemoteEvent("TrainTroop")
local CancelTraining = createRemoteEvent("CancelTraining")

-- Combat events
local StartBattle = createRemoteEvent("StartBattle")
local DeployTroop = createRemoteEvent("DeployTroop")
local DeploySpell = createRemoteEvent("DeploySpell")
local BattleTick = createRemoteEvent("BattleTick")
local BattleEnded = createRemoteEvent("BattleEnded")

-- Matchmaking events
local FindOpponent = createRemoteEvent("FindOpponent")
local NextOpponent = createRemoteEvent("NextOpponent")
local OpponentFound = createRemoteEvent("OpponentFound")

-- World Map events
local GetMapPlayers = createRemoteFunction("GetMapPlayers")
local RelocateBase = createRemoteEvent("RelocateBase")
local GetRelocationStatus = createRemoteFunction("GetRelocationStatus")
local StartTravel = createRemoteEvent("StartTravel")
local CancelTravel = createRemoteEvent("CancelTravel")
local GetTravelTime = createRemoteFunction("GetTravelTime")
local TravelUpdate = createRemoteEvent("TravelUpdate")
local AddFriend = createRemoteEvent("AddFriend")
local RemoveFriend = createRemoteEvent("RemoveFriend")

-- Alliance events
local CreateAlliance = createRemoteEvent("CreateAlliance")
local JoinAlliance = createRemoteEvent("JoinAlliance")
local LeaveAlliance = createRemoteEvent("LeaveAlliance")
local DonateTroops = createRemoteEvent("DonateTroops")

-- Shop events
local ShopPurchase = createRemoteEvent("ShopPurchase")
local RedeemCode = createRemoteEvent("RedeemCode")

-- Action button events
local ActionButtonPressed = createRemoteEvent("ActionButtonPressed")

-- Tutorial events
local CompleteTutorial = createRemoteEvent("CompleteTutorial")

-- Quest events
local GetDailyQuests = createRemoteFunction("GetDailyQuests")
local GetAchievements = createRemoteFunction("GetAchievements")
local ClaimQuestReward = createRemoteEvent("ClaimQuestReward")
local QuestCompleted = createRemoteEvent("QuestCompleted")
local QuestProgress = createRemoteEvent("QuestProgress")

-- Daily reward events
local GetDailyRewardInfo = createRemoteFunction("GetDailyRewardInfo")
local ClaimDailyReward = createRemoteEvent("ClaimDailyReward")
local DailyRewardClaimed = createRemoteEvent("DailyRewardClaimed")

-- Spell events
local BrewSpell = createRemoteEvent("BrewSpell")
local CancelSpellBrewing = createRemoteEvent("CancelSpellBrewing")
local GetSpellQueue = createRemoteFunction("GetSpellQueue")
local SpellBrewingComplete = createRemoteEvent("SpellBrewingComplete")

-- Leaderboard events
local GetLeaderboard = createRemoteFunction("GetLeaderboard")
local GetPlayerRank = createRemoteFunction("GetPlayerRank")
local GetLeaderboardInfo = createRemoteFunction("GetLeaderboardInfo")
local LeagueChanged = createRemoteEvent("LeagueChanged")

-- Research events
local GetResearchList = createRemoteEvent("GetResearchList")
local StartResearchRequest = createRemoteEvent("StartResearchRequest")
local ResearchUpdate = createRemoteEvent("ResearchUpdate")
local OpenResearchUI = createRemoteEvent("OpenResearchUI")

-- Teleport events
local RequestTeleportToOverworld = createRemoteEvent("RequestTeleportToOverworld")

print("[SERVER] Events folder created with all RemoteEvents")

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 2.5: Detect Reserved Server + Initialize VillageStateService
-- ═══════════════════════════════════════════════════════════════════════════════

local TeleportService_main = game:GetService("TeleportService")
local _isReservedServer = (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)
local _villageOwnerUserId: number? = nil

if _isReservedServer then
    print("[SERVER] Running as RESERVED SERVER (per-player village instance)")

    -- Wait for the first player to arrive to read their teleport data
    local firstPlayer = Players.PlayerAdded:Wait()
    local joinData = firstPlayer:GetJoinData()
    local teleportData = joinData and joinData.TeleportData

    if teleportData and teleportData.ownerUserId then
        _villageOwnerUserId = teleportData.ownerUserId
        print(string.format("[SERVER] Village owner: %d (from teleport data)", _villageOwnerUserId))
    else
        -- Fallback: first player is owner
        _villageOwnerUserId = firstPlayer.UserId
        print(string.format("[SERVER] Village owner: %d (first player fallback)", _villageOwnerUserId))
    end
else
    print("[SERVER] Running as STANDARD SERVER (Studio or shared)")
    -- In Studio/standard mode, first player will become owner (handled in SimpleTest)
end

-- Initialize VillageStateService early (before other services) if we have an owner
local VillageStateService_main = nil
do
    local ServicesFolder_check = ServerScriptService:FindFirstChild("Services")
    if ServicesFolder_check then
        local vssModule = ServicesFolder_check:FindFirstChild("VillageStateService")
        if vssModule then
            local vssSuccess, vssResult = pcall(function()
                return require(vssModule)
            end)
            if vssSuccess then
                VillageStateService_main = vssResult
                if _villageOwnerUserId then
                    pcall(function()
                        VillageStateService_main:Init(_villageOwnerUserId)
                    end)
                    print(string.format("[SERVER] VillageStateService initialized for owner %d", _villageOwnerUserId))
                end
            else
                warn("[SERVER] Failed to load VillageStateService:", vssResult)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 3: Load and initialize services
-- ═══════════════════════════════════════════════════════════════════════════════
print("[SERVER] Loading services...")

local ServicesFolder = ServerScriptService:FindFirstChild("Services")
if not ServicesFolder then
    warn("[SERVER] Services folder not found!")
    return
end

-- Load services with error handling
local function loadService(name: string)
    local module = ServicesFolder:FindFirstChild(name)
    if not module then
        warn(string.format("[SERVER] Service not found: %s", name))
        return nil
    end

    local success, result = pcall(function()
        return require(module)
    end)

    if success then
        print(string.format("[SERVER] Loaded: %s", name))
        return result
    else
        warn(string.format("[SERVER] Failed to load %s: %s", name, tostring(result)))
        return nil
    end
end

-- Load all services
local DataService = loadService("DataService")
local BuildingService = loadService("BuildingService")
local TroopService = loadService("TroopService")
local CombatService = loadService("CombatService")
local EconomyService = loadService("EconomyService")
local AllianceService = loadService("AllianceService")
local MatchmakingService = loadService("MatchmakingService")
local QuestService = loadService("QuestService")
local DailyRewardService = loadService("DailyRewardService")
local SpellService = loadService("SpellService")
local LeaderboardService = loadService("LeaderboardService")
local WorldMapService = loadService("WorldMapService")

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 4: Initialize services
-- ═══════════════════════════════════════════════════════════════════════════════
print("[SERVER] Initializing services...")

local function initService(service, name: string)
    if service and service.Init then
        local success, err = pcall(function()
            service:Init()
        end)
        if success then
            print(string.format("[SERVER] Initialized: %s", name))
        else
            warn(string.format("[SERVER] Failed to init %s: %s", name, tostring(err)))
        end
    end
end

-- Initialize in dependency order
initService(DataService, "DataService")
initService(EconomyService, "EconomyService")
initService(BuildingService, "BuildingService")
initService(TroopService, "TroopService")
initService(SpellService, "SpellService")
initService(CombatService, "CombatService")
initService(MatchmakingService, "MatchmakingService")
initService(AllianceService, "AllianceService")
initService(QuestService, "QuestService")
initService(DailyRewardService, "DailyRewardService")
initService(LeaderboardService, "LeaderboardService")
initService(WorldMapService, "WorldMapService")

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 4.5: Village environment
-- NOTE: VillageBuilder is DISABLED - SimpleTest.server.lua builds the actual
-- gameplay village with buildings, walls, and interiors. VillageBuilder was
-- creating duplicate ground, invisible boundary walls, and overlapping objects
-- that blocked player movement.
-- ═══════════════════════════════════════════════════════════════════════════════
print("[SERVER] Village environment built by SimpleTest.server.lua (VillageBuilder disabled)")

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 5: Connect service signals for food supply updates
-- ═══════════════════════════════════════════════════════════════════════════════
print("[SERVER] Connecting service signals...")

-- Listen for building upgrade completion to update food supply
if BuildingService and BuildingService.UpgradeCompleted then
    BuildingService.UpgradeCompleted:Connect(function(player, building)
        if building.type == "Farm" then
            print(string.format("[FoodSupply] Farm upgrade complete for %s, sending update", player.Name))
            if DataService and DataService.GetFoodSupplyStatus then
                local status = DataService:GetFoodSupplyStatus(player)
                FoodSupplyUpdate:FireClient(player, status.production, status.usage, status.paused)
            end
        end
    end)
end

-- Listen for troop training completion to update food supply
if TroopService and TroopService.TrainingCompleted then
    TroopService.TrainingCompleted:Connect(function(player, troopType, quantity)
        print(string.format("[FoodSupply] Training complete for %s (%dx %s), sending update",
            player.Name, quantity, troopType))
        if DataService and DataService.GetFoodSupplyStatus then
            local status = DataService:GetFoodSupplyStatus(player)
            FoodSupplyUpdate:FireClient(player, status.production, status.usage, status.paused)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 6: Connect events to service handlers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[SERVER] Connecting event handlers...")

-- Helper for safe event connections
local function connectEvent(event: RemoteEvent, handler: (Player, ...any) -> ())
    event.OnServerEvent:Connect(function(player, ...)
        local success, err = pcall(handler, player, ...)
        if not success then
            warn(string.format("[SERVER] Event handler error: %s", tostring(err)))
            ServerResponse:FireClient(player, event.Name, { success = false, error = "Server error" })
        end
    end)
end

-- Data sync
connectEvent(SyncPlayerData, function(player)
    if DataService and DataService.GetPlayerData then
        local data = DataService:GetPlayerData(player)
        if data then
            SyncPlayerData:FireClient(player, data)
        end
    end
end)

-- Code redemption
local VALID_CODES = {
    ["giveme"] = { gold = 10000, wood = 10000, food = 10000 },
}

connectEvent(RedeemCode, function(player, code)
    if typeof(code) ~= "string" then return end
    code = string.lower(string.gsub(code, "%s+", ""))
    local reward = VALID_CODES[code]
    if not reward then
        ServerResponse:FireClient(player, "RedeemCode", { success = false, error = "Invalid code" })
        return
    end
    if DataService and DataService.UpdateResources then
        DataService:UpdateResources(player, reward)
        local data = DataService:GetPlayerData(player)
        if data then
            SyncPlayerData:FireClient(player, data)
        end
        ServerResponse:FireClient(player, "RedeemCode", { success = true, message = string.format("+%dg +%dw +%df", reward.gold or 0, reward.wood or 0, reward.food or 0) })
        print(string.format("[RedeemCode] %s redeemed '%s'", player.Name, code))
    end
end)

-- Shop purchases
local SHOP_ITEMS = {
    -- Resource packs (gold → wood/food)
    wood_500  = { type = "resource", resource = "wood", amount = 500,  goldCost = 750 },
    wood_2k   = { type = "resource", resource = "wood", amount = 2000, goldCost = 2500 },
    wood_5k   = { type = "resource", resource = "wood", amount = 5000, goldCost = 5000 },
    food_300  = { type = "resource", resource = "food", amount = 300,  goldCost = 500 },
    food_1k   = { type = "resource", resource = "food", amount = 1000, goldCost = 1500 },
    food_3k   = { type = "resource", resource = "food", amount = 3000, goldCost = 4000 },
    -- Shields (gold → timed protection)
    shield_1d = { type = "shield", duration = 86400,  goldCost = 1000 },
    shield_2d = { type = "shield", duration = 172800, goldCost = 2000 },
    shield_7d = { type = "shield", duration = 604800, goldCost = 4500 },
}

connectEvent(ShopPurchase, function(player, itemId)
    if typeof(itemId) ~= "string" then return end
    local item = SHOP_ITEMS[itemId]
    if not item then
        ServerResponse:FireClient(player, "ShopPurchase", { success = false, error = "Invalid item" })
        return
    end
    if not DataService or not DataService.CanAfford then
        ServerResponse:FireClient(player, "ShopPurchase", { success = false, error = "Server not ready" })
        return
    end
    if not DataService:CanAfford(player, { gold = item.goldCost }) then
        ServerResponse:FireClient(player, "ShopPurchase", { success = false, error = "Not enough gold" })
        return
    end

    DataService:DeductResources(player, { gold = item.goldCost })

    if item.type == "resource" then
        DataService:UpdateResources(player, { [item.resource] = item.amount })
    elseif item.type == "shield" then
        local data = DataService:GetPlayerData(player)
        if data then
            local now = os.time()
            local currentEnd = 0
            if data.shield and data.shield.expiresAt and data.shield.expiresAt > now then
                currentEnd = data.shield.expiresAt
            else
                currentEnd = now
            end
            data.shield = { type = itemId, expiresAt = currentEnd + item.duration }
            print(string.format("[Shop] %s shield active until %d (+%ds)", player.Name, data.shield.expiresAt, item.duration))
        end
    end

    local data = DataService:GetPlayerData(player)
    if data then
        SyncPlayerData:FireClient(player, data)
    end
    ServerResponse:FireClient(player, "ShopPurchase", { success = true })
    print(string.format("[Shop] %s purchased %s", player.Name, itemId))
end)

-- Helper to send food supply updates to client
local function sendFoodSupplyUpdate(player)
    if DataService and DataService.GetFoodSupplyStatus then
        local status = DataService:GetFoodSupplyStatus(player)
        print(string.format("[FoodSupply] Sending to %s: +%.1f/-%.1f paused=%s",
            player.Name, status.production, status.usage, tostring(status.paused)))
        FoodSupplyUpdate:FireClient(player, status.production, status.usage, status.paused)
    end
end

-- Building events
connectEvent(PlaceBuilding, function(player, buildingType, position)
    if BuildingService and BuildingService.PlaceBuilding then
        local result = BuildingService:PlaceBuilding(player, buildingType, position)
        ServerResponse:FireClient(player, "PlaceBuilding", result)
        -- Send food supply update if farm was placed
        if result.success and buildingType == "Farm" then
            sendFoodSupplyUpdate(player)
        end
    end
end)

connectEvent(UpgradeBuilding, function(player, buildingId)
    if BuildingService and BuildingService.UpgradeBuilding then
        -- Check if it's a farm before upgrading
        local building = BuildingService:GetBuilding(player, buildingId)
        local isFarm = building and building.type == "Farm"

        local result = BuildingService:UpgradeBuilding(player, buildingId)
        ServerResponse:FireClient(player, "UpgradeBuilding", result)

        -- Send food supply update if farm was upgraded (production changes when upgrade completes)
        if result.success and isFarm then
            sendFoodSupplyUpdate(player)
        end
    end
end)

connectEvent(CollectResources, function(player, buildingId)
    if BuildingService and BuildingService.CollectResources then
        local result = BuildingService:CollectResources(player, buildingId)
        ServerResponse:FireClient(player, "CollectResources", result)
    end
end)

connectEvent(PurchaseFarmPlot, function(player)
    if BuildingService and BuildingService.PurchaseFarmPlot then
        local result = BuildingService:PurchaseFarmPlot(player)
        ServerResponse:FireClient(player, "PurchaseFarmPlot", result)
    end
end)

-- Troop events
connectEvent(TrainTroop, function(player, troopType, quantity)
    if TroopService and TroopService.TrainTroop then
        local result = TroopService:TrainTroop(player, troopType, quantity)
        ServerResponse:FireClient(player, "TrainTroop", result)
        -- Food supply update is sent when training completes (in TroopService)
        -- But also send current state so client knows the pending usage
        sendFoodSupplyUpdate(player)
    end
end)

connectEvent(CancelTraining, function(player, queueIndex)
    if TroopService and TroopService.CancelTraining then
        local result = TroopService:CancelTraining(player, queueIndex)
        ServerResponse:FireClient(player, "CancelTraining", result)
    end
end)

-- Combat events
connectEvent(StartBattle, function(player, defenderUserId)
    if CombatService and CombatService.StartBattle then
        local result = CombatService:StartBattle(player, defenderUserId)
        ServerResponse:FireClient(player, "StartBattle", result)
    end
end)

connectEvent(DeployTroop, function(player, battleId, troopType, position)
    if CombatService and CombatService.DeployTroop then
        CombatService:DeployTroop(battleId, player, troopType, position)
    end
end)

connectEvent(DeploySpell, function(player, battleId, spellType, position)
    if CombatService and CombatService.DeploySpell then
        CombatService:DeploySpell(battleId, player, spellType, position)
    end
end)

-- Matchmaking events
connectEvent(FindOpponent, function(player)
    if MatchmakingService and MatchmakingService.FindOpponent then
        local result = MatchmakingService:FindOpponent(player)
        if result then
            OpponentFound:FireClient(player, result, 0)
        end
    end
end)

connectEvent(NextOpponent, function(player)
    if MatchmakingService and MatchmakingService.NextOpponent then
        local result = MatchmakingService:NextOpponent(player, 1)
        if result then
            OpponentFound:FireClient(player, result, 0)
        end
    end
end)

-- Alliance events
connectEvent(CreateAlliance, function(player, name, description)
    if AllianceService and AllianceService.CreateAlliance then
        local result = AllianceService:CreateAlliance(player, name, description)
        ServerResponse:FireClient(player, "CreateAlliance", result)
    end
end)

connectEvent(JoinAlliance, function(player, allianceId)
    if AllianceService and AllianceService.JoinAlliance then
        local result = AllianceService:JoinAlliance(player, allianceId)
        ServerResponse:FireClient(player, "JoinAlliance", result)
    end
end)

connectEvent(LeaveAlliance, function(player)
    if AllianceService and AllianceService.LeaveAlliance then
        local result = AllianceService:LeaveAlliance(player)
        ServerResponse:FireClient(player, "LeaveAlliance", result)
    end
end)

connectEvent(DonateTroops, function(player, recipientUserId, troopType, count)
    if AllianceService and AllianceService.DonateTroops then
        local result = AllianceService:DonateTroops(player, recipientUserId, troopType, count)
        ServerResponse:FireClient(player, "DonateTroops", result)
    end
end)

-- Quest functions
GetDailyQuests.OnServerInvoke = function(player)
    if QuestService and QuestService.GetDailyQuests then
        return QuestService:GetDailyQuests(player)
    end
    return {}
end

GetAchievements.OnServerInvoke = function(player)
    if QuestService and QuestService.GetAchievements then
        return QuestService:GetAchievements(player)
    end
    return {}
end

connectEvent(ClaimQuestReward, function(player, questId)
    if QuestService and QuestService.ClaimReward then
        local result = QuestService:ClaimReward(player, questId)
        ServerResponse:FireClient(player, "ClaimQuestReward", result)
        if result.success then
            QuestCompleted:FireClient(player, { questId = questId, title = questId })
        end
    end
end)

-- Daily reward functions
GetDailyRewardInfo.OnServerInvoke = function(player)
    if DailyRewardService and DailyRewardService.GetRewardInfo then
        return DailyRewardService:GetRewardInfo(player)
    end
    return nil
end

connectEvent(ClaimDailyReward, function(player)
    if DailyRewardService and DailyRewardService.ClaimReward then
        local result = DailyRewardService:ClaimReward(player)
        if result and result.success then
            DailyRewardClaimed:FireClient(player, result)
        end
        ServerResponse:FireClient(player, "ClaimDailyReward", result or { success = false })
    end
end)

-- Spell functions
GetSpellQueue.OnServerInvoke = function(player)
    if SpellService and SpellService.GetBrewingQueue then
        return SpellService:GetBrewingQueue(player)
    end
    return {}
end

connectEvent(BrewSpell, function(player, spellType)
    if SpellService and SpellService.BrewSpell then
        local result = SpellService:BrewSpell(player, spellType)
        ServerResponse:FireClient(player, "BrewSpell", result)
    end
end)

connectEvent(CancelSpellBrewing, function(player, queueIndex)
    if SpellService and SpellService.CancelBrewing then
        local result = SpellService:CancelBrewing(player, queueIndex)
        ServerResponse:FireClient(player, "CancelSpellBrewing", result)
    end
end)

-- Leaderboard functions
GetLeaderboard.OnServerInvoke = function(player, count)
    if LeaderboardService and LeaderboardService.GetTopPlayers then
        return LeaderboardService:GetTopPlayers(count or 100)
    end
    return {}
end

GetPlayerRank.OnServerInvoke = function(player)
    if LeaderboardService and LeaderboardService.GetPlayerRank then
        return LeaderboardService:GetPlayerRank(player)
    end
    return nil
end

GetLeaderboardInfo.OnServerInvoke = function(player)
    if LeaderboardService and LeaderboardService.GetLeaderboardInfo then
        return LeaderboardService:GetLeaderboardInfo(player)
    end
    return nil
end

-- World Map functions
GetMapPlayers.OnServerInvoke = function(player, centerPosition, maxCount)
    if WorldMapService and WorldMapService.GetNearbyPlayers then
        return WorldMapService:GetNearbyPlayers(player, centerPosition, maxCount)
    end
    return {}
end

GetRelocationStatus.OnServerInvoke = function(player)
    if WorldMapService and WorldMapService.GetRelocationStatus then
        return WorldMapService:GetRelocationStatus(player)
    end
    return { canRelocateFree = true, cooldownRemaining = 0, costIfNow = 0 }
end

GetTravelTime.OnServerInvoke = function(player, targetPosition)
    if WorldMapService and WorldMapService.GetTravelTime then
        return WorldMapService:GetTravelTime(player, targetPosition)
    end
    return { success = false, error = "SERVICE_UNAVAILABLE" }
end

connectEvent(RelocateBase, function(player, newPosition)
    if WorldMapService and WorldMapService.RelocateBase then
        local result = WorldMapService:RelocateBase(player, newPosition)
        ServerResponse:FireClient(player, "RelocateBase", result)
    end
end)

connectEvent(StartTravel, function(player, targetUserId)
    if WorldMapService and WorldMapService.StartTravel then
        local result = WorldMapService:StartTravel(player, targetUserId)
        ServerResponse:FireClient(player, "StartTravel", result)

        -- If traveling, send updates
        if result.success and result.travelTime > 0 then
            task.spawn(function()
                while true do
                    task.wait(1)
                    local remaining = WorldMapService:GetRemainingTravelTime(player)
                    if remaining <= 0 then
                        TravelUpdate:FireClient(player, { complete = true, targetId = targetUserId })
                        break
                    else
                        TravelUpdate:FireClient(player, { complete = false, remaining = remaining })
                    end
                end
            end)
        end
    end
end)

connectEvent(CancelTravel, function(player)
    if WorldMapService and WorldMapService.CancelTravel then
        local result = WorldMapService:CancelTravel(player)
        ServerResponse:FireClient(player, "CancelTravel", { success = result })
    end
end)

connectEvent(AddFriend, function(player, friendUserId)
    if WorldMapService and WorldMapService.AddFriend then
        local result = WorldMapService:AddFriend(player, friendUserId)
        ServerResponse:FireClient(player, "AddFriend", { success = result })
    end
end)

connectEvent(RemoveFriend, function(player, friendUserId)
    if WorldMapService and WorldMapService.RemoveFriend then
        local result = WorldMapService:RemoveFriend(player, friendUserId)
        ServerResponse:FireClient(player, "RemoveFriend", { success = result })
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 6: Player connection handling
-- ═══════════════════════════════════════════════════════════════════════════════
print("[SERVER] Setting up player handlers...")

Players.PlayerAdded:Connect(function(player)
    print(string.format("[SERVER] Player joined: %s (%d)", player.Name, player.UserId))

    -- Load player data
    if DataService and DataService.LoadPlayerData then
        local success, result = pcall(function()
            return DataService:LoadPlayerData(player)
        end)

        if success and result and result.success and result.data then
            -- Sync data to client
            task.wait(1) -- Brief wait for client to be ready
            SyncPlayerData:FireClient(player, result.data)

            -- Check daily rewards
            if DailyRewardService and DailyRewardService.CheckAvailable then
                local available = DailyRewardService:CheckAvailable(player.UserId)
                -- Client will check via GetDailyRewardInfo
            end

            print(string.format("[SERVER] Data loaded for %s", player.Name))
        else
            local errorMsg = result and result.error or "Unknown error"
            warn(string.format("[SERVER] Failed to load data for %s: %s", player.Name, errorMsg))
        end
    end
end)

Players.PlayerRemoving:Connect(function(player)
    print(string.format("[SERVER] Player leaving: %s (%d)", player.Name, player.UserId))

    -- NOTE: DataService's own PlayerRemoving handler saves data and releases lock.
    -- Do NOT call DataService:SavePlayerData here — it causes double saves and
    -- races where DataService clears _playerData before this handler runs.

    -- Clean up matchmaking
    if MatchmakingService and MatchmakingService.PlayerLeft then
        MatchmakingService:PlayerLeft(player.UserId)
    end
end)

-- Handle game shutdown - save all data + village state
game:BindToClose(function()
    print("[SERVER] Game closing, saving all player data...")

    -- Serialize village state into playerData (no separate DataStore write)
    if VillageStateService_main then
        pcall(function()
            VillageStateService_main:Shutdown()
        end)
    end

    -- DataService saves everything (resources + village state) in one DataStore write
    if DataService and DataService.SaveAllData then
        DataService:SaveAllData()
    end

    task.wait(5) -- Give time for saves with retry backoff to complete
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- TELEPORT TO OVERWORLD
-- ═══════════════════════════════════════════════════════════════════════════════
local TeleportService = game:GetService("TeleportService")
local OverworldConfig = nil
pcall(function()
    OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
end)

local _teleportRateLimit: {[number]: number} = {}

connectEvent(RequestTeleportToOverworld, function(player)
    -- Rate limit: 1 request per 3 seconds
    local now = os.clock()
    local last = _teleportRateLimit[player.UserId] or 0
    if now - last < 3 then return end
    _teleportRateLimit[player.UserId] = now

    local overworldPlaceId = OverworldConfig and OverworldConfig.Teleport
        and OverworldConfig.Teleport.OverworldPlaceId
    if not overworldPlaceId or overworldPlaceId == 0 then
        warn("[SERVER] OverworldPlaceId not configured")
        ServerResponse:FireClient(player, "TeleportToOverworld", {
            success = false, error = "Overworld not configured",
        })
        return
    end

    -- Serialize village state into playerData before teleport (PrepareForTeleport will persist it)
    if player.UserId == _villageOwnerUserId and VillageStateService_main then
        local saveStateOk = pcall(function()
            VillageStateService_main:SaveState()
        end)
        if not saveStateOk then
            warn(string.format("[SERVER] VillageStateService:SaveState() failed for %s", player.Name))
            ServerResponse:FireClient(player, "TeleportToOverworld", {
                success = false, error = "Failed to save village state",
            })
            return
        end
    end

    -- Prepare for teleport BEFORE initiating: save data, release lock, mark as teleporting.
    -- This prevents the race condition where PlayerRemoving fires between Teleport()
    -- and PrepareForTeleport, causing double saves or nil data.
    if DataService and DataService.PrepareForTeleport then
        local prepOk, prepResult = pcall(function()
            return DataService:PrepareForTeleport(player)
        end)
        if not prepOk or not prepResult then
            -- prepResult is the boolean return on success, or error string on pcall failure
            warn(string.format("[SERVER] PrepareForTeleport failed for %s: %s", player.Name, tostring(prepResult)))
            ServerResponse:FireClient(player, "TeleportToOverworld", {
                success = false, error = "Failed to save data for teleport",
            })
            return
        end
    end

    -- Teleport to overworld
    local success, err = pcall(function()
        TeleportService:Teleport(overworldPlaceId, player)
    end)

    if success then
        print(string.format("[SERVER] Teleporting %s to overworld", player.Name))
        -- Data already saved and lock released by PrepareForTeleport.
        -- PlayerRemoving will skip save (teleport flag set) and just clean up cache.
    else
        warn(string.format("[SERVER] Teleport failed for %s: %s", player.Name, tostring(err)))
        -- Teleport failed — cancel teleport state to re-acquire lock and restore normal operation
        if DataService and DataService.CancelTeleportState then
            DataService:CancelTeleportState(player)
        end
        -- Data is still in cache, sync to client
        if DataService then
            local data = DataService:GetPlayerData(player)
            if data then
                SyncPlayerData:FireClient(player, data)
                print(string.format("[SERVER] Data restored for %s after failed teleport", player.Name))
            end
        end
        ServerResponse:FireClient(player, "TeleportToOverworld", {
            success = false, error = "Teleport failed",
        })
    end
end)

-- Handle failed teleports: if Roblox accepted the call but the teleport fails
-- later, the player stays in-game but PrepareForTeleport already saved data
-- and released the lock. Cancel teleport state to re-acquire lock.
TeleportService.TeleportInitFailed:Connect(function(player, _result, errorMessage)
    warn(string.format("[SERVER] Teleport failed for %s after init: %s", player.Name, tostring(errorMessage)))

    -- Cancel teleport state: clears flag and re-acquires session lock
    if DataService and DataService.CancelTeleportState then
        DataService:CancelTeleportState(player)
    end

    -- Data should still be in cache (PrepareForTeleport no longer clears it)
    if DataService then
        local data = DataService:GetPlayerData(player)
        if data then
            SyncPlayerData:FireClient(player, data)
            print(string.format("[SERVER] Data restored for %s after TeleportInitFailed", player.Name))
        else
            -- Data somehow missing — attempt reload
            warn(string.format("[SERVER] Data missing for %s after TeleportInitFailed, attempting reload", player.Name))
            if DataService.LoadPlayerData then
                local result = DataService:LoadPlayerData(player)
                if result.success and result.data then
                    SyncPlayerData:FireClient(player, result.data)
                else
                    player:Kick("Teleport failed and we couldn't restore your data. Please rejoin!")
                end
            end
        end
    end
end)

Players.PlayerRemoving:Connect(function(player)
    _teleportRateLimit[player.UserId] = nil
end)

print("========================================")
print("BATTLE TYCOON: CONQUEST - SERVER READY!")
print("========================================")
