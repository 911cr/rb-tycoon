--!strict
--[[
    DataService.lua

    Manages player data persistence using DataStoreService.
    Implements session locking and data validation.

    SECURITY: All data operations are server-authoritative.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types.PlayerTypes)
local BalanceConfig = require(ReplicatedStorage.Shared.Constants.BalanceConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local DataService = {}
DataService.__index = DataService

-- Events
DataService.PlayerDataLoaded = Signal.new()
DataService.PlayerDataSaved = Signal.new()
DataService.PlayerDataError = Signal.new()

-- Private state
local _playerData: {[number]: Types.PlayerData} = {}
local _sessionLocks: {[number]: number} = {}
local _dataStore = DataStoreService:GetDataStore("BattleTycoon_PlayerData_v1")
local _initialized = false

-- Constants
local DATA_SAVE_INTERVAL = 300 -- 5 minutes
local SESSION_LOCK_KEY_PREFIX = "SessionLock_"

--[[
    Creates default player data for new players.
]]
local function createDefaultData(userId: number, username: string): Types.PlayerData
    local now = os.time()
    local startingResources = BalanceConfig.Economy.StartingResources

    return {
        -- Identity
        userId = userId,
        username = username,
        joinedAt = now,
        lastLoginAt = now,

        -- Resources
        resources = {
            gold = startingResources.gold,
            wood = startingResources.wood,
            food = startingResources.food,
            gems = startingResources.gems,
        },
        storageCapacity = {
            gold = 5000,
            wood = 5000,
            food = 3000,
        },

        -- Progression
        townHallLevel = 1,
        stats = {
            level = 1,
            xp = 0,
            xpToNextLevel = 30,
            attacksWon = 0,
            defensesWon = 0,
            troopsDestroyed = 0,
            buildingsDestroyed = 0,
        },
        trophies = {
            current = 0,
            season = 0,
            allTime = 0,
            league = "Unranked",
        },

        -- Buildings
        buildings = {},

        -- Military
        troops = {},
        spells = {},
        armyCampCapacity = 20,

        -- Builders
        builders = {
            { id = 1, busy = false, assignedBuildingId = nil, completesAt = nil },
        },
        maxBuilders = 1,

        -- Protection
        shield = nil,
        revengeList = {},

        -- Social
        alliance = {
            allianceId = nil,
            role = nil,
            joinedAt = nil,
            donationsThisWeek = 0,
            donationsReceived = 0,
        },

        -- Cities
        cities = {},
        activeCityId = "",

        -- Monetization
        vipActive = false,
        vipExpiresAt = nil,
        battlePassTier = 0,
        battlePassPremium = false,

        -- Settings
        settings = {
            musicEnabled = true,
            sfxEnabled = true,
            notificationsEnabled = true,
        },
    }
end

--[[
    Validates and sanitizes loaded player data.
    Ensures all fields exist and are within valid ranges.
]]
local function validatePlayerData(data: Types.PlayerData): Types.PlayerData
    -- Ensure resources exist and are valid
    data.resources = data.resources or {}
    data.resources.gold = math.max(0, data.resources.gold or 0)
    data.resources.wood = math.max(0, data.resources.wood or 0)
    data.resources.food = math.max(0, data.resources.food or 0)
    data.resources.gems = math.max(0, data.resources.gems or 0)

    -- Ensure progression is valid
    data.townHallLevel = math.clamp(data.townHallLevel or 1, 1, 10)

    -- Ensure stats exist
    data.stats = data.stats or {
        level = 1,
        xp = 0,
        xpToNextLevel = 30,
        attacksWon = 0,
        defensesWon = 0,
        troopsDestroyed = 0,
        buildingsDestroyed = 0,
    }

    -- Ensure trophies are valid
    data.trophies = data.trophies or { current = 0, season = 0, allTime = 0, league = "Unranked" }
    data.trophies.current = math.max(0, data.trophies.current or 0)

    -- Ensure buildings table exists
    data.buildings = data.buildings or {}

    -- Ensure military tables exist
    data.troops = data.troops or {}
    data.spells = data.spells or {}
    data.armyCampCapacity = math.max(20, data.armyCampCapacity or 20)

    -- Ensure builders exist
    if not data.builders or #data.builders == 0 then
        data.builders = {{ id = 1, busy = false, assignedBuildingId = nil, completesAt = nil }}
    end
    data.maxBuilders = math.clamp(data.maxBuilders or 1, 1, 5)

    -- Ensure cities exist
    data.cities = data.cities or {}
    data.activeCityId = data.activeCityId or ""

    -- Ensure settings exist
    data.settings = data.settings or { musicEnabled = true, sfxEnabled = true, notificationsEnabled = true }

    return data
end

--[[
    Acquires a session lock for the player.
    Prevents data corruption from multiple sessions.
]]
local function acquireSessionLock(userId: number): boolean
    local lockKey = SESSION_LOCK_KEY_PREFIX .. userId
    local lockStore = DataStoreService:GetDataStore("BattleTycoon_SessionLocks")

    local success, currentLock = pcall(function()
        return lockStore:GetAsync(lockKey)
    end)

    if not success then
        warn("Failed to check session lock for", userId)
        return false
    end

    local now = os.time()

    -- If lock exists and isn't stale (< 10 minutes old), deny
    if currentLock and (now - currentLock) < 600 then
        warn("Session lock active for", userId)
        return false
    end

    -- Acquire lock
    local setSuccess = pcall(function()
        lockStore:SetAsync(lockKey, now)
    end)

    if setSuccess then
        _sessionLocks[userId] = now
        return true
    end

    return false
end

--[[
    Releases the session lock for the player.
]]
local function releaseSessionLock(userId: number)
    local lockKey = SESSION_LOCK_KEY_PREFIX .. userId
    local lockStore = DataStoreService:GetDataStore("BattleTycoon_SessionLocks")

    pcall(function()
        lockStore:RemoveAsync(lockKey)
    end)

    _sessionLocks[userId] = nil
end

--[[
    Loads player data from DataStore.
]]
function DataService:LoadPlayerData(player: Player): Types.PlayerDataResult
    local userId = player.UserId
    local username = player.Name

    -- Acquire session lock
    if not acquireSessionLock(userId) then
        return {
            success = false,
            data = nil,
            error = "SESSION_LOCKED",
        }
    end

    -- Load from DataStore
    local success, result = pcall(function()
        return _dataStore:GetAsync(tostring(userId))
    end)

    if not success then
        releaseSessionLock(userId)
        warn("DataStore error loading", userId, result)
        return {
            success = false,
            data = nil,
            error = "DATASTORE_ERROR",
        }
    end

    local data: Types.PlayerData

    if result then
        -- Existing player
        data = validatePlayerData(result)
        data.lastLoginAt = os.time()
    else
        -- New player
        data = createDefaultData(userId, username)
    end

    -- Cache data
    _playerData[userId] = data

    -- Fire event
    DataService.PlayerDataLoaded:Fire(player, data)

    return {
        success = true,
        data = data,
        error = nil,
    }
end

--[[
    Saves player data to DataStore.
]]
function DataService:SavePlayerData(player: Player): boolean
    local userId = player.UserId
    local data = _playerData[userId]

    if not data then
        warn("No data to save for", userId)
        return false
    end

    local success, err = pcall(function()
        _dataStore:SetAsync(tostring(userId), data)
    end)

    if not success then
        warn("Failed to save data for", userId, err)
        DataService.PlayerDataError:Fire(player, "SAVE_FAILED")
        return false
    end

    DataService.PlayerDataSaved:Fire(player)
    return true
end

--[[
    Gets cached player data (server-side only).
]]
function DataService:GetPlayerData(player: Player): Types.PlayerData?
    return _playerData[player.UserId]
end

--[[
    Gets player data by UserId (for offline operations).
]]
function DataService:GetPlayerDataById(userId: number): Types.PlayerData?
    -- Check cache first
    if _playerData[userId] then
        return _playerData[userId]
    end

    -- Load from DataStore
    local success, result = pcall(function()
        return _dataStore:GetAsync(tostring(userId))
    end)

    if success and result then
        return validatePlayerData(result)
    end

    return nil
end

--[[
    Updates player resources (server-authoritative).
]]
function DataService:UpdateResources(player: Player, changes: Types.ResourceData): boolean
    local data = _playerData[player.UserId]
    if not data then return false end

    -- Apply changes with validation
    if changes.gold then
        data.resources.gold = math.max(0, data.resources.gold + changes.gold)
        data.resources.gold = math.min(data.resources.gold, data.storageCapacity.gold)
    end

    if changes.wood then
        data.resources.wood = math.max(0, data.resources.wood + changes.wood)
        data.resources.wood = math.min(data.resources.wood, data.storageCapacity.wood)
    end

    if changes.food then
        data.resources.food = math.max(0, data.resources.food + changes.food)
        data.resources.food = math.min(data.resources.food, data.storageCapacity.food)
    end

    if changes.gems then
        data.resources.gems = math.max(0, data.resources.gems + changes.gems)
        -- Gems have no cap
    end

    return true
end

--[[
    Deducts resources if player has enough.
]]
function DataService:DeductResources(player: Player, cost: Types.ResourceData): boolean
    local data = _playerData[player.UserId]
    if not data then return false end

    -- Check if player has enough
    if (cost.gold or 0) > data.resources.gold then return false end
    if (cost.wood or 0) > data.resources.wood then return false end
    if (cost.food or 0) > data.resources.food then return false end
    if (cost.gems or 0) > data.resources.gems then return false end

    -- Deduct
    data.resources.gold -= (cost.gold or 0)
    data.resources.wood -= (cost.wood or 0)
    data.resources.food -= (cost.food or 0)
    data.resources.gems -= (cost.gems or 0)

    return true
end

--[[
    Checks if player can afford a cost.
]]
function DataService:CanAfford(player: Player, cost: Types.ResourceData): boolean
    local data = _playerData[player.UserId]
    if not data then return false end

    if (cost.gold or 0) > data.resources.gold then return false end
    if (cost.wood or 0) > data.resources.wood then return false end
    if (cost.food or 0) > data.resources.food then return false end
    if (cost.gems or 0) > data.resources.gems then return false end

    return true
end

--[[
    Initializes the DataService.
]]
function DataService:Init()
    if _initialized then
        warn("DataService already initialized")
        return
    end

    -- Handle player join
    Players.PlayerAdded:Connect(function(player)
        local result = self:LoadPlayerData(player)

        if not result.success then
            player:Kick("Failed to load data: " .. (result.error or "Unknown error"))
        end
    end)

    -- Handle player leave
    Players.PlayerRemoving:Connect(function(player)
        self:SavePlayerData(player)
        releaseSessionLock(player.UserId)
        _playerData[player.UserId] = nil
    end)

    -- Auto-save interval
    task.spawn(function()
        while true do
            task.wait(DATA_SAVE_INTERVAL)
            for _, player in Players:GetPlayers() do
                self:SavePlayerData(player)
            end
        end
    end)

    -- Save all on shutdown
    game:BindToClose(function()
        for _, player in Players:GetPlayers() do
            self:SavePlayerData(player)
            releaseSessionLock(player.UserId)
        end
    end)

    _initialized = true
    print("DataService initialized")
end

return DataService
