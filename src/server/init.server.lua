--!strict
--[[
    Server Entry Point

    Initializes all server services in correct order.
    This script runs when the server starts.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("Battle Tycoon: Conquest - Server Starting...")

-- Wait for shared modules to be accessible
repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Shared")

-- Service initialization order matters
-- DataService must be first as other services depend on it
local Services = ServerScriptService:WaitForChild("Services")

-- Initialize services in dependency order
local initOrder = {
    "DataService",
    "BuildingService",
    "EconomyService",
    "TroopService",
    "SpellService",
    "CombatService",
    "AllianceService",
    "MatchmakingService",
    "QuestService",
    "DailyRewardService",
    "LeaderboardService",
}

for _, serviceName in initOrder do
    local serviceModule = Services:FindFirstChild(serviceName)
    if serviceModule then
        local success, err = pcall(function()
            local service = require(serviceModule)
            if service.Init then
                service:Init()
            end
        end)

        if success then
            print(string.format("[SERVER] %s initialized", serviceName))
        else
            warn(string.format("[SERVER] Failed to initialize %s: %s", serviceName, err))
        end
    else
        warn(string.format("[SERVER] Service not found: %s", serviceName))
    end
end

-- Setup RemoteEvents for client-server communication
local function setupRemoteEvents()
    local Events = Instance.new("Folder")
    Events.Name = "Events"
    Events.Parent = ReplicatedStorage

    -- Building events
    local PlaceBuilding = Instance.new("RemoteEvent")
    PlaceBuilding.Name = "PlaceBuilding"
    PlaceBuilding.Parent = Events

    local UpgradeBuilding = Instance.new("RemoteEvent")
    UpgradeBuilding.Name = "UpgradeBuilding"
    UpgradeBuilding.Parent = Events

    local CollectResources = Instance.new("RemoteEvent")
    CollectResources.Name = "CollectResources"
    CollectResources.Parent = Events

    local SpeedUpUpgrade = Instance.new("RemoteEvent")
    SpeedUpUpgrade.Name = "SpeedUpUpgrade"
    SpeedUpUpgrade.Parent = Events

    -- Response events
    local ServerResponse = Instance.new("RemoteEvent")
    ServerResponse.Name = "ServerResponse"
    ServerResponse.Parent = Events

    -- Data sync event
    local SyncPlayerData = Instance.new("RemoteEvent")
    SyncPlayerData.Name = "SyncPlayerData"
    SyncPlayerData.Parent = Events

    -- Troop training events
    local TrainTroop = Instance.new("RemoteEvent")
    TrainTroop.Name = "TrainTroop"
    TrainTroop.Parent = Events

    local CancelTraining = Instance.new("RemoteEvent")
    CancelTraining.Name = "CancelTraining"
    CancelTraining.Parent = Events

    -- Combat events
    local StartBattle = Instance.new("RemoteEvent")
    StartBattle.Name = "StartBattle"
    StartBattle.Parent = Events

    local DeployTroop = Instance.new("RemoteEvent")
    DeployTroop.Name = "DeployTroop"
    DeployTroop.Parent = Events

    local DeploySpell = Instance.new("RemoteEvent")
    DeploySpell.Name = "DeploySpell"
    DeploySpell.Parent = Events

    -- Battle state broadcast events (server → client)
    local BattleTick = Instance.new("RemoteEvent")
    BattleTick.Name = "BattleTick"
    BattleTick.Parent = Events

    local BattleEnded = Instance.new("RemoteEvent")
    BattleEnded.Name = "BattleEnded"
    BattleEnded.Parent = Events

    -- Alliance events
    local CreateAlliance = Instance.new("RemoteEvent")
    CreateAlliance.Name = "CreateAlliance"
    CreateAlliance.Parent = Events

    local JoinAlliance = Instance.new("RemoteEvent")
    JoinAlliance.Name = "JoinAlliance"
    JoinAlliance.Parent = Events

    local LeaveAlliance = Instance.new("RemoteEvent")
    LeaveAlliance.Name = "LeaveAlliance"
    LeaveAlliance.Parent = Events

    local DonateTroops = Instance.new("RemoteEvent")
    DonateTroops.Name = "DonateTroops"
    DonateTroops.Parent = Events

    -- Shop events
    local ShopPurchase = Instance.new("RemoteEvent")
    ShopPurchase.Name = "ShopPurchase"
    ShopPurchase.Parent = Events

    -- Matchmaking events
    local FindOpponent = Instance.new("RemoteEvent")
    FindOpponent.Name = "FindOpponent"
    FindOpponent.Parent = Events

    local NextOpponent = Instance.new("RemoteEvent")
    NextOpponent.Name = "NextOpponent"
    NextOpponent.Parent = Events

    local OpponentFound = Instance.new("RemoteEvent")
    OpponentFound.Name = "OpponentFound"
    OpponentFound.Parent = Events

    -- Tutorial events
    local CompleteTutorial = Instance.new("RemoteEvent")
    CompleteTutorial.Name = "CompleteTutorial"
    CompleteTutorial.Parent = Events

    -- Quest events
    local GetDailyQuests = Instance.new("RemoteFunction")
    GetDailyQuests.Name = "GetDailyQuests"
    GetDailyQuests.Parent = Events

    local GetAchievements = Instance.new("RemoteFunction")
    GetAchievements.Name = "GetAchievements"
    GetAchievements.Parent = Events

    local ClaimQuestReward = Instance.new("RemoteEvent")
    ClaimQuestReward.Name = "ClaimQuestReward"
    ClaimQuestReward.Parent = Events

    local QuestCompleted = Instance.new("RemoteEvent")
    QuestCompleted.Name = "QuestCompleted"
    QuestCompleted.Parent = Events

    local QuestProgress = Instance.new("RemoteEvent")
    QuestProgress.Name = "QuestProgress"
    QuestProgress.Parent = Events

    -- Daily reward events
    local GetDailyRewardInfo = Instance.new("RemoteFunction")
    GetDailyRewardInfo.Name = "GetDailyRewardInfo"
    GetDailyRewardInfo.Parent = Events

    local ClaimDailyReward = Instance.new("RemoteEvent")
    ClaimDailyReward.Name = "ClaimDailyReward"
    ClaimDailyReward.Parent = Events

    local DailyRewardClaimed = Instance.new("RemoteEvent")
    DailyRewardClaimed.Name = "DailyRewardClaimed"
    DailyRewardClaimed.Parent = Events

    -- Spell events
    local BrewSpell = Instance.new("RemoteEvent")
    BrewSpell.Name = "BrewSpell"
    BrewSpell.Parent = Events

    local CancelSpellBrewing = Instance.new("RemoteEvent")
    CancelSpellBrewing.Name = "CancelSpellBrewing"
    CancelSpellBrewing.Parent = Events

    local GetSpellQueue = Instance.new("RemoteFunction")
    GetSpellQueue.Name = "GetSpellQueue"
    GetSpellQueue.Parent = Events

    local SpellBrewingComplete = Instance.new("RemoteEvent")
    SpellBrewingComplete.Name = "SpellBrewingComplete"
    SpellBrewingComplete.Parent = Events

    -- Leaderboard events
    local GetLeaderboard = Instance.new("RemoteFunction")
    GetLeaderboard.Name = "GetLeaderboard"
    GetLeaderboard.Parent = Events

    local GetPlayerRank = Instance.new("RemoteFunction")
    GetPlayerRank.Name = "GetPlayerRank"
    GetPlayerRank.Parent = Events

    local GetLeaderboardInfo = Instance.new("RemoteFunction")
    GetLeaderboardInfo.Name = "GetLeaderboardInfo"
    GetLeaderboardInfo.Parent = Events

    local LeagueChanged = Instance.new("RemoteEvent")
    LeagueChanged.Name = "LeagueChanged"
    LeagueChanged.Parent = Events

    return Events
end

local Events = setupRemoteEvents()

-- Connect RemoteEvent handlers with security validation
local RateLimiter = {}

-- Constants for input validation
local MAX_STRING_LENGTH = 36 -- GUIDs are 36 characters
local MAX_BUILDING_TYPE_LENGTH = 50

--[[
    Validates string input for length and type.
    Prevents memory exhaustion from oversized strings.
]]
local function validateStringInput(value: any, maxLength: number): boolean
    if typeof(value) ~= "string" then return false end
    if #value > maxLength then return false end
    if #value == 0 then return false end
    return true
end

local function checkRateLimit(player: Player, action: string, limit: number): boolean
    local now = os.clock()
    RateLimiter[player.UserId] = RateLimiter[player.UserId] or {}
    local playerLimits = RateLimiter[player.UserId]

    playerLimits[action] = playerLimits[action] or { count = 0, reset = now + 1 }
    local data = playerLimits[action]

    if now > data.reset then
        data.count = 0
        data.reset = now + 1
    end

    data.count += 1
    return data.count <= limit
end

-- Building placement handler
Events.PlaceBuilding.OnServerEvent:Connect(function(player, buildingType, position)
    -- Rate limit
    if not checkRateLimit(player, "PlaceBuilding", 2) then
        Events.ServerResponse:FireClient(player, "PlaceBuilding", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type and length validation (prevents memory exhaustion)
    if not validateStringInput(buildingType, MAX_BUILDING_TYPE_LENGTH) then return end
    if typeof(position) ~= "Vector3" then return end

    -- Execute
    local BuildingService = require(Services.BuildingService)
    local result = BuildingService:PlaceBuilding(player, buildingType, position)

    Events.ServerResponse:FireClient(player, "PlaceBuilding", result)
end)

-- Building upgrade handler
Events.UpgradeBuilding.OnServerEvent:Connect(function(player, buildingId)
    -- Rate limit
    if not checkRateLimit(player, "UpgradeBuilding", 2) then
        Events.ServerResponse:FireClient(player, "UpgradeBuilding", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type and length validation (GUIDs are 36 chars)
    if not validateStringInput(buildingId, MAX_STRING_LENGTH) then return end

    -- Execute
    local BuildingService = require(Services.BuildingService)
    local result = BuildingService:UpgradeBuilding(player, buildingId)

    Events.ServerResponse:FireClient(player, "UpgradeBuilding", result)
end)

-- Resource collection handler
Events.CollectResources.OnServerEvent:Connect(function(player, buildingId)
    -- Rate limit
    if not checkRateLimit(player, "CollectResources", 10) then
        Events.ServerResponse:FireClient(player, "CollectResources", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type and length validation (GUIDs are 36 chars)
    if not validateStringInput(buildingId, MAX_STRING_LENGTH) then return end

    -- Execute
    local BuildingService = require(Services.BuildingService)
    local result = BuildingService:CollectResources(player, buildingId)

    Events.ServerResponse:FireClient(player, "CollectResources", result)
end)

-- Speed up handler
Events.SpeedUpUpgrade.OnServerEvent:Connect(function(player, buildingId)
    -- Rate limit
    if not checkRateLimit(player, "SpeedUpUpgrade", 5) then
        Events.ServerResponse:FireClient(player, "SpeedUpUpgrade", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type and length validation (GUIDs are 36 chars)
    if not validateStringInput(buildingId, MAX_STRING_LENGTH) then return end

    -- Execute
    local EconomyService = require(Services.EconomyService)
    local success = EconomyService:SpeedUpUpgrade(player, buildingId)

    Events.ServerResponse:FireClient(player, "SpeedUpUpgrade", { success = success })
end)

-- Sync player data on request
Events.SyncPlayerData.OnServerEvent:Connect(function(player)
    -- Rate limit
    if not checkRateLimit(player, "SyncPlayerData", 5) then return end

    local DataService = require(Services.DataService)
    local playerData = DataService:GetPlayerData(player)

    if playerData then
        -- Only send safe data to client (not sensitive fields)
        local safeData = {
            resources = playerData.resources,
            townHallLevel = playerData.townHallLevel,
            buildings = playerData.buildings,
            troops = playerData.troops,
            spells = playerData.spells,
            armyCampCapacity = playerData.armyCampCapacity,
            builders = playerData.builders,
            shield = playerData.shield,
            trophies = playerData.trophies,
            stats = playerData.stats,
            vipActive = playerData.vipActive,
        }

        Events.SyncPlayerData:FireClient(player, safeData)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- TROOP SERVICE HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Train troop handler
Events.TrainTroop.OnServerEvent:Connect(function(player, troopType, quantity)
    -- Rate limit
    if not checkRateLimit(player, "TrainTroop", 10) then
        Events.ServerResponse:FireClient(player, "TrainTroop", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if not validateStringInput(troopType, MAX_BUILDING_TYPE_LENGTH) then return end
    if typeof(quantity) ~= "number" then return end
    quantity = math.floor(quantity) -- Ensure integer
    if quantity < 1 or quantity > 50 then return end -- Reasonable limit

    -- Execute
    local TroopService = require(Services.TroopService)
    local result = TroopService:TrainTroop(player, troopType, quantity)

    Events.ServerResponse:FireClient(player, "TrainTroop", result)
end)

-- Cancel training handler
Events.CancelTraining.OnServerEvent:Connect(function(player, queueIndex)
    -- Rate limit
    if not checkRateLimit(player, "CancelTraining", 5) then
        Events.ServerResponse:FireClient(player, "CancelTraining", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if typeof(queueIndex) ~= "number" then return end
    queueIndex = math.floor(queueIndex) -- Ensure integer
    if queueIndex < 1 or queueIndex > 50 then return end -- Reasonable limit

    -- Execute
    local TroopService = require(Services.TroopService)
    local result = TroopService:CancelTraining(player, queueIndex)

    Events.ServerResponse:FireClient(player, "CancelTraining", result)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- COMBAT SERVICE HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Start battle handler
Events.StartBattle.OnServerEvent:Connect(function(player, defenderUserId)
    -- Rate limit (battles are expensive)
    if not checkRateLimit(player, "StartBattle", 1) then
        Events.ServerResponse:FireClient(player, "StartBattle", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if typeof(defenderUserId) ~= "number" then return end
    defenderUserId = math.floor(defenderUserId) -- Ensure integer
    if defenderUserId < 1 then return end

    -- Execute
    local CombatService = require(Services.CombatService)
    local result = CombatService:StartBattle(player, defenderUserId)

    Events.ServerResponse:FireClient(player, "StartBattle", result)
end)

-- Deploy troop handler
Events.DeployTroop.OnServerEvent:Connect(function(player, battleId, troopType, position)
    -- Rate limit (troops can be deployed quickly in battle)
    if not checkRateLimit(player, "DeployTroop", 30) then return end

    -- Type validation
    if not validateStringInput(battleId, MAX_STRING_LENGTH) then return end
    if not validateStringInput(troopType, MAX_BUILDING_TYPE_LENGTH) then return end
    if typeof(position) ~= "Vector3" then return end

    -- Execute
    local CombatService = require(Services.CombatService)
    local result = CombatService:DeployTroop(player, battleId, troopType, position)

    if not result.success then
        Events.ServerResponse:FireClient(player, "DeployTroop", result)
    end
    -- Successful deploys are broadcast via BattleTick events
end)

-- Deploy spell handler
Events.DeploySpell.OnServerEvent:Connect(function(player, battleId, spellType, position)
    -- Rate limit
    if not checkRateLimit(player, "DeploySpell", 10) then return end

    -- Type validation
    if not validateStringInput(battleId, MAX_STRING_LENGTH) then return end
    if not validateStringInput(spellType, MAX_BUILDING_TYPE_LENGTH) then return end
    if typeof(position) ~= "Vector3" then return end

    -- Execute
    local CombatService = require(Services.CombatService)
    local result = CombatService:DeploySpell(player, battleId, spellType, position)

    if not result.success then
        Events.ServerResponse:FireClient(player, "DeploySpell", result)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- ALLIANCE SERVICE HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

local MAX_ALLIANCE_NAME_LENGTH = 20
local MAX_DESCRIPTION_LENGTH = 200

-- Create alliance handler
Events.CreateAlliance.OnServerEvent:Connect(function(player, name, description)
    -- Rate limit (expensive operation)
    if not checkRateLimit(player, "CreateAlliance", 1) then
        Events.ServerResponse:FireClient(player, "CreateAlliance", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if not validateStringInput(name, MAX_ALLIANCE_NAME_LENGTH) then return end
    description = description or ""
    if typeof(description) ~= "string" then return end
    if #description > MAX_DESCRIPTION_LENGTH then return end

    -- Execute
    local AllianceService = require(Services.AllianceService)
    local result = AllianceService:CreateAlliance(player, name, description)

    Events.ServerResponse:FireClient(player, "CreateAlliance", result)
end)

-- Join alliance handler
Events.JoinAlliance.OnServerEvent:Connect(function(player, allianceId)
    -- Rate limit
    if not checkRateLimit(player, "JoinAlliance", 2) then
        Events.ServerResponse:FireClient(player, "JoinAlliance", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if not validateStringInput(allianceId, MAX_STRING_LENGTH) then return end

    -- Execute
    local AllianceService = require(Services.AllianceService)
    local result = AllianceService:JoinAlliance(player, allianceId)

    Events.ServerResponse:FireClient(player, "JoinAlliance", result)
end)

-- Leave alliance handler
Events.LeaveAlliance.OnServerEvent:Connect(function(player)
    -- Rate limit
    if not checkRateLimit(player, "LeaveAlliance", 1) then
        Events.ServerResponse:FireClient(player, "LeaveAlliance", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Execute
    local AllianceService = require(Services.AllianceService)
    local result = AllianceService:LeaveAlliance(player)

    Events.ServerResponse:FireClient(player, "LeaveAlliance", result)
end)

-- Donate troops handler
Events.DonateTroops.OnServerEvent:Connect(function(player, recipientUserId, troopType, count)
    -- Rate limit
    if not checkRateLimit(player, "DonateTroops", 10) then
        Events.ServerResponse:FireClient(player, "DonateTroops", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if typeof(recipientUserId) ~= "number" then return end
    recipientUserId = math.floor(recipientUserId)
    if recipientUserId < 1 then return end
    if not validateStringInput(troopType, MAX_BUILDING_TYPE_LENGTH) then return end
    if typeof(count) ~= "number" then return end
    count = math.floor(count)
    if count < 1 or count > 10 then return end -- Reasonable donation limit

    -- Execute
    local AllianceService = require(Services.AllianceService)
    local result = AllianceService:DonateTroops(player, recipientUserId, troopType, count)

    Events.ServerResponse:FireClient(player, "DonateTroops", result)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- SHOP HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

local MAX_ITEM_ID_LENGTH = 50

-- Shop purchase handler (gem purchases)
Events.ShopPurchase.OnServerEvent:Connect(function(player, itemId)
    -- Rate limit
    if not checkRateLimit(player, "ShopPurchase", 5) then
        Events.ServerResponse:FireClient(player, "ShopPurchase", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if not validateStringInput(itemId, MAX_ITEM_ID_LENGTH) then return end

    -- Execute
    local EconomyService = require(Services.EconomyService)
    local result = EconomyService:ProcessShopPurchase(player, itemId)

    Events.ServerResponse:FireClient(player, "ShopPurchase", result)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- MATCHMAKING HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Player search counters for skip cost calculation
local _playerSearchCounts: {[number]: number} = {}

-- Find opponent handler
Events.FindOpponent.OnServerEvent:Connect(function(player)
    -- Rate limit
    if not checkRateLimit(player, "FindOpponent", 2) then
        Events.ServerResponse:FireClient(player, "FindOpponent", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Reset search count for new search session
    _playerSearchCounts[player.UserId] = 1

    -- Execute
    local MatchmakingService = require(Services.MatchmakingService)
    local opponent, err = MatchmakingService:FindOpponent(player)

    if opponent then
        Events.OpponentFound:FireClient(player, opponent)
    else
        Events.ServerResponse:FireClient(player, "FindOpponent", { success = false, error = err or "NO_OPPONENT" })
    end
end)

-- Next opponent handler (skip)
Events.NextOpponent.OnServerEvent:Connect(function(player)
    -- Rate limit
    if not checkRateLimit(player, "NextOpponent", 5) then
        Events.ServerResponse:FireClient(player, "NextOpponent", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Increment search count
    local searchCount = (_playerSearchCounts[player.UserId] or 0) + 1
    _playerSearchCounts[player.UserId] = searchCount

    -- Execute
    local MatchmakingService = require(Services.MatchmakingService)
    local opponent, err = MatchmakingService:NextOpponent(player, searchCount)

    if opponent then
        local skipCost = MatchmakingService:GetSkipCost(searchCount)
        Events.OpponentFound:FireClient(player, opponent, skipCost)
    else
        Events.ServerResponse:FireClient(player, "NextOpponent", { success = false, error = err or "NO_OPPONENT" })
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- TUTORIAL HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Complete tutorial handler
Events.CompleteTutorial.OnServerEvent:Connect(function(player)
    -- Rate limit
    if not checkRateLimit(player, "CompleteTutorial", 1) then
        return
    end

    -- Execute
    local DataService = require(Services.DataService)
    local playerData = DataService:GetPlayerData(player)

    if playerData then
        -- Mark tutorial as completed
        playerData.tutorialCompleted = true

        -- Grant tutorial completion reward
        DataService:UpdateResources(player, { gems = 50 } :: any)

        Events.ServerResponse:FireClient(player, "CompleteTutorial", {
            success = true,
            reward = { gems = 50 }
        })
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- QUEST SERVICE HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

local MAX_QUEST_ID_LENGTH = 50

-- Get daily quests (RemoteFunction for synchronous data)
Events.GetDailyQuests.OnServerInvoke = function(player)
    -- Rate limit
    if not checkRateLimit(player, "GetDailyQuests", 5) then
        return nil
    end

    -- Execute
    local QuestService = require(Services.QuestService)
    return QuestService:GetDailyQuests(player)
end

-- Get achievements (RemoteFunction for synchronous data)
Events.GetAchievements.OnServerInvoke = function(player)
    -- Rate limit
    if not checkRateLimit(player, "GetAchievements", 5) then
        return nil
    end

    -- Execute
    local QuestService = require(Services.QuestService)
    return QuestService:GetAchievements(player)
end

-- Claim quest reward handler
Events.ClaimQuestReward.OnServerEvent:Connect(function(player, questId)
    -- Rate limit
    if not checkRateLimit(player, "ClaimQuestReward", 10) then
        Events.ServerResponse:FireClient(player, "ClaimQuestReward", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if not validateStringInput(questId, MAX_QUEST_ID_LENGTH) then return end

    -- Execute
    local QuestService = require(Services.QuestService)
    local result = QuestService:ClaimReward(player, questId)

    Events.ServerResponse:FireClient(player, "ClaimQuestReward", result)
end)

-- Connect QuestService signals to broadcast to clients
task.defer(function()
    local QuestService = require(Services.QuestService)

    -- Broadcast quest completion
    QuestService.QuestCompleted:Connect(function(player, quest)
        Events.QuestCompleted:FireClient(player, {
            questId = quest.id,
            title = quest.title,
            reward = quest.reward,
        })
    end)

    -- Broadcast quest progress updates
    QuestService.QuestProgressUpdated:Connect(function(player, questId, progress, target)
        Events.QuestProgress:FireClient(player, {
            questId = questId,
            progress = progress,
            target = target,
        })
    end)

    -- Broadcast achievement unlock
    QuestService.AchievementUnlocked:Connect(function(player, achievement)
        Events.QuestCompleted:FireClient(player, {
            questId = achievement.id,
            title = achievement.title,
            reward = achievement.reward,
            isAchievement = true,
        })
    end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- DAILY REWARD SERVICE HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Get daily reward info (RemoteFunction for synchronous data)
Events.GetDailyRewardInfo.OnServerInvoke = function(player)
    -- Rate limit
    if not checkRateLimit(player, "GetDailyRewardInfo", 5) then
        return nil
    end

    -- Execute
    local DailyRewardService = require(Services.DailyRewardService)
    return DailyRewardService:GetRewardInfo(player)
end

-- Claim daily reward handler
Events.ClaimDailyReward.OnServerEvent:Connect(function(player)
    -- Rate limit
    if not checkRateLimit(player, "ClaimDailyReward", 2) then
        Events.ServerResponse:FireClient(player, "ClaimDailyReward", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Execute
    local DailyRewardService = require(Services.DailyRewardService)
    local result = DailyRewardService:ClaimReward(player)

    if result.success then
        Events.DailyRewardClaimed:FireClient(player, {
            reward = result.reward,
            streakBonus = result.streakBonus,
            newStreak = result.newStreak,
        })
    end

    Events.ServerResponse:FireClient(player, "ClaimDailyReward", result)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- SPELL SERVICE HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

local MAX_SPELL_TYPE_LENGTH = 30

-- Brew spell handler
Events.BrewSpell.OnServerEvent:Connect(function(player, spellType)
    -- Rate limit
    if not checkRateLimit(player, "BrewSpell", 10) then
        Events.ServerResponse:FireClient(player, "BrewSpell", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if not validateStringInput(spellType, MAX_SPELL_TYPE_LENGTH) then return end

    -- Execute
    local SpellService = require(Services.SpellService)
    local result = SpellService:BrewSpell(player, spellType)

    Events.ServerResponse:FireClient(player, "BrewSpell", result)
end)

-- Cancel spell brewing handler
Events.CancelSpellBrewing.OnServerEvent:Connect(function(player, queueIndex)
    -- Rate limit
    if not checkRateLimit(player, "CancelSpellBrewing", 5) then
        Events.ServerResponse:FireClient(player, "CancelSpellBrewing", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if typeof(queueIndex) ~= "number" then return end
    queueIndex = math.floor(queueIndex)
    if queueIndex < 1 or queueIndex > 20 then return end

    -- Execute
    local SpellService = require(Services.SpellService)
    local result = SpellService:CancelBrewing(player, queueIndex)

    Events.ServerResponse:FireClient(player, "CancelSpellBrewing", result)
end)

-- Get spell queue (RemoteFunction for synchronous data)
Events.GetSpellQueue.OnServerInvoke = function(player)
    -- Rate limit
    if not checkRateLimit(player, "GetSpellQueue", 5) then
        return nil
    end

    -- Execute
    local SpellService = require(Services.SpellService)
    return SpellService:GetBrewingQueue(player)
end

-- Connect SpellService signals to broadcast to clients
task.defer(function()
    local SpellService = require(Services.SpellService)

    -- Broadcast spell brewing complete
    SpellService.BrewingComplete:Connect(function(player, spellType)
        Events.SpellBrewingComplete:FireClient(player, {
            spellType = spellType,
        })
    end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- LEADERBOARD SERVICE HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Get global leaderboard (RemoteFunction for synchronous data)
Events.GetLeaderboard.OnServerInvoke = function(player, count)
    -- Rate limit
    if not checkRateLimit(player, "GetLeaderboard", 3) then
        return nil
    end

    -- Validate count
    if typeof(count) ~= "number" then count = 100 end
    count = math.clamp(math.floor(count), 1, 200)

    -- Execute
    local LeaderboardService = require(Services.LeaderboardService)
    return LeaderboardService:GetTopPlayers(count)
end

-- Get player rank (RemoteFunction for synchronous data)
Events.GetPlayerRank.OnServerInvoke = function(player)
    -- Rate limit
    if not checkRateLimit(player, "GetPlayerRank", 5) then
        return nil
    end

    -- Execute
    local LeaderboardService = require(Services.LeaderboardService)
    return LeaderboardService:GetPlayerRank(player)
end

-- Get leaderboard info (RemoteFunction for synchronous data)
Events.GetLeaderboardInfo.OnServerInvoke = function(player)
    -- Rate limit
    if not checkRateLimit(player, "GetLeaderboardInfo", 5) then
        return nil
    end

    -- Execute
    local LeaderboardService = require(Services.LeaderboardService)
    return LeaderboardService:GetLeaderboardInfo(player)
end

-- Connect LeaderboardService signals to broadcast to clients
task.defer(function()
    local LeaderboardService = require(Services.LeaderboardService)

    -- Broadcast league changes
    LeaderboardService.LeagueChanged:Connect(function(player, oldLeague, newLeague)
        Events.LeagueChanged:FireClient(player, {
            oldLeague = oldLeague,
            newLeague = newLeague,
        })
    end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- BATTLE STATE BROADCASTS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Connect CombatService signals to broadcast battle state to clients
task.defer(function()
    local CombatService = require(Services.CombatService)
    local Players = game:GetService("Players")

    -- Broadcast battle tick updates to attacker
    CombatService.BattleTick:Connect(function(battleId, battleState)
        local attacker = Players:GetPlayerByUserId(battleState.attackerId)
        if attacker then
            -- Send minimal state for rendering (don't send full internal state)
            local clientState = {
                battleId = battleId,
                phase = battleState.phase,
                timeRemaining = math.max(0, battleState.endsAt - os.time()),
                destruction = battleState.destruction,
                starsEarned = battleState.starsEarned,
                troops = battleState.troops,
                spells = battleState.spells,
            }
            Events.BattleTick:FireClient(attacker, clientState)
        end
    end)

    -- Broadcast battle end to attacker
    CombatService.BattleEnded:Connect(function(battleId, result)
        local attacker = Players:GetPlayerByUserId(result.attackerId or 0)
        if attacker then
            Events.BattleEnded:FireClient(attacker, result)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════════════════════════

-- Cleanup rate limiter on player leave
game:GetService("Players").PlayerRemoving:Connect(function(player)
    RateLimiter[player.UserId] = nil
end)

print("Battle Tycoon: Conquest - Server Ready!")
