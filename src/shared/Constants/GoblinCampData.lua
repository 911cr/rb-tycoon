--!strict
--[[
    GoblinCampData.lua

    Defines PvE goblin camp configurations for Battle Tycoon: Conquest.
    Goblin camps are NPC bases scattered across the overworld that players
    can attack for guaranteed loot. Camps respawn after being cleared.

    IMPORTANT: Changes to this file affect game balance.
    Consult game-designer agent before modifications.

    Each camp defines:
    - Unique id and themed name
    - Difficulty tier (Easy, Medium, Hard)
    - Town Hall equivalent level (simulated base strength)
    - Overworld position for visual marker placement
    - Guaranteed loot rewards
    - Respawn timer
    - Building layout for the battle arena
    - All defense buildings ALWAYS fire (no research gate)
]]

local GoblinCampData = {}

-- Respawn times by difficulty (in seconds)
local RESPAWN_EASY = 14400    -- 4 hours
local RESPAWN_MEDIUM = 18000  -- 5 hours
local RESPAWN_HARD = 21600    -- 6 hours

GoblinCampData.Camps = {
    -- ═══════════════════════════════════════════════════════════════════════════
    -- EASY CAMPS (TH 2-3) - For new players
    -- Loot: 500-800 gold, 300-500 wood, 200-300 food
    -- Few buildings, 1-2 defenses
    -- ═══════════════════════════════════════════════════════════════════════════
    {
        id = "goblin_camp_1",
        name = "Goblin Outpost",
        difficulty = "Easy",
        thEquivalent = 2,
        position = Vector3.new(500, 0, 500),
        loot = { gold = 500, wood = 300, food = 200 },
        respawnTime = RESPAWN_EASY,
        buildings = {
            { type = "TownHall", level = 2, gridPos = Vector3.new(4, 0, 4), hp = 800 },
            { type = "Cannon", level = 1, gridPos = Vector3.new(2, 0, 2), hp = 420 },
            { type = "GoldStorage", level = 1, gridPos = Vector3.new(6, 0, 4), hp = 400 },
            { type = "Wall", level = 1, gridPos = Vector3.new(3, 0, 1), hp = 300 },
            { type = "Wall", level = 1, gridPos = Vector3.new(4, 0, 1), hp = 300 },
            { type = "Wall", level = 1, gridPos = Vector3.new(5, 0, 1), hp = 300 },
        },
    },
    {
        id = "goblin_camp_2",
        name = "Goblin Hideout",
        difficulty = "Easy",
        thEquivalent = 2,
        position = Vector3.new(1500, 0, 400),
        loot = { gold = 600, wood = 350, food = 250 },
        respawnTime = RESPAWN_EASY,
        buildings = {
            { type = "TownHall", level = 2, gridPos = Vector3.new(5, 0, 5), hp = 800 },
            { type = "ArcherTower", level = 1, gridPos = Vector3.new(7, 0, 3), hp = 380 },
            { type = "GoldMine", level = 2, gridPos = Vector3.new(3, 0, 3), hp = 440 },
            { type = "Wall", level = 1, gridPos = Vector3.new(4, 0, 2), hp = 300 },
            { type = "Wall", level = 1, gridPos = Vector3.new(5, 0, 2), hp = 300 },
            { type = "Wall", level = 1, gridPos = Vector3.new(6, 0, 2), hp = 300 },
            { type = "Wall", level = 1, gridPos = Vector3.new(6, 0, 3), hp = 300 },
        },
    },
    {
        id = "goblin_camp_3",
        name = "Goblin Burrow",
        difficulty = "Easy",
        thEquivalent = 3,
        position = Vector3.new(800, 0, 1500),
        loot = { gold = 800, wood = 500, food = 300 },
        respawnTime = RESPAWN_EASY,
        buildings = {
            { type = "TownHall", level = 3, gridPos = Vector3.new(5, 0, 5), hp = 1200 },
            { type = "Cannon", level = 2, gridPos = Vector3.new(3, 0, 3), hp = 470 },
            { type = "ArcherTower", level = 1, gridPos = Vector3.new(7, 0, 3), hp = 380 },
            { type = "GoldStorage", level = 2, gridPos = Vector3.new(2, 0, 6), hp = 600 },
            { type = "LumberMill", level = 2, gridPos = Vector3.new(8, 0, 6), hp = 440 },
            { type = "Wall", level = 2, gridPos = Vector3.new(3, 0, 2), hp = 500 },
            { type = "Wall", level = 2, gridPos = Vector3.new(4, 0, 2), hp = 500 },
            { type = "Wall", level = 2, gridPos = Vector3.new(5, 0, 2), hp = 500 },
            { type = "Wall", level = 2, gridPos = Vector3.new(6, 0, 2), hp = 500 },
            { type = "Wall", level = 2, gridPos = Vector3.new(7, 0, 2), hp = 500 },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- MEDIUM CAMPS (TH 4-6) - For mid-game players
    -- Loot: 1500-2500 gold, 1000-1500 wood, 500-800 food
    -- More buildings, 3-4 defenses
    -- ═══════════════════════════════════════════════════════════════════════════
    {
        id = "goblin_camp_4",
        name = "Goblin Village",
        difficulty = "Medium",
        thEquivalent = 4,
        position = Vector3.new(350, 0, 1100),
        loot = { gold = 1500, wood = 1000, food = 500 },
        respawnTime = RESPAWN_MEDIUM,
        buildings = {
            { type = "TownHall", level = 4, gridPos = Vector3.new(5, 0, 5), hp = 2500 },
            { type = "Cannon", level = 3, gridPos = Vector3.new(2, 0, 3), hp = 520 },
            { type = "ArcherTower", level = 2, gridPos = Vector3.new(8, 0, 3), hp = 420 },
            { type = "Mortar", level = 1, gridPos = Vector3.new(5, 0, 8), hp = 400 },
            { type = "GoldStorage", level = 3, gridPos = Vector3.new(3, 0, 7), hp = 800 },
            { type = "GoldMine", level = 3, gridPos = Vector3.new(7, 0, 7), hp = 480 },
            { type = "LumberMill", level = 3, gridPos = Vector3.new(2, 0, 7), hp = 480 },
            { type = "Farm", level = 2, gridPos = Vector3.new(8, 0, 7), hp = 440 },
            { type = "Wall", level = 3, gridPos = Vector3.new(3, 0, 2), hp = 700 },
            { type = "Wall", level = 3, gridPos = Vector3.new(4, 0, 2), hp = 700 },
            { type = "Wall", level = 3, gridPos = Vector3.new(5, 0, 2), hp = 700 },
            { type = "Wall", level = 3, gridPos = Vector3.new(6, 0, 2), hp = 700 },
            { type = "Wall", level = 3, gridPos = Vector3.new(7, 0, 2), hp = 700 },
        },
    },
    {
        id = "goblin_camp_5",
        name = "Goblin Fortress",
        difficulty = "Medium",
        thEquivalent = 5,
        position = Vector3.new(1200, 0, 900),
        loot = { gold = 2000, wood = 1200, food = 650 },
        respawnTime = RESPAWN_MEDIUM,
        buildings = {
            { type = "TownHall", level = 5, gridPos = Vector3.new(5, 0, 5), hp = 2900 },
            { type = "Cannon", level = 4, gridPos = Vector3.new(2, 0, 3), hp = 570 },
            { type = "ArcherTower", level = 3, gridPos = Vector3.new(8, 0, 3), hp = 460 },
            { type = "Mortar", level = 2, gridPos = Vector3.new(5, 0, 9), hp = 450 },
            { type = "AirDefense", level = 1, gridPos = Vector3.new(5, 0, 2), hp = 800 },
            { type = "GoldStorage", level = 4, gridPos = Vector3.new(3, 0, 7), hp = 1000 },
            { type = "GoldMine", level = 4, gridPos = Vector3.new(7, 0, 7), hp = 520 },
            { type = "LumberMill", level = 4, gridPos = Vector3.new(2, 0, 7), hp = 520 },
            { type = "Farm", level = 3, gridPos = Vector3.new(8, 0, 7), hp = 480 },
            { type = "Barracks", level = 3, gridPos = Vector3.new(1, 0, 5), hp = 330 },
            { type = "Wall", level = 4, gridPos = Vector3.new(3, 0, 2), hp = 900 },
            { type = "Wall", level = 4, gridPos = Vector3.new(4, 0, 2), hp = 900 },
            { type = "Wall", level = 4, gridPos = Vector3.new(5, 0, 1), hp = 900 },
            { type = "Wall", level = 4, gridPos = Vector3.new(6, 0, 2), hp = 900 },
            { type = "Wall", level = 4, gridPos = Vector3.new(7, 0, 2), hp = 900 },
            { type = "Wall", level = 4, gridPos = Vector3.new(2, 0, 3), hp = 900 },
            { type = "Wall", level = 4, gridPos = Vector3.new(8, 0, 3), hp = 900 },
        },
    },
    {
        id = "goblin_camp_6",
        name = "Goblin Encampment",
        difficulty = "Medium",
        thEquivalent = 6,
        position = Vector3.new(700, 0, 600),
        loot = { gold = 2500, wood = 1500, food = 800 },
        respawnTime = RESPAWN_MEDIUM,
        buildings = {
            { type = "TownHall", level = 6, gridPos = Vector3.new(5, 0, 5), hp = 3300 },
            { type = "Cannon", level = 5, gridPos = Vector3.new(2, 0, 3), hp = 620 },
            { type = "ArcherTower", level = 4, gridPos = Vector3.new(8, 0, 3), hp = 500 },
            { type = "Mortar", level = 2, gridPos = Vector3.new(5, 0, 9), hp = 450 },
            { type = "WizardTower", level = 1, gridPos = Vector3.new(3, 0, 5), hp = 620 },
            { type = "GoldStorage", level = 5, gridPos = Vector3.new(3, 0, 7), hp = 1200 },
            { type = "GoldMine", level = 5, gridPos = Vector3.new(7, 0, 7), hp = 560 },
            { type = "LumberMill", level = 5, gridPos = Vector3.new(2, 0, 8), hp = 560 },
            { type = "Farm", level = 4, gridPos = Vector3.new(8, 0, 7), hp = 520 },
            { type = "Farm", level = 3, gridPos = Vector3.new(9, 0, 5), hp = 480 },
            { type = "Barracks", level = 4, gridPos = Vector3.new(1, 0, 5), hp = 370 },
            { type = "Wall", level = 5, gridPos = Vector3.new(3, 0, 2), hp = 1400 },
            { type = "Wall", level = 5, gridPos = Vector3.new(4, 0, 2), hp = 1400 },
            { type = "Wall", level = 5, gridPos = Vector3.new(5, 0, 1), hp = 1400 },
            { type = "Wall", level = 5, gridPos = Vector3.new(6, 0, 2), hp = 1400 },
            { type = "Wall", level = 5, gridPos = Vector3.new(7, 0, 2), hp = 1400 },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- HARD CAMPS (TH 7-9) - For endgame players
    -- Loot: 5000-8000 gold, 3000-5000 wood, 1500-2500 food
    -- Many buildings, 5-6 defenses
    -- ═══════════════════════════════════════════════════════════════════════════
    {
        id = "goblin_camp_7",
        name = "Goblin Stronghold",
        difficulty = "Hard",
        thEquivalent = 7,
        position = Vector3.new(300, 0, 1700),
        loot = { gold = 5000, wood = 3000, food = 1500 },
        respawnTime = RESPAWN_HARD,
        buildings = {
            { type = "TownHall", level = 7, gridPos = Vector3.new(5, 0, 5), hp = 3700 },
            { type = "Cannon", level = 6, gridPos = Vector3.new(2, 0, 3), hp = 670 },
            { type = "Cannon", level = 5, gridPos = Vector3.new(8, 0, 8), hp = 620 },
            { type = "ArcherTower", level = 5, gridPos = Vector3.new(8, 0, 3), hp = 540 },
            { type = "Mortar", level = 3, gridPos = Vector3.new(5, 0, 9), hp = 500 },
            { type = "AirDefense", level = 3, gridPos = Vector3.new(5, 0, 2), hp = 900 },
            { type = "WizardTower", level = 2, gridPos = Vector3.new(3, 0, 5), hp = 660 },
            { type = "GoldStorage", level = 6, gridPos = Vector3.new(3, 0, 7), hp = 1400 },
            { type = "GoldMine", level = 6, gridPos = Vector3.new(7, 0, 7), hp = 600 },
            { type = "LumberMill", level = 6, gridPos = Vector3.new(2, 0, 8), hp = 600 },
            { type = "Farm", level = 5, gridPos = Vector3.new(8, 0, 7), hp = 560 },
            { type = "Farm", level = 4, gridPos = Vector3.new(9, 0, 5), hp = 520 },
            { type = "Barracks", level = 5, gridPos = Vector3.new(1, 0, 5), hp = 420 },
            { type = "SpellFactory", level = 1, gridPos = Vector3.new(1, 0, 7), hp = 475 },
            { type = "Wall", level = 6, gridPos = Vector3.new(3, 0, 2), hp = 2000 },
            { type = "Wall", level = 6, gridPos = Vector3.new(4, 0, 2), hp = 2000 },
            { type = "Wall", level = 6, gridPos = Vector3.new(5, 0, 1), hp = 2000 },
            { type = "Wall", level = 6, gridPos = Vector3.new(6, 0, 2), hp = 2000 },
            { type = "Wall", level = 6, gridPos = Vector3.new(7, 0, 2), hp = 2000 },
            { type = "Wall", level = 6, gridPos = Vector3.new(2, 0, 3), hp = 2000 },
            { type = "Wall", level = 6, gridPos = Vector3.new(8, 0, 3), hp = 2000 },
            { type = "Wall", level = 6, gridPos = Vector3.new(2, 0, 4), hp = 2000 },
            { type = "Wall", level = 6, gridPos = Vector3.new(8, 0, 4), hp = 2000 },
        },
    },
    {
        id = "goblin_camp_8",
        name = "Goblin Citadel",
        difficulty = "Hard",
        thEquivalent = 9,
        position = Vector3.new(1600, 0, 1600),
        loot = { gold = 8000, wood = 5000, food = 2500 },
        respawnTime = RESPAWN_HARD,
        buildings = {
            { type = "TownHall", level = 9, gridPos = Vector3.new(5, 0, 5), hp = 4600 },
            { type = "Cannon", level = 7, gridPos = Vector3.new(2, 0, 3), hp = 730 },
            { type = "Cannon", level = 7, gridPos = Vector3.new(8, 0, 8), hp = 730 },
            { type = "ArcherTower", level = 7, gridPos = Vector3.new(8, 0, 3), hp = 630 },
            { type = "Mortar", level = 5, gridPos = Vector3.new(5, 0, 9), hp = 600 },
            { type = "AirDefense", level = 5, gridPos = Vector3.new(5, 0, 2), hp = 1000 },
            { type = "WizardTower", level = 4, gridPos = Vector3.new(3, 0, 5), hp = 740 },
            { type = "GoldStorage", level = 8, gridPos = Vector3.new(3, 0, 7), hp = 1800 },
            { type = "GoldMine", level = 8, gridPos = Vector3.new(7, 0, 7), hp = 680 },
            { type = "LumberMill", level = 8, gridPos = Vector3.new(2, 0, 8), hp = 680 },
            { type = "Farm", level = 7, gridPos = Vector3.new(8, 0, 7), hp = 640 },
            { type = "Farm", level = 6, gridPos = Vector3.new(9, 0, 5), hp = 600 },
            { type = "Farm", level = 5, gridPos = Vector3.new(9, 0, 3), hp = 560 },
            { type = "Barracks", level = 7, gridPos = Vector3.new(1, 0, 5), hp = 520 },
            { type = "SpellFactory", level = 3, gridPos = Vector3.new(1, 0, 7), hp = 545 },
            { type = "ArmyCamp", level = 3, gridPos = Vector3.new(1, 0, 9), hp = 290 },
            { type = "Wall", level = 8, gridPos = Vector3.new(3, 0, 2), hp = 3000 },
            { type = "Wall", level = 8, gridPos = Vector3.new(4, 0, 2), hp = 3000 },
            { type = "Wall", level = 8, gridPos = Vector3.new(5, 0, 1), hp = 3000 },
            { type = "Wall", level = 8, gridPos = Vector3.new(6, 0, 2), hp = 3000 },
            { type = "Wall", level = 8, gridPos = Vector3.new(7, 0, 2), hp = 3000 },
            { type = "Wall", level = 8, gridPos = Vector3.new(2, 0, 3), hp = 3000 },
            { type = "Wall", level = 8, gridPos = Vector3.new(8, 0, 3), hp = 3000 },
            { type = "Wall", level = 8, gridPos = Vector3.new(2, 0, 4), hp = 3000 },
            { type = "Wall", level = 8, gridPos = Vector3.new(8, 0, 4), hp = 3000 },
            { type = "Wall", level = 8, gridPos = Vector3.new(2, 0, 5), hp = 3000 },
            { type = "Wall", level = 8, gridPos = Vector3.new(8, 0, 5), hp = 3000 },
        },
    },
}

--[[
    Returns a camp definition by its unique ID.
    @param id string - The camp ID (e.g. "goblin_camp_1")
    @return table? - The camp data or nil if not found
]]
function GoblinCampData.GetCampById(id: string): any?
    for _, camp in GoblinCampData.Camps do
        if camp.id == id then
            return camp
        end
    end
    return nil
end

--[[
    Returns all camps matching the given difficulty.
    @param difficulty string - "Easy", "Medium", or "Hard"
    @return {table} - Array of camp definitions
]]
function GoblinCampData.GetCampsByDifficulty(difficulty: string): {any}
    local result = {}
    for _, camp in GoblinCampData.Camps do
        if camp.difficulty == difficulty then
            table.insert(result, camp)
        end
    end
    return result
end

--[[
    Returns all camp definitions.
    @return {table} - Array of all camp definitions
]]
function GoblinCampData.GetAllCamps(): {any}
    return GoblinCampData.Camps
end

return GoblinCampData
