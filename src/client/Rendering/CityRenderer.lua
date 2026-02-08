--!strict
--[[
    CityRenderer.lua

    Renders the player's city with buildings, grid, and visual effects.
    Manages 3D building models and placement preview.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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

-- Building instances by ID
local _buildingModels: {[string]: Model} = {}

-- Grid settings
local GRID_SIZE = 40
local CELL_SIZE = 3 -- studs per cell
local GRID_HEIGHT = 0.1

-- Placement preview
local _placementPreview: Model? = nil
local _placementValid = true

-- Selection highlight
local _selectionHighlight: SelectionBox? = nil
local _selectedBuildingId: string? = nil

-- Building colors by category
local BuildingColors = {
    townhall = Color3.fromRGB(255, 215, 0), -- Gold
    resource = Color3.fromRGB(139, 90, 43), -- Brown
    storage = Color3.fromRGB(100, 100, 100), -- Gray
    defense = Color3.fromRGB(139, 0, 0), -- Dark red
    army = Color3.fromRGB(0, 100, 0), -- Dark green
    wall = Color3.fromRGB(80, 80, 80), -- Dark gray
    decoration = Color3.fromRGB(50, 205, 50), -- Lime green
}

--[[
    Creates a placeholder building model.
    In production, this would load actual models from ReplicatedStorage.
]]
local function createBuildingModel(buildingType: string, level: number): Model
    local buildingDef = BuildingData.GetByType(buildingType)
    local model = Instance.new("Model")
    model.Name = buildingType

    -- Get size from building data or use defaults
    local sizeX = 1
    local sizeZ = 1
    if buildingDef then
        sizeX = buildingDef.size and buildingDef.size.x or 1
        sizeZ = buildingDef.size and buildingDef.size.z or 1
    end

    -- Create base part
    local basePart = Instance.new("Part")
    basePart.Name = "Base"
    basePart.Size = Vector3.new(sizeX * CELL_SIZE - 0.2, 0.5, sizeZ * CELL_SIZE - 0.2)
    basePart.Position = Vector3.new(0, 0.25, 0)
    basePart.Anchored = true
    basePart.CanCollide = true
    basePart.Material = Enum.Material.SmoothPlastic

    -- Color based on category
    local category = buildingDef and buildingDef.category or "resource"
    basePart.Color = BuildingColors[category] or Color3.fromRGB(128, 128, 128)
    basePart.Parent = model

    -- Create main structure
    local height = math.min(level * 0.5 + 1, 5) -- Height scales with level
    local mainPart = Instance.new("Part")
    mainPart.Name = "Main"
    mainPart.Size = Vector3.new(
        (sizeX * CELL_SIZE - 0.4) * 0.8,
        height,
        (sizeZ * CELL_SIZE - 0.4) * 0.8
    )
    mainPart.Position = Vector3.new(0, 0.5 + height / 2, 0)
    mainPart.Anchored = true
    mainPart.CanCollide = true
    mainPart.Material = Enum.Material.SmoothPlastic
    mainPart.Color = BuildingColors[category] or Color3.fromRGB(128, 128, 128)
    mainPart.Parent = model

    -- Add level indicator
    local levelGui = Instance.new("BillboardGui")
    levelGui.Name = "LevelGui"
    levelGui.Size = UDim2.new(0, 40, 0, 20)
    levelGui.StudsOffset = Vector3.new(0, height + 1, 0)
    levelGui.AlwaysOnTop = true
    levelGui.Parent = mainPart

    local levelLabel = Instance.new("TextLabel")
    levelLabel.Size = UDim2.new(1, 0, 1, 0)
    levelLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    levelLabel.BackgroundTransparency = 0.5
    levelLabel.TextColor3 = Color3.new(1, 1, 1)
    levelLabel.Text = "Lv." .. level
    levelLabel.TextScaled = true
    levelLabel.Font = Enum.Font.GothamBold
    levelLabel.Parent = levelGui

    -- Add click detector
    local clickDetector = Instance.new("ClickDetector")
    clickDetector.MaxActivationDistance = 100
    clickDetector.Parent = basePart

    -- Set primary part
    model.PrimaryPart = basePart

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
    cell.Material = Enum.Material.SmoothPlastic
    cell.Transparency = 0.9
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
                Transparency = 0.95
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
    local basePart = model:FindFirstChild("Base")
    if basePart then
        local clickDetector = basePart:FindFirstChild("ClickDetector")
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
    _selectionHighlight.Color3 = Color3.fromRGB(0, 200, 255)
    _selectionHighlight.LineThickness = 0.05
    _selectionHighlight.SurfaceTransparency = 0.8
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
    local mainPart = model:FindFirstChild("Main")
    if not mainPart then return end

    local particles = Instance.new("ParticleEmitter")
    particles.Name = "UpgradeEffect"
    particles.Texture = "rbxassetid://0" -- Placeholder
    particles.Color = ColorSequence.new(Color3.fromRGB(255, 200, 0))
    particles.Size = NumberSequence.new(0.2)
    particles.Rate = 10
    particles.Lifetime = NumberRange.new(1, 2)
    particles.Speed = NumberRange.new(1, 3)
    particles.SpreadAngle = Vector2.new(360, 360)
    particles.Parent = mainPart

    -- Add construction indicator
    local constructGui = Instance.new("BillboardGui")
    constructGui.Name = "ConstructionGui"
    constructGui.Size = UDim2.new(0, 50, 0, 50)
    constructGui.StudsOffset = Vector3.new(0, mainPart.Size.Y + 1, 0)
    constructGui.AlwaysOnTop = true
    constructGui.Parent = mainPart

    local constructLabel = Instance.new("TextLabel")
    constructLabel.Size = UDim2.new(1, 0, 1, 0)
    constructLabel.BackgroundTransparency = 1
    constructLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
    constructLabel.Text = "🔨"
    constructLabel.TextScaled = true
    constructLabel.Parent = constructGui

    -- Animate
    task.spawn(function()
        while constructGui.Parent do
            constructLabel.Rotation = constructLabel.Rotation + 5
            task.wait(0.05)
        end
    end)
end

--[[
    Clears upgrade effect from a building.
]]
function CityRenderer:ClearUpgradeEffect(buildingId: string)
    local model = _buildingModels[buildingId]
    if not model then return end

    local mainPart = model:FindFirstChild("Main")
    if mainPart then
        local particles = mainPart:FindFirstChild("UpgradeEffect")
        if particles then particles:Destroy() end

        local constructGui = mainPart:FindFirstChild("ConstructionGui")
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
    billboardGui.Size = UDim2.new(0, 100, 0, 30)
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
    label.TextStrokeTransparency = 0.5
    label.Parent = billboardGui

    -- Animate up and fade
    local startOffset = billboardGui.StudsOffset
    local tween = TweenService:Create(billboardGui, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        StudsOffset = startOffset + Vector3.new(0, 2, 0)
    })
    tween:Play()

    TweenService:Create(label, TweenInfo.new(1), {
        TextTransparency = 1,
        TextStrokeTransparency = 1
    }):Play()

    task.delay(1, function()
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

    -- Create ground
    local ground = Instance.new("Part")
    ground.Name = "Ground"
    ground.Size = Vector3.new(GRID_SIZE * CELL_SIZE, 1, GRID_SIZE * CELL_SIZE)
    ground.Position = Vector3.new(GRID_SIZE * CELL_SIZE / 2, -0.5, GRID_SIZE * CELL_SIZE / 2)
    ground.Anchored = true
    ground.Material = Enum.Material.Grass
    ground.Color = Color3.fromRGB(76, 153, 0)
    ground.Parent = _cityFolder

    -- Create grid
    createGrid()
    self:HideGrid()

    _initialized = true
    print("CityRenderer initialized")
end

return CityRenderer
