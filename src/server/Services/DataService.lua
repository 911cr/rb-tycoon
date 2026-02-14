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
local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)
local WorldMapData = require(ReplicatedStorage.Shared.Constants.WorldMapData)
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
local _dataStore = nil
local _useLocalData = false -- True when DataStore is unavailable (Studio testing)
local _initialized = false

-- Try to get DataStore, fall back to local-only mode if unavailable
local success, result = pcall(function()
    return DataStoreService:GetDataStore("BattleTycoon_PlayerData_v1")
end)

if success then
    _dataStore = result
    print("[DataService] DataStore connected")
else
    _useLocalData = true
    warn("[DataService] DataStore unavailable, using local-only mode (data won't persist)")
end

-- Constants
local DATA_SAVE_INTERVAL = 300 -- 5 minutes
local SESSION_LOCK_KEY_PREFIX = "SessionLock_"
local SESSION_LOCK_TIMEOUT = 120 -- 2 minutes (reduced from 10 to handle crashes + teleport transitions)

--[[
    Sanitizes a number to prevent NaN/Infinity exploits.
    Per security rules: invalid numbers could corrupt player data.
]]
local function sanitizeNumber(value: number, default: number?): number
    default = default or 0
    -- Check for nil
    if value == nil then return default end
    -- Check for NaN (NaN ~= NaN is true)
    if value ~= value then return default end
    -- Check for infinity
    if value == math.huge or value == -math.huge then return default end
    return value
end

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
        armyCampCapacity = 20, -- Deprecated: kept for compatibility

        -- Food Supply System
        foodProduction = 0,
        foodUsage = 0,
        trainingPaused = false,
        farmPlots = 1,
        maxFarmPlots = BuildingData.MaxFarmPlotsPerTH[1] or 2,

        -- Builders
        builders = {
            { id = 1, busy = false, assignedBuildingId = nil, completesAt = nil },
        },
        maxBuilders = 1,

        -- Protection
        shield = nil,
        revengeList = {},
        defenseLog = {},

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

        -- World Map
        mapPosition = WorldMapData.GenerateStartingPosition(),
        lastMoveTime = 0,
        friends = {},
    }
end

--[[
    Validates and sanitizes loaded player data.
    Ensures all fields exist and are within valid ranges.
]]
local function validatePlayerData(data: Types.PlayerData): Types.PlayerData
    -- Ensure resources exist and are valid (sanitize for NaN/Infinity)
    data.resources = data.resources or {}
    data.resources.gold = math.max(0, sanitizeNumber(data.resources.gold, 0))
    data.resources.wood = math.max(0, sanitizeNumber(data.resources.wood, 0))
    data.resources.food = math.max(0, sanitizeNumber(data.resources.food, 0))

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

    -- Defense log migration
    if not data.defenseLog then data.defenseLog = {} end

    -- Food Supply System migration
    if data.foodProduction == nil then data.foodProduction = 0 end
    if data.foodUsage == nil then data.foodUsage = 0 end
    if data.trainingPaused == nil then data.trainingPaused = false end

    -- Set farmPlots based on existing farm count (migration)
    if data.farmPlots == nil then
        local farmCount = 0
        for _, building in data.buildings do
            if building.type == "Farm" then
                farmCount += 1
            end
        end
        data.farmPlots = math.max(1, farmCount)
    end

    -- Set maxFarmPlots based on TH level
    data.maxFarmPlots = BuildingData.MaxFarmPlotsPerTH[data.townHallLevel] or 2

    -- World Map migration
    if not data.mapPosition then
        data.mapPosition = WorldMapData.GenerateStartingPosition()
    else
        -- Validate position is within bounds
        if not WorldMapData.IsValidPosition(data.mapPosition) then
            data.mapPosition = WorldMapData.GenerateStartingPosition()
        end
    end

    if data.lastMoveTime == nil then
        data.lastMoveTime = 0
    end

    if not data.friends then
        data.friends = {}
    end

    return data
end

--[[
    Acquires a session lock for the player using atomic UpdateAsync.
    Prevents data corruption from multiple sessions.
    FIXED: Uses UpdateAsync for atomic check-and-set to prevent race conditions.
]]
local SESSION_LOCK_RETRIES = 3
local SESSION_LOCK_RETRY_DELAY = 2 -- seconds between retries

local function acquireSessionLock(userId: number): boolean
    -- In local mode, always succeed (no DataStore)
    if _useLocalData then
        _sessionLocks[userId] = os.time()
        return true
    end

    local lockKey = SESSION_LOCK_KEY_PREFIX .. userId
    local lockStore = DataStoreService:GetDataStore("BattleTycoon_SessionLocks")

    -- Retry loop: the previous server may still be releasing the lock (teleport race condition)
    for attempt = 1, SESSION_LOCK_RETRIES do
        local acquired = false
        local now = os.time()

        local success, err = pcall(function()
            lockStore:UpdateAsync(lockKey, function(currentValue)
                -- If no lock exists or lock is stale (> 10 minutes old), acquire it
                if not currentValue or (now - currentValue) >= SESSION_LOCK_TIMEOUT then
                    acquired = true
                    return now -- Set new lock timestamp
                end
                -- Lock is active, don't modify
                acquired = false
                return nil -- Return nil to cancel the update
            end)
        end)

        if not success then
            warn("Failed to acquire session lock for", userId, "attempt", attempt, err)
        elseif acquired then
            _sessionLocks[userId] = now
            return true
        end

        -- Wait before retrying (gives previous server time to release lock)
        if attempt < SESSION_LOCK_RETRIES then
            warn(string.format("[DataService] Session lock busy for %d, retrying in %ds (attempt %d/%d)",
                userId, SESSION_LOCK_RETRY_DELAY, attempt, SESSION_LOCK_RETRIES))
            task.wait(SESSION_LOCK_RETRY_DELAY)
        end
    end

    warn("Session lock still active for", userId, "after", SESSION_LOCK_RETRIES, "attempts")
    return false
end

--[[
    Releases the session lock for the player.
]]
local function releaseSessionLock(userId: number)
    -- In local mode, just clear local state
    if _useLocalData then
        _sessionLocks[userId] = nil
        return
    end

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

    -- In local mode, skip session lock and just create default data
    if _useLocalData then
        local data = _playerData[userId]
        if not data then
            data = createDefaultData(userId, username)
            _playerData[userId] = data
        end
        data.lastLoginAt = os.time()
        -- Calculate initial food supply state
        self:UpdateFoodSupplyState(player)
        DataService.PlayerDataLoaded:Fire(player, data)
        return {
            success = true,
            data = data,
            error = nil,
        }
    end

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

    -- Calculate initial food supply state
    self:UpdateFoodSupplyState(player)

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

    -- In local mode, data is only in memory (no persistence)
    if _useLocalData then
        DataService.PlayerDataSaved:Fire(player)
        return true
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
    Prepares player data for cross-place teleport.
    Saves data, releases session lock, and clears cache so the destination
    server can acquire the lock immediately without a race condition.

    MUST be called before TeleportService:TeleportAsync().
]]
function DataService:PrepareForTeleport(player: Player): boolean
    local userId = player.UserId

    -- Save data first
    local saved = self:SavePlayerData(player)
    if not saved then
        warn("[DataService] Failed to save before teleport for", userId)
        return false
    end

    -- Release session lock so destination server can acquire it
    releaseSessionLock(userId)

    -- Clear cached data (PlayerRemoving will fire later but find nothing to do)
    _playerData[userId] = nil

    print(string.format("[DataService] Player %s prepared for teleport (data saved, lock released)", player.Name))
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
    Saves player data by UserId directly to DataStore.
    Used for offline players whose data was modified (e.g., defender after a battle).
    Does NOT affect the in-memory cache (_playerData) for online players.
]]
function DataService:SavePlayerDataById(userId: number, data: any): boolean
    -- In local mode, data is only in memory (no persistence)
    if _useLocalData then
        return true
    end

    if not data then
        warn("[DataService] No data to save for userId", userId)
        return false
    end

    local success, err = pcall(function()
        _dataStore:SetAsync(tostring(userId), data)
    end)

    if not success then
        warn("[DataService] Failed to save offline data for userId", userId, err)
        return false
    end

    print(string.format("[DataService] Saved offline player data for userId %d", userId))
    return true
end

--[[
    Updates player resources (server-authoritative).
]]
function DataService:UpdateResources(player: Player, changes: Types.ResourceData): boolean
    local data = _playerData[player.UserId]
    if not data then return false end

    -- Apply changes with validation (sanitize for NaN/Infinity exploits)
    if changes.gold then
        local sanitizedGold = sanitizeNumber(changes.gold, 0)
        data.resources.gold = math.max(0, data.resources.gold + sanitizedGold)
        data.resources.gold = math.min(data.resources.gold, data.storageCapacity.gold)
    end

    if changes.wood then
        local sanitizedWood = sanitizeNumber(changes.wood, 0)
        data.resources.wood = math.max(0, data.resources.wood + sanitizedWood)
        data.resources.wood = math.min(data.resources.wood, data.storageCapacity.wood)
    end

    if changes.food then
        local sanitizedFood = sanitizeNumber(changes.food, 0)
        data.resources.food = math.max(0, data.resources.food + sanitizedFood)
        data.resources.food = math.min(data.resources.food, data.storageCapacity.food)
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

    -- Deduct
    data.resources.gold -= (cost.gold or 0)
    data.resources.wood -= (cost.wood or 0)
    data.resources.food -= (cost.food or 0)

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

    return true
end

--[[
    Calculates total food production per minute from all farms.
]]
function DataService:CalculateFoodProduction(player: Player): number
    local data = _playerData[player.UserId]
    if not data then return 0 end

    local totalProduction = 0
    local farmCount = 0
    local upgradingCount = 0

    for _, building in data.buildings do
        if building.type == "Farm" then
            if building.state ~= "Upgrading" then
                local levelData = BuildingData.GetLevelData("Farm", building.level)
                if levelData and levelData.productionRate then
                    -- productionRate is per hour, convert to per minute
                    totalProduction += levelData.productionRate / 60
                    farmCount += 1
                end
            else
                upgradingCount += 1
            end
        end
    end

    print(string.format("[FoodSupply] %s: %d farms producing, %d upgrading, total=%.1f/min",
        player.Name, farmCount, upgradingCount, totalProduction))

    return totalProduction
end

--[[
    Calculates total food usage per minute from all troops.
]]
function DataService:CalculateFoodUsage(player: Player): number
    local data = _playerData[player.UserId]
    if not data then return 0 end

    local totalUsage = 0

    for troopType, count in data.troops do
        local troopDef = TroopData.GetByType(troopType)
        if troopDef and troopDef.foodUpkeep then
            totalUsage += troopDef.foodUpkeep * count
        end
    end

    return totalUsage
end

--[[
    Updates the food supply state for a player.
    Should be called after any operation that affects farms or troops.
]]
function DataService:UpdateFoodSupplyState(player: Player)
    local data = _playerData[player.UserId]
    if not data then return end

    data.foodProduction = self:CalculateFoodProduction(player)
    data.foodUsage = self:CalculateFoodUsage(player)
    data.trainingPaused = data.foodUsage > data.foodProduction

    -- Update maxFarmPlots based on TH level
    data.maxFarmPlots = BuildingData.MaxFarmPlotsPerTH[data.townHallLevel] or 2

    -- Debug
    print(string.format("[FoodSupply] Player %s: Production=%.1f/min, Usage=%.1f/min, Paused=%s",
        player.Name, data.foodProduction, data.foodUsage, tostring(data.trainingPaused)))
end

--[[
    Gets the food supply status for a player.
]]
function DataService:GetFoodSupplyStatus(player: Player): {production: number, usage: number, paused: boolean}
    local data = _playerData[player.UserId]
    if not data then
        return { production = 0, usage = 0, paused = false }
    end

    return {
        production = data.foodProduction,
        usage = data.foodUsage,
        paused = data.trainingPaused,
    }
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

    -- Handle player leave (ALWAYS release lock, even if data wasn't loaded)
    Players.PlayerRemoving:Connect(function(player)
        if _playerData[player.UserId] then
            self:SavePlayerData(player)
            _playerData[player.UserId] = nil
        end
        -- Always release lock - prevents death loop where failed load → kick → lock never released
        releaseSessionLock(player.UserId)
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
