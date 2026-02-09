--!strict
--[[
    PlayerTypes.lua

    Type definitions for player data and related structures.
    Used by both server and client.
]]

export type ResourceData = {
    gold: number,
    wood: number,
    food: number,
}

export type StorageCapacity = {
    gold: number,
    wood: number,
    food: number,
}

export type BuilderData = {
    id: number,
    busy: boolean,
    assignedBuildingId: string?,
    completesAt: number?,
}

export type ShieldData = {
    active: boolean,
    expiresAt: number,
    source: string, -- "attack" | "purchase" | "guard"
}

export type RevengeData = {
    attackerId: number,
    attackerName: string,
    attackTime: number,
    expiresAt: number,
    used: boolean,
}

export type TrophyData = {
    current: number,
    season: number,
    allTime: number,
    league: string,
}

export type PlayerStats = {
    level: number,
    xp: number,
    xpToNextLevel: number,
    attacksWon: number,
    defensesWon: number,
    troopsDestroyed: number,
    buildingsDestroyed: number,
}

export type AllianceMembership = {
    allianceId: string?,
    role: string?, -- "leader" | "co-leader" | "elder" | "member"
    joinedAt: number?,
    donationsThisWeek: number,
    donationsReceived: number,
}

export type PlayerData = {
    -- Identity
    userId: number,
    username: string,
    joinedAt: number,
    lastLoginAt: number,

    -- Resources
    resources: ResourceData,
    storageCapacity: StorageCapacity,

    -- Progression
    townHallLevel: number,
    stats: PlayerStats,
    trophies: TrophyData,

    -- Buildings (stored by ID)
    buildings: {[string]: any}, -- BuildingTypes.Building

    -- Military
    troops: {[string]: number}, -- troopType -> count
    spells: {[string]: number}, -- spellType -> count
    armyCampCapacity: number, -- Deprecated: kept for compatibility

    -- Food Supply System
    foodProduction: number, -- Food produced per minute from all farms
    foodUsage: number, -- Food consumed per minute by all troops
    trainingPaused: boolean, -- True if foodUsage > foodProduction
    farmPlots: number, -- Number of purchased farm slots (starts at 1)
    maxFarmPlots: number, -- Maximum farm slots allowed at current TH level

    -- Builders
    builders: {BuilderData},
    maxBuilders: number,

    -- Protection
    shield: ShieldData?,
    revengeList: {RevengeData},

    -- Social
    alliance: AllianceMembership,

    -- Cities owned (for multi-city conquest)
    cities: {string}, -- cityIds
    activeCityId: string,

    -- Monetization
    vipActive: boolean,
    vipExpiresAt: number?,
    battlePassTier: number,
    battlePassPremium: boolean,

    -- Settings
    settings: {
        musicEnabled: boolean,
        sfxEnabled: boolean,
        notificationsEnabled: boolean,
    },
}

export type PlayerDataResult = {
    success: boolean,
    data: PlayerData?,
    error: string?,
}

return nil
