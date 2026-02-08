--!strict
--[[
    BuildingTypes.lua

    Type definitions for buildings and construction.
    Used by both server and client.
]]

export type ResourceCost = {
    gold: number?,
    wood: number?,
    food: number?,
    gems: number?,
}

export type BuildingState = "Idle" | "Upgrading" | "Producing" | "Training" | "Researching"

export type Building = {
    id: string,
    type: string,
    level: number,
    position: Vector3,
    rotation: number, -- 0, 90, 180, 270
    state: BuildingState,

    -- Upgrade tracking
    upgradeStartedAt: number?,
    upgradeCompletesAt: number?,

    -- Production tracking (for resource buildings)
    lastCollectedAt: number?,
    storedAmount: number?,

    -- Training tracking (for military buildings)
    trainingQueue: {TrainingQueueItem}?,

    -- Health (for defenses in battle)
    maxHp: number,
    currentHp: number,
}

export type TrainingQueueItem = {
    troopType: string,
    completesAt: number,
}

export type BuildingDefinition = {
    type: string,
    category: string, -- "resource" | "military" | "defense" | "wall" | "decoration"
    displayName: string,
    description: string,

    -- Size on grid
    width: number,
    height: number,

    -- Requirements
    townHallRequired: number,
    maxCount: number, -- per TH level or total

    -- Level data (indexed by level)
    levels: {BuildingLevelData},
}

export type BuildingLevelData = {
    level: number,

    -- Costs
    cost: ResourceCost,
    buildTime: number, -- seconds

    -- Stats
    hp: number,

    -- Resource production (if applicable)
    productionRate: number?, -- per hour
    storageCapacity: number?,

    -- Defense stats (if applicable)
    damage: number?,
    attackSpeed: number?, -- attacks per second
    range: number?,
    targetType: string?, -- "ground" | "air" | "both"
    splashRadius: number?,

    -- Training stats (if applicable)
    trainingCapacity: number?,
    trainingSpeedBonus: number?,

    -- Housing (for army camps)
    housingCapacity: number?,
}

export type PlacementResult = {
    success: boolean,
    building: Building?,
    error: string?,
}

export type UpgradeResult = {
    success: boolean,
    completesAt: number?,
    error: string?,
}

export type CollectResult = {
    success: boolean,
    amount: number?,
    resourceType: string?,
    error: string?,
}

return nil
