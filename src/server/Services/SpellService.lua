--!strict
--[[
    SpellService.lua

    Manages spell creation, upgrades, and inventory.
    Spells are used during battles for tactical advantages.

    SECURITY: All spell operations validated server-side.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declarations
local DataService
local EconomyService

local SpellService = {}
SpellService.__index = SpellService

-- Events
SpellService.SpellBrewed = Signal.new()
SpellService.SpellUsed = Signal.new()
SpellService.BrewingComplete = Signal.new()

-- Private state
local _initialized = false
local _brewingQueues: {[number]: {any}} = {}

-- Spell definitions
export type SpellDef = {
    id: string,
    name: string,
    description: string,
    housingSpace: number,
    brewTime: number, -- seconds
    radius: number, -- effect radius in studs
    duration: number, -- effect duration in seconds
    levels: {{
        effect: number, -- damage/heal/boost amount
        goldCost: number,
        elixirCost: number?,
        darkElixirCost: number?,
        labLevel: number, -- required Spell Factory level
    }},
}

local SpellDefinitions: {[string]: SpellDef} = {
    -- Offensive Spells
    Lightning = {
        id = "Lightning",
        name = "Lightning Spell",
        description = "Summon lightning to deal damage to buildings and troops",
        housingSpace = 2,
        brewTime = 360, -- 6 minutes
        radius = 8,
        duration = 0, -- instant
        levels = {
            { effect = 300, goldCost = 15000, labLevel = 1 },
            { effect = 400, goldCost = 25000, labLevel = 2 },
            { effect = 500, goldCost = 40000, labLevel = 3 },
            { effect = 600, goldCost = 60000, labLevel = 4 },
            { effect = 700, goldCost = 80000, labLevel = 5 },
        },
    },
    Heal = {
        id = "Heal",
        name = "Healing Spell",
        description = "Heal friendly troops within the radius over time",
        housingSpace = 2,
        brewTime = 360,
        radius = 10,
        duration = 12,
        levels = {
            { effect = 600, goldCost = 15000, labLevel = 1 },
            { effect = 800, goldCost = 25000, labLevel = 2 },
            { effect = 1000, goldCost = 40000, labLevel = 3 },
            { effect = 1200, goldCost = 60000, labLevel = 4 },
            { effect = 1600, goldCost = 80000, labLevel = 5 },
        },
    },
    Rage = {
        id = "Rage",
        name = "Rage Spell",
        description = "Boost troop speed and damage within the radius",
        housingSpace = 2,
        brewTime = 360,
        radius = 10,
        duration = 16,
        levels = {
            { effect = 30, goldCost = 20000, labLevel = 2 }, -- 30% boost
            { effect = 40, goldCost = 35000, labLevel = 3 },
            { effect = 50, goldCost = 50000, labLevel = 4 },
            { effect = 60, goldCost = 70000, labLevel = 5 },
            { effect = 70, goldCost = 90000, labLevel = 6 },
        },
    },
    Freeze = {
        id = "Freeze",
        name = "Freeze Spell",
        description = "Freeze enemy defenses and troops in place",
        housingSpace = 1,
        brewTime = 180, -- 3 minutes
        radius = 6,
        duration = 4,
        levels = {
            { effect = 4, goldCost = 25000, labLevel = 3 }, -- 4 second freeze
            { effect = 5, goldCost = 40000, labLevel = 4 },
            { effect = 6, goldCost = 55000, labLevel = 5 },
            { effect = 7, goldCost = 70000, labLevel = 6 },
        },
    },
    Jump = {
        id = "Jump",
        name = "Jump Spell",
        description = "Allow ground troops to jump over walls",
        housingSpace = 2,
        brewTime = 360,
        radius = 8,
        duration = 20,
        levels = {
            { effect = 20, goldCost = 23000, labLevel = 2 }, -- duration
            { effect = 40, goldCost = 38000, labLevel = 3 },
            { effect = 60, goldCost = 53000, labLevel = 4 },
        },
    },
    Clone = {
        id = "Clone",
        name = "Clone Spell",
        description = "Clone friendly troops that enter the radius",
        housingSpace = 3,
        brewTime = 540, -- 9 minutes
        radius = 6,
        duration = 18,
        levels = {
            { effect = 10, goldCost = 30000, labLevel = 4 }, -- max housing cloned
            { effect = 16, goldCost = 50000, labLevel = 5 },
            { effect = 22, goldCost = 75000, labLevel = 6 },
            { effect = 28, goldCost = 100000, labLevel = 7 },
        },
    },
    Invisibility = {
        id = "Invisibility",
        name = "Invisibility Spell",
        description = "Make troops invisible to defenses temporarily",
        housingSpace = 1,
        brewTime = 180,
        radius = 6,
        duration = 4,
        levels = {
            { effect = 4, goldCost = 25000, labLevel = 4 }, -- duration
            { effect = 5, goldCost = 40000, labLevel = 5 },
            { effect = 6, goldCost = 55000, labLevel = 6 },
        },
    },
}

-- Max spell capacity by Spell Factory level
local SpellCapacity = {
    [1] = 2,
    [2] = 4,
    [3] = 6,
    [4] = 8,
    [5] = 10,
    [6] = 11,
}

--[[
    Gets the definition for a spell type.
]]
function SpellService:GetSpellDefinition(spellType: string): SpellDef?
    return SpellDefinitions[spellType]
end

--[[
    Gets all available spell definitions.
]]
function SpellService:GetAllSpellDefinitions(): {[string]: SpellDef}
    return SpellDefinitions
end

--[[
    Gets the player's spell capacity based on Spell Factory level.
]]
function SpellService:GetSpellCapacity(player: Player): number
    local playerData = DataService:GetPlayerData(player)
    if not playerData or not playerData.buildings then
        return 0
    end

    -- Find Spell Factory and get its level
    local factoryLevel = 0
    for _, building in playerData.buildings do
        if building.type == "SpellFactory" then
            factoryLevel = math.max(factoryLevel, building.level or 1)
        end
    end

    return SpellCapacity[factoryLevel] or 0
end

--[[
    Gets the player's current spells.
]]
function SpellService:GetSpells(player: Player): {[string]: number}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return {}
    end

    return playerData.spells or {}
end

--[[
    Gets the current housing space used.
]]
function SpellService:GetUsedCapacity(player: Player): number
    local spells = self:GetSpells(player)
    local used = 0

    for spellType, count in spells do
        local def = SpellDefinitions[spellType]
        if def then
            used += def.housingSpace * count
        end
    end

    return used
end

--[[
    Starts brewing a spell.
]]
function SpellService:BrewSpell(player: Player, spellType: string): {success: boolean, error: string?}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_DATA" }
    end

    local def = SpellDefinitions[spellType]
    if not def then
        return { success = false, error = "INVALID_SPELL" }
    end

    -- Check if player has Spell Factory
    local factoryLevel = 0
    local factoryId = nil
    for _, building in playerData.buildings or {} do
        if building.type == "SpellFactory" and (building.level or 1) > factoryLevel then
            factoryLevel = building.level or 1
            factoryId = building.id
        end
    end

    if factoryLevel == 0 then
        return { success = false, error = "NO_SPELL_FACTORY" }
    end

    -- Check spell level requirement
    local spellLevel = (playerData.spellLevels or {})[spellType] or 1
    local levelData = def.levels[spellLevel]
    if not levelData then
        return { success = false, error = "SPELL_NOT_UNLOCKED" }
    end

    if factoryLevel < levelData.labLevel then
        return { success = false, error = "FACTORY_LEVEL_TOO_LOW" }
    end

    -- Check capacity
    local capacity = SpellCapacity[factoryLevel] or 0
    local usedCapacity = self:GetUsedCapacity(player)
    local queueCapacity = self:GetQueueCapacity(player)

    if usedCapacity + queueCapacity + def.housingSpace > capacity then
        return { success = false, error = "NO_CAPACITY" }
    end

    -- Check and deduct resources
    if levelData.goldCost then
        if (playerData.resources.gold or 0) < levelData.goldCost then
            return { success = false, error = "INSUFFICIENT_GOLD" }
        end
        DataService:UpdateResources(player, { gold = -levelData.goldCost } :: any)
    end

    -- Add to brewing queue
    _brewingQueues[player.UserId] = _brewingQueues[player.UserId] or {}
    local queue = _brewingQueues[player.UserId]

    local brewItem = {
        spellType = spellType,
        startTime = os.time(),
        brewTime = def.brewTime,
        level = spellLevel,
    }
    table.insert(queue, brewItem)

    SpellService.SpellBrewed:Fire(player, spellType, #queue)

    return { success = true }
end

--[[
    Gets the current brewing queue capacity (housing space).
]]
function SpellService:GetQueueCapacity(player: Player): number
    local queue = _brewingQueues[player.UserId]
    if not queue then return 0 end

    local capacity = 0
    for _, item in queue do
        local def = SpellDefinitions[item.spellType]
        if def then
            capacity += def.housingSpace
        end
    end

    return capacity
end

--[[
    Gets the brewing queue for a player.
]]
function SpellService:GetBrewingQueue(player: Player): {any}
    return _brewingQueues[player.UserId] or {}
end

--[[
    Cancels a spell from the brewing queue.
]]
function SpellService:CancelBrewing(player: Player, queueIndex: number): {success: boolean, error: string?}
    local queue = _brewingQueues[player.UserId]
    if not queue or not queue[queueIndex] then
        return { success = false, error = "INVALID_INDEX" }
    end

    local item = queue[queueIndex]
    local def = SpellDefinitions[item.spellType]

    -- Refund 50% of resources
    if def then
        local levelData = def.levels[item.level]
        if levelData and levelData.goldCost then
            local refund = math.floor(levelData.goldCost * 0.5)
            DataService:UpdateResources(player, { gold = refund } :: any)
        end
    end

    table.remove(queue, queueIndex)

    return { success = true }
end

--[[
    Uses a spell (decrements count in inventory).
]]
function SpellService:UseSpell(player: Player, spellType: string): {success: boolean, error: string?}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_DATA" }
    end

    local spells = playerData.spells or {}
    if (spells[spellType] or 0) <= 0 then
        return { success = false, error = "NO_SPELL" }
    end

    spells[spellType] = spells[spellType] - 1
    if spells[spellType] <= 0 then
        spells[spellType] = nil
    end
    playerData.spells = spells

    SpellService.SpellUsed:Fire(player, spellType)

    return { success = true }
end

--[[
    Gets the stats for a spell at a given level.
]]
function SpellService:GetSpellStats(spellType: string, level: number): {
    damage: number?,
    heal: number?,
    boost: number?,
    radius: number,
    duration: number,
}?
    local def = SpellDefinitions[spellType]
    if not def then return nil end

    local levelData = def.levels[level]
    if not levelData then return nil end

    return {
        effect = levelData.effect,
        radius = def.radius,
        duration = def.duration,
    }
end

--[[
    Processes brewing queue (called periodically).
]]
function SpellService:ProcessBrewingQueues()
    local now = os.time()
    local Players = game:GetService("Players")

    for userId, queue in _brewingQueues do
        local player = Players:GetPlayerByUserId(userId)
        if not player then
            -- Clean up disconnected players
            _brewingQueues[userId] = nil
            continue
        end

        -- Process first item in queue
        while #queue > 0 do
            local item = queue[1]
            local elapsed = now - item.startTime

            if elapsed >= item.brewTime then
                -- Brewing complete
                local playerData = DataService:GetPlayerData(player)
                if playerData then
                    playerData.spells = playerData.spells or {}
                    playerData.spells[item.spellType] = (playerData.spells[item.spellType] or 0) + 1

                    SpellService.BrewingComplete:Fire(player, item.spellType)
                end

                table.remove(queue, 1)

                -- Update start time for next item
                if queue[1] then
                    queue[1].startTime = now
                end
            else
                break -- Still brewing
            end
        end
    end
end

--[[
    Initializes the SpellService.
]]
function SpellService:Init()
    if _initialized then
        warn("SpellService already initialized")
        return
    end

    -- Get service references
    local ServerScriptService = game:GetService("ServerScriptService")
    DataService = require(ServerScriptService.Services.DataService)
    EconomyService = require(ServerScriptService.Services.EconomyService)

    -- Start brewing processor
    task.spawn(function()
        while true do
            self:ProcessBrewingQueues()
            task.wait(1) -- Process every second
        end
    end)

    _initialized = true
    print("SpellService initialized")
end

return SpellService
