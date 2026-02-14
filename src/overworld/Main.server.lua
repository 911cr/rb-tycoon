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

-- UI data
local GetOwnBaseData = createRemoteFunction("GetOwnBaseData")
local GetPlayerResources = createRemoteFunction("GetPlayerResources")

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

-- Load overworld services
local OverworldService = loadService("OverworldService")
local TeleportManager = loadService("TeleportManager")
local BattleArenaService = loadService("BattleArenaService")
local MatchmakingService = loadService("MatchmakingService")

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

initService(TeleportManager, "TeleportManager")
initService(OverworldService, "OverworldService")
initService(MatchmakingService, "MatchmakingService")
initService(BattleArenaService, "BattleArenaService")

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
    -- This would connect to DataService in a full implementation
    return {
        gold = 1000,
        wood = 500,
        food = 300,
    }
end

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

        local success, teleportErr = TeleportManager:TeleportToVillage(player, currentPos)

        if not success then
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
        local lootPercent = 0.2 -- 20% of stored resources
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
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- STEP 8: Player connection handling
-- ═══════════════════════════════════════════════════════════════════════════════
print("[OVERWORLD] Setting up player handlers...")

Players.PlayerAdded:Connect(function(player)
    print(string.format("[OVERWORLD] Player joined: %s (%d)", player.Name, player.UserId))

    -- Check if player arrived via teleport
    local teleportData = nil
    if TeleportManager then
        teleportData = TeleportManager:GetJoinData(player)
        if teleportData then
            local source = TeleportManager:GetSourcePlace(teleportData)
            print(string.format("[OVERWORLD] Player arrived from: %s", source or "unknown"))
        end
    end

    -- Register player in overworld
    if OverworldService then
        local spawnPos = OverworldService:RegisterPlayer(player)

        -- If returning from village/battle, use return position
        if teleportData and TeleportManager then
            local returnPos = TeleportManager:ParseReturnPosition(teleportData)
            if returnPos then
                spawnPos = returnPos
                OverworldService:UpdatePlayerPosition(player, returnPos)
            end
        end

        -- Wait for character then position
        player.CharacterAdded:Connect(function(character)
            task.wait(0.1)

            local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
            if humanoidRootPart then
                humanoidRootPart.CFrame = CFrame.new(spawnPos + Vector3.new(0, 5, 0))
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
                humanoidRootPart.CFrame = CFrame.new(spawnPos + Vector3.new(0, 5, 0))
            end
        end
    end

    -- Send initial data to client after brief delay
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

    if OverworldService then
        OverworldService:UnregisterPlayer(player)
    end
end)

-- Handle players already in game (for Studio testing or late script loading)
for _, player in Players:GetPlayers() do
    task.spawn(function()
        print(string.format("[OVERWORLD] Registering existing player: %s (%d)", player.Name, player.UserId))

        if OverworldService then
            local spawnPos = OverworldService:RegisterPlayer(player)

            -- If character exists, position it
            if player.Character then
                local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
                if humanoidRootPart then
                    humanoidRootPart.CFrame = CFrame.new(spawnPos + Vector3.new(0, 5, 0))
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

-- Handle game shutdown
game:BindToClose(function()
    print("[OVERWORLD] Shutting down...")
    task.wait(1)
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

print("========================================")
print("BATTLE TYCOON: CONQUEST - OVERWORLD READY!")
print("========================================")
