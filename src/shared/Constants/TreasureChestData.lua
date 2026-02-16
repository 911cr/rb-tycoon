--!strict
--[[
    TreasureChestData.lua

    Defines treasure chest positions and loot ranges for the overworld.
    Chests are scattered across wilderness and forbidden zones.
    Uses per-player cooldowns (similar to ResourceNodeService pattern).

    IMPORTANT: Changes to this file affect game balance.
    Consult game-designer agent before modifications.
]]

local TreasureChestData = {}

-- Per-player cooldown range (seconds)
TreasureChestData.CooldownRange = {
    min = 3600,   -- 1 hour
    max = 10800,  -- 3 hours
}

-- Collection range (studs)
TreasureChestData.CollectRange = 10

-- ============================================================================
-- CHEST TYPES
-- ============================================================================

TreasureChestData.Types = {
    Wilderness = {
        displayName = "Wilderness Chest",
        color = Color3.fromRGB(139, 90, 43),
        accentColor = Color3.fromRGB(200, 170, 50),
    },
    Forbidden = {
        displayName = "Forbidden Chest",
        color = Color3.fromRGB(80, 30, 60),
        accentColor = Color3.fromRGB(220, 50, 220),
    },
}

-- ============================================================================
-- CHEST POSITIONS
-- ============================================================================

-- Wilderness chests (~15 total)
TreasureChestData.Chests = {
    -- Wilderness chests (no gems)
    {
        id = "chest_w1",
        zone = "Wilderness",
        x = 350, z = 350,
        loot = { gold = { 150, 400 }, wood = { 100, 300 }, food = { 80, 250 }, gems = { 0, 0 } },
    },
    {
        id = "chest_w2",
        zone = "Wilderness",
        x = 1650, z = 350,
        loot = { gold = { 150, 400 }, wood = { 100, 300 }, food = { 80, 250 }, gems = { 0, 0 } },
    },
    {
        id = "chest_w3",
        zone = "Wilderness",
        x = 350, z = 1650,
        loot = { gold = { 150, 400 }, wood = { 100, 300 }, food = { 80, 250 }, gems = { 0, 0 } },
    },
    {
        id = "chest_w4",
        zone = "Wilderness",
        x = 200, z = 800,
        loot = { gold = { 200, 500 }, wood = { 150, 400 }, food = { 100, 300 }, gems = { 0, 0 } },
    },
    {
        id = "chest_w5",
        zone = "Wilderness",
        x = 800, z = 200,
        loot = { gold = { 200, 500 }, wood = { 150, 400 }, food = { 100, 300 }, gems = { 0, 0 } },
    },
    {
        id = "chest_w6",
        zone = "Wilderness",
        x = 1800, z = 800,
        loot = { gold = { 200, 500 }, wood = { 150, 400 }, food = { 100, 300 }, gems = { 0, 1 } },
    },
    {
        id = "chest_w7",
        zone = "Wilderness",
        x = 800, z = 1800,
        loot = { gold = { 200, 500 }, wood = { 150, 400 }, food = { 100, 300 }, gems = { 0, 1 } },
    },
    {
        id = "chest_w8",
        zone = "Wilderness",
        x = 100, z = 1300,
        loot = { gold = { 250, 600 }, wood = { 200, 500 }, food = { 150, 400 }, gems = { 0, 1 } },
    },
    {
        id = "chest_w9",
        zone = "Wilderness",
        x = 1300, z = 100,
        loot = { gold = { 250, 600 }, wood = { 200, 500 }, food = { 150, 400 }, gems = { 0, 1 } },
    },
    {
        id = "chest_w10",
        zone = "Wilderness",
        x = 1900, z = 1300,
        loot = { gold = { 300, 700 }, wood = { 250, 600 }, food = { 200, 500 }, gems = { 0, 1 } },
    },
    {
        id = "chest_w11",
        zone = "Wilderness",
        x = 100, z = 500,
        loot = { gold = { 200, 500 }, wood = { 150, 400 }, food = { 100, 300 }, gems = { 0, 0 } },
    },
    {
        id = "chest_w12",
        zone = "Wilderness",
        x = 500, z = 1900,
        loot = { gold = { 250, 600 }, wood = { 200, 500 }, food = { 150, 400 }, gems = { 0, 1 } },
    },
    {
        id = "chest_w13",
        zone = "Wilderness",
        x = 1400, z = 1900,
        loot = { gold = { 300, 700 }, wood = { 250, 600 }, food = { 200, 500 }, gems = { 0, 1 } },
    },
    {
        id = "chest_w14",
        zone = "Wilderness",
        x = 1900, z = 400,
        loot = { gold = { 250, 600 }, wood = { 200, 500 }, food = { 150, 400 }, gems = { 0, 0 } },
    },
    {
        id = "chest_w15",
        zone = "Wilderness",
        x = 400, z = 100,
        loot = { gold = { 200, 500 }, wood = { 150, 400 }, food = { 100, 300 }, gems = { 0, 0 } },
    },

    -- Forbidden zone chests (~5 total, gems guaranteed)
    {
        id = "chest_f1",
        zone = "Forbidden",
        x = 1600, z = 1600,
        loot = { gold = { 500, 1000 }, wood = { 400, 800 }, food = { 300, 700 }, gems = { 2, 5 } },
    },
    {
        id = "chest_f2",
        zone = "Forbidden",
        x = 1800, z = 1600,
        loot = { gold = { 500, 1000 }, wood = { 400, 800 }, food = { 300, 700 }, gems = { 2, 5 } },
    },
    {
        id = "chest_f3",
        zone = "Forbidden",
        x = 1700, z = 1800,
        loot = { gold = { 600, 1200 }, wood = { 500, 1000 }, food = { 400, 800 }, gems = { 3, 8 } },
    },
    {
        id = "chest_f4",
        zone = "Forbidden",
        x = 1550, z = 1850,
        loot = { gold = { 500, 1000 }, wood = { 400, 800 }, food = { 300, 700 }, gems = { 2, 5 } },
    },
    {
        id = "chest_f5",
        zone = "Forbidden",
        x = 1850, z = 1750,
        loot = { gold = { 600, 1200 }, wood = { 500, 1000 }, food = { 400, 800 }, gems = { 3, 8 } },
    },
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

function TreasureChestData.GetChestById(id: string): any?
    for _, chest in TreasureChestData.Chests do
        if chest.id == id then
            return chest
        end
    end
    return nil
end

function TreasureChestData.GetAllChests(): {any}
    return TreasureChestData.Chests
end

--[[
    Rolls random loot for a chest.
    @param chestId string
    @return {gold: number, wood: number, food: number, gems: number}?
]]
function TreasureChestData.RollLoot(chestId: string): {gold: number, wood: number, food: number, gems: number}?
    local chest = TreasureChestData.GetChestById(chestId)
    if not chest then return nil end

    local loot = chest.loot
    return {
        gold = math.random(loot.gold[1], loot.gold[2]),
        wood = math.random(loot.wood[1], loot.wood[2]),
        food = math.random(loot.food[1], loot.food[2]),
        gems = if loot.gems[2] > 0 then math.random(loot.gems[1], loot.gems[2]) else 0,
    }
end

--[[
    Generates a random per-player cooldown within the configured range.
    @return number - Cooldown in seconds
]]
function TreasureChestData.RollCooldown(): number
    return math.random(TreasureChestData.CooldownRange.min, TreasureChestData.CooldownRange.max)
end

return TreasureChestData
