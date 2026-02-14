--!strict
--[[
    ResourceNodeService.lua

    Manages collectible resource nodes for Battle Tycoon: Conquest.
    Resource nodes are scattered across the overworld. Players walk up and
    interact to collect a small resource bonus. Each node uses PER-PLAYER
    cooldowns so one player collecting a node does not affect others.

    SECURITY:
    - All node state is server-authoritative
    - Client only receives node metadata (position, type, amount range)
    - Resources are granted server-side via DataService
    - Rate limited: 1 collection per 2 seconds per player
    - Distance validation: player must be within 30 studs of node
    - Per-player cooldowns stored server-side

    Dependencies:
    - ResourceNodeData (node definitions)
    - DataService (player data / resource granting)

    Architecture:
    - Per-player cooldowns (not global): each player can collect each node independently
    - Server validates proximity, rate limits, and cooldown before granting resources
    - Random amount between min/max calculated server-side
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ResourceNodeData = require(ReplicatedStorage.Shared.Constants.ResourceNodeData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declaration for DataService (resolved in Init)
local DataService

local ResourceNodeService = {}
ResourceNodeService.__index = ResourceNodeService

-- Events
ResourceNodeService.NodeCollected = Signal.new()

-- Private state
local _initialized = false

-- Per-player collection tracking: [userId] = { [nodeId] = timestamp }
local _playerCollections: {[number]: {[string]: number}} = {}

-- Rate limit for collection requests per player
local _collectRateLimit: {[number]: number} = {} -- [userId] = lastCollectTime
local COLLECT_RATE_LIMIT = 2 -- seconds between collection requests
local MAX_COLLECT_DISTANCE = 30 -- studs

--[[
    Initializes the ResourceNodeService.
    Resolves service references and sets up cleanup handlers.
]]
function ResourceNodeService:Init()
    if _initialized then
        warn("[ResourceNodeService] Already initialized")
        return
    end

    -- Resolve service references
    DataService = require(ServerScriptService.Services.DataService)

    -- Clean up player data when they leave
    Players.PlayerRemoving:Connect(function(player)
        _playerCollections[player.UserId] = nil
        _collectRateLimit[player.UserId] = nil
    end)

    _initialized = true
    print("[ResourceNodeService] Initialized with", #ResourceNodeData.Nodes, "nodes")
end

--[[
    Attempts to collect a resource node for a player.
    Validates node exists, player proximity, rate limit, and per-player cooldown.
    Grants resources via DataService on success.

    @param player Player - The collecting player
    @param nodeId string - The node ID to collect
    @return boolean - Whether collection succeeded
    @return string? - Error code if failed, or resource type if succeeded
    @return number? - Amount collected (only on success)
]]
function ResourceNodeService:CollectNode(player: Player, nodeId: string): (boolean, string?, number?)
    -- 1. Rate limit
    local now = os.clock()
    local lastCollect = _collectRateLimit[player.UserId] or 0
    if now - lastCollect < COLLECT_RATE_LIMIT then
        return false, "RATE_LIMITED", nil
    end
    _collectRateLimit[player.UserId] = now

    -- 2. Type validation
    if typeof(nodeId) ~= "string" then
        return false, "INVALID_NODE_ID", nil
    end

    -- 3. Validate node exists
    local node = ResourceNodeData.GetNodeById(nodeId)
    if not node then
        return false, "NODE_NOT_FOUND", nil
    end

    -- 4. Validate player proximity (anti-exploit)
    local character = player.Character
    if not character then
        return false, "NO_CHARACTER", nil
    end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then
        return false, "NO_CHARACTER", nil
    end

    local playerPos = (humanoidRootPart :: BasePart).Position
    local nodePos = node.position
    -- Use horizontal distance only (ignore Y axis differences from terrain)
    local horizontalDistance = ((playerPos - nodePos) * Vector3.new(1, 0, 1)).Magnitude
    if horizontalDistance > MAX_COLLECT_DISTANCE then
        return false, "TOO_FAR", nil
    end

    -- 5. Check per-player cooldown
    local playerCooldowns = _playerCollections[player.UserId]
    if playerCooldowns then
        local lastCollected = playerCooldowns[nodeId]
        if lastCollected then
            local elapsed = os.time() - lastCollected
            if elapsed < node.respawnTime then
                return false, "ON_COOLDOWN", nil
            end
        end
    end

    -- 6. Validate DataService is available
    if not DataService then
        return false, "SERVICE_UNAVAILABLE", nil
    end

    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return false, "NO_PLAYER_DATA", nil
    end

    -- 7. Calculate random amount
    local amount = math.random(node.amount.min, node.amount.max)

    -- 8. Determine resource key from node type
    local typeConfig = ResourceNodeData.TypeConfig[node.type]
    if not typeConfig then
        return false, "INVALID_NODE_TYPE", nil
    end
    local resourceKey = typeConfig.resourceKey -- "gold", "wood", or "food"

    -- 9. Grant resources via DataService
    local changes = {}
    changes[resourceKey] = amount
    local updateSuccess = DataService:UpdateResources(player, changes)
    if not updateSuccess then
        return false, "UPDATE_FAILED", nil
    end

    -- 10. Record collection timestamp for per-player cooldown
    if not _playerCollections[player.UserId] then
        _playerCollections[player.UserId] = {}
    end
    _playerCollections[player.UserId][nodeId] = os.time()

    -- 11. Sync player HUD
    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    local syncEvent = eventsFolder and eventsFolder:FindFirstChild("SyncPlayerData")
    if syncEvent then
        local updatedData = DataService:GetPlayerData(player)
        if updatedData then
            (syncEvent :: RemoteEvent):FireClient(player, updatedData)
        end
    end

    -- 12. Fire event
    ResourceNodeService.NodeCollected:Fire(nodeId, player.UserId, node.type, amount)

    print(string.format(
        "[ResourceNodeService] Player %s collected %s node '%s': +%d %s",
        player.Name, node.type, nodeId, amount, resourceKey
    ))

    return true, node.type, amount
end

--[[
    Returns all nodes that a specific player can currently collect
    (nodes whose per-player cooldown has elapsed or was never collected).

    @param player Player - The player to check availability for
    @return {table} - Array of available node data with position, type, amount range
]]
function ResourceNodeService:GetActiveNodes(player: Player): {any}
    local activeNodes = {}
    local nowTime = os.time()
    local playerCooldowns = _playerCollections[player.UserId]

    for _, node in ResourceNodeData.Nodes do
        local isAvailable = true

        -- Check if player has a cooldown for this node
        if playerCooldowns then
            local lastCollected = playerCooldowns[node.id]
            if lastCollected then
                local elapsed = nowTime - lastCollected
                if elapsed < node.respawnTime then
                    isAvailable = false
                end
            end
        end

        if isAvailable then
            local typeConfig = ResourceNodeData.TypeConfig[node.type]
            table.insert(activeNodes, {
                id = node.id,
                type = node.type,
                displayName = typeConfig and typeConfig.displayName or node.type,
                position = node.position,
                amount = node.amount,
                respawnTime = node.respawnTime,
            })
        end
    end

    return activeNodes
end

--[[
    Checks if any of a player's collected nodes have respawned.
    Returns the list of node IDs that have respawned since last check.

    @param player Player - The player to check respawns for
    @return {string} - Array of node IDs that have respawned
]]
function ResourceNodeService:CheckRespawns(player: Player): {string}
    local respawned = {}
    local nowTime = os.time()
    local playerCooldowns = _playerCollections[player.UserId]

    if not playerCooldowns then
        return respawned
    end

    for nodeId, lastCollected in playerCooldowns do
        local node = ResourceNodeData.GetNodeById(nodeId)
        if node then
            local elapsed = nowTime - lastCollected
            if elapsed >= node.respawnTime then
                table.insert(respawned, nodeId)
                -- Clear the expired cooldown
                playerCooldowns[nodeId] = nil
            end
        else
            -- Node no longer exists in data, clean up
            playerCooldowns[nodeId] = nil
        end
    end

    -- Clean up empty player entry
    if next(playerCooldowns) == nil then
        _playerCollections[player.UserId] = nil
    end

    return respawned
end

return ResourceNodeService
