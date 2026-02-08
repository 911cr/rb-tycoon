--!strict
--[[
    TroopService.lua

    Manages troop training, army composition, and troop consumption.
    All operations are server-authoritative.

    SECURITY: Client sends requests, server validates and executes.
    Training times are enforced server-side to prevent speed hacks.

    Dependencies:
    - DataService (for player data)
    - EconomyService (for resource transactions)

    Events:
    - TrainingStarted(player, troopType, quantity, completesAt)
    - TrainingCompleted(player, troopType, quantity)
    - TrainingCancelled(player, troopType, refundAmount)
    - TroopsConsumed(player, troopType, count)
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)
local BalanceConfig = require(ReplicatedStorage.Shared.Constants.BalanceConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declarations
local DataService

local TroopService = {}
TroopService.__index = TroopService

-- Events
TroopService.TrainingStarted = Signal.new()
TroopService.TrainingCompleted = Signal.new()
TroopService.TrainingCancelled = Signal.new()
TroopService.TroopsConsumed = Signal.new()

-- Private state
local _trainingQueues: {[number]: {TrainingQueueItem}} = {} -- [userId] = queue
local _initialized = false

-- Constants
local CANCEL_REFUND_PERCENT = 0.5 -- 50% refund on cancel
local MAX_QUEUE_SIZE = 50

-- Types
type TrainingQueueItem = {
    id: string,
    troopType: string,
    quantity: number,
    startedAt: number,
    completesAt: number,
    trainingTimePerUnit: number,
}

type TrainResult = {
    success: boolean,
    queueItem: TrainingQueueItem?,
    error: string?,
}

type CancelResult = {
    success: boolean,
    refund: {food: number, gold: number?}?,
    error: string?,
}

--[[
    Gets the current troop level for a player (based on lab upgrades).
    For now, returns 1. Can be extended with lab system.
]]
local function getTroopLevel(playerData: any, troopType: string): number
    -- TODO: Implement lab upgrade tracking
    -- For now, all troops are level 1
    return 1
end

--[[
    Gets the total army camp capacity for a player.
]]
local function getArmyCampCapacity(playerData: any): number
    return playerData.armyCampCapacity or 20
end

--[[
    Gets the current army size (troops already trained).
]]
local function getCurrentArmySize(playerData: any): number
    local total = 0
    for troopType, count in playerData.troops do
        local troopDef = TroopData.GetByType(troopType)
        if troopDef then
            total += count * troopDef.housingSpace
        end
    end
    return total
end

--[[
    Gets the training queue size (troops being trained).
]]
local function getQueuedArmySize(userId: number): number
    local queue = _trainingQueues[userId]
    if not queue then return 0 end

    local total = 0
    for _, item in queue do
        local troopDef = TroopData.GetByType(item.troopType)
        if troopDef then
            total += item.quantity * troopDef.housingSpace
        end
    end
    return total
end

--[[
    Finds the training building for a troop type.
]]
local function hasTrainingBuilding(playerData: any, troopDef: any): boolean
    local requiredBuilding = troopDef.trainingBuilding
    if not requiredBuilding then return false end

    for _, building in playerData.buildings do
        if building.type == requiredBuilding and building.state ~= "Upgrading" then
            return true
        end
    end
    return false
end

--[[
    Gets the queue end time (when last item completes).
]]
local function getQueueEndTime(userId: number): number
    local queue = _trainingQueues[userId]
    if not queue or #queue == 0 then
        return os.time()
    end

    local lastItem = queue[#queue]
    return lastItem.completesAt
end

--[[
    Trains troops and adds them to the training queue.
]]
function TroopService:TrainTroop(player: Player, troopType: string, quantity: number): TrainResult
    -- Validate player
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, queueItem = nil, error = "NO_PLAYER_DATA" }
    end

    -- Validate troop type
    if typeof(troopType) ~= "string" then
        return { success = false, queueItem = nil, error = "INVALID_TROOP_TYPE" }
    end

    local troopDef = TroopData.GetByType(troopType)
    if not troopDef then
        return { success = false, queueItem = nil, error = "INVALID_TROOP_TYPE" }
    end

    -- Validate quantity
    if typeof(quantity) ~= "number" or quantity <= 0 or quantity ~= math.floor(quantity) then
        return { success = false, queueItem = nil, error = "INVALID_QUANTITY" }
    end
    quantity = math.min(quantity, 100) -- Cap at 100 per request

    -- Check TH requirement
    if playerData.townHallLevel < troopDef.townHallRequired then
        return { success = false, queueItem = nil, error = "TH_TOO_LOW" }
    end

    -- Check training building exists
    if not hasTrainingBuilding(playerData, troopDef) then
        return { success = false, queueItem = nil, error = "NO_TRAINING_BUILDING" }
    end

    -- Check army capacity
    local capacity = getArmyCampCapacity(playerData)
    local currentSize = getCurrentArmySize(playerData)
    local queuedSize = getQueuedArmySize(player.UserId)
    local requestedSpace = quantity * troopDef.housingSpace

    if currentSize + queuedSize + requestedSpace > capacity then
        return { success = false, queueItem = nil, error = "ARMY_FULL" }
    end

    -- Check queue size limit
    local queue = _trainingQueues[player.UserId] or {}
    if #queue >= MAX_QUEUE_SIZE then
        return { success = false, queueItem = nil, error = "QUEUE_FULL" }
    end

    -- Get troop level data
    local level = getTroopLevel(playerData, troopType)
    local levelData = TroopData.GetLevelData(troopType, level)
    if not levelData then
        return { success = false, queueItem = nil, error = "NO_LEVEL_DATA" }
    end

    -- Calculate cost
    local costPerUnit = levelData.trainingCost
    local totalCost = {
        food = (costPerUnit.food or 0) * quantity,
        gold = (costPerUnit.gold or 0) * quantity,
    }

    -- Check resources
    if not DataService:CanAfford(player, totalCost :: any) then
        return { success = false, queueItem = nil, error = "INSUFFICIENT_RESOURCES" }
    end

    -- Deduct resources
    DataService:DeductResources(player, totalCost :: any)

    -- Calculate training time
    local trainingTimePerUnit = levelData.trainingTime or troopDef.trainingTime or 30
    local totalTrainingTime = trainingTimePerUnit * quantity

    -- VIP bonus
    if playerData.vipActive then
        totalTrainingTime = totalTrainingTime * (1 - BalanceConfig.Economy.VIP.UpgradeTimeReduction)
    end

    -- Create queue item
    local now = os.time()
    local queueStartTime = getQueueEndTime(player.UserId)
    if queueStartTime < now then
        queueStartTime = now
    end

    local queueItem: TrainingQueueItem = {
        id = HttpService:GenerateGUID(false),
        troopType = troopType,
        quantity = quantity,
        startedAt = queueStartTime,
        completesAt = queueStartTime + totalTrainingTime,
        trainingTimePerUnit = trainingTimePerUnit,
    }

    -- Add to queue
    _trainingQueues[player.UserId] = _trainingQueues[player.UserId] or {}
    table.insert(_trainingQueues[player.UserId], queueItem)

    -- Fire event
    TroopService.TrainingStarted:Fire(player, troopType, quantity, queueItem.completesAt)

    return { success = true, queueItem = queueItem, error = nil }
end

--[[
    Cancels a training queue item by index.
]]
function TroopService:CancelTraining(player: Player, queueIndex: number): CancelResult
    -- Validate player
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, refund = nil, error = "NO_PLAYER_DATA" }
    end

    -- Validate queue index
    if typeof(queueIndex) ~= "number" or queueIndex <= 0 or queueIndex ~= math.floor(queueIndex) then
        return { success = false, refund = nil, error = "INVALID_INDEX" }
    end

    local queue = _trainingQueues[player.UserId]
    if not queue or queueIndex > #queue then
        return { success = false, refund = nil, error = "INVALID_INDEX" }
    end

    local item = queue[queueIndex]

    -- Get troop data for refund calculation
    local level = getTroopLevel(playerData, item.troopType)
    local levelData = TroopData.GetLevelData(item.troopType, level)
    if not levelData then
        return { success = false, refund = nil, error = "NO_LEVEL_DATA" }
    end

    -- Calculate refund (50% of cost)
    local costPerUnit = levelData.trainingCost
    local refund = {
        food = math.floor((costPerUnit.food or 0) * item.quantity * CANCEL_REFUND_PERCENT),
        gold = math.floor((costPerUnit.gold or 0) * item.quantity * CANCEL_REFUND_PERCENT),
    }

    -- Remove from queue
    table.remove(queue, queueIndex)

    -- Recalculate completion times for remaining items
    local previousEndTime = os.time()
    if queueIndex > 1 and queue[queueIndex - 1] then
        previousEndTime = queue[queueIndex - 1].completesAt
    end

    for i = queueIndex, #queue do
        local queueItem = queue[i]
        local itemDuration = queueItem.trainingTimePerUnit * queueItem.quantity
        queueItem.startedAt = previousEndTime
        queueItem.completesAt = previousEndTime + itemDuration
        previousEndTime = queueItem.completesAt
    end

    -- Refund resources
    DataService:UpdateResources(player, refund :: any)

    -- Fire event
    TroopService.TrainingCancelled:Fire(player, item.troopType, refund)

    return { success = true, refund = refund, error = nil }
end

--[[
    Checks and completes finished training items.
]]
function TroopService:CheckTrainingComplete(player: Player)
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return end

    local queue = _trainingQueues[player.UserId]
    if not queue then return end

    local now = os.time()
    local completed = {}

    -- Check from front of queue
    while #queue > 0 do
        local item = queue[1]
        if now >= item.completesAt then
            -- Training complete
            table.remove(queue, 1)

            -- Add troops to player
            playerData.troops[item.troopType] = (playerData.troops[item.troopType] or 0) + item.quantity

            table.insert(completed, item)
        else
            break -- Queue is ordered, so stop checking
        end
    end

    -- Fire events for completed items
    for _, item in completed do
        TroopService.TrainingCompleted:Fire(player, item.troopType, item.quantity)
    end
end

--[[
    Consumes troops for battle or donation.
]]
function TroopService:ConsumeTroops(player: Player, troopType: string, count: number): boolean
    -- Validate player
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return false end

    -- Validate inputs
    if typeof(troopType) ~= "string" then return false end
    if typeof(count) ~= "number" or count <= 0 or count ~= math.floor(count) then return false end

    -- Check troop exists
    local troopDef = TroopData.GetByType(troopType)
    if not troopDef then return false end

    -- Check player has enough
    local available = playerData.troops[troopType] or 0
    if available < count then return false end

    -- Consume troops
    playerData.troops[troopType] = available - count
    if playerData.troops[troopType] <= 0 then
        playerData.troops[troopType] = nil
    end

    -- Fire event
    TroopService.TroopsConsumed:Fire(player, troopType, count)

    return true
end

--[[
    Gets available trained troops ready for battle.
]]
function TroopService:GetAvailableTroops(player: Player): {[string]: number}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return {} end

    -- Return a copy of the troops table
    local result = {}
    for troopType, count in playerData.troops do
        if count > 0 then
            result[troopType] = count
        end
    end

    return result
end

--[[
    Gets the current training queue for a player.
]]
function TroopService:GetTrainingQueue(player: Player): {TrainingQueueItem}
    local queue = _trainingQueues[player.UserId]
    if not queue then return {} end

    -- Return a copy
    local result = {}
    for _, item in queue do
        table.insert(result, {
            id = item.id,
            troopType = item.troopType,
            quantity = item.quantity,
            startedAt = item.startedAt,
            completesAt = item.completesAt,
            trainingTimePerUnit = item.trainingTimePerUnit,
        })
    end

    return result
end

--[[
    Gets remaining army capacity.
]]
function TroopService:GetRemainingCapacity(player: Player): number
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return 0 end

    local capacity = getArmyCampCapacity(playerData)
    local currentSize = getCurrentArmySize(playerData)
    local queuedSize = getQueuedArmySize(player.UserId)

    return math.max(0, capacity - currentSize - queuedSize)
end

--[[
    Initializes the TroopService.
]]
function TroopService:Init()
    if _initialized then
        warn("TroopService already initialized")
        return
    end

    -- Get service references
    local ServerScriptService = game:GetService("ServerScriptService")
    DataService = require(ServerScriptService.Services.DataService)

    -- Initialize queue for existing players
    for _, player in Players:GetPlayers() do
        _trainingQueues[player.UserId] = {}
    end

    -- Handle player join
    Players.PlayerAdded:Connect(function(player)
        _trainingQueues[player.UserId] = {}
    end)

    -- Handle player leave
    Players.PlayerRemoving:Connect(function(player)
        _trainingQueues[player.UserId] = nil
    end)

    -- Periodic training completion check
    task.spawn(function()
        while true do
            task.wait(1)
            for _, player in Players:GetPlayers() do
                self:CheckTrainingComplete(player)
            end
        end
    end)

    _initialized = true
    print("TroopService initialized")
end

return TroopService
