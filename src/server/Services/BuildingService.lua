--!strict
--[[
    BuildingService.lua

    Manages building placement, upgrades, and production.
    All operations are server-authoritative.

    SECURITY: Client sends requests, server validates and executes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Types = require(ReplicatedStorage.Shared.Types.BuildingTypes)
local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
local BalanceConfig = require(ReplicatedStorage.Shared.Constants.BalanceConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declaration for DataService
local DataService

local BuildingService = {}
BuildingService.__index = BuildingService

-- Events
BuildingService.BuildingPlaced = Signal.new()
BuildingService.BuildingUpgraded = Signal.new()
BuildingService.BuildingCollected = Signal.new()
BuildingService.UpgradeCompleted = Signal.new()

-- Private state
local _initialized = false

--[[
    Validates grid position is within bounds and on grid.
]]
local function isValidGridPosition(position: Vector3, buildingDef: any): boolean
    -- Check position is on grid (integer coordinates)
    if position.X ~= math.floor(position.X) then return false end
    if position.Z ~= math.floor(position.Z) then return false end

    -- Check within city bounds (40x40 grid)
    local citySize = 40
    if position.X < 0 or position.X + buildingDef.width > citySize then return false end
    if position.Z < 0 or position.Z + buildingDef.height > citySize then return false end

    return true
end

--[[
    Checks if position is occupied by another building.
]]
local function isPositionOccupied(playerData: any, position: Vector3, buildingDef: any, excludeId: string?): boolean
    for id, building in playerData.buildings do
        if excludeId and id == excludeId then continue end

        local otherDef = BuildingData.GetByType(building.type)
        if not otherDef then continue end

        -- Check AABB overlap
        local ax1, az1 = position.X, position.Z
        local ax2, az2 = ax1 + buildingDef.width, az1 + buildingDef.height

        local bx1, bz1 = building.position.X, building.position.Z
        local bx2, bz2 = bx1 + otherDef.width, bz1 + otherDef.height

        -- Check for overlap
        if ax1 < bx2 and ax2 > bx1 and az1 < bz2 and az2 > bz1 then
            return true
        end
    end

    return false
end

--[[
    Gets count of building type for player.
]]
local function getBuildingCount(playerData: any, buildingType: string): number
    local count = 0
    for _, building in playerData.buildings do
        if building.type == buildingType then
            count += 1
        end
    end
    return count
end

--[[
    Checks if player meets TH requirement for building.
]]
local function meetsTHRequirement(playerData: any, buildingDef: any): boolean
    return playerData.townHallLevel >= buildingDef.townHallRequired
end

--[[
    Gets maximum allowed count for building at current TH level.
]]
local function getMaxBuildingCount(playerData: any, buildingType: string): number
    local thLevel = playerData.townHallLevel
    local counts = BalanceConfig.Progression.BuildingCounts[thLevel]

    if counts and counts[buildingType] then
        return counts[buildingType]
    end

    -- Default to building definition max
    local def = BuildingData.GetByType(buildingType)
    return def and def.maxCount or 1
end

--[[
    Finds an available builder.
]]
local function findAvailableBuilder(playerData: any): any?
    for _, builder in playerData.builders do
        if not builder.busy then
            return builder
        end
    end
    return nil
end

--[[
    Places a new building.
]]
function BuildingService:PlaceBuilding(player: Player, buildingType: string, position: Vector3): Types.PlacementResult
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, building = nil, error = "NO_PLAYER_DATA" }
    end

    -- Get building definition
    local buildingDef = BuildingData.GetByType(buildingType)
    if not buildingDef then
        return { success = false, building = nil, error = "INVALID_BUILDING_TYPE" }
    end

    -- Check TH requirement
    if not meetsTHRequirement(playerData, buildingDef) then
        return { success = false, building = nil, error = "TH_TOO_LOW" }
    end

    -- Check building count limit
    local currentCount = getBuildingCount(playerData, buildingType)
    local maxCount = getMaxBuildingCount(playerData, buildingType)
    if currentCount >= maxCount then
        return { success = false, building = nil, error = "MAX_COUNT_REACHED" }
    end

    -- Validate position
    if not isValidGridPosition(position, buildingDef) then
        return { success = false, building = nil, error = "INVALID_POSITION" }
    end

    -- Check position not occupied
    if isPositionOccupied(playerData, position, buildingDef) then
        return { success = false, building = nil, error = "POSITION_OCCUPIED" }
    end

    -- Get level 1 data for cost
    local levelData = buildingDef.levels[1]
    if not levelData then
        return { success = false, building = nil, error = "NO_LEVEL_DATA" }
    end

    -- Check resources
    if not DataService:CanAfford(player, levelData.cost) then
        return { success = false, building = nil, error = "INSUFFICIENT_RESOURCES" }
    end

    -- Find available builder (skip for walls)
    local builder = nil
    if buildingDef.category ~= "wall" and levelData.buildTime > 0 then
        builder = findAvailableBuilder(playerData)
        if not builder then
            return { success = false, building = nil, error = "NO_BUILDER_AVAILABLE" }
        end
    end

    -- Deduct resources
    DataService:DeductResources(player, levelData.cost)

    -- Create building
    local buildingId = HttpService:GenerateGUID(false)
    local now = os.time()

    local building: Types.Building = {
        id = buildingId,
        type = buildingType,
        level = 1,
        position = position,
        rotation = 0,
        state = levelData.buildTime > 0 and "Upgrading" or "Idle",
        upgradeStartedAt = levelData.buildTime > 0 and now or nil,
        upgradeCompletesAt = levelData.buildTime > 0 and (now + levelData.buildTime) or nil,
        lastCollectedAt = now,
        storedAmount = 0,
        trainingQueue = {},
        maxHp = levelData.hp,
        currentHp = levelData.hp,
    }

    -- Assign builder
    if builder then
        builder.busy = true
        builder.assignedBuildingId = buildingId
        builder.completesAt = building.upgradeCompletesAt
    end

    -- Add to player data
    playerData.buildings[buildingId] = building

    -- Fire event
    BuildingService.BuildingPlaced:Fire(player, building)

    return { success = true, building = building, error = nil }
end

--[[
    Upgrades an existing building.
]]
function BuildingService:UpgradeBuilding(player: Player, buildingId: string): Types.UpgradeResult
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_PLAYER_DATA" }
    end

    local building = playerData.buildings[buildingId]
    if not building then
        return { success = false, error = "BUILDING_NOT_FOUND" }
    end

    -- Check not already upgrading
    if building.state == "Upgrading" then
        return { success = false, error = "ALREADY_UPGRADING" }
    end

    -- Get building definition
    local buildingDef = BuildingData.GetByType(building.type)
    if not buildingDef then
        return { success = false, error = "INVALID_BUILDING_TYPE" }
    end

    -- Check not at max level
    local nextLevel = building.level + 1
    local nextLevelData = buildingDef.levels[nextLevel]
    if not nextLevelData then
        return { success = false, error = "MAX_LEVEL_REACHED" }
    end

    -- Check TH gates next level
    local thGates = BalanceConfig.Progression.THBuildingGates[playerData.townHallLevel]
    if thGates and nextLevel > thGates.maxBuildingLevel then
        return { success = false, error = "TH_TOO_LOW" }
    end

    -- Check resources
    if not DataService:CanAfford(player, nextLevelData.cost) then
        return { success = false, error = "INSUFFICIENT_RESOURCES" }
    end

    -- Find available builder (skip for walls)
    local builder = nil
    if buildingDef.category ~= "wall" and nextLevelData.buildTime > 0 then
        builder = findAvailableBuilder(playerData)
        if not builder then
            return { success = false, error = "NO_BUILDER_AVAILABLE" }
        end
    end

    -- Deduct resources
    DataService:DeductResources(player, nextLevelData.cost)

    -- Start upgrade
    local now = os.time()
    building.state = "Upgrading"
    building.upgradeStartedAt = now
    building.upgradeCompletesAt = now + nextLevelData.buildTime

    -- Assign builder
    if builder then
        builder.busy = true
        builder.assignedBuildingId = buildingId
        builder.completesAt = building.upgradeCompletesAt
    end

    -- Fire event
    BuildingService.BuildingUpgraded:Fire(player, building, nextLevel)

    return { success = true, completesAt = building.upgradeCompletesAt, error = nil }
end

--[[
    Collects resources from a production building.
]]
function BuildingService:CollectResources(player: Player, buildingId: string): Types.CollectResult
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_PLAYER_DATA" }
    end

    local building = playerData.buildings[buildingId]
    if not building then
        return { success = false, error = "BUILDING_NOT_FOUND" }
    end

    -- Get building definition
    local buildingDef = BuildingData.GetByType(building.type)
    if not buildingDef or buildingDef.category ~= "resource" then
        return { success = false, error = "NOT_RESOURCE_BUILDING" }
    end

    -- Get level data for production rate
    local levelData = buildingDef.levels[building.level]
    if not levelData or not levelData.productionRate then
        return { success = false, error = "NO_PRODUCTION" }
    end

    -- Calculate accumulated resources
    local now = os.time()
    local elapsed = now - (building.lastCollectedAt or now)
    local produced = math.floor((levelData.productionRate / 3600) * elapsed)
    local storageCapacity = levelData.storageCapacity or 1000

    -- Add stored amount (capped at storage)
    local totalAvailable = math.min((building.storedAmount or 0) + produced, storageCapacity)

    if totalAvailable <= 0 then
        return { success = false, error = "NOTHING_TO_COLLECT" }
    end

    -- Determine resource type
    local resourceType: string
    if building.type == "GoldMine" then
        resourceType = "gold"
    elseif building.type == "LumberMill" then
        resourceType = "wood"
    elseif building.type == "Farm" then
        resourceType = "food"
    else
        return { success = false, error = "UNKNOWN_RESOURCE_TYPE" }
    end

    -- Add to player resources
    local changes = {}
    changes[resourceType] = totalAvailable
    DataService:UpdateResources(player, changes :: any)

    -- Reset collection state
    building.lastCollectedAt = now
    building.storedAmount = 0

    -- Fire event
    BuildingService.BuildingCollected:Fire(player, building, totalAvailable, resourceType)

    return { success = true, amount = totalAvailable, resourceType = resourceType, error = nil }
end

--[[
    Checks and completes finished upgrades (called periodically).
]]
function BuildingService:CheckUpgrades(player: Player)
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return end

    local now = os.time()

    for buildingId, building in playerData.buildings do
        if building.state == "Upgrading" and building.upgradeCompletesAt then
            if now >= building.upgradeCompletesAt then
                -- Complete upgrade
                building.level += 1
                building.state = "Idle"
                building.upgradeStartedAt = nil
                building.upgradeCompletesAt = nil

                -- Update HP to new level
                local buildingDef = BuildingData.GetByType(building.type)
                if buildingDef then
                    local levelData = buildingDef.levels[building.level]
                    if levelData then
                        building.maxHp = levelData.hp
                        building.currentHp = levelData.hp
                    end
                end

                -- Free builder
                for _, builder in playerData.builders do
                    if builder.assignedBuildingId == buildingId then
                        builder.busy = false
                        builder.assignedBuildingId = nil
                        builder.completesAt = nil
                        break
                    end
                end

                -- Fire event
                BuildingService.UpgradeCompleted:Fire(player, building)
            end
        end
    end
end

--[[
    Gets a building by ID.
]]
function BuildingService:GetBuilding(player: Player, buildingId: string): Types.Building?
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return nil end

    return playerData.buildings[buildingId]
end

--[[
    Initializes the BuildingService.
]]
function BuildingService:Init()
    if _initialized then
        warn("BuildingService already initialized")
        return
    end

    -- Get DataService reference
    local ServerScriptService = game:GetService("ServerScriptService")
    DataService = require(ServerScriptService.Services.DataService)

    -- Periodic upgrade check
    task.spawn(function()
        while true do
            task.wait(1)
            for _, player in game:GetService("Players"):GetPlayers() do
                self:CheckUpgrades(player)
            end
        end
    end)

    _initialized = true
    print("BuildingService initialized")
end

return BuildingService
