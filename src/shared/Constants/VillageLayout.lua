--!strict
--[[
    VillageLayout.lua

    Defines the static layout of the medieval village.
    All buildings are pre-positioned to create a cohesive town.
]]

local VillageLayout = {}

-- Grid scale (studs per unit)
local SCALE = 3

-- ============================================================================
-- BUILDING POSITIONS
-- All coordinates are in studs, relative to village center (0, 0)
-- ============================================================================

VillageLayout.Buildings = {
    -- No pre-placed buildings - players build their own
}

-- ============================================================================
-- STREET LAYOUT
-- ============================================================================

VillageLayout.Streets = {
    -- No pre-placed streets
}

-- ============================================================================
-- FARM ZONE
-- ============================================================================

VillageLayout.FarmZone = {
    -- No pre-placed farm elements
}

-- ============================================================================
-- DEFENSE ZONE
-- ============================================================================

VillageLayout.DefenseZone = {
    -- No pre-placed defenses
}

-- ============================================================================
-- DECORATIONS
-- ============================================================================

VillageLayout.Decorations = {
    -- No pre-placed decorations
    StreetLamps = {},
    Barrels = {},
    Crates = {},
    Benches = {},
}

-- ============================================================================
-- VILLAGE GATE (Exit to World Map)
-- ============================================================================

VillageLayout.Gate = {
    -- Trigger zone spanning the gate doorway and extending far outside the village.
    -- Gate arch is at world (60, Y, 8), gate opening X=47..73, GROUND_Y=2.
    -- This zone starts a few studs INSIDE the gate (world Z=12) and extends
    -- far outside (world Z=-40) so you can't miss it.
    -- Local coords: world - CenterOffset(50,0,50)
    position = Vector3.new(10, 5, -64), -- world center: (60, 5, -14)
    size = Vector3.new(30, 14, 52),     -- fills gate opening, 52 studs deep (inside to far outside)
}

-- ============================================================================
-- VILLAGE BOUNDS
-- ============================================================================

VillageLayout.Bounds = {
    MinX = -35,
    MaxX = 45,
    MinZ = -50, -- Extended to include gate area
    MaxZ = 65,
    CenterOffset = Vector3.new(50, 0, 50), -- Offset from world origin (village center)
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

function VillageLayout.GetWorldPosition(localPos: Vector3): Vector3
    return localPos + VillageLayout.Bounds.CenterOffset
end

function VillageLayout.GetBuildingWorldPosition(buildingType: string): Vector3?
    local building = VillageLayout.Buildings[buildingType]
    if building then
        return VillageLayout.GetWorldPosition(building.position)
    end
    return nil
end

--[[
    Gets the world position of the gate trigger zone.
]]
function VillageLayout.GetGateWorldPosition(): Vector3
    return VillageLayout.GetWorldPosition(VillageLayout.Gate.position)
end

--[[
    Gets the gate trigger zone bounds in world space.
    Returns center position and size.
]]
function VillageLayout.GetGateTriggerBounds(): (Vector3, Vector3)
    local center = VillageLayout.GetGateWorldPosition()
    local size = VillageLayout.Gate.size
    return center, size
end

--[[
    Checks if a world position is within the gate trigger zone.
]]
function VillageLayout.IsAtGate(worldPosition: Vector3): boolean
    local center, size = VillageLayout.GetGateTriggerBounds()

    local halfSize = size / 2
    local minBound = center - halfSize
    local maxBound = center + halfSize

    return worldPosition.X >= minBound.X and worldPosition.X <= maxBound.X
        and worldPosition.Y >= minBound.Y - 2 and worldPosition.Y <= maxBound.Y + 2 -- Allow some Y tolerance
        and worldPosition.Z >= minBound.Z and worldPosition.Z <= maxBound.Z
end

return VillageLayout
