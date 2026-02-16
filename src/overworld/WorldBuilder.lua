--!strict
--[[
    WorldBuilder.lua

    Builds the 3D voxel terrain environment for the overworld.
    Uses workspace.Terrain:FillRegion() for natural Perlin-noise heightmap,
    then places roads, rivers, trees, rocks, and decorations — all raycast-
    grounded on the terrain surface.

    6 sequential passes:
    1. Heightmap (Perlin noise with zone-aware shaping)
    2. Roads (carved flat cobblestone paths)
    3. River & Lake (carved depression, filled with water)
    4. Trees (raycast-placed on terrain surface)
    5. Rocks & Decorations (raycast-placed, partially embedded)
    6. Boundary (invisible walls at map edges)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)

local WorldBuilder = {}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local MAP_SIZE = OverworldConfig.Map.Width -- 2000
local MAP_CENTER = MAP_SIZE / 2
local VOXEL = OverworldConfig.Terrain.VoxelSize -- 4
local SEED = OverworldConfig.Terrain.SeedOffset

-- Colors for Part-based decorations
local Colors = {
    TreeTrunk = Color3.fromRGB(85, 60, 40),
    TreeTrunkDark = Color3.fromRGB(55, 35, 25),
    TreeLeaves = Color3.fromRGB(60, 120, 45),
    TreeLeavesDark = Color3.fromRGB(45, 90, 35),
    TreeLeavesLight = Color3.fromRGB(75, 140, 55),
    DeadWood = Color3.fromRGB(70, 55, 40),
    Rock = Color3.fromRGB(100, 100, 105),
    RockDark = Color3.fromRGB(80, 80, 85),
    RockLight = Color3.fromRGB(120, 118, 115),
    SignPost = Color3.fromRGB(120, 90, 60),
    SignBoard = Color3.fromRGB(160, 130, 90),
    TorchBase = Color3.fromRGB(90, 65, 45),
    BridgeStone = Color3.fromRGB(140, 130, 120),
}

-- ============================================================================
-- FOLDER REFERENCES
-- ============================================================================

local _worldFolder: Folder
local _propsFolder: Folder
local _treesFolder: Folder

-- ============================================================================
-- TERRAIN HELPERS
-- ============================================================================

local _terrain: Terrain

--[[
    Multi-octave Perlin noise for natural heightmap.
]]
local function sampleHeight(x: number, z: number): number
    local h = 0
    for _, octave in OverworldConfig.Terrain.Octaves do
        h += math.noise(x * octave.scale + SEED, z * octave.scale + SEED) * octave.amplitude
    end
    return h
end

--[[
    Get zone-modified height at a world position.
    Safe zone is flattened, forbidden zone is raised.
]]
local function getWorldHeight(x: number, z: number): number
    local raw = sampleHeight(x, z)

    -- Safe zone flattening
    local sz = OverworldConfig.SafeZone
    local safeCenterX = (sz.MinX + sz.MaxX) / 2
    local safeCenterZ = (sz.MinZ + sz.MaxZ) / 2
    local safeDist = math.sqrt((x - safeCenterX)^2 + (z - safeCenterZ)^2)
    local flattenRadius = sz.FlattenRadius

    if safeDist < flattenRadius then
        local t = safeDist / flattenRadius
        local flattenAmount = 1 - t * t -- quadratic falloff
        raw = raw * (1 - flattenAmount * sz.FlattenStrength)
    end

    -- Forbidden zone elevation boost
    local fz = OverworldConfig.ForbiddenZone
    if x >= fz.MinX and x <= fz.MaxX and z >= fz.MinZ and z <= fz.MaxZ then
        -- Smooth ramp into forbidden zone
        local edgeDist = math.min(
            x - fz.MinX, fz.MaxX - x,
            z - fz.MinZ, fz.MaxZ - z
        )
        local ramp = math.clamp(edgeDist / 80, 0, 1) -- 80 studs transition
        raw += fz.HeightBoost * ramp
    end

    return raw
end

--[[
    Get terrain material based on zone and height.
]]
local function getMaterial(x: number, z: number, height: number): Enum.Material
    local mats = OverworldConfig.Terrain.Materials
    local zone = OverworldConfig.GetZone(x, z)

    if zone == "forbidden" then
        if height > 20 then
            return mats.ForbiddenRock
        end
        return mats.Forbidden
    end

    if zone == "safe" then
        return mats.Safe
    end

    -- Wilderness: vary by height and noise
    if height > 18 then
        return mats.WildernessRock
    end
    local detail = math.noise(x * 0.05 + SEED + 100, z * 0.05 + SEED + 100)
    if detail > 0.3 then
        return mats.WildernessMud
    end
    return mats.Wilderness
end

--[[
    Raycast terrain surface to find exact Y at (x, z).
    Returns nil if no terrain hit (e.g. over water void).
]]
local function raycastTerrain(x: number, z: number): RaycastResult?
    local origin = Vector3.new(x, 200, z)
    local direction = Vector3.new(0, -400, 0)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {_terrain}
    return workspace:Raycast(origin, direction, params)
end

--[[
    Place a model on terrain surface with partial embedding.
]]
local function placeOnTerrain(x: number, z: number, model: Model, embedDepth: number)
    local hit = raycastTerrain(x, z)
    if not hit then return false end

    local surfaceY = hit.Position.Y
    model:PivotTo(CFrame.new(x, surfaceY - embedDepth, z))
    model.Parent = _propsFolder
    return true
end

--[[
    Place a single Part on terrain surface with partial embedding.
]]
local function placePartOnTerrain(x: number, z: number, part: BasePart, embedDepth: number): boolean
    local hit = raycastTerrain(x, z)
    if not hit then return false end

    local surfaceY = hit.Position.Y
    part.Position = Vector3.new(x, surfaceY - embedDepth + part.Size.Y / 2, z)
    part.Parent = _propsFolder
    return true
end

-- ============================================================================
-- PASS 1: HEIGHTMAP
-- ============================================================================

--[[
    Fills voxel terrain column by column using FillRegion.
    Processes in chunks for performance.
]]
local function buildHeightmap()
    print("[WorldBuilder] Pass 1: Building heightmap...")

    local chunkSize = 64 -- process 64x64 stud chunks
    local totalChunks = 0
    local baseY = -20 -- fill from below ground up to surface

    for cx = 0, MAP_SIZE - 1, chunkSize do
        for cz = 0, MAP_SIZE - 1, chunkSize do
            -- For each chunk, determine the max height to know fill range
            local maxH = 0
            for lx = cx, math.min(cx + chunkSize - 1, MAP_SIZE - 1), VOXEL do
                for lz = cz, math.min(cz + chunkSize - 1, MAP_SIZE - 1), VOXEL do
                    local h = getWorldHeight(lx, lz)
                    if h > maxH then maxH = h end
                end
            end

            -- Fill from baseY up to slightly above max height
            local fillTop = maxH + VOXEL
            local region = Region3.new(
                Vector3.new(cx, baseY, cz),
                Vector3.new(math.min(cx + chunkSize, MAP_SIZE), fillTop, math.min(cz + chunkSize, MAP_SIZE))
            ):ExpandToGrid(VOXEL)

            local regionSize = region.Size / VOXEL
            local sizeX = math.max(1, math.round(regionSize.X))
            local sizeY = math.max(1, math.round(regionSize.Y))
            local sizeZ = math.max(1, math.round(regionSize.Z))

            -- Create material and occupancy arrays
            local materials = {}
            local occupancy = {}

            for ix = 1, sizeX do
                materials[ix] = {}
                occupancy[ix] = {}
                for iy = 1, sizeY do
                    materials[ix][iy] = {}
                    occupancy[ix][iy] = {}
                    for iz = 1, sizeZ do
                        local worldX = region.CFrame.Position.X - region.Size.X/2 + (ix - 0.5) * VOXEL
                        local worldY = region.CFrame.Position.Y - region.Size.Y/2 + (iy - 0.5) * VOXEL
                        local worldZ = region.CFrame.Position.Z - region.Size.Z/2 + (iz - 0.5) * VOXEL

                        local surfaceH = getWorldHeight(worldX, worldZ)

                        if worldY <= surfaceH then
                            local mat = getMaterial(worldX, worldZ, surfaceH)
                            materials[ix][iy][iz] = mat
                            -- Smooth occupancy at the surface for natural slopes
                            if worldY > surfaceH - VOXEL then
                                local frac = (surfaceH - worldY) / VOXEL
                                occupancy[ix][iy][iz] = math.clamp(frac + 0.5, 0, 1)
                            else
                                occupancy[ix][iy][iz] = 1
                            end
                        else
                            materials[ix][iy][iz] = Enum.Material.Air
                            occupancy[ix][iy][iz] = 0
                        end
                    end
                end
            end

            _terrain:WriteVoxels(region, VOXEL, materials, occupancy)

            totalChunks += 1
            -- Yield periodically to avoid timeout
            if totalChunks % 8 == 0 then
                task.wait()
            end
        end
    end

    print(string.format("[WorldBuilder] Heightmap complete (%d chunks)", totalChunks))
end

-- ============================================================================
-- PASS 2: ROADS
-- ============================================================================

--[[
    Carve a flat road along a path by setting terrain to Cobblestone at surface level.
]]
local function carveRoad(points: {Vector3}, width: number)
    local mats = OverworldConfig.Terrain.Materials

    for i = 1, #points - 1 do
        local p1 = points[i]
        local p2 = points[i + 1]
        local dir = (p2 - p1).Unit
        local length = (p2 - p1).Magnitude
        local perp = Vector3.new(-dir.Z, 0, dir.X)

        -- Walk along the road segment
        local step = VOXEL
        for d = 0, length, step do
            local center = p1 + dir * d
            -- Sample height at road center
            local roadY = getWorldHeight(center.X, center.Z)

            -- Fill road cross-section
            for w = -width/2, width/2, VOXEL do
                local wx = center.X + perp.X * w
                local wz = center.Z + perp.Z * w

                if wx >= 0 and wx <= MAP_SIZE and wz >= 0 and wz <= MAP_SIZE then
                    -- Clear above road
                    local clearRegion = Region3.new(
                        Vector3.new(wx - VOXEL/2, roadY - 0.5, wz - VOXEL/2),
                        Vector3.new(wx + VOXEL/2, roadY + 4, wz + VOXEL/2)
                    ):ExpandToGrid(VOXEL)
                    _terrain:FillRegion(clearRegion, VOXEL, Enum.Material.Air)

                    -- Fill road surface
                    local roadRegion = Region3.new(
                        Vector3.new(wx - VOXEL/2, roadY - 1, wz - VOXEL/2),
                        Vector3.new(wx + VOXEL/2, roadY + 0.2, wz + VOXEL/2)
                    ):ExpandToGrid(VOXEL)
                    _terrain:FillRegion(roadRegion, VOXEL, mats.Road)
                end
            end
        end
    end
end

local function buildRoads()
    print("[WorldBuilder] Pass 2: Building roads...")

    local mainWidth = OverworldConfig.Terrain.Roads.MainWidth
    local secWidth = OverworldConfig.Terrain.Roads.SecondaryWidth

    -- Main crossroads through center
    -- East-West
    carveRoad({
        Vector3.new(100, 0, MAP_CENTER),
        Vector3.new(MAP_SIZE - 100, 0, MAP_CENTER),
    }, mainWidth)

    -- North-South
    carveRoad({
        Vector3.new(MAP_CENTER, 0, 100),
        Vector3.new(MAP_CENTER, 0, MAP_SIZE - 100),
    }, mainWidth)

    -- Secondary grid within safe zone
    local sz = OverworldConfig.SafeZone
    local spacing = 200

    for x = sz.MinX, sz.MaxX, spacing do
        if math.abs(x - MAP_CENTER) > 50 then
            carveRoad({
                Vector3.new(x, 0, sz.MinZ),
                Vector3.new(x, 0, sz.MaxZ),
            }, secWidth)
        end
    end

    for z = sz.MinZ, sz.MaxZ, spacing do
        if math.abs(z - MAP_CENTER) > 50 then
            carveRoad({
                Vector3.new(sz.MinX, 0, z),
                Vector3.new(sz.MaxX, 0, z),
            }, secWidth)
        end
    end

    task.wait()
    print("[WorldBuilder] Roads complete")
end

-- ============================================================================
-- PASS 3: RIVER & LAKE
-- ============================================================================

local function buildRiver()
    print("[WorldBuilder] Pass 3: Building river & lake...")

    local riverWidth = OverworldConfig.Terrain.River.Width
    local riverDepth = OverworldConfig.Terrain.River.Depth
    local waterLevel = OverworldConfig.Terrain.River.WaterLevel

    -- River path: winding from SW through center to E
    local riverPoints = {
        Vector3.new(100, 0, 1600),     -- SW start
        Vector3.new(300, 0, 1400),
        Vector3.new(500, 0, 1200),
        Vector3.new(700, 0, 1050),
        Vector3.new(900, 0, 1000),     -- Approaches center
        Vector3.new(1100, 0, 950),
        Vector3.new(1300, 0, 900),
        Vector3.new(1500, 0, 850),
        Vector3.new(1700, 0, 800),
        Vector3.new(1900, 0, 750),     -- Exits east
    }

    -- Carve river channel
    for i = 1, #riverPoints - 1 do
        local p1 = riverPoints[i]
        local p2 = riverPoints[i + 1]
        local dir = (p2 - p1).Unit
        local length = (p2 - p1).Magnitude
        local perp = Vector3.new(-dir.Z, 0, dir.X)

        for d = 0, length, VOXEL do
            local center = p1 + dir * d

            for w = -riverWidth/2, riverWidth/2, VOXEL do
                local wx = center.X + perp.X * w
                local wz = center.Z + perp.Z * w

                if wx >= 0 and wx <= MAP_SIZE and wz >= 0 and wz <= MAP_SIZE then
                    -- Parabolic depth profile (deeper at center)
                    local normalizedW = math.abs(w) / (riverWidth / 2)
                    local depthHere = riverDepth * (1 - normalizedW * normalizedW)

                    -- Carve depression (air)
                    local clearRegion = Region3.new(
                        Vector3.new(wx - VOXEL/2, waterLevel - depthHere, wz - VOXEL/2),
                        Vector3.new(wx + VOXEL/2, waterLevel + 3, wz + VOXEL/2)
                    ):ExpandToGrid(VOXEL)
                    _terrain:FillRegion(clearRegion, VOXEL, Enum.Material.Air)

                    -- Fill riverbed with sand
                    local bedRegion = Region3.new(
                        Vector3.new(wx - VOXEL/2, waterLevel - depthHere - VOXEL, wz - VOXEL/2),
                        Vector3.new(wx + VOXEL/2, waterLevel - depthHere, wz + VOXEL/2)
                    ):ExpandToGrid(VOXEL)
                    _terrain:FillRegion(bedRegion, VOXEL, Enum.Material.Sand)

                    -- Fill with water
                    local waterRegion = Region3.new(
                        Vector3.new(wx - VOXEL/2, waterLevel - depthHere, wz - VOXEL/2),
                        Vector3.new(wx + VOXEL/2, waterLevel, wz + VOXEL/2)
                    ):ExpandToGrid(VOXEL)
                    _terrain:FillRegion(waterRegion, VOXEL, Enum.Material.Water)
                end
            end
        end

        task.wait()
    end

    -- Lake in SW area (near river start)
    local lakeCenter = Vector3.new(250, 0, 1500)
    local lakeRadius = 80

    for lx = lakeCenter.X - lakeRadius, lakeCenter.X + lakeRadius, VOXEL do
        for lz = lakeCenter.Z - lakeRadius, lakeCenter.Z + lakeRadius, VOXEL do
            local dist = math.sqrt((lx - lakeCenter.X)^2 + (lz - lakeCenter.Z)^2)
            if dist <= lakeRadius then
                local normalizedDist = dist / lakeRadius
                local depthHere = riverDepth * 1.5 * (1 - normalizedDist * normalizedDist)

                -- Carve
                local clearRegion = Region3.new(
                    Vector3.new(lx - VOXEL/2, waterLevel - depthHere, lz - VOXEL/2),
                    Vector3.new(lx + VOXEL/2, waterLevel + 2, lz + VOXEL/2)
                ):ExpandToGrid(VOXEL)
                _terrain:FillRegion(clearRegion, VOXEL, Enum.Material.Air)

                -- Sand bed
                local bedRegion = Region3.new(
                    Vector3.new(lx - VOXEL/2, waterLevel - depthHere - VOXEL, lz - VOXEL/2),
                    Vector3.new(lx + VOXEL/2, waterLevel - depthHere, lz + VOXEL/2)
                ):ExpandToGrid(VOXEL)
                _terrain:FillRegion(bedRegion, VOXEL, Enum.Material.Sand)

                -- Water fill
                local waterRegion = Region3.new(
                    Vector3.new(lx - VOXEL/2, waterLevel - depthHere, lz - VOXEL/2),
                    Vector3.new(lx + VOXEL/2, waterLevel, lz + VOXEL/2)
                ):ExpandToGrid(VOXEL)
                _terrain:FillRegion(waterRegion, VOXEL, Enum.Material.Water)
            end
        end
    end

    task.wait()
    print("[WorldBuilder] River & lake complete")
end

-- ============================================================================
-- PASS 4: TREES
-- ============================================================================

--[[
    Creates an oak tree model (tapered trunk + foliage balls).
]]
local function createOakTree(scale: number): Model
    local tree = Instance.new("Model")
    tree.Name = "OakTree"

    local trunkH = (6 + math.random() * 3) * scale
    local trunkW = (0.8 + math.random() * 0.4) * scale

    -- Trunk (block instead of cylinder to avoid rotation issues)
    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Shape = Enum.PartType.Block
    trunk.Size = Vector3.new(trunkW, trunkH, trunkW)
    trunk.CFrame = CFrame.new(0, trunkH / 2, 0)
    trunk.Anchored = true
    trunk.Material = Enum.Material.Wood
    trunk.Color = Colors.TreeTrunk
    trunk.Parent = tree
    tree.PrimaryPart = trunk

    -- Foliage (3 overlapping balls)
    local foliageColors = {Colors.TreeLeaves, Colors.TreeLeavesDark, Colors.TreeLeavesLight}
    for i = 1, 3 do
        local radius = (2.5 + math.random() * 1.5) * scale
        local offsetX = (math.random() - 0.5) * radius * 0.5
        local offsetZ = (math.random() - 0.5) * radius * 0.5
        local foliage = Instance.new("Part")
        foliage.Name = "Foliage"
        foliage.Shape = Enum.PartType.Ball
        foliage.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
        foliage.Position = Vector3.new(offsetX, trunkH + radius * 0.5 + (i - 1) * radius * 0.4, offsetZ)
        foliage.Anchored = true
        foliage.Material = Enum.Material.LeafyGrass
        foliage.Color = foliageColors[i]
        foliage.Parent = tree
    end

    return tree
end

--[[
    Creates a pine tree model (narrow trunk + stacked cones).
]]
local function createPineTree(scale: number): Model
    local tree = Instance.new("Model")
    tree.Name = "PineTree"

    local trunkH = (8 + math.random() * 4) * scale
    local trunkW = (0.5 + math.random() * 0.3) * scale

    -- Trunk (block to avoid cylinder rotation issues with PivotTo)
    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Shape = Enum.PartType.Block
    trunk.Size = Vector3.new(trunkW, trunkH, trunkW)
    trunk.CFrame = CFrame.new(0, trunkH / 2, 0)
    trunk.Anchored = true
    trunk.Material = Enum.Material.Wood
    trunk.Color = Colors.TreeTrunk
    trunk.Parent = tree
    tree.PrimaryPart = trunk

    -- Cone layers (balls to approximate foliage tiers — avoids cylinder sideways issue)
    local layers = 3 + math.random(0, 1)
    for i = 1, layers do
        local layerRadius = (2.5 - (i - 1) * 0.5) * scale
        local layerH = 2.0 * scale
        local yPos = trunkH * 0.5 + (i - 1) * layerH * 0.7

        local cone = Instance.new("Part")
        cone.Name = "Cone"
        cone.Shape = Enum.PartType.Ball
        cone.Size = Vector3.new(layerRadius * 2, layerH, layerRadius * 2)
        cone.CFrame = CFrame.new(0, yPos, 0)
        cone.Anchored = true
        cone.Material = Enum.Material.LeafyGrass
        cone.Color = i % 2 == 0 and Colors.TreeLeavesDark or Colors.TreeLeaves
        cone.Parent = tree
    end

    return tree
end

--[[
    Creates a dead tree (bare trunk with angled branches).
]]
local function createDeadTree(scale: number): Model
    local tree = Instance.new("Model")
    tree.Name = "DeadTree"

    local trunkH = (5 + math.random() * 3) * scale
    local trunkW = (0.6 + math.random() * 0.3) * scale

    -- Trunk (block to avoid cylinder rotation issues with PivotTo)
    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Shape = Enum.PartType.Block
    trunk.Size = Vector3.new(trunkW, trunkH, trunkW)
    trunk.CFrame = CFrame.new(0, trunkH / 2, 0)
    trunk.Anchored = true
    trunk.Material = Enum.Material.Wood
    trunk.Color = Colors.DeadWood
    trunk.Parent = tree
    tree.PrimaryPart = trunk

    -- Bare branches
    for i = 1, 3 do
        local branchLen = (2 + math.random() * 2) * scale
        local branchW = 0.2 * scale
        local angle = math.rad(30 + math.random() * 40)
        local rotation = math.rad(i * 120 + math.random(-20, 20))

        local branch = Instance.new("Part")
        branch.Name = "Branch"
        branch.Size = Vector3.new(branchLen, branchW, branchW)
        branch.CFrame = CFrame.new(0, trunkH * (0.5 + i * 0.15), 0)
            * CFrame.Angles(0, rotation, angle)
            * CFrame.new(branchLen / 2, 0, 0)
        branch.Anchored = true
        branch.Material = Enum.Material.Wood
        branch.Color = Colors.DeadWood
        branch.Parent = tree
    end

    return tree
end

--[[
    Check if position is near a road or river (avoid placing trees there).
]]
local function isNearRoadOrRiver(x: number, z: number): boolean
    -- Near main roads (center crossroads)
    if math.abs(x - MAP_CENTER) < 20 or math.abs(z - MAP_CENTER) < 20 then
        return true
    end

    -- Near river path (rough approximation)
    -- River runs from (100,1600) through center to (1900,750)
    local riverZ = 1600 - (x / MAP_SIZE) * 850
    if math.abs(z - riverZ) < 40 then
        return true
    end

    -- Near lake
    local lakeDist = math.sqrt((x - 250)^2 + (z - 1500)^2)
    if lakeDist < 100 then
        return true
    end

    return false
end

local function buildTrees()
    print("[WorldBuilder] Pass 4: Placing trees...")

    local treeConfig = OverworldConfig.Terrain.Trees
    local treeCount = 0
    local embedDepth = treeConfig.EmbedDepth

    -- Define forest regions by zone
    local regions = {
        -- Wilderness forests (dense)
        {minX = 50, maxX = 550, minZ = 50, maxZ = 550, density = treeConfig.WildernessDensity, zone = "wilderness"},
        {minX = 1450, maxX = 1950, minZ = 50, maxZ = 550, density = treeConfig.WildernessDensity, zone = "wilderness"},
        {minX = 50, maxX = 550, minZ = 1450, maxZ = 1950, density = treeConfig.WildernessDensity, zone = "wilderness"},
        {minX = 50, maxX = 550, minZ = 600, maxZ = 1400, density = treeConfig.WildernessDensity * 0.6, zone = "wilderness"},
        {minX = 1450, maxX = 1950, minZ = 600, maxZ = 1400, density = treeConfig.WildernessDensity * 0.6, zone = "wilderness"},
        {minX = 600, maxX = 1400, minZ = 50, maxZ = 550, density = treeConfig.WildernessDensity * 0.5, zone = "wilderness"},
        {minX = 600, maxX = 1400, minZ = 1450, maxZ = 1500, density = treeConfig.WildernessDensity * 0.5, zone = "wilderness"},
        -- Safe zone (sparse)
        {minX = 620, maxX = 1380, minZ = 620, maxZ = 1380, density = treeConfig.SafeDensity, zone = "safe"},
        -- Forbidden zone (dead trees)
        {minX = 1510, maxX = 1890, minZ = 1510, maxZ = 1890, density = treeConfig.ForbiddenDensity, zone = "forbidden"},
    }

    for _, region in regions do
        local areaW = region.maxX - region.minX
        local areaD = region.maxZ - region.minZ
        local numTrees = math.floor((areaW * areaD / 100) * region.density)

        for _ = 1, numTrees do
            local x = region.minX + math.random() * areaW
            local z = region.minZ + math.random() * areaD

            -- Skip if near road or river
            if not isNearRoadOrRiver(x, z) then
                local tree: Model
                local scale = 0.8 + math.random() * 0.4

                if region.zone == "forbidden" then
                    tree = createDeadTree(scale)
                elseif math.random() > 0.4 then
                    tree = createOakTree(scale)
                else
                    tree = createPineTree(scale)
                end

                if placeOnTerrain(x, z, tree, embedDepth) then
                    tree.Parent = _treesFolder
                    treeCount += 1
                else
                    tree:Destroy()
                end
            end
        end

        task.wait()
    end

    print(string.format("[WorldBuilder] Trees complete (%d placed)", treeCount))
end

-- ============================================================================
-- PASS 5: ROCKS & DECORATIONS
-- ============================================================================

local function createRock(size: number): Part
    local rock = Instance.new("Part")
    rock.Name = "Rock"
    rock.Shape = math.random() > 0.5 and Enum.PartType.Ball or Enum.PartType.Block
    rock.Size = Vector3.new(
        size * (0.8 + math.random() * 0.4),
        size * (0.5 + math.random() * 0.3),
        size * (0.7 + math.random() * 0.5)
    )
    rock.Orientation = Vector3.new(
        math.random(-15, 15),
        math.random(0, 360),
        math.random(-15, 15)
    )
    rock.Anchored = true
    rock.Material = Enum.Material.Rock

    local colorChoices = {Colors.Rock, Colors.RockDark, Colors.RockLight}
    rock.Color = colorChoices[math.random(1, 3)]

    return rock
end

local function createSignpost(text: string): Model
    local sign = Instance.new("Model")
    sign.Name = "Signpost"

    local post = Instance.new("Part")
    post.Name = "Post"
    post.Size = Vector3.new(0.4, 5, 0.4)
    post.Position = Vector3.new(0, 2.5, 0)
    post.Anchored = true
    post.Material = Enum.Material.WoodPlanks
    post.Color = Colors.SignPost
    post.Parent = sign

    local board = Instance.new("Part")
    board.Name = "Board"
    board.Size = Vector3.new(3, 1.2, 0.2)
    board.Position = Vector3.new(0, 4.5, 0)
    board.Anchored = true
    board.Material = Enum.Material.WoodPlanks
    board.Color = Colors.SignBoard
    board.Parent = sign

    local surfaceGui = Instance.new("SurfaceGui")
    surfaceGui.Face = Enum.NormalId.Front
    surfaceGui.Parent = board

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(50, 35, 20)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = surfaceGui

    return sign
end

local function createTorch(): Model
    local torch = Instance.new("Model")
    torch.Name = "Torch"

    local post = Instance.new("Part")
    post.Name = "Post"
    post.Size = Vector3.new(0.3, 4, 0.3)
    post.Position = Vector3.new(0, 2, 0)
    post.Anchored = true
    post.Material = Enum.Material.WoodPlanks
    post.Color = Colors.TorchBase
    post.Parent = torch

    local head = Instance.new("Part")
    head.Name = "Head"
    head.Shape = Enum.PartType.Ball
    head.Size = Vector3.new(0.6, 0.6, 0.6)
    head.Position = Vector3.new(0, 4.2, 0)
    head.Anchored = true
    head.Material = Enum.Material.Neon
    head.Color = Color3.fromRGB(255, 180, 50)
    head.Parent = torch

    local light = Instance.new("PointLight")
    light.Brightness = 1.5
    light.Range = 20
    light.Color = Color3.fromRGB(255, 200, 100)
    light.Parent = head

    return torch
end

local function createBridge(length: number, width: number): Model
    local bridge = Instance.new("Model")
    bridge.Name = "StoneBridge"

    -- Deck (PrimaryPart — center at Y=0.5 so bottom sits at model origin Y)
    local deck = Instance.new("Part")
    deck.Name = "Deck"
    deck.Size = Vector3.new(width, 1, length)
    deck.CFrame = CFrame.new(0, 0.5, 0)
    deck.Anchored = true
    deck.Material = Enum.Material.Cobblestone
    deck.Color = Colors.BridgeStone
    deck.Parent = bridge
    bridge.PrimaryPart = deck

    -- Low stone railing walls
    for side = -1, 1, 2 do
        local railing = Instance.new("Part")
        railing.Name = "Railing"
        railing.Size = Vector3.new(0.6, 1.2, length)
        railing.Position = Vector3.new(side * (width / 2 - 0.3), 1.6, 0)
        railing.Anchored = true
        railing.Material = Enum.Material.Rock
        railing.Color = Colors.Rock
        railing.Parent = bridge

        -- Flat capstone on top of railing
        local cap = Instance.new("Part")
        cap.Name = "RailingCap"
        cap.Size = Vector3.new(0.9, 0.25, length + 0.4)
        cap.Position = Vector3.new(side * (width / 2 - 0.3), 2.35, 0)
        cap.Anchored = true
        cap.Material = Enum.Material.Cobblestone
        cap.Color = Colors.RockLight
        cap.Parent = bridge
    end

    -- Corner posts (decorative pillars at each end of each railing)
    for side = -1, 1, 2 do
        for endDir = -1, 1, 2 do
            local post = Instance.new("Part")
            post.Name = "Post"
            post.Shape = Enum.PartType.Block
            post.Size = Vector3.new(1.0, 2.2, 1.0)
            post.Position = Vector3.new(
                side * (width / 2 - 0.3),
                2.1,
                endDir * (length / 2 - 0.5)
            )
            post.Anchored = true
            post.Material = Enum.Material.Rock
            post.Color = Colors.RockDark
            post.Parent = bridge

            -- Post cap (slightly wider top)
            local postCap = Instance.new("Part")
            postCap.Name = "PostCap"
            postCap.Shape = Enum.PartType.Block
            postCap.Size = Vector3.new(1.3, 0.3, 1.3)
            postCap.Position = Vector3.new(
                side * (width / 2 - 0.3),
                3.35,
                endDir * (length / 2 - 0.5)
            )
            postCap.Anchored = true
            postCap.Material = Enum.Material.Cobblestone
            postCap.Color = Colors.RockLight
            postCap.Parent = bridge
        end
    end

    -- Support pillars (extend below deck into the riverbed)
    for zDir = -1, 1, 2 do
        local pillar = Instance.new("Part")
        pillar.Name = "Support"
        pillar.Size = Vector3.new(width * 0.5, 8, 2.5)
        pillar.Position = Vector3.new(0, -3.5, zDir * (length / 2 - 3))
        pillar.Anchored = true
        pillar.Material = Enum.Material.Rock
        pillar.Color = Colors.Rock
        pillar.Parent = bridge
    end

    -- Center keystone (wider support under middle of bridge)
    local keystone = Instance.new("Part")
    keystone.Name = "Keystone"
    keystone.Size = Vector3.new(width * 0.35, 6, 3)
    keystone.Position = Vector3.new(0, -2.5, 0)
    keystone.Anchored = true
    keystone.Material = Enum.Material.Rock
    keystone.Color = Colors.RockDark
    keystone.Parent = bridge

    return bridge
end

local function buildDecorations()
    print("[WorldBuilder] Pass 5: Placing rocks & decorations...")

    local rockConfig = OverworldConfig.Terrain.Rocks
    local rockCount = 0

    -- Rocks in safe zone
    for _ = 1, rockConfig.SafeCount do
        local sz = OverworldConfig.SafeZone
        local x = math.random(sz.MinX, sz.MaxX)
        local z = math.random(sz.MinZ, sz.MaxZ)
        if not isNearRoadOrRiver(x, z) then
            local size = 1 + math.random() * 2
            local rock = createRock(size)
            local embedDepth = size * rockConfig.EmbedPercent
            if placePartOnTerrain(x, z, rock, embedDepth) then
                rockCount += 1
            else
                rock:Destroy()
            end
        end
    end

    -- Rocks in wilderness
    for _ = 1, rockConfig.WildernessCount do
        local x = math.random(50, MAP_SIZE - 50)
        local z = math.random(50, MAP_SIZE - 50)
        if OverworldConfig.GetZone(x, z) == "wilderness" and not isNearRoadOrRiver(x, z) then
            local size = 1.5 + math.random() * 3
            local rock = createRock(size)
            local embedDepth = size * rockConfig.EmbedPercent
            if placePartOnTerrain(x, z, rock, embedDepth) then
                rockCount += 1
            else
                rock:Destroy()
            end
        end
    end

    -- Boulders in forbidden zone
    for _ = 1, rockConfig.ForbiddenCount do
        local fz = OverworldConfig.ForbiddenZone
        local x = math.random(fz.MinX, fz.MaxX)
        local z = math.random(fz.MinZ, fz.MaxZ)
        local size = 3 + math.random() * 8
        local rock = createRock(size)
        rock.Material = Enum.Material.Slate
        local embedDepth = size * rockConfig.EmbedPercent
        if placePartOnTerrain(x, z, rock, embedDepth) then
            rockCount += 1
        else
            rock:Destroy()
        end
    end

    task.wait()

    -- Signposts at road intersections
    local signposts = {
        {x = MAP_CENTER + 20, z = MAP_CENTER + 20, text = "Town Center"},
        {x = MAP_CENTER - 300, z = MAP_CENTER, text = "Western Wilds"},
        {x = MAP_CENTER + 300, z = MAP_CENTER, text = "Eastern Frontier"},
        {x = MAP_CENTER, z = MAP_CENTER - 300, text = "Southern Meadows"},
        {x = MAP_CENTER, z = MAP_CENTER + 300, text = "Northern Forest"},
        {x = 1500, z = 1500, text = "Forbidden Zone"},
        {x = 250, z = 1520, text = "Lake Shore"},
    }

    for _, data in signposts do
        local sign = createSignpost(data.text)
        placeOnTerrain(data.x, data.z, sign, 0.8)
    end

    -- Torches along safe zone roads
    local torchCount = 0
    local sz = OverworldConfig.SafeZone
    local torchSpacing = 40
    -- Along main E-W road in safe zone
    for x = sz.MinX, sz.MaxX, torchSpacing do
        for side = -1, 1, 2 do
            local torch = createTorch()
            local tz = MAP_CENTER + side * 10
            if placeOnTerrain(x, tz, torch, 0.3) then
                torchCount += 1
            else
                torch:Destroy()
            end
        end
    end
    -- Along main N-S road in safe zone
    for z = sz.MinZ, sz.MaxZ, torchSpacing do
        for side = -1, 1, 2 do
            local torch = createTorch()
            local tx = MAP_CENTER + side * 10
            if placeOnTerrain(tx, z, torch, 0.3) then
                torchCount += 1
            else
                torch:Destroy()
            end
        end
    end

    task.wait()

    -- ================================================================
    -- Stone bridges at every road-river crossing
    -- ================================================================
    -- River path (same points used in buildRiver)
    local riverPoints = {
        {x = 100, z = 1600}, {x = 300, z = 1400}, {x = 500, z = 1200},
        {x = 700, z = 1050}, {x = 900, z = 1000}, {x = 1100, z = 950},
        {x = 1300, z = 900}, {x = 1500, z = 850}, {x = 1700, z = 800},
        {x = 1900, z = 750},
    }

    -- Interpolate river Z at a given X
    local function getRiverZAtX(targetX: number): number?
        for ri = 1, #riverPoints - 1 do
            local p1 = riverPoints[ri]
            local p2 = riverPoints[ri + 1]
            if targetX >= p1.x and targetX <= p2.x then
                local t = (targetX - p1.x) / (p2.x - p1.x)
                return p1.z + t * (p2.z - p1.z)
            end
        end
        return nil
    end

    -- Interpolate river X at a given Z (river Z is monotonically decreasing)
    local function getRiverXAtZ(targetZ: number): number?
        for ri = 1, #riverPoints - 1 do
            local p1 = riverPoints[ri]
            local p2 = riverPoints[ri + 1]
            local minZ = math.min(p1.z, p2.z)
            local maxZ = math.max(p1.z, p2.z)
            if targetZ >= minZ and targetZ <= maxZ then
                local t = (targetZ - p1.z) / (p2.z - p1.z)
                return p1.x + t * (p2.x - p1.x)
            end
        end
        return nil
    end

    local mainWidth = OverworldConfig.Terrain.Roads.MainWidth
    local secWidth = OverworldConfig.Terrain.Roads.SecondaryWidth
    local roadSpacing = 200
    local bridgeLength = 44 -- spans 30-stud river + 7 stud margin each side
    local bridgeCount = 0

    -- Collect all road-river crossings: {x, z, isEW, roadW}
    local crossings = {}

    -- Main E-W road (z = MAP_CENTER) × river
    local ewCrossX = getRiverXAtZ(MAP_CENTER)
    if ewCrossX and ewCrossX >= 100 and ewCrossX <= MAP_SIZE - 100 then
        table.insert(crossings, {x = ewCrossX, z = MAP_CENTER, isEW = true, roadW = mainWidth})
    end

    -- Main N-S road (x = MAP_CENTER) × river
    local nsCrossZ = getRiverZAtX(MAP_CENTER)
    if nsCrossZ and nsCrossZ >= 100 and nsCrossZ <= MAP_SIZE - 100 then
        table.insert(crossings, {x = MAP_CENTER, z = nsCrossZ, isEW = false, roadW = mainWidth})
    end

    -- Secondary N-S roads (vertical, in safe zone) × river
    for roadX = sz.MinX, sz.MaxX, roadSpacing do
        if math.abs(roadX - MAP_CENTER) > 50 then
            local crossZ = getRiverZAtX(roadX)
            if crossZ and crossZ >= sz.MinZ and crossZ <= sz.MaxZ then
                table.insert(crossings, {x = roadX, z = crossZ, isEW = false, roadW = secWidth})
            end
        end
    end

    -- Secondary E-W roads (horizontal, in safe zone) × river
    for roadZ = sz.MinZ, sz.MaxZ, roadSpacing do
        if math.abs(roadZ - MAP_CENTER) > 50 then
            local crossX = getRiverXAtZ(roadZ)
            if crossX and crossX >= sz.MinX and crossX <= sz.MaxX then
                table.insert(crossings, {x = crossX, z = roadZ, isEW = true, roadW = secWidth})
            end
        end
    end

    -- Place a stone bridge at each crossing
    for _, cross in crossings do
        local bWidth = cross.roadW + 4 -- slightly wider than the road
        local bridge = createBridge(bridgeLength, bWidth)

        -- Position deck top near road surface level
        local surfaceY = getWorldHeight(cross.x, cross.z)
        local placeCF = CFrame.new(cross.x, surfaceY, cross.z)

        if cross.isEW then
            -- E-W road: rotate bridge 90° so deck spans along X
            placeCF = placeCF * CFrame.Angles(0, math.rad(90), 0)
        end

        bridge:PivotTo(placeCF)
        bridge.Parent = _propsFolder
        bridgeCount += 1
    end

    print(string.format("[WorldBuilder] Decorations complete (%d rocks, %d torches, %d bridges)", rockCount, torchCount, bridgeCount))
end

-- ============================================================================
-- PASS 6: BOUNDARY
-- ============================================================================

local function buildBoundary()
    print("[WorldBuilder] Pass 6: Building boundary walls...")

    local height = 80
    local thickness = 5

    local boundaries = {
        -- North
        {
            size = Vector3.new(MAP_SIZE + thickness * 2, height, thickness),
            position = Vector3.new(MAP_CENTER, height / 2, MAP_SIZE + thickness / 2),
        },
        -- South
        {
            size = Vector3.new(MAP_SIZE + thickness * 2, height, thickness),
            position = Vector3.new(MAP_CENTER, height / 2, -thickness / 2),
        },
        -- East
        {
            size = Vector3.new(thickness, height, MAP_SIZE + thickness * 2),
            position = Vector3.new(MAP_SIZE + thickness / 2, height / 2, MAP_CENTER),
        },
        -- West
        {
            size = Vector3.new(thickness, height, MAP_SIZE + thickness * 2),
            position = Vector3.new(-thickness / 2, height / 2, MAP_CENTER),
        },
    }

    for i, data in boundaries do
        local wall = Instance.new("Part")
        wall.Name = "Boundary" .. i
        wall.Size = data.size
        wall.Position = data.position
        wall.Anchored = true
        wall.Transparency = 1
        wall.CanCollide = true
        wall.Parent = _worldFolder
    end

    print("[WorldBuilder] Boundary walls complete")
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Builds the entire overworld environment.
]]
function WorldBuilder.Build()
    print("[WorldBuilder] Building overworld environment (2000x2000 voxel terrain)...")

    -- Get terrain reference
    _terrain = workspace:FindFirstChildOfClass("Terrain") :: Terrain
    if not _terrain then
        warn("[WorldBuilder] No Terrain object in workspace!")
        return
    end

    -- Clear any existing terrain
    _terrain:Clear()

    -- Create folder structure
    _worldFolder = Instance.new("Folder")
    _worldFolder.Name = "Overworld"
    _worldFolder.Parent = workspace

    _propsFolder = Instance.new("Folder")
    _propsFolder.Name = "Props"
    _propsFolder.Parent = _worldFolder

    _treesFolder = Instance.new("Folder")
    _treesFolder.Name = "Trees"
    _treesFolder.Parent = _worldFolder

    -- Build in 6 sequential passes
    buildHeightmap()
    buildRoads()
    buildRiver()
    buildTrees()
    buildDecorations()
    buildBoundary()

    print("[WorldBuilder] Overworld environment complete!")
end

--[[
    Destroys the overworld environment.
]]
function WorldBuilder.Destroy()
    if _worldFolder then
        _worldFolder:Destroy()
        _worldFolder = nil
    end
    if _terrain then
        _terrain:Clear()
    end
end

--[[
    Gets the world folder reference.
]]
function WorldBuilder.GetWorldFolder(): Folder?
    return _worldFolder
end

--[[
    Gets the props folder reference (for placing game objects on terrain).
]]
function WorldBuilder.GetPropsFolder(): Folder?
    return _propsFolder
end

--[[
    Flattens terrain in a square area for base placement.
    Fills with LeafyGrass at a consistent height.

    @param x number - Center X position
    @param z number - Center Z position
    @param size number - Square area size in studs
]]
function WorldBuilder.FlattenForBase(x: number, z: number, size: number)
    if not _terrain then return end

    -- Find average height at this position
    local targetHeight = getWorldHeight(x, z)

    local halfSize = size / 2
    local region = Region3.new(
        Vector3.new(x - halfSize, targetHeight - 2, z - halfSize),
        Vector3.new(x + halfSize, targetHeight + 10, z + halfSize)
    ):ExpandToGrid(VOXEL)

    -- Clear above
    _terrain:FillRegion(region, VOXEL, Enum.Material.Air)

    -- Fill flat surface
    local surfaceRegion = Region3.new(
        Vector3.new(x - halfSize, targetHeight - 4, z - halfSize),
        Vector3.new(x + halfSize, targetHeight, z + halfSize)
    ):ExpandToGrid(VOXEL)
    _terrain:FillRegion(surfaceRegion, VOXEL, Enum.Material.LeafyGrass)
end

return WorldBuilder
