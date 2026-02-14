--!strict
--[[
    OverworldConfig.lua

    Configuration constants for the 3D walkable overworld.
    Defines map dimensions, base layout, interaction zones, and visual settings.
]]

local OverworldConfig = {}

-- ============================================================================
-- MAP DIMENSIONS
-- ============================================================================

OverworldConfig.Map = {
    -- Total map size in studs
    Width = 1000,
    Height = 1000,

    -- Center position of the map
    CenterX = 500,
    CenterZ = 500,

    -- Terrain height levels
    BaseHeight = 0,
    WaterLevel = -5,
    HillHeight = 15,
}

-- ============================================================================
-- BASE PLACEMENT
-- ============================================================================

OverworldConfig.Base = {
    -- Size of each mini-base footprint
    Size = 20, -- studs

    -- Minimum distance between bases
    MinSpacing = 50, -- studs

    -- Height of mini-bases
    BaseHeight = 0.5,

    -- Keep height for central tower (multiplied by TH level)
    KeepBaseHeight = 8,
    KeepHeightPerLevel = 2,

    -- Wall ring around base
    WallRadius = 10,
    WallHeight = 3,
    WallThickness = 1,
}

-- ============================================================================
-- INTERACTION DISTANCES
-- ============================================================================

OverworldConfig.Interaction = {
    -- Distance to show base info UI
    InfoDistance = 30, -- studs

    -- Distance to trigger gate prompt
    GateDistance = 8, -- studs

    -- Distance for base to be considered "in view"
    ViewDistance = 200, -- studs

    -- Maximum bases to render at once (performance)
    MaxVisibleBases = 50,

    -- Update interval for nearby base checks
    UpdateInterval = 0.5, -- seconds
}

-- ============================================================================
-- PLAYER CHARACTER
-- ============================================================================

OverworldConfig.Character = {
    -- Walk speed in overworld
    WalkSpeed = 24, -- studs/second

    -- Jump power
    JumpPower = 50,

    -- Spawn offset from map center
    SpawnOffset = Vector3.new(0, 5, 0),
}

-- ============================================================================
-- TERRAIN ZONES
-- ============================================================================

OverworldConfig.Zones = {
    -- Road network
    Roads = {
        MainRoadWidth = 12,
        SideRoadWidth = 8,
        Material = Enum.Material.Cobblestone,
        Color = Color3.fromRGB(140, 130, 120),
    },

    -- Forest areas
    Forest = {
        TreeDensity = 0.3, -- trees per 10x10 stud area
        TreeVariation = 3, -- number of tree types
    },

    -- Meadow/grass areas
    Meadow = {
        GrassColor = Color3.fromRGB(80, 140, 50),
        Material = Enum.Material.Grass,
    },

    -- River
    River = {
        Width = 20,
        WaterColor = Color3.fromRGB(80, 120, 180),
        Transparency = 0.4,
    },
}

-- ============================================================================
-- VISUAL SETTINGS
-- ============================================================================

OverworldConfig.Visuals = {
    -- Base difficulty colors
    DifficultyColors = {
        Easy = Color3.fromRGB(100, 200, 100),    -- Green
        Medium = Color3.fromRGB(230, 180, 50),   -- Yellow
        Hard = Color3.fromRGB(200, 80, 80),      -- Red
    },

    -- Friend highlight
    FriendColor = Color3.fromRGB(80, 150, 255),  -- Blue

    -- Own base color
    OwnBaseColor = Color3.fromRGB(150, 120, 200), -- Purple

    -- Banner colors based on alliance
    DefaultBannerColor = Color3.fromRGB(140, 30, 30), -- Red

    -- Shield visual
    ShieldColor = Color3.fromRGB(100, 180, 255),
    ShieldTransparency = 0.5,
}

-- ============================================================================
-- TELEPORT CONFIGURATION
-- ============================================================================

OverworldConfig.Teleport = {
    -- Place IDs
    VillagePlaceId = 119185440618543,
    OverworldPlaceId = 91563355452416,
    BattlePlaceId = 0, -- Set this when battle place is created

    -- Teleport retry settings
    MaxRetries = 3,
    RetryDelay = 2, -- seconds

    -- Data keys for teleport
    DataKeys = {
        Source = "sourcePlace",
        PlayerId = "playerId",
        ReturnPosition = "returnPosition",
        Timestamp = "timestamp",
        TargetBase = "targetBaseId",
    },
}

-- ============================================================================
-- CAMERA SETTINGS
-- ============================================================================

OverworldConfig.Camera = {
    -- Default camera offset from character
    DefaultOffset = Vector3.new(0, 30, 40),

    -- Camera angle
    DefaultAngle = -35, -- degrees (looking down)

    -- Zoom limits
    MinZoom = 15,
    MaxZoom = 80,

    -- Camera smoothing
    SmoothSpeed = 8,
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Converts a map position (0-1000) to world position.
    Map center is at (500, 500), world Y is based on terrain height.

    @param mapX number - X position on map (0-1000)
    @param mapZ number - Z position on map (0-1000)
    @return Vector3 - World position
]]
function OverworldConfig.MapToWorld(mapX: number, mapZ: number): Vector3
    return Vector3.new(
        mapX,
        OverworldConfig.Map.BaseHeight,
        mapZ
    )
end

--[[
    Converts world position to map position.

    @param worldPos Vector3 - World position
    @return number, number - Map X and Z coordinates
]]
function OverworldConfig.WorldToMap(worldPos: Vector3): (number, number)
    return worldPos.X, worldPos.Z
end

--[[
    Checks if a position is within map bounds.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return boolean - True if within bounds
]]
function OverworldConfig.IsInBounds(x: number, z: number): boolean
    return x >= 0 and x <= OverworldConfig.Map.Width
       and z >= 0 and z <= OverworldConfig.Map.Height
end

--[[
    Gets the difficulty color for an opponent based on TH difference.

    @param thDiff number - Defender TH level minus attacker TH level
    @return Color3 - Difficulty color
]]
function OverworldConfig.GetDifficultyColor(thDiff: number): Color3
    local colors = OverworldConfig.Visuals.DifficultyColors

    if thDiff <= -2 then
        return colors.Easy
    elseif thDiff <= 0 then
        return colors.Medium
    else
        return colors.Hard
    end
end

--[[
    Calculates keep height based on Town Hall level.

    @param thLevel number - Town Hall level (1-10)
    @return number - Keep height in studs
]]
function OverworldConfig.GetKeepHeight(thLevel: number): number
    local base = OverworldConfig.Base
    return base.KeepBaseHeight + (thLevel - 1) * base.KeepHeightPerLevel
end

return OverworldConfig
