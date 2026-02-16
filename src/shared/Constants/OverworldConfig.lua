--!strict
--[[
    OverworldConfig.lua

    Configuration constants for the 3D walkable overworld.
    Defines map dimensions, zone boundaries, terrain generation parameters,
    base layout, interaction zones, wilderness gameplay, and visual settings.
]]

local OverworldConfig = {}

-- ============================================================================
-- MAP DIMENSIONS (2000x2000 voxel terrain)
-- ============================================================================

OverworldConfig.Map = {
    -- Total map size in studs
    Width = 2000,
    Height = 2000,

    -- Center position of the map
    CenterX = 1000,
    CenterZ = 1000,

    -- Terrain height levels
    BaseHeight = 0,
    WaterLevel = -3,
    HillHeight = 30,
}

-- ============================================================================
-- ZONE DEFINITIONS
-- ============================================================================

OverworldConfig.SafeZone = {
    MinX = 600,
    MaxX = 1400,
    MinZ = 600,
    MaxZ = 1400,
    -- Flatten terrain within this many studs of zone center
    FlattenRadius = 400,
    FlattenStrength = 0.85, -- 85% height reduction
}

OverworldConfig.ForbiddenZone = {
    MinX = 1500,
    MaxX = 1900,
    MinZ = 1500,
    MaxZ = 1900,
    -- Extra elevation for mountains
    HeightBoost = 25,
    -- Elite enemy stat multiplier
    StatMultiplier = 2.5,
}

-- ============================================================================
-- TERRAIN GENERATION
-- ============================================================================

OverworldConfig.Terrain = {
    -- Voxel resolution (studs per voxel cell)
    VoxelSize = 4,

    -- Perlin noise octaves for heightmap
    Octaves = {
        { scale = 0.002, amplitude = 30 },  -- Large landforms
        { scale = 0.008, amplitude = 12 },  -- Medium hills
        { scale = 0.025, amplitude = 4 },   -- Small bumps
    },

    -- Random seed offset (change to get different terrain)
    SeedOffset = 42,

    -- Materials per biome
    Materials = {
        Safe = Enum.Material.LeafyGrass,
        Wilderness = Enum.Material.Grass,
        WildernessRock = Enum.Material.Rock,
        WildernessMud = Enum.Material.Mud,
        Forbidden = Enum.Material.Snow,
        ForbiddenRock = Enum.Material.Rock,
        Road = Enum.Material.Cobblestone,
        RiverBed = Enum.Material.Sand,
        Water = Enum.Material.Water,
    },

    -- Tree placement
    Trees = {
        SafeDensity = 0.08,        -- sparse in safe zone
        WildernessDensity = 0.25,  -- dense in wilderness forests
        ForbiddenDensity = 0.12,   -- dead trees in forbidden
        EmbedDepth = 0.5,          -- studs into ground
    },

    -- Rock placement
    Rocks = {
        SafeCount = 30,
        WildernessCount = 80,
        ForbiddenCount = 50,
        EmbedPercent = 0.3, -- 30% buried
    },

    -- Road dimensions
    Roads = {
        MainWidth = 14,
        SecondaryWidth = 10,
        Material = Enum.Material.Cobblestone,
    },

    -- River dimensions
    River = {
        Width = 30,
        Depth = 6,
        WaterLevel = -2,
    },

    -- Base terrain flattening
    BaseFlattenSize = 30, -- studs, square area to flatten for each base
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
-- GRID-BASED BASE PLACEMENT
-- ============================================================================

OverworldConfig.Grid = {
    -- Max players per server = 50, so we need ~50 pre-defined city plots
    -- 7x7 grid = 49 plots (covers 50-player server; 50th falls back if needed)
    Rows = 7,
    Cols = 7,

    -- Spacing between plot centers in studs
    -- Safe zone usable area: 650-1350 = 700 studs per axis
    -- 7 plots across 700 studs: spacing = 700/6 ≈ 117 studs
    CellSize = 117,

    -- World-space origin of grid cell (0,0) — bottom-left of city area
    -- 1000 (center) - 3 * 117 = 649
    OriginX = 649,
    OriginZ = 649,

    -- Center cell (0-indexed): row 3, col 3 maps to world ~(1000, 1000)
    CenterRow = 3,
    CenterCol = 3,

    -- Maximum bases that can be placed (matches server player cap)
    MaxPlots = 50,
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

    -- Banking distance (auto-bank loot at own base gate)
    BankingDistance = 12, -- studs

    -- Co-op join radius
    CoopRadius = 30, -- studs

    -- Co-op join prompt duration
    CoopPromptDuration = 5, -- seconds
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
-- WILDERNESS GAMEPLAY
-- ============================================================================

OverworldConfig.Wilderness = {
    -- PvP settings
    PvP = {
        AttackRange = 50,        -- studs to initiate attack
        Cooldown = 120,          -- seconds between attacking same player
        LootStealPercent = 1.0,  -- steal 100% of carried loot on win
    },

    -- Loot carrying
    LootCarry = {
        -- Cart size thresholds (total loot value)
        SmallCartThreshold = 500,
        MediumCartThreshold = 2000,
        LargeCartThreshold = 5000,
        -- Dropped loot lifetime
        DropLifetime = 300, -- 5 minutes
        -- Drop collection range
        DropCollectRange = 10, -- studs
    },

    -- Auto-clash combat
    Combat = {
        MaxDuration = 60,     -- seconds
        TickInterval = 0.5,   -- seconds per tick
        MinDuration = 10,     -- minimum combat ticks before early end
    },

    -- Bandit settings
    Bandits = {
        WildernessCount = 25,    -- ~20-25 bandits in wilderness
        ForbiddenCount = 8,      -- ~5-8 in forbidden zone
        PatrolRadius = 40,       -- studs from spawn point
        PatrolInterval = 4,      -- seconds between waypoint changes
        AggroRadius = 20,        -- studs to engage
        RespawnTime = 300,       -- 5 minutes after defeated
    },

    -- Boss settings
    Bosses = {
        RespawnTime = 7200,      -- 2 hours minimum
        MaxRespawnTime = 14400,  -- 4 hours maximum
        HPBarDistance = 60,      -- studs to see HP bar
    },

    -- Treasure chest settings
    TreasureChests = {
        WildernessCount = 15,
        ForbiddenCount = 5,
        CollectRange = 10,       -- studs
        MinRespawnTime = 3600,   -- 1 hour per-player cooldown
        MaxRespawnTime = 10800,  -- 3 hours per-player cooldown
    },

    -- Merchant settings
    Merchants = {
        ActiveCount = 2,         -- merchants active at a time
        WaypointCount = 5,       -- waypoints per route
        InventoryRotation = 1800, -- 30 minutes
        BuyRate = 1.2,           -- buy at 1.2x base price
        SellRate = 0.6,          -- sell at 0.6x base price
        InteractRange = 8,       -- studs
    },

    -- Random event settings
    Events = {
        MinInterval = 1800,      -- 30 minutes between events
        MaxInterval = 3600,      -- 60 minutes between events
        MinDuration = 600,       -- 10 minutes
        MaxDuration = 1800,      -- 30 minutes
    },
}

-- ============================================================================
-- TERRAIN ZONES (legacy - kept for backward compatibility)
-- ============================================================================

OverworldConfig.Zones = {
    -- Road network
    Roads = {
        MainRoadWidth = 14,
        SideRoadWidth = 10,
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
        Width = 30,
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

    -- Zone atmosphere
    ZoneColors = {
        Safe = Color3.fromRGB(80, 140, 50),        -- Warm green
        Wilderness = Color3.fromRGB(60, 100, 40),   -- Darker green
        Forbidden = Color3.fromRGB(180, 180, 200),  -- Cold grey-blue
    },
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
        OwnerUserId = "ownerUserId",
        IsOwner = "isOwner",
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
    Converts a map position (0-2000) to world position.
    Queries terrain surface height via raycast when workspace.Terrain exists.

    @param mapX number - X position on map (0-2000)
    @param mapZ number - Z position on map (0-2000)
    @return Vector3 - World position
]]
function OverworldConfig.MapToWorld(mapX: number, mapZ: number): Vector3
    -- Try to raycast terrain for accurate Y position
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        local origin = Vector3.new(mapX, 200, mapZ)
        local direction = Vector3.new(0, -400, 0)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = {terrain}

        local hit = workspace:Raycast(origin, direction, params)
        if hit then
            return Vector3.new(mapX, hit.Position.Y, mapZ)
        end
    end

    return Vector3.new(
        mapX,
        OverworldConfig.Map.BaseHeight,
        mapZ
    )
end

--[[
    Gets terrain surface height at a position via raycast.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return number - Y height at surface, or BaseHeight if no terrain
]]
function OverworldConfig.GetTerrainHeight(x: number, z: number): number
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        local origin = Vector3.new(x, 200, z)
        local direction = Vector3.new(0, -400, 0)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = {terrain}

        local hit = workspace:Raycast(origin, direction, params)
        if hit then
            return hit.Position.Y
        end
    end
    return OverworldConfig.Map.BaseHeight
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
    Determines which zone a position falls in.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return string - "safe", "wilderness", or "forbidden"
]]
function OverworldConfig.GetZone(x: number, z: number): string
    local fz = OverworldConfig.ForbiddenZone
    if x >= fz.MinX and x <= fz.MaxX and z >= fz.MinZ and z <= fz.MaxZ then
        return "forbidden"
    end

    local sz = OverworldConfig.SafeZone
    if x >= sz.MinX and x <= sz.MaxX and z >= sz.MinZ and z <= sz.MaxZ then
        return "safe"
    end

    return "wilderness"
end

--[[
    Checks if PvP is allowed at a position.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return boolean - True if PvP allowed (not in safe zone)
]]
function OverworldConfig.CanPvPAt(x: number, z: number): boolean
    return OverworldConfig.GetZone(x, z) ~= "safe"
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

--[[
    Gets bandit tier (1-5) based on distance from map center.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return number - Tier 1-5
]]
function OverworldConfig.GetBanditTier(x: number, z: number): number
    local zone = OverworldConfig.GetZone(x, z)
    if zone == "forbidden" then
        return 5
    end
    if zone == "safe" then
        return 1
    end

    -- Wilderness: tier based on distance from center
    local cx = OverworldConfig.Map.CenterX
    local cz = OverworldConfig.Map.CenterZ
    local dist = math.sqrt((x - cx)^2 + (z - cz)^2)

    if dist < 500 then return 2 end
    if dist < 700 then return 3 end
    return 4
end

-- ============================================================================
-- GRID HELPER FUNCTIONS
-- ============================================================================

--[[
    Converts grid cell coordinates to world position (center of cell).

    @param row number - Grid row (0-indexed)
    @param col number - Grid column (0-indexed)
    @return number, number - World X, Z coordinates
]]
function OverworldConfig.GridCellToWorld(row: number, col: number): (number, number)
    local grid = OverworldConfig.Grid
    local x = grid.OriginX + col * grid.CellSize
    local z = grid.OriginZ + row * grid.CellSize
    return x, z
end

--[[
    Snaps a world position to the nearest grid cell.

    @param x number - World X coordinate
    @param z number - World Z coordinate
    @return number, number - Grid row, col (0-indexed, clamped to grid bounds)
]]
function OverworldConfig.WorldToGridCell(x: number, z: number): (number, number)
    local grid = OverworldConfig.Grid
    local col = math.floor((x - grid.OriginX + grid.CellSize / 2) / grid.CellSize)
    local row = math.floor((z - grid.OriginZ + grid.CellSize / 2) / grid.CellSize)
    row = math.clamp(row, 0, grid.Rows - 1)
    col = math.clamp(col, 0, grid.Cols - 1)
    return row, col
end

return OverworldConfig
