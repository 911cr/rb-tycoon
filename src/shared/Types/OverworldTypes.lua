--!strict
--[[
    OverworldTypes.lua

    Type definitions for the 3D walkable overworld system.
    Used by both server and client.
]]

-- Import related types
local PlayerTypes = require(script.Parent.PlayerTypes)

-- ============================================================================
-- TELEPORT TYPES
-- ============================================================================

export type TeleportSource = "Overworld" | "Village" | "Battle"

export type TeleportData = {
    sourcePlace: TeleportSource,
    playerId: number,
    returnPosition: Vector3?,
    timestamp: number,
    targetBaseId: number?, -- For attacks, the defender's userId
}

export type TeleportResult = {
    success: boolean,
    error: string?,
}

-- ============================================================================
-- MINI-BASE TYPES
-- ============================================================================

export type MiniBaseData = {
    -- Owner information
    userId: number,
    username: string,

    -- Position on map
    position: Vector3,

    -- Player stats for display
    townHallLevel: number,
    trophies: number,
    league: string,

    -- Shield status
    hasShield: boolean,
    shieldExpiresAt: number?,

    -- Social
    isFriend: boolean,
    isOwnBase: boolean,
    allianceId: string?,
    allianceName: string?,

    -- Last activity
    lastOnline: number,
    isOnline: boolean,

    -- Resources for attack preview (only if scouted)
    resources: {
        gold: number?,
        wood: number?,
        food: number?,
    }?,
}

export type MiniBaseModel = {
    -- The actual Model in workspace
    model: Model,

    -- Associated data
    data: MiniBaseData,

    -- Visual components
    keep: Part,
    walls: Model,
    banner: BillboardGui,
    gate: Part,

    -- State
    visible: boolean,
    highlighted: boolean,
}

export type MiniBaseSpawnResult = {
    success: boolean,
    model: Model?,
    error: string?,
}

-- ============================================================================
-- INTERACTION TYPES
-- ============================================================================

export type InteractionType = "Enter" | "Scout" | "Attack" | "Visit"

export type BaseInteraction = {
    type: InteractionType,
    targetUserId: number,
    targetBase: MiniBaseData,
    distance: number,
}

export type InteractionResult = {
    success: boolean,
    action: InteractionType?,
    error: string?,
}

-- ============================================================================
-- OVERWORLD STATE TYPES
-- ============================================================================

export type OverworldPlayerState = {
    -- Player reference
    player: Player,
    userId: number,

    -- Current position in overworld
    position: Vector3,
    lastUpdateTime: number,

    -- Mini-base reference
    miniBase: MiniBaseModel?,

    -- Interaction state
    nearbyBases: {MiniBaseData},
    selectedBase: MiniBaseData?,
    isInteracting: boolean,

    -- Travel state (if walking to a base)
    travelTarget: MiniBaseData?,
    travelStartTime: number?,
}

export type OverworldServerState = {
    -- All active players in overworld
    players: {[number]: OverworldPlayerState}, -- userId -> state

    -- Cached mini-base data for all players
    basesCache: {[number]: MiniBaseData}, -- userId -> baseData

    -- Last cache update time
    lastCacheUpdate: number,
}

-- ============================================================================
-- TERRAIN TYPES
-- ============================================================================

export type TerrainZoneType = "Road" | "Forest" | "Meadow" | "River" | "Hill"

export type TerrainZone = {
    type: TerrainZoneType,
    bounds: {
        minX: number,
        maxX: number,
        minZ: number,
        maxZ: number,
    },
    properties: {[string]: any},
}

export type RoadSegment = {
    startPos: Vector3,
    endPos: Vector3,
    width: number,
}

-- ============================================================================
-- UI TYPES
-- ============================================================================

export type BaseInfoUIData = {
    username: string,
    townHallLevel: number,
    trophies: number,
    league: string,
    allianceName: string?,
    isOnline: boolean,
    isFriend: boolean,
    isOwnBase: boolean,
    hasShield: boolean,
    difficulty: "Easy" | "Medium" | "Hard",
}

export type OverworldHUDData = {
    -- Player resources
    resources: PlayerTypes.ResourceData,
    storageCapacity: PlayerTypes.StorageCapacity,

    -- Position info
    currentPosition: Vector3,
    nearbyPlayersCount: number,

    -- Map state
    zoomLevel: number,
}

-- ============================================================================
-- SERVICE RESULT TYPES
-- ============================================================================

export type GetNearbyBasesResult = {
    success: boolean,
    bases: {MiniBaseData}?,
    error: string?,
}

export type UpdatePositionResult = {
    success: boolean,
    newPosition: Vector3?,
    error: string?,
}

export type EnterVillageResult = {
    success: boolean,
    error: string?,
}

export type StartAttackResult = {
    success: boolean,
    battleId: string?,
    error: string?,
}

return nil
