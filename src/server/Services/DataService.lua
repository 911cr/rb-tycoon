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
local _teleportingPlayers: {[number]: boolean} = {} -- Players prepared for teleport (data saved, lock released)
local _dataStore = nil
local _useLocalData = false -- True when DataStore is unavailable (Studio testing)
local _initialized = false
local _preSaveCallbacks = {} -- Callbacks fired before every DataStore save

--[[
    Registers a callback fired before every DataStore save.
    Signature: callback(player: Player, data: PlayerData)
    Used by VillageStateService to serialize village state into playerData.
]]
function DataService:RegisterPreSaveCallback(callback)
    table.insert(_preSaveCallbacks, callback)
end

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
local SESSION_LOCK_TIMEOUT = 600 -- 10 minutes (must be > auto-save interval to prevent lock expiry between saves)
local LOCK_HEARTBEAT_INTERVAL = 60 -- Refresh lock every 60 seconds (independent of save cycle)
local SAVE_MAX_RETRIES = 3
local SAVE_RETRY_BASE_DELAY = 1 -- seconds (exponential backoff: 1, 2, 4)
local LOAD_MAX_RETRIES = 3
local LOAD_RETRY_DELAY = 2 -- seconds (exponential backoff: 2, 4, 8)

-- Unique session identifier for ownership-aware locking
local SESSION_ID = game.JobId .. "_" .. tostring(os.time())

-- User-friendly kick messages
local KICK_MESSAGES = {
    SESSION_LOCKED = "Your save data is being used by another server. Please wait a moment and rejoin!",
    DATASTORE_ERROR = "Couldn't reach Roblox save servers. Please try again in a minute!",
    LOAD_FAILED = "We couldn't load your save data after multiple tries. Please rejoin shortly!",
}

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

        -- Village Instance
        villageAccessCode = nil, -- Reserved server access code for private village
        villageState = nil, -- Populated by VillageStateService serialization
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

    -- If ALL resources are 0, grant starting resources so the player isn't stuck
    if data.resources.gold == 0 and data.resources.wood == 0 and data.resources.food == 0 then
        local startingResources = BalanceConfig.Economy.StartingResources
        data.resources.gold = startingResources.gold
        data.resources.wood = startingResources.wood
        data.resources.food = startingResources.food
        print(string.format("[DataService] Granted starting resources to player %d (all were 0)", data.userId or 0))
    end

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
    Lock value is { owner = SESSION_ID, timestamp = os.time() } for ownership-aware release.
]]
local SESSION_LOCK_RETRIES = 5
local SESSION_LOCK_RETRY_DELAY = 2 -- base seconds (exponential backoff: 2, 4, 8, 8)

local _lockStore = nil
pcall(function()
    _lockStore = DataStoreService:GetDataStore("BattleTycoon_SessionLocks")
end)

local function acquireSessionLock(userId: number): boolean
    -- In local mode, always succeed (no DataStore)
    if _useLocalData then
        _sessionLocks[userId] = os.time()
        return true
    end

    if not _lockStore then
        warn("[DataService] Lock store unavailable, proceeding without lock")
        return true
    end

    local lockKey = SESSION_LOCK_KEY_PREFIX .. userId

    -- Retry loop: the previous server may still be releasing the lock (teleport race condition)
    for attempt = 1, SESSION_LOCK_RETRIES do
        local acquired = false
        local now = os.time()

        local success, err = pcall(function()
            _lockStore:UpdateAsync(lockKey, function(currentValue)
                -- Lock value format: { owner = SESSION_ID, timestamp = os.time() }
                -- Legacy format: plain number (os.time()) — handle migration
                local lockTimestamp = 0
                if typeof(currentValue) == "table" then
                    lockTimestamp = currentValue.timestamp or 0
                elseif typeof(currentValue) == "number" then
                    lockTimestamp = currentValue -- Legacy format
                end

                -- If no lock exists or lock is stale (expired), acquire it
                if not currentValue or (now - lockTimestamp) >= SESSION_LOCK_TIMEOUT then
                    acquired = true
                    return { owner = SESSION_ID, timestamp = now }
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

        -- Wait before retrying with exponential backoff (gives previous server time to release lock)
        if attempt < SESSION_LOCK_RETRIES then
            local delay = SESSION_LOCK_RETRY_DELAY * math.min(2 ^ (attempt - 1), 4)
            warn(string.format("[DataService] Session lock busy for %d, retrying in %ds (attempt %d/%d)",
                userId, delay, attempt, SESSION_LOCK_RETRIES))
            task.wait(delay)
        end
    end

    warn("Session lock still active for", userId, "after", SESSION_LOCK_RETRIES, "attempts")
    return false
end

--[[
    Releases the session lock for the player.
    Ownership-aware: only clears the lock if we own it (our SESSION_ID matches).
    Uses UpdateAsync instead of RemoveAsync to prevent deleting another server's lock.
]]
local function releaseSessionLock(userId: number)
    -- In local mode, just clear local state
    if _useLocalData then
        _sessionLocks[userId] = nil
        return
    end

    if not _lockStore then
        _sessionLocks[userId] = nil
        return
    end

    local lockKey = SESSION_LOCK_KEY_PREFIX .. userId

    pcall(function()
        _lockStore:UpdateAsync(lockKey, function(currentValue)
            if typeof(currentValue) == "table" and currentValue.owner == SESSION_ID then
                -- We own this lock — mark as expired (timestamp = 0) so next acquirer gets it immediately
                return { owner = SESSION_ID, timestamp = 0 }
            end
            -- Not our lock (another server acquired it) — leave it alone
            return nil
        end)
    end)

    _sessionLocks[userId] = nil
end

--[[
    Refreshes the session lock timestamp to prevent expiry during long sessions.
    Only refreshes if we still own the lock.
]]
local function refreshSessionLock(userId: number)
    if _useLocalData or not _lockStore then return end

    local lockKey = SESSION_LOCK_KEY_PREFIX .. userId
    local now = os.time()

    pcall(function()
        _lockStore:UpdateAsync(lockKey, function(currentValue)
            if typeof(currentValue) == "table" and currentValue.owner == SESSION_ID then
                return { owner = SESSION_ID, timestamp = now }
            end
            -- Not our lock — don't touch it
            return nil
        end)
    end)
end

--[[
    Loads player data from DataStore.
]]
function DataService:LoadPlayerData(player: Player): Types.PlayerDataResult
    local userId = player.UserId
    local username = player.Name

    -- Already loaded (e.g., player joined before handler was connected and was
    -- loaded via the existing-players loop in Init). Return cached data.
    if _playerData[userId] then
        return {
            success = true,
            data = _playerData[userId],
            error = nil,
        }
    end

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

    -- Retry loop: handles temporary DataStore throttling and session locks from previous server
    local lastError = "UNKNOWN"

    for attempt = 1, LOAD_MAX_RETRIES do
        -- Player may have left during retry wait
        if not player.Parent then
            return { success = false, data = nil, error = "PLAYER_LEFT" }
        end

        -- Acquire session lock (has its own internal retries)
        if not acquireSessionLock(userId) then
            lastError = "SESSION_LOCKED"
            if attempt < LOAD_MAX_RETRIES then
                warn(string.format("[DataService] Load attempt %d/%d: session locked for %d, retrying in %ds",
                    attempt, LOAD_MAX_RETRIES, userId, LOAD_RETRY_DELAY * (2 ^ (attempt - 1))))
                task.wait(LOAD_RETRY_DELAY * (2 ^ (attempt - 1)))
                continue
            end
            -- Final attempt failed
            break
        end

        -- Load from DataStore
        local success, result = pcall(function()
            return _dataStore:GetAsync(tostring(userId))
        end)

        if not success then
            releaseSessionLock(userId)
            lastError = "DATASTORE_ERROR"
            warn(string.format("[DataService] Load attempt %d/%d failed for %d: %s",
                attempt, LOAD_MAX_RETRIES, userId, tostring(result)))
            if attempt < LOAD_MAX_RETRIES then
                task.wait(LOAD_RETRY_DELAY * (2 ^ (attempt - 1)))
                continue
            end
            break
        end

        -- Success! Process data
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

    -- All retries exhausted
    warn(string.format("[DataService] All %d load attempts failed for %d: %s", LOAD_MAX_RETRIES, userId, lastError))
    return {
        success = false,
        data = nil,
        error = lastError,
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

    -- Fire pre-save callbacks (e.g. VillageStateService serialization)
    for _, callback in _preSaveCallbacks do
        pcall(callback, player, data)
    end

    -- In local mode, data is only in memory (no persistence)
    if _useLocalData then
        DataService.PlayerDataSaved:Fire(player)
        return true
    end

    -- Retry with exponential backoff
    for attempt = 1, SAVE_MAX_RETRIES do
        local success, err = pcall(function()
            _dataStore:SetAsync(tostring(userId), data)
        end)

        if success then
            DataService.PlayerDataSaved:Fire(player)
            return true
        end

        warn(string.format("[DataService] Save attempt %d/%d failed for %d: %s",
            attempt, SAVE_MAX_RETRIES, userId, tostring(err)))

        if attempt < SAVE_MAX_RETRIES then
            local delay = SAVE_RETRY_BASE_DELAY * (2 ^ (attempt - 1))
            task.wait(delay)
        end
    end

    warn(string.format("[DataService] All %d save attempts failed for %d", SAVE_MAX_RETRIES, userId))
    DataService.PlayerDataError:Fire(player, "SAVE_FAILED")
    return false
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

    -- Mark as teleporting but keep data in cache.
    -- PlayerRemoving will skip save (already done) and just clean up.
    -- If teleport fails, CancelTeleportState() restores normal state.
    _teleportingPlayers[userId] = true

    print(string.format("[DataService] Player %s prepared for teleport (data saved, lock released)", player.Name))
    return true
end

--[[
    Cancels teleport state for a player whose teleport failed.
    Re-acquires the session lock so the player can keep playing on this server.
    Data is still in cache (PrepareForTeleport no longer clears it).

    MUST be called when:
    - TeleportService:Teleport() pcall fails
    - TeleportInitFailed fires (Roblox accepted call but teleport failed later)
]]
function DataService:CancelTeleportState(player: Player)
    local userId = player.UserId

    if not _teleportingPlayers[userId] then
        return -- Not in teleport state, nothing to cancel
    end

    _teleportingPlayers[userId] = nil

    -- Re-acquire session lock so we can keep saving data for this player
    local lockAcquired = acquireSessionLock(userId)
    if not lockAcquired then
        warn(string.format("[DataService] Failed to re-acquire lock for %s after cancelled teleport", player.Name))
    end

    print(string.format("[DataService] Cancelled teleport state for %s (lock %s)",
        player.Name, lockAcquired and "re-acquired" or "FAILED"))
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
    Saves all online player data and releases locks.
    Used for BindToClose and explicit shutdown calls.
]]
function DataService:SaveAllData()
    for _, player in Players:GetPlayers() do
        pcall(function()
            self:SavePlayerData(player)
        end)
        releaseSessionLock(player.UserId)
    end
    print("[DataService] SaveAllData complete")
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
            local friendlyMsg = KICK_MESSAGES[result.error] or KICK_MESSAGES.LOAD_FAILED
            player:Kick(friendlyMsg)
        end
    end)

    -- Load data for players who joined BEFORE this handler was connected.
    -- This happens in reserved servers (Players.PlayerAdded:Wait() in Main
    -- captures the first player before Init runs) and can happen in Studio
    -- if the player loads faster than service initialization.
    for _, player in Players:GetPlayers() do
        if not _playerData[player.UserId] then
            local result = self:LoadPlayerData(player)
            if result.success and result.data then
                -- Sync to client in case they already requested data and got nil
                local Events = ReplicatedStorage:FindFirstChild("Events")
                if Events then
                    local SyncPlayerData = Events:FindFirstChild("SyncPlayerData")
                    if SyncPlayerData then
                        SyncPlayerData:FireClient(player, result.data)
                    end
                end
                print(string.format("[DataService] Loaded data for existing player: %s", player.Name))
            else
                warn(string.format("[DataService] Failed to load data for existing player: %s", player.Name))
            end
        end
    end

    -- Handle player leave (ALWAYS release lock, even if data wasn't loaded)
    Players.PlayerRemoving:Connect(function(player)
        local userId = player.UserId

        if _teleportingPlayers[userId] then
            -- PrepareForTeleport already saved data and released lock.
            -- Just clean up cache and clear the flag.
            _playerData[userId] = nil
            _teleportingPlayers[userId] = nil
        elseif _playerData[userId] then
            self:SavePlayerData(player)
            _playerData[userId] = nil
        end
        -- Always release lock - prevents death loop where failed load → kick → lock never released
        releaseSessionLock(userId)
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

    -- Lock heartbeat: refresh session locks every 60s to prevent expiry during long sessions
    task.spawn(function()
        while true do
            task.wait(LOCK_HEARTBEAT_INTERVAL)
            for userId, _ in _sessionLocks do
                -- Skip players in teleport state (lock already released by PrepareForTeleport)
                if not _teleportingPlayers[userId] then
                    refreshSessionLock(userId)
                end
            end
        end
    end)

    -- Save all on shutdown
    game:BindToClose(function()
        self:SaveAllData()
    end)

    _initialized = true
    print("DataService initialized")
end

return DataService
