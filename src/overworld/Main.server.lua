--!strict
--[[
    Main.server.lua - Battle Tycoon: Conquest - Overworld Server Entry Point

    This script initializes all overworld services, creates the networking
    infrastructure, and handles player connections for the overworld place.

    The overworld is where players walk around and see other players' bases
    before teleporting to their village or attacking others.
]]

print("========================================")
print("BATTLE TYCOON: CONQUEST - OVERWORLD SERVER")
print("========================================")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 1: Wait for Shared modules to be available
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Waiting for Shared modules...")

repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Shared")

print("[OVERWORLD] Shared modules found")

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 2: Create Events folder with RemoteEvents and RemoteFunctions
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Creating Events folder...")

local Events = Instance.new("Folder")
Events.Name = "Events"
Events.Parent = ReplicatedStorage

-- Helper functions
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

-- Player data sync
local SyncPlayerData = createRemoteEvent("SyncPlayerData")
local ServerResponse = createRemoteEvent("ServerResponse")

-- Position updates
local UpdatePosition = createRemoteEvent("UpdatePosition")
local PositionSync = createRemoteEvent("PositionSync")

-- Base management
local GetNearbyBases = createRemoteFunction("GetNearbyBases")
local GetBaseData = createRemoteFunction("GetBaseData")
local SpawnBase = createRemoteEvent("SpawnBase")
local RemoveBase = createRemoteEvent("RemoveBase")
local UpdateBase = createRemoteEvent("UpdateBase")

-- Interaction events
local ApproachBase = createRemoteEvent("ApproachBase")
local LeaveBase = createRemoteEvent("LeaveBase")
local InteractWithBase = createRemoteEvent("InteractWithBase")
local BaseInteractionResult = createRemoteEvent("BaseInteractionResult")

-- Teleport events
local RequestTeleportToVillage = createRemoteEvent("RequestTeleportToVillage")
local RequestTeleportToBattle = createRemoteEvent("RequestTeleportToBattle")
local TeleportStarted = createRemoteEvent("TeleportStarted")
local TeleportFailed = createRemoteEvent("TeleportFailed")

-- Matchmaking events
local RequestMatchmaking = createRemoteEvent("RequestMatchmaking")
local MatchmakingResult = createRemoteEvent("MatchmakingResult")
local ConfirmMatchmaking = createRemoteEvent("ConfirmMatchmaking")

-- Battle events
local RequestSurrender = createRemoteEvent("RequestSurrender")
local RequestRevenge = createRemoteEvent("RequestRevenge")

-- Goblin camp events
local AttackGoblinCamp = createRemoteEvent("AttackGoblinCamp")
local GetGoblinCamps = createRemoteFunction("GetGoblinCamps")

-- Resource node events
local CollectResourceNode = createRemoteEvent("CollectResourceNode")
local GetResourceNodes = createRemoteFunction("GetResourceNodes")

-- Trade events
local ProposeTrade = createRemoteEvent("ProposeTrade")
local TradeProposal = createRemoteEvent("TradeProposal")
local RespondToTrade = createRemoteEvent("RespondToTrade")
local TradeResult = createRemoteEvent("TradeResult")
local CancelTrade = createRemoteEvent("CancelTrade")

-- Visit base events
local RequestVisitBase = createRemoteEvent("RequestVisitBase")

-- UI data
local GetOwnBaseData = createRemoteFunction("GetOwnBaseData")
local GetPlayerResources = createRemoteFunction("GetPlayerResources")
local GetDefenseLog = createRemoteFunction("GetDefenseLog")
local GetUnreadAttacks = createRemoteFunction("GetUnreadAttacks")
local GetShieldStatus = createRemoteFunction("GetShieldStatus")

print("[OVERWORLD] Events folder created")

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 3: Load and initialize services
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Loading services...")

local ServicesFolder = ServerScriptService:FindFirstChild("Services")
if not ServicesFolder then
    warn("[OVERWORLD] Services folder not found!")
    return
end

-- Load services with error handling
local function loadService(name: string)
    local module = ServicesFolder:FindFirstChild(name)
    if not module then
        warn(string.format("[OVERWORLD] Service not found: %s", name))
        return nil
    end

    local success, result = pcall(function()
        return require(module)
    end)

    if success then
        print(string.format("[OVERWORLD] Loaded: %s", name))
        return result
    else
        warn(string.format("[OVERWORLD] Failed to load %s: %s", name, tostring(result)))
        return nil
    end
end

-- Load DataService first (other services depend on it for player resources)
local DataService = loadService("DataService")

-- Load overworld services
local OverworldService = loadService("OverworldService")
local TeleportManager = loadService("TeleportManager")
local BattleArenaService = loadService("BattleArenaService")
local MatchmakingService = loadService("MatchmakingService")
local GoblinCampService = loadService("GoblinCampService")
local ResourceNodeService = loadService("ResourceNodeService")
local TradeService = loadService("TradeService")

-- Load shared module references
local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 4: Initialize services
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Initializing services...")

local function initService(service, name: string)
    if service and service.Init then
        local success, err = pcall(function()
            service:Init()
        end)
        if success then
            print(string.format("[OVERWORLD] Initialized: %s", name))
        else
            warn(string.format("[OVERWORLD] Failed to init %s: %s", name, tostring(err)))
        end
    end
end

initService(DataService, "DataService") -- Must be first: loads player data, sets up auto-save
initService(TeleportManager, "TeleportManager")
initService(OverworldService, "OverworldService")
initService(MatchmakingService, "MatchmakingService")
initService(BattleArenaService, "BattleArenaService")
initService(GoblinCampService, "GoblinCampService")
initService(ResourceNodeService, "ResourceNodeService")
initService(TradeService, "TradeService")

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 5: Build the overworld environment
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Building environment...")

local WorldBuilder = require(ServerScriptService:WaitForChild("WorldBuilder"))
local buildSuccess, buildErr = pcall(function()
    WorldBuilder.Build()
end)

if buildSuccess then
    print("[OVERWORLD] Environment built successfully")
else
    warn("[OVERWORLD] Failed to build environment:", tostring(buildErr))
end

local MiniBaseBuilder = require(ServerScriptService:WaitForChild("MiniBaseBuilder"))

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 6: Connect service signals
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Connecting signals...")

if OverworldService then
    -- When a player enters, spawn their base
    OverworldService.PlayerEnteredOverworld:Connect(function(player, state)
        local baseData = OverworldService:GetOwnBaseData(player)
        if baseData then
            MiniBaseBuilder.Create(baseData)
            -- Notify all clients about new base
            SpawnBase:FireAllClients(baseData)
        end
    end)

    -- When a player leaves, remove their base
    OverworldService.PlayerLeftOverworld:Connect(function(player, state)
        MiniBaseBuilder.Remove(player.UserId)
        RemoveBase:FireAllClients(player.UserId)
    end)
end

if TeleportManager then
    TeleportManager.TeleportStarted:Connect(function(player, destination)
        TeleportStarted:FireClient(player, destination)
    end)

    TeleportManager.TeleportFailed:Connect(function(player, destination, errorMsg)
        TeleportFailed:FireClient(player, destination, errorMsg)
    end)
end

if TradeService then
    TradeService.TradeCancelled:Connect(function(trade, reason)
        -- Notify both players when a trade is cancelled/expired/declined
        local proposer = Players:GetPlayerByUserId(trade.proposerUserId)
        local target = Players:GetPlayerByUserId(trade.targetUserId)
        if proposer then
            TradeResult:FireClient(proposer, { status = reason, tradeId = trade.id })
        end
        if target then
            TradeResult:FireClient(target, { status = reason, tradeId = trade.id })
        end
    end)

    TradeService.TradeCompleted:Connect(function(trade)
        -- Notify both players when a trade completes
        local proposer = Players:GetPlayerByUserId(trade.proposerUserId)
        local target = Players:GetPlayerByUserId(trade.targetUserId)
        if proposer then
            TradeResult:FireClient(proposer, { status = "accepted", tradeId = trade.id })
        end
        if target then
            TradeResult:FireClient(target, { status = "accepted", tradeId = trade.id })
        end
    end)
end

-- Track players who are teleporting (village/visit) so their base isn't destroyed
local _teleportingPlayers: {[number]: boolean} = {}

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 7: Connect event handlers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Connecting event handlers...")

-- Helper for safe event connections
local function connectEvent(event: RemoteEvent, handler: (Player, ...any) -> ())
    event.OnServerEvent:Connect(function(player, ...)
        local success, err = pcall(handler, player, ...)
        if not success then
            warn(string.format("[OVERWORLD] Event handler error: %s", tostring(err)))
            ServerResponse:FireClient(player, event.Name, { success = false, error = "Server error" })
        end
    end)
end

-- Position updates from clients
connectEvent(UpdatePosition, function(player, position)
    if OverworldService then
        -- Validate position is Vector3
        if typeof(position) ~= "Vector3" then
            return
        end

        -- Validate position is in bounds
        if not OverworldConfig.IsInBounds(position.X, position.Z) then
            return
        end

        OverworldService:UpdatePlayerPosition(player, position)
    end
end)

-- Get nearby bases
GetNearbyBases.OnServerInvoke = function(player, centerPos, maxCount)
    if OverworldService then
        return OverworldService:GetNearbyBases(player, centerPos, maxCount)
    end
    return {}
end

-- Get specific base data
GetBaseData.OnServerInvoke = function(player, targetUserId)
    if OverworldService then
        -- Validate userId is number
        if typeof(targetUserId) ~= "number" then
            return nil
        end

        return OverworldService:GetBaseData(targetUserId, player)
    end
    return nil
end

-- Get own base data
GetOwnBaseData.OnServerInvoke = function(player)
    if OverworldService then
        return OverworldService:GetOwnBaseData(player)
    end
    return nil
end

-- Get player resources (for HUD)
GetPlayerResources.OnServerInvoke = function(player)
    if DataService and DataService.GetPlayerData then
        local data = DataService:GetPlayerData(player)
        if data and data.resources then
            return {
                gold = data.resources.gold or 0,
                wood = data.resources.wood or 0,
                food = data.resources.food or 0,
            }
        end
    end

    -- Fallback if DataService unavailable or player data not loaded yet
    return {
        gold = 0,
        wood = 0,
        food = 0,
    }
end

-- Get player defense log
GetDefenseLog.OnServerInvoke = function(player)
    if DataService and DataService.GetPlayerData then
        local data = DataService:GetPlayerData(player)
        if data and data.defenseLog then
            return data.defenseLog
        end
    end
    return {}
end

-- Get unread attacks (attacks since last login) and update lastLoginTime
GetUnreadAttacks.OnServerInvoke = function(player)
    if DataService and DataService.GetPlayerData then
        local data = DataService:GetPlayerData(player)
        if data then
            local lastLogin = data.lastLoginTime or 0
            local unreadAttacks = {}

            if data.defenseLog then
                for _, entry in data.defenseLog do
                    if (entry.timestamp or 0) > lastLogin then
                        table.insert(unreadAttacks, entry)
                    end
                end
            end

            -- Update lastLoginTime to current time
            data.lastLoginTime = os.time()

            return unreadAttacks
        end
    end
    return {}
end

-- Get shield status (for Shield Timer HUD)
GetShieldStatus.OnServerInvoke = function(player)
    if DataService and DataService.GetPlayerData then
        local data = DataService:GetPlayerData(player)
        if data and data.shield then
            local shield = data.shield
            -- Shield can be a table with active + expiresAt fields
            if typeof(shield) == "table" then
                local isActive = shield.active == true
                local expiresAt = shield.expiresAt or 0

                -- Check if shield has expired
                if isActive and expiresAt > 0 and os.time() >= expiresAt then
                    -- Shield expired, deactivate it
                    shield.active = false
                    isActive = false
                end

                if isActive and expiresAt > os.time() then
                    return {
                        active = true,
                        expiresAt = expiresAt,
                        remainingSeconds = expiresAt - os.time(),
                    }
                end
            end
        end
    end
    return { active = false }
end

-- Surrender: client requests to surrender the current battle
connectEvent(RequestSurrender, function(player, data)
    if not BattleArenaService then return end

    -- Validate player is in a battle
    if not BattleArenaService:IsPlayerInBattle(player) then return end

    local battleId = BattleArenaService:GetPlayerBattleId(player)
    if not battleId then return end

    -- Validate battleId from client matches (if provided)
    if data and typeof(data) == "table" and data.battleId then
        if data.battleId ~= battleId then return end
    end

    -- End the battle via CombatService
    local CombatServiceModule = ServerScriptService:FindFirstChild("Services")
        and ServerScriptService.Services:FindFirstChild("CombatService")
    if CombatServiceModule then
        local success, CombatService = pcall(require, CombatServiceModule)
        if success and CombatService and CombatService.EndBattle then
            CombatService:EndBattle(battleId)
        end
    end

    print(string.format("[OVERWORLD] Player %s surrendered battle %s", player.Name, battleId))
end)

-- Base interaction (approach/leave)
connectEvent(ApproachBase, function(player, targetUserId)
    if OverworldService then
        if typeof(targetUserId) ~= "number" then return end

        local baseData = OverworldService:GetBaseData(targetUserId, player)
        if baseData then
            BaseInteractionResult:FireClient(player, "approach", baseData)
        end
    end
end)

connectEvent(LeaveBase, function(player, targetUserId)
    BaseInteractionResult:FireClient(player, "leave", nil)
end)

-- Teleport to village request
connectEvent(RequestTeleportToVillage, function(player)
    if TeleportManager and OverworldService then
        local canEnter, err = OverworldService:CanEnterVillage(player)

        if not canEnter then
            ServerResponse:FireClient(player, "TeleportToVillage", { success = false, error = err })
            return
        end

        local state = OverworldService:GetPlayerState(player)
        local currentPos = state and state.position or Vector3.new(500, 0, 500)

        -- Mark as teleporting so PlayerRemoving keeps their base
        _teleportingPlayers[player.UserId] = true

        local success, teleportErr = TeleportManager:TeleportToVillage(player, currentPos)

        if not success then
            _teleportingPlayers[player.UserId] = nil -- Clear on failure
            ServerResponse:FireClient(player, "TeleportToVillage", { success = false, error = teleportErr })
        end
    end
end)

-- Teleport to battle request (LEGACY - bypassed)
-- Battle flow now uses BattleArenaService's RequestBattle RemoteEvent for
-- same-server instanced arenas instead of cross-place teleports.
-- This handler is kept for backwards compatibility but no longer triggers teleports.
connectEvent(RequestTeleportToBattle, function(player, targetUserId)
    -- Redirect to BattleArenaService if available
    if BattleArenaService then
        print(string.format("[OVERWORLD] Legacy RequestTeleportToBattle from %s redirected to BattleArenaService", player.Name))
        -- BattleArenaService handles battles via its own RequestBattle RemoteEvent.
        -- If client still fires the old event, inform them to use RequestBattle instead.
        ServerResponse:FireClient(player, "TeleportToBattle", {
            success = false,
            error = "USE_REQUEST_BATTLE",
        })
        return
    end

    -- Fallback to old teleport flow if BattleArenaService is not loaded
    if TeleportManager and OverworldService then
        if typeof(targetUserId) ~= "number" then
            ServerResponse:FireClient(player, "TeleportToBattle", { success = false, error = "INVALID_TARGET" })
            return
        end

        local canAttack, err = OverworldService:CanStartAttack(player, targetUserId)

        if not canAttack then
            ServerResponse:FireClient(player, "TeleportToBattle", { success = false, error = err })
            return
        end

        local state = OverworldService:GetPlayerState(player)
        local currentPos = state and state.position or Vector3.new(500, 0, 500)

        local success, teleportErr = TeleportManager:TeleportToBattle(player, targetUserId, currentPos)

        if not success then
            ServerResponse:FireClient(player, "TeleportToBattle", { success = false, error = teleportErr })
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 7.5: Matchmaking handlers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Connecting matchmaking handlers...")

-- Track pending matchmaking results per player:
-- [userId] = { opponent data from FindOpponent, timestamp, searchCount }
local _pendingMatches: {[number]: any} = {}
local _matchmakingRateLimit: {[number]: number} = {} -- [userId] = lastRequestTime
local MATCHMAKING_RATE_LIMIT = 1 -- seconds between requests
local _revengeRateLimit: {[number]: number} = {} -- [userId] = lastRequestTime (declared here, used in revenge handler below)

-- Request matchmaking: client asks server to find an opponent
connectEvent(RequestMatchmaking, function(player)
    if not MatchmakingService then
        MatchmakingResult:FireClient(player, { success = false, error = "SERVICE_UNAVAILABLE" })
        return
    end

    -- Rate limit
    local now = os.clock()
    local lastRequest = _matchmakingRateLimit[player.UserId] or 0
    if now - lastRequest < MATCHMAKING_RATE_LIMIT then
        MatchmakingResult:FireClient(player, { success = false, error = "RATE_LIMITED" })
        return
    end
    _matchmakingRateLimit[player.UserId] = now

    -- Check if player is already in a battle
    if BattleArenaService and BattleArenaService:IsPlayerInBattle(player) then
        MatchmakingResult:FireClient(player, { success = false, error = "ALREADY_IN_BATTLE" })
        return
    end

    -- Get search count from pending match data (for skip cost tracking)
    local pending = _pendingMatches[player.UserId]
    local searchCount = if pending then pending.searchCount + 1 else 1

    -- Find or skip to next opponent
    local opponent, err
    if searchCount > 1 then
        opponent, err = MatchmakingService:NextOpponent(player, searchCount)
    else
        opponent, err = MatchmakingService:FindOpponent(player)
    end

    if not opponent then
        MatchmakingResult:FireClient(player, { success = false, error = err or "NO_OPPONENT_FOUND" })
        return
    end

    -- Calculate available loot
    local lootAvailable = {
        gold = 0,
        wood = 0,
        food = 0,
    }
    if opponent.resources then
        -- Loot formula: attacker can steal a percentage of defender resources
        local lootPercent = 0.85 -- 85% of stored resources
        lootAvailable.gold = math.floor((opponent.resources.gold or 0) * lootPercent)
        lootAvailable.wood = math.floor((opponent.resources.wood or 0) * lootPercent)
        lootAvailable.food = math.floor((opponent.resources.food or 0) * lootPercent)
    end

    -- Calculate next skip cost
    local nextSkipCost = MatchmakingService:GetSkipCost(searchCount + 1)

    -- Store pending match for validation when client confirms
    _pendingMatches[player.UserId] = {
        opponent = opponent,
        timestamp = os.time(),
        searchCount = searchCount,
    }

    -- Send result to client
    MatchmakingResult:FireClient(player, {
        success = true,
        target = {
            userId = opponent.userId,
            username = opponent.username,
            townHallLevel = opponent.townHallLevel or 1,
            trophies = opponent.trophies or 0,
            lootAvailable = lootAvailable,
        },
        skipCost = nextSkipCost,
        searchCount = searchCount,
    })

    print(string.format("[OVERWORLD] Matchmaking result for %s: found %s (search #%d)",
        player.Name, opponent.username, searchCount))
end)

-- Confirm matchmaking: client wants to attack the matched opponent
connectEvent(ConfirmMatchmaking, function(player, targetUserId)
    -- Type validation
    if typeof(targetUserId) ~= "number" then return end

    if not BattleArenaService then
        ServerResponse:FireClient(player, "ConfirmMatchmaking", { success = false, error = "SERVICE_UNAVAILABLE" })
        return
    end

    -- Check if player is already in a battle
    if BattleArenaService:IsPlayerInBattle(player) then
        ServerResponse:FireClient(player, "ConfirmMatchmaking", { success = false, error = "ALREADY_IN_BATTLE" })
        return
    end

    -- Validate the target was actually matched to this player
    local pending = _pendingMatches[player.UserId]
    if not pending or not pending.opponent then
        ServerResponse:FireClient(player, "ConfirmMatchmaking", { success = false, error = "NO_PENDING_MATCH" })
        return
    end

    if pending.opponent.userId ~= targetUserId then
        ServerResponse:FireClient(player, "ConfirmMatchmaking", { success = false, error = "MATCH_MISMATCH" })
        return
    end

    -- Check match freshness (expire after 60 seconds)
    if os.time() - pending.timestamp > 60 then
        _pendingMatches[player.UserId] = nil
        ServerResponse:FireClient(player, "ConfirmMatchmaking", { success = false, error = "MATCH_EXPIRED" })
        return
    end

    -- Clear pending match
    _pendingMatches[player.UserId] = nil

    -- Create the battle arena
    -- BattleArenaService:CreateArena handles both real players and AI opponents.
    -- For AI opponents (negative userId), CreateArena loads defender data via
    -- DataService or CombatService which supports AI battle data.
    local result = BattleArenaService:CreateArena(player, targetUserId)
    if result.success then
        ServerResponse:FireClient(player, "ConfirmMatchmaking", { success = true, battleId = result.battleId })
    else
        ServerResponse:FireClient(player, "ConfirmMatchmaking", { success = false, error = result.error })
    end

    print(string.format("[OVERWORLD] ConfirmMatchmaking from %s for target %d", player.Name, targetUserId))
end)

-- Clean up pending matches when player leaves
Players.PlayerRemoving:Connect(function(player)
    _pendingMatches[player.UserId] = nil
    _matchmakingRateLimit[player.UserId] = nil
    _revengeRateLimit[player.UserId] = nil
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 7.6: Revenge attack handler
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Connecting revenge handler...")

local REVENGE_RATE_LIMIT = 5 -- seconds between revenge requests

connectEvent(RequestRevenge, function(player, data)
    if not BattleArenaService then
        ServerResponse:FireClient(player, "RequestRevenge", { success = false, error = "SERVICE_UNAVAILABLE" })
        return
    end

    -- 1. RATE LIMIT (1 request per 5 seconds)
    local now = os.clock()
    local lastRequest = _revengeRateLimit[player.UserId] or 0
    if now - lastRequest < REVENGE_RATE_LIMIT then
        ServerResponse:FireClient(player, "RequestRevenge", { success = false, error = "RATE_LIMITED" })
        return
    end
    _revengeRateLimit[player.UserId] = now

    -- 2. TYPE VALIDATION
    if typeof(data) ~= "table" then
        ServerResponse:FireClient(player, "RequestRevenge", { success = false, error = "INVALID_DATA" })
        return
    end

    local targetUserId = data.targetUserId
    if typeof(targetUserId) ~= "number" then
        ServerResponse:FireClient(player, "RequestRevenge", { success = false, error = "INVALID_TARGET" })
        return
    end

    -- 3. CHECK PLAYER IS NOT ALREADY IN BATTLE
    if BattleArenaService:IsPlayerInBattle(player) then
        ServerResponse:FireClient(player, "RequestRevenge", { success = false, error = "ALREADY_IN_BATTLE" })
        return
    end

    -- 4. VERIFY PLAYER WAS ATTACKED BY THIS TARGET (via defenseLog)
    if not DataService then
        ServerResponse:FireClient(player, "RequestRevenge", { success = false, error = "SERVICE_UNAVAILABLE" })
        return
    end

    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        ServerResponse:FireClient(player, "RequestRevenge", { success = false, error = "NO_PLAYER_DATA" })
        return
    end

    -- Check defenseLog for an entry where this target attacked the player
    local foundValidRevenge = false
    if playerData.defenseLog then
        for _, entry in playerData.defenseLog do
            if entry.attackerId == targetUserId and entry.canRevenge then
                foundValidRevenge = true
                break
            end
        end
    end

    if not foundValidRevenge then
        ServerResponse:FireClient(player, "RequestRevenge", { success = false, error = "NO_REVENGE_AVAILABLE" })
        return
    end

    -- 5. CREATE BATTLE ARENA WITH isRevenge FLAG
    -- Revenge attacks bypass shields (handled by CombatService via isRevenge option)
    local result = BattleArenaService:CreateArena(player, targetUserId, { isRevenge = true })

    if result.success then
        -- Mark all revenge entries for this target as used (canRevenge = false)
        if playerData.defenseLog then
            for _, entry in playerData.defenseLog do
                if entry.attackerId == targetUserId then
                    entry.canRevenge = false
                end
            end
        end

        -- Also mark revengeList entries as used
        if playerData.revengeList then
            for _, entry in playerData.revengeList do
                if entry.attackerId == targetUserId then
                    entry.used = true
                end
            end
        end

        ServerResponse:FireClient(player, "RequestRevenge", { success = true, battleId = result.battleId })
        print(string.format("[OVERWORLD] Revenge battle started: %s vs %d (battleId=%s)", player.Name, targetUserId, result.battleId))
    else
        ServerResponse:FireClient(player, "RequestRevenge", { success = false, error = result.error })
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 7.7: Goblin camp handlers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Connecting goblin camp handlers...")

-- GetGoblinCamps: client asks for active camps with position, name, difficulty, loot preview
GetGoblinCamps.OnServerInvoke = function(player)
    if GoblinCampService then
        return GoblinCampService:GetActiveCamps()
    end
    return {}
end

-- AttackGoblinCamp: client requests to attack a specific goblin camp
connectEvent(AttackGoblinCamp, function(player, campId)
    if not GoblinCampService then
        ServerResponse:FireClient(player, "AttackGoblinCamp", { success = false, error = "SERVICE_UNAVAILABLE" })
        return
    end

    -- Type validation
    if typeof(campId) ~= "string" then
        ServerResponse:FireClient(player, "AttackGoblinCamp", { success = false, error = "INVALID_CAMP_ID" })
        return
    end

    -- Check if player is already in a battle
    if BattleArenaService and BattleArenaService:IsPlayerInBattle(player) then
        ServerResponse:FireClient(player, "AttackGoblinCamp", { success = false, error = "ALREADY_IN_BATTLE" })
        return
    end

    -- Start the camp attack
    local success, err = GoblinCampService:StartCampAttack(player, campId)
    if success then
        ServerResponse:FireClient(player, "AttackGoblinCamp", { success = true })
    else
        ServerResponse:FireClient(player, "AttackGoblinCamp", { success = false, error = err or "ATTACK_FAILED" })
    end

    print(string.format("[OVERWORLD] AttackGoblinCamp from %s for camp %s: %s",
        player.Name, tostring(campId), success and "success" or (err or "failed")))
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 7.8: Resource node handlers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Connecting resource node handlers...")

-- GetResourceNodes: client asks for nodes available to this player
GetResourceNodes.OnServerInvoke = function(player)
    if ResourceNodeService then
        return ResourceNodeService:GetActiveNodes(player)
    end
    return {}
end

-- CollectResourceNode: client requests to collect a specific node
connectEvent(CollectResourceNode, function(player, nodeId)
    if not ResourceNodeService then
        ServerResponse:FireClient(player, "CollectResourceNode", { success = false, error = "SERVICE_UNAVAILABLE" })
        return
    end

    -- Type validation
    if typeof(nodeId) ~= "string" then
        ServerResponse:FireClient(player, "CollectResourceNode", { success = false, error = "INVALID_NODE_ID" })
        return
    end

    -- Attempt collection
    local success, resourceType, amount = ResourceNodeService:CollectNode(player, nodeId)
    if success then
        ServerResponse:FireClient(player, "CollectResourceNode", {
            success = true,
            nodeId = nodeId,
            resourceType = resourceType,
            amount = amount,
        })
    else
        ServerResponse:FireClient(player, "CollectResourceNode", {
            success = false,
            error = resourceType or "COLLECT_FAILED", -- resourceType holds error code on failure
        })
    end

    print(string.format("[OVERWORLD] CollectResourceNode from %s for node %s: %s",
        player.Name, tostring(nodeId), success and ("+" .. tostring(amount) .. " " .. tostring(resourceType)) or (resourceType or "failed")))
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 7.9: Trading handlers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Connecting trade handlers...")

connectEvent(ProposeTrade, function(player, data)
    if not TradeService then return end

    -- Validate data is a table
    if typeof(data) ~= "table" then return end
    if typeof(data.targetUserId) ~= "number" then return end
    if typeof(data.offering) ~= "table" then return end
    if typeof(data.requesting) ~= "table" then return end

    -- Sanitize resource values to non-negative integers
    local offering = {
        gold = math.max(0, math.floor(tonumber(data.offering.gold) or 0)),
        wood = math.max(0, math.floor(tonumber(data.offering.wood) or 0)),
        food = math.max(0, math.floor(tonumber(data.offering.food) or 0)),
    }
    local requesting = {
        gold = math.max(0, math.floor(tonumber(data.requesting.gold) or 0)),
        wood = math.max(0, math.floor(tonumber(data.requesting.wood) or 0)),
        food = math.max(0, math.floor(tonumber(data.requesting.food) or 0)),
    }

    local success, tradeIdOrErr = TradeService:ProposeTrade(player, data.targetUserId, offering, requesting)

    if success then
        -- Notify the target player of the incoming proposal
        local targetPlayer = Players:GetPlayerByUserId(data.targetUserId)
        if targetPlayer then
            local trade = TradeService:GetActiveTrade(player)
            if trade then
                TradeProposal:FireClient(targetPlayer, {
                    tradeId = trade.id,
                    proposerName = player.Name,
                    proposerUserId = player.UserId,
                    offering = trade.offering,
                    requesting = trade.requesting,
                    expiresAt = trade.expiresAt,
                })
            end
        end
        -- Confirm to proposer
        TradeResult:FireClient(player, { status = "proposed", tradeId = tradeIdOrErr })
    else
        TradeResult:FireClient(player, { status = "error", error = tradeIdOrErr })
    end
end)

connectEvent(RespondToTrade, function(player, data)
    if not TradeService then return end
    if typeof(data) ~= "table" then return end
    if typeof(data.tradeId) ~= "string" then return end
    if typeof(data.accepted) ~= "boolean" then return end

    -- Get the trade state before responding (for notification purposes)
    local trade = TradeService:GetTradeById(data.tradeId)
    local proposerUserId = trade and trade.proposerUserId or 0

    local success, err = TradeService:RespondToTrade(player, data.tradeId, data.accepted)

    if success then
        -- TradeService signals (TradeCompleted / TradeCancelled) handle notifications
        -- to both players via the signal connections in STEP 6.
        -- We still send immediate feedback to the responder.
        if data.accepted then
            TradeResult:FireClient(player, { status = "accepted", tradeId = data.tradeId })
        else
            TradeResult:FireClient(player, { status = "declined", tradeId = data.tradeId })
        end
    else
        TradeResult:FireClient(player, { status = "error", error = err })
    end
end)

connectEvent(CancelTrade, function(player, data)
    if not TradeService then return end
    if typeof(data) ~= "table" then return end
    if typeof(data.tradeId) ~= "string" then return end

    local success, err = TradeService:CancelTrade(player, data.tradeId)

    if success then
        -- TradeService.TradeCancelled signal handles notifications to both players
        TradeResult:FireClient(player, { status = "cancelled", tradeId = data.tradeId })
    else
        TradeResult:FireClient(player, { status = "error", error = err })
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 7.10: Visit base handlers (teleports visitor to target's village)
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Connecting visit base handlers...")

local _visitRateLimit: {[number]: number} = {} -- [userId] = lastRequestTime
local VISIT_RATE_LIMIT = 3 -- seconds between visit requests

connectEvent(RequestVisitBase, function(player, data)
    if typeof(data) ~= "table" then return end
    if typeof(data.targetUserId) ~= "number" then return end

    -- Rate limit
    local now = os.clock()
    local lastRequest = _visitRateLimit[player.UserId] or 0
    if now - lastRequest < VISIT_RATE_LIMIT then
        ServerResponse:FireClient(player, "VisitBase", { success = false, error = "RATE_LIMITED" })
        return
    end
    _visitRateLimit[player.UserId] = now

    -- Check player is not in a battle
    if BattleArenaService and BattleArenaService:IsPlayerInBattle(player) then
        ServerResponse:FireClient(player, "VisitBase", { success = false, error = "ALREADY_IN_BATTLE" })
        return
    end

    -- Can't visit yourself
    if data.targetUserId == player.UserId then
        ServerResponse:FireClient(player, "VisitBase", { success = false, error = "CANNOT_VISIT_SELF" })
        return
    end

    -- Teleport to the target's village using TeleportManager
    if TeleportManager and OverworldService then
        local state = OverworldService:GetPlayerState(player)
        local currentPos = state and state.position or Vector3.new(500, 0, 500)

        -- Mark as teleporting so PlayerRemoving keeps their base
        _teleportingPlayers[player.UserId] = true

        local success, teleportErr = TeleportManager:TeleportToVillageAsVisitor(
            player, data.targetUserId, currentPos
        )

        if not success then
            _teleportingPlayers[player.UserId] = nil -- Clear on failure
            ServerResponse:FireClient(player, "VisitBase", { success = false, error = teleportErr })
        else
            print(string.format("[OVERWORLD] %s teleporting to visit %d's village", player.Name, data.targetUserId))
        end
    else
        ServerResponse:FireClient(player, "VisitBase", { success = false, error = "SERVICE_UNAVAILABLE" })
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 8: Player connection handling
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Setting up player handlers...")

Players.PlayerAdded:Connect(function(player)
    print(string.format("[OVERWORLD] Player joined: %s (%d)", player.Name, player.UserId))

    -- Check if player arrived via teleport (returning from village/visit/battle)
    local teleportData = nil
    local isReturning = OverworldService and OverworldService:IsPlayerInVillage(player.UserId)
    if TeleportManager then
        teleportData = TeleportManager:GetJoinData(player)
        if teleportData then
            local source = TeleportManager:GetSourcePlace(teleportData)
            print(string.format("[OVERWORLD] Player arrived from: %s", source or "unknown"))
        end
    end

    -- Wait for DataService to load player data before registering.
    -- DataService.Init() connects its own PlayerAdded handler which calls LoadPlayerData,
    -- but that's async (DataStore:GetAsync). We must wait for it to finish so
    -- getSpawnPosition() reads the correct saved mapPosition instead of generating
    -- a random one. Returning players skip this (their state is already in memory).
    if DataService and not isReturning then
        local waitStart = os.clock()
        while not DataService:GetPlayerData(player) do
            if player.Parent == nil then return end -- Player left during load
            if os.clock() - waitStart > 10 then
                warn(string.format("[OVERWORLD] Timed out waiting for data load: %s", player.Name))
                break
            end
            task.wait(0.2)
        end
    end

    -- Now that data is loaded, sync resources to client and ensure access code
    if DataService and DataService.GetPlayerData then
        local playerData = DataService:GetPlayerData(player)
        if playerData then
            SyncPlayerData:FireClient(player, playerData)
        end
    end
    if TeleportManager and TeleportManager.EnsureVillageAccessCode then
        TeleportManager:EnsureVillageAccessCode(player)
    end

    -- Register player in overworld (handles returning-from-village automatically)
    if OverworldService then
        local spawnPos = OverworldService:RegisterPlayer(player)

        -- If returning from village/visit, update banner to show online again
        if isReturning then
            local existingBase = MiniBaseBuilder.GetBase(player.UserId)
            if existingBase then
                local baseData = OverworldService:GetOwnBaseData(player)
                if baseData then
                    MiniBaseBuilder.Update(existingBase, baseData)
                    UpdateBase:FireAllClients(baseData)
                end
            end
        end

        -- Spawn player in front of their base gate (gate faces -Z at radius 10)
        local gateOffset = Vector3.new(0, 0, -25) -- 25 studs in front of base center
        local playerSpawnPos = spawnPos + gateOffset
        local facingBase = CFrame.lookAt(playerSpawnPos + Vector3.new(0, 3, 0), spawnPos + Vector3.new(0, 3, 0))

        -- Wait for character then position
        player.CharacterAdded:Connect(function(character)
            task.wait(0.1)

            local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
            if humanoidRootPart then
                humanoidRootPart.CFrame = facingBase
            end

            -- Set walk speed
            local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
            if humanoid then
                humanoid.WalkSpeed = OverworldConfig.Character.WalkSpeed
                humanoid.JumpPower = OverworldConfig.Character.JumpPower
            end
        end)

        -- If character already exists, position immediately
        if player.Character then
            local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                humanoidRootPart.CFrame = facingBase
            end
        end
    end

    -- Send initial data to client after brief delay (data is now loaded)
    task.delay(1, function()
        if player.Parent == nil then return end -- Player left

        if OverworldService then
            -- Send nearby bases
            local nearbyBases = OverworldService:GetNearbyBases(player)
            for _, baseData in nearbyBases do
                SpawnBase:FireClient(player, baseData)
            end

            -- Send own base data
            local ownBase = OverworldService:GetOwnBaseData(player)
            if ownBase then
                SpawnBase:FireClient(player, ownBase)
            end
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    print(string.format("[OVERWORLD] Player leaving: %s (%d)", player.Name, player.UserId))

    _visitRateLimit[player.UserId] = nil

    if _teleportingPlayers[player.UserId] then
        -- Player is teleporting to their village or visiting another base
        -- Keep their base on the map, just mark as away
        _teleportingPlayers[player.UserId] = nil
        if OverworldService then
            OverworldService:MarkPlayerInVillage(player.UserId)
            -- Update banner to show offline/away
            local existingBase = MiniBaseBuilder.GetBase(player.UserId)
            if existingBase then
                local state = OverworldService:GetPlayerState(player)
                if state then
                    MiniBaseBuilder.Update(existingBase, {
                        username = state.username,
                        trophies = state.trophies,
                        townHallLevel = state.townHallLevel,
                        isOnline = false,
                        hasShield = state.hasShield,
                    })
                    UpdateBase:FireAllClients({
                        userId = player.UserId,
                        isOnline = false,
                    })
                end
            end
        end
        print(string.format("[OVERWORLD] Player %s teleported — base kept on map", player.Name))
    else
        -- Player actually leaving the game — remove their base
        if OverworldService then
            OverworldService:UnregisterPlayer(player)
        end
    end
end)

-- Handle players already in game (for Studio testing or late script loading)
for _, player in Players:GetPlayers() do
    task.spawn(function()
        print(string.format("[OVERWORLD] Registering existing player: %s (%d)", player.Name, player.UserId))

        if OverworldService then
            local spawnPos = OverworldService:RegisterPlayer(player)

            -- Spawn in front of base gate, facing the base
            local gateOffset = Vector3.new(0, 0, -25)
            local playerSpawnPos = spawnPos + gateOffset
            local facingBase = CFrame.lookAt(playerSpawnPos + Vector3.new(0, 3, 0), spawnPos + Vector3.new(0, 3, 0))

            if player.Character then
                local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
                if humanoidRootPart then
                    humanoidRootPart.CFrame = facingBase
                end

                local humanoid = player.Character:FindFirstChild("Humanoid") :: Humanoid?
                if humanoid then
                    humanoid.WalkSpeed = OverworldConfig.Character.WalkSpeed
                    humanoid.JumpPower = OverworldConfig.Character.JumpPower
                end
            end
        end

        -- Send initial data to client
        task.delay(1, function()
            if player.Parent == nil then return end

            if OverworldService then
                local nearbyBases = OverworldService:GetNearbyBases(player)
                for _, baseData in nearbyBases do
                    SpawnBase:FireClient(player, baseData)
                end

                local ownBase = OverworldService:GetOwnBaseData(player)
                if ownBase then
                    SpawnBase:FireClient(player, ownBase)
                end
            end
        end)
    end)
end

-- Handle game shutdown - save all player data
game:BindToClose(function()
    print("[OVERWORLD] Shutting down, saving all player data...")
    if DataService and DataService.SaveAllData then
        DataService:SaveAllData()
    else
        -- Fallback: save individually if SaveAllData doesn't exist
        if DataService and DataService.SavePlayerData then
            for _, player in Players:GetPlayers() do
                pcall(function() DataService:SavePlayerData(player) end)
            end
        end
    end
    task.wait(3) -- Give time for saves with retry backoff to complete
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 9: Periodic updates
-- ═══════════════════════════════════════════════════════════════════════════════

-- Periodically sync nearby bases to all players
task.spawn(function()
    while true do
        task.wait(5) -- Every 5 seconds

        for _, player in Players:GetPlayers() do
            if OverworldService then
                local nearbyBases = OverworldService:GetNearbyBases(player, nil, 20)
                PositionSync:FireClient(player, nearbyBases)
            end
        end
    end
end)

-- Periodically check for goblin camp respawns
task.spawn(function()
    while true do
        task.wait(60) -- Every 60 seconds
        if GoblinCampService then
            GoblinCampService:CheckRespawns()
        end
    end
end)

-- Periodically check for resource node respawns (per-player cooldowns)
task.spawn(function()
    while true do
        task.wait(60) -- Every 60 seconds
        if ResourceNodeService then
            for _, player in Players:GetPlayers() do
                ResourceNodeService:CheckRespawns(player)
            end
        end
    end
end)

print("========================================")
print("BATTLE TYCOON: CONQUEST - OVERWORLD READY!")
print("========================================")
