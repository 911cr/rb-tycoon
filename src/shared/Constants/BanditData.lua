--!strict
--[[
    BanditData.lua

    Defines roaming bandit configurations for the overworld wilderness.
    Bandits patrol the wilderness and forbidden zones. Players engage them
    via the auto-clash combat system for loot rewards.

    Tiers 1-5 scale from Safe Zone edge to Forbidden Zone.
    Each tier defines troop compositions, loot tables, and visual config.

    IMPORTANT: Changes to this file affect game balance.
    Consult combat-designer agent before modifications.
]]

local BanditData = {}

-- ============================================================================
-- TIER DEFINITIONS
-- ============================================================================

BanditData.Tiers = {
    -- Tier 1: Safe Zone edge scouts — very weak, minimal loot
    [1] = {
        name = "Bandit Scout",
        troops = {
            { troopType = "Barbarian", level = 1, count = 3 },
        },
        loot = {
            gold = { min = 50, max = 150 },
            wood = { min = 30, max = 100 },
            food = { min = 20, max = 80 },
            gems = { min = 0, max = 0 },
        },
        appearance = {
            shirtColor = Color3.fromRGB(120, 60, 30),
            pantsColor = Color3.fromRGB(80, 50, 25),
            headColor = Color3.fromRGB(200, 160, 130),
        },
    },

    -- Tier 2: Inner wilderness — moderate group
    [2] = {
        name = "Bandit Thug",
        troops = {
            { troopType = "Barbarian", level = 1, count = 5 },
            { troopType = "Archer", level = 1, count = 3 },
        },
        loot = {
            gold = { min = 100, max = 300 },
            wood = { min = 80, max = 200 },
            food = { min = 60, max = 150 },
            gems = { min = 0, max = 0 },
        },
        appearance = {
            shirtColor = Color3.fromRGB(100, 40, 20),
            pantsColor = Color3.fromRGB(70, 40, 20),
            headColor = Color3.fromRGB(190, 150, 120),
        },
    },

    -- Tier 3: Mid wilderness — balanced army
    [3] = {
        name = "Bandit Raider",
        troops = {
            { troopType = "Barbarian", level = 2, count = 8 },
            { troopType = "Archer", level = 2, count = 5 },
            { troopType = "Giant", level = 1, count = 1 },
        },
        loot = {
            gold = { min = 200, max = 500 },
            wood = { min = 150, max = 400 },
            food = { min = 100, max = 300 },
            gems = { min = 0, max = 1 },
        },
        appearance = {
            shirtColor = Color3.fromRGB(80, 30, 15),
            pantsColor = Color3.fromRGB(60, 30, 15),
            headColor = Color3.fromRGB(180, 140, 110),
        },
    },

    -- Tier 4: Outer wilderness — veteran bandits
    [4] = {
        name = "Bandit Veteran",
        troops = {
            { troopType = "Barbarian", level = 3, count = 10 },
            { troopType = "Archer", level = 3, count = 6 },
            { troopType = "Giant", level = 2, count = 2 },
            { troopType = "Wizard", level = 1, count = 1 },
        },
        loot = {
            gold = { min = 400, max = 800 },
            wood = { min = 300, max = 600 },
            food = { min = 200, max = 500 },
            gems = { min = 0, max = 2 },
        },
        appearance = {
            shirtColor = Color3.fromRGB(60, 20, 10),
            pantsColor = Color3.fromRGB(50, 25, 10),
            headColor = Color3.fromRGB(170, 130, 100),
        },
    },

    -- Tier 5: Forbidden Zone — elite bandits with 2.5x stat multiplier
    [5] = {
        name = "Bandit Warlord",
        troops = {
            { troopType = "Barbarian", level = 4, count = 12 },
            { troopType = "Archer", level = 4, count = 8 },
            { troopType = "Giant", level = 3, count = 3 },
            { troopType = "Wizard", level = 2, count = 2 },
        },
        loot = {
            gold = { min = 600, max = 1200 },
            wood = { min = 500, max = 1000 },
            food = { min = 400, max = 800 },
            gems = { min = 1, max = 5 },
        },
        appearance = {
            shirtColor = Color3.fromRGB(40, 10, 10),
            pantsColor = Color3.fromRGB(30, 15, 10),
            headColor = Color3.fromRGB(160, 120, 90),
        },
    },
}

-- ============================================================================
-- SPAWN POSITIONS (approximate zones, actual Y determined by terrain raycast)
-- ============================================================================

-- Wilderness bandits (~25 total)
BanditData.WildernessSpawns = {
    -- Near safe zone edge (tier 1-2)
    { id = "bandit_w1", x = 550, z = 550, tier = 1 },
    { id = "bandit_w2", x = 1450, z = 550, tier = 1 },
    { id = "bandit_w3", x = 550, z = 1450, tier = 1 },
    { id = "bandit_w4", x = 1450, z = 1450, tier = 2 },
    { id = "bandit_w5", x = 500, z = 1000, tier = 1 },

    -- Inner wilderness (tier 2-3)
    { id = "bandit_w6", x = 400, z = 400, tier = 2 },
    { id = "bandit_w7", x = 1600, z = 400, tier = 2 },
    { id = "bandit_w8", x = 400, z = 1600, tier = 2 },
    { id = "bandit_w9", x = 1000, z = 200, tier = 3 },
    { id = "bandit_w10", x = 200, z = 1000, tier = 2 },

    -- Mid wilderness (tier 3)
    { id = "bandit_w11", x = 300, z = 300, tier = 3 },
    { id = "bandit_w12", x = 1700, z = 300, tier = 3 },
    { id = "bandit_w13", x = 300, z = 1700, tier = 3 },
    { id = "bandit_w14", x = 1700, z = 700, tier = 3 },
    { id = "bandit_w15", x = 700, z = 1700, tier = 3 },

    -- Outer wilderness (tier 4)
    { id = "bandit_w16", x = 150, z = 150, tier = 4 },
    { id = "bandit_w17", x = 1850, z = 150, tier = 4 },
    { id = "bandit_w18", x = 150, z = 1850, tier = 4 },
    { id = "bandit_w19", x = 1850, z = 600, tier = 4 },
    { id = "bandit_w20", x = 100, z = 600, tier = 4 },
    { id = "bandit_w21", x = 600, z = 100, tier = 4 },
    { id = "bandit_w22", x = 1900, z = 1200, tier = 4 },
    { id = "bandit_w23", x = 1200, z = 1900, tier = 4 },
    { id = "bandit_w24", x = 1850, z = 1850, tier = 4 },
    { id = "bandit_w25", x = 100, z = 1200, tier = 4 },
}

-- Forbidden Zone bandits (~8 total, tier 5)
BanditData.ForbiddenSpawns = {
    { id = "bandit_f1", x = 1550, z = 1550, tier = 5 },
    { id = "bandit_f2", x = 1750, z = 1550, tier = 5 },
    { id = "bandit_f3", x = 1550, z = 1750, tier = 5 },
    { id = "bandit_f4", x = 1750, z = 1750, tier = 5 },
    { id = "bandit_f5", x = 1650, z = 1650, tier = 5 },
    { id = "bandit_f6", x = 1850, z = 1550, tier = 5 },
    { id = "bandit_f7", x = 1550, z = 1850, tier = 5 },
    { id = "bandit_f8", x = 1850, z = 1850, tier = 5 },
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

function BanditData.GetTierData(tier: number): any?
    return BanditData.Tiers[tier]
end

function BanditData.GetAllSpawns(): {any}
    local all = {}
    for _, spawn in BanditData.WildernessSpawns do
        table.insert(all, spawn)
    end
    for _, spawn in BanditData.ForbiddenSpawns do
        table.insert(all, spawn)
    end
    return all
end

function BanditData.GetSpawnById(id: string): any?
    for _, spawn in BanditData.WildernessSpawns do
        if spawn.id == id then return spawn end
    end
    for _, spawn in BanditData.ForbiddenSpawns do
        if spawn.id == id then return spawn end
    end
    return nil
end

--[[
    Generates random loot within a tier's loot range.
    @param tier number - Bandit tier (1-5)
    @return {gold: number, wood: number, food: number, gems: number}
]]
function BanditData.RollLoot(tier: number): {gold: number, wood: number, food: number, gems: number}
    local data = BanditData.Tiers[tier]
    if not data then
        return { gold = 0, wood = 0, food = 0, gems = 0 }
    end

    local loot = data.loot
    return {
        gold = math.random(loot.gold.min, loot.gold.max),
        wood = math.random(loot.wood.min, loot.wood.max),
        food = math.random(loot.food.min, loot.food.max),
        gems = if loot.gems.max > 0 then math.random(loot.gems.min, loot.gems.max) else 0,
    }
end

return BanditData
