--!strict
--[[
    VillageStateService.lua

    Serializes and persists per-player village state to DataStore.
    Handles loading saved state on server startup and saving on shutdown/leave.

    Village state includes: building levels, equipment levels, worker counts,
    smelter/sawmill queues, crop progress, prospecting state, and farm data.

    Worker NPC Models are NOT saved — only counts. NPCs are reconstructed on load.
    Transient per-player carrying state (playerOre, playerGold) is NOT saved.

    SECURITY: All operations are server-authoritative.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local VillageStateService = {}
VillageStateService.__index = VillageStateService

-- Constants
local DATASTORE_NAME = "BattleTycoon_VillageState_v1"
local LOCK_DATASTORE_NAME = "BattleTycoon_VillageLock"
local AUTO_SAVE_INTERVAL = 300 -- 5 minutes
local SESSION_LOCK_TIMEOUT = 120 -- 2 minutes
local CURRENT_VERSION = 1
local SAVE_MAX_RETRIES = 3
local SAVE_RETRY_BASE_DELAY = 1 -- seconds (exponential backoff: 1, 2, 4)

-- Private state
local _initialized = false
local _ownerUserId: number? = nil
local _loadedState: any = nil
local _dataStore: any = nil
local _lockStore: any = nil
local _useLocalData = false
local _sessionLocked = false
local _autoSaveThread: thread? = nil
local _stateTablesRef: any = nil -- Reference to SimpleTest state tables
local _loadFailed = false -- True if DataStore load errored (prevents overwriting saved data)

-- Try to get DataStore
local success, result = pcall(function()
    return DataStoreService:GetDataStore(DATASTORE_NAME)
end)

if success then
    _dataStore = result
else
    _useLocalData = true
    warn("[VillageStateService] DataStore unavailable, using local-only mode")
end

local lockSuccess, lockResult = pcall(function()
    return DataStoreService:GetDataStore(LOCK_DATASTORE_NAME)
end)

if lockSuccess then
    _lockStore = lockResult
end

-- ============================================================================
-- SESSION LOCKING (prevents two servers loading same village)
-- ============================================================================

local function acquireVillageLock(userId: number): boolean
    if _useLocalData then
        _sessionLocked = true
        return true
    end

    if not _lockStore then return true end

    local lockKey = "VillageLock_" .. userId
    local acquired = false
    local now = os.time()

    local lockSuccess2, lockErr = pcall(function()
        _lockStore:UpdateAsync(lockKey, function(currentValue)
            if not currentValue or (now - currentValue) >= SESSION_LOCK_TIMEOUT then
                acquired = true
                return now
            end
            acquired = false
            return nil
        end)
    end)

    if not lockSuccess2 then
        warn("[VillageStateService] Failed to acquire village lock:", lockErr)
        return false
    end

    _sessionLocked = acquired
    return acquired
end

local function releaseVillageLock(userId: number)
    if _useLocalData or not _lockStore then
        _sessionLocked = false
        return
    end

    local lockKey = "VillageLock_" .. userId
    pcall(function()
        _lockStore:RemoveAsync(lockKey)
    end)
    _sessionLocked = false
end

local function refreshVillageLock(userId: number)
    if _useLocalData or not _lockStore then return end

    local lockKey = "VillageLock_" .. userId
    pcall(function()
        _lockStore:SetAsync(lockKey, os.time())
    end)
end

-- ============================================================================
-- DEFAULT STATE
-- ============================================================================

local function createDefaultState(userId: number): any
    return {
        version = CURRENT_VERSION,
        ownerId = userId,
        accessCode = nil,
        lastActiveAt = os.time(),

        goldMine = {
            level = 1,
            xp = 0,
            equipment = {
                pickaxeLevel = 1,
                smelterLevel = 1,
                minerLevel = 1,
                collectorLevel = 1,
            },
            minerCount = 0,
            collectorCount = 0,
            smelterOre = 0,
            smelterGold = 0,
            chestGold = 0,
            prospecting = {
                isActive = false,
                tier = nil,
                startTime = 0,
                endTime = 0,
            },
        },

        lumberMill = {
            level = 1,
            xp = 0,
            equipment = {
                axeLevel = 1,
                sawmillLevel = 1,
                loggerLevel = 1,
                haulerLevel = 1,
            },
            loggerCount = 0,
            haulerCount = 0,
            sawmillLogs = 0,
            woodStorage = 0,
            treeStages = {}, -- [treeId] = stage (1-4)
            treeRespawnTimes = {}, -- [treeId] = os.time() when tree respawns
        },

        farms = {}, -- [farmNumber] = { level, xp, equipment, farmerCount, carrierCount, plots, harvestPile, windmillCrops, foodStorage }

        barracks = {
            level = 1,
            xp = 0,
            xpToNextLevel = 100,
            equipment = {
                dummies = "Basic",
                weapons = "Basic",
                armor = "Basic",
            },
            drillSergeantCount = 0,
            totalTroopsTrained = 0,
        },

        townHall = {
            level = 1,
            xp = 0,
            xpToNextLevel = 100,
            jewelCase = {
                slots = {},
                maxSlots = 3,
            },
            buildingLevels = {
                goldMine = 1,
                lumberMill = 1,
                barracks = 1,
                farm1 = 1,
                farm2 = 1,
                farm3 = 1,
                farm4 = 1,
                farm5 = 1,
                farm6 = 1,
            },
            shields = {
                isActive = false,
                duration = 0,
                endTime = 0,
            },
            research = {
                completed = {},
                inProgress = nil,
            },
            population = 10,
        },

        farmData = {
            farmPlots = 1,
            builtFarms = { [1] = true },
        },
    }
end

local function createDefaultFarmState(farmNumber: number): any
    return {
        farmNumber = farmNumber,
        level = 1,
        xp = 0,
        equipment = {
            hoeLevel = 1,
            wateringCanLevel = 1,
            windmillLevel = 1,
            farmerLevel = 1,
            carrierLevel = 1,
        },
        farmerCount = 0,
        carrierCount = 0,
        plots = {},
        harvestPile = 0,
        windmillCrops = 0,
        foodStorage = 0,
    }
end

-- ============================================================================
-- SERIALIZATION (Live State → Saveable Data)
-- ============================================================================

--[[
    Reads from the live SimpleTest state tables and serializes
    into a flat VillageStateData structure for DataStore persistence.
]]
function VillageStateService:SerializeState(): any
    if not _ownerUserId then
        warn("[VillageStateService] Cannot serialize: no owner set")
        return nil
    end

    local tables = _stateTablesRef
    if not tables then
        warn("[VillageStateService] Cannot serialize: no state tables reference")
        return nil
    end

    local GoldMineState = tables.GoldMineState
    local LumberMillState = tables.LumberMillState
    local FarmStates = tables.FarmStates
    local BarracksState = tables.BarracksState
    local TownHallState = tables.TownHallState
    local PlayerFarmData = tables.PlayerFarmData

    local state = createDefaultState(_ownerUserId)
    state.lastActiveAt = os.time()

    -- Gold Mine
    if GoldMineState then
        state.goldMine.level = GoldMineState.level or 1
        state.goldMine.xp = GoldMineState.xp or 0
        state.goldMine.equipment = {
            pickaxeLevel = GoldMineState.equipment.pickaxeLevel or 1,
            smelterLevel = GoldMineState.equipment.smelterLevel or 1,
            minerLevel = GoldMineState.equipment.minerLevel or 1,
            collectorLevel = GoldMineState.equipment.collectorLevel or 1,
        }
        state.goldMine.minerCount = #(GoldMineState.miners or {})
        state.goldMine.collectorCount = #(GoldMineState.collectors or {})
        state.goldMine.smelterOre = GoldMineState.smelterOre or 0
        state.goldMine.smelterGold = GoldMineState.smelterGold or 0
        state.goldMine.chestGold = GoldMineState.chestGold or 0
        if GoldMineState.prospecting then
            state.goldMine.prospecting = {
                isActive = GoldMineState.prospecting.isActive or false,
                tier = GoldMineState.prospecting.tier,
                startTime = GoldMineState.prospecting.startTime or 0,
                endTime = GoldMineState.prospecting.endTime or 0,
            }
        end
    end

    -- Lumber Mill
    if LumberMillState then
        state.lumberMill.level = LumberMillState.level or 1
        state.lumberMill.xp = LumberMillState.xp or 0
        state.lumberMill.equipment = {
            axeLevel = LumberMillState.equipment.axeLevel or 1,
            sawmillLevel = LumberMillState.equipment.sawmillLevel or 1,
            loggerLevel = LumberMillState.equipment.loggerLevel or 1,
            haulerLevel = LumberMillState.equipment.haulerLevel or 1,
        }
        state.lumberMill.loggerCount = #(LumberMillState.loggers or {})
        state.lumberMill.haulerCount = #(LumberMillState.haulers or {})
        state.lumberMill.sawmillLogs = LumberMillState.sawmillLogs or 0
        state.lumberMill.woodStorage = LumberMillState.woodStorage or 0

        -- Save tree stages (for offline growth/respawn)
        if LumberMillState.treeStage then
            for treeId, stage in LumberMillState.treeStage do
                state.lumberMill.treeStages[tostring(treeId)] = stage
            end
        end
        if LumberMillState.treeRespawn then
            for treeId, respawnTime in LumberMillState.treeRespawn do
                state.lumberMill.treeRespawnTimes[tostring(treeId)] = respawnTime
            end
        end
    end

    -- Farms
    if FarmStates then
        for farmNumber, farmState in FarmStates do
            local farmData = createDefaultFarmState(farmNumber)
            farmData.level = farmState.level or 1
            farmData.xp = farmState.xp or 0
            farmData.equipment = {
                hoeLevel = farmState.equipment.hoeLevel or 1,
                wateringCanLevel = farmState.equipment.wateringCanLevel or 1,
                windmillLevel = farmState.equipment.windmillLevel or 1,
                farmerLevel = farmState.equipment.farmerLevel or 1,
                carrierLevel = farmState.equipment.carrierLevel or 1,
            }
            farmData.farmerCount = #(farmState.farmers or {})
            farmData.carrierCount = #(farmState.carriers or {})
            farmData.harvestPile = farmState.harvestPile or 0
            farmData.windmillCrops = farmState.windmillCrops or 0
            farmData.foodStorage = farmState.foodStorage or 0

            -- Save plot states (crop type, stage, watered, plantedAt)
            if farmState.plots then
                for plotId, plotData in farmState.plots do
                    farmData.plots[tostring(plotId)] = {
                        crop = plotData.crop,
                        stage = plotData.stage,
                        watered = plotData.watered,
                        plantedAt = plotData.plantedAt or os.time(),
                    }
                end
            end

            state.farms[tostring(farmNumber)] = farmData
        end
    end

    -- Barracks
    if BarracksState then
        state.barracks.level = BarracksState.level or 1
        state.barracks.xp = BarracksState.xp or 0
        state.barracks.xpToNextLevel = BarracksState.xpToNextLevel or 100
        state.barracks.equipment = {
            dummies = BarracksState.equipment.dummies or "Basic",
            weapons = BarracksState.equipment.weapons or "Basic",
            armor = BarracksState.equipment.armor or "Basic",
        }
        state.barracks.drillSergeantCount = #(BarracksState.drillSergeants or {})
        state.barracks.totalTroopsTrained = BarracksState.totalTroopsTrained or 0
    end

    -- Town Hall
    if TownHallState then
        state.townHall.level = TownHallState.level or 1
        state.townHall.xp = TownHallState.xp or 0
        state.townHall.xpToNextLevel = TownHallState.xpToNextLevel or 100
        state.townHall.population = TownHallState.population or 10

        if TownHallState.jewelCase then
            state.townHall.jewelCase = {
                slots = {},
                maxSlots = TownHallState.jewelCase.maxSlots or 3,
            }
            -- Serialize jewel slots (strip non-serializable Color3)
            for slotIdx, slotData in TownHallState.jewelCase.slots do
                if slotData then
                    state.townHall.jewelCase.slots[tostring(slotIdx)] = {
                        type = slotData.type,
                        size = slotData.size,
                        boost = slotData.boost,
                        multiplier = slotData.multiplier,
                        -- Color3 → RGB table for serialization
                        color = slotData.color and {
                            r = math.floor(slotData.color.R * 255),
                            g = math.floor(slotData.color.G * 255),
                            b = math.floor(slotData.color.B * 255),
                        } or nil,
                    }
                end
            end
        end

        if TownHallState.buildingLevels then
            state.townHall.buildingLevels = {}
            for k, v in TownHallState.buildingLevels do
                state.townHall.buildingLevels[k] = v
            end
        end

        if TownHallState.shields then
            state.townHall.shields = {
                isActive = TownHallState.shields.isActive or false,
                duration = TownHallState.shields.duration or 0,
                endTime = TownHallState.shields.endTime or 0,
            }
        end

        if TownHallState.research then
            state.townHall.research = {
                completed = TownHallState.research.completed or {},
                inProgress = nil,
            }
            -- Convert tick()-based research times to os.time() for cross-session persistence
            if TownHallState.research.inProgress then
                local ip = TownHallState.research.inProgress
                local now = tick()
                local remainingTime = math.max(0, (ip.endTime or 0) - now)
                state.townHall.research.inProgress = {
                    id = ip.id,
                    remainingTime = remainingTime, -- seconds left (tick-independent)
                    savedAt = os.time(),
                }
            end
        end
    end

    -- Farm Data (player-level farm plot purchases)
    if PlayerFarmData and _ownerUserId then
        local ownerFarmData = PlayerFarmData[_ownerUserId]
        if ownerFarmData then
            state.farmData = {
                farmPlots = ownerFarmData.farmPlots or 1,
                builtFarms = {},
            }
            for k, v in ownerFarmData.builtFarms or {} do
                state.farmData.builtFarms[tostring(k)] = v
            end
        end
    end

    return state
end

-- ============================================================================
-- PERSISTENCE (DataStore Read/Write)
-- ============================================================================

--[[
    Initializes the service for a specific owner.
    Loads their village state from DataStore if it exists.
]]
function VillageStateService:Init(ownerUserId: number)
    if _initialized then
        warn("[VillageStateService] Already initialized")
        return
    end

    _ownerUserId = ownerUserId
    print(string.format("[VillageStateService] Initializing for owner %d", ownerUserId))

    -- Acquire session lock
    if not acquireVillageLock(ownerUserId) then
        warn("[VillageStateService] Could not acquire village lock, using default state")
        _loadedState = nil
        _initialized = true
        return
    end

    -- Load from DataStore
    if _useLocalData then
        _loadedState = nil
        _initialized = true
        print("[VillageStateService] Local mode: no saved state to load")
        return
    end

    local loadSuccess, loadResult = pcall(function()
        return _dataStore:GetAsync(tostring(ownerUserId))
    end)

    if loadSuccess and loadResult then
        -- Validate version
        if loadResult.version and loadResult.version <= CURRENT_VERSION then
            _loadedState = loadResult
            print(string.format("[VillageStateService] Loaded saved village state (v%d) for %d",
                loadResult.version or 0, ownerUserId))
        else
            warn(string.format("[VillageStateService] Unknown state version %s, using default",
                tostring(loadResult.version)))
            _loadedState = nil
        end
    elseif loadSuccess then
        print(string.format("[VillageStateService] No saved state for %d (new village)", ownerUserId))
        _loadedState = nil
    else
        warn(string.format("[VillageStateService] DataStore load error: %s", tostring(loadResult)))
        _loadedState = nil
        _loadFailed = true -- Prevent overwriting potentially valid saved data
    end

    _initialized = true
end

--[[
    Returns the loaded village state (from DataStore), or nil if new village.
]]
function VillageStateService:GetLoadedState(): any
    return _loadedState
end

--[[
    Returns the owner's user ID.
]]
function VillageStateService:GetOwnerUserId(): number?
    return _ownerUserId
end

--[[
    Sets the reference to SimpleTest's live state tables.
    Must be called by SimpleTest after state tables are created.
]]
function VillageStateService:SetStateTables(tables: any)
    _stateTablesRef = tables
    print("[VillageStateService] State tables reference set")
end

--[[
    Serializes current live state and saves to DataStore.
]]
function VillageStateService:SaveState(): boolean
    if not _ownerUserId then
        warn("[VillageStateService] Cannot save: no owner set")
        return false
    end

    -- Guard: If the initial DataStore load failed, do NOT overwrite
    -- potentially valid saved data with a fresh default state
    if _loadFailed then
        warn("[VillageStateService] Skipping save: initial load failed, refusing to overwrite potential saved data")
        return false
    end

    local state = self:SerializeState()
    if not state then
        warn("[VillageStateService] Serialization failed, cannot save")
        return false
    end

    if _useLocalData then
        print("[VillageStateService] Local mode: state serialized but not persisted")
        return true
    end

    -- Retry with exponential backoff
    for attempt = 1, SAVE_MAX_RETRIES do
        local saveSuccess, saveErr = pcall(function()
            _dataStore:SetAsync(tostring(_ownerUserId), state)
        end)

        if saveSuccess then
            print(string.format("[VillageStateService] Saved village state for %d (attempt %d)", _ownerUserId, attempt))
            -- Refresh lock to prevent it from expiring during long sessions
            refreshVillageLock(_ownerUserId)
            return true
        else
            warn(string.format("[VillageStateService] Save attempt %d/%d failed: %s",
                attempt, SAVE_MAX_RETRIES, tostring(saveErr)))
            if attempt < SAVE_MAX_RETRIES then
                local delay = SAVE_RETRY_BASE_DELAY * (2 ^ (attempt - 1))
                task.wait(delay)
            end
        end
    end

    warn(string.format("[VillageStateService] All %d save attempts failed for %d", SAVE_MAX_RETRIES, _ownerUserId))
    return false
end

--[[
    Sets the access code for this village's reserved server.
]]
function VillageStateService:SetAccessCode(code: string)
    if _loadedState then
        _loadedState.accessCode = code
    end
end

--[[
    Gets the access code for this village's reserved server.
]]
function VillageStateService:GetAccessCode(): string?
    if _loadedState then
        return _loadedState.accessCode
    end
    return nil
end

-- ============================================================================
-- AUTO-SAVE LOOP
-- ============================================================================

--[[
    Starts the auto-save loop. Should be called after Init + state tables are set.
]]
function VillageStateService:StartAutoSave()
    if _autoSaveThread then return end

    _autoSaveThread = task.spawn(function()
        while _initialized do
            task.wait(AUTO_SAVE_INTERVAL)
            if _stateTablesRef and _ownerUserId then
                print("[VillageStateService] Auto-saving...")
                self:SaveState()
            end
        end
    end)

    print("[VillageStateService] Auto-save loop started (every " .. AUTO_SAVE_INTERVAL .. "s)")
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

--[[
    Final save and release lock. Call in BindToClose or on owner leave.
]]
function VillageStateService:Shutdown()
    if not _ownerUserId then return end

    print(string.format("[VillageStateService] Shutting down for owner %d", _ownerUserId))

    -- Final save
    if _stateTablesRef then
        self:SaveState()
    end

    -- Release lock
    releaseVillageLock(_ownerUserId)

    _initialized = false
end

return VillageStateService
