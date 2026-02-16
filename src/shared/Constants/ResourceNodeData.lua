--!strict
--[[
    ResourceNodeData.lua

    Defines collectible resource node configurations for Battle Tycoon: Conquest.
    Resource nodes are scattered across the overworld map. Players walk up and
    interact to collect a small resource bonus. Nodes use PER-PLAYER cooldowns,
    so each player can independently collect each node without affecting others.

    IMPORTANT: Changes to this file affect game balance.
    Consult game-designer agent before modifications.

    Each node defines:
    - Unique id and resource type (Gold, Wood, Food)
    - Overworld position for visual marker placement
    - Random reward amount range (min/max)
    - Per-player respawn timer (seconds)

    Respawn times by type:
    - Gold Vein:    2 hours  (7200s)
    - Lumber Patch: 2.5 hours (9000s)
    - Berry Bush:   3 hours  (10800s)
]]

local ResourceNodeData = {}

-- Respawn times by resource type (in seconds)
local RESPAWN_GOLD = 7200   -- 2 hours
local RESPAWN_WOOD = 9000   -- 2.5 hours
local RESPAWN_FOOD = 10800  -- 3 hours

-- Visual config per type (used by client for marker appearance)
ResourceNodeData.TypeConfig = {
    Gold = {
        displayName = "Gold Vein",
        color = Color3.fromRGB(255, 200, 50),
        secondaryColor = Color3.fromRGB(180, 140, 30),
        material = Enum.Material.Metal,
        resourceKey = "gold",
    },
    Wood = {
        displayName = "Lumber Patch",
        color = Color3.fromRGB(140, 90, 40),
        secondaryColor = Color3.fromRGB(100, 65, 25),
        material = Enum.Material.WoodPlanks,
        resourceKey = "wood",
    },
    Food = {
        displayName = "Berry Bush",
        color = Color3.fromRGB(50, 160, 60),
        secondaryColor = Color3.fromRGB(180, 40, 60),
        material = Enum.Material.Grass,
        resourceKey = "food",
    },
}

ResourceNodeData.Nodes = {
    -- ═══════════════════════════════════════════════════════════════════════════
    -- GOLD VEINS (6 nodes) - 200-500 gold, 2hr respawn
    -- Yellow/golden rock appearance — spread across wilderness zones
    -- ═══════════════════════════════════════════════════════════════════════════
    {
        id = "gold_1",
        type = "Gold",
        position = Vector3.new(250, 0, 400),
        amount = { min = 200, max = 500 },
        respawnTime = RESPAWN_GOLD,
    },
    {
        id = "gold_2",
        type = "Gold",
        position = Vector3.new(700, 0, 250),
        amount = { min = 200, max = 500 },
        respawnTime = RESPAWN_GOLD,
    },
    {
        id = "gold_3",
        type = "Gold",
        position = Vector3.new(1400, 0, 300),
        amount = { min = 200, max = 500 },
        respawnTime = RESPAWN_GOLD,
    },
    {
        id = "gold_4",
        type = "Gold",
        position = Vector3.new(1700, 0, 900),
        amount = { min = 200, max = 500 },
        respawnTime = RESPAWN_GOLD,
    },
    {
        id = "gold_5",
        type = "Gold",
        position = Vector3.new(500, 0, 1700),
        amount = { min = 200, max = 500 },
        respawnTime = RESPAWN_GOLD,
    },
    {
        id = "gold_6",
        type = "Gold",
        position = Vector3.new(1100, 0, 1500),
        amount = { min = 200, max = 500 },
        respawnTime = RESPAWN_GOLD,
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- LUMBER PATCHES (6 nodes) - 150-400 wood, 2.5hr respawn
    -- Brown tree stump/log appearance
    -- ═══════════════════════════════════════════════════════════════════════════
    {
        id = "wood_1",
        type = "Wood",
        position = Vector3.new(350, 0, 1200),
        amount = { min = 150, max = 400 },
        respawnTime = RESPAWN_WOOD,
    },
    {
        id = "wood_2",
        type = "Wood",
        position = Vector3.new(900, 0, 500),
        amount = { min = 150, max = 400 },
        respawnTime = RESPAWN_WOOD,
    },
    {
        id = "wood_3",
        type = "Wood",
        position = Vector3.new(1600, 0, 500),
        amount = { min = 150, max = 400 },
        respawnTime = RESPAWN_WOOD,
    },
    {
        id = "wood_4",
        type = "Wood",
        position = Vector3.new(150, 0, 800),
        amount = { min = 150, max = 400 },
        respawnTime = RESPAWN_WOOD,
    },
    {
        id = "wood_5",
        type = "Wood",
        position = Vector3.new(800, 0, 1800),
        amount = { min = 150, max = 400 },
        respawnTime = RESPAWN_WOOD,
    },
    {
        id = "wood_6",
        type = "Wood",
        position = Vector3.new(1800, 0, 1400),
        amount = { min = 150, max = 400 },
        respawnTime = RESPAWN_WOOD,
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- BERRY BUSHES (6 nodes) - 100-300 food, 3hr respawn
    -- Green bush appearance
    -- ═══════════════════════════════════════════════════════════════════════════
    {
        id = "food_1",
        type = "Food",
        position = Vector3.new(1500, 0, 600),
        amount = { min = 100, max = 300 },
        respawnTime = RESPAWN_FOOD,
    },
    {
        id = "food_2",
        type = "Food",
        position = Vector3.new(400, 0, 700),
        amount = { min = 100, max = 300 },
        respawnTime = RESPAWN_FOOD,
    },
    {
        id = "food_3",
        type = "Food",
        position = Vector3.new(1000, 0, 400),
        amount = { min = 100, max = 300 },
        respawnTime = RESPAWN_FOOD,
    },
    {
        id = "food_4",
        type = "Food",
        position = Vector3.new(200, 0, 1600),
        amount = { min = 100, max = 300 },
        respawnTime = RESPAWN_FOOD,
    },
    {
        id = "food_5",
        type = "Food",
        position = Vector3.new(1700, 0, 1800),
        amount = { min = 100, max = 300 },
        respawnTime = RESPAWN_FOOD,
    },
    {
        id = "food_6",
        type = "Food",
        position = Vector3.new(1300, 0, 1100),
        amount = { min = 100, max = 300 },
        respawnTime = RESPAWN_FOOD,
    },
}

--[[
    Returns a node definition by its unique ID.
    @param id string - The node ID (e.g. "gold_1")
    @return table? - The node data or nil if not found
]]
function ResourceNodeData.GetNodeById(id: string): any?
    for _, node in ResourceNodeData.Nodes do
        if node.id == id then
            return node
        end
    end
    return nil
end

--[[
    Returns all node definitions.
    @return {table} - Array of all node definitions
]]
function ResourceNodeData.GetAllNodes(): {any}
    return ResourceNodeData.Nodes
end

--[[
    Returns all nodes matching the given resource type.
    @param nodeType string - "Gold", "Wood", or "Food"
    @return {table} - Array of matching node definitions
]]
function ResourceNodeData.GetNodesByType(nodeType: string): {any}
    local result = {}
    for _, node in ResourceNodeData.Nodes do
        if node.type == nodeType then
            table.insert(result, node)
        end
    end
    return result
end

return ResourceNodeData
