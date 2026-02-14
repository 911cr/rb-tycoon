--!strict
--[[
    WorldBuilder.lua

    Builds the 3D terrain environment for the overworld.
    Creates terrain, roads, rivers, trees, and environmental decorations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)

local WorldBuilder = {}

-- ============================================================================
-- MATERIALS & COLORS
-- ============================================================================

local Materials = {
    Grass = Enum.Material.Grass,
    Cobblestone = Enum.Material.Cobblestone,
    Dirt = Enum.Material.Ground,
    Water = Enum.Material.Water,
    Rock = Enum.Material.Rock,
    Wood = Enum.Material.WoodPlanks,
    WoodLog = Enum.Material.Wood,
    Sand = Enum.Material.Sand,
}

local Colors = {
    Grass = Color3.fromRGB(80, 140, 50),
    GrassDark = Color3.fromRGB(60, 110, 40),
    Road = Color3.fromRGB(140, 130, 120),
    RoadDark = Color3.fromRGB(110, 105, 95),
    Dirt = Color3.fromRGB(115, 85, 55),
    Water = Color3.fromRGB(80, 120, 180),
    Rock = Color3.fromRGB(100, 100, 105),
    TreeTrunk = Color3.fromRGB(85, 60, 40),
    TreeLeaves = Color3.fromRGB(60, 120, 45),
    TreeLeavesDark = Color3.fromRGB(45, 90, 35),
    Sand = Color3.fromRGB(200, 180, 140),
}

-- ============================================================================
-- FOLDER REFERENCES
-- ============================================================================

local _worldFolder: Folder
local _terrainFolder: Folder
local _roadsFolder: Folder
local _treesFolder: Folder
local _decorationsFolder: Folder
local _waterFolder: Folder

-- ============================================================================
-- GROUND TERRAIN
-- ============================================================================

--[[
    Creates the base ground terrain for the entire map.
]]
local function createGroundTerrain()
    local mapConfig = OverworldConfig.Map

    -- Main grass ground
    local ground = Instance.new("Part")
    ground.Name = "MainGround"
    ground.Size = Vector3.new(mapConfig.Width, 4, mapConfig.Height)
    ground.Position = Vector3.new(mapConfig.CenterX, -2, mapConfig.CenterZ)
    ground.Anchored = true
    ground.Material = Materials.Grass
    ground.Color = Colors.Grass
    ground.Parent = _terrainFolder

    -- Add subtle terrain variation with grass patches
    local numPatches = 80
    for i = 1, numPatches do
        local patch = Instance.new("Part")
        patch.Name = "GrassPatch"
        patch.Size = Vector3.new(
            30 + math.random() * 50,
            0.1,
            30 + math.random() * 50
        )
        patch.Position = Vector3.new(
            math.random(50, mapConfig.Width - 50),
            0.05,
            math.random(50, mapConfig.Height - 50)
        )
        patch.Anchored = true
        patch.Material = Materials.Grass
        patch.Color = math.random() > 0.5 and Colors.GrassDark or Colors.Grass
        patch.Parent = _terrainFolder
    end

    -- Add some hills for terrain variation
    local hillPositions = {
        {x = 150, z = 150, height = 12, radius = 60},
        {x = 850, z = 200, height = 15, radius = 70},
        {x = 200, z = 800, height = 10, radius = 50},
        {x = 750, z = 750, height = 18, radius = 80},
        {x = 500, z = 100, height = 8, radius = 45},
        {x = 100, z = 500, height = 10, radius = 55},
        {x = 900, z = 500, height = 12, radius = 60},
    }

    for _, hillData in hillPositions do
        local hill = Instance.new("Part")
        hill.Name = "Hill"
        hill.Size = Vector3.new(hillData.radius * 2, hillData.height, hillData.radius * 2)
        hill.Position = Vector3.new(hillData.x, hillData.height / 2 - 2, hillData.z)
        hill.Anchored = true
        hill.Material = Materials.Grass
        hill.Color = Colors.Grass
        hill.Shape = Enum.PartType.Ball
        hill.Parent = _terrainFolder

        -- Flatten bottom of hill
        local flatTop = Instance.new("Part")
        flatTop.Name = "HillTop"
        flatTop.Size = Vector3.new(hillData.radius * 1.8, 0.5, hillData.radius * 1.8)
        flatTop.Position = Vector3.new(hillData.x, hillData.height - 2, hillData.z)
        flatTop.Anchored = true
        flatTop.Material = Materials.Grass
        flatTop.Color = Colors.GrassDark
        flatTop.Parent = _terrainFolder
    end
end

-- ============================================================================
-- ROAD NETWORK
-- ============================================================================

--[[
    Creates a road segment between two points.
]]
local function createRoadSegment(startPos: Vector3, endPos: Vector3, width: number): Model
    local road = Instance.new("Model")
    road.Name = "RoadSegment"

    local direction = (endPos - startPos).Unit
    local length = (endPos - startPos).Magnitude
    local midPoint = startPos + direction * (length / 2)

    -- Road base
    local roadBase = Instance.new("Part")
    roadBase.Name = "RoadBase"
    roadBase.Size = Vector3.new(width, 0.3, length)
    roadBase.CFrame = CFrame.new(midPoint + Vector3.new(0, 0.15, 0), endPos)
    roadBase.Anchored = true
    roadBase.Material = Materials.Cobblestone
    roadBase.Color = Colors.Road
    roadBase.Parent = road

    -- Add road markings/stones for detail
    local numStones = math.floor(length / 8)
    for i = 0, numStones do
        local stonePos = startPos + direction * (i * (length / numStones))
        local stone = Instance.new("Part")
        stone.Name = "RoadStone"
        stone.Size = Vector3.new(
            width * 0.8,
            0.05,
            2
        )
        stone.Position = Vector3.new(stonePos.X, 0.32, stonePos.Z)
        stone.Anchored = true
        stone.Material = Materials.Cobblestone
        stone.Color = Colors.RoadDark
        stone.Parent = road
    end

    -- Edge stones
    for side = -1, 1, 2 do
        local edgeOffset = (width / 2 - 0.3) * side

        for i = 0, math.floor(length / 3) do
            local stonePos = startPos + direction * (i * 3)
            local edgeStone = Instance.new("Part")
            edgeStone.Name = "EdgeStone"
            edgeStone.Size = Vector3.new(0.5, 0.3, 1)

            local perpendicular = Vector3.new(-direction.Z, 0, direction.X)
            edgeStone.Position = stonePos + perpendicular * edgeOffset + Vector3.new(0, 0.2, 0)
            edgeStone.Anchored = true
            edgeStone.Material = Materials.Rock
            edgeStone.Color = Colors.Rock
            edgeStone.Parent = road
        end
    end

    road.Parent = _roadsFolder
    return road
end

--[[
    Creates the main road network across the map.
]]
local function createRoadNetwork()
    local roadConfig = OverworldConfig.Zones.Roads
    local mapConfig = OverworldConfig.Map

    -- Main crossroads in center
    local centerX = mapConfig.CenterX
    local centerZ = mapConfig.CenterZ

    -- Main horizontal road (east-west)
    createRoadSegment(
        Vector3.new(50, 0, centerZ),
        Vector3.new(mapConfig.Width - 50, 0, centerZ),
        roadConfig.MainRoadWidth
    )

    -- Main vertical road (north-south)
    createRoadSegment(
        Vector3.new(centerX, 0, 50),
        Vector3.new(centerX, 0, mapConfig.Height - 50),
        roadConfig.MainRoadWidth
    )

    -- Secondary roads (grid pattern)
    local sideRoadSpacing = 250

    -- Horizontal side roads
    for z = sideRoadSpacing, mapConfig.Height - sideRoadSpacing, sideRoadSpacing do
        if math.abs(z - centerZ) > 50 then -- Skip if too close to main road
            createRoadSegment(
                Vector3.new(100, 0, z),
                Vector3.new(mapConfig.Width - 100, 0, z),
                roadConfig.SideRoadWidth
            )
        end
    end

    -- Vertical side roads
    for x = sideRoadSpacing, mapConfig.Width - sideRoadSpacing, sideRoadSpacing do
        if math.abs(x - centerX) > 50 then
            createRoadSegment(
                Vector3.new(x, 0, 100),
                Vector3.new(x, 0, mapConfig.Height - 100),
                roadConfig.SideRoadWidth
            )
        end
    end

    -- Diagonal roads for variety
    createRoadSegment(
        Vector3.new(100, 0, 100),
        Vector3.new(400, 0, 400),
        roadConfig.SideRoadWidth
    )

    createRoadSegment(
        Vector3.new(mapConfig.Width - 100, 0, 100),
        Vector3.new(mapConfig.Width - 400, 0, 400),
        roadConfig.SideRoadWidth
    )
end

-- ============================================================================
-- RIVER SYSTEM
-- ============================================================================

--[[
    Creates a river segment.
]]
local function createRiverSegment(startPos: Vector3, endPos: Vector3, width: number): Model
    local river = Instance.new("Model")
    river.Name = "RiverSegment"

    local direction = (endPos - startPos).Unit
    local length = (endPos - startPos).Magnitude
    local midPoint = startPos + direction * (length / 2)

    -- River bed (darker ground)
    local riverBed = Instance.new("Part")
    riverBed.Name = "RiverBed"
    riverBed.Size = Vector3.new(width + 4, 0.5, length + 4)
    riverBed.CFrame = CFrame.new(midPoint + Vector3.new(0, -2.5, 0), endPos)
    riverBed.Anchored = true
    riverBed.Material = Materials.Sand
    riverBed.Color = Colors.Sand
    riverBed.Parent = river

    -- Water surface
    local water = Instance.new("Part")
    water.Name = "Water"
    water.Size = Vector3.new(width, 3, length)
    water.CFrame = CFrame.new(midPoint + Vector3.new(0, -1, 0), endPos)
    water.Anchored = true
    water.Material = Materials.Water
    water.Color = Colors.Water
    water.Transparency = OverworldConfig.Zones.River.Transparency
    water.Parent = river

    -- Bank edges
    for side = -1, 1, 2 do
        local bankOffset = (width / 2 + 1) * side
        local perpendicular = Vector3.new(-direction.Z, 0, direction.X)

        local bank = Instance.new("Part")
        bank.Name = "RiverBank"
        bank.Size = Vector3.new(2, 1, length)
        bank.CFrame = CFrame.new(midPoint + perpendicular * bankOffset + Vector3.new(0, 0, 0), endPos)
        bank.Anchored = true
        bank.Material = Materials.Dirt
        bank.Color = Colors.Dirt
        bank.Parent = river
    end

    river.Parent = _waterFolder
    return river
end

--[[
    Creates the river flowing through the map.
]]
local function createRiver()
    local riverConfig = OverworldConfig.Zones.River
    local mapConfig = OverworldConfig.Map

    -- Winding river from west to east
    local riverPoints = {
        Vector3.new(0, 0, 300),
        Vector3.new(200, 0, 350),
        Vector3.new(400, 0, 280),
        Vector3.new(600, 0, 320),
        Vector3.new(800, 0, 250),
        Vector3.new(1000, 0, 300),
    }

    for i = 1, #riverPoints - 1 do
        createRiverSegment(riverPoints[i], riverPoints[i + 1], riverConfig.Width)
    end

    -- Secondary stream
    local streamPoints = {
        Vector3.new(500, 0, 0),
        Vector3.new(480, 0, 150),
        Vector3.new(520, 0, 280), -- Joins main river
    }

    for i = 1, #streamPoints - 1 do
        createRiverSegment(streamPoints[i], streamPoints[i + 1], riverConfig.Width * 0.5)
    end

    -- Add bridges over main road intersections
    local bridgePositions = {
        Vector3.new(500, 0, 305), -- Main crossroads
    }

    for _, pos in bridgePositions do
        local bridge = Instance.new("Model")
        bridge.Name = "Bridge"

        -- Bridge deck
        local deck = Instance.new("Part")
        deck.Name = "Deck"
        deck.Size = Vector3.new(18, 1, riverConfig.Width + 6)
        deck.Position = pos + Vector3.new(0, 1, 0)
        deck.Anchored = true
        deck.Material = Materials.Cobblestone
        deck.Color = Colors.Road
        deck.Parent = bridge

        -- Bridge railings
        for side = -1, 1, 2 do
            local railing = Instance.new("Part")
            railing.Name = "Railing"
            railing.Size = Vector3.new(0.5, 1.5, riverConfig.Width + 4)
            railing.Position = pos + Vector3.new(side * 8.5, 2.25, 0)
            railing.Anchored = true
            railing.Material = Materials.Rock
            railing.Color = Colors.Rock
            railing.Parent = bridge
        end

        -- Bridge supports
        for z = -1, 1, 2 do
            local support = Instance.new("Part")
            support.Name = "Support"
            support.Size = Vector3.new(3, 5, 2)
            support.Position = pos + Vector3.new(0, -1.5, z * (riverConfig.Width / 2 + 1))
            support.Anchored = true
            support.Material = Materials.Rock
            support.Color = Colors.Rock
            support.Parent = bridge
        end

        bridge.Parent = _waterFolder
    end
end

-- ============================================================================
-- TREES AND VEGETATION
-- ============================================================================

--[[
    Creates a tree at the specified position.
]]
local function createTree(position: Vector3, variation: number): Model
    local tree = Instance.new("Model")
    tree.Name = "Tree"

    local trunkHeight = 6 + variation * 2 + math.random() * 2
    local foliageRadius = 3 + variation * 0.5

    -- Trunk
    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Size = Vector3.new(1 + variation * 0.2, trunkHeight, 1 + variation * 0.2)
    trunk.Position = position + Vector3.new(0, trunkHeight / 2, 0)
    trunk.Anchored = true
    trunk.Material = Materials.WoodLog
    trunk.Color = Colors.TreeTrunk
    trunk.Shape = Enum.PartType.Cylinder
    trunk.Orientation = Vector3.new(0, 0, 90)
    trunk.Parent = tree

    -- Foliage layers
    local trunkTop = position.Y + trunkHeight
    local numLayers = 2 + variation

    for layer = 1, numLayers do
        local layerRadius = foliageRadius * (1 - (layer - 1) / (numLayers + 1))
        local layerHeight = trunkTop + (layer - 0.5) * 1.5

        local foliage = Instance.new("Part")
        foliage.Name = "Foliage"
        foliage.Size = Vector3.new(layerRadius * 2, 2.5, layerRadius * 2)
        foliage.Position = Vector3.new(position.X, layerHeight, position.Z)
        foliage.Anchored = true
        foliage.Material = Materials.Grass
        foliage.Color = layer % 2 == 0 and Colors.TreeLeavesDark or Colors.TreeLeaves
        foliage.Shape = Enum.PartType.Ball
        foliage.Parent = tree
    end

    tree.Parent = _treesFolder
    return tree
end

--[[
    Creates forests across the map.
]]
local function createForests()
    local mapConfig = OverworldConfig.Map
    local forestConfig = OverworldConfig.Zones.Forest

    -- Forest regions (avoid roads and river areas)
    local forestRegions = {
        {minX = 50, maxX = 200, minZ = 50, maxZ = 200},
        {minX = 800, maxX = 950, minZ = 50, maxZ = 200},
        {minX = 50, maxX = 200, minZ = 400, maxZ = 600},
        {minX = 800, maxX = 950, minZ = 400, maxZ = 600},
        {minX = 50, maxX = 200, minZ = 700, maxZ = 950},
        {minX = 800, maxX = 950, minZ = 700, maxZ = 950},
        {minX = 300, maxX = 450, minZ = 600, maxZ = 750},
        {minX = 550, maxX = 700, minZ = 600, maxZ = 750},
    }

    for _, region in forestRegions do
        local areaWidth = region.maxX - region.minX
        local areaDepth = region.maxZ - region.minZ
        local numTrees = math.floor((areaWidth * areaDepth / 100) * forestConfig.TreeDensity)

        for i = 1, numTrees do
            local x = region.minX + math.random() * areaWidth
            local z = region.minZ + math.random() * areaDepth
            local variation = math.random(0, forestConfig.TreeVariation)

            createTree(Vector3.new(x, 0, z), variation)
        end
    end

    -- Scattered trees near roads
    local scatteredCount = 50
    for i = 1, scatteredCount do
        local x = math.random(50, mapConfig.Width - 50)
        local z = math.random(50, mapConfig.Height - 50)

        -- Avoid center crossroads area
        local centerX = mapConfig.CenterX
        local centerZ = mapConfig.CenterZ
        local distFromCenter = math.sqrt((x - centerX)^2 + (z - centerZ)^2)

        if distFromCenter > 100 then
            local variation = math.random(0, 2)
            createTree(Vector3.new(x, 0, z), variation)
        end
    end
end

-- ============================================================================
-- DECORATIONS
-- ============================================================================

--[[
    Creates a rock formation.
]]
local function createRock(position: Vector3, size: number): Part
    local rock = Instance.new("Part")
    rock.Name = "Rock"
    rock.Size = Vector3.new(size, size * 0.6, size * 0.8)
    rock.Position = position + Vector3.new(0, size * 0.3, 0)
    rock.Orientation = Vector3.new(math.random(-10, 10), math.random(0, 360), math.random(-10, 10))
    rock.Anchored = true
    rock.Material = Materials.Rock
    rock.Color = Color3.fromRGB(
        Colors.Rock.R * 255 + math.random(-15, 15),
        Colors.Rock.G * 255 + math.random(-15, 15),
        Colors.Rock.B * 255 + math.random(-15, 15)
    )
    rock.Parent = _decorationsFolder
    return rock
end

--[[
    Creates a signpost.
]]
local function createSignpost(position: Vector3, text: string): Model
    local sign = Instance.new("Model")
    sign.Name = "Signpost"

    -- Post
    local post = Instance.new("Part")
    post.Name = "Post"
    post.Size = Vector3.new(0.4, 5, 0.4)
    post.Position = position + Vector3.new(0, 2.5, 0)
    post.Anchored = true
    post.Material = Materials.Wood
    post.Color = Colors.TreeTrunk
    post.Parent = sign

    -- Sign board
    local board = Instance.new("Part")
    board.Name = "Board"
    board.Size = Vector3.new(3, 1.2, 0.2)
    board.Position = position + Vector3.new(0, 4.5, 0)
    board.Anchored = true
    board.Material = Materials.Wood
    board.Color = Color3.fromRGB(120, 90, 60)
    board.Parent = sign

    -- Sign text
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

    sign.Parent = _decorationsFolder
    return sign
end

--[[
    Creates all decorations across the map.
]]
local function createDecorations()
    local mapConfig = OverworldConfig.Map

    -- Scatter rocks
    local numRocks = 60
    for i = 1, numRocks do
        local x = math.random(50, mapConfig.Width - 50)
        local z = math.random(50, mapConfig.Height - 50)
        local size = 1 + math.random() * 2
        createRock(Vector3.new(x, 0, z), size)
    end

    -- Signposts at road intersections
    local signposts = {
        {pos = Vector3.new(520, 0, 520), text = "Town Center"},
        {pos = Vector3.new(270, 0, 520), text = "Western Realm"},
        {pos = Vector3.new(770, 0, 520), text = "Eastern Realm"},
        {pos = Vector3.new(520, 0, 270), text = "Southern Fields"},
        {pos = Vector3.new(520, 0, 770), text = "Northern Woods"},
    }

    for _, signData in signposts do
        createSignpost(signData.pos, signData.text)
    end
end

-- ============================================================================
-- MAP BOUNDARY
-- ============================================================================

--[[
    Creates invisible boundary walls to keep players on the map.
]]
local function createBoundary()
    local mapConfig = OverworldConfig.Map
    local height = 50
    local thickness = 5

    local boundaries = {
        -- North
        {
            size = Vector3.new(mapConfig.Width, height, thickness),
            position = Vector3.new(mapConfig.CenterX, height / 2, mapConfig.Height + thickness / 2),
        },
        -- South
        {
            size = Vector3.new(mapConfig.Width, height, thickness),
            position = Vector3.new(mapConfig.CenterX, height / 2, -thickness / 2),
        },
        -- East
        {
            size = Vector3.new(thickness, height, mapConfig.Height),
            position = Vector3.new(mapConfig.Width + thickness / 2, height / 2, mapConfig.CenterZ),
        },
        -- West
        {
            size = Vector3.new(thickness, height, mapConfig.Height),
            position = Vector3.new(-thickness / 2, height / 2, mapConfig.CenterZ),
        },
    }

    for i, boundaryData in boundaries do
        local wall = Instance.new("Part")
        wall.Name = "Boundary" .. i
        wall.Size = boundaryData.size
        wall.Position = boundaryData.position
        wall.Anchored = true
        wall.Transparency = 1
        wall.CanCollide = true
        wall.Parent = _terrainFolder
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Builds the entire overworld environment.
]]
function WorldBuilder.Build()
    print("[WorldBuilder] Building overworld environment...")

    -- Create folder structure
    _worldFolder = Instance.new("Folder")
    _worldFolder.Name = "Overworld"
    _worldFolder.Parent = workspace

    _terrainFolder = Instance.new("Folder")
    _terrainFolder.Name = "Terrain"
    _terrainFolder.Parent = _worldFolder

    _roadsFolder = Instance.new("Folder")
    _roadsFolder.Name = "Roads"
    _roadsFolder.Parent = _worldFolder

    _treesFolder = Instance.new("Folder")
    _treesFolder.Name = "Trees"
    _treesFolder.Parent = _worldFolder

    _decorationsFolder = Instance.new("Folder")
    _decorationsFolder.Name = "Decorations"
    _decorationsFolder.Parent = _worldFolder

    _waterFolder = Instance.new("Folder")
    _waterFolder.Name = "Water"
    _waterFolder.Parent = _worldFolder

    -- Build components
    createGroundTerrain()
    print("[WorldBuilder] Ground terrain created")

    createRoadNetwork()
    print("[WorldBuilder] Road network created")

    createRiver()
    print("[WorldBuilder] River system created")

    createForests()
    print("[WorldBuilder] Forests created")

    createDecorations()
    print("[WorldBuilder] Decorations created")

    createBoundary()
    print("[WorldBuilder] Boundary walls created")

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
end

--[[
    Gets the world folder reference.
]]
function WorldBuilder.GetWorldFolder(): Folder?
    return _worldFolder
end

return WorldBuilder
