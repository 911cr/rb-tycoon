--!strict
--[[
    SpellData.lua

    Spell definitions and effects for all spells in Battle Tycoon: Conquest.
    Reference: docs/GAME_DESIGN_DOCUMENT.md Section 5.4

    IMPORTANT: Changes to this file affect game balance.
    Consult combat-designer agent before modifications.
]]

-- Helper to create time in seconds
local function seconds(s: number): number return s end
local function minutes(m: number): number return m * 60 end

local SpellData = {}

--[[
    OFFENSIVE SPELLS
]]
SpellData.Lightning = {
    type = "Lightning",
    displayName = "Lightning Spell",
    description = "Strikes a target with powerful lightning bolts.",
    housingSpace = 2,
    townHallRequired = 3,
    spellFactoryLevel = 1,
    levels = {
        {
            level = 1,
            craftingTime = minutes(10),
            craftingCost = { gold = 15000 },
            radius = 2,
            duration = 0, -- instant
            totalDamage = 150,
            numberOfStrikes = 6,
        },
        {
            level = 2,
            craftingTime = minutes(10),
            craftingCost = { gold = 20000 },
            radius = 2,
            duration = 0,
            totalDamage = 180,
            numberOfStrikes = 6,
            upgradeCost = { gold = 200000 },
            upgradeTime = minutes(60),
        },
        {
            level = 3,
            craftingTime = minutes(10),
            craftingCost = { gold = 25000 },
            radius = 2,
            duration = 0,
            totalDamage = 210,
            numberOfStrikes = 6,
            upgradeCost = { gold = 500000 },
            upgradeTime = minutes(120),
        },
        {
            level = 4,
            craftingTime = minutes(10),
            craftingCost = { gold = 30000 },
            radius = 2,
            duration = 0,
            totalDamage = 240,
            numberOfStrikes = 6,
            upgradeCost = { gold = 1000000 },
            upgradeTime = minutes(240),
        },
        {
            level = 5,
            craftingTime = minutes(10),
            craftingCost = { gold = 35000 },
            radius = 2,
            duration = 0,
            totalDamage = 320,
            numberOfStrikes = 6,
            upgradeCost = { gold = 2000000 },
            upgradeTime = minutes(480),
        },
    },
}

SpellData.Earthquake = {
    type = "Earthquake",
    displayName = "Earthquake Spell",
    description = "Deals percentage damage to buildings. Multiple quakes stack!",
    housingSpace = 1,
    townHallRequired = 5,
    spellFactoryLevel = 3,
    levels = {
        {
            level = 1,
            craftingTime = minutes(5),
            craftingCost = { gold = 10000 },
            radius = 3.5,
            duration = 0,
            buildingDamagePercent = 14,
            wallDamageMultiplier = 4, -- 4x damage to walls
        },
        {
            level = 2,
            craftingTime = minutes(5),
            craftingCost = { gold = 12000 },
            radius = 3.5,
            duration = 0,
            buildingDamagePercent = 17,
            wallDamageMultiplier = 4,
            upgradeCost = { gold = 400000 },
            upgradeTime = minutes(90),
        },
        {
            level = 3,
            craftingTime = minutes(5),
            craftingCost = { gold = 14000 },
            radius = 3.5,
            duration = 0,
            buildingDamagePercent = 21,
            wallDamageMultiplier = 4,
            upgradeCost = { gold = 800000 },
            upgradeTime = minutes(180),
        },
        {
            level = 4,
            craftingTime = minutes(5),
            craftingCost = { gold = 16000 },
            radius = 3.5,
            duration = 0,
            buildingDamagePercent = 25,
            wallDamageMultiplier = 4,
            upgradeCost = { gold = 1600000 },
            upgradeTime = minutes(360),
        },
        {
            level = 5,
            craftingTime = minutes(5),
            craftingCost = { gold = 18000 },
            radius = 3.5,
            duration = 0,
            buildingDamagePercent = 29,
            wallDamageMultiplier = 4,
            upgradeCost = { gold = 3200000 },
            upgradeTime = minutes(720),
        },
    },
}

--[[
    SUPPORT SPELLS
]]
SpellData.Heal = {
    type = "Heal",
    displayName = "Healing Spell",
    description = "Heals all troops within its radius over time.",
    housingSpace = 2,
    townHallRequired = 4,
    spellFactoryLevel = 2,
    levels = {
        {
            level = 1,
            craftingTime = minutes(10),
            craftingCost = { gold = 15000 },
            radius = 5,
            duration = seconds(12),
            healPerSecond = 35,
            totalPulsesPerSecond = 5,
        },
        {
            level = 2,
            craftingTime = minutes(10),
            craftingCost = { gold = 20000 },
            radius = 5,
            duration = seconds(12),
            healPerSecond = 45,
            totalPulsesPerSecond = 5,
            upgradeCost = { gold = 300000 },
            upgradeTime = minutes(60),
        },
        {
            level = 3,
            craftingTime = minutes(10),
            craftingCost = { gold = 25000 },
            radius = 5,
            duration = seconds(12),
            healPerSecond = 55,
            totalPulsesPerSecond = 5,
            upgradeCost = { gold = 600000 },
            upgradeTime = minutes(120),
        },
        {
            level = 4,
            craftingTime = minutes(10),
            craftingCost = { gold = 30000 },
            radius = 5,
            duration = seconds(12),
            healPerSecond = 65,
            totalPulsesPerSecond = 5,
            upgradeCost = { gold = 1200000 },
            upgradeTime = minutes(240),
        },
        {
            level = 5,
            craftingTime = minutes(10),
            craftingCost = { gold = 35000 },
            radius = 5,
            duration = seconds(12),
            healPerSecond = 80,
            totalPulsesPerSecond = 5,
            upgradeCost = { gold = 2400000 },
            upgradeTime = minutes(480),
        },
    },
}

SpellData.Rage = {
    type = "Rage",
    displayName = "Rage Spell",
    description = "Boosts movement speed and damage of all troops in radius.",
    housingSpace = 2,
    townHallRequired = 5,
    spellFactoryLevel = 3,
    levels = {
        {
            level = 1,
            craftingTime = minutes(10),
            craftingCost = { gold = 20000 },
            radius = 5,
            duration = seconds(18),
            speedBoost = 1.2, -- 20% faster
            damageBoost = 1.3, -- 30% more damage
        },
        {
            level = 2,
            craftingTime = minutes(10),
            craftingCost = { gold = 26000 },
            radius = 5,
            duration = seconds(18),
            speedBoost = 1.24,
            damageBoost = 1.4,
            upgradeCost = { gold = 450000 },
            upgradeTime = minutes(90),
        },
        {
            level = 3,
            craftingTime = minutes(10),
            craftingCost = { gold = 32000 },
            radius = 5,
            duration = seconds(18),
            speedBoost = 1.28,
            damageBoost = 1.5,
            upgradeCost = { gold = 900000 },
            upgradeTime = minutes(180),
        },
        {
            level = 4,
            craftingTime = minutes(10),
            craftingCost = { gold = 38000 },
            radius = 5,
            duration = seconds(18),
            speedBoost = 1.32,
            damageBoost = 1.6,
            upgradeCost = { gold = 1800000 },
            upgradeTime = minutes(360),
        },
        {
            level = 5,
            craftingTime = minutes(10),
            craftingCost = { gold = 44000 },
            radius = 5.5,
            duration = seconds(18),
            speedBoost = 1.4,
            damageBoost = 1.7,
            upgradeCost = { gold = 3600000 },
            upgradeTime = minutes(720),
        },
    },
}

--[[
    UTILITY SPELLS
]]
SpellData.Freeze = {
    type = "Freeze",
    displayName = "Freeze Spell",
    description = "Freezes enemy defenses and troops in place.",
    housingSpace = 1,
    townHallRequired = 7,
    spellFactoryLevel = 4,
    levels = {
        {
            level = 1,
            craftingTime = minutes(8),
            craftingCost = { gold = 22000 },
            radius = 3.5,
            duration = seconds(4),
            freezeDuration = seconds(4),
        },
        {
            level = 2,
            craftingTime = minutes(8),
            craftingCost = { gold = 28000 },
            radius = 3.5,
            duration = seconds(5),
            freezeDuration = seconds(5),
            upgradeCost = { gold = 600000 },
            upgradeTime = minutes(120),
        },
        {
            level = 3,
            craftingTime = minutes(8),
            craftingCost = { gold = 34000 },
            radius = 3.5,
            duration = seconds(5.5),
            freezeDuration = seconds(5.5),
            upgradeCost = { gold = 1200000 },
            upgradeTime = minutes(240),
        },
        {
            level = 4,
            craftingTime = minutes(8),
            craftingCost = { gold = 40000 },
            radius = 4,
            duration = seconds(6),
            freezeDuration = seconds(6),
            upgradeCost = { gold = 2400000 },
            upgradeTime = minutes(480),
        },
        {
            level = 5,
            craftingTime = minutes(8),
            craftingCost = { gold = 46000 },
            radius = 4,
            duration = seconds(7),
            freezeDuration = seconds(7),
            upgradeCost = { gold = 4800000 },
            upgradeTime = minutes(960),
        },
    },
}

SpellData.Jump = {
    type = "Jump",
    displayName = "Jump Spell",
    description = "Ground troops can jump over walls in the affected area.",
    housingSpace = 2,
    townHallRequired = 6,
    spellFactoryLevel = 3,
    levels = {
        {
            level = 1,
            craftingTime = minutes(10),
            craftingCost = { gold = 23000 },
            radius = 3.5,
            duration = seconds(20),
        },
        {
            level = 2,
            craftingTime = minutes(10),
            craftingCost = { gold = 28000 },
            radius = 3.5,
            duration = seconds(40),
            upgradeCost = { gold = 500000 },
            upgradeTime = minutes(120),
        },
        {
            level = 3,
            craftingTime = minutes(10),
            craftingCost = { gold = 33000 },
            radius = 3.5,
            duration = seconds(60),
            upgradeCost = { gold = 1000000 },
            upgradeTime = minutes(240),
        },
        {
            level = 4,
            craftingTime = minutes(10),
            craftingCost = { gold = 38000 },
            radius = 4,
            duration = seconds(80),
            upgradeCost = { gold = 2000000 },
            upgradeTime = minutes(480),
        },
    },
}

-- Helper function to get spell data by type
function SpellData.GetByType(spellType: string): any?
    return SpellData[spellType]
end

-- Helper function to get level data
function SpellData.GetLevelData(spellType: string, level: number): any?
    local spell = SpellData[spellType]
    if not spell then return nil end
    return spell.levels[level]
end

-- Get all spells unlocked at a given TH level
function SpellData.GetUnlockedAtTH(thLevel: number): {string}
    local unlocked = {}
    for name, data in pairs(SpellData) do
        if type(data) == "table" and data.townHallRequired and data.townHallRequired <= thLevel then
            table.insert(unlocked, name)
        end
    end
    return unlocked
end

return SpellData
