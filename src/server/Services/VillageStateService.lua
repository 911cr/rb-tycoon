--!strict
--[[
    VillageStateService.lua

    Serializes per-player village state into DataService's playerData.
    ONE DataStore, ONE session lock, ONE save cycle — all managed by DataService.

    Village state includes: building levels, equipment levels, worker counts,
    smelter/sawmill queues, crop progress, prospecting state, and farm data.

    Worker NPC Models are NOT saved — only counts. NPCs are reconstructed on load.
    Transient per-player carrying state (playerOre, playerGold) is NOT saved.

    SECURITY: All operations are server-authoritative.
]]

local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local VillageStateService = {}
VillageStateService.__index = VillageStateService

-- Constants
local AUTO_SAVE_INTERVAL = 300 -- 5 minutes
local CURRENT_VERSION = 1

-- Old DataStore names for one-time migration
local OLD_DATASTORE_NAME = "BattleTycoon_VillageState_v1"
local OLD_LOCK_DATASTORE_NAME = "BattleTycoon_VillageLock"

-- Private state
local _initialized = false
local _ownerUserId: number? = nil
local _loadedState: any = nil
local _autoSaveThread: thread? = nil
local _stateTablesRef: any = nil -- Reference to SimpleTest state tables
local _migrationAttempted = false
local _dataServiceRef: any = nil -- Lazy-loaded DataService reference

-- ============================================================================
-- HELPERS
-- ============================================================================

--[[
    Lazy-loads DataService to avoid require-time circular dependency.
]]
local function _getDataService(): any
    if _dataServiceRef then return _dataServiceRef end
    local ServicesFolder = ServerScriptService:FindFirstChild("Services")
    if ServicesFolder then
        local dsModule = ServicesFolder:FindFirstChild("DataService")
        if dsModule then
            local ok, ds = pcall(function() return require(dsModule) end)
            if ok then
                _dataServiceRef = ds
                return ds
            end
        end
    end
    return nil
end

--[[
    Gets the owner player's cached playerData from DataService.
]]
local function _getOwnerPlayerData(): any
    if not _ownerUserId then return nil end
    local DataService = _getDataService()
    if not DataService then return nil end
    local player = Players:GetPlayerByUserId(_ownerUserId)
    if not player then return nil end
    return DataService:GetPlayerData(player)
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
-- PERSISTENCE (via DataService's playerData)
-- ============================================================================

--[[
    Initializes the service for a specific owner.
    No DataStore access — just sets the owner ID.
    Data is loaded via GetLoadedState() which reads from DataService.
]]
function VillageStateService:Init(ownerUserId: number)
    if _initialized then
        warn("[VillageStateService] Already initialized")
        return
    end

    _ownerUserId = ownerUserId
    _initialized = true
    print(string.format("[VillageStateService] Initialized for owner %d (using DataService persistence)", ownerUserId))
end

--[[
    Returns the loaded village state, polling DataService for playerData.
    On first call, performs one-time migration from old DataStore if needed.
]]
function VillageStateService:GetLoadedState(): any
    if _loadedState then return _loadedState end
    if not _ownerUserId then return nil end

    -- Wait for DataService to have player data (up to 15s)
    local DataService = _getDataService()
    if not DataService then
        warn("[VillageStateService] DataService not available")
        return nil
    end

    local player, playerData
    local waitStart = os.clock()
    repeat
        player = Players:GetPlayerByUserId(_ownerUserId)
        if player then playerData = DataService:GetPlayerData(player) end
        if not playerData then task.wait(0.5) end
    until playerData or os.clock() - waitStart > 15

    if not playerData then
        warn(string.format("[VillageStateService] Timed out waiting for playerData for owner %d", _ownerUserId))
        return nil
    end

    -- Found in new location (DataService's playerData.villageState)
    if playerData.villageState then
        _loadedState = playerData.villageState
        print(string.format("[VillageStateService] Loaded village state from playerData (v%d) for %d",
            _loadedState.version or 0, _ownerUserId))
        return _loadedState
    end

    -- One-time migration from old DataStore
    if not _migrationAttempted then
        _migrationAttempted = true
        local oldStore = nil
        pcall(function()
            oldStore = DataStoreService:GetDataStore(OLD_DATASTORE_NAME)
        end)

        if oldStore then
            local migSuccess, migResult = pcall(function()
                return oldStore:GetAsync(tostring(_ownerUserId))
            end)

            if migSuccess and migResult and migResult.version then
                _loadedState = migResult
                playerData.villageState = migResult
                print(string.format("[VillageStateService] MIGRATION: Copied village state (v%d) from old DataStore for %d",
                    migResult.version or 0, _ownerUserId))

                -- Fire-and-forget cleanup of old DataStore keys
                task.spawn(function()
                    pcall(function()
                        oldStore:RemoveAsync(tostring(_ownerUserId))
                        print(string.format("[VillageStateService] MIGRATION: Removed old village state key for %d", _ownerUserId))
                    end)
                    -- Also clean up old lock key
                    pcall(function()
                        local oldLockStore = DataStoreService:GetDataStore(OLD_LOCK_DATASTORE_NAME)
                        if oldLockStore then
                            oldLockStore:RemoveAsync("VillageLock_" .. _ownerUserId)
                            print(string.format("[VillageStateService] MIGRATION: Removed old village lock key for %d", _ownerUserId))
                        end
                    end)
                end)

                return _loadedState
            elseif migSuccess then
                print(string.format("[VillageStateService] No old village state for %d (new village)", _ownerUserId))
            else
                warn(string.format("[VillageStateService] MIGRATION: Failed to read old DataStore for %d: %s",
                    _ownerUserId, tostring(migResult)))
            end
        end
    end

    return nil
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
    Serializes current live state into DataService's playerData (in-memory).
    DataService handles actual DataStore persistence on its save cycle.
]]
function VillageStateService:SaveState(): boolean
    if not _ownerUserId then
        warn("[VillageStateService] Cannot save: no owner set")
        return false
    end

    local state = self:SerializeState()
    if not state then
        warn("[VillageStateService] Serialization failed, cannot save")
        return false
    end

    local playerData = _getOwnerPlayerData()
    if playerData then
        playerData.villageState = state
        print(string.format("[VillageStateService] Serialized village state into playerData for %d", _ownerUserId))
        return true
    end

    warn(string.format("[VillageStateService] Cannot save: no playerData for owner %d", _ownerUserId))
    return false
end

--[[
    Sets the access code for this village's reserved server.
    Stored in DataService's playerData.villageAccessCode (already in schema).
]]
function VillageStateService:SetAccessCode(code: string)
    local pd = _getOwnerPlayerData()
    if pd then
        pd.villageAccessCode = code
    end
end

--[[
    Gets the access code for this village's reserved server.
]]
function VillageStateService:GetAccessCode(): string?
    local pd = _getOwnerPlayerData()
    return pd and pd.villageAccessCode
end

-- ============================================================================
-- AUTO-SAVE LOOP
-- ============================================================================

--[[
    Starts the auto-save loop and registers a pre-save callback with DataService.
    The pre-save callback ensures village state is always fresh before DataStore writes.
]]
function VillageStateService:StartAutoSave()
    if _autoSaveThread then return end

    -- Periodic serialize into playerData
    _autoSaveThread = task.spawn(function()
        while _initialized do
            task.wait(AUTO_SAVE_INTERVAL)
            if _stateTablesRef and _ownerUserId then
                print("[VillageStateService] Auto-serializing village state...")
                self:SaveState()
            end
        end
    end)

    -- Register pre-save callback so DataService always gets fresh village data
    -- This fires inside SavePlayerData() before every DataStore write
    local DataService = _getDataService()
    if DataService and DataService.RegisterPreSaveCallback then
        DataService:RegisterPreSaveCallback(function(player, data)
            if player.UserId == _ownerUserId and _stateTablesRef then
                local state = self:SerializeState()
                if state then
                    data.villageState = state
                end
            end
        end)
        print("[VillageStateService] Registered pre-save callback with DataService")
    end

    print("[VillageStateService] Auto-save loop started (every " .. AUTO_SAVE_INTERVAL .. "s)")
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

--[[
    Final serialize into playerData. DataService's own PlayerRemoving/BindToClose
    handles the actual DataStore write and session lock release.
]]
function VillageStateService:Shutdown()
    if not _ownerUserId then return end

    print(string.format("[VillageStateService] Shutting down for owner %d", _ownerUserId))

    -- Final serialize into playerData (DataService will persist it)
    if _stateTablesRef then
        self:SaveState()
    end

    _initialized = false
end

return VillageStateService
