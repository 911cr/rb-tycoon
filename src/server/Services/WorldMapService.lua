--!strict
--[[
    WorldMapService.lua

    Manages the World Map system for Battle Tycoon: Conquest.
    Handles player positioning, base relocation, and cross-server visibility.

    SECURITY:
    - All map operations are server-authoritative
    - Position validation prevents invalid placements
    - Rate limiting on relocation requests

    Dependencies:
    - DataService (for player data)
    - MatchmakingService (for opponent filtering)

    Events:
    - BaseRelocated(player, oldPosition, newPosition)
    - TravelStarted(player, targetId, travelTime)
]]

local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldMapData = require(ReplicatedStorage.Shared.Constants.WorldMapData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declarations
local DataService

local WorldMapService = {}
WorldMapService.__index = WorldMapService

-- Events
WorldMapService.BaseRelocated = Signal.new()
WorldMapService.TravelStarted = Signal.new()
WorldMapService.TravelCompleted = Signal.new()

-- Private state
local _initialized = false
local _worldMapStore = nil -- MemoryStoreHashMap
local _useLocalMode = false -- True when MemoryStore unavailable
local _localMapCache: {[number]: any} = {} -- Local cache for testing

-- Active travel sessions
local _activeTravels: {[number]: {
    targetId: number,
    startTime: number,
    endTime: number,
    cancelled: boolean,
}} = {}

-- Rate limiting
local _lastRelocation: {[number]: number} = {}
local RELOCATION_RATE_LIMIT = 5 -- seconds between relocation attempts

-- Types
type MapPlayerInfo = {
    userId: number,
    username: string,
    trophies: number,
    townHallLevel: number,
    position: {x: number, z: number},
    isShielded: boolean,
    lastOnline: number,
    isFriend: boolean?,
    resources: {gold: number, wood: number, food: number}?,
}

type RelocationResult = {
    success: boolean,
    newPosition: {x: number, z: number}?,
    error: string?,
    cost: number?,
}

type TravelResult = {
    success: boolean,
    travelTime: number?,
    description: string?,
    error: string?,
}

--[[
    Initializes the MemoryStore for cross-server map state.
]]
local function initMemoryStore()
    local success, result = pcall(function()
        return MemoryStoreService:GetHashMap(WorldMapData.MemoryStore.MapName)
    end)

    if success then
        _worldMapStore = result
        print("[WorldMapService] MemoryStore connected")
    else
        _useLocalMode = true
        warn("[WorldMapService] MemoryStore unavailable, using local-only mode")
    end
end

--[[
    Updates a player's position in the world map store.
]]
local function updatePlayerInStore(player: Player, playerData: any)
    if not playerData or not playerData.mapPosition then return end

    local mapInfo: MapPlayerInfo = {
        userId = player.UserId,
        username = player.Name,
        trophies = playerData.trophies and playerData.trophies.current or 0,
        townHallLevel = playerData.townHallLevel or 1,
        position = playerData.mapPosition,
        isShielded = playerData.shield ~= nil and playerData.shield.active == true
            and os.time() < (playerData.shield.expiresAt or 0),
        lastOnline = os.time(),
    }

    if _useLocalMode then
        _localMapCache[player.UserId] = mapInfo
    else
        local success, err = pcall(function()
            _worldMapStore:SetAsync(
                tostring(player.UserId),
                mapInfo,
                WorldMapData.MemoryStore.PositionExpiry
            )
        end)

        if not success then
            warn("[WorldMapService] Failed to update player in store:", err)
            -- Fall back to local cache
            _localMapCache[player.UserId] = mapInfo
        end
    end
end

--[[
    Removes a player from the world map store.
]]
local function removePlayerFromStore(userId: number)
    _localMapCache[userId] = nil

    if not _useLocalMode and _worldMapStore then
        pcall(function()
            _worldMapStore:RemoveAsync(tostring(userId))
        end)
    end
end

--[[
    Gets players within view distance of a position.
]]
function WorldMapService:GetNearbyPlayers(
    player: Player,
    centerPosition: {x: number, z: number}?,
    maxCount: number?
): {MapPlayerInfo}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return {} end

    local center = centerPosition or playerData.mapPosition
    if not center then return {} end

    local viewDistance = WorldMapData.Map.ViewDistance
    local maxResults = maxCount or WorldMapData.Map.MaxVisibleBases
    local friends = playerData.friends or {}

    -- Create friend lookup
    local friendLookup = {}
    for _, friendId in friends do
        friendLookup[friendId] = true
    end

    -- Extended view distance for friends
    local friendViewDistance = viewDistance + WorldMapData.Friends.ViewDistanceBonus

    local nearbyPlayers: {MapPlayerInfo} = {}

    -- Collect from local cache
    for userId, info in _localMapCache do
        if userId == player.UserId then continue end

        local distance = WorldMapData.CalculateDistance(center, info.position)
        local isFriend = friendLookup[userId] == true

        -- Check view distance (friends visible further)
        local maxDist = isFriend and friendViewDistance or viewDistance
        if distance <= maxDist then
            local playerInfo = table.clone(info)
            playerInfo.isFriend = isFriend
            table.insert(nearbyPlayers, playerInfo)
        end
    end

    -- Also check online players not in cache
    for _, otherPlayer in Players:GetPlayers() do
        if otherPlayer.UserId == player.UserId then continue end
        if _localMapCache[otherPlayer.UserId] then continue end

        local otherData = DataService:GetPlayerData(otherPlayer)
        if not otherData or not otherData.mapPosition then continue end

        local distance = WorldMapData.CalculateDistance(center, otherData.mapPosition)
        local isFriend = friendLookup[otherPlayer.UserId] == true

        local maxDist = isFriend and friendViewDistance or viewDistance
        if distance <= maxDist then
            table.insert(nearbyPlayers, {
                userId = otherPlayer.UserId,
                username = otherPlayer.Name,
                trophies = otherData.trophies and otherData.trophies.current or 0,
                townHallLevel = otherData.townHallLevel or 1,
                position = otherData.mapPosition,
                isShielded = otherData.shield ~= nil and otherData.shield.active == true
                    and os.time() < (otherData.shield.expiresAt or 0),
                lastOnline = os.time(),
                isFriend = isFriend,
            })
        end
    end

    -- Sort by distance
    table.sort(nearbyPlayers, function(a, b)
        local distA = WorldMapData.CalculateDistance(center, a.position)
        local distB = WorldMapData.CalculateDistance(center, b.position)
        return distA < distB
    end)

    -- Limit results
    if #nearbyPlayers > maxResults then
        local trimmed = {}
        for i = 1, maxResults do
            trimmed[i] = nearbyPlayers[i]
        end
        return trimmed
    end

    return nearbyPlayers
end

--[[
    Relocates a player's base to a new position.
]]
function WorldMapService:RelocateBase(
    player: Player,
    newPosition: {x: number, z: number}
): RelocationResult
    -- Rate limiting
    local now = os.time()
    local lastAttempt = _lastRelocation[player.UserId] or 0
    if now - lastAttempt < RELOCATION_RATE_LIMIT then
        return { success = false, newPosition = nil, error = "RATE_LIMITED", cost = nil }
    end
    _lastRelocation[player.UserId] = now

    -- Validate input
    if typeof(newPosition) ~= "table" then
        return { success = false, newPosition = nil, error = "INVALID_POSITION", cost = nil }
    end

    if typeof(newPosition.x) ~= "number" or typeof(newPosition.z) ~= "number" then
        return { success = false, newPosition = nil, error = "INVALID_POSITION", cost = nil }
    end

    -- Validate position is within bounds
    if not WorldMapData.IsValidPosition(newPosition) then
        return { success = false, newPosition = nil, error = "OUT_OF_BOUNDS", cost = nil }
    end

    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, newPosition = nil, error = "NO_PLAYER_DATA", cost = nil }
    end

    local currentPosition = playerData.mapPosition
    if not currentPosition then
        -- First time placement
        playerData.mapPosition = newPosition
        playerData.lastMoveTime = now
        updatePlayerInStore(player, playerData)
        WorldMapService.BaseRelocated:Fire(player, nil, newPosition)
        return { success = true, newPosition = newPosition, error = nil, cost = 0 }
    end

    -- Check minimum move distance
    local distance = WorldMapData.CalculateDistance(currentPosition, newPosition)
    if distance < WorldMapData.Relocation.MinMoveDistance then
        return { success = false, newPosition = nil, error = "TOO_CLOSE", cost = nil }
    end

    -- Calculate cost based on cooldown
    local lastMoveTime = playerData.lastMoveTime or 0
    local timeSinceMove = now - lastMoveTime
    local withinCooldown = timeSinceMove < WorldMapData.Relocation.FreeCooldown

    local cost = WorldMapData.CalculateRelocationCost(playerData.townHallLevel, withinCooldown)

    -- Check if player can afford
    if cost > 0 then
        if not playerData.resources or playerData.resources.gold < cost then
            return { success = false, newPosition = nil, error = "INSUFFICIENT_GOLD", cost = cost }
        end

        -- Deduct cost
        playerData.resources.gold -= cost
    end

    -- Store old position for event
    local oldPosition = currentPosition

    -- Update position
    playerData.mapPosition = newPosition
    playerData.lastMoveTime = now

    -- Update in store
    updatePlayerInStore(player, playerData)

    -- Fire event
    WorldMapService.BaseRelocated:Fire(player, oldPosition, newPosition)

    return { success = true, newPosition = newPosition, error = nil, cost = cost }
end

--[[
    Gets the relocation status for a player.
]]
function WorldMapService:GetRelocationStatus(player: Player): {
    canRelocateFree: boolean,
    cooldownRemaining: number,
    costIfNow: number,
}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { canRelocateFree = true, cooldownRemaining = 0, costIfNow = 0 }
    end

    local now = os.time()
    local lastMoveTime = playerData.lastMoveTime or 0
    local timeSinceMove = now - lastMoveTime
    local cooldownRemaining = math.max(0, WorldMapData.Relocation.FreeCooldown - timeSinceMove)

    local withinCooldown = cooldownRemaining > 0
    local cost = WorldMapData.CalculateRelocationCost(playerData.townHallLevel, withinCooldown)

    return {
        canRelocateFree = not withinCooldown,
        cooldownRemaining = cooldownRemaining,
        costIfNow = cost,
    }
end

--[[
    Calculates travel time to a target position.
]]
function WorldMapService:GetTravelTime(
    player: Player,
    targetPosition: {x: number, z: number}
): TravelResult
    local playerData = DataService:GetPlayerData(player)
    if not playerData or not playerData.mapPosition then
        return { success = false, travelTime = nil, description = nil, error = "NO_POSITION" }
    end

    local distance = WorldMapData.CalculateDistance(playerData.mapPosition, targetPosition)
    local travelTime, description = WorldMapData.CalculateTravelTime(distance)

    return {
        success = true,
        travelTime = travelTime,
        description = description,
        error = nil,
    }
end

--[[
    Starts travel to a target for attack.
]]
function WorldMapService:StartTravel(
    player: Player,
    targetUserId: number
): TravelResult
    local playerData = DataService:GetPlayerData(player)
    if not playerData or not playerData.mapPosition then
        return { success = false, travelTime = nil, description = nil, error = "NO_POSITION" }
    end

    -- Check if already traveling
    if _activeTravels[player.UserId] then
        return { success = false, travelTime = nil, description = nil, error = "ALREADY_TRAVELING" }
    end

    -- Get target position
    local targetData = DataService:GetPlayerDataById(targetUserId)
    if not targetData or not targetData.mapPosition then
        -- Check local cache
        local cached = _localMapCache[targetUserId]
        if not cached then
            return { success = false, travelTime = nil, description = nil, error = "TARGET_NOT_FOUND" }
        end
        targetData = { mapPosition = cached.position }
    end

    local distance = WorldMapData.CalculateDistance(playerData.mapPosition, targetData.mapPosition)
    local travelTime, description = WorldMapData.CalculateTravelTime(distance)

    -- If instant, just return success
    if travelTime == 0 then
        return {
            success = true,
            travelTime = 0,
            description = description,
            error = nil,
        }
    end

    -- Start travel
    local now = os.time()
    _activeTravels[player.UserId] = {
        targetId = targetUserId,
        startTime = now,
        endTime = now + travelTime,
        cancelled = false,
    }

    -- Fire event
    WorldMapService.TravelStarted:Fire(player, targetUserId, travelTime)

    return {
        success = true,
        travelTime = travelTime,
        description = description,
        error = nil,
    }
end

--[[
    Cancels an active travel.
]]
function WorldMapService:CancelTravel(player: Player): boolean
    local travel = _activeTravels[player.UserId]
    if not travel then return false end

    travel.cancelled = true
    _activeTravels[player.UserId] = nil

    return true
end

--[[
    Checks if travel is complete for a player.
]]
function WorldMapService:IsTravelComplete(player: Player): (boolean, number?)
    local travel = _activeTravels[player.UserId]
    if not travel then
        return true, nil -- Not traveling, can proceed
    end

    if travel.cancelled then
        return false, nil
    end

    local now = os.time()
    if now >= travel.endTime then
        local targetId = travel.targetId
        _activeTravels[player.UserId] = nil
        WorldMapService.TravelCompleted:Fire(player, targetId)
        return true, targetId
    end

    -- Still traveling
    return false, travel.targetId
end

--[[
    Gets remaining travel time.
]]
function WorldMapService:GetRemainingTravelTime(player: Player): number
    local travel = _activeTravels[player.UserId]
    if not travel then return 0 end

    local now = os.time()
    return math.max(0, travel.endTime - now)
end

--[[
    Adds a friend to player's friend list.
]]
function WorldMapService:AddFriend(player: Player, friendUserId: number): boolean
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return false end

    -- Validate friend exists
    if friendUserId == player.UserId then return false end

    -- Check max friends
    playerData.friends = playerData.friends or {}
    if #playerData.friends >= WorldMapData.Friends.MaxFriends then
        return false
    end

    -- Check not already friend
    for _, id in playerData.friends do
        if id == friendUserId then
            return false
        end
    end

    table.insert(playerData.friends, friendUserId)
    return true
end

--[[
    Removes a friend from player's friend list.
]]
function WorldMapService:RemoveFriend(player: Player, friendUserId: number): boolean
    local playerData = DataService:GetPlayerData(player)
    if not playerData or not playerData.friends then return false end

    for i, id in playerData.friends do
        if id == friendUserId then
            table.remove(playerData.friends, i)
            return true
        end
    end

    return false
end

--[[
    Gets player's position on the map.
]]
function WorldMapService:GetPlayerPosition(player: Player): {x: number, z: number}?
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return nil end
    return playerData.mapPosition
end

--[[
    Initializes the WorldMapService.
]]
function WorldMapService:Init()
    if _initialized then
        warn("WorldMapService already initialized")
        return
    end

    -- Get service references
    local ServerScriptService = game:GetService("ServerScriptService")
    DataService = require(ServerScriptService.Services.DataService)

    -- Initialize memory store
    initMemoryStore()

    -- Update player positions periodically
    task.spawn(function()
        while true do
            task.wait(WorldMapData.MemoryStore.SyncInterval)

            for _, player in Players:GetPlayers() do
                local playerData = DataService:GetPlayerData(player)
                if playerData then
                    updatePlayerInStore(player, playerData)
                end
            end
        end
    end)

    -- Handle player join
    Players.PlayerAdded:Connect(function(player)
        -- Wait for data to load
        task.delay(2, function()
            local playerData = DataService:GetPlayerData(player)
            if playerData then
                updatePlayerInStore(player, playerData)
            end
        end)
    end)

    -- Handle player leave
    Players.PlayerRemoving:Connect(function(player)
        -- Cancel any active travel
        _activeTravels[player.UserId] = nil
        _lastRelocation[player.UserId] = nil

        -- Remove from store after delay (show as offline)
        task.delay(60, function()
            removePlayerFromStore(player.UserId)
        end)
    end)

    -- Check travel completions
    task.spawn(function()
        while true do
            task.wait(1)

            local now = os.time()
            for userId, travel in _activeTravels do
                if not travel.cancelled and now >= travel.endTime then
                    local player = Players:GetPlayerByUserId(userId)
                    if player then
                        local targetId = travel.targetId
                        _activeTravels[userId] = nil
                        WorldMapService.TravelCompleted:Fire(player, targetId)
                    else
                        _activeTravels[userId] = nil
                    end
                end
            end
        end
    end)

    _initialized = true
    print("WorldMapService initialized")
end

return WorldMapService
