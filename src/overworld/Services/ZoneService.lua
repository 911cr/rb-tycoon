--!strict
--[[
    ZoneService.lua

    Foundation service for all wilderness gameplay systems.
    Provides zone detection, PvP gating, bandit tier lookup,
    and base/river spawn exclusion checks.

    Wraps OverworldConfig geometric helpers and adds server-side
    state tracking (player zone transitions, zone entry/exit events).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local ZoneService = {}
ZoneService.__index = ZoneService

-- ============================================================================
-- SIGNALS
-- ============================================================================

ZoneService.PlayerEnteredSafeZone = Signal.new()
ZoneService.PlayerLeftSafeZone = Signal.new()
ZoneService.PlayerEnteredWilderness = Signal.new()
ZoneService.PlayerEnteredForbiddenZone = Signal.new()

-- ============================================================================
-- TYPES
-- ============================================================================

export type ZoneType = "safe" | "wilderness" | "forbidden"

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

-- Track each player's current zone for transition events
local _playerZones: {[number]: ZoneType} = {}

-- River path segments (approximate) for spawn exclusion
-- Matches the river path carved in WorldBuilder:
--   SW (100,1600) -> center (900,1000) -> E (1900,750)
local RIVER_SEGMENTS = {
    { x1 = 100, z1 = 1600, x2 = 500, z2 = 1300 },
    { x1 = 500, z1 = 1300, x2 = 900, z2 = 1000 },
    { x1 = 900, z1 = 1000, x2 = 1400, z2 = 870 },
    { x1 = 1400, z1 = 870, x2 = 1900, z2 = 750 },
}

local RIVER_WIDTH = OverworldConfig.Terrain.River.Width
local LAKE_CENTER_X = 250
local LAKE_CENTER_Z = 1500
local LAKE_RADIUS = 80

local _initialized = false
local _updateConnection: RBXScriptConnection? = nil

-- ============================================================================
-- PRIVATE FUNCTIONS
-- ============================================================================

--[[
    Calculates the minimum distance from a point to a line segment.
    Used for river proximity checks.
]]
local function distToSegment(px: number, pz: number, x1: number, z1: number, x2: number, z2: number): number
    local dx = x2 - x1
    local dz = z2 - z1
    local lenSq = dx * dx + dz * dz

    if lenSq == 0 then
        local ex = px - x1
        local ez = pz - z1
        return math.sqrt(ex * ex + ez * ez)
    end

    local t = math.clamp(((px - x1) * dx + (pz - z1) * dz) / lenSq, 0, 1)
    local projX = x1 + t * dx
    local projZ = z1 + t * dz
    local ex = px - projX
    local ez = pz - projZ
    return math.sqrt(ex * ex + ez * ez)
end

--[[
    Checks if a position is near the river or lake.
]]
local function isNearWater(x: number, z: number, margin: number): boolean
    -- Check lake
    local lakeDx = x - LAKE_CENTER_X
    local lakeDz = z - LAKE_CENTER_Z
    if math.sqrt(lakeDx * lakeDx + lakeDz * lakeDz) < (LAKE_RADIUS + margin) then
        return true
    end

    -- Check river segments
    local halfWidth = RIVER_WIDTH / 2 + margin
    for _, seg in RIVER_SEGMENTS do
        if distToSegment(x, z, seg.x1, seg.z1, seg.x2, seg.z2) < halfWidth then
            return true
        end
    end

    return false
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Initializes the zone tracking loop.
    Should be called once from Main.server.lua.
]]
function ZoneService:Init()
    if _initialized then
        warn("[ZoneService] Already initialized")
        return
    end
    _initialized = true

    -- Track zone transitions every 1 second
    local elapsed = 0
    _updateConnection = RunService.Heartbeat:Connect(function(dt)
        elapsed += dt
        if elapsed < 1 then return end
        elapsed = 0

        for _, player in Players:GetPlayers() do
            local character = player.Character
            if not character then continue end

            local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not root then continue end

            local pos = root.Position
            local newZone = self:GetZone(pos.X, pos.Z)
            local oldZone = _playerZones[player.UserId]

            if oldZone ~= newZone then
                _playerZones[player.UserId] = newZone

                -- Fire transition events (skip initial assignment)
                if oldZone then
                    if oldZone == "safe" then
                        self.PlayerLeftSafeZone:Fire(player, newZone)
                    end

                    if newZone == "safe" then
                        self.PlayerEnteredSafeZone:Fire(player)
                    elseif newZone == "wilderness" then
                        self.PlayerEnteredWilderness:Fire(player)
                    elseif newZone == "forbidden" then
                        self.PlayerEnteredForbiddenZone:Fire(player)
                    end
                end
            end
        end
    end)

    -- Clean up on player leave
    Players.PlayerRemoving:Connect(function(player)
        _playerZones[player.UserId] = nil
    end)
end

--[[
    Stops the zone tracking loop. Called on server shutdown.
]]
function ZoneService:Destroy()
    if _updateConnection then
        _updateConnection:Disconnect()
        _updateConnection = nil
    end
    _playerZones = {}
    _initialized = false
end

-- ============================================================================
-- ZONE QUERIES
-- ============================================================================

--[[
    Determines which zone a position falls in.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return ZoneType - "safe", "wilderness", or "forbidden"
]]
function ZoneService:GetZone(x: number, z: number): ZoneType
    return OverworldConfig.GetZone(x, z) :: ZoneType
end

--[[
    Checks if a position is within the safe zone.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return boolean
]]
function ZoneService:IsInSafeZone(x: number, z: number): boolean
    return OverworldConfig.GetZone(x, z) == "safe"
end

--[[
    Checks if a position is within the forbidden zone.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return boolean
]]
function ZoneService:IsInForbiddenZone(x: number, z: number): boolean
    return OverworldConfig.GetZone(x, z) == "forbidden"
end

--[[
    Checks if PvP combat is allowed at a position.
    PvP is NOT allowed in the safe zone.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return boolean
]]
function ZoneService:CanPvPAt(x: number, z: number): boolean
    return OverworldConfig.CanPvPAt(x, z)
end

--[[
    Gets the bandit difficulty tier (1-5) based on position.
    - Safe zone edge: tier 1 (weak scouts)
    - Inner wilderness: tier 2-3
    - Outer wilderness: tier 4
    - Forbidden zone: tier 5 (elite)

    @param x number - X coordinate
    @param z number - Z coordinate
    @return number - Tier 1-5
]]
function ZoneService:GetBanditTierForPosition(x: number, z: number): number
    return OverworldConfig.GetBanditTier(x, z)
end

--[[
    Gets the stat multiplier for enemies in this zone.
    Forbidden zone enemies get 2.5x stats.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return number - Stat multiplier (1.0 for normal, 2.5 for forbidden)
]]
function ZoneService:GetStatMultiplier(x: number, z: number): number
    if OverworldConfig.GetZone(x, z) == "forbidden" then
        return OverworldConfig.ForbiddenZone.StatMultiplier
    end
    return 1.0
end

--[[
    Checks if a base can be spawned at a position.
    Bases cannot be placed in the forbidden zone or on water.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return boolean
]]
function ZoneService:CanSpawnBaseAt(x: number, z: number): boolean
    -- Must be within map bounds
    if not OverworldConfig.IsInBounds(x, z) then
        return false
    end

    -- Cannot place in forbidden zone
    if OverworldConfig.GetZone(x, z) == "forbidden" then
        return false
    end

    -- Cannot place on/near river or lake
    if isNearWater(x, z, 20) then
        return false
    end

    return true
end

--[[
    Checks if a position is near water (river or lake).
    Used to prevent spawning entities in water.

    @param x number - X coordinate
    @param z number - Z coordinate
    @param margin number? - Extra margin around water (default 5)
    @return boolean
]]
function ZoneService:IsNearWater(x: number, z: number, margin: number?): boolean
    return isNearWater(x, z, margin or 5)
end

--[[
    Gets the current zone for a player (cached from tracking loop).
    Returns nil if player hasn't been tracked yet.

    @param player Player
    @return ZoneType? - Current zone or nil
]]
function ZoneService:GetPlayerZone(player: Player): ZoneType?
    return _playerZones[player.UserId]
end

--[[
    Checks if a player is currently in the safe zone.

    @param player Player
    @return boolean
]]
function ZoneService:IsPlayerInSafeZone(player: Player): boolean
    return _playerZones[player.UserId] == "safe"
end

--[[
    Gets the zone atmosphere color for client visuals.

    @param zone ZoneType
    @return Color3
]]
function ZoneService:GetZoneColor(zone: ZoneType): Color3
    local colors = OverworldConfig.Visuals.ZoneColors
    if zone == "safe" then
        return colors.Safe
    elseif zone == "forbidden" then
        return colors.Forbidden
    end
    return colors.Wilderness
end

return ZoneService
