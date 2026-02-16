--!strict
--[[
    BossData.lua

    Boss monster definitions for the overworld.
    3-5 bosses total: 2 wilderness, 2-3 forbidden zone.

    Bosses have much stronger armies (TH 7-10 equivalent), long respawns,
    and unique loot (high resources + gems in forbidden zone).
    Co-op support: nearby players can join the fight.

    IMPORTANT: Changes to this file affect game balance.
    Consult combat-designer agent before modifications.
]]

local BossData = {}

-- ============================================================================
-- BOSS DEFINITIONS
-- ============================================================================

BossData.Bosses = {
    -- WILDERNESS BOSSES (2) — TH 5-7 equivalent
    {
        id = "boss_troll_king",
        name = "Troll King",
        description = "A massive troll warlord commanding a horde of brutes.",
        zone = "wilderness",
        x = 200, z = 200,
        troops = {
            { troopType = "Giant", level = 3, count = 5 },
            { troopType = "Barbarian", level = 3, count = 15 },
            { troopType = "Archer", level = 2, count = 8 },
        },
        loot = {
            gold = { min = 1000, max = 2000 },
            wood = { min = 800, max = 1500 },
            food = { min = 600, max = 1200 },
            gems = { min = 0, max = 3 },
        },
        respawnTime = 7200,  -- 2 hours
        appearance = {
            bodyColor = Color3.fromRGB(80, 130, 60),
            headColor = Color3.fromRGB(100, 150, 80),
            scale = 2.0,
        },
    },
    {
        id = "boss_bandit_lord",
        name = "Bandit Lord",
        description = "The cunning leader of all wilderness bandits.",
        zone = "wilderness",
        x = 1800, z = 200,
        troops = {
            { troopType = "Barbarian", level = 4, count = 20 },
            { troopType = "Archer", level = 3, count = 12 },
            { troopType = "Wizard", level = 2, count = 3 },
        },
        loot = {
            gold = { min = 1200, max = 2500 },
            wood = { min = 1000, max = 2000 },
            food = { min = 800, max = 1500 },
            gems = { min = 1, max = 5 },
        },
        respawnTime = 9000,  -- 2.5 hours
        appearance = {
            bodyColor = Color3.fromRGB(50, 20, 10),
            headColor = Color3.fromRGB(170, 130, 100),
            scale = 1.8,
        },
    },

    -- FORBIDDEN ZONE BOSSES (3) — TH 8-10 equivalent
    {
        id = "boss_frost_giant",
        name = "Frost Giant",
        description = "An ancient ice giant guarding the forbidden peaks.",
        zone = "forbidden",
        x = 1600, z = 1700,
        troops = {
            { troopType = "Giant", level = 4, count = 6 },
            { troopType = "Wizard", level = 3, count = 4 },
            { troopType = "Barbarian", level = 4, count = 10 },
        },
        loot = {
            gold = { min = 2000, max = 4000 },
            wood = { min = 1500, max = 3000 },
            food = { min = 1200, max = 2500 },
            gems = { min = 5, max = 15 },
        },
        respawnTime = 10800, -- 3 hours
        appearance = {
            bodyColor = Color3.fromRGB(150, 180, 220),
            headColor = Color3.fromRGB(180, 200, 240),
            scale = 2.5,
        },
    },
    {
        id = "boss_dark_sorcerer",
        name = "Dark Sorcerer",
        description = "A powerful mage who commands armies of shadow.",
        zone = "forbidden",
        x = 1800, z = 1600,
        troops = {
            { troopType = "Wizard", level = 4, count = 6 },
            { troopType = "Dragon", level = 2, count = 1 },
            { troopType = "Archer", level = 4, count = 10 },
        },
        loot = {
            gold = { min = 2500, max = 5000 },
            wood = { min = 2000, max = 4000 },
            food = { min = 1500, max = 3000 },
            gems = { min = 8, max = 20 },
        },
        respawnTime = 12600, -- 3.5 hours
        appearance = {
            bodyColor = Color3.fromRGB(40, 20, 60),
            headColor = Color3.fromRGB(160, 140, 180),
            scale = 1.6,
        },
    },
    {
        id = "boss_ancient_pekka",
        name = "Ancient P.E.K.K.A",
        description = "A legendary armored construct from a forgotten age.",
        zone = "forbidden",
        x = 1700, z = 1850,
        troops = {
            { troopType = "PEKKA", level = 3, count = 2 },
            { troopType = "Giant", level = 4, count = 4 },
            { troopType = "Wizard", level = 3, count = 3 },
            { troopType = "Barbarian", level = 4, count = 8 },
        },
        loot = {
            gold = { min = 3000, max = 6000 },
            wood = { min = 2500, max = 5000 },
            food = { min = 2000, max = 4000 },
            gems = { min = 10, max = 30 },
        },
        respawnTime = 14400, -- 4 hours
        appearance = {
            bodyColor = Color3.fromRGB(60, 50, 80),
            headColor = Color3.fromRGB(100, 80, 120),
            scale = 3.0,
        },
    },
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

function BossData.GetBossById(id: string): any?
    for _, boss in BossData.Bosses do
        if boss.id == id then
            return boss
        end
    end
    return nil
end

function BossData.GetAllBosses(): {any}
    return BossData.Bosses
end

function BossData.GetBossesByZone(zone: string): {any}
    local result = {}
    for _, boss in BossData.Bosses do
        if boss.zone == zone then
            table.insert(result, boss)
        end
    end
    return result
end

--[[
    Rolls random loot for a boss.
    @param bossId string
    @return {gold: number, wood: number, food: number, gems: number}?
]]
function BossData.RollLoot(bossId: string): {gold: number, wood: number, food: number, gems: number}?
    local boss = BossData.GetBossById(bossId)
    if not boss then return nil end

    local loot = boss.loot
    return {
        gold = math.random(loot.gold.min, loot.gold.max),
        wood = math.random(loot.wood.min, loot.wood.max),
        food = math.random(loot.food.min, loot.food.max),
        gems = math.random(loot.gems.min, loot.gems.max),
    }
end

return BossData
