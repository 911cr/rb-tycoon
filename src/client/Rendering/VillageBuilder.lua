--!strict
--[[
    VillageBuilder.lua

    Creates the complete medieval village environment.
    Handles cobblestone streets, building placement, farm zone, and decorations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

-- Use WaitForChild to safely access ReplicatedStorage modules (standard Roblox pattern)
local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
if not Shared then
    error("ReplicatedStorage.Shared failed to load after 10 seconds")
end

local Constants = Shared:WaitForChild("Constants", 10)
if not Constants then
    error("ReplicatedStorage.Shared.Constants failed to load after 10 seconds")
end

local VillageLayout = require(Constants:WaitForChild("VillageLayout", 10))

local VillageBuilder = {}

-- ============================================================================
-- MATERIALS & COLORS
-- ============================================================================

local Materials = {
    Cobblestone = Enum.Material.Cobblestone,
    Brick = Enum.Material.Brick,
    Wood = Enum.Material.WoodPlanks,
    WoodLog = Enum.Material.Wood,
    Stone = Enum.Material.Rock,
    Dirt = Enum.Material.Ground,
    Grass = Enum.Material.Grass,
    Metal = Enum.Material.DiamondPlate,
    Thatch = Enum.Material.Grass,
    Slate = Enum.Material.Slate,
    Fabric = Enum.Material.Fabric,
}

local Colors = {
    Cobblestone = Color3.fromRGB(120, 115, 110),
    CobblestoneWorn = Color3.fromRGB(105, 100, 95),
    Dirt = Color3.fromRGB(115, 85, 55),
    DirtPath = Color3.fromRGB(130, 100, 70),
    WoodBrown = Color3.fromRGB(101, 67, 33),
    WoodLight = Color3.fromRGB(139, 100, 60),
    StoneGray = Color3.fromRGB(128, 125, 120),
    StoneDark = Color3.fromRGB(80, 78, 75),
    Hay = Color3.fromRGB(210, 180, 100),
    Wheat = Color3.fromRGB(218, 190, 100),
    WheatGreen = Color3.fromRGB(100, 150, 60),
    FenceWood = Color3.fromRGB(120, 80, 45),
    MetalDark = Color3.fromRGB(60, 60, 65),
    Rope = Color3.fromRGB(160, 140, 100),
    TreeTrunk = Color3.fromRGB(85, 60, 40),
    TreeLeaves = Color3.fromRGB(60, 120, 45),
    BannerRed = Color3.fromRGB(140, 30, 30),
    BannerGold = Color3.fromRGB(180, 150, 50),
    TorchFire = Color3.fromRGB(255, 150, 50),
    IronDark = Color3.fromRGB(70, 70, 75),
}

-- ============================================================================
-- FOLDER STRUCTURE
-- ============================================================================

local _villageFolder: Folder
local _streetsFolder: Folder
local _buildingsFolder: Folder
local _farmFolder: Folder
local _decorationsFolder: Folder
local _defenseFolder: Folder
local _boundaryFolder: Folder
local _treesFolder: Folder

-- ============================================================================
-- STREET CREATION
-- ============================================================================

--[[
    Creates a cobblestone street section with detail.
]]
local function createStreetSection(position: Vector3, size: Vector3, material: string, parent: Folder): Model
    local street = Instance.new("Model")
    street.Name = "Street"

    -- Base layer
    local base = Instance.new("Part")
    base.Name = "StreetBase"
    base.Size = size + Vector3.new(0, 0.1, 0)
    base.Position = position + Vector3.new(size.X/2, 0.05, size.Z/2)
    base.Anchored = true
    base.Material = material == "Dirt" and Materials.Dirt or Materials.Cobblestone
    base.Color = material == "Dirt" and Colors.DirtPath or Colors.Cobblestone
    base.Parent = street

    -- Add cobblestone detail (raised stones)
    if material == "Cobblestone" then
        local numStones = math.floor(size.X * size.Z / 8)
        for i = 1, math.min(numStones, 30) do
            local stone = Instance.new("Part")
            stone.Name = "Stone"
            stone.Size = Vector3.new(
                0.8 + math.random() * 0.6,
                0.15 + math.random() * 0.1,
                0.8 + math.random() * 0.6
            )
            stone.Position = position + Vector3.new(
                math.random() * size.X,
                0.15 + stone.Size.Y/2,
                math.random() * size.Z
            )
            stone.Orientation = Vector3.new(
                math.random(-3, 3),
                math.random(0, 360),
                math.random(-3, 3)
            )
            stone.Anchored = true
            stone.Material = Materials.Cobblestone
            stone.Color = Color3.fromRGB(
                110 + math.random(-15, 15),
                105 + math.random(-15, 15),
                100 + math.random(-15, 15)
            )
            stone.Parent = street
        end

        -- Curb stones on edges
        local curbs = {
            {Vector3.new(position.X, 0, position.Z), Vector3.new(size.X, 0.25, 0.4)},
            {Vector3.new(position.X, 0, position.Z + size.Z - 0.4), Vector3.new(size.X, 0.25, 0.4)},
        }

        for _, curbData in curbs do
            local curb = Instance.new("Part")
            curb.Name = "Curb"
            curb.Size = curbData[2]
            curb.Position = curbData[1] + Vector3.new(curbData[2].X/2, 0.125, curbData[2].Z/2)
            curb.Anchored = true
            curb.Material = Materials.Stone
            curb.Color = Colors.StoneDark
            curb.Parent = street
        end
    end

    street.Parent = parent
    return street
end

--[[
    Creates all streets in the village.
]]
local function createStreets()
    for name, streetData in VillageLayout.Streets do
        local worldPos = VillageLayout.GetWorldPosition(streetData.start)
        createStreetSection(worldPos, streetData.size, streetData.material, _streetsFolder)
    end
end

-- ============================================================================
-- BUILDING CREATION
-- ============================================================================

--[[
    Creates a medieval-style building.
]]
local function createBuilding(buildingType: string, position: Vector3, rotation: number): Model
    local model = Instance.new("Model")
    model.Name = buildingType

    -- Building dimensions based on type
    local dimensions = {
        TownHall = {width = 14, height = 12, depth = 14},
        LumberMill = {width = 10, height = 7, depth = 10},
        GoldStorage = {width = 10, height = 8, depth = 10},
        Barracks = {width = 12, height = 8, depth = 10},
        GoldMine = {width = 10, height = 6, depth = 10},
        Shop = {width = 10, height = 7, depth = 8},
        SpellFactory = {width = 10, height = 9, depth = 10},
        ArmyCamp = {width = 14, height = 5, depth = 14},
    }

    local dim = dimensions[buildingType] or {width = 10, height = 8, depth = 10}

    -- Foundation
    local foundation = Instance.new("Part")
    foundation.Name = "Foundation"
    foundation.Size = Vector3.new(dim.width + 1, 0.5, dim.depth + 1)
    foundation.Position = position + Vector3.new(0, 0.25, 0)
    foundation.Anchored = true
    foundation.Material = Materials.Stone
    foundation.Color = Colors.StoneDark
    foundation.Parent = model

    -- Main building body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(dim.width, dim.height, dim.depth)
    body.Position = position + Vector3.new(0, 0.5 + dim.height/2, 0)
    body.Anchored = true

    if buildingType == "TownHall" then
        body.Material = Materials.Brick
        body.Color = Color3.fromRGB(139, 119, 101)
    elseif buildingType == "LumberMill" then
        body.Material = Materials.Wood
        body.Color = Colors.WoodBrown
    elseif buildingType == "GoldStorage" then
        body.Material = Materials.Stone
        body.Color = Colors.StoneGray
    elseif buildingType == "Barracks" then
        body.Material = Materials.Brick
        body.Color = Color3.fromRGB(120, 80, 70)
    elseif buildingType == "GoldMine" then
        body.Material = Materials.Stone
        body.Color = Color3.fromRGB(90, 85, 80)
    elseif buildingType == "Shop" then
        body.Material = Materials.Wood
        body.Color = Colors.WoodLight
    elseif buildingType == "SpellFactory" then
        body.Material = Materials.Brick
        body.Color = Color3.fromRGB(100, 80, 120)
    elseif buildingType == "ArmyCamp" then
        body.Material = Materials.Fabric
        body.Color = Color3.fromRGB(160, 140, 100)
    else
        body.Material = Materials.Brick
        body.Color = Colors.StoneGray
    end

    body.Parent = model

    -- Roof
    if buildingType ~= "ArmyCamp" then
        local roofHeight = dim.height * 0.4
        local roof = Instance.new("WedgePart")
        roof.Name = "Roof"
        roof.Size = Vector3.new(dim.width + 2, roofHeight, dim.depth/2 + 1)
        roof.Position = position + Vector3.new(0, 0.5 + dim.height + roofHeight/2, dim.depth/4)
        roof.Orientation = Vector3.new(0, 180, 0)
        roof.Anchored = true
        roof.Material = buildingType == "LumberMill" and Materials.Wood or Materials.Slate
        roof.Color = buildingType == "TownHall" and Color3.fromRGB(100, 60, 80) or Color3.fromRGB(80, 75, 70)
        roof.Parent = model

        local roof2 = Instance.new("WedgePart")
        roof2.Name = "Roof2"
        roof2.Size = Vector3.new(dim.width + 2, roofHeight, dim.depth/2 + 1)
        roof2.Position = position + Vector3.new(0, 0.5 + dim.height + roofHeight/2, -dim.depth/4)
        roof2.Anchored = true
        roof2.Material = roof.Material
        roof2.Color = roof.Color
        roof2.Parent = model
    end

    -- Door
    local door = Instance.new("Part")
    door.Name = "Door"
    door.Size = Vector3.new(dim.width * 0.25, dim.height * 0.5, 0.2)
    door.Position = position + Vector3.new(0, 0.5 + dim.height * 0.25, dim.depth/2 + 0.1)
    door.Anchored = true
    door.Material = Materials.Wood
    door.Color = Color3.fromRGB(80, 50, 25)
    door.Parent = model

    -- Windows with warm interior glow
    local windowHeight = dim.height * 0.6
    for i = -1, 1, 2 do
        local window = Instance.new("Part")
        window.Name = "Window"
        window.Size = Vector3.new(1.5, 2, 0.1)
        window.Position = position + Vector3.new(i * dim.width * 0.3, windowHeight, dim.depth/2 + 0.1)
        window.Anchored = true
        window.Material = Enum.Material.Glass
        window.Color = Color3.fromRGB(255, 220, 150)  -- Warm candlelight color
        window.Transparency = 0.4
        window.Parent = model

        -- Interior glow (warm light behind window)
        local glow = Instance.new("PointLight")
        glow.Color = Color3.fromRGB(255, 180, 100)
        glow.Brightness = 0.8
        glow.Range = 8
        glow.Parent = window
    end

    -- Wall torches next to door
    for i = -1, 1, 2 do
        local torchPos = position + Vector3.new(i * (dim.width * 0.4), dim.height * 0.5, dim.depth/2 + 0.3)

        -- Torch bracket
        local bracket = Instance.new("Part")
        bracket.Name = "TorchBracket"
        bracket.Size = Vector3.new(0.15, 0.15, 0.3)
        bracket.Position = torchPos
        bracket.Anchored = true
        bracket.Material = Enum.Material.DiamondPlate
        bracket.Color = Color3.fromRGB(70, 70, 75)
        bracket.Parent = model

        -- Torch
        local torch = Instance.new("Part")
        torch.Name = "Torch"
        torch.Size = Vector3.new(0.15, 0.5, 0.15)
        torch.Position = torchPos + Vector3.new(0, 0.3, 0.15)
        torch.Orientation = Vector3.new(-15, 0, 0)
        torch.Anchored = true
        torch.Material = Enum.Material.Wood
        torch.Color = Color3.fromRGB(101, 67, 33)
        torch.Parent = model

        -- Fire particles
        local fire = Instance.new("ParticleEmitter")
        fire.Texture = "rbxasset://textures/particles/fire_main.dds"
        fire.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 80)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 30)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 60, 20)),
        })
        fire.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.15),
            NumberSequenceKeypoint.new(0.5, 0.25),
            NumberSequenceKeypoint.new(1, 0.05),
        })
        fire.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(1, 1),
        })
        fire.Lifetime = NumberRange.new(0.2, 0.4)
        fire.Rate = 20
        fire.Speed = NumberRange.new(1, 2)
        fire.SpreadAngle = Vector2.new(8, 8)
        fire.Parent = torch

        -- Torch light
        local light = Instance.new("PointLight")
        light.Color = Color3.fromRGB(255, 180, 80)
        light.Brightness = 1.2
        light.Range = 10
        light.Parent = torch
    end

    -- Chimney (except for army camp)
    if buildingType ~= "ArmyCamp" then
        local chimney = Instance.new("Part")
        chimney.Name = "Chimney"
        chimney.Size = Vector3.new(1.5, 3, 1.5)
        chimney.Position = position + Vector3.new(dim.width * 0.3, 0.5 + dim.height + 1.5, 0)
        chimney.Anchored = true
        chimney.Material = Materials.Brick
        chimney.Color = Color3.fromRGB(100, 70, 60)
        chimney.Parent = model

        -- Smoke particles
        local smoke = Instance.new("ParticleEmitter")
        smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
        smoke.Color = ColorSequence.new(Color3.fromRGB(150, 150, 150))
        smoke.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(1, 2),
        })
        smoke.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(1, 1),
        })
        smoke.Lifetime = NumberRange.new(3, 5)
        smoke.Rate = 3
        smoke.Speed = NumberRange.new(1, 2)
        smoke.SpreadAngle = Vector2.new(10, 10)
        smoke.Parent = chimney
    end

    -- Building sign
    local signGui = Instance.new("BillboardGui")
    signGui.Name = "Sign"
    signGui.Size = UDim2.new(0, 150, 0, 40)
    signGui.StudsOffset = Vector3.new(0, dim.height + 3, 0)
    signGui.AlwaysOnTop = false
    signGui.Parent = body

    local signBg = Instance.new("Frame")
    signBg.Size = UDim2.new(1, 0, 1, 0)
    signBg.BackgroundColor3 = Color3.fromRGB(60, 45, 30)
    signBg.BorderSizePixel = 0
    signBg.Parent = signGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.2, 0)
    corner.Parent = signBg

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(139, 100, 50)
    stroke.Thickness = 2
    stroke.Parent = signBg

    local signLabel = Instance.new("TextLabel")
    signLabel.Size = UDim2.new(1, 0, 1, 0)
    signLabel.BackgroundTransparency = 1
    signLabel.TextColor3 = Color3.fromRGB(230, 210, 170)
    signLabel.Text = buildingType:gsub("(%u)", " %1"):sub(2) -- Add spaces before capitals
    signLabel.TextScaled = true
    signLabel.Font = Enum.Font.GothamBold
    signLabel.Parent = signBg

    -- Set primary part and rotate
    model.PrimaryPart = foundation
    if rotation ~= 0 then
        model:SetPrimaryPartCFrame(CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0))
    end

    return model
end

--[[
    Creates all buildings in the village.
]]
local function createBuildings()
    for buildingType, buildingData in VillageLayout.Buildings do
        local worldPos = VillageLayout.GetWorldPosition(buildingData.position)
        local building = createBuilding(buildingType, worldPos, buildingData.rotation)
        building.Parent = _buildingsFolder
    end
end

-- ============================================================================
-- FARM ZONE CREATION
-- ============================================================================

--[[
    Creates a wooden fence section.
]]
local function createFence(startPos: Vector3, endPos: Vector3, parent: Folder): Model
    local fence = Instance.new("Model")
    fence.Name = "Fence"

    local direction = (endPos - startPos).Unit
    local length = (endPos - startPos).Magnitude
    local numPosts = math.floor(length / 3) + 1

    -- Fence posts
    for i = 0, numPosts - 1 do
        local postPos = startPos + direction * (i * 3)

        local post = Instance.new("Part")
        post.Name = "Post"
        post.Size = Vector3.new(0.4, 2.5, 0.4)
        post.Position = postPos + Vector3.new(0, 1.25, 0)
        post.Anchored = true
        post.Material = Materials.WoodLog
        post.Color = Colors.FenceWood
        post.Parent = fence

        -- Post cap
        local cap = Instance.new("Part")
        cap.Name = "Cap"
        cap.Size = Vector3.new(0.5, 0.2, 0.5)
        cap.Position = postPos + Vector3.new(0, 2.6, 0)
        cap.Anchored = true
        cap.Material = Materials.Wood
        cap.Color = Colors.FenceWood
        cap.Parent = fence
    end

    -- Horizontal rails
    for railHeight = 0.6, 1.8, 0.6 do
        local rail = Instance.new("Part")
        rail.Name = "Rail"
        rail.Size = Vector3.new(length, 0.2, 0.15)
        rail.CFrame = CFrame.new(startPos + direction * (length/2) + Vector3.new(0, railHeight, 0), endPos)
        rail.Anchored = true
        rail.Material = Materials.Wood
        rail.Color = Colors.WoodLight
        rail.Parent = fence
    end

    fence.Parent = parent
    return fence
end

--[[
    Creates a wheat field with growing wheat.
]]
local function createWheatField(position: Vector3, size: Vector3, parent: Folder): Model
    local field = Instance.new("Model")
    field.Name = "WheatField"

    -- Soil base
    local soil = Instance.new("Part")
    soil.Name = "Soil"
    soil.Size = Vector3.new(size.X, 0.3, size.Z)
    soil.Position = position + Vector3.new(0, 0.15, 0)
    soil.Anchored = true
    soil.Material = Materials.Dirt
    soil.Color = Color3.fromRGB(100, 70, 45)
    soil.Parent = field

    -- Tilled rows
    local numRows = math.floor(size.X / 1.5)
    for i = 1, numRows do
        local rowX = position.X - size.X/2 + (i - 0.5) * (size.X / numRows)

        -- Row mound
        local row = Instance.new("Part")
        row.Name = "Row"
        row.Size = Vector3.new(0.8, 0.15, size.Z - 1)
        row.Position = Vector3.new(rowX, 0.38, position.Z)
        row.Anchored = true
        row.Material = Materials.Dirt
        row.Color = Color3.fromRGB(90, 60, 40)
        row.Parent = field

        -- Wheat stalks
        local numStalks = math.floor(size.Z / 1.2)
        for j = 1, numStalks do
            local stalkZ = position.Z - size.Z/2 + (j - 0.5) * (size.Z / numStalks)

            local stalk = Instance.new("Part")
            stalk.Name = "Wheat"
            stalk.Size = Vector3.new(0.15, 1.2 + math.random() * 0.4, 0.15)
            stalk.Position = Vector3.new(
                rowX + (math.random() - 0.5) * 0.3,
                0.45 + stalk.Size.Y/2,
                stalkZ + (math.random() - 0.5) * 0.3
            )
            stalk.Orientation = Vector3.new(math.random(-5, 5), math.random(0, 360), math.random(-5, 5))
            stalk.Anchored = true
            stalk.Material = Enum.Material.Grass
            stalk.Color = Colors.Wheat
            stalk.Parent = field

            -- Wheat head
            local head = Instance.new("Part")
            head.Name = "WheatHead"
            head.Size = Vector3.new(0.2, 0.35, 0.15)
            head.Position = stalk.Position + Vector3.new(0, stalk.Size.Y/2 + 0.15, 0)
            head.Anchored = true
            head.Material = Enum.Material.Grass
            head.Color = Color3.fromRGB(230, 200, 110)
            head.Parent = field
        end
    end

    -- Scarecrow
    local scarecrow = Instance.new("Model")
    scarecrow.Name = "Scarecrow"

    local pole = Instance.new("Part")
    pole.Name = "Pole"
    pole.Size = Vector3.new(0.3, 4, 0.3)
    pole.Position = position + Vector3.new(0, 2, 0)
    pole.Anchored = true
    pole.Material = Materials.WoodLog
    pole.Color = Colors.WoodBrown
    pole.Parent = scarecrow

    local arms = Instance.new("Part")
    arms.Name = "Arms"
    arms.Size = Vector3.new(3, 0.25, 0.25)
    arms.Position = position + Vector3.new(0, 3.2, 0)
    arms.Anchored = true
    arms.Material = Materials.Wood
    arms.Color = Colors.WoodBrown
    arms.Parent = scarecrow

    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(0.8, 0.8, 0.8)
    head.Position = position + Vector3.new(0, 4.2, 0)
    head.Anchored = true
    head.Material = Materials.Fabric
    head.Color = Color3.fromRGB(200, 180, 140)
    head.Shape = Enum.PartType.Ball
    head.Parent = scarecrow

    local hat = Instance.new("Part")
    hat.Name = "Hat"
    hat.Size = Vector3.new(1.2, 0.4, 1.2)
    hat.Position = position + Vector3.new(0, 4.7, 0)
    hat.Anchored = true
    hat.Material = Materials.Fabric
    hat.Color = Color3.fromRGB(100, 80, 50)
    hat.Shape = Enum.PartType.Cylinder
    hat.Orientation = Vector3.new(0, 0, 90)
    hat.Parent = scarecrow

    scarecrow.Parent = field
    field.Parent = parent
    return field
end

--[[
    Creates the stable with horse and cart.
]]
local function createStable(position: Vector3, parent: Folder): Model
    local stable = Instance.new("Model")
    stable.Name = "Stable"

    -- Stable structure
    local floor = Instance.new("Part")
    floor.Name = "Floor"
    floor.Size = Vector3.new(15, 0.3, 12)
    floor.Position = position + Vector3.new(0, 0.15, 0)
    floor.Anchored = true
    floor.Material = Materials.Wood
    floor.Color = Colors.WoodBrown
    floor.Parent = stable

    -- Support posts
    local postPositions = {
        Vector3.new(-6, 0, -5), Vector3.new(6, 0, -5),
        Vector3.new(-6, 0, 5), Vector3.new(6, 0, 5),
    }

    for _, postPos in postPositions do
        local post = Instance.new("Part")
        post.Name = "Post"
        post.Size = Vector3.new(0.6, 5, 0.6)
        post.Position = position + postPos + Vector3.new(0, 2.8, 0)
        post.Anchored = true
        post.Material = Materials.WoodLog
        post.Color = Colors.WoodBrown
        post.Parent = stable
    end

    -- Roof
    local roof = Instance.new("Part")
    roof.Name = "Roof"
    roof.Size = Vector3.new(16, 0.4, 14)
    roof.Position = position + Vector3.new(0, 5.5, 0)
    roof.Anchored = true
    roof.Material = Materials.Wood
    roof.Color = Color3.fromRGB(90, 60, 35)
    roof.Parent = stable

    -- Hay on floor
    for i = 1, 8 do
        local hay = Instance.new("Part")
        hay.Name = "Hay"
        hay.Size = Vector3.new(2 + math.random(), 0.5 + math.random() * 0.3, 2 + math.random())
        hay.Position = position + Vector3.new(
            -5 + math.random() * 3,
            0.5 + hay.Size.Y/2,
            -3 + math.random() * 6
        )
        hay.Anchored = true
        hay.Material = Enum.Material.Grass
        hay.Color = Colors.Hay
        hay.Parent = stable
    end

    -- Horse
    local horse = Instance.new("Model")
    horse.Name = "Horse"

    local horseBody = Instance.new("Part")
    horseBody.Name = "Body"
    horseBody.Size = Vector3.new(2, 2, 4)
    horseBody.Position = position + Vector3.new(3, 1.8, 0)
    horseBody.Anchored = true
    horseBody.Material = Enum.Material.SmoothPlastic
    horseBody.Color = Color3.fromRGB(120, 80, 50)
    horseBody.Parent = horse

    local horseHead = Instance.new("Part")
    horseHead.Name = "Head"
    horseHead.Size = Vector3.new(0.8, 1.2, 1.5)
    horseHead.Position = position + Vector3.new(3, 2.5, 2.5)
    horseHead.Orientation = Vector3.new(-20, 0, 0)
    horseHead.Anchored = true
    horseHead.Material = Enum.Material.SmoothPlastic
    horseHead.Color = Color3.fromRGB(120, 80, 50)
    horseHead.Parent = horse

    -- Horse legs
    for i = -1, 1, 2 do
        for j = -1, 1, 2 do
            local leg = Instance.new("Part")
            leg.Name = "Leg"
            leg.Size = Vector3.new(0.3, 1.5, 0.3)
            leg.Position = position + Vector3.new(3 + i * 0.6, 0.75, j * 1.3)
            leg.Anchored = true
            leg.Material = Enum.Material.SmoothPlastic
            leg.Color = Color3.fromRGB(120, 80, 50)
            leg.Parent = horse
        end
    end

    horse.Parent = stable

    -- Cart
    local cart = Instance.new("Model")
    cart.Name = "Cart"

    local cartBed = Instance.new("Part")
    cartBed.Name = "Bed"
    cartBed.Size = Vector3.new(3, 0.3, 5)
    cartBed.Position = position + Vector3.new(-4, 1.2, 0)
    cartBed.Anchored = true
    cartBed.Material = Materials.Wood
    cartBed.Color = Colors.WoodLight
    cartBed.Parent = cart

    -- Cart sides
    for side = -1, 1, 2 do
        local cartSide = Instance.new("Part")
        cartSide.Name = "Side"
        cartSide.Size = Vector3.new(0.2, 1, 5)
        cartSide.Position = position + Vector3.new(-4 + side * 1.4, 1.85, 0)
        cartSide.Anchored = true
        cartSide.Material = Materials.Wood
        cartSide.Color = Colors.WoodBrown
        cartSide.Parent = cart
    end

    -- Cart wheels
    for i = -1, 1, 2 do
        local wheel = Instance.new("Part")
        wheel.Name = "Wheel"
        wheel.Size = Vector3.new(0.3, 1.8, 1.8)
        wheel.Position = position + Vector3.new(-4 + 1.6, 0.9, i * 2)
        wheel.Anchored = true
        wheel.Material = Materials.Wood
        wheel.Color = Colors.WoodBrown
        wheel.Shape = Enum.PartType.Cylinder
        wheel.Parent = cart
    end

    cart.Parent = stable

    -- Water trough
    local trough = Instance.new("Part")
    trough.Name = "WaterTrough"
    trough.Size = Vector3.new(1.5, 0.8, 3)
    trough.Position = position + Vector3.new(5.5, 0.7, -3)
    trough.Anchored = true
    trough.Material = Materials.Wood
    trough.Color = Colors.WoodBrown
    trough.Parent = stable

    local water = Instance.new("Part")
    water.Name = "Water"
    water.Size = Vector3.new(1.3, 0.5, 2.8)
    water.Position = position + Vector3.new(5.5, 0.75, -3)
    water.Anchored = true
    water.Material = Enum.Material.Water
    water.Color = Color3.fromRGB(80, 120, 180)
    water.Transparency = 0.3
    water.Parent = stable

    stable.Parent = parent
    return stable
end

--[[
    Creates the complete farm zone.
]]
local function createFarmZone()
    -- Create stable
    local stablePos = VillageLayout.GetWorldPosition(VillageLayout.FarmZone.Stable.position)
    createStable(stablePos, _farmFolder)

    -- Create wheat fields with fences
    for fieldName, fieldData in pairs({
        WheatField1 = VillageLayout.FarmZone.WheatField1,
        WheatField2 = VillageLayout.FarmZone.WheatField2,
    }) do
        local fieldPos = VillageLayout.GetWorldPosition(fieldData.position)
        local fieldSize = fieldData.size

        -- Create wheat
        createWheatField(fieldPos, fieldSize, _farmFolder)

        -- Create fence around field
        if fieldData.fenced then
            local halfX = fieldSize.X / 2 + 1
            local halfZ = fieldSize.Z / 2 + 1

            -- Four sides of fence
            createFence(fieldPos + Vector3.new(-halfX, 0, -halfZ), fieldPos + Vector3.new(halfX, 0, -halfZ), _farmFolder)
            createFence(fieldPos + Vector3.new(halfX, 0, -halfZ), fieldPos + Vector3.new(halfX, 0, halfZ), _farmFolder)
            createFence(fieldPos + Vector3.new(halfX, 0, halfZ), fieldPos + Vector3.new(-halfX, 0, halfZ), _farmFolder)
            createFence(fieldPos + Vector3.new(-halfX, 0, halfZ), fieldPos + Vector3.new(-halfX, 0, -halfZ), _farmFolder)
        end
    end
end

-- ============================================================================
-- DECORATION CREATION
-- ============================================================================

--[[
    Creates a street lamp.
]]
local function createStreetLamp(position: Vector3, parent: Folder): Model
    local lamp = Instance.new("Model")
    lamp.Name = "StreetLamp"

    -- Pole
    local pole = Instance.new("Part")
    pole.Name = "Pole"
    pole.Size = Vector3.new(0.3, 4, 0.3)
    pole.Position = position + Vector3.new(0, 2, 0)
    pole.Anchored = true
    pole.Material = Materials.Metal
    pole.Color = Colors.MetalDark
    pole.Parent = lamp

    -- Lamp holder
    local holder = Instance.new("Part")
    holder.Name = "Holder"
    holder.Size = Vector3.new(0.8, 0.15, 0.8)
    holder.Position = position + Vector3.new(0, 4.1, 0)
    holder.Anchored = true
    holder.Material = Materials.Metal
    holder.Color = Colors.MetalDark
    holder.Parent = lamp

    -- Lantern
    local lantern = Instance.new("Part")
    lantern.Name = "Lantern"
    lantern.Size = Vector3.new(0.6, 0.8, 0.6)
    lantern.Position = position + Vector3.new(0, 4.6, 0)
    lantern.Anchored = true
    lantern.Material = Enum.Material.Glass
    lantern.Color = Color3.fromRGB(255, 200, 100)
    lantern.Transparency = 0.3
    lantern.Parent = lamp

    -- Light
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 200, 120)
    light.Brightness = 1.5
    light.Range = 20
    light.Parent = lantern

    lamp.Parent = parent
    return lamp
end

--[[
    Creates a barrel.
]]
local function createBarrel(position: Vector3, parent: Folder): Part
    local barrel = Instance.new("Part")
    barrel.Name = "Barrel"
    barrel.Size = Vector3.new(1.2, 1.5, 1.2)
    barrel.Position = position + Vector3.new(0, 0.75, 0)
    barrel.Anchored = true
    barrel.Material = Materials.Wood
    barrel.Color = Colors.WoodBrown
    barrel.Shape = Enum.PartType.Cylinder
    barrel.Orientation = Vector3.new(0, 0, 0)
    barrel.Parent = parent
    return barrel
end

--[[
    Creates a crate.
]]
local function createCrate(position: Vector3, parent: Folder): Part
    local crate = Instance.new("Part")
    crate.Name = "Crate"
    crate.Size = Vector3.new(1 + math.random() * 0.5, 1 + math.random() * 0.3, 1 + math.random() * 0.5)
    crate.Position = position + Vector3.new(0, crate.Size.Y/2, 0)
    crate.Orientation = Vector3.new(0, math.random(0, 45), 0)
    crate.Anchored = true
    crate.Material = Materials.Wood
    crate.Color = Colors.WoodLight
    crate.Parent = parent
    return crate
end

--[[
    Creates a well.
]]
local function createWell(position: Vector3, parent: Folder): Model
    local well = Instance.new("Model")
    well.Name = "Well"

    -- Base
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(3, 1.5, 3)
    base.Position = position + Vector3.new(0, 0.75, 0)
    base.Anchored = true
    base.Material = Materials.Cobblestone
    base.Color = Colors.StoneGray
    base.Shape = Enum.PartType.Cylinder
    base.Parent = well

    -- Roof supports
    for i = -1, 1, 2 do
        local support = Instance.new("Part")
        support.Name = "Support"
        support.Size = Vector3.new(0.3, 3, 0.3)
        support.Position = position + Vector3.new(i * 1.2, 3, 0)
        support.Anchored = true
        support.Material = Materials.Wood
        support.Color = Colors.WoodBrown
        support.Parent = well
    end

    -- Roof beam
    local beam = Instance.new("Part")
    beam.Name = "Beam"
    beam.Size = Vector3.new(3, 0.3, 0.3)
    beam.Position = position + Vector3.new(0, 4.5, 0)
    beam.Anchored = true
    beam.Material = Materials.Wood
    beam.Color = Colors.WoodBrown
    beam.Parent = well

    -- Roof
    local roof = Instance.new("Part")
    roof.Name = "Roof"
    roof.Size = Vector3.new(4, 0.3, 3)
    roof.Position = position + Vector3.new(0, 5, 0)
    roof.Orientation = Vector3.new(15, 0, 0)
    roof.Anchored = true
    roof.Material = Materials.Wood
    roof.Color = Color3.fromRGB(90, 60, 35)
    roof.Parent = well

    -- Bucket
    local bucket = Instance.new("Part")
    bucket.Name = "Bucket"
    bucket.Size = Vector3.new(0.5, 0.6, 0.5)
    bucket.Position = position + Vector3.new(0, 2.5, 0)
    bucket.Anchored = true
    bucket.Material = Materials.Wood
    bucket.Color = Colors.WoodLight
    bucket.Parent = well

    -- Rope
    local rope = Instance.new("Part")
    rope.Name = "Rope"
    rope.Size = Vector3.new(0.1, 2, 0.1)
    rope.Position = position + Vector3.new(0, 3.8, 0)
    rope.Anchored = true
    rope.Material = Materials.Fabric
    rope.Color = Colors.Rope
    rope.Parent = well

    well.Parent = parent
    return well
end

--[[
    Creates a market stall.
]]
local function createMarketStall(position: Vector3, stallType: string, parent: Folder): Model
    local stall = Instance.new("Model")
    stall.Name = "MarketStall_" .. stallType

    -- Counter
    local counter = Instance.new("Part")
    counter.Name = "Counter"
    counter.Size = Vector3.new(4, 1, 2)
    counter.Position = position + Vector3.new(0, 0.5, 0)
    counter.Anchored = true
    counter.Material = Materials.Wood
    counter.Color = Colors.WoodBrown
    counter.Parent = stall

    -- Canopy supports
    for i = -1, 1, 2 do
        local support = Instance.new("Part")
        support.Name = "Support"
        support.Size = Vector3.new(0.2, 2.5, 0.2)
        support.Position = position + Vector3.new(i * 1.8, 2.25, 0.8)
        support.Anchored = true
        support.Material = Materials.Wood
        support.Color = Colors.WoodBrown
        support.Parent = stall
    end

    -- Canopy
    local canopy = Instance.new("Part")
    canopy.Name = "Canopy"
    canopy.Size = Vector3.new(4.5, 0.2, 2.5)
    canopy.Position = position + Vector3.new(0, 3.5, 0.5)
    canopy.Orientation = Vector3.new(-10, 0, 0)
    canopy.Anchored = true
    canopy.Material = Materials.Fabric
    canopy.Color = stallType == "produce" and Color3.fromRGB(180, 60, 60) or Color3.fromRGB(60, 100, 160)
    canopy.Parent = stall

    -- Goods on counter
    if stallType == "produce" then
        for i = 1, 5 do
            local item = Instance.new("Part")
            item.Name = "Produce"
            item.Size = Vector3.new(0.4, 0.4, 0.4)
            item.Position = position + Vector3.new(-1.5 + i * 0.6, 1.2, 0)
            item.Anchored = true
            item.Material = Enum.Material.SmoothPlastic
            item.Color = Color3.fromRGB(
                math.random(180, 255),
                math.random(50, 150),
                math.random(50, 100)
            )
            item.Shape = Enum.PartType.Ball
            item.Parent = stall
        end
    else
        for i = 1, 3 do
            local crate = Instance.new("Part")
            crate.Name = "Goods"
            crate.Size = Vector3.new(0.8, 0.6, 0.8)
            crate.Position = position + Vector3.new(-1 + i * 0.9, 1.3, 0)
            crate.Anchored = true
            crate.Material = Materials.Wood
            crate.Color = Colors.WoodLight
            crate.Parent = stall
        end
    end

    stall.Parent = parent
    return stall
end

--[[
    Creates all decorations.
]]
local function createDecorations()
    local decorData = VillageLayout.Decorations

    -- Well
    if decorData.Well then
        local wellPos = VillageLayout.GetWorldPosition(decorData.Well.position)
        createWell(wellPos, _decorationsFolder)
    end

    -- Street lamps
    for _, lampData in decorData.StreetLamps do
        local lampPos = VillageLayout.GetWorldPosition(lampData.position)
        createStreetLamp(lampPos, _decorationsFolder)
    end

    -- Barrels
    for _, barrelData in decorData.Barrels do
        local barrelPos = VillageLayout.GetWorldPosition(barrelData.position)
        createBarrel(barrelPos, _decorationsFolder)
    end

    -- Crates
    for _, crateData in decorData.Crates do
        local cratePos = VillageLayout.GetWorldPosition(crateData.position)
        createCrate(cratePos, _decorationsFolder)
    end

    -- Market stalls
    for _, stallData in decorData.MarketStalls do
        local stallPos = VillageLayout.GetWorldPosition(stallData.position)
        createMarketStall(stallPos, stallData.type, _decorationsFolder)
    end
end

-- ============================================================================
-- GROUND CREATION
-- ============================================================================

--[[
    Creates the base ground for the village.
    Covers entire village area with cobblestone, grass surrounds.
]]
local function createGround()
    local center = VillageLayout.Bounds.CenterOffset

    -- Main grass ground (larger surrounding area)
    local grass = Instance.new("Part")
    grass.Name = "GrassGround"
    grass.Size = Vector3.new(180, 2, 180)
    grass.Position = center + Vector3.new(0, -1, 15)
    grass.Anchored = true
    grass.Material = Materials.Grass
    grass.Color = Color3.fromRGB(80, 140, 50)
    grass.Parent = _villageFolder

    -- Village center cobblestone (entire building area - strip mall style)
    -- This creates the cohesive cobblestone base the user wanted
    local villageGround = Instance.new("Part")
    villageGround.Name = "VillageGround"
    villageGround.Size = Vector3.new(85, 0.15, 40)  -- Covers both building rows
    villageGround.Position = center + Vector3.new(3, 0.075, -6)
    villageGround.Anchored = true
    villageGround.Material = Materials.Cobblestone
    villageGround.Color = Colors.CobblestoneWorn
    villageGround.Parent = _villageFolder

    -- Transition zone (worn cobblestone leading to farm)
    local transitionGround = Instance.new("Part")
    transitionGround.Name = "TransitionGround"
    transitionGround.Size = Vector3.new(30, 0.12, 20)
    transitionGround.Position = center + Vector3.new(0, 0.06, 18)
    transitionGround.Anchored = true
    transitionGround.Material = Materials.Cobblestone
    transitionGround.Color = Colors.CobblestoneWorn
    transitionGround.Parent = _villageFolder

    -- Farm area ground (dirt)
    local farmGround = Instance.new("Part")
    farmGround.Name = "FarmGround"
    farmGround.Size = Vector3.new(60, 0.1, 45)
    farmGround.Position = center + Vector3.new(0, 0.05, 45)
    farmGround.Anchored = true
    farmGround.Material = Materials.Dirt
    farmGround.Color = Colors.Dirt
    farmGround.Parent = _villageFolder
end

-- ============================================================================
-- DEFENSE ZONE CREATION
-- ============================================================================

--[[
    Creates a cannon defense structure.
]]
local function createCannon(position: Vector3, rotation: number, parent: Folder): Model
    local cannon = Instance.new("Model")
    cannon.Name = "Cannon"

    -- Base platform
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(4, 0.5, 4)
    base.Position = position + Vector3.new(0, 0.25, 0)
    base.Anchored = true
    base.Material = Materials.Cobblestone
    base.Color = Colors.StoneDark
    base.Parent = cannon

    -- Cannon mount
    local mount = Instance.new("Part")
    mount.Name = "Mount"
    mount.Size = Vector3.new(2, 1, 2)
    mount.Position = position + Vector3.new(0, 1, 0)
    mount.Anchored = true
    mount.Material = Materials.Wood
    mount.Color = Colors.WoodBrown
    mount.Parent = cannon

    -- Cannon barrel
    local barrel = Instance.new("Part")
    barrel.Name = "Barrel"
    barrel.Size = Vector3.new(1.2, 1.2, 3)
    barrel.Position = position + Vector3.new(0, 1.5, 1)
    barrel.Orientation = Vector3.new(-15, 0, 0)
    barrel.Anchored = true
    barrel.Material = Materials.Metal
    barrel.Color = Color3.fromRGB(50, 50, 55)
    barrel.Shape = Enum.PartType.Cylinder
    barrel.Parent = cannon

    cannon.PrimaryPart = base
    if rotation ~= 0 then
        cannon:SetPrimaryPartCFrame(CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0))
    end

    cannon.Parent = parent
    return cannon
end

--[[
    Creates an archer tower.
]]
local function createArcherTower(position: Vector3, rotation: number, parent: Folder): Model
    local tower = Instance.new("Model")
    tower.Name = "ArcherTower"

    -- Base
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(5, 1, 5)
    base.Position = position + Vector3.new(0, 0.5, 0)
    base.Anchored = true
    base.Material = Materials.Stone
    base.Color = Colors.StoneDark
    base.Parent = tower

    -- Tower body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(4, 8, 4)
    body.Position = position + Vector3.new(0, 5, 0)
    body.Anchored = true
    body.Material = Materials.Brick
    body.Color = Color3.fromRGB(130, 110, 95)
    body.Parent = tower

    -- Platform at top
    local platform = Instance.new("Part")
    platform.Name = "Platform"
    platform.Size = Vector3.new(6, 0.5, 6)
    platform.Position = position + Vector3.new(0, 9.25, 0)
    platform.Anchored = true
    platform.Material = Materials.Wood
    platform.Color = Colors.WoodBrown
    platform.Parent = tower

    -- Battlements
    for i = -1, 1, 2 do
        for j = -1, 1, 2 do
            local battlement = Instance.new("Part")
            battlement.Name = "Battlement"
            battlement.Size = Vector3.new(1.5, 1.5, 1.5)
            battlement.Position = position + Vector3.new(i * 2.25, 10.25, j * 2.25)
            battlement.Anchored = true
            battlement.Material = Materials.Brick
            battlement.Color = Color3.fromRGB(120, 100, 85)
            battlement.Parent = tower
        end
    end

    -- Pointed roof
    local roof = Instance.new("Part")
    roof.Name = "Roof"
    roof.Size = Vector3.new(5, 3, 5)
    roof.Position = position + Vector3.new(0, 12.5, 0)
    roof.Anchored = true
    roof.Material = Materials.Slate
    roof.Color = Color3.fromRGB(70, 65, 60)
    roof.Parent = tower

    tower.PrimaryPart = base
    tower.Parent = parent
    return tower
end

--[[
    Creates wall segments between points.
]]
local function createWallSegment(startPos: Vector3, endPos: Vector3, parent: Folder): Model
    local wall = Instance.new("Model")
    wall.Name = "Wall"

    local direction = (endPos - startPos).Unit
    local length = (endPos - startPos).Magnitude
    local midPoint = startPos + direction * (length / 2)

    -- Wall base
    local wallPart = Instance.new("Part")
    wallPart.Name = "WallSection"
    wallPart.Size = Vector3.new(length, 3, 1.5)
    wallPart.CFrame = CFrame.new(midPoint + Vector3.new(0, 1.5, 0), endPos + Vector3.new(0, 1.5, 0))
    wallPart.Anchored = true
    wallPart.Material = Materials.Stone
    wallPart.Color = Colors.StoneDark
    wallPart.Parent = wall

    -- Battlements on top
    local numBattlements = math.floor(length / 3)
    for i = 0, numBattlements - 1 do
        local battlement = Instance.new("Part")
        battlement.Name = "Battlement"
        battlement.Size = Vector3.new(1, 1, 1.6)
        battlement.Position = startPos + direction * (1.5 + i * 3) + Vector3.new(0, 3.5, 0)
        battlement.Anchored = true
        battlement.Material = Materials.Stone
        battlement.Color = Colors.StoneGray
        battlement.Parent = wall
    end

    wall.Parent = parent
    return wall
end

--[[
    Creates the complete defense zone.
]]
local function createDefenseZone()
    local defenseData = VillageLayout.DefenseZone

    -- Create cannons
    if defenseData.Cannon1 then
        local pos = VillageLayout.GetWorldPosition(defenseData.Cannon1.position)
        createCannon(pos, defenseData.Cannon1.rotation, _defenseFolder)
    end

    if defenseData.Cannon2 then
        local pos = VillageLayout.GetWorldPosition(defenseData.Cannon2.position)
        createCannon(pos, defenseData.Cannon2.rotation, _defenseFolder)
    end

    -- Create archer tower
    if defenseData.ArcherTower then
        local pos = VillageLayout.GetWorldPosition(defenseData.ArcherTower.position)
        createArcherTower(pos, defenseData.ArcherTower.rotation, _defenseFolder)
    end

    -- Create wall segments (avoiding gaps)
    if defenseData.WallStart and defenseData.WallEnd then
        local wallStart = VillageLayout.GetWorldPosition(defenseData.WallStart)
        local wallEnd = VillageLayout.GetWorldPosition(defenseData.WallEnd)

        -- If there are gaps, create segments around them
        if defenseData.WallGaps and #defenseData.WallGaps > 0 then
            local gapPos = VillageLayout.GetWorldPosition(defenseData.WallGaps[1])
            local gapWidth = 8 -- Gate width

            -- Left segment
            createWallSegment(wallStart, Vector3.new(gapPos.X - gapWidth/2, wallStart.Y, wallStart.Z), _defenseFolder)
            -- Right segment
            createWallSegment(Vector3.new(gapPos.X + gapWidth/2, wallEnd.Y, wallEnd.Z), wallEnd, _defenseFolder)
        else
            createWallSegment(wallStart, wallEnd, _defenseFolder)
        end
    end
end

-- ============================================================================
-- BOUNDARY & PERIMETER CREATION
-- ============================================================================

--[[
    Creates an invisible boundary wall to keep players in the village.
]]
local function createBoundaryWall(startPos: Vector3, endPos: Vector3, height: number, parent: Folder): Part
    local direction = (endPos - startPos).Unit
    local length = (endPos - startPos).Magnitude
    local midPoint = startPos + direction * (length / 2)

    local wall = Instance.new("Part")
    wall.Name = "BoundaryWall"
    wall.Size = Vector3.new(length, height, 1)
    wall.CFrame = CFrame.new(midPoint + Vector3.new(0, height/2, 0), endPos + Vector3.new(0, height/2, 0))
    wall.Anchored = true
    wall.Transparency = 1  -- Invisible
    wall.CanCollide = true
    wall.Parent = parent
    return wall
end

--[[
    Creates a medieval stone perimeter wall (visible).
]]
local function createPerimeterWall(startPos: Vector3, endPos: Vector3, parent: Folder): Model
    local wall = Instance.new("Model")
    wall.Name = "PerimeterWall"

    local direction = (endPos - startPos).Unit
    local length = (endPos - startPos).Magnitude
    local midPoint = startPos + direction * (length / 2)

    -- Main wall
    local wallPart = Instance.new("Part")
    wallPart.Name = "Wall"
    wallPart.Size = Vector3.new(length, 4, 2)
    wallPart.CFrame = CFrame.new(midPoint + Vector3.new(0, 2, 0), endPos + Vector3.new(0, 2, 0))
    wallPart.Anchored = true
    wallPart.Material = Materials.Stone
    wallPart.Color = Colors.StoneDark
    wallPart.Parent = wall

    -- Battlements
    local numBattlements = math.floor(length / 2.5)
    for i = 0, numBattlements - 1 do
        local battlement = Instance.new("Part")
        battlement.Name = "Battlement"
        battlement.Size = Vector3.new(1.2, 1.2, 2.2)
        battlement.Position = startPos + direction * (1.25 + i * 2.5) + Vector3.new(0, 4.6, 0)
        battlement.Anchored = true
        battlement.Material = Materials.Stone
        battlement.Color = Colors.StoneGray
        battlement.Parent = wall
    end

    wall.Parent = parent
    return wall
end

--[[
    Creates a medieval gate structure.
]]
local function createGate(position: Vector3, rotation: number, parent: Folder): Model
    local gate = Instance.new("Model")
    gate.Name = "VillageGate"

    -- Left tower
    local leftTower = Instance.new("Part")
    leftTower.Name = "LeftTower"
    leftTower.Size = Vector3.new(4, 8, 4)
    leftTower.Position = position + Vector3.new(-5, 4, 0)
    leftTower.Anchored = true
    leftTower.Material = Materials.Stone
    leftTower.Color = Colors.StoneDark
    leftTower.Parent = gate

    -- Right tower
    local rightTower = Instance.new("Part")
    rightTower.Name = "RightTower"
    rightTower.Size = Vector3.new(4, 8, 4)
    rightTower.Position = position + Vector3.new(5, 4, 0)
    rightTower.Anchored = true
    rightTower.Material = Materials.Stone
    rightTower.Color = Colors.StoneDark
    rightTower.Parent = gate

    -- Gate arch
    local arch = Instance.new("Part")
    arch.Name = "Arch"
    arch.Size = Vector3.new(6, 2, 2)
    arch.Position = position + Vector3.new(0, 7, 0)
    arch.Anchored = true
    arch.Material = Materials.Stone
    arch.Color = Colors.StoneGray
    arch.Parent = gate

    -- Wooden gate doors
    for i = -1, 1, 2 do
        local door = Instance.new("Part")
        door.Name = "GateDoor"
        door.Size = Vector3.new(2.8, 5, 0.4)
        door.Position = position + Vector3.new(i * 1.5, 2.5, 0)
        door.Anchored = true
        door.Material = Materials.Wood
        door.Color = Colors.WoodBrown
        door.Parent = gate

        -- Door iron bands
        for j = 1, 3 do
            local band = Instance.new("Part")
            band.Name = "IronBand"
            band.Size = Vector3.new(2.6, 0.2, 0.5)
            band.Position = position + Vector3.new(i * 1.5, j * 1.5, 0)
            band.Anchored = true
            band.Material = Materials.Metal
            band.Color = Colors.IronDark
            band.Parent = gate
        end
    end

    -- Tower battlements
    for _, towerX in {-5, 5} do
        for dx = -1, 1, 2 do
            for dz = -1, 1, 2 do
                local battlement = Instance.new("Part")
                battlement.Name = "Battlement"
                battlement.Size = Vector3.new(1, 1.5, 1)
                battlement.Position = position + Vector3.new(towerX + dx * 1.2, 8.75, dz * 1.2)
                battlement.Anchored = true
                battlement.Material = Materials.Stone
                battlement.Color = Colors.StoneGray
                battlement.Parent = gate
            end
        end
    end

    -- Torches on gate
    for i = -1, 1, 2 do
        local torch = Instance.new("Part")
        torch.Name = "GateTorch"
        torch.Size = Vector3.new(0.2, 0.8, 0.2)
        torch.Position = position + Vector3.new(i * 3.5, 5, 1.5)
        torch.Anchored = true
        torch.Material = Materials.Wood
        torch.Color = Colors.WoodBrown
        torch.Parent = gate

        -- Fire effect
        local fire = Instance.new("ParticleEmitter")
        fire.Texture = "rbxasset://textures/particles/fire_main.dds"
        fire.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 50)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 20)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 50, 10)),
        })
        fire.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(0.5, 0.5),
            NumberSequenceKeypoint.new(1, 0.1),
        })
        fire.Lifetime = NumberRange.new(0.3, 0.6)
        fire.Rate = 30
        fire.Speed = NumberRange.new(2, 4)
        fire.SpreadAngle = Vector2.new(15, 15)
        fire.Parent = torch

        -- Torch light
        local light = Instance.new("PointLight")
        light.Color = Color3.fromRGB(255, 180, 80)
        light.Brightness = 2
        light.Range = 15
        light.Parent = torch
    end

    gate.PrimaryPart = arch
    if rotation ~= 0 then
        gate:SetPrimaryPartCFrame(CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0))
    end

    gate.Parent = parent
    return gate
end

--[[
    Creates the complete village boundary.
]]
local function createBoundary()
    local center = VillageLayout.Bounds.CenterOffset
    local bounds = VillageLayout.Bounds

    -- Invisible boundary walls (keeps players in)
    local boundaryHeight = 20
    local padding = 5

    -- North boundary
    createBoundaryWall(
        center + Vector3.new(bounds.MinX - padding, 0, bounds.MaxZ + padding),
        center + Vector3.new(bounds.MaxX + padding, 0, bounds.MaxZ + padding),
        boundaryHeight, _boundaryFolder
    )
    -- South boundary
    createBoundaryWall(
        center + Vector3.new(bounds.MinX - padding, 0, bounds.MinZ - padding),
        center + Vector3.new(bounds.MaxX + padding, 0, bounds.MinZ - padding),
        boundaryHeight, _boundaryFolder
    )
    -- East boundary
    createBoundaryWall(
        center + Vector3.new(bounds.MaxX + padding, 0, bounds.MinZ - padding),
        center + Vector3.new(bounds.MaxX + padding, 0, bounds.MaxZ + padding),
        boundaryHeight, _boundaryFolder
    )
    -- West boundary
    createBoundaryWall(
        center + Vector3.new(bounds.MinX - padding, 0, bounds.MinZ - padding),
        center + Vector3.new(bounds.MinX - padding, 0, bounds.MaxZ + padding),
        boundaryHeight, _boundaryFolder
    )

    -- Visible perimeter walls (medieval stone walls around village)
    -- East wall
    createPerimeterWall(
        center + Vector3.new(bounds.MaxX - 5, 0, bounds.MinZ + 10),
        center + Vector3.new(bounds.MaxX - 5, 0, 20),
        _boundaryFolder
    )
    -- West wall
    createPerimeterWall(
        center + Vector3.new(bounds.MinX + 5, 0, bounds.MinZ + 10),
        center + Vector3.new(bounds.MinX + 5, 0, 20),
        _boundaryFolder
    )

    -- Main gate (south entrance)
    local gatePos = VillageLayout.GetWorldPosition(Vector3.new(0, 0, -35))
    createGate(gatePos, 0, _boundaryFolder)
end

-- ============================================================================
-- TREES & VEGETATION
-- ============================================================================

--[[
    Creates a medieval-style tree.
]]
local function createTree(position: Vector3, parent: Folder): Model
    local tree = Instance.new("Model")
    tree.Name = "Tree"

    -- Trunk
    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Size = Vector3.new(1.5, 6 + math.random() * 2, 1.5)
    trunk.Position = position + Vector3.new(0, trunk.Size.Y/2, 0)
    trunk.Anchored = true
    trunk.Material = Materials.WoodLog
    trunk.Color = Colors.TreeTrunk
    trunk.Shape = Enum.PartType.Cylinder
    trunk.Orientation = Vector3.new(0, 0, 90)
    trunk.Parent = tree

    -- Foliage layers
    local trunkTop = position.Y + trunk.Size.Y
    for layer = 1, 3 do
        local foliage = Instance.new("Part")
        foliage.Name = "Foliage"
        foliage.Size = Vector3.new(
            6 - layer * 1.5,
            2,
            6 - layer * 1.5
        )
        foliage.Position = Vector3.new(position.X, trunkTop + layer * 1.5, position.Z)
        foliage.Anchored = true
        foliage.Material = Enum.Material.Grass
        foliage.Color = Color3.fromRGB(
            Colors.TreeLeaves.R * 255 + math.random(-15, 15),
            Colors.TreeLeaves.G * 255 + math.random(-15, 15),
            Colors.TreeLeaves.B * 255 + math.random(-10, 10)
        )
        foliage.Shape = Enum.PartType.Ball
        foliage.Parent = tree
    end

    tree.Parent = parent
    return tree
end

--[[
    Creates trees around the village.
]]
local function createTrees()
    local center = VillageLayout.Bounds.CenterOffset

    -- Tree positions around the village perimeter
    local treePositions = {
        -- Along east side
        Vector3.new(35, 0, -20),
        Vector3.new(38, 0, -5),
        Vector3.new(36, 0, 10),
        Vector3.new(35, 0, 25),
        -- Along west side
        Vector3.new(-30, 0, -20),
        Vector3.new(-32, 0, -5),
        Vector3.new(-30, 0, 10),
        Vector3.new(-28, 0, 25),
        -- Near farm
        Vector3.new(-30, 0, 40),
        Vector3.new(30, 0, 40),
        Vector3.new(-35, 0, 55),
        Vector3.new(35, 0, 55),
        -- Scattered
        Vector3.new(-25, 0, 35),
        Vector3.new(25, 0, 35),
    }

    for _, pos in treePositions do
        local worldPos = center + pos
        createTree(worldPos, _treesFolder)
    end
end

-- ============================================================================
-- TORCHES & LIGHTING
-- ============================================================================

--[[
    Creates a wall-mounted torch.
]]
local function createWallTorch(position: Vector3, parent: Instance): Model
    local torch = Instance.new("Model")
    torch.Name = "WallTorch"

    -- Bracket
    local bracket = Instance.new("Part")
    bracket.Name = "Bracket"
    bracket.Size = Vector3.new(0.15, 0.15, 0.4)
    bracket.Position = position
    bracket.Anchored = true
    bracket.Material = Materials.Metal
    bracket.Color = Colors.IronDark
    bracket.Parent = torch

    -- Torch handle
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.15, 0.6, 0.15)
    handle.Position = position + Vector3.new(0, 0.3, 0.2)
    handle.Orientation = Vector3.new(-20, 0, 0)
    handle.Anchored = true
    handle.Material = Materials.Wood
    handle.Color = Colors.WoodBrown
    handle.Parent = torch

    -- Flame holder
    local holder = Instance.new("Part")
    holder.Name = "FlameHolder"
    holder.Size = Vector3.new(0.25, 0.3, 0.25)
    holder.Position = position + Vector3.new(0, 0.7, 0.3)
    holder.Anchored = true
    holder.Material = Materials.Fabric
    holder.Color = Color3.fromRGB(80, 60, 40)
    holder.Parent = torch

    -- Fire particle
    local fire = Instance.new("ParticleEmitter")
    fire.Texture = "rbxasset://textures/particles/fire_main.dds"
    fire.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 80)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 30)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 60, 20)),
    })
    fire.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.5, 0.35),
        NumberSequenceKeypoint.new(1, 0.1),
    })
    fire.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    fire.Lifetime = NumberRange.new(0.2, 0.5)
    fire.Rate = 25
    fire.Speed = NumberRange.new(1, 3)
    fire.SpreadAngle = Vector2.new(10, 10)
    fire.Parent = holder

    -- Warm light
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 180, 80)
    light.Brightness = 1.5
    light.Range = 12
    light.Shadows = true
    light.Parent = holder

    torch.Parent = parent
    return torch
end

--[[
    Creates a fire brazier (outdoor fire pit).
]]
local function createBrazier(position: Vector3, parent: Folder): Model
    local brazier = Instance.new("Model")
    brazier.Name = "Brazier"

    -- Base stand
    local stand = Instance.new("Part")
    stand.Name = "Stand"
    stand.Size = Vector3.new(1.5, 0.3, 1.5)
    stand.Position = position + Vector3.new(0, 0.15, 0)
    stand.Anchored = true
    stand.Material = Materials.Metal
    stand.Color = Colors.IronDark
    stand.Parent = brazier

    -- Bowl
    local bowl = Instance.new("Part")
    bowl.Name = "Bowl"
    bowl.Size = Vector3.new(1.2, 0.8, 1.2)
    bowl.Position = position + Vector3.new(0, 0.7, 0)
    bowl.Anchored = true
    bowl.Material = Materials.Metal
    bowl.Color = Colors.MetalDark
    bowl.Shape = Enum.PartType.Cylinder
    bowl.Parent = brazier

    -- Fire
    local fireBase = Instance.new("Part")
    fireBase.Name = "FireBase"
    fireBase.Size = Vector3.new(0.8, 0.3, 0.8)
    fireBase.Position = position + Vector3.new(0, 1, 0)
    fireBase.Anchored = true
    fireBase.Transparency = 1
    fireBase.CanCollide = false
    fireBase.Parent = brazier

    local fire = Instance.new("ParticleEmitter")
    fire.Texture = "rbxasset://textures/particles/fire_main.dds"
    fire.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 100)),
        ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 150, 50)),
        ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 80, 20)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 30, 10)),
    })
    fire.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.3, 0.6),
        NumberSequenceKeypoint.new(0.7, 0.4),
        NumberSequenceKeypoint.new(1, 0.1),
    })
    fire.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.8, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    fire.Lifetime = NumberRange.new(0.5, 1)
    fire.Rate = 40
    fire.Speed = NumberRange.new(2, 5)
    fire.SpreadAngle = Vector2.new(20, 20)
    fire.Parent = fireBase

    -- Bright light
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 160, 60)
    light.Brightness = 3
    light.Range = 25
    light.Shadows = true
    light.Parent = fireBase

    brazier.Parent = parent
    return brazier
end

-- ============================================================================
-- FARM EQUIPMENT
-- ============================================================================

--[[
    Creates a wooden plow.
]]
local function createPlow(position: Vector3, parent: Folder): Model
    local plow = Instance.new("Model")
    plow.Name = "Plow"

    -- Main beam
    local beam = Instance.new("Part")
    beam.Name = "Beam"
    beam.Size = Vector3.new(0.3, 0.3, 4)
    beam.Position = position + Vector3.new(0, 0.5, 0)
    beam.Anchored = true
    beam.Material = Materials.Wood
    beam.Color = Colors.WoodBrown
    beam.Parent = plow

    -- Handles
    for i = -1, 1, 2 do
        local handle = Instance.new("Part")
        handle.Name = "Handle"
        handle.Size = Vector3.new(0.15, 1.5, 0.15)
        handle.Position = position + Vector3.new(i * 0.4, 1.1, -1.5)
        handle.Orientation = Vector3.new(-30, 0, 0)
        handle.Anchored = true
        handle.Material = Materials.Wood
        handle.Color = Colors.WoodLight
        handle.Parent = plow
    end

    -- Blade
    local blade = Instance.new("Part")
    blade.Name = "Blade"
    blade.Size = Vector3.new(1, 0.8, 0.1)
    blade.Position = position + Vector3.new(0, 0.2, 1.8)
    blade.Orientation = Vector3.new(45, 0, 0)
    blade.Anchored = true
    blade.Material = Materials.Metal
    blade.Color = Colors.IronDark
    blade.Parent = plow

    plow.Parent = parent
    return plow
end

--[[
    Creates a wheelbarrow.
]]
local function createWheelbarrow(position: Vector3, parent: Folder): Model
    local wb = Instance.new("Model")
    wb.Name = "Wheelbarrow"

    -- Wheel
    local wheel = Instance.new("Part")
    wheel.Name = "Wheel"
    wheel.Size = Vector3.new(0.2, 1.2, 1.2)
    wheel.Position = position + Vector3.new(0, 0.6, 1)
    wheel.Anchored = true
    wheel.Material = Materials.Wood
    wheel.Color = Colors.WoodBrown
    wheel.Shape = Enum.PartType.Cylinder
    wheel.Parent = wb

    -- Tray
    local tray = Instance.new("Part")
    tray.Name = "Tray"
    tray.Size = Vector3.new(1.5, 0.6, 2)
    tray.Position = position + Vector3.new(0, 0.8, 0)
    tray.Orientation = Vector3.new(10, 0, 0)
    tray.Anchored = true
    tray.Material = Materials.Wood
    tray.Color = Colors.WoodLight
    tray.Parent = wb

    -- Handles
    for i = -1, 1, 2 do
        local handle = Instance.new("Part")
        handle.Name = "Handle"
        handle.Size = Vector3.new(0.1, 0.1, 1.5)
        handle.Position = position + Vector3.new(i * 0.6, 0.7, -1.2)
        handle.Anchored = true
        handle.Material = Materials.Wood
        handle.Color = Colors.WoodBrown
        handle.Parent = wb
    end

    -- Legs
    for i = -1, 1, 2 do
        local leg = Instance.new("Part")
        leg.Name = "Leg"
        leg.Size = Vector3.new(0.1, 0.5, 0.1)
        leg.Position = position + Vector3.new(i * 0.5, 0.25, -0.8)
        leg.Anchored = true
        leg.Material = Materials.Wood
        leg.Color = Colors.WoodBrown
        leg.Parent = wb
    end

    wb.Parent = parent
    return wb
end

--[[
    Creates hay bales.
]]
local function createHayBale(position: Vector3, parent: Folder): Part
    local bale = Instance.new("Part")
    bale.Name = "HayBale"
    bale.Size = Vector3.new(2, 1.5, 1.5)
    bale.Position = position + Vector3.new(0, 0.75, 0)
    bale.Orientation = Vector3.new(0, math.random(0, 45), 0)
    bale.Anchored = true
    bale.Material = Enum.Material.Grass
    bale.Color = Colors.Hay
    bale.Shape = Enum.PartType.Cylinder
    bale.Parent = parent
    return bale
end

-- ============================================================================
-- BANNERS & FLAGS
-- ============================================================================

--[[
    Creates a medieval banner.
]]
local function createBanner(position: Vector3, bannerColor: Color3, parent: Instance): Model
    local banner = Instance.new("Model")
    banner.Name = "Banner"

    -- Pole
    local pole = Instance.new("Part")
    pole.Name = "Pole"
    pole.Size = Vector3.new(0.2, 5, 0.2)
    pole.Position = position + Vector3.new(0, 2.5, 0)
    pole.Anchored = true
    pole.Material = Materials.Wood
    pole.Color = Colors.WoodBrown
    pole.Parent = banner

    -- Flag fabric
    local flag = Instance.new("Part")
    flag.Name = "Flag"
    flag.Size = Vector3.new(2, 3, 0.1)
    flag.Position = position + Vector3.new(1.1, 3.5, 0)
    flag.Anchored = true
    flag.Material = Materials.Fabric
    flag.Color = bannerColor
    flag.Parent = banner

    -- Gold trim at top
    local trim = Instance.new("Part")
    trim.Name = "Trim"
    trim.Size = Vector3.new(2, 0.2, 0.12)
    trim.Position = position + Vector3.new(1.1, 5, 0)
    trim.Anchored = true
    trim.Material = Materials.Metal
    trim.Color = Colors.BannerGold
    trim.Parent = banner

    -- Pole cap
    local cap = Instance.new("Part")
    cap.Name = "Cap"
    cap.Size = Vector3.new(0.4, 0.4, 0.4)
    cap.Position = position + Vector3.new(0, 5.2, 0)
    cap.Anchored = true
    cap.Material = Materials.Metal
    cap.Color = Colors.BannerGold
    cap.Shape = Enum.PartType.Ball
    cap.Parent = banner

    banner.Parent = parent
    return banner
end

-- ============================================================================
-- ENHANCED DECORATIONS
-- ============================================================================

--[[
    Adds torches, braziers, banners, and extra details.
]]
local function createEnhancedDecorations()
    local center = VillageLayout.Bounds.CenterOffset

    -- Braziers near main areas
    local brazierPositions = {
        Vector3.new(-12, 0, -9),  -- Near town center
        Vector3.new(12, 0, -9),
        Vector3.new(0, 0, -28),   -- Near gate
        Vector3.new(-8, 0, -28),
        Vector3.new(8, 0, -28),
    }

    for _, pos in brazierPositions do
        createBrazier(center + pos, _decorationsFolder)
    end

    -- Banners on Town Hall
    local townHallPos = VillageLayout.GetWorldPosition(VillageLayout.Buildings.TownHall.position)
    createBanner(townHallPos + Vector3.new(-5, 8, 7), Colors.BannerRed, _buildingsFolder)
    createBanner(townHallPos + Vector3.new(5, 8, 7), Colors.BannerRed, _buildingsFolder)

    -- Additional hay bales
    local hayPositions = {
        Vector3.new(-15, 0, 28),
        Vector3.new(-16, 0, 29),
        Vector3.new(12, 0, 26),
        Vector3.new(14, 0, 27),
    }

    for _, pos in hayPositions do
        createHayBale(center + pos, _farmFolder)
    end

    -- Farm equipment
    local stablePos = VillageLayout.GetWorldPosition(VillageLayout.FarmZone.Stable.position)
    createPlow(stablePos + Vector3.new(-10, 0, 5), _farmFolder)
    createWheelbarrow(stablePos + Vector3.new(-8, 0, -4), _farmFolder)
    createWheelbarrow(center + Vector3.new(8, 0, 30), _farmFolder)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Builds the entire village.
]]
function VillageBuilder.Build()
    -- Create folder structure
    _villageFolder = Instance.new("Folder")
    _villageFolder.Name = "Village"
    _villageFolder.Parent = workspace

    _streetsFolder = Instance.new("Folder")
    _streetsFolder.Name = "Streets"
    _streetsFolder.Parent = _villageFolder

    _buildingsFolder = Instance.new("Folder")
    _buildingsFolder.Name = "Buildings"
    _buildingsFolder.Parent = _villageFolder

    _farmFolder = Instance.new("Folder")
    _farmFolder.Name = "Farm"
    _farmFolder.Parent = _villageFolder

    _decorationsFolder = Instance.new("Folder")
    _decorationsFolder.Name = "Decorations"
    _decorationsFolder.Parent = _villageFolder

    _defenseFolder = Instance.new("Folder")
    _defenseFolder.Name = "Defenses"
    _defenseFolder.Parent = _villageFolder

    _boundaryFolder = Instance.new("Folder")
    _boundaryFolder.Name = "Boundary"
    _boundaryFolder.Parent = _villageFolder

    _treesFolder = Instance.new("Folder")
    _treesFolder.Name = "Trees"
    _treesFolder.Parent = _villageFolder

    -- Build everything
    print("Building medieval village...")

    createGround()
    print("  Ground created")

    createStreets()
    print("  Streets created")

    createBuildings()
    print("  Buildings created")

    createFarmZone()
    print("  Farm zone created")

    createDecorations()
    print("  Decorations created")

    createDefenseZone()
    print("  Defense zone created")

    createBoundary()
    print("  Boundary walls and gate created")

    createTrees()
    print("  Trees created")

    createEnhancedDecorations()
    print("  Torches, braziers, banners, and equipment created")

    print("Medieval village complete!")
end

--[[
    Destroys the village (for rebuilding).
]]
function VillageBuilder.Destroy()
    if _villageFolder then
        _villageFolder:Destroy()
        _villageFolder = nil
    end
end

return VillageBuilder
