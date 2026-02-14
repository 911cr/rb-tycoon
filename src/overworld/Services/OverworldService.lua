--!strict
--[[
    OverworldService.lua

    Server-side service that manages the overworld state.
    Tracks player positions, coordinates mini-base spawning, and handles
    interactions between players in the overworld.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local WorldMapData = require(ReplicatedStorage.Shared.Constants.WorldMapData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local OverworldService = {}
OverworldService.__index = OverworldService

-- ============================================================================
-- SIGNALS (Events)
-- ============================================================================

OverworldService.PlayerEnteredOverworld = Signal.new()
OverworldService.PlayerLeftOverworld = Signal.new()
OverworldService.BaseSpawned = Signal.new()
OverworldService.BaseRemoved = Signal.new()
OverworldService.PlayerApproachedBase = Signal.new()
OverworldService.PlayerLeftBase = Signal.new()

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

type PlayerState = {
    userId: number,
    username: string,
    position: Vector3,
    lastUpdate: number,
    townHallLevel: number,
    trophies: number,
    hasShield: boolean,
    isOnline: boolean,
    allianceId: string?,
    friends: {number},
}

local _initialized = false
local _players: {[number]: PlayerState} = {} -- userId -> state
local _basesCache: {[number]: PlayerState} = {} -- userId -> cached state for bases
local _lastCacheUpdate = 0
local _updateInterval = OverworldConfig.Interaction.UpdateInterval
local _cacheRefreshInterval = 30 -- seconds

-- Reference to DataService (loaded dynamically)
local _dataService: any = nil

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Gets the DataService if available.
]]
local function getDataService(): any
    if _dataService then return _dataService end

    local ServerScriptService = game:GetService("ServerScriptService")
    local servicesFolder = ServerScriptService:FindFirstChild("Services")

    if servicesFolder then
        local dataServiceModule = servicesFolder:FindFirstChild("DataService")
        if dataServiceModule then
            _dataService = require(dataServiceModule)
        end
    end

    return _dataService
end

--[[
    Gets player data from DataService or returns defaults.
]]
local function getPlayerData(player: Player): (number, number, boolean, string?, {number})
    local dataService = getDataService()

    if dataService and dataService.GetPlayerData then
        local data = dataService:GetPlayerData(player)
        if data then
            return data.townHallLevel or 1,
                   data.trophies and data.trophies.current or 0,
                   data.shield and data.shield.active or false,
                   data.alliance and data.alliance.allianceId or nil,
                   data.friends or {}
        end
    end

    return 1, 0, false, nil, {}
end

--[[
    Minimum distance between any two player bases (in map units).
]]
local MIN_BASE_DISTANCE = 40

--[[
    Checks if a map position is too close to any existing player base.

    @param pos {x: number, z: number} - The candidate position
    @return boolean - True if the position is occupied (too close to another base)
]]
local function isPositionOccupied(pos: {x: number, z: number}): boolean
    for _, state in _players do
        local dx = state.position.X - pos.x
        local dz = state.position.Z - pos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist < MIN_BASE_DISTANCE then
            return true
        end
    end
    return false
end

--[[
    Generates a starting position that doesn't overlap with existing bases.
    Tries up to 20 times before accepting whatever it gets.

    @return {x: number, z: number} - A non-overlapping map position
]]
local function generateNonOverlappingPosition(): {x: number, z: number}
    for _ = 1, 20 do
        local candidate = WorldMapData.GenerateStartingPosition()
        if not isPositionOccupied(candidate) then
            return candidate
        end
    end
    -- After 20 attempts, accept the last random position (map is large enough this is rare)
    return WorldMapData.GenerateStartingPosition()
end

--[[
    Gets the spawn position for a player based on their map position.
]]
local function getSpawnPosition(player: Player): Vector3
    local dataService = getDataService()

    if dataService and dataService.GetPlayerData then
        local data = dataService:GetPlayerData(player)
        if data and data.mapPosition then
            return OverworldConfig.MapToWorld(data.mapPosition.x, data.mapPosition.z)
        end

        -- No saved position — generate a non-overlapping random position and save it
        local startPos = generateNonOverlappingPosition()
        if data then
            data.mapPosition = startPos
        end

        return OverworldConfig.MapToWorld(startPos.x, startPos.z)
    end

    -- Fallback if DataService unavailable — non-overlapping random position
    local startPos = generateNonOverlappingPosition()
    return OverworldConfig.MapToWorld(startPos.x, startPos.z)
end

--[[
    Updates the bases cache with data from WorldMapService or MemoryStore.
]]
local function refreshBasesCache()
    local now = os.time()

    -- Only refresh if enough time has passed
    if now - _lastCacheUpdate < _cacheRefreshInterval then
        return
    end

    _lastCacheUpdate = now

    -- For now, cache is built from connected players
    -- In a full implementation, this would pull from MemoryStore
    -- to show players from other servers

    -- Update cache with current player states
    for userId, state in _players do
        _basesCache[userId] = state
    end

    print("[OverworldService] Bases cache refreshed with", #_players, "players")
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Initializes the OverworldService.
]]
function OverworldService:Init()
    if _initialized then
        warn("[OverworldService] Already initialized")
        return
    end

    _initialized = true
    print("[OverworldService] Initialized")
end

--[[
    Registers a player in the overworld.

    @param player Player - The player joining the overworld
    @return Vector3 - The spawn position for the player
]]
function OverworldService:RegisterPlayer(player: Player): Vector3
    local userId = player.UserId
    local spawnPos = getSpawnPosition(player)
    local thLevel, trophies, hasShield, allianceId, friends = getPlayerData(player)

    local state: PlayerState = {
        userId = userId,
        username = player.Name,
        position = spawnPos,
        lastUpdate = os.time(),
        townHallLevel = thLevel,
        trophies = trophies,
        hasShield = hasShield,
        isOnline = true,
        allianceId = allianceId,
        friends = friends,
    }

    _players[userId] = state

    -- Fire event
    self.PlayerEnteredOverworld:Fire(player, state)

    print(string.format("[OverworldService] Player registered: %s at (%.0f, %.0f)",
        player.Name, spawnPos.X, spawnPos.Z))

    return spawnPos
end

--[[
    Unregisters a player from the overworld.

    @param player Player - The player leaving
]]
function OverworldService:UnregisterPlayer(player: Player)
    local userId = player.UserId
    local state = _players[userId]

    if state then
        _players[userId] = nil
        self.PlayerLeftOverworld:Fire(player, state)

        print(string.format("[OverworldService] Player unregistered: %s", player.Name))
    end
end

--[[
    Updates a player's position in the overworld.

    @param player Player - The player
    @param position Vector3 - New position
]]
function OverworldService:UpdatePlayerPosition(player: Player, position: Vector3)
    local userId = player.UserId
    local state = _players[userId]

    if state then
        state.position = position
        state.lastUpdate = os.time()
    end
end

--[[
    Gets a player's current state in the overworld.

    @param player Player - The player
    @return PlayerState? - The player's state, or nil if not registered
]]
function OverworldService:GetPlayerState(player: Player): PlayerState?
    return _players[player.UserId]
end

--[[
    Gets all nearby bases for a player.

    @param player Player - The requesting player
    @param centerPos Vector3? - Center position to search from (defaults to player position)
    @param maxCount number? - Maximum bases to return
    @return {table} - Array of base data for nearby players
]]
function OverworldService:GetNearbyBases(player: Player, centerPos: Vector3?, maxCount: number?): {any}
    refreshBasesCache()

    local userId = player.UserId
    local playerState = _players[userId]

    if not playerState then
        return {}
    end

    local center = centerPos or playerState.position
    local viewDistance = OverworldConfig.Interaction.ViewDistance
    local limit = maxCount or OverworldConfig.Interaction.MaxVisibleBases

    local nearbyBases = {}

    -- Get nearby bases from cache
    for otherUserId, otherState in _basesCache do
        if otherUserId ~= userId then
            local distance = (otherState.position - center).Magnitude

            if distance <= viewDistance then
                local isFriend = table.find(playerState.friends, otherUserId) ~= nil

                table.insert(nearbyBases, {
                    userId = otherUserId,
                    username = otherState.username,
                    position = otherState.position,
                    townHallLevel = otherState.townHallLevel,
                    trophies = otherState.trophies,
                    hasShield = otherState.hasShield,
                    isOnline = otherState.isOnline,
                    isFriend = isFriend,
                    isOwnBase = false,
                    distance = distance,
                })
            end
        end
    end

    -- Sort by distance
    table.sort(nearbyBases, function(a, b)
        return a.distance < b.distance
    end)

    -- Limit count
    if #nearbyBases > limit then
        local limited = {}
        for i = 1, limit do
            limited[i] = nearbyBases[i]
        end
        return limited
    end

    return nearbyBases
end

--[[
    Gets the base data for a specific player (for spawning their mini-base).

    @param targetUserId number - The user ID of the base owner
    @param viewerPlayer Player - The player viewing the base
    @return table? - Base data, or nil if not found
]]
function OverworldService:GetBaseData(targetUserId: number, viewerPlayer: Player): any
    local targetState = _players[targetUserId] or _basesCache[targetUserId]

    if not targetState then
        return nil
    end

    local viewerState = _players[viewerPlayer.UserId]
    local isFriend = false
    local isOwnBase = targetUserId == viewerPlayer.UserId

    if viewerState then
        isFriend = table.find(viewerState.friends, targetUserId) ~= nil
    end

    -- Get viewer's TH level for difficulty comparison
    local viewerTH = 1
    if viewerState then
        viewerTH = viewerState.townHallLevel or 1
    end

    -- Estimate available loot (20% of target resources)
    local lootEstimate = nil
    if not isOwnBase then
        local dataService = getDataService()
        if dataService and dataService.GetPlayerData then
            local targetPlayer = game:GetService("Players"):GetPlayerByUserId(targetUserId)
            if targetPlayer then
                local targetData = dataService:GetPlayerData(targetPlayer)
                if targetData and targetData.resources then
                    local lootPercent = 0.85
                    lootEstimate = {
                        gold = math.floor((targetData.resources.gold or 0) * lootPercent),
                        wood = math.floor((targetData.resources.wood or 0) * lootPercent),
                        food = math.floor((targetData.resources.food or 0) * lootPercent),
                    }
                end
            end
        end
    end

    return {
        userId = targetUserId,
        username = targetState.username,
        position = targetState.position,
        townHallLevel = targetState.townHallLevel,
        trophies = targetState.trophies,
        hasShield = targetState.hasShield,
        isOnline = targetState.isOnline,
        isFriend = isFriend,
        isOwnBase = isOwnBase,
        viewerTownHallLevel = viewerTH,
        lootEstimate = lootEstimate,
    }
end

--[[
    Gets the player's own base data for display.

    @param player Player - The player
    @return table? - Own base data
]]
function OverworldService:GetOwnBaseData(player: Player): any
    local state = _players[player.UserId]

    if not state then
        return nil
    end

    return {
        userId = state.userId,
        username = state.username,
        position = state.position,
        townHallLevel = state.townHallLevel,
        trophies = state.trophies,
        hasShield = state.hasShield,
        isOnline = true,
        isFriend = false,
        isOwnBase = true,
    }
end

--[[
    Checks if a player is near a base's gate.

    @param player Player - The player
    @param targetUserId number - The target base owner's user ID
    @return boolean - True if within gate distance
]]
function OverworldService:IsNearGate(player: Player, targetUserId: number): boolean
    local playerState = _players[player.UserId]
    local targetState = _players[targetUserId] or _basesCache[targetUserId]

    if not playerState or not targetState then
        return false
    end

    local distance = (playerState.position - targetState.position).Magnitude
    return distance <= OverworldConfig.Interaction.GateDistance
end

--[[
    Validates that a player can enter a village (their own base).

    @param player Player - The player
    @return boolean, string? - Success and optional error
]]
function OverworldService:CanEnterVillage(player: Player): (boolean, string?)
    local state = _players[player.UserId]

    if not state then
        return false, "NOT_REGISTERED"
    end

    -- Must be near their own base
    local baseData = self:GetOwnBaseData(player)
    if not baseData then
        return false, "BASE_NOT_FOUND"
    end

    local distance = (state.position - baseData.position).Magnitude
    if distance > OverworldConfig.Interaction.GateDistance * 2 then
        return false, "TOO_FAR_FROM_BASE"
    end

    return true
end

--[[
    Validates that a player can start an attack on a target.

    @param player Player - The attacking player
    @param targetUserId number - The target user ID
    @return boolean, string? - Success and optional error
]]
function OverworldService:CanStartAttack(player: Player, targetUserId: number): (boolean, string?)
    local playerState = _players[player.UserId]

    if not playerState then
        return false, "NOT_REGISTERED"
    end

    -- Can't attack yourself
    if targetUserId == player.UserId then
        return false, "CANNOT_ATTACK_SELF"
    end

    -- Get target data
    local targetState = _players[targetUserId] or _basesCache[targetUserId]
    if not targetState then
        return false, "TARGET_NOT_FOUND"
    end

    -- Check if target has shield
    if targetState.hasShield then
        return false, "TARGET_HAS_SHIELD"
    end

    -- Must be within interaction distance
    local distance = (playerState.position - targetState.position).Magnitude
    if distance > OverworldConfig.Interaction.InfoDistance then
        return false, "TOO_FAR_FROM_TARGET"
    end

    return true
end

--[[
    Updates player data when it changes (e.g., after a battle).

    @param player Player - The player
]]
function OverworldService:RefreshPlayerData(player: Player)
    local state = _players[player.UserId]

    if state then
        local thLevel, trophies, hasShield, allianceId, friends = getPlayerData(player)
        state.townHallLevel = thLevel
        state.trophies = trophies
        state.hasShield = hasShield
        state.allianceId = allianceId
        state.friends = friends
        state.lastUpdate = os.time()
    end
end

--[[
    Gets all registered players in the overworld.

    @return {[number]: PlayerState} - Map of user ID to player state
]]
function OverworldService:GetAllPlayers(): {[number]: PlayerState}
    return _players
end

--[[
    Gets the count of active players in the overworld.

    @return number - Number of registered players
]]
function OverworldService:GetPlayerCount(): number
    local count = 0
    for _ in _players do
        count += 1
    end
    return count
end

return OverworldService
