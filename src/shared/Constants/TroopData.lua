--!strict
--[[
    TroopData.lua

    Troop definitions and combat stats for all troops in Battle Tycoon: Conquest.
    Reference: docs/GAME_DESIGN_DOCUMENT.md Section 5

    IMPORTANT: Changes to this file affect game balance.
    Consult combat-designer agent before modifications.
]]

-- Helper to create time in seconds
local function seconds(s: number): number return s end
local function minutes(m: number): number return m * 60 end

local TroopData = {}

--[[
    TIER 1 - BASIC TROOPS (Barracks)
]]
TroopData.Barbarian = {
    type = "Barbarian",
    displayName = "Barbarian",
    description = "Basic melee fighter. Cheap and quick to train.",
    trainingBuilding = "Barracks",
    housingSpace = 1,
    foodUpkeep = 1, -- Food consumed per minute
    townHallRequired = 1,
    levels = {
        {
            level = 1,
            trainingTime = seconds(20),
            trainingCost = { food = 25 },
            dps = 8,
            hp = 45,
            moveSpeed = 16,
            targetType = "ground",
            preferredTarget = "any",
            attackRange = 0.4,
        },
        {
            level = 2,
            trainingTime = seconds(20),
            trainingCost = { food = 40 },
            dps = 11,
            hp = 54,
            moveSpeed = 16,
            targetType = "ground",
            preferredTarget = "any",
            attackRange = 0.4,
            upgradeCost = { gold = 50000 },
            upgradeTime = minutes(30),
        },
        {
            level = 3,
            trainingTime = seconds(20),
            trainingCost = { food = 60 },
            dps = 14,
            hp = 65,
            moveSpeed = 16,
            targetType = "ground",
            preferredTarget = "any",
            attackRange = 0.4,
            upgradeCost = { gold = 150000 },
            upgradeTime = minutes(90),
        },
        {
            level = 4,
            trainingTime = seconds(20),
            trainingCost = { food = 80 },
            dps = 18,
            hp = 78,
            moveSpeed = 16,
            targetType = "ground",
            preferredTarget = "any",
            attackRange = 0.4,
            upgradeCost = { gold = 500000 },
            upgradeTime = minutes(180),
        },
        {
            level = 5,
            trainingTime = seconds(20),
            trainingCost = { food = 100 },
            dps = 23,
            hp = 95,
            moveSpeed = 16,
            targetType = "ground",
            preferredTarget = "any",
            attackRange = 0.4,
            upgradeCost = { gold = 1500000 },
            upgradeTime = minutes(360),
        },
    },
}

TroopData.Archer = {
    type = "Archer",
    displayName = "Archer",
    description = "Ranged attacker. Can target both ground and air units.",
    trainingBuilding = "Barracks",
    housingSpace = 1,
    foodUpkeep = 1, -- Food consumed per minute
    townHallRequired = 1,
    levels = {
        {
            level = 1,
            trainingTime = seconds(25),
            trainingCost = { food = 50 },
            dps = 7,
            hp = 20,
            moveSpeed = 24,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3.5,
        },
        {
            level = 2,
            trainingTime = seconds(25),
            trainingCost = { food = 80 },
            dps = 9,
            hp = 23,
            moveSpeed = 24,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3.5,
            upgradeCost = { gold = 50000 },
            upgradeTime = minutes(45),
        },
        {
            level = 3,
            trainingTime = seconds(25),
            trainingCost = { food = 120 },
            dps = 12,
            hp = 28,
            moveSpeed = 24,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3.5,
            upgradeCost = { gold = 250000 },
            upgradeTime = minutes(120),
        },
        {
            level = 4,
            trainingTime = seconds(25),
            trainingCost = { food = 160 },
            dps = 16,
            hp = 33,
            moveSpeed = 24,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3.5,
            upgradeCost = { gold = 750000 },
            upgradeTime = minutes(240),
        },
        {
            level = 5,
            trainingTime = seconds(25),
            trainingCost = { food = 200 },
            dps = 20,
            hp = 40,
            moveSpeed = 24,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3.5,
            upgradeCost = { gold = 2250000 },
            upgradeTime = minutes(480),
        },
    },
}

--[[
    TIER 2 - SPECIALIZED TROOPS (Barracks)
]]
TroopData.Giant = {
    type = "Giant",
    displayName = "Giant",
    description = "Tanky unit that prioritizes attacking defenses.",
    trainingBuilding = "Barracks",
    housingSpace = 5,
    foodUpkeep = 4, -- Food consumed per minute
    townHallRequired = 2,
    levels = {
        {
            level = 1,
            trainingTime = seconds(120),
            trainingCost = { food = 250 },
            dps = 11,
            hp = 300,
            moveSpeed = 12,
            targetType = "ground",
            preferredTarget = "defenses",
            attackRange = 0.4,
        },
        {
            level = 2,
            trainingTime = seconds(120),
            trainingCost = { food = 400 },
            dps = 14,
            hp = 360,
            moveSpeed = 12,
            targetType = "ground",
            preferredTarget = "defenses",
            attackRange = 0.4,
            upgradeCost = { gold = 100000 },
            upgradeTime = minutes(60),
        },
        {
            level = 3,
            trainingTime = seconds(120),
            trainingCost = { food = 600 },
            dps = 19,
            hp = 430,
            moveSpeed = 12,
            targetType = "ground",
            preferredTarget = "defenses",
            attackRange = 0.4,
            upgradeCost = { gold = 250000 },
            upgradeTime = minutes(120),
        },
        {
            level = 4,
            trainingTime = seconds(120),
            trainingCost = { food = 800 },
            dps = 24,
            hp = 520,
            moveSpeed = 12,
            targetType = "ground",
            preferredTarget = "defenses",
            attackRange = 0.4,
            upgradeCost = { gold = 750000 },
            upgradeTime = minutes(240),
        },
        {
            level = 5,
            trainingTime = seconds(120),
            trainingCost = { food = 1000 },
            dps = 31,
            hp = 620,
            moveSpeed = 12,
            targetType = "ground",
            preferredTarget = "defenses",
            attackRange = 0.4,
            upgradeCost = { gold = 2250000 },
            upgradeTime = minutes(480),
        },
    },
}

TroopData.WallBreaker = {
    type = "WallBreaker",
    displayName = "Wall Breaker",
    description = "Suicidal bomber that deals massive damage to walls.",
    trainingBuilding = "Barracks",
    housingSpace = 2,
    foodUpkeep = 2, -- Food consumed per minute
    townHallRequired = 3,
    levels = {
        {
            level = 1,
            trainingTime = seconds(30),
            trainingCost = { food = 150 },
            dps = 12, -- actually damage per attack
            hp = 20,
            moveSpeed = 24,
            targetType = "ground",
            preferredTarget = "walls",
            attackRange = 0.4,
            wallDamageMultiplier = 40, -- 40x damage to walls
        },
        {
            level = 2,
            trainingTime = seconds(30),
            trainingCost = { food = 240 },
            dps = 16,
            hp = 24,
            moveSpeed = 24,
            targetType = "ground",
            preferredTarget = "walls",
            attackRange = 0.4,
            wallDamageMultiplier = 40,
            upgradeCost = { gold = 100000 },
            upgradeTime = minutes(45),
        },
        {
            level = 3,
            trainingTime = seconds(30),
            trainingCost = { food = 360 },
            dps = 21,
            hp = 29,
            moveSpeed = 24,
            targetType = "ground",
            preferredTarget = "walls",
            attackRange = 0.4,
            wallDamageMultiplier = 40,
            upgradeCost = { gold = 250000 },
            upgradeTime = minutes(90),
        },
        {
            level = 4,
            trainingTime = seconds(30),
            trainingCost = { food = 480 },
            dps = 29,
            hp = 35,
            moveSpeed = 24,
            targetType = "ground",
            preferredTarget = "walls",
            attackRange = 0.4,
            wallDamageMultiplier = 40,
            upgradeCost = { gold = 750000 },
            upgradeTime = minutes(180),
        },
        {
            level = 5,
            trainingTime = seconds(30),
            trainingCost = { food = 600 },
            dps = 39,
            hp = 42,
            moveSpeed = 24,
            targetType = "ground",
            preferredTarget = "walls",
            attackRange = 0.4,
            wallDamageMultiplier = 40,
            upgradeCost = { gold = 2250000 },
            upgradeTime = minutes(360),
        },
    },
}

--[[
    TIER 3 - ELITE TROOPS (Barracks)
]]
TroopData.Wizard = {
    type = "Wizard",
    displayName = "Wizard",
    description = "Powerful ranged attacker with splash damage.",
    trainingBuilding = "Barracks",
    housingSpace = 4,
    foodUpkeep = 5, -- Food consumed per minute
    townHallRequired = 5,
    levels = {
        {
            level = 1,
            trainingTime = seconds(90),
            trainingCost = { food = 500 },
            dps = 50,
            hp = 75,
            moveSpeed = 16,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3,
            splashRadius = 0.5,
        },
        {
            level = 2,
            trainingTime = seconds(90),
            trainingCost = { food = 700 },
            dps = 70,
            hp = 90,
            moveSpeed = 16,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3,
            splashRadius = 0.5,
            upgradeCost = { gold = 300000 },
            upgradeTime = minutes(90),
        },
        {
            level = 3,
            trainingTime = seconds(90),
            trainingCost = { food = 900 },
            dps = 90,
            hp = 108,
            moveSpeed = 16,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3,
            splashRadius = 0.5,
            upgradeCost = { gold = 900000 },
            upgradeTime = minutes(180),
        },
        {
            level = 4,
            trainingTime = seconds(90),
            trainingCost = { food = 1200 },
            dps = 125,
            hp = 130,
            moveSpeed = 16,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3,
            splashRadius = 0.5,
            upgradeCost = { gold = 2700000 },
            upgradeTime = minutes(360),
        },
        {
            level = 5,
            trainingTime = seconds(90),
            trainingCost = { food = 1500 },
            dps = 170,
            hp = 156,
            moveSpeed = 16,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3,
            splashRadius = 0.5,
            upgradeCost = { gold = 5500000 },
            upgradeTime = minutes(720),
        },
    },
}

--[[
    TIER 4 - AERIAL TROOPS
]]
TroopData.Dragon = {
    type = "Dragon",
    displayName = "Dragon",
    description = "Flying beast with devastating splash damage breath.",
    trainingBuilding = "Barracks",
    housingSpace = 20,
    foodUpkeep = 15, -- Food consumed per minute
    townHallRequired = 7,
    levels = {
        {
            level = 1,
            trainingTime = seconds(300),
            trainingCost = { food = 2000 },
            dps = 140,
            hp = 1900,
            moveSpeed = 16,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3,
            splashRadius = 0.3,
            isFlying = true,
        },
        {
            level = 2,
            trainingTime = seconds(300),
            trainingCost = { food = 2800 },
            dps = 160,
            hp = 2100,
            moveSpeed = 16,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3,
            splashRadius = 0.3,
            isFlying = true,
            upgradeCost = { gold = 2000000 },
            upgradeTime = minutes(240),
        },
        {
            level = 3,
            trainingTime = seconds(300),
            trainingCost = { food = 3600 },
            dps = 180,
            hp = 2300,
            moveSpeed = 16,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3,
            splashRadius = 0.3,
            isFlying = true,
            upgradeCost = { gold = 4000000 },
            upgradeTime = minutes(480),
        },
        {
            level = 4,
            trainingTime = seconds(300),
            trainingCost = { food = 4400 },
            dps = 200,
            hp = 2500,
            moveSpeed = 16,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3,
            splashRadius = 0.3,
            isFlying = true,
            upgradeCost = { gold = 6000000 },
            upgradeTime = minutes(720),
        },
        {
            level = 5,
            trainingTime = seconds(300),
            trainingCost = { food = 5200 },
            dps = 220,
            hp = 2700,
            moveSpeed = 16,
            targetType = "both",
            preferredTarget = "any",
            attackRange = 3,
            splashRadius = 0.3,
            isFlying = true,
            upgradeCost = { gold = 8000000 },
            upgradeTime = minutes(1440),
        },
    },
}

--[[
    TIER 5 - HEAVY UNITS
]]
TroopData.PEKKA = {
    type = "PEKKA",
    displayName = "P.E.K.K.A",
    description = "Heavily armored knight with devastating melee damage.",
    trainingBuilding = "Barracks",
    housingSpace = 25,
    foodUpkeep = 20, -- Food consumed per minute
    townHallRequired = 8,
    levels = {
        {
            level = 1,
            trainingTime = seconds(360),
            trainingCost = { food = 3000 },
            dps = 240,
            hp = 2800,
            moveSpeed = 16,
            targetType = "ground",
            preferredTarget = "any",
            attackRange = 0.4,
        },
        {
            level = 2,
            trainingTime = seconds(360),
            trainingCost = { food = 3800 },
            dps = 270,
            hp = 3100,
            moveSpeed = 16,
            targetType = "ground",
            preferredTarget = "any",
            attackRange = 0.4,
            upgradeCost = { gold = 3000000 },
            upgradeTime = minutes(300),
        },
        {
            level = 3,
            trainingTime = seconds(360),
            trainingCost = { food = 4600 },
            dps = 300,
            hp = 3500,
            moveSpeed = 16,
            targetType = "ground",
            preferredTarget = "any",
            attackRange = 0.4,
            upgradeCost = { gold = 5000000 },
            upgradeTime = minutes(600),
        },
        {
            level = 4,
            trainingTime = seconds(360),
            trainingCost = { food = 5400 },
            dps = 340,
            hp = 4000,
            moveSpeed = 16,
            targetType = "ground",
            preferredTarget = "any",
            attackRange = 0.4,
            upgradeCost = { gold = 7000000 },
            upgradeTime = minutes(900),
        },
        {
            level = 5,
            trainingTime = seconds(360),
            trainingCost = { food = 6200 },
            dps = 380,
            hp = 4500,
            moveSpeed = 16,
            targetType = "ground",
            preferredTarget = "any",
            attackRange = 0.4,
            upgradeCost = { gold = 9000000 },
            upgradeTime = minutes(1440),
        },
    },
}

-- Helper function to get troop data by type
function TroopData.GetByType(troopType: string): any?
    return TroopData[troopType]
end

-- Helper function to get level data
function TroopData.GetLevelData(troopType: string, level: number): any?
    local troop = TroopData[troopType]
    if not troop then return nil end
    return troop.levels[level]
end

-- Get all troops unlocked at a given TH level
function TroopData.GetUnlockedAtTH(thLevel: number): {string}
    local unlocked = {}
    for name, data in pairs(TroopData) do
        if type(data) == "table" and data.townHallRequired and data.townHallRequired <= thLevel then
            table.insert(unlocked, name)
        end
    end
    return unlocked
end

return TroopData
