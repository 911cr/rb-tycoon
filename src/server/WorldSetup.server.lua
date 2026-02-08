--!strict
--[[
    WorldSetup.server.lua

    Creates the basic world environment when the game starts.
    Adds baseplate, spawn location, and lighting.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

print("Setting up world...")

-- Create baseplate (grass-like ground)
local baseplate = Instance.new("Part")
baseplate.Name = "Baseplate"
baseplate.Size = Vector3.new(512, 4, 512)
baseplate.Position = Vector3.new(0, -2, 0)
baseplate.Anchored = true
baseplate.BrickColor = BrickColor.new("Bright green")
baseplate.Material = Enum.Material.Grass
baseplate.TopSurface = Enum.SurfaceType.Smooth
baseplate.BottomSurface = Enum.SurfaceType.Smooth
baseplate.Parent = Workspace

-- Create spawn location
local spawn = Instance.new("SpawnLocation")
spawn.Name = "SpawnLocation"
spawn.Size = Vector3.new(6, 1, 6)
spawn.Position = Vector3.new(0, 0.5, 0)
spawn.Anchored = true
spawn.BrickColor = BrickColor.new("Medium stone grey")
spawn.Material = Enum.Material.Concrete
spawn.TopSurface = Enum.SurfaceType.Smooth
spawn.BottomSurface = Enum.SurfaceType.Smooth
spawn.Parent = Workspace

-- Create a simple Town Hall placeholder at start
local townHall = Instance.new("Part")
townHall.Name = "TownHall_Preview"
townHall.Size = Vector3.new(16, 20, 16)
townHall.Position = Vector3.new(30, 10, 0)
townHall.Anchored = true
townHall.BrickColor = BrickColor.new("Nougat")
townHall.Material = Enum.Material.Brick
townHall.Parent = Workspace

local townHallLabel = Instance.new("BillboardGui")
townHallLabel.Name = "Label"
townHallLabel.Size = UDim2.new(0, 200, 0, 50)
townHallLabel.StudsOffset = Vector3.new(0, 12, 0)
townHallLabel.Parent = townHall

local labelText = Instance.new("TextLabel")
labelText.Size = UDim2.new(1, 0, 1, 0)
labelText.BackgroundTransparency = 1
labelText.TextColor3 = Color3.new(1, 1, 1)
labelText.TextStrokeTransparency = 0
labelText.TextScaled = true
labelText.Text = "Town Hall"
labelText.Font = Enum.Font.GothamBold
labelText.Parent = townHallLabel

-- Create some placeholder resource buildings
local function createPlaceholderBuilding(name: string, color: BrickColor, position: Vector3)
    local building = Instance.new("Part")
    building.Name = name .. "_Preview"
    building.Size = Vector3.new(8, 10, 8)
    building.Position = position
    building.Anchored = true
    building.BrickColor = color
    building.Material = Enum.Material.SmoothPlastic
    building.Parent = Workspace

    local label = Instance.new("BillboardGui")
    label.Name = "Label"
    label.Size = UDim2.new(0, 150, 0, 40)
    label.StudsOffset = Vector3.new(0, 7, 0)
    label.Parent = building

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, 0, 1, 0)
    text.BackgroundTransparency = 1
    text.TextColor3 = Color3.new(1, 1, 1)
    text.TextStrokeTransparency = 0
    text.TextScaled = true
    text.Text = name
    text.Font = Enum.Font.GothamBold
    text.Parent = label
end

createPlaceholderBuilding("Gold Mine", BrickColor.new("Bright yellow"), Vector3.new(-20, 5, 20))
createPlaceholderBuilding("Barracks", BrickColor.new("Bright red"), Vector3.new(-20, 5, -20))
createPlaceholderBuilding("Spell Factory", BrickColor.new("Bright violet"), Vector3.new(20, 5, -30))

-- Set up atmosphere
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.3
atmosphere.Color = Color3.fromRGB(199, 199, 199)
atmosphere.Decay = Color3.fromRGB(92, 60, 13)
atmosphere.Glare = 0
atmosphere.Haze = 1
atmosphere.Parent = Lighting

-- Set up sky
local sky = Instance.new("Sky")
sky.SunAngularSize = 11
sky.MoonAngularSize = 11
sky.Parent = Lighting

-- Add some ambient lighting
Lighting.Ambient = Color3.fromRGB(100, 100, 100)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
Lighting.ClockTime = 12 -- Noon

print("World setup complete!")
