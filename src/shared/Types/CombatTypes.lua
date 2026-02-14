--!strict
--[[
    CombatTypes.lua

    Type definitions for combat, troops, and battles.
    Used by both server and client.
]]

export type TroopDefinition = {
    type: string,
    displayName: string,
    description: string,

    -- Training
    trainingBuilding: string, -- "Barracks" | "ArcheryRange" | etc.
    trainingTime: number, -- seconds
    trainingCost: {
        food: number,
        gold: number?,
    },

    -- Housing
    housingSpace: number,

    -- Unlock requirements
    townHallRequired: number,

    -- Combat stats (indexed by level)
    levels: {TroopLevelData},
}

export type TroopLevelData = {
    level: number,

    -- Combat stats
    dps: number,
    hp: number,

    -- Movement
    moveSpeed: number,

    -- Targeting
    targetType: string, -- "ground" | "air" | "both"
    preferredTarget: string?, -- "defenses" | "resources" | "walls" | "any"
    attackRange: number,

    -- Special abilities
    splashRadius: number?,
    canJumpWalls: boolean?,

    -- Upgrade cost (for lab)
    upgradeCost: {
        gold: number?,
        elixir: number?,
    }?,
    upgradeTime: number?,
}

export type SpellDefinition = {
    type: string,
    displayName: string,
    description: string,

    -- Crafting
    craftingTime: number, -- seconds
    craftingCost: {
        gold: number?,
        elixir: number?,
    },

    -- Housing
    housingSpace: number,

    -- Unlock requirements
    townHallRequired: number,
    spellFactoryLevel: number,

    -- Effect stats (indexed by level)
    levels: {SpellLevelData},
}

export type SpellLevelData = {
    level: number,

    -- Effect
    radius: number,
    duration: number,

    -- Type-specific stats
    damagePerSecond: number?, -- for damage spells
    healPerSecond: number?, -- for heal spells
    speedBoost: number?, -- for rage/haste
    freezeDuration: number?, -- for freeze
}

export type DeployedTroop = {
    id: string,
    type: string,
    level: number,

    -- Position
    position: Vector3,
    targetPosition: Vector3?,

    -- State
    currentHp: number,
    maxHp: number,
    state: string, -- "moving" | "attacking" | "dead"

    -- Target
    targetId: string?,

    -- Timing
    deployedAt: number,
    lastAttackAt: number?,
}

export type DeployedSpell = {
    id: string,
    type: string,
    level: number,

    -- Position
    position: Vector3,
    radius: number,

    -- Timing
    deployedAt: number,
    expiresAt: number,
}

export type BattleState = {
    id: string,

    -- Participants
    attackerId: number,
    defenderId: number,
    defenderCityId: string,

    -- Timing
    startedAt: number,
    endsAt: number,
    scoutEndsAt: number,

    -- Phase
    phase: string, -- "scout" | "deploy" | "battle" | "ended"

    -- Deployed units
    troops: {DeployedTroop},
    spells: {DeployedSpell},

    -- Battle progress
    destruction: number, -- 0-100
    starsEarned: number, -- 0-3
    townHallDestroyed: boolean,

    -- Available army
    remainingTroops: {[string]: number},
    remainingSpells: {[string]: number},

    -- Loot
    lootAvailable: {
        gold: number,
        wood: number,
        food: number,
    },
    lootClaimed: {
        gold: number,
        wood: number,
        food: number,
    },

    -- Revenge flag (revenge attacks bypass shields and grant bonus loot)
    isRevenge: boolean?,
}

export type BattleResult = {
    battleId: string,

    -- Outcome
    victory: boolean,
    destruction: number,
    stars: number,
    isConquest: boolean, -- 100% destruction = take city

    -- Rewards
    loot: {
        gold: number,
        wood: number,
        food: number,
    },
    trophiesGained: number,
    xpGained: number,

    -- Timing
    duration: number,

    -- Stats
    troopsLost: {[string]: number},
    spellsUsed: {[string]: number},
    buildingsDestroyed: number,

    -- Revenge info
    isRevenge: boolean?,
    revengeLootBonus: number?, -- Bonus percentage applied (e.g. 0.20 for 20%)
}

export type MatchmakingResult = {
    success: boolean,
    target: {
        userId: number,
        username: string,
        cityId: string,
        townHallLevel: number,
        trophies: number,
        lootAvailable: {
            gold: number,
            wood: number,
            food: number,
        },
    }?,
    error: string?,
}

return nil
