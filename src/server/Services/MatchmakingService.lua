--!strict
--[[
    MatchmakingService.lua

    Finds suitable opponents for players based on trophy count.
    Implements fair matchmaking with trophy range restrictions.

    SECURITY: All matchmaking is server-authoritative.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local BalanceConfig = require(ReplicatedStorage.Shared.Constants.BalanceConfig)

-- Forward declarations
local DataService

local MatchmakingService = {}
MatchmakingService.__index = MatchmakingService

-- Events
MatchmakingService.OpponentFound = Signal.new()
MatchmakingService.SearchFailed = Signal.new()

-- Private state
local _initialized = false

-- Search parameters
local TROPHY_RANGE_MIN = 200 -- Minimum trophy difference
local TROPHY_RANGE_MAX = 500 -- Maximum trophy difference
local SEARCH_TIMEOUT = 10 -- seconds
local MAX_SEARCH_ATTEMPTS = 5

-- Cache of online players for quick matching
local _onlinePlayersCache: {[number]: any} = {}
local _cacheExpiry = 0
local CACHE_DURATION = 30 -- seconds

-- AI opponent templates for when no real players available
local AIOpponents = {
    {
        userId = -1,
        username = "GoblinKing",
        trophies = 100,
        townHallLevel = 2,
        resources = { gold = 15000, wood = 12000, food = 8000 },
        buildings = {},
    },
    {
        userId = -2,
        username = "DragonLord",
        trophies = 300,
        townHallLevel = 3,
        resources = { gold = 35000, wood = 28000, food = 15000 },
        buildings = {},
    },
    {
        userId = -3,
        username = "ShadowArcher",
        trophies = 500,
        townHallLevel = 4,
        resources = { gold = 60000, wood = 50000, food = 25000 },
        buildings = {},
    },
    {
        userId = -4,
        username = "IronFist",
        trophies = 800,
        townHallLevel = 5,
        resources = { gold = 100000, wood = 85000, food = 40000 },
        buildings = {},
    },
    {
        userId = -5,
        username = "StormBringer",
        trophies = 1200,
        townHallLevel = 6,
        resources = { gold = 180000, wood = 150000, food = 70000 },
        buildings = {},
    },
    {
        userId = -6,
        username = "ThunderKnight",
        trophies = 1600,
        townHallLevel = 7,
        resources = { gold = 300000, wood = 250000, food = 120000 },
        buildings = {},
    },
    {
        userId = -7,
        username = "CrystalMage",
        trophies = 2000,
        townHallLevel = 8,
        resources = { gold = 500000, wood = 400000, food = 200000 },
        buildings = {},
    },
    {
        userId = -8,
        username = "LegendaryChief",
        trophies = 2500,
        townHallLevel = 9,
        resources = { gold = 800000, wood = 650000, food = 350000 },
        buildings = {},
    },
}

--[[
    Generates a random base layout for AI opponents.
]]
local function generateAIBaseLayout(townHallLevel: number): {[string]: any}
    local buildings = {}
    local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)

    -- Always have a Town Hall
    local thId = "th_" .. tostring(math.random(10000, 99999))
    buildings[thId] = {
        id = thId,
        type = "TownHall",
        level = townHallLevel,
        position = { x = 18, z = 18 },
        state = "Ready",
    }

    -- Add resource buildings based on TH level
    local resourceCount = math.min(townHallLevel * 2, 8)
    for i = 1, resourceCount do
        local goldMineId = "gm_" .. tostring(i) .. "_" .. tostring(math.random(1000, 9999))
        buildings[goldMineId] = {
            id = goldMineId,
            type = "GoldMine",
            level = math.min(i, townHallLevel),
            position = { x = 10 + (i % 4) * 3, z = 10 + math.floor(i / 4) * 3 },
            state = "Ready",
        }
    end

    -- Add storage buildings
    local storageCount = math.min(townHallLevel, 4)
    for i = 1, storageCount do
        local storageId = "gs_" .. tostring(i) .. "_" .. tostring(math.random(1000, 9999))
        buildings[storageId] = {
            id = storageId,
            type = "GoldStorage",
            level = math.min(i, townHallLevel),
            position = { x = 22 + (i % 2) * 4, z = 10 + math.floor(i / 2) * 4 },
            state = "Ready",
        }
    end

    -- Add defense buildings
    local defenseCount = math.min(townHallLevel * 2, 10)
    for i = 1, defenseCount do
        local defenseType = i % 2 == 0 and "Cannon" or "ArcherTower"
        local defenseId = "def_" .. tostring(i) .. "_" .. tostring(math.random(1000, 9999))
        buildings[defenseId] = {
            id = defenseId,
            type = defenseType,
            level = math.min(math.ceil(i / 2), townHallLevel),
            position = { x = 5 + (i % 5) * 6, z = 25 + math.floor(i / 5) * 5 },
            state = "Ready",
        }
    end

    -- Add walls
    local wallCount = townHallLevel * 10
    for i = 1, math.min(wallCount, 50) do
        local wallId = "wall_" .. tostring(i) .. "_" .. tostring(math.random(1000, 9999))
        -- Create a perimeter
        local angle = (i / wallCount) * math.pi * 2
        local radius = 12
        local x = 18 + math.floor(math.cos(angle) * radius)
        local z = 18 + math.floor(math.sin(angle) * radius)

        buildings[wallId] = {
            id = wallId,
            type = "Wall",
            level = math.min(math.ceil(townHallLevel / 2), 5),
            position = { x = math.clamp(x, 0, 39), z = math.clamp(z, 0, 39) },
            state = "Ready",
        }
    end

    return buildings
end

--[[
    Gets an AI opponent suitable for the player's trophy range.
]]
local function getAIOpponent(playerTrophies: number): any
    -- Find AI opponent closest to player's trophies
    local bestMatch = AIOpponents[1]
    local bestDiff = math.abs(bestMatch.trophies - playerTrophies)

    for _, ai in AIOpponents do
        local diff = math.abs(ai.trophies - playerTrophies)
        if diff < bestDiff then
            bestMatch = ai
            bestDiff = diff
        end
    end

    -- Clone and customize
    local opponent = table.clone(bestMatch)

    -- Add some randomness to resources
    opponent.resources = {
        gold = math.floor(opponent.resources.gold * (0.8 + math.random() * 0.4)),
        wood = math.floor(opponent.resources.wood * (0.8 + math.random() * 0.4)),
        food = math.floor(opponent.resources.food * (0.8 + math.random() * 0.4)),
    }

    -- Randomize trophies slightly
    opponent.trophies = opponent.trophies + math.random(-50, 50)

    -- Generate base layout
    opponent.buildings = generateAIBaseLayout(opponent.townHallLevel)

    -- Add username variation
    local suffixes = { "99", "Pro", "X", "Master", "Elite", "2024" }
    if math.random() > 0.5 then
        opponent.username = opponent.username .. suffixes[math.random(1, #suffixes)]
    end

    return opponent
end

--[[
    Refreshes the online players cache.
]]
local function refreshOnlineCache()
    local now = os.time()
    if now < _cacheExpiry then return end

    _onlinePlayersCache = {}

    for _, player in Players:GetPlayers() do
        local playerData = DataService:GetPlayerData(player)
        if playerData then
            _onlinePlayersCache[player.UserId] = {
                userId = player.UserId,
                username = player.Name,
                trophies = playerData.trophies or 0,
                townHallLevel = playerData.townHallLevel or 1,
                resources = playerData.resources,
                buildings = playerData.buildings,
                shield = playerData.shield,
            }
        end
    end

    _cacheExpiry = now + CACHE_DURATION
end

--[[
    Finds a real player opponent.
]]
local function findRealOpponent(attackerUserId: number, attackerTrophies: number): any?
    refreshOnlineCache()

    local candidates = {}

    for userId, data in _onlinePlayersCache do
        -- Skip self
        if userId == attackerUserId then continue end

        -- Skip shielded players
        if data.shield and data.shield.active then
            local now = os.time()
            if data.shield.expiresAt > now then continue end
        end

        -- Check trophy range
        local trophyDiff = math.abs(data.trophies - attackerTrophies)
        if trophyDiff <= TROPHY_RANGE_MAX then
            table.insert(candidates, {
                data = data,
                trophyDiff = trophyDiff,
            })
        end
    end

    if #candidates == 0 then return nil end

    -- Sort by trophy difference (closer = better match)
    table.sort(candidates, function(a, b)
        return a.trophyDiff < b.trophyDiff
    end)

    -- Pick from top candidates with some randomness
    local pickIndex = math.random(1, math.min(3, #candidates))
    return candidates[pickIndex].data
end

--[[
    Finds an opponent for a player.
]]
function MatchmakingService:FindOpponent(player: Player): any
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return nil, "NO_PLAYER_DATA"
    end

    local playerTrophies = playerData.trophies or 0

    -- Try to find a real opponent first
    local realOpponent = findRealOpponent(player.UserId, playerTrophies)
    if realOpponent then
        print(string.format("[Matchmaking] Found real opponent for %s: %s",
            player.Name, realOpponent.username))
        return realOpponent
    end

    -- Fall back to AI opponent
    local aiOpponent = getAIOpponent(playerTrophies)
    print(string.format("[Matchmaking] Assigned AI opponent for %s: %s",
        player.Name, aiOpponent.username))

    return aiOpponent
end

--[[
    Skips to next opponent (costs gold or is free).
]]
function MatchmakingService:NextOpponent(player: Player, searchCount: number): any
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return nil, "NO_PLAYER_DATA"
    end

    -- Calculate skip cost (first few are free)
    local skipCost = 0
    if searchCount > 3 then
        skipCost = (searchCount - 3) * 100 -- 100 gold per skip after 3 free
    end

    if skipCost > 0 then
        if not DataService:CanAfford(player, { gold = skipCost } :: any) then
            return nil, "INSUFFICIENT_GOLD"
        end
        DataService:DeductResources(player, { gold = skipCost } :: any)
    end

    return self:FindOpponent(player)
end

--[[
    Gets the cost to skip to next opponent.
]]
function MatchmakingService:GetSkipCost(searchCount: number): number
    if searchCount <= 3 then
        return 0
    end
    return (searchCount - 3) * 100
end

--[[
    Checks if a player can be attacked (not shielded).
]]
function MatchmakingService:CanBeAttacked(targetUserId: number): boolean
    local player = Players:GetPlayerByUserId(targetUserId)
    if not player then
        -- Offline player - check stored data
        -- For AI opponents, always attackable
        if targetUserId < 0 then
            return true
        end
        return true -- Offline players can be attacked
    end

    local playerData = DataService:GetPlayerData(player)
    if not playerData then return false end

    -- Check shield
    if playerData.shield and playerData.shield.active then
        local now = os.time()
        if playerData.shield.expiresAt > now then
            return false
        end
    end

    return true
end

--[[
    Gets opponent data for battle (includes full base layout).
]]
function MatchmakingService:GetOpponentBattleData(opponentUserId: number): any?
    -- AI opponent
    if opponentUserId < 0 then
        -- Find matching AI
        for _, ai in AIOpponents do
            if ai.userId == opponentUserId then
                local opponent = table.clone(ai)
                opponent.buildings = generateAIBaseLayout(opponent.townHallLevel)
                return opponent
            end
        end
        return nil
    end

    -- Real player
    local player = Players:GetPlayerByUserId(opponentUserId)
    if player then
        local playerData = DataService:GetPlayerData(player)
        if playerData then
            return {
                userId = opponentUserId,
                username = player.Name,
                trophies = playerData.trophies,
                townHallLevel = playerData.townHallLevel,
                resources = playerData.resources,
                buildings = playerData.buildings,
            }
        end
    end

    -- TODO: Load offline player data from DataStore
    return nil
end

--[[
    Initializes the MatchmakingService.
]]
function MatchmakingService:Init()
    if _initialized then
        warn("MatchmakingService already initialized")
        return
    end

    -- Get service references
    local ServerScriptService = game:GetService("ServerScriptService")
    DataService = require(ServerScriptService.Services.DataService)

    _initialized = true
    print("MatchmakingService initialized")
end

return MatchmakingService
