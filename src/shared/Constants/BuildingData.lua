--!strict
--[[
    BuildingData.lua

    Building definitions and stats for all buildings in Battle Tycoon: Conquest.
    Reference: docs/GAME_DESIGN_DOCUMENT.md Section 4

    IMPORTANT: Changes to this file affect game balance.
    Consult game-designer agent before modifications.
]]

local Types = require(script.Parent.Parent.Types.BuildingTypes)

-- Helper to create time in seconds
local function minutes(m: number): number return m * 60 end
local function hours(h: number): number return h * 3600 end

local BuildingData = {}

--[[
    TOWN HALL
    The central building that gates all progression.
]]
BuildingData.TownHall = {
    type = "TownHall",
    category = "core",
    displayName = "Town Hall",
    description = "The heart of your city. Upgrade to unlock new buildings and higher levels.",
    width = 4,
    height = 4,
    townHallRequired = 1,
    maxCount = 1,
    levels = {
        { level = 1, cost = { gold = 0 }, buildTime = 0, hp = 1500 },
        { level = 2, cost = { gold = 1000 }, buildTime = minutes(10), hp = 1800 },
        { level = 3, cost = { gold = 4000 }, buildTime = hours(1), hp = 2100 },
        { level = 4, cost = { gold = 25000 }, buildTime = hours(3), hp = 2500 },
        { level = 5, cost = { gold = 150000 }, buildTime = hours(8), hp = 2900 },
        { level = 6, cost = { gold = 750000 }, buildTime = hours(16), hp = 3300 },
        { level = 7, cost = { gold = 1200000 }, buildTime = hours(24), hp = 3700 },
        { level = 8, cost = { gold = 2000000 }, buildTime = hours(48), hp = 4100 },
        { level = 9, cost = { gold = 3000000 }, buildTime = hours(72), hp = 4600 },
        { level = 10, cost = { gold = 5000000 }, buildTime = hours(120), hp = 5500 },
    },
}

--[[
    RESOURCE BUILDINGS
]]
BuildingData.GoldMine = {
    type = "GoldMine",
    category = "resource",
    displayName = "Gold Mine",
    description = "Produces gold over time. Collect before storage fills up!",
    width = 3,
    height = 3,
    townHallRequired = 1,
    maxCount = 6, -- scales with TH
    levels = {
        { level = 1, cost = { gold = 150 }, buildTime = minutes(1), hp = 400, productionRate = 200, storageCapacity = 500 },
        { level = 2, cost = { gold = 300 }, buildTime = minutes(5), hp = 440, productionRate = 400, storageCapacity = 1000 },
        { level = 3, cost = { gold = 700 }, buildTime = minutes(15), hp = 480, productionRate = 600, storageCapacity = 1500 },
        { level = 4, cost = { gold = 1400 }, buildTime = minutes(30), hp = 520, productionRate = 800, storageCapacity = 2000 },
        { level = 5, cost = { gold = 3000 }, buildTime = hours(1), hp = 560, productionRate = 1000, storageCapacity = 3000 },
        { level = 6, cost = { gold = 7000 }, buildTime = hours(2), hp = 600, productionRate = 1300, storageCapacity = 4500 },
        { level = 7, cost = { gold = 14000 }, buildTime = hours(4), hp = 640, productionRate = 1600, storageCapacity = 6000 },
        { level = 8, cost = { gold = 28000 }, buildTime = hours(8), hp = 680, productionRate = 1900, storageCapacity = 8000 },
        { level = 9, cost = { gold = 56000 }, buildTime = hours(12), hp = 720, productionRate = 2200, storageCapacity = 10000 },
        { level = 10, cost = { gold = 100000 }, buildTime = hours(18), hp = 760, productionRate = 2600, storageCapacity = 13000 },
        { level = 11, cost = { gold = 200000 }, buildTime = hours(24), hp = 800, productionRate = 3000, storageCapacity = 16000 },
        { level = 12, cost = { gold = 400000 }, buildTime = hours(36), hp = 860, productionRate = 3500, storageCapacity = 20000 },
    },
}

BuildingData.LumberMill = {
    type = "LumberMill",
    category = "resource",
    displayName = "Lumber Mill",
    description = "Produces wood over time. Essential for building walls.",
    width = 3,
    height = 3,
    townHallRequired = 1,
    maxCount = 6,
    levels = {
        { level = 1, cost = { gold = 150 }, buildTime = minutes(1), hp = 400, productionRate = 150, storageCapacity = 400 },
        { level = 2, cost = { gold = 300 }, buildTime = minutes(5), hp = 440, productionRate = 300, storageCapacity = 800 },
        { level = 3, cost = { gold = 700 }, buildTime = minutes(15), hp = 480, productionRate = 450, storageCapacity = 1200 },
        { level = 4, cost = { gold = 1400 }, buildTime = minutes(30), hp = 520, productionRate = 600, storageCapacity = 1600 },
        { level = 5, cost = { gold = 3000 }, buildTime = hours(1), hp = 560, productionRate = 750, storageCapacity = 2500 },
        { level = 6, cost = { gold = 7000 }, buildTime = hours(2), hp = 600, productionRate = 975, storageCapacity = 3500 },
        { level = 7, cost = { gold = 14000 }, buildTime = hours(4), hp = 640, productionRate = 1200, storageCapacity = 4500 },
        { level = 8, cost = { gold = 28000 }, buildTime = hours(8), hp = 680, productionRate = 1425, storageCapacity = 6000 },
        { level = 9, cost = { gold = 56000 }, buildTime = hours(12), hp = 720, productionRate = 1650, storageCapacity = 7500 },
        { level = 10, cost = { gold = 100000 }, buildTime = hours(18), hp = 760, productionRate = 1950, storageCapacity = 10000 },
        { level = 11, cost = { gold = 200000 }, buildTime = hours(24), hp = 800, productionRate = 2250, storageCapacity = 12500 },
        { level = 12, cost = { gold = 400000 }, buildTime = hours(36), hp = 860, productionRate = 2600, storageCapacity = 15000 },
    },
}

BuildingData.Farm = {
    type = "Farm",
    category = "resource",
    displayName = "Farm",
    description = "Produces food for training troops.",
    width = 3,
    height = 3,
    townHallRequired = 1,
    maxCount = 6,
    levels = {
        { level = 1, cost = { gold = 100 }, buildTime = minutes(1), hp = 400, productionRate = 100, storageCapacity = 300 },
        { level = 2, cost = { gold = 200 }, buildTime = minutes(5), hp = 440, productionRate = 200, storageCapacity = 600 },
        { level = 3, cost = { gold = 500 }, buildTime = minutes(15), hp = 480, productionRate = 300, storageCapacity = 900 },
        { level = 4, cost = { gold = 1000 }, buildTime = minutes(30), hp = 520, productionRate = 400, storageCapacity = 1200 },
        { level = 5, cost = { gold = 2000 }, buildTime = hours(1), hp = 560, productionRate = 500, storageCapacity = 1800 },
        { level = 6, cost = { gold = 5000 }, buildTime = hours(2), hp = 600, productionRate = 650, storageCapacity = 2500 },
        { level = 7, cost = { gold = 10000 }, buildTime = hours(4), hp = 640, productionRate = 800, storageCapacity = 3200 },
        { level = 8, cost = { gold = 20000 }, buildTime = hours(8), hp = 680, productionRate = 950, storageCapacity = 4000 },
        { level = 9, cost = { gold = 40000 }, buildTime = hours(12), hp = 720, productionRate = 1100, storageCapacity = 5000 },
        { level = 10, cost = { gold = 80000 }, buildTime = hours(18), hp = 760, productionRate = 1300, storageCapacity = 6500 },
        { level = 11, cost = { gold = 160000 }, buildTime = hours(24), hp = 800, productionRate = 1500, storageCapacity = 8000 },
        { level = 12, cost = { gold = 320000 }, buildTime = hours(36), hp = 860, productionRate = 1750, storageCapacity = 10000 },
    },
}

BuildingData.GoldStorage = {
    type = "GoldStorage",
    category = "storage",
    displayName = "Gold Storage",
    description = "Stores gold. Build more to increase your maximum gold.",
    width = 3,
    height = 3,
    townHallRequired = 1,
    maxCount = 4,
    levels = {
        { level = 1, cost = { gold = 300 }, buildTime = minutes(1), hp = 400, storageCapacity = 1500 },
        { level = 2, cost = { gold = 750 }, buildTime = minutes(10), hp = 600, storageCapacity = 3000 },
        { level = 3, cost = { gold = 1500 }, buildTime = minutes(30), hp = 800, storageCapacity = 6000 },
        { level = 4, cost = { gold = 3000 }, buildTime = hours(1), hp = 1000, storageCapacity = 12000 },
        { level = 5, cost = { gold = 6000 }, buildTime = hours(2), hp = 1200, storageCapacity = 25000 },
        { level = 6, cost = { gold = 12000 }, buildTime = hours(4), hp = 1400, storageCapacity = 50000 },
        { level = 7, cost = { gold = 25000 }, buildTime = hours(6), hp = 1600, storageCapacity = 100000 },
        { level = 8, cost = { gold = 50000 }, buildTime = hours(8), hp = 1800, storageCapacity = 250000 },
        { level = 9, cost = { gold = 100000 }, buildTime = hours(12), hp = 2100, storageCapacity = 500000 },
        { level = 10, cost = { gold = 250000 }, buildTime = hours(18), hp = 2500, storageCapacity = 1000000 },
    },
}

--[[
    MILITARY BUILDINGS
]]
BuildingData.Barracks = {
    type = "Barracks",
    category = "military",
    displayName = "Barracks",
    description = "Train ground troops like Barbarians and Giants.",
    width = 3,
    height = 3,
    townHallRequired = 1,
    maxCount = 4,
    levels = {
        { level = 1, cost = { gold = 200 }, buildTime = minutes(1), hp = 250, trainingCapacity = 20 },
        { level = 2, cost = { gold = 1000 }, buildTime = minutes(15), hp = 290, trainingCapacity = 25 },
        { level = 3, cost = { gold = 2500 }, buildTime = minutes(30), hp = 330, trainingCapacity = 30 },
        { level = 4, cost = { gold = 5000 }, buildTime = hours(1), hp = 370, trainingCapacity = 35 },
        { level = 5, cost = { gold = 10000 }, buildTime = hours(2), hp = 420, trainingCapacity = 40 },
        { level = 6, cost = { gold = 25000 }, buildTime = hours(4), hp = 470, trainingCapacity = 45 },
        { level = 7, cost = { gold = 50000 }, buildTime = hours(6), hp = 520, trainingCapacity = 50 },
        { level = 8, cost = { gold = 100000 }, buildTime = hours(8), hp = 580, trainingCapacity = 55 },
        { level = 9, cost = { gold = 200000 }, buildTime = hours(12), hp = 640, trainingCapacity = 60 },
        { level = 10, cost = { gold = 400000 }, buildTime = hours(18), hp = 720, trainingCapacity = 70 },
    },
}

BuildingData.ArmyCamp = {
    type = "ArmyCamp",
    category = "military",
    displayName = "Army Camp",
    description = "Houses your trained troops. More camps = bigger army!",
    width = 4,
    height = 4,
    townHallRequired = 1,
    maxCount = 4,
    levels = {
        { level = 1, cost = { gold = 250 }, buildTime = minutes(5), hp = 250, housingCapacity = 20 },
        { level = 2, cost = { gold = 2500 }, buildTime = minutes(30), hp = 270, housingCapacity = 30 },
        { level = 3, cost = { gold = 10000 }, buildTime = hours(2), hp = 290, housingCapacity = 40 },
        { level = 4, cost = { gold = 100000 }, buildTime = hours(4), hp = 310, housingCapacity = 50 },
        { level = 5, cost = { gold = 250000 }, buildTime = hours(8), hp = 330, housingCapacity = 60 },
        { level = 6, cost = { gold = 750000 }, buildTime = hours(12), hp = 350, housingCapacity = 70 },
        { level = 7, cost = { gold = 1500000 }, buildTime = hours(18), hp = 380, housingCapacity = 80 },
        { level = 8, cost = { gold = 2500000 }, buildTime = hours(24), hp = 400, housingCapacity = 90 },
    },
}

BuildingData.SpellFactory = {
    type = "SpellFactory",
    category = "military",
    displayName = "Spell Factory",
    description = "Brew powerful spells to support your troops in battle.",
    width = 3,
    height = 3,
    townHallRequired = 3,
    maxCount = 1,
    levels = {
        { level = 1, cost = { gold = 10000 }, buildTime = hours(1), hp = 475, trainingCapacity = 2 },
        { level = 2, cost = { gold = 50000 }, buildTime = hours(4), hp = 510, trainingCapacity = 4 },
        { level = 3, cost = { gold = 200000 }, buildTime = hours(8), hp = 545, trainingCapacity = 6 },
        { level = 4, cost = { gold = 500000 }, buildTime = hours(16), hp = 580, trainingCapacity = 8 },
        { level = 5, cost = { gold = 1000000 }, buildTime = hours(24), hp = 625, trainingCapacity = 10 },
    },
}

--[[
    DEFENSIVE BUILDINGS
]]
BuildingData.Cannon = {
    type = "Cannon",
    category = "defense",
    displayName = "Cannon",
    description = "Basic defense that shoots ground targets.",
    width = 3,
    height = 3,
    townHallRequired = 1,
    maxCount = 6, -- scales with TH
    levels = {
        { level = 1, cost = { gold = 250 }, buildTime = minutes(1), hp = 420, damage = 9, attackSpeed = 0.8, range = 9, targetType = "ground" },
        { level = 2, cost = { gold = 1000 }, buildTime = minutes(15), hp = 470, damage = 11, attackSpeed = 0.8, range = 9, targetType = "ground" },
        { level = 3, cost = { gold = 4000 }, buildTime = minutes(45), hp = 520, damage = 15, attackSpeed = 0.8, range = 9, targetType = "ground" },
        { level = 4, cost = { gold = 16000 }, buildTime = hours(2), hp = 570, damage = 19, attackSpeed = 0.8, range = 9, targetType = "ground" },
        { level = 5, cost = { gold = 50000 }, buildTime = hours(4), hp = 620, damage = 25, attackSpeed = 0.8, range = 9, targetType = "ground" },
        { level = 6, cost = { gold = 100000 }, buildTime = hours(8), hp = 670, damage = 31, attackSpeed = 0.8, range = 9, targetType = "ground" },
        { level = 7, cost = { gold = 200000 }, buildTime = hours(12), hp = 730, damage = 40, attackSpeed = 0.8, range = 9, targetType = "ground" },
        { level = 8, cost = { gold = 400000 }, buildTime = hours(18), hp = 800, damage = 48, attackSpeed = 0.8, range = 9, targetType = "ground" },
        { level = 9, cost = { gold = 800000 }, buildTime = hours(24), hp = 880, damage = 56, attackSpeed = 0.8, range = 9, targetType = "ground" },
        { level = 10, cost = { gold = 1600000 }, buildTime = hours(36), hp = 960, damage = 65, attackSpeed = 0.8, range = 9, targetType = "ground" },
    },
}

BuildingData.ArcherTower = {
    type = "ArcherTower",
    category = "defense",
    displayName = "Archer Tower",
    description = "Shoots both ground and air targets from long range.",
    width = 3,
    height = 3,
    townHallRequired = 2,
    maxCount = 6,
    levels = {
        { level = 1, cost = { gold = 1000 }, buildTime = minutes(5), hp = 380, damage = 11, attackSpeed = 1, range = 10, targetType = "both" },
        { level = 2, cost = { gold = 2000 }, buildTime = minutes(15), hp = 420, damage = 15, attackSpeed = 1, range = 10, targetType = "both" },
        { level = 3, cost = { gold = 5000 }, buildTime = minutes(45), hp = 460, damage = 19, attackSpeed = 1, range = 10, targetType = "both" },
        { level = 4, cost = { gold = 20000 }, buildTime = hours(2), hp = 500, damage = 25, attackSpeed = 1, range = 10, targetType = "both" },
        { level = 5, cost = { gold = 80000 }, buildTime = hours(4), hp = 540, damage = 30, attackSpeed = 1, range = 10, targetType = "both" },
        { level = 6, cost = { gold = 180000 }, buildTime = hours(8), hp = 580, damage = 35, attackSpeed = 1, range = 10, targetType = "both" },
        { level = 7, cost = { gold = 360000 }, buildTime = hours(12), hp = 630, damage = 42, attackSpeed = 1, range = 10, targetType = "both" },
        { level = 8, cost = { gold = 720000 }, buildTime = hours(18), hp = 690, damage = 48, attackSpeed = 1, range = 10, targetType = "both" },
        { level = 9, cost = { gold = 1400000 }, buildTime = hours(24), hp = 750, damage = 56, attackSpeed = 1, range = 10, targetType = "both" },
        { level = 10, cost = { gold = 2800000 }, buildTime = hours(36), hp = 820, damage = 65, attackSpeed = 1, range = 10, targetType = "both" },
    },
}

BuildingData.Mortar = {
    type = "Mortar",
    category = "defense",
    displayName = "Mortar",
    description = "Fires explosive shells that deal splash damage to ground targets.",
    width = 3,
    height = 3,
    townHallRequired = 3,
    maxCount = 4,
    levels = {
        { level = 1, cost = { gold = 8000 }, buildTime = hours(1), hp = 400, damage = 20, attackSpeed = 0.2, range = 11, targetType = "ground", splashRadius = 1.5 },
        { level = 2, cost = { gold = 32000 }, buildTime = hours(3), hp = 450, damage = 25, attackSpeed = 0.2, range = 11, targetType = "ground", splashRadius = 1.5 },
        { level = 3, cost = { gold = 120000 }, buildTime = hours(6), hp = 500, damage = 30, attackSpeed = 0.2, range = 11, targetType = "ground", splashRadius = 1.5 },
        { level = 4, cost = { gold = 400000 }, buildTime = hours(12), hp = 550, damage = 35, attackSpeed = 0.2, range = 11, targetType = "ground", splashRadius = 1.5 },
        { level = 5, cost = { gold = 800000 }, buildTime = hours(18), hp = 600, damage = 40, attackSpeed = 0.2, range = 11, targetType = "ground", splashRadius = 1.5 },
        { level = 6, cost = { gold = 1600000 }, buildTime = hours(24), hp = 650, damage = 45, attackSpeed = 0.2, range = 11, targetType = "ground", splashRadius = 1.5 },
        { level = 7, cost = { gold = 2400000 }, buildTime = hours(36), hp = 700, damage = 50, attackSpeed = 0.2, range = 11, targetType = "ground", splashRadius = 1.5 },
        { level = 8, cost = { gold = 3200000 }, buildTime = hours(48), hp = 780, damage = 55, attackSpeed = 0.2, range = 11, targetType = "ground", splashRadius = 1.5 },
    },
}

BuildingData.AirDefense = {
    type = "AirDefense",
    category = "defense",
    displayName = "Air Defense",
    description = "Powerful anti-air defense. Essential against Dragons!",
    width = 3,
    height = 3,
    townHallRequired = 4,
    maxCount = 3,
    levels = {
        { level = 1, cost = { gold = 22500 }, buildTime = hours(2), hp = 800, damage = 80, attackSpeed = 1, range = 10, targetType = "air" },
        { level = 2, cost = { gold = 90000 }, buildTime = hours(4), hp = 850, damage = 110, attackSpeed = 1, range = 10, targetType = "air" },
        { level = 3, cost = { gold = 270000 }, buildTime = hours(8), hp = 900, damage = 140, attackSpeed = 1, range = 10, targetType = "air" },
        { level = 4, cost = { gold = 540000 }, buildTime = hours(12), hp = 950, damage = 170, attackSpeed = 1, range = 10, targetType = "air" },
        { level = 5, cost = { gold = 1080000 }, buildTime = hours(18), hp = 1000, damage = 200, attackSpeed = 1, range = 10, targetType = "air" },
        { level = 6, cost = { gold = 2160000 }, buildTime = hours(24), hp = 1050, damage = 230, attackSpeed = 1, range = 10, targetType = "air" },
        { level = 7, cost = { gold = 4320000 }, buildTime = hours(36), hp = 1100, damage = 260, attackSpeed = 1, range = 10, targetType = "air" },
        { level = 8, cost = { gold = 6400000 }, buildTime = hours(48), hp = 1150, damage = 290, attackSpeed = 1, range = 10, targetType = "air" },
    },
}

BuildingData.WizardTower = {
    type = "WizardTower",
    category = "defense",
    displayName = "Wizard Tower",
    description = "Magical tower that deals splash damage to ground and air.",
    width = 3,
    height = 3,
    townHallRequired = 5,
    maxCount = 3,
    levels = {
        { level = 1, cost = { gold = 180000 }, buildTime = hours(4), hp = 620, damage = 24, attackSpeed = 0.7, range = 7, targetType = "both", splashRadius = 1 },
        { level = 2, cost = { gold = 360000 }, buildTime = hours(8), hp = 660, damage = 32, attackSpeed = 0.7, range = 7, targetType = "both", splashRadius = 1 },
        { level = 3, cost = { gold = 720000 }, buildTime = hours(12), hp = 700, damage = 40, attackSpeed = 0.7, range = 7, targetType = "both", splashRadius = 1 },
        { level = 4, cost = { gold = 1280000 }, buildTime = hours(18), hp = 740, damage = 48, attackSpeed = 0.7, range = 7, targetType = "both", splashRadius = 1 },
        { level = 5, cost = { gold = 2560000 }, buildTime = hours(24), hp = 780, damage = 56, attackSpeed = 0.7, range = 7, targetType = "both", splashRadius = 1 },
        { level = 6, cost = { gold = 3840000 }, buildTime = hours(36), hp = 840, damage = 64, attackSpeed = 0.7, range = 7, targetType = "both", splashRadius = 1 },
        { level = 7, cost = { gold = 5120000 }, buildTime = hours(48), hp = 900, damage = 72, attackSpeed = 0.7, range = 7, targetType = "both", splashRadius = 1 },
    },
}

--[[
    WALLS
]]
BuildingData.Wall = {
    type = "Wall",
    category = "wall",
    displayName = "Wall",
    description = "Walls slow down enemy troops and protect your buildings.",
    width = 1,
    height = 1,
    townHallRequired = 1,
    maxCount = 250, -- increases with TH
    levels = {
        { level = 1, cost = { gold = 50 }, buildTime = 0, hp = 300 },
        { level = 2, cost = { gold = 1000 }, buildTime = 0, hp = 500 },
        { level = 3, cost = { gold = 5000 }, buildTime = 0, hp = 700 },
        { level = 4, cost = { gold = 10000 }, buildTime = 0, hp = 900 },
        { level = 5, cost = { gold = 30000 }, buildTime = 0, hp = 1400 },
        { level = 6, cost = { gold = 75000 }, buildTime = 0, hp = 2000 },
        { level = 7, cost = { gold = 200000 }, buildTime = 0, hp = 2500 },
        { level = 8, cost = { gold = 500000 }, buildTime = 0, hp = 3000 },
        { level = 9, cost = { gold = 1000000 }, buildTime = 0, hp = 4000 },
        { level = 10, cost = { gold = 2000000 }, buildTime = 0, hp = 5500 },
    },
}

-- Helper function to get building data by type
function BuildingData.GetByType(buildingType: string): any?
    return BuildingData[buildingType]
end

-- Helper function to get level data
function BuildingData.GetLevelData(buildingType: string, level: number): any?
    local building = BuildingData[buildingType]
    if not building then return nil end
    return building.levels[level]
end

return BuildingData
