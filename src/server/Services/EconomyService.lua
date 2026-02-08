--!strict
--[[
    EconomyService.lua

    Manages resource economy, production ticks, and gem transactions.
    All operations are server-authoritative.

    SECURITY: Resources are NEVER trusted from client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.Shared.Constants.BalanceConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declarations
local DataService
local BuildingService

local EconomyService = {}
EconomyService.__index = EconomyService

-- Events
EconomyService.ResourcesChanged = Signal.new()
EconomyService.GemsPurchased = Signal.new()
EconomyService.SpeedUpUsed = Signal.new()

-- Private state
local _initialized = false

--[[
    Calculates gem cost to skip remaining time.
]]
local function calculateGemCost(remainingSeconds: number): number
    local rate = BalanceConfig.Monetization.GemSkipRate
    local minutes = math.ceil(remainingSeconds / 60)
    return math.max(1, minutes * rate)
end

--[[
    Processes resource production for a player.
]]
function EconomyService:ProcessProduction(player: Player)
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return end

    local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
    local now = os.time()

    for _, building in playerData.buildings do
        -- Skip non-resource buildings or upgrading buildings
        local buildingDef = BuildingData.GetByType(building.type)
        if not buildingDef or buildingDef.category ~= "resource" then continue end
        if building.state == "Upgrading" then continue end

        -- Get level data
        local levelData = buildingDef.levels[building.level]
        if not levelData or not levelData.productionRate then continue end

        -- Calculate produced since last tick
        local lastCollected = building.lastCollectedAt or now
        local elapsed = now - lastCollected
        local produced = (levelData.productionRate / 3600) * elapsed

        -- Accumulate (capped at storage)
        local storageCapacity = levelData.storageCapacity or 1000
        building.storedAmount = math.min((building.storedAmount or 0) + produced, storageCapacity)
    end
end

--[[
    Adds gems to a player (from purchase or reward).
]]
function EconomyService:AddGems(player: Player, amount: number, source: string): boolean
    if amount <= 0 then return false end

    local success = DataService:UpdateResources(player, { gems = amount } :: any)

    if success then
        EconomyService.GemsPurchased:Fire(player, amount, source)
    end

    return success
end

--[[
    Spends gems to skip an upgrade.
]]
function EconomyService:SpeedUpUpgrade(player: Player, buildingId: string): boolean
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return false end

    local building = playerData.buildings[buildingId]
    if not building or building.state ~= "Upgrading" then
        return false
    end

    -- Calculate remaining time
    local now = os.time()
    local remaining = (building.upgradeCompletesAt or now) - now
    if remaining <= 0 then
        -- Already done
        BuildingService:CheckUpgrades(player)
        return true
    end

    -- Calculate gem cost
    local gemCost = calculateGemCost(remaining)

    -- Check player has enough gems
    if not DataService:CanAfford(player, { gems = gemCost } :: any) then
        return false
    end

    -- Deduct gems
    DataService:DeductResources(player, { gems = gemCost } :: any)

    -- Complete upgrade instantly
    building.upgradeCompletesAt = now
    BuildingService:CheckUpgrades(player)

    -- Fire event
    EconomyService.SpeedUpUsed:Fire(player, buildingId, gemCost)

    return true
end

--[[
    Calculates total storage capacity for a resource type.
]]
function EconomyService:GetStorageCapacity(player: Player, resourceType: string): number
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return 0 end

    local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
    local total = 0

    -- Find storage building type for resource
    local storageType = nil
    if resourceType == "gold" then
        storageType = "GoldStorage"
    elseif resourceType == "wood" then
        storageType = "WoodStorage"
    elseif resourceType == "food" then
        storageType = "FoodStorage"
    end

    if not storageType then return 0 end

    -- Sum capacity from all storage buildings
    for _, building in playerData.buildings do
        if building.type == storageType and building.state ~= "Upgrading" then
            local buildingDef = BuildingData.GetByType(building.type)
            if buildingDef then
                local levelData = buildingDef.levels[building.level]
                if levelData and levelData.storageCapacity then
                    total += levelData.storageCapacity
                end
            end
        end
    end

    return total
end

--[[
    Gets production rate per hour for a resource type.
]]
function EconomyService:GetProductionRate(player: Player, resourceType: string): number
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return 0 end

    local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
    local total = 0

    -- Find production building type for resource
    local productionType = nil
    if resourceType == "gold" then
        productionType = "GoldMine"
    elseif resourceType == "wood" then
        productionType = "LumberMill"
    elseif resourceType == "food" then
        productionType = "Farm"
    end

    if not productionType then return 0 end

    -- Sum production from all production buildings
    for _, building in playerData.buildings do
        if building.type == productionType and building.state ~= "Upgrading" then
            local buildingDef = BuildingData.GetByType(building.type)
            if buildingDef then
                local levelData = buildingDef.levels[building.level]
                if levelData and levelData.productionRate then
                    total += levelData.productionRate
                end
            end
        end
    end

    -- Apply VIP bonus
    if playerData.vipActive then
        total = total * (1 + BalanceConfig.Economy.VIP.ResourceProductionBonus)
    end

    return total
end

--[[
    Calculates available loot from a player's city.
]]
function EconomyService:CalculateAvailableLoot(targetPlayerData: any): {gold: number, wood: number, food: number}
    local lootConfig = BalanceConfig.Economy.Loot

    return {
        gold = math.floor(targetPlayerData.resources.gold * lootConfig.AvailablePercent),
        wood = math.floor(targetPlayerData.resources.wood * lootConfig.AvailablePercent),
        food = math.floor(targetPlayerData.resources.food * lootConfig.AvailablePercent),
    }
end

--[[
    Transfers loot from defender to attacker.
]]
function EconomyService:TransferLoot(
    attacker: Player,
    defenderData: any,
    lootPercent: number,
    townHallDestroyed: boolean
): {gold: number, wood: number, food: number}
    local availableLoot = self:CalculateAvailableLoot(defenderData)

    -- Apply loot percentage
    local actualLoot = {
        gold = math.floor(availableLoot.gold * lootPercent),
        wood = math.floor(availableLoot.wood * lootPercent),
        food = math.floor(availableLoot.food * lootPercent),
    }

    -- Apply TH bonus
    if townHallDestroyed then
        local thBonus = BalanceConfig.Economy.Loot.TownHallBonus
        actualLoot.gold = math.floor(actualLoot.gold * (1 + thBonus))
        actualLoot.wood = math.floor(actualLoot.wood * (1 + thBonus))
        actualLoot.food = math.floor(actualLoot.food * (1 + thBonus))
    end

    -- Add to attacker
    DataService:UpdateResources(attacker, actualLoot :: any)

    -- Remove from defender (will be saved when they next load)
    defenderData.resources.gold = math.max(0, defenderData.resources.gold - actualLoot.gold)
    defenderData.resources.wood = math.max(0, defenderData.resources.wood - actualLoot.wood)
    defenderData.resources.food = math.max(0, defenderData.resources.food - actualLoot.food)

    return actualLoot
end

-- Shop item definitions (gem purchases only - real money handled via MarketplaceService)
local ShopItems = {
    -- Resources
    gold_10k = { type = "resource", resource = "gold", amount = 10000, gems = 50 },
    gold_50k = { type = "resource", resource = "gold", amount = 50000, gems = 200 },
    gold_200k = { type = "resource", resource = "gold", amount = 200000, gems = 700 },
    wood_10k = { type = "resource", resource = "wood", amount = 10000, gems = 50 },
    wood_50k = { type = "resource", resource = "wood", amount = 50000, gems = 200 },
    food_5k = { type = "resource", resource = "food", amount = 5000, gems = 30 },
    food_25k = { type = "resource", resource = "food", amount = 25000, gems = 120 },

    -- Builders
    builder_2 = { type = "builder", builderIndex = 2, gems = 250 },
    builder_3 = { type = "builder", builderIndex = 3, gems = 500 },
    builder_4 = { type = "builder", builderIndex = 4, gems = 1000 },
    builder_5 = { type = "builder", builderIndex = 5, gems = 2000 },

    -- Shields
    shield_1d = { type = "shield", duration = 86400, gems = 100 }, -- 24 hours
    shield_2d = { type = "shield", duration = 172800, gems = 150 }, -- 48 hours
    shield_7d = { type = "shield", duration = 604800, gems = 400 }, -- 7 days

    -- VIP
    vip_week = { type = "vip", duration = 604800, gems = 200 }, -- 7 days
    vip_month = { type = "vip", duration = 2592000, gems = 600 }, -- 30 days
}

--[[
    Processes a gem-based shop purchase.
]]
function EconomyService:ProcessShopPurchase(player: Player, itemId: string): {success: boolean, error: string?}
    local item = ShopItems[itemId]
    if not item then
        return { success = false, error = "INVALID_ITEM" }
    end

    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_DATA" }
    end

    -- Check player has enough gems
    if not DataService:CanAfford(player, { gems = item.gems } :: any) then
        return { success = false, error = "INSUFFICIENT_GEMS" }
    end

    -- Process based on item type
    if item.type == "resource" then
        -- Add resource
        local resources = { [item.resource] = item.amount }
        DataService:DeductResources(player, { gems = item.gems } :: any)
        DataService:UpdateResources(player, resources :: any)

    elseif item.type == "builder" then
        -- Check if builder already purchased
        if playerData.builders >= item.builderIndex then
            return { success = false, error = "ALREADY_OWNED" }
        end

        -- Check if purchasing in order (can't skip builders)
        if playerData.builders + 1 ~= item.builderIndex then
            return { success = false, error = "PURCHASE_PREVIOUS_FIRST" }
        end

        -- Add builder
        DataService:DeductResources(player, { gems = item.gems } :: any)
        playerData.builders = item.builderIndex

    elseif item.type == "shield" then
        -- Apply shield
        local now = os.time()
        local currentShield = playerData.shield or { active = false, expiresAt = 0 }

        -- Extend existing shield or start new
        if currentShield.active and currentShield.expiresAt > now then
            currentShield.expiresAt = currentShield.expiresAt + item.duration
        else
            currentShield.active = true
            currentShield.expiresAt = now + item.duration
        end

        DataService:DeductResources(player, { gems = item.gems } :: any)
        playerData.shield = currentShield

    elseif item.type == "vip" then
        -- Apply VIP
        local now = os.time()
        local currentExpiry = playerData.vipExpiresAt or 0

        -- Extend existing VIP or start new
        if currentExpiry > now then
            playerData.vipExpiresAt = currentExpiry + item.duration
        else
            playerData.vipExpiresAt = now + item.duration
        end

        playerData.vipActive = true
        DataService:DeductResources(player, { gems = item.gems } :: any)

    else
        return { success = false, error = "UNKNOWN_TYPE" }
    end

    return { success = true }
end

--[[
    Initializes the EconomyService.
]]
function EconomyService:Init()
    if _initialized then
        warn("EconomyService already initialized")
        return
    end

    -- Get service references
    local ServerScriptService = game:GetService("ServerScriptService")
    DataService = require(ServerScriptService.Services.DataService)
    BuildingService = require(ServerScriptService.Services.BuildingService)

    -- Production tick (every 60 seconds)
    task.spawn(function()
        while true do
            task.wait(60)
            for _, player in Players:GetPlayers() do
                self:ProcessProduction(player)
            end
        end
    end)

    _initialized = true
    print("EconomyService initialized")
end

return EconomyService
