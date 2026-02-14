--!strict
--[[
    WorldMapData.lua

    Configuration for the World Map system including:
    - Map dimensions and boundaries
    - Travel time calculations
    - Base relocation rules
    - Distance thresholds

    Reference: docs/GAME_DESIGN_DOCUMENT.md
]]

local WorldMapData = {}

--[[
    MAP DIMENSIONS
    The world map is a grid where players can position their bases.
]]
WorldMapData.Map = {
    -- Map size in world units
    Width = 1000,
    Height = 1000,

    -- Grid cell size for positioning
    CellSize = 10,

    -- Minimum distance between bases
    MinBaseDistance = 20,

    -- View distance for rendering other bases
    ViewDistance = 200,

    -- Maximum bases to show at once (performance)
    MaxVisibleBases = 50,
}

--[[
    TRAVEL TIME CONFIGURATION
    Distance-based travel times for attacking other bases.
]]
WorldMapData.Travel = {
    -- Distance thresholds (in map units)
    Thresholds = {
        -- Nearby: Instant attack
        Nearby = {
            maxDistance = 100,
            travelTime = 0, -- seconds
            description = "Instant",
        },
        -- Medium: Short march
        Medium = {
            maxDistance = 300,
            travelTime = 30, -- seconds
            description = "Short March",
        },
        -- Far: Longer march
        Far = {
            maxDistance = math.huge,
            travelTime = 120, -- 2 minutes max
            description = "Long March",
        },
    },

    -- Time per unit distance for far travel (seconds per unit)
    TimePerUnit = 0.5,

    -- Can cancel during travel
    AllowCancel = true,

    -- Gold cost per 100 units of distance (for instant travel boost)
    InstantTravelCostPer100Units = 50,
}

--[[
    BASE RELOCATION CONFIGURATION
]]
WorldMapData.Relocation = {
    -- Cooldown between free relocations (in seconds)
    FreeCooldown = 86400, -- 24 hours

    -- Gold cost to bypass cooldown (multiplied by TH level)
    CostPerTHLevel = 100,

    -- Minimum distance to move
    MinMoveDistance = 50,

    -- Animation duration for relocation
    AnimationDuration = 2.0,
}

--[[
    DIFFICULTY COLOR CODING
    Based on TH level and trophy difference.
]]
WorldMapData.Difficulty = {
    -- Easy: Lower TH, significantly fewer trophies
    Easy = {
        color = Color3.fromRGB(100, 200, 100), -- Green
        maxTHDifference = -2, -- 2+ TH levels below
        maxTrophyDifference = -200,
    },
    -- Medium: Similar level
    Medium = {
        color = Color3.fromRGB(230, 180, 50), -- Yellow
        maxTHDifference = 0,
        maxTrophyDifference = 100,
    },
    -- Hard: Higher TH, more trophies
    Hard = {
        color = Color3.fromRGB(200, 80, 80), -- Red
        maxTHDifference = 2,
        maxTrophyDifference = math.huge,
    },
}

--[[
    FRIEND SYSTEM
]]
WorldMapData.Friends = {
    -- Maximum friends per player
    MaxFriends = 100,

    -- Friend base highlight color
    HighlightColor = Color3.fromRGB(80, 150, 255), -- Blue

    -- Friend visibility bonus (see friends further away)
    ViewDistanceBonus = 100,
}

--[[
    MEMORY STORE CONFIGURATION
    For cross-server world map state.
]]
WorldMapData.MemoryStore = {
    -- Map name for MemoryStoreService
    MapName = "WorldMap_v1",

    -- How long player positions stay valid (seconds)
    PositionExpiry = 300, -- 5 minutes

    -- Update frequency for position syncing
    SyncInterval = 30, -- seconds
}

--[[
    Calculates travel time based on distance.

    @param distance number - Distance in map units
    @return number - Travel time in seconds
    @return string - Travel category description
]]
function WorldMapData.CalculateTravelTime(distance: number): (number, string)
    local thresholds = WorldMapData.Travel.Thresholds

    -- Check nearby
    if distance <= thresholds.Nearby.maxDistance then
        return thresholds.Nearby.travelTime, thresholds.Nearby.description
    end

    -- Check medium
    if distance <= thresholds.Medium.maxDistance then
        return thresholds.Medium.travelTime, thresholds.Medium.description
    end

    -- Far distance: calculate based on time per unit
    local baseTime = thresholds.Medium.travelTime
    local extraDistance = distance - thresholds.Medium.maxDistance
    local extraTime = extraDistance * WorldMapData.Travel.TimePerUnit

    -- Cap at far threshold max time
    local totalTime = math.min(
        baseTime + extraTime,
        thresholds.Far.travelTime
    )

    return totalTime, thresholds.Far.description
end

--[[
    Calculates relocation cost based on TH level.

    @param thLevel number - Town Hall level
    @param withinCooldown boolean - Whether cooldown is still active
    @return number - Gold cost (0 if free move available)
]]
function WorldMapData.CalculateRelocationCost(thLevel: number, withinCooldown: boolean): number
    if not withinCooldown then
        return 0 -- Free move
    end

    return WorldMapData.Relocation.CostPerTHLevel * thLevel
end

--[[
    Calculates instant travel cost to bypass march time.

    @param distance number - Distance in map units
    @return number - Gold cost
]]
function WorldMapData.CalculateInstantTravelCost(distance: number): number
    local units = distance / 100
    return math.ceil(units * WorldMapData.Travel.InstantTravelCostPer100Units)
end

--[[
    Determines difficulty color for an opponent.

    @param attackerTH number - Attacker's Town Hall level
    @param attackerTrophies number - Attacker's trophy count
    @param defenderTH number - Defender's Town Hall level
    @param defenderTrophies number - Defender's trophy count
    @return Color3 - Difficulty color
    @return string - Difficulty level ("Easy", "Medium", "Hard")
]]
function WorldMapData.GetDifficultyColor(
    attackerTH: number,
    attackerTrophies: number,
    defenderTH: number,
    defenderTrophies: number
): (Color3, string)
    local thDiff = defenderTH - attackerTH
    local trophyDiff = defenderTrophies - attackerTrophies

    local difficulty = WorldMapData.Difficulty

    -- Check Easy first
    if thDiff <= difficulty.Easy.maxTHDifference or trophyDiff <= difficulty.Easy.maxTrophyDifference then
        return difficulty.Easy.color, "Easy"
    end

    -- Check Medium
    if thDiff <= difficulty.Medium.maxTHDifference and trophyDiff <= difficulty.Medium.maxTrophyDifference then
        return difficulty.Medium.color, "Medium"
    end

    -- Hard
    return difficulty.Hard.color, "Hard"
end

--[[
    Generates a random starting position for a new player.

    @return {x: number, z: number} - Map position
]]
function WorldMapData.GenerateStartingPosition(): {x: number, z: number}
    local map = WorldMapData.Map
    local margin = 50 -- Keep away from edges

    return {
        x = math.random(margin, map.Width - margin),
        z = math.random(margin, map.Height - margin),
    }
end

--[[
    Calculates distance between two map positions.

    @param pos1 {x: number, z: number} - First position
    @param pos2 {x: number, z: number} - Second position
    @return number - Distance in map units
]]
function WorldMapData.CalculateDistance(
    pos1: {x: number, z: number},
    pos2: {x: number, z: number}
): number
    local dx = pos2.x - pos1.x
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dz * dz)
end

--[[
    Validates a map position is within bounds.

    @param position {x: number, z: number} - Position to validate
    @return boolean - True if valid
]]
function WorldMapData.IsValidPosition(position: {x: number, z: number}): boolean
    local map = WorldMapData.Map

    if position.x < 0 or position.x > map.Width then
        return false
    end

    if position.z < 0 or position.z > map.Height then
        return false
    end

    return true
end

return WorldMapData
