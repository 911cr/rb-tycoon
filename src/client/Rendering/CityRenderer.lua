--!strict
--[[
    CityRenderer.lua

    Renders the player's city with detailed 3D building models.
    Fantasy-Medieval themed with proper materials and textures.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local CityRenderer = {}
CityRenderer.__index = CityRenderer

-- Events
CityRenderer.BuildingClicked = Signal.new()
CityRenderer.GridCellClicked = Signal.new()

-- Private state
local _initialized = false
local _player = Players.LocalPlayer

-- Rendering containers
local _cityFolder: Folder
local _buildingsFolder: Folder
local _gridFolder: Folder
local _effectsFolder: Folder
local _environmentFolder: Folder

-- Building instances by ID
local _buildingModels: {[string]: Model} = {}

-- Grid settings
local GRID_SIZE = 40
local CELL_SIZE = 3 -- studs per cell
local GRID_HEIGHT = 0.05

-- Placement preview
local _placementPreview: Model? = nil
local _placementValid = true

-- Selection highlight
local _selectionHighlight: SelectionBox? = nil
local _selectedBuildingId: string? = nil

-- Material palettes for Fantasy-Medieval theme
local Materials = {
    Stone = Enum.Material.Cobblestone,
    StoneBrick = Enum.Material.Brick,
    Wood = Enum.Material.WoodPlanks,
    WoodLog = Enum.Material.Wood,
    Metal = Enum.Material.DiamondPlate,
    Slate = Enum.Material.Slate,
    Thatch = Enum.Material.Grass,
    Gold = Enum.Material.Foil,
    Crystal = Enum.Material.Glass,
    Dirt = Enum.Material.Ground,
}

-- Color palettes for building types
local BuildingPalettes = {
    townhall = {
        primary = Color3.fromRGB(139, 119, 101),    -- Stone gray-brown
        secondary = Color3.fromRGB(64, 64, 64),     -- Dark stone
        accent = Color3.fromRGB(184, 134, 11),      -- Royal gold
        roof = Color3.fromRGB(120, 81, 169),        -- Royal purple
        trim = Color3.fromRGB(218, 165, 32),        -- Gold trim
    },
    resource = {
        primary = Color3.fromRGB(139, 90, 43),      -- Rich brown
        secondary = Color3.fromRGB(101, 67, 33),    -- Darker brown
        accent = Color3.fromRGB(184, 134, 11),      -- Gold
        roof = Color3.fromRGB(85, 55, 26),          -- Dark wood
        trim = Color3.fromRGB(60, 40, 20),          -- Wood trim
    },
    storage = {
        primary = Color3.fromRGB(169, 169, 169),    -- Silver gray
        secondary = Color3.fromRGB(105, 105, 105),  -- Darker gray
        accent = Color3.fromRGB(255, 215, 0),       -- Gold
        roof = Color3.fromRGB(72, 61, 139),         -- Dark slate blue
        trim = Color3.fromRGB(192, 192, 192),       -- Silver
    },
    defense = {
        primary = Color3.fromRGB(128, 128, 128),    -- Stone gray
        secondary = Color3.fromRGB(64, 64, 64),     -- Dark stone
        accent = Color3.fromRGB(139, 0, 0),         -- Dark red
        roof = Color3.fromRGB(47, 79, 79),          -- Dark slate
        trim = Color3.fromRGB(70, 70, 70),          -- Metal
    },
    military = {
        primary = Color3.fromRGB(139, 69, 19),      -- Saddle brown
        secondary = Color3.fromRGB(85, 55, 26),     -- Dark brown
        accent = Color3.fromRGB(178, 34, 34),       -- Firebrick red
        roof = Color3.fromRGB(60, 40, 20),          -- Dark roof
        trim = Color3.fromRGB(139, 0, 0),           -- Military red
    },
    wall = {
        primary = Color3.fromRGB(128, 128, 128),    -- Stone gray
        secondary = Color3.fromRGB(105, 105, 105),  -- Darker stone
        accent = Color3.fromRGB(70, 70, 70),        -- Dark accent
    },
    core = {
        primary = Color3.fromRGB(139, 119, 101),    -- Stone
        secondary = Color3.fromRGB(64, 64, 64),     -- Dark stone
        accent = Color3.fromRGB(184, 134, 11),      -- Royal gold
        roof = Color3.fromRGB(120, 81, 169),        -- Royal purple
        trim = Color3.fromRGB(218, 165, 32),        -- Gold trim
    },
}

--[[
    Creates a stone foundation for buildings.
]]
local function createFoundation(parent: Model, sizeX: number, sizeZ: number, palette: any): Part
    local foundation = Instance.new("Part")
    foundation.Name = "Foundation"
    foundation.Size = Vector3.new(sizeX * CELL_SIZE - 0.1, 0.4, sizeZ * CELL_SIZE - 0.1)
    foundation.Position = Vector3.new(0, 0.2, 0)
    foundation.Anchored = true
    foundation.CanCollide = true
    foundation.Material = Materials.StoneBrick
    foundation.Color = palette.secondary
    foundation.Parent = parent
    return foundation
end

--[[
    Creates castle/tower style building (TownHall, DefenseTowers).
]]
local function createCastleBuilding(parent: Model, sizeX: number, sizeZ: number, level: number, palette: any): Part
    local height = 3 + level * 0.8
    local baseSize = math.min(sizeX, sizeZ) * CELL_SIZE - 0.3

    -- Main tower body
    local mainBody = Instance.new("Part")
    mainBody.Name = "MainBody"
    mainBody.Size = Vector3.new(baseSize * 0.9, height, baseSize * 0.9)
    mainBody.Position = Vector3.new(0, 0.4 + height / 2, 0)
    mainBody.Anchored = true
    mainBody.Material = Materials.StoneBrick
    mainBody.Color = palette.primary
    mainBody.Parent = parent

    -- Stone base ring
    local baseRing = Instance.new("Part")
    baseRing.Name = "BaseRing"
    baseRing.Size = Vector3.new(baseSize, 0.5, baseSize)
    baseRing.Position = Vector3.new(0, 0.65, 0)
    baseRing.Anchored = true
    baseRing.Material = Materials.Stone
    baseRing.Color = palette.secondary
    baseRing.Parent = parent

    -- Battlements (crenellations on top)
    local battlementSize = 0.4
    local numBattlements = math.floor(baseSize / battlementSize) - 1
    for i = 1, 4 do
        for j = 1, math.floor(numBattlements / 2) do
            local battlement = Instance.new("Part")
            battlement.Name = "Battlement"
            battlement.Size = Vector3.new(battlementSize, 0.6, battlementSize)
            battlement.Anchored = true
            battlement.Material = Materials.Stone
            battlement.Color = palette.secondary

            local offset = (j - 1) * battlementSize * 2 - baseSize * 0.9 / 2 + battlementSize
            if i == 1 then
                battlement.Position = Vector3.new(offset, 0.4 + height + 0.3, baseSize * 0.9 / 2 - battlementSize / 2)
            elseif i == 2 then
                battlement.Position = Vector3.new(offset, 0.4 + height + 0.3, -baseSize * 0.9 / 2 + battlementSize / 2)
            elseif i == 3 then
                battlement.Position = Vector3.new(baseSize * 0.9 / 2 - battlementSize / 2, 0.4 + height + 0.3, offset)
            else
                battlement.Position = Vector3.new(-baseSize * 0.9 / 2 + battlementSize / 2, 0.4 + height + 0.3, offset)
            end
            battlement.Parent = parent
        end
    end

    -- Central spire/tower
    local spireHeight = height * 0.5
    local spire = Instance.new("Part")
    spire.Name = "Spire"
    spire.Size = Vector3.new(baseSize * 0.3, spireHeight, baseSize * 0.3)
    spire.Position = Vector3.new(0, 0.4 + height + spireHeight / 2, 0)
    spire.Anchored = true
    spire.Material = Materials.Stone
    spire.Color = palette.primary
    spire.Parent = parent

    -- Roof cone for spire
    local roofCone = Instance.new("WedgePart")
    roofCone.Name = "RoofCone"
    roofCone.Size = Vector3.new(baseSize * 0.4, spireHeight * 0.6, baseSize * 0.4)
    roofCone.Position = Vector3.new(0, 0.4 + height + spireHeight + spireHeight * 0.3, 0)
    roofCone.Anchored = true
    roofCone.Material = Materials.Slate
    roofCone.Color = palette.roof
    roofCone.Orientation = Vector3.new(0, 45, 0)
    roofCone.Parent = parent

    -- Gold accent trim
    local trimRing = Instance.new("Part")
    trimRing.Name = "TrimRing"
    trimRing.Size = Vector3.new(baseSize * 0.95, 0.15, baseSize * 0.95)
    trimRing.Position = Vector3.new(0, 0.4 + height * 0.6, 0)
    trimRing.Anchored = true
    trimRing.Material = Materials.Metal
    trimRing.Color = palette.accent
    trimRing.Parent = parent

    -- Door
    local door = Instance.new("Part")
    door.Name = "Door"
    door.Size = Vector3.new(baseSize * 0.25, height * 0.4, 0.15)
    door.Position = Vector3.new(0, 0.4 + height * 0.2, baseSize * 0.45)
    door.Anchored = true
    door.Material = Materials.Wood
    door.Color = Color3.fromRGB(101, 67, 33)
    door.Parent = parent

    -- Windows (arched style)
    for side = 1, 4 do
        local window = Instance.new("Part")
        window.Name = "Window"
        window.Size = Vector3.new(0.1, 0.8, 0.5)
        window.Anchored = true
        window.Material = Materials.Crystal
        window.Color = Color3.fromRGB(135, 206, 250)
        window.Transparency = 0.3

        if side == 1 then
            window.Size = Vector3.new(0.5, 0.8, 0.1)
            window.Position = Vector3.new(baseSize * 0.25, 0.4 + height * 0.65, baseSize * 0.45)
        elseif side == 2 then
            window.Size = Vector3.new(0.5, 0.8, 0.1)
            window.Position = Vector3.new(-baseSize * 0.25, 0.4 + height * 0.65, baseSize * 0.45)
        elseif side == 3 then
            window.Position = Vector3.new(baseSize * 0.45, 0.4 + height * 0.65, 0)
        else
            window.Position = Vector3.new(-baseSize * 0.45, 0.4 + height * 0.65, 0)
        end
        window.Parent = parent
    end

    return mainBody
end

--[[
    Creates mine-style building (GoldMine).
]]
local function createMineBuilding(parent: Model, sizeX: number, sizeZ: number, level: number, palette: any): Part
    local baseSize = math.min(sizeX, sizeZ) * CELL_SIZE - 0.3

    -- Mine entrance structure
    local entranceFrame = Instance.new("Part")
    entranceFrame.Name = "EntranceFrame"
    entranceFrame.Size = Vector3.new(baseSize * 0.6, 2.5, 0.3)
    entranceFrame.Position = Vector3.new(0, 1.65, baseSize * 0.35)
    entranceFrame.Anchored = true
    entranceFrame.Material = Materials.WoodLog
    entranceFrame.Color = Color3.fromRGB(101, 67, 33)
    entranceFrame.Parent = parent

    -- Dark entrance hole
    local entranceHole = Instance.new("Part")
    entranceHole.Name = "EntranceHole"
    entranceHole.Size = Vector3.new(baseSize * 0.5, 2, 1)
    entranceHole.Position = Vector3.new(0, 1.4, baseSize * 0.3)
    entranceHole.Anchored = true
    entranceHole.Material = Enum.Material.SmoothPlastic
    entranceHole.Color = Color3.fromRGB(20, 15, 10)
    entranceHole.Parent = parent

    -- Wooden support beams
    for i = -1, 1, 2 do
        local beam = Instance.new("Part")
        beam.Name = "SupportBeam"
        beam.Size = Vector3.new(0.3, 3, 0.3)
        beam.Position = Vector3.new(i * baseSize * 0.28, 1.9, baseSize * 0.35)
        beam.Anchored = true
        beam.Material = Materials.WoodLog
        beam.Color = Color3.fromRGB(101, 67, 33)
        beam.Parent = parent
    end

    -- Top beam
    local topBeam = Instance.new("Part")
    topBeam.Name = "TopBeam"
    topBeam.Size = Vector3.new(baseSize * 0.7, 0.3, 0.3)
    topBeam.Position = Vector3.new(0, 3.25, baseSize * 0.35)
    topBeam.Anchored = true
    topBeam.Material = Materials.WoodLog
    topBeam.Color = Color3.fromRGB(101, 67, 33)
    topBeam.Parent = parent

    -- Mining cart track
    local track = Instance.new("Part")
    track.Name = "Track"
    track.Size = Vector3.new(0.8, 0.1, baseSize * 0.6)
    track.Position = Vector3.new(0, 0.45, 0)
    track.Anchored = true
    track.Material = Materials.Metal
    track.Color = Color3.fromRGB(80, 80, 80)
    track.Parent = parent

    -- Mining cart
    local cart = Instance.new("Part")
    cart.Name = "Cart"
    cart.Size = Vector3.new(0.6, 0.4, 0.8)
    cart.Position = Vector3.new(0, 0.7, -baseSize * 0.15)
    cart.Anchored = true
    cart.Material = Materials.Metal
    cart.Color = Color3.fromRGB(60, 60, 60)
    cart.Parent = parent

    -- Gold ore in cart (shows production)
    local goldOre = Instance.new("Part")
    goldOre.Name = "GoldOre"
    goldOre.Size = Vector3.new(0.5, 0.25, 0.6)
    goldOre.Position = Vector3.new(0, 0.95, -baseSize * 0.15)
    goldOre.Anchored = true
    goldOre.Material = Materials.Gold
    goldOre.Color = Color3.fromRGB(255, 215, 0)
    goldOre.Parent = parent

    -- Rock pile decoration
    for i = 1, 3 + level do
        local rock = Instance.new("Part")
        rock.Name = "Rock"
        rock.Size = Vector3.new(0.4 + math.random() * 0.3, 0.3 + math.random() * 0.2, 0.4 + math.random() * 0.3)
        rock.Position = Vector3.new(
            baseSize * 0.3 + math.random() * 0.5,
            0.5 + (i - 1) * 0.15,
            -baseSize * 0.2 + math.random() * 0.4
        )
        rock.Anchored = true
        rock.Material = Materials.Stone
        rock.Color = Color3.fromRGB(80 + math.random(-20, 20), 80 + math.random(-20, 20), 80 + math.random(-20, 20))
        rock.Parent = parent
    end

    -- Wooden shed structure for higher levels
    if level >= 3 then
        local shed = Instance.new("Part")
        shed.Name = "Shed"
        shed.Size = Vector3.new(baseSize * 0.4, 1.5, baseSize * 0.4)
        shed.Position = Vector3.new(-baseSize * 0.25, 1.15, -baseSize * 0.25)
        shed.Anchored = true
        shed.Material = Materials.Wood
        shed.Color = palette.primary
        shed.Parent = parent

        -- Shed roof
        local shedRoof = Instance.new("WedgePart")
        shedRoof.Name = "ShedRoof"
        shedRoof.Size = Vector3.new(baseSize * 0.45, 0.6, baseSize * 0.45)
        shedRoof.Position = Vector3.new(-baseSize * 0.25, 2.2, -baseSize * 0.25)
        shedRoof.Anchored = true
        shedRoof.Material = Materials.Wood
        shedRoof.Color = palette.roof
        shedRoof.Parent = parent
    end

    return entranceFrame
end

--[[
    Creates lumber mill style building.
]]
local function createLumberMillBuilding(parent: Model, sizeX: number, sizeZ: number, level: number, palette: any): Part
    local baseSize = math.min(sizeX, sizeZ) * CELL_SIZE - 0.3
    local height = 2 + level * 0.3

    -- Main mill structure
    local millBody = Instance.new("Part")
    millBody.Name = "MillBody"
    millBody.Size = Vector3.new(baseSize * 0.8, height, baseSize * 0.6)
    millBody.Position = Vector3.new(0, 0.4 + height / 2, 0)
    millBody.Anchored = true
    millBody.Material = Materials.Wood
    millBody.Color = palette.primary
    millBody.Parent = parent

    -- Sloped wooden roof
    local roofLeft = Instance.new("WedgePart")
    roofLeft.Name = "RoofLeft"
    roofLeft.Size = Vector3.new(baseSize * 0.85, height * 0.4, baseSize * 0.35)
    roofLeft.Position = Vector3.new(0, 0.4 + height + height * 0.2, baseSize * 0.15)
    roofLeft.Orientation = Vector3.new(0, 180, 0)
    roofLeft.Anchored = true
    roofLeft.Material = Materials.Wood
    roofLeft.Color = palette.roof
    roofLeft.Parent = parent

    local roofRight = Instance.new("WedgePart")
    roofRight.Name = "RoofRight"
    roofRight.Size = Vector3.new(baseSize * 0.85, height * 0.4, baseSize * 0.35)
    roofRight.Position = Vector3.new(0, 0.4 + height + height * 0.2, -baseSize * 0.15)
    roofRight.Anchored = true
    roofRight.Material = Materials.Wood
    roofRight.Color = palette.roof
    roofRight.Parent = parent

    -- Sawmill blade (circular)
    local blade = Instance.new("Part")
    blade.Name = "SawBlade"
    blade.Size = Vector3.new(0.1, 1.2, 1.2)
    blade.Position = Vector3.new(baseSize * 0.4 + 0.1, 1.4, 0)
    blade.Anchored = true
    blade.Material = Materials.Metal
    blade.Color = Color3.fromRGB(150, 150, 150)
    blade.Shape = Enum.PartType.Cylinder
    blade.Orientation = Vector3.new(0, 0, 90)
    blade.Parent = parent

    -- Log pile
    for i = 1, 3 + math.floor(level / 2) do
        for j = 1, 3 - math.floor(i / 2) do
            local log = Instance.new("Part")
            log.Name = "Log"
            log.Size = Vector3.new(1.5, 0.35, 0.35)
            log.Position = Vector3.new(
                -baseSize * 0.35,
                0.55 + (i - 1) * 0.3,
                -baseSize * 0.3 + (j - 1) * 0.4
            )
            log.Anchored = true
            log.Material = Materials.WoodLog
            log.Color = Color3.fromRGB(101 + math.random(-10, 10), 67 + math.random(-10, 10), 33 + math.random(-10, 10))
            log.Shape = Enum.PartType.Cylinder
            log.Parent = parent
        end
    end

    -- Wood plank pile
    for i = 1, level do
        local plank = Instance.new("Part")
        plank.Name = "Plank"
        plank.Size = Vector3.new(1.2, 0.08, 0.3)
        plank.Position = Vector3.new(baseSize * 0.3, 0.5 + i * 0.08, baseSize * 0.3)
        plank.Anchored = true
        plank.Material = Materials.Wood
        plank.Color = Color3.fromRGB(194, 150, 100)
        plank.Parent = parent
    end

    return millBody
end

--[[
    Creates farm style building - Classic red barn with open doors.
]]
local function createFarmBuilding(parent: Model, sizeX: number, sizeZ: number, level: number, palette: any): Part
    local baseSize = math.min(sizeX, sizeZ) * CELL_SIZE - 0.3
    local barnWidth = baseSize * 0.85
    local barnDepth = baseSize * 0.7
    local wallHeight = 2.5 + level * 0.15
    local roofHeight = 1.5 + level * 0.1

    -- Classic barn red and white trim colors
    local barnRed = Color3.fromRGB(139, 35, 35)
    local barnRedDark = Color3.fromRGB(110, 28, 28)
    local whiteTrim = Color3.fromRGB(245, 245, 240)
    local roofGray = Color3.fromRGB(80, 80, 85)

    -- Main barn body (back wall - solid)
    local backWall = Instance.new("Part")
    backWall.Name = "BarnBackWall"
    backWall.Size = Vector3.new(barnWidth, wallHeight, 0.3)
    backWall.Position = Vector3.new(0, 0.4 + wallHeight / 2, -barnDepth / 2 + 0.15)
    backWall.Anchored = true
    backWall.Material = Materials.Wood
    backWall.Color = barnRed
    backWall.Parent = parent

    -- Left wall
    local leftWall = Instance.new("Part")
    leftWall.Name = "BarnLeftWall"
    leftWall.Size = Vector3.new(0.3, wallHeight, barnDepth)
    leftWall.Position = Vector3.new(-barnWidth / 2 + 0.15, 0.4 + wallHeight / 2, 0)
    leftWall.Anchored = true
    leftWall.Material = Materials.Wood
    leftWall.Color = barnRed
    leftWall.Parent = parent

    -- Right wall
    local rightWall = Instance.new("Part")
    rightWall.Name = "BarnRightWall"
    rightWall.Size = Vector3.new(0.3, wallHeight, barnDepth)
    rightWall.Position = Vector3.new(barnWidth / 2 - 0.15, 0.4 + wallHeight / 2, 0)
    rightWall.Anchored = true
    rightWall.Material = Materials.Wood
    rightWall.Color = barnRed
    rightWall.Parent = parent

    -- Front wall left section (beside door)
    local frontWallLeft = Instance.new("Part")
    frontWallLeft.Name = "BarnFrontLeft"
    frontWallLeft.Size = Vector3.new(barnWidth * 0.25, wallHeight, 0.3)
    frontWallLeft.Position = Vector3.new(-barnWidth * 0.375, 0.4 + wallHeight / 2, barnDepth / 2 - 0.15)
    frontWallLeft.Anchored = true
    frontWallLeft.Material = Materials.Wood
    frontWallLeft.Color = barnRed
    frontWallLeft.Parent = parent

    -- Front wall right section (beside door)
    local frontWallRight = Instance.new("Part")
    frontWallRight.Name = "BarnFrontRight"
    frontWallRight.Size = Vector3.new(barnWidth * 0.25, wallHeight, 0.3)
    frontWallRight.Position = Vector3.new(barnWidth * 0.375, 0.4 + wallHeight / 2, barnDepth / 2 - 0.15)
    frontWallRight.Anchored = true
    frontWallRight.Material = Materials.Wood
    frontWallRight.Color = barnRed
    frontWallRight.Parent = parent

    -- Front wall above door
    local frontWallTop = Instance.new("Part")
    frontWallTop.Name = "BarnFrontTop"
    frontWallTop.Size = Vector3.new(barnWidth * 0.5, wallHeight * 0.25, 0.3)
    frontWallTop.Position = Vector3.new(0, 0.4 + wallHeight * 0.875, barnDepth / 2 - 0.15)
    frontWallTop.Anchored = true
    frontWallTop.Material = Materials.Wood
    frontWallTop.Color = barnRed
    frontWallTop.Parent = parent

    -- Door frame (white trim around opening)
    local doorFrameLeft = Instance.new("Part")
    doorFrameLeft.Name = "DoorFrameLeft"
    doorFrameLeft.Size = Vector3.new(0.15, wallHeight * 0.75, 0.35)
    doorFrameLeft.Position = Vector3.new(-barnWidth * 0.25 + 0.075, 0.4 + wallHeight * 0.375, barnDepth / 2 - 0.15)
    doorFrameLeft.Anchored = true
    doorFrameLeft.Material = Materials.Wood
    doorFrameLeft.Color = whiteTrim
    doorFrameLeft.Parent = parent

    local doorFrameRight = Instance.new("Part")
    doorFrameRight.Name = "DoorFrameRight"
    doorFrameRight.Size = Vector3.new(0.15, wallHeight * 0.75, 0.35)
    doorFrameRight.Position = Vector3.new(barnWidth * 0.25 - 0.075, 0.4 + wallHeight * 0.375, barnDepth / 2 - 0.15)
    doorFrameRight.Anchored = true
    doorFrameRight.Material = Materials.Wood
    doorFrameRight.Color = whiteTrim
    doorFrameRight.Parent = parent

    local doorFrameTop = Instance.new("Part")
    doorFrameTop.Name = "DoorFrameTop"
    doorFrameTop.Size = Vector3.new(barnWidth * 0.5 + 0.15, 0.15, 0.35)
    doorFrameTop.Position = Vector3.new(0, 0.4 + wallHeight * 0.75 + 0.075, barnDepth / 2 - 0.15)
    doorFrameTop.Anchored = true
    doorFrameTop.Material = Materials.Wood
    doorFrameTop.Color = whiteTrim
    doorFrameTop.Parent = parent

    -- Barn doors (open, swung outward) - decorative
    local leftDoor = Instance.new("Part")
    leftDoor.Name = "BarnDoorLeft"
    leftDoor.Size = Vector3.new(barnWidth * 0.25, wallHeight * 0.7, 0.15)
    leftDoor.CFrame = CFrame.new(-barnWidth * 0.35, 0.4 + wallHeight * 0.35, barnDepth / 2 + 0.3)
        * CFrame.Angles(0, math.rad(45), 0)
    leftDoor.Anchored = true
    leftDoor.Material = Materials.Wood
    leftDoor.Color = barnRedDark
    leftDoor.Parent = parent

    local rightDoor = Instance.new("Part")
    rightDoor.Name = "BarnDoorRight"
    rightDoor.Size = Vector3.new(barnWidth * 0.25, wallHeight * 0.7, 0.15)
    rightDoor.CFrame = CFrame.new(barnWidth * 0.35, 0.4 + wallHeight * 0.35, barnDepth / 2 + 0.3)
        * CFrame.Angles(0, math.rad(-45), 0)
    rightDoor.Anchored = true
    rightDoor.Material = Materials.Wood
    rightDoor.Color = barnRedDark
    rightDoor.Parent = parent

    -- White X pattern on doors (classic barn style)
    local function createDoorX(door, xOffset)
        local xPart1 = Instance.new("Part")
        xPart1.Name = "DoorX1"
        xPart1.Size = Vector3.new(0.08, wallHeight * 0.5, 0.02)
        xPart1.CFrame = door.CFrame * CFrame.new(0, 0, 0.08) * CFrame.Angles(0, 0, math.rad(30))
        xPart1.Anchored = true
        xPart1.Material = Materials.Wood
        xPart1.Color = whiteTrim
        xPart1.Parent = parent

        local xPart2 = Instance.new("Part")
        xPart2.Name = "DoorX2"
        xPart2.Size = Vector3.new(0.08, wallHeight * 0.5, 0.02)
        xPart2.CFrame = door.CFrame * CFrame.new(0, 0, 0.08) * CFrame.Angles(0, 0, math.rad(-30))
        xPart2.Anchored = true
        xPart2.Material = Materials.Wood
        xPart2.Color = whiteTrim
        xPart2.Parent = parent
    end
    createDoorX(leftDoor, -1)
    createDoorX(rightDoor, 1)

    -- Gambrel roof (classic barn roof) - left side lower
    local roofLeftLower = Instance.new("Part")
    roofLeftLower.Name = "RoofLeftLower"
    roofLeftLower.Size = Vector3.new(barnWidth * 0.35, 0.2, barnDepth + 0.4)
    roofLeftLower.CFrame = CFrame.new(-barnWidth * 0.32, 0.4 + wallHeight + roofHeight * 0.25, 0)
        * CFrame.Angles(0, 0, math.rad(60))
    roofLeftLower.Anchored = true
    roofLeftLower.Material = Enum.Material.Metal
    roofLeftLower.Color = roofGray
    roofLeftLower.Parent = parent

    -- Gambrel roof - right side lower
    local roofRightLower = Instance.new("Part")
    roofRightLower.Name = "RoofRightLower"
    roofRightLower.Size = Vector3.new(barnWidth * 0.35, 0.2, barnDepth + 0.4)
    roofRightLower.CFrame = CFrame.new(barnWidth * 0.32, 0.4 + wallHeight + roofHeight * 0.25, 0)
        * CFrame.Angles(0, 0, math.rad(-60))
    roofRightLower.Anchored = true
    roofRightLower.Material = Enum.Material.Metal
    roofRightLower.Color = roofGray
    roofRightLower.Parent = parent

    -- Gambrel roof - left side upper
    local roofLeftUpper = Instance.new("Part")
    roofLeftUpper.Name = "RoofLeftUpper"
    roofLeftUpper.Size = Vector3.new(barnWidth * 0.35, 0.2, barnDepth + 0.4)
    roofLeftUpper.CFrame = CFrame.new(-barnWidth * 0.12, 0.4 + wallHeight + roofHeight * 0.7, 0)
        * CFrame.Angles(0, 0, math.rad(25))
    roofLeftUpper.Anchored = true
    roofLeftUpper.Material = Enum.Material.Metal
    roofLeftUpper.Color = roofGray
    roofLeftUpper.Parent = parent

    -- Gambrel roof - right side upper
    local roofRightUpper = Instance.new("Part")
    roofRightUpper.Name = "RoofRightUpper"
    roofRightUpper.Size = Vector3.new(barnWidth * 0.35, 0.2, barnDepth + 0.4)
    roofRightUpper.CFrame = CFrame.new(barnWidth * 0.12, 0.4 + wallHeight + roofHeight * 0.7, 0)
        * CFrame.Angles(0, 0, math.rad(-25))
    roofRightUpper.Anchored = true
    roofRightUpper.Material = Enum.Material.Metal
    roofRightUpper.Color = roofGray
    roofRightUpper.Parent = parent

    -- Roof ridge cap
    local roofRidge = Instance.new("Part")
    roofRidge.Name = "RoofRidge"
    roofRidge.Size = Vector3.new(0.25, 0.15, barnDepth + 0.5)
    roofRidge.Position = Vector3.new(0, 0.4 + wallHeight + roofHeight, 0)
    roofRidge.Anchored = true
    roofRidge.Material = Enum.Material.Metal
    roofRidge.Color = Color3.fromRGB(60, 60, 65)
    roofRidge.Parent = parent

    -- Hay bales inside (visible through door)
    local hayColors = {
        Color3.fromRGB(218, 190, 130),
        Color3.fromRGB(195, 170, 115),
        Color3.fromRGB(230, 200, 140),
    }

    for i = 1, 2 + math.floor(level / 3) do
        local hay = Instance.new("Part")
        hay.Name = "HayBale" .. i
        hay.Size = Vector3.new(0.6, 0.4, 0.5)
        hay.Position = Vector3.new(
            -barnWidth * 0.25 + (i - 1) * 0.7,
            0.6,
            -barnDepth * 0.2
        )
        hay.Anchored = true
        hay.Material = Enum.Material.Fabric
        hay.Color = hayColors[(i % 3) + 1]
        hay.Parent = parent
    end

    -- Stacked hay (shows food production level)
    if level >= 3 then
        for i = 1, math.min(level - 2, 4) do
            local stackedHay = Instance.new("Part")
            stackedHay.Name = "StackedHay" .. i
            stackedHay.Size = Vector3.new(0.5, 0.35, 0.45)
            stackedHay.Position = Vector3.new(
                -barnWidth * 0.15 + ((i - 1) % 2) * 0.6,
                0.95 + math.floor((i - 1) / 2) * 0.4,
                -barnDepth * 0.2
            )
            stackedHay.Anchored = true
            stackedHay.Material = Enum.Material.Fabric
            stackedHay.Color = hayColors[((i + 1) % 3) + 1]
            stackedHay.Parent = parent
        end
    end

    -- Floor inside barn (dirt/wood)
    local barnFloor = Instance.new("Part")
    barnFloor.Name = "BarnFloor"
    barnFloor.Size = Vector3.new(barnWidth - 0.4, 0.1, barnDepth - 0.4)
    barnFloor.Position = Vector3.new(0, 0.45, 0)
    barnFloor.Anchored = true
    barnFloor.Material = Materials.Dirt
    barnFloor.Color = Color3.fromRGB(90, 65, 40)
    barnFloor.Parent = parent

    -- White trim around top of walls
    local trimTop = Instance.new("Part")
    trimTop.Name = "TrimTop"
    trimTop.Size = Vector3.new(barnWidth + 0.1, 0.12, barnDepth + 0.1)
    trimTop.Position = Vector3.new(0, 0.4 + wallHeight + 0.06, 0)
    trimTop.Anchored = true
    trimTop.Material = Materials.Wood
    trimTop.Color = whiteTrim
    trimTop.Parent = parent

    -- Grain sack near entrance (shows food production)
    local sack = Instance.new("Part")
    sack.Name = "GrainSack"
    sack.Size = Vector3.new(0.4, 0.5, 0.3)
    sack.Position = Vector3.new(barnWidth * 0.35, 0.65, barnDepth * 0.35)
    sack.Anchored = true
    sack.Material = Enum.Material.Fabric
    sack.Color = Color3.fromRGB(194, 178, 128)
    sack.Parent = parent

    -- Second grain sack at higher levels
    if level >= 5 then
        local sack2 = Instance.new("Part")
        sack2.Name = "GrainSack2"
        sack2.Size = Vector3.new(0.35, 0.45, 0.28)
        sack2.Position = Vector3.new(barnWidth * 0.35, 1.1, barnDepth * 0.3)
        sack2.Anchored = true
        sack2.Material = Enum.Material.Fabric
        sack2.Color = Color3.fromRGB(180, 165, 120)
        sack2.Parent = parent
    end

    return backWall
end

--[[
    Creates barracks/military style building.
]]
local function createMilitaryBuilding(parent: Model, sizeX: number, sizeZ: number, level: number, palette: any): Part
    local baseSize = math.min(sizeX, sizeZ) * CELL_SIZE - 0.3
    local height = 2 + level * 0.4

    -- Main barracks structure
    local barracks = Instance.new("Part")
    barracks.Name = "Barracks"
    barracks.Size = Vector3.new(baseSize * 0.85, height, baseSize * 0.7)
    barracks.Position = Vector3.new(0, 0.4 + height / 2, 0)
    barracks.Anchored = true
    barracks.Material = Materials.StoneBrick
    barracks.Color = palette.primary
    barracks.Parent = parent

    -- Military banner poles
    for i = -1, 1, 2 do
        local pole = Instance.new("Part")
        pole.Name = "BannerPole"
        pole.Size = Vector3.new(0.1, height + 1, 0.1)
        pole.Position = Vector3.new(i * baseSize * 0.35, 0.4 + (height + 1) / 2, baseSize * 0.35)
        pole.Anchored = true
        pole.Material = Materials.Wood
        pole.Color = Color3.fromRGB(101, 67, 33)
        pole.Parent = parent

        -- Red banner
        local banner = Instance.new("Part")
        banner.Name = "Banner"
        banner.Size = Vector3.new(0.05, 0.8, 0.5)
        banner.Position = Vector3.new(i * baseSize * 0.35, 0.4 + height + 0.8, baseSize * 0.35 + 0.3)
        banner.Anchored = true
        banner.Material = Enum.Material.Fabric
        banner.Color = palette.accent
        banner.Parent = parent
    end

    -- Sloped roof
    local roof = Instance.new("WedgePart")
    roof.Name = "Roof"
    roof.Size = Vector3.new(baseSize * 0.9, 0.8, baseSize * 0.4)
    roof.Position = Vector3.new(0, 0.4 + height + 0.4, baseSize * 0.15)
    roof.Orientation = Vector3.new(0, 180, 0)
    roof.Anchored = true
    roof.Material = Materials.Slate
    roof.Color = palette.roof
    roof.Parent = parent

    -- Weapon rack
    local rack = Instance.new("Part")
    rack.Name = "WeaponRack"
    rack.Size = Vector3.new(1, 1.2, 0.2)
    rack.Position = Vector3.new(baseSize * 0.3, 1.2, -baseSize * 0.35)
    rack.Anchored = true
    rack.Material = Materials.Wood
    rack.Color = Color3.fromRGB(101, 67, 33)
    rack.Parent = parent

    -- Swords on rack
    for i = 1, 3 do
        local sword = Instance.new("Part")
        sword.Name = "Sword"
        sword.Size = Vector3.new(0.08, 0.9, 0.15)
        sword.Position = Vector3.new(baseSize * 0.3 + (i - 2) * 0.25, 1.3, -baseSize * 0.35 + 0.15)
        sword.Anchored = true
        sword.Material = Materials.Metal
        sword.Color = Color3.fromRGB(192, 192, 192)
        sword.Parent = parent
    end

    -- Training dummy
    if level >= 2 then
        local dummyPost = Instance.new("Part")
        dummyPost.Name = "DummyPost"
        dummyPost.Size = Vector3.new(0.15, 1.5, 0.15)
        dummyPost.Position = Vector3.new(-baseSize * 0.3, 1.15, baseSize * 0.2)
        dummyPost.Anchored = true
        dummyPost.Material = Materials.Wood
        dummyPost.Color = Color3.fromRGB(139, 90, 43)
        dummyPost.Parent = parent

        local dummyBody = Instance.new("Part")
        dummyBody.Name = "DummyBody"
        dummyBody.Size = Vector3.new(0.5, 0.7, 0.2)
        dummyBody.Position = Vector3.new(-baseSize * 0.3, 1.6, baseSize * 0.2)
        dummyBody.Anchored = true
        dummyBody.Material = Enum.Material.Fabric
        dummyBody.Color = Color3.fromRGB(194, 178, 128)
        dummyBody.Parent = parent
    end

    return barracks
end

--[[
    Creates storage building style.
]]
local function createStorageBuilding(parent: Model, sizeX: number, sizeZ: number, level: number, palette: any): Part
    local baseSize = math.min(sizeX, sizeZ) * CELL_SIZE - 0.3
    local height = 2 + level * 0.3

    -- Main vault structure
    local vault = Instance.new("Part")
    vault.Name = "Vault"
    vault.Size = Vector3.new(baseSize * 0.85, height, baseSize * 0.85)
    vault.Position = Vector3.new(0, 0.4 + height / 2, 0)
    vault.Anchored = true
    vault.Material = Materials.StoneBrick
    vault.Color = palette.primary
    vault.Parent = parent

    -- Reinforced corners
    for i = -1, 1, 2 do
        for j = -1, 1, 2 do
            local corner = Instance.new("Part")
            corner.Name = "Corner"
            corner.Size = Vector3.new(0.3, height + 0.2, 0.3)
            corner.Position = Vector3.new(i * baseSize * 0.4, 0.4 + (height + 0.2) / 2, j * baseSize * 0.4)
            corner.Anchored = true
            corner.Material = Materials.Stone
            corner.Color = palette.secondary
            corner.Parent = parent
        end
    end

    -- Gold trim bands
    for i = 1, math.min(3, level) do
        local band = Instance.new("Part")
        band.Name = "GoldBand"
        band.Size = Vector3.new(baseSize * 0.9, 0.1, baseSize * 0.9)
        band.Position = Vector3.new(0, 0.4 + height * (i / 4), 0)
        band.Anchored = true
        band.Material = Materials.Metal
        band.Color = palette.accent
        band.Parent = parent
    end

    -- Vault door
    local door = Instance.new("Part")
    door.Name = "VaultDoor"
    door.Size = Vector3.new(baseSize * 0.35, height * 0.6, 0.15)
    door.Position = Vector3.new(0, 0.4 + height * 0.35, baseSize * 0.42)
    door.Anchored = true
    door.Material = Materials.Metal
    door.Color = Color3.fromRGB(100, 100, 100)
    door.Parent = parent

    -- Door rivets
    for i = -1, 1 do
        for j = 0, 2 do
            local rivet = Instance.new("Part")
            rivet.Name = "Rivet"
            rivet.Size = Vector3.new(0.1, 0.1, 0.1)
            rivet.Position = Vector3.new(
                i * baseSize * 0.1,
                0.4 + height * 0.2 + j * height * 0.15,
                baseSize * 0.43
            )
            rivet.Anchored = true
            rivet.Material = Materials.Metal
            rivet.Color = Color3.fromRGB(192, 192, 192)
            rivet.Shape = Enum.PartType.Ball
            rivet.Parent = parent
        end
    end

    -- Domed roof
    local dome = Instance.new("Part")
    dome.Name = "Dome"
    dome.Size = Vector3.new(baseSize * 0.6, 0.8, baseSize * 0.6)
    dome.Position = Vector3.new(0, 0.4 + height + 0.4, 0)
    dome.Anchored = true
    dome.Material = Materials.Stone
    dome.Color = palette.roof
    dome.Shape = Enum.PartType.Ball
    dome.Parent = parent

    return vault
end

--[[
    Creates defense tower building.
]]
local function createDefenseBuilding(parent: Model, sizeX: number, sizeZ: number, level: number, palette: any, buildingType: string): Part
    local baseSize = math.min(sizeX, sizeZ) * CELL_SIZE - 0.3
    local height = 2.5 + level * 0.5

    -- Tower base
    local base = Instance.new("Part")
    base.Name = "TowerBase"
    base.Size = Vector3.new(baseSize * 0.9, height * 0.6, baseSize * 0.9)
    base.Position = Vector3.new(0, 0.4 + height * 0.3, 0)
    base.Anchored = true
    base.Material = Materials.Stone
    base.Color = palette.primary
    base.Parent = parent

    -- Tower platform
    local platform = Instance.new("Part")
    platform.Name = "Platform"
    platform.Size = Vector3.new(baseSize, 0.3, baseSize)
    platform.Position = Vector3.new(0, 0.4 + height * 0.6 + 0.15, 0)
    platform.Anchored = true
    platform.Material = Materials.StoneBrick
    platform.Color = palette.secondary
    platform.Parent = parent

    -- Weapon mount based on type
    if buildingType == "Cannon" then
        -- Cannon barrel
        local cannon = Instance.new("Part")
        cannon.Name = "Cannon"
        cannon.Size = Vector3.new(1.5, 0.5, 0.5)
        cannon.Position = Vector3.new(0, 0.4 + height * 0.6 + 0.6, baseSize * 0.2)
        cannon.Orientation = Vector3.new(0, 0, -10)
        cannon.Anchored = true
        cannon.Material = Materials.Metal
        cannon.Color = Color3.fromRGB(64, 64, 64)
        cannon.Shape = Enum.PartType.Cylinder
        cannon.Parent = parent

        -- Cannon base
        local cannonBase = Instance.new("Part")
        cannonBase.Name = "CannonBase"
        cannonBase.Size = Vector3.new(0.8, 0.3, 0.8)
        cannonBase.Position = Vector3.new(0, 0.4 + height * 0.6 + 0.45, 0)
        cannonBase.Anchored = true
        cannonBase.Material = Materials.Wood
        cannonBase.Color = Color3.fromRGB(101, 67, 33)
        cannonBase.Parent = parent

    elseif buildingType == "ArcherTower" then
        -- Archer platform with roof
        local roofPeaks = Instance.new("Part")
        roofPeaks.Name = "Roof"
        roofPeaks.Size = Vector3.new(baseSize * 1.1, 0.6, baseSize * 1.1)
        roofPeaks.Position = Vector3.new(0, 0.4 + height + 0.3, 0)
        roofPeaks.Anchored = true
        roofPeaks.Material = Materials.Wood
        roofPeaks.Color = palette.roof
        roofPeaks.Parent = parent

        -- Support beams
        for i = -1, 1, 2 do
            for j = -1, 1, 2 do
                local beam = Instance.new("Part")
                beam.Name = "SupportBeam"
                beam.Size = Vector3.new(0.15, 0.8, 0.15)
                beam.Position = Vector3.new(i * baseSize * 0.35, 0.4 + height * 0.6 + 0.7, j * baseSize * 0.35)
                beam.Anchored = true
                beam.Material = Materials.Wood
                beam.Color = Color3.fromRGB(101, 67, 33)
                beam.Parent = parent
            end
        end

    elseif buildingType == "Mortar" then
        -- Mortar tube
        local mortar = Instance.new("Part")
        mortar.Name = "Mortar"
        mortar.Size = Vector3.new(0.8, 1, 0.8)
        mortar.Position = Vector3.new(0, 0.4 + height * 0.6 + 0.8, 0)
        mortar.Orientation = Vector3.new(-30, 0, 0)
        mortar.Anchored = true
        mortar.Material = Materials.Metal
        mortar.Color = Color3.fromRGB(80, 80, 80)
        mortar.Shape = Enum.PartType.Cylinder
        mortar.Parent = parent

    elseif buildingType == "WizardTower" then
        -- Magical crystal top
        local crystal = Instance.new("Part")
        crystal.Name = "Crystal"
        crystal.Size = Vector3.new(0.6, 1.2, 0.6)
        crystal.Position = Vector3.new(0, 0.4 + height + 0.6, 0)
        crystal.Anchored = true
        crystal.Material = Materials.Crystal
        crystal.Color = Color3.fromRGB(138, 43, 226)
        crystal.Transparency = 0.3
        crystal.Parent = parent

        -- Magic glow
        local light = Instance.new("PointLight")
        light.Color = Color3.fromRGB(138, 43, 226)
        light.Brightness = 2
        light.Range = 8
        light.Parent = crystal

    elseif buildingType == "AirDefense" then
        -- Anti-air spikes
        for i = 1, 4 do
            local spike = Instance.new("Part")
            spike.Name = "Spike"
            spike.Size = Vector3.new(0.2, 1.5, 0.2)
            spike.Position = Vector3.new(
                math.cos(i * math.pi / 2) * baseSize * 0.25,
                0.4 + height * 0.6 + 1,
                math.sin(i * math.pi / 2) * baseSize * 0.25
            )
            spike.Orientation = Vector3.new(15 * math.cos(i * math.pi / 2), 0, 15 * math.sin(i * math.pi / 2))
            spike.Anchored = true
            spike.Material = Materials.Metal
            spike.Color = Color3.fromRGB(192, 192, 192)
            spike.Parent = parent
        end
    end

    -- Battlements
    for i = 1, 4 do
        local battlement = Instance.new("Part")
        battlement.Name = "Battlement"
        battlement.Size = Vector3.new(baseSize * 0.25, 0.5, 0.25)
        battlement.Position = Vector3.new(
            math.cos((i - 0.5) * math.pi / 2) * baseSize * 0.4,
            0.4 + height * 0.6 + 0.55,
            math.sin((i - 0.5) * math.pi / 2) * baseSize * 0.4
        )
        battlement.Anchored = true
        battlement.Material = Materials.Stone
        battlement.Color = palette.secondary
        battlement.Parent = parent
    end

    return base
end

--[[
    Creates wall segment.
]]
local function createWallBuilding(parent: Model, sizeX: number, sizeZ: number, level: number, palette: any): Part
    local wallHeight = 1 + level * 0.2

    -- Main wall segment
    local wall = Instance.new("Part")
    wall.Name = "Wall"
    wall.Size = Vector3.new(CELL_SIZE - 0.05, wallHeight, CELL_SIZE * 0.4)
    wall.Position = Vector3.new(0, 0.4 + wallHeight / 2, 0)
    wall.Anchored = true
    wall.Material = level >= 6 and Materials.Stone or (level >= 3 and Materials.StoneBrick or Materials.Wood)

    -- Color by level
    if level >= 8 then
        wall.Color = Color3.fromRGB(100, 100, 100)  -- Dark stone
    elseif level >= 6 then
        wall.Color = Color3.fromRGB(128, 128, 128)  -- Gray stone
    elseif level >= 4 then
        wall.Color = Color3.fromRGB(169, 154, 134)  -- Light stone
    elseif level >= 2 then
        wall.Color = Color3.fromRGB(139, 90, 43)    -- Wood
    else
        wall.Color = Color3.fromRGB(160, 120, 80)   -- Light wood
    end

    wall.Parent = parent

    -- Top cap
    local cap = Instance.new("Part")
    cap.Name = "Cap"
    cap.Size = Vector3.new(CELL_SIZE, 0.15, CELL_SIZE * 0.5)
    cap.Position = Vector3.new(0, 0.4 + wallHeight + 0.075, 0)
    cap.Anchored = true
    cap.Material = wall.Material
    cap.Color = palette.secondary
    cap.Parent = parent

    return wall
end

--[[
    Main building model creation function.
]]
local function createBuildingModel(buildingType: string, level: number): Model
    local buildingDef = BuildingData.GetByType(buildingType)
    local model = Instance.new("Model")
    model.Name = buildingType

    -- Get size from building data
    local sizeX = 1
    local sizeZ = 1
    if buildingDef then
        sizeX = buildingDef.width or 1
        sizeZ = buildingDef.height or 1
    end

    -- Get category and palette
    local category = buildingDef and buildingDef.category or "resource"
    local palette = BuildingPalettes[category] or BuildingPalettes.resource

    -- Create foundation for all buildings
    local foundation = createFoundation(model, sizeX, sizeZ, palette)

    -- Create building based on type
    local mainPart: Part

    if buildingType == "TownHall" then
        mainPart = createCastleBuilding(model, sizeX, sizeZ, level, palette)
    elseif buildingType == "GoldMine" then
        mainPart = createMineBuilding(model, sizeX, sizeZ, level, palette)
    elseif buildingType == "LumberMill" then
        mainPart = createLumberMillBuilding(model, sizeX, sizeZ, level, palette)
    elseif buildingType == "Farm" then
        mainPart = createFarmBuilding(model, sizeX, sizeZ, level, palette)
    elseif buildingType == "Barracks" or buildingType == "ArmyCamp" or buildingType == "SpellFactory" then
        mainPart = createMilitaryBuilding(model, sizeX, sizeZ, level, palette)
    elseif buildingType == "GoldStorage" then
        mainPart = createStorageBuilding(model, sizeX, sizeZ, level, palette)
    elseif buildingType == "Cannon" or buildingType == "ArcherTower" or buildingType == "Mortar"
           or buildingType == "AirDefense" or buildingType == "WizardTower" then
        mainPart = createDefenseBuilding(model, sizeX, sizeZ, level, palette, buildingType)
    elseif buildingType == "Wall" then
        mainPart = createWallBuilding(model, sizeX, sizeZ, level, palette)
    else
        -- Fallback generic building
        mainPart = createCastleBuilding(model, sizeX, sizeZ, level, palette)
    end

    -- Add level indicator for non-wall buildings
    if buildingType ~= "Wall" then
        local levelGui = Instance.new("BillboardGui")
        levelGui.Name = "LevelGui"
        levelGui.Size = UDim2.new(0, 50, 0, 25)
        levelGui.StudsOffset = Vector3.new(0, 4 + level * 0.3, 0)
        levelGui.AlwaysOnTop = false
        levelGui.Parent = mainPart

        local levelBg = Instance.new("Frame")
        levelBg.Size = UDim2.new(1, 0, 1, 0)
        levelBg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        levelBg.BackgroundTransparency = 0.3
        levelBg.BorderSizePixel = 0
        levelBg.Parent = levelGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0.2, 0)
        corner.Parent = levelBg

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(184, 134, 11)
        stroke.Thickness = 1
        stroke.Parent = levelBg

        local levelLabel = Instance.new("TextLabel")
        levelLabel.Size = UDim2.new(1, 0, 1, 0)
        levelLabel.BackgroundTransparency = 1
        levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        levelLabel.Text = "Lv." .. level
        levelLabel.TextScaled = true
        levelLabel.Font = Enum.Font.GothamBold
        levelLabel.Parent = levelBg
    end

    -- Add click detector
    local clickDetector = Instance.new("ClickDetector")
    clickDetector.MaxActivationDistance = 100
    clickDetector.Parent = foundation

    -- Set primary part
    model.PrimaryPart = foundation

    return model
end

--[[
    Creates a grid cell visual.
]]
local function createGridCell(x: number, z: number): Part
    local cell = Instance.new("Part")
    cell.Name = string.format("Cell_%d_%d", x, z)
    cell.Size = Vector3.new(CELL_SIZE - 0.1, GRID_HEIGHT, CELL_SIZE - 0.1)
    cell.Position = Vector3.new(
        x * CELL_SIZE + CELL_SIZE / 2,
        GRID_HEIGHT / 2,
        z * CELL_SIZE + CELL_SIZE / 2
    )
    cell.Anchored = true
    cell.CanCollide = false
    cell.Material = Enum.Material.Neon
    cell.Transparency = 0.95
    cell.Color = Color3.fromRGB(100, 200, 100)
    cell.Parent = _gridFolder

    return cell
end

--[[
    Creates the city grid.
]]
local function createGrid()
    for x = 0, GRID_SIZE - 1 do
        for z = 0, GRID_SIZE - 1 do
            createGridCell(x, z)
        end
    end
end

--[[
    Creates environmental decorations.
]]
local function createEnvironment()
    -- Trees around the perimeter
    local treePositions = {
        {-15, -15}, {-15, 0}, {-15, 15}, {-15, 30},
        {GRID_SIZE * CELL_SIZE + 10, -10}, {GRID_SIZE * CELL_SIZE + 10, 20},
        {-10, -10}, {30, GRID_SIZE * CELL_SIZE + 5}, {60, GRID_SIZE * CELL_SIZE + 5},
    }

    for _, pos in treePositions do
        -- Tree trunk
        local trunk = Instance.new("Part")
        trunk.Name = "TreeTrunk"
        trunk.Size = Vector3.new(0.8, 3 + math.random() * 2, 0.8)
        trunk.Position = Vector3.new(pos[1], trunk.Size.Y / 2, pos[2])
        trunk.Anchored = true
        trunk.Material = Materials.WoodLog
        trunk.Color = Color3.fromRGB(101, 67, 33)
        trunk.Shape = Enum.PartType.Cylinder
        trunk.Orientation = Vector3.new(0, 0, 90)
        trunk.Parent = _environmentFolder

        -- Tree canopy
        local canopy = Instance.new("Part")
        canopy.Name = "TreeCanopy"
        canopy.Size = Vector3.new(3 + math.random() * 2, 3 + math.random() * 2, 3 + math.random() * 2)
        canopy.Position = Vector3.new(pos[1], trunk.Size.Y + canopy.Size.Y / 2, pos[2])
        canopy.Anchored = true
        canopy.Material = Enum.Material.Grass
        canopy.Color = Color3.fromRGB(34 + math.random(-15, 15), 139 + math.random(-20, 20), 34 + math.random(-15, 15))
        canopy.Shape = Enum.PartType.Ball
        canopy.Parent = _environmentFolder
    end

    -- Decorative rocks
    for i = 1, 8 do
        local rock = Instance.new("Part")
        rock.Name = "Rock"
        rock.Size = Vector3.new(
            1 + math.random() * 1.5,
            0.5 + math.random() * 1,
            1 + math.random() * 1.5
        )
        rock.Position = Vector3.new(
            math.random(-20, GRID_SIZE * CELL_SIZE + 20),
            rock.Size.Y / 2,
            math.random(-20, GRID_SIZE * CELL_SIZE + 20)
        )
        rock.Anchored = true
        rock.Material = Materials.Stone
        rock.Color = Color3.fromRGB(100 + math.random(-20, 20), 100 + math.random(-20, 20), 100 + math.random(-20, 20))
        rock.Parent = _environmentFolder
    end
end

--[[
    Shows the grid (for placement mode).
]]
function CityRenderer:ShowGrid()
    for _, cell in _gridFolder:GetChildren() do
        if cell:IsA("Part") then
            TweenService:Create(cell, TweenInfo.new(0.2), {
                Transparency = 0.7
            }):Play()
        end
    end
end

--[[
    Hides the grid.
]]
function CityRenderer:HideGrid()
    for _, cell in _gridFolder:GetChildren() do
        if cell:IsA("Part") then
            TweenService:Create(cell, TweenInfo.new(0.2), {
                Transparency = 0.98
            }):Play()
        end
    end
end

--[[
    Creates or updates a building model.
]]
function CityRenderer:RenderBuilding(buildingId: string, buildingData: any)
    -- Remove existing model if any
    if _buildingModels[buildingId] then
        _buildingModels[buildingId]:Destroy()
    end

    -- Create new model
    local model = createBuildingModel(buildingData.type, buildingData.level or 1)
    model.Name = buildingId

    -- Position on grid
    local gridX = buildingData.position and buildingData.position.x or 0
    local gridZ = buildingData.position and buildingData.position.z or 0
    local worldPos = Vector3.new(
        gridX * CELL_SIZE + CELL_SIZE / 2,
        0,
        gridZ * CELL_SIZE + CELL_SIZE / 2
    )

    model:SetPrimaryPartCFrame(CFrame.new(worldPos))
    model.Parent = _buildingsFolder

    -- Connect click handler
    local foundation = model:FindFirstChild("Foundation")
    if foundation then
        local clickDetector = foundation:FindFirstChild("ClickDetector")
        if clickDetector then
            clickDetector.MouseClick:Connect(function()
                CityRenderer.BuildingClicked:Fire(buildingId)
            end)
        end
    end

    -- Show upgrade effect if upgrading
    if buildingData.state == "Upgrading" then
        self:ShowUpgradeEffect(model)
    end

    -- Store reference
    _buildingModels[buildingId] = model
end

--[[
    Removes a building model.
]]
function CityRenderer:RemoveBuilding(buildingId: string)
    local model = _buildingModels[buildingId]
    if model then
        -- Fade out animation
        for _, part in model:GetDescendants() do
            if part:IsA("BasePart") then
                TweenService:Create(part, TweenInfo.new(0.3), {
                    Transparency = 1
                }):Play()
            end
        end

        task.delay(0.3, function()
            model:Destroy()
        end)

        _buildingModels[buildingId] = nil
    end
end

--[[
    Renders all buildings from player data.
]]
function CityRenderer:RenderAllBuildings(buildings: {[string]: any})
    -- Clear existing
    for id in _buildingModels do
        self:RemoveBuilding(id)
    end

    -- Render each building
    for id, data in buildings do
        self:RenderBuilding(id, data)
    end
end

--[[
    Shows placement preview for a building type.
]]
function CityRenderer:ShowPlacementPreview(buildingType: string)
    -- Remove existing preview
    self:HidePlacementPreview()

    -- Create preview model
    _placementPreview = createBuildingModel(buildingType, 1)
    _placementPreview.Name = "PlacementPreview"

    -- Make semi-transparent
    for _, part in _placementPreview:GetDescendants() do
        if part:IsA("BasePart") then
            part.Transparency = 0.5
            part.CanCollide = false
        end
    end

    _placementPreview.Parent = _effectsFolder

    -- Show grid
    self:ShowGrid()
end

--[[
    Updates placement preview position.
]]
function CityRenderer:UpdatePlacementPreview(gridX: number, gridZ: number, isValid: boolean)
    if not _placementPreview then return end

    local worldPos = Vector3.new(
        gridX * CELL_SIZE + CELL_SIZE / 2,
        0,
        gridZ * CELL_SIZE + CELL_SIZE / 2
    )

    _placementPreview:SetPrimaryPartCFrame(CFrame.new(worldPos))
    _placementValid = isValid

    -- Update color based on validity
    local color = isValid and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
    for _, part in _placementPreview:GetDescendants() do
        if part:IsA("BasePart") then
            part.Color = color
        end
    end
end

--[[
    Hides placement preview.
]]
function CityRenderer:HidePlacementPreview()
    if _placementPreview then
        _placementPreview:Destroy()
        _placementPreview = nil
    end

    self:HideGrid()
end

--[[
    Selects a building (shows highlight).
]]
function CityRenderer:SelectBuilding(buildingId: string)
    -- Deselect previous
    self:DeselectBuilding()

    local model = _buildingModels[buildingId]
    if not model then return end

    _selectedBuildingId = buildingId

    -- Create selection highlight
    _selectionHighlight = Instance.new("SelectionBox")
    _selectionHighlight.Adornee = model
    _selectionHighlight.Color3 = Color3.fromRGB(255, 215, 0)
    _selectionHighlight.LineThickness = 0.03
    _selectionHighlight.SurfaceTransparency = 0.9
    _selectionHighlight.Parent = model
end

--[[
    Deselects the current building.
]]
function CityRenderer:DeselectBuilding()
    if _selectionHighlight then
        _selectionHighlight:Destroy()
        _selectionHighlight = nil
    end
    _selectedBuildingId = nil
end

--[[
    Shows upgrade effect on a building.
]]
function CityRenderer:ShowUpgradeEffect(model: Model)
    -- Create sparkle effect
    local mainPart = model:FindFirstChild("Foundation")
    if not mainPart then return end

    local particles = Instance.new("ParticleEmitter")
    particles.Name = "UpgradeEffect"
    particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    particles.Color = ColorSequence.new(Color3.fromRGB(255, 200, 0))
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 0)
    })
    particles.Rate = 15
    particles.Lifetime = NumberRange.new(1, 2)
    particles.Speed = NumberRange.new(2, 4)
    particles.SpreadAngle = Vector2.new(360, 360)
    particles.Parent = mainPart

    -- Add construction indicator
    local constructGui = Instance.new("BillboardGui")
    constructGui.Name = "ConstructionGui"
    constructGui.Size = UDim2.new(0, 60, 0, 60)
    constructGui.StudsOffset = Vector3.new(0, 5, 0)
    constructGui.AlwaysOnTop = true
    constructGui.Parent = mainPart

    local constructBg = Instance.new("Frame")
    constructBg.Size = UDim2.new(1, 0, 1, 0)
    constructBg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    constructBg.BackgroundTransparency = 0.3
    constructBg.BorderSizePixel = 0
    constructBg.Parent = constructGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = constructBg

    local constructLabel = Instance.new("TextLabel")
    constructLabel.Size = UDim2.new(1, 0, 1, 0)
    constructLabel.BackgroundTransparency = 1
    constructLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
    constructLabel.Text = "🔨"
    constructLabel.TextScaled = true
    constructLabel.Parent = constructBg

    -- Animate
    task.spawn(function()
        while constructGui.Parent do
            constructLabel.Rotation = constructLabel.Rotation + 3
            task.wait(0.03)
        end
    end)
end

--[[
    Clears upgrade effect from a building.
]]
function CityRenderer:ClearUpgradeEffect(buildingId: string)
    local model = _buildingModels[buildingId]
    if not model then return end

    local foundation = model:FindFirstChild("Foundation")
    if foundation then
        local particles = foundation:FindFirstChild("UpgradeEffect")
        if particles then particles:Destroy() end

        local constructGui = foundation:FindFirstChild("ConstructionGui")
        if constructGui then constructGui:Destroy() end
    end
end

--[[
    Shows resource collection effect.
]]
function CityRenderer:ShowCollectionEffect(buildingId: string, resourceType: string, amount: number)
    local model = _buildingModels[buildingId]
    if not model or not model.PrimaryPart then return end

    local position = model.PrimaryPart.Position

    -- Create floating text
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(0, 120, 0, 40)
    billboardGui.StudsOffset = Vector3.new(0, 3, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = _effectsFolder

    local attachment = Instance.new("Attachment")
    attachment.WorldPosition = position
    attachment.Parent = workspace.Terrain
    billboardGui.Adornee = attachment

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = resourceType == "gold" and Color3.fromRGB(255, 215, 0) or
                       resourceType == "wood" and Color3.fromRGB(139, 90, 43) or
                       Color3.fromRGB(50, 205, 50)
    label.Text = "+" .. tostring(amount)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.TextStrokeTransparency = 0.3
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.Parent = billboardGui

    -- Animate up and fade
    local startOffset = billboardGui.StudsOffset
    local tween = TweenService:Create(billboardGui, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        StudsOffset = startOffset + Vector3.new(0, 3, 0)
    })
    tween:Play()

    TweenService:Create(label, TweenInfo.new(1.2), {
        TextTransparency = 1,
        TextStrokeTransparency = 1
    }):Play()

    task.delay(1.2, function()
        billboardGui:Destroy()
        attachment:Destroy()
    end)
end

--[[
    Gets the building ID at a world position.
]]
function CityRenderer:GetBuildingAtPosition(position: Vector3): string?
    for id, model in _buildingModels do
        if model.PrimaryPart then
            local size = model.PrimaryPart.Size
            local center = model.PrimaryPart.Position
            local minBound = center - size / 2
            local maxBound = center + size / 2

            if position.X >= minBound.X and position.X <= maxBound.X and
               position.Z >= minBound.Z and position.Z <= maxBound.Z then
                return id
            end
        end
    end
    return nil
end

--[[
    Initializes the CityRenderer.
]]
function CityRenderer:Init()
    if _initialized then
        warn("CityRenderer already initialized")
        return
    end

    -- Create folder structure
    _cityFolder = Instance.new("Folder")
    _cityFolder.Name = "City"
    _cityFolder.Parent = workspace

    _buildingsFolder = Instance.new("Folder")
    _buildingsFolder.Name = "Buildings"
    _buildingsFolder.Parent = _cityFolder

    _gridFolder = Instance.new("Folder")
    _gridFolder.Name = "Grid"
    _gridFolder.Parent = _cityFolder

    _effectsFolder = Instance.new("Folder")
    _effectsFolder.Name = "Effects"
    _effectsFolder.Parent = _cityFolder

    _environmentFolder = Instance.new("Folder")
    _environmentFolder.Name = "Environment"
    _environmentFolder.Parent = _cityFolder

    -- Create ground with grass texture
    local ground = Instance.new("Part")
    ground.Name = "Ground"
    ground.Size = Vector3.new(GRID_SIZE * CELL_SIZE + 60, 2, GRID_SIZE * CELL_SIZE + 60)
    ground.Position = Vector3.new(GRID_SIZE * CELL_SIZE / 2, -1, GRID_SIZE * CELL_SIZE / 2)
    ground.Anchored = true
    ground.Material = Enum.Material.Grass
    ground.Color = Color3.fromRGB(76, 153, 34)
    ground.Parent = _cityFolder

    -- Add subtle terrain variations
    local dirtPatch = Instance.new("Part")
    dirtPatch.Name = "DirtPatch"
    dirtPatch.Size = Vector3.new(GRID_SIZE * CELL_SIZE, 0.05, GRID_SIZE * CELL_SIZE)
    dirtPatch.Position = Vector3.new(GRID_SIZE * CELL_SIZE / 2, 0.025, GRID_SIZE * CELL_SIZE / 2)
    dirtPatch.Anchored = true
    dirtPatch.Material = Enum.Material.Ground
    dirtPatch.Color = Color3.fromRGB(139, 115, 85)
    dirtPatch.Transparency = 0.7
    dirtPatch.Parent = _cityFolder

    -- Create grid
    createGrid()
    self:HideGrid()

    -- Create environmental decorations
    createEnvironment()

    _initialized = true
    print("CityRenderer initialized with Fantasy-Medieval theme")
end

return CityRenderer
