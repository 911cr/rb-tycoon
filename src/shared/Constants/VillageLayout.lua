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
    -- Trigger zone in front of the entrance gate (local coords, offset by CenterOffset)
    -- Gate arch is at world (60, Y, 8), towers at X=45..75
    -- Local: center X=10, Z=-42; trigger just outside gate (lower Z = outside village)
    position = Vector3.new(10, 3, -46),
    size = Vector3.new(30, 10, 6), -- Wide enough for gate opening, thin trigger strip
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
