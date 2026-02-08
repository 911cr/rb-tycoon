--!strict
--[[
    BattleRenderer.lua

    Renders battle scenes with enemy buildings, deployed troops, and effects.
    Visualizes combat in real-time based on server state updates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local BattleRenderer = {}
BattleRenderer.__index = BattleRenderer

-- Events
BattleRenderer.DeployPositionClicked = Signal.new()

-- Private state
local _initialized = false
local _isActive = false

-- Rendering containers
local _battleFolder: Folder
local _buildingsFolder: Folder
local _troopsFolder: Folder
local _effectsFolder: Folder
local _deployZone: Part

-- Model tracking
local _buildingModels: {[string]: Model} = {}
local _troopModels: {[string]: Model} = {}

-- Grid settings (matches city)
local GRID_SIZE = 40
local CELL_SIZE = 3

-- Troop colors by category
local TroopColors = {
    ground = Color3.fromRGB(100, 150, 255), -- Blue
    ranged = Color3.fromRGB(255, 100, 100), -- Red
    tank = Color3.fromRGB(100, 100, 100), -- Gray
    flying = Color3.fromRGB(255, 255, 100), -- Yellow
    siege = Color3.fromRGB(150, 100, 50), -- Brown
}

--[[
    Creates a placeholder troop model.
]]
local function createTroopModel(troopType: string, level: number): Model
    local troopDef = TroopData.GetByType(troopType)
    local model = Instance.new("Model")
    model.Name = troopType

    -- Size based on housing space
    local housingSpace = troopDef and troopDef.housingSpace or 1
    local scale = 0.5 + (housingSpace * 0.1)

    -- Create body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Shape = Enum.PartType.Ball
    body.Size = Vector3.new(scale, scale, scale)
    body.Position = Vector3.new(0, scale / 2, 0)
    body.Anchored = false
    body.CanCollide = true
    body.Material = Enum.Material.SmoothPlastic

    -- Color based on troop category
    local category = troopDef and troopDef.category or "ground"
    body.Color = TroopColors[category] or Color3.fromRGB(100, 150, 255)
    body.Parent = model

    -- Add health bar
    local healthGui = Instance.new("BillboardGui")
    healthGui.Name = "HealthGui"
    healthGui.Size = UDim2.new(0, 40, 0, 6)
    healthGui.StudsOffset = Vector3.new(0, scale + 0.3, 0)
    healthGui.AlwaysOnTop = true
    healthGui.Parent = body

    local healthBg = Instance.new("Frame")
    healthBg.Name = "Background"
    healthBg.Size = UDim2.new(1, 0, 1, 0)
    healthBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    healthBg.BorderSizePixel = 0
    healthBg.Parent = healthGui

    local healthBar = Instance.new("Frame")
    healthBar.Name = "HealthBar"
    healthBar.Size = UDim2.new(1, 0, 1, 0)
    healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    healthBar.BorderSizePixel = 0
    healthBar.Parent = healthBg

    -- Set primary part
    model.PrimaryPart = body

    return model
end

--[[
    Creates a damaged building model (enemy base).
]]
local function createEnemyBuilding(buildingType: string, level: number): Model
    local buildingDef = BuildingData.GetByType(buildingType)
    local model = Instance.new("Model")
    model.Name = buildingType

    -- Get size from building data
    local sizeX = buildingDef and buildingDef.size and buildingDef.size.x or 1
    local sizeZ = buildingDef and buildingDef.size and buildingDef.size.z or 1

    -- Create base
    local basePart = Instance.new("Part")
    basePart.Name = "Base"
    basePart.Size = Vector3.new(sizeX * CELL_SIZE - 0.2, 0.5, sizeZ * CELL_SIZE - 0.2)
    basePart.Position = Vector3.new(0, 0.25, 0)
    basePart.Anchored = true
    basePart.CanCollide = true
    basePart.Material = Enum.Material.SmoothPlastic
    basePart.Color = Color3.fromRGB(150, 80, 80) -- Reddish tint for enemy
    basePart.Parent = model

    -- Create main structure
    local height = math.min(level * 0.5 + 1, 5)
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
    mainPart.Color = Color3.fromRGB(150, 80, 80)
    mainPart.Parent = model

    -- Add health bar
    local healthGui = Instance.new("BillboardGui")
    healthGui.Name = "HealthGui"
    healthGui.Size = UDim2.new(0, 60, 0, 8)
    healthGui.StudsOffset = Vector3.new(0, height + 1, 0)
    healthGui.AlwaysOnTop = true
    healthGui.Parent = mainPart

    local healthBg = Instance.new("Frame")
    healthBg.Name = "Background"
    healthBg.Size = UDim2.new(1, 0, 1, 0)
    healthBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    healthBg.BorderSizePixel = 0
    healthBg.Parent = healthGui

    local healthBar = Instance.new("Frame")
    healthBar.Name = "HealthBar"
    healthBar.Size = UDim2.new(1, 0, 1, 0)
    healthBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    healthBar.BorderSizePixel = 0
    healthBar.Parent = healthBg

    model.PrimaryPart = basePart

    return model
end

--[[
    Creates the deploy zone indicator.
]]
local function createDeployZone()
    _deployZone = Instance.new("Part")
    _deployZone.Name = "DeployZone"
    _deployZone.Size = Vector3.new(GRID_SIZE * CELL_SIZE + 20, 0.1, 10)
    _deployZone.Position = Vector3.new(GRID_SIZE * CELL_SIZE / 2, 0.05, -5)
    _deployZone.Anchored = true
    _deployZone.CanCollide = false
    _deployZone.Material = Enum.Material.Neon
    _deployZone.Color = Color3.fromRGB(0, 200, 100)
    _deployZone.Transparency = 0.5
    _deployZone.Parent = _battleFolder

    -- Add click detection for deployment
    local clickDetector = Instance.new("ClickDetector")
    clickDetector.MaxActivationDistance = 200
    clickDetector.Parent = _deployZone

    clickDetector.MouseClick:Connect(function()
        local mouse = Players.LocalPlayer:GetMouse()
        BattleRenderer.DeployPositionClicked:Fire(Vector3.new(mouse.Hit.X, 0, mouse.Hit.Z))
    end)
end

--[[
    Activates the battle renderer.
]]
function BattleRenderer:Activate()
    if _isActive then return end
    _isActive = true

    _battleFolder.Parent = workspace
    print("[BattleRenderer] Activated")
end

--[[
    Deactivates the battle renderer.
]]
function BattleRenderer:Deactivate()
    if not _isActive then return end
    _isActive = false

    -- Clear all models
    for id in _buildingModels do
        self:RemoveBuilding(id)
    end
    for id in _troopModels do
        self:RemoveTroop(id)
    end

    _battleFolder.Parent = nil
    print("[BattleRenderer] Deactivated")
end

--[[
    Loads the enemy base layout.
]]
function BattleRenderer:LoadEnemyBase(buildings: {[string]: any})
    for id, data in buildings do
        self:RenderBuilding(id, data)
    end
end

--[[
    Renders an enemy building.
]]
function BattleRenderer:RenderBuilding(buildingId: string, buildingData: any)
    -- Remove existing
    if _buildingModels[buildingId] then
        _buildingModels[buildingId]:Destroy()
    end

    local model = createEnemyBuilding(buildingData.type, buildingData.level or 1)
    model.Name = buildingId

    -- Position
    local gridX = buildingData.position and buildingData.position.x or 0
    local gridZ = buildingData.position and buildingData.position.z or 0
    local worldPos = Vector3.new(
        gridX * CELL_SIZE + CELL_SIZE / 2,
        0,
        gridZ * CELL_SIZE + CELL_SIZE / 2
    )

    model:SetPrimaryPartCFrame(CFrame.new(worldPos))
    model.Parent = _buildingsFolder

    _buildingModels[buildingId] = model
end

--[[
    Removes a building (destroyed).
]]
function BattleRenderer:RemoveBuilding(buildingId: string)
    local model = _buildingModels[buildingId]
    if model then
        -- Destruction effect
        self:ShowDestructionEffect(model)
        model:Destroy()
        _buildingModels[buildingId] = nil
    end
end

--[[
    Updates building health display.
]]
function BattleRenderer:UpdateBuildingHealth(buildingId: string, healthPercent: number)
    local model = _buildingModels[buildingId]
    if not model then return end

    local mainPart = model:FindFirstChild("Main")
    if not mainPart then return end

    local healthGui = mainPart:FindFirstChild("HealthGui")
    if not healthGui then return end

    local healthBg = healthGui:FindFirstChild("Background")
    if not healthBg then return end

    local healthBar = healthBg:FindFirstChild("HealthBar")
    if healthBar then
        TweenService:Create(healthBar, TweenInfo.new(0.2), {
            Size = UDim2.new(math.clamp(healthPercent, 0, 1), 0, 1, 0)
        }):Play()

        -- Change color based on health
        if healthPercent > 0.5 then
            healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        elseif healthPercent > 0.25 then
            healthBar.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
        else
            healthBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end
end

--[[
    Renders a troop on the battlefield.
]]
function BattleRenderer:RenderTroop(troopId: string, troopData: any)
    -- Remove existing
    if _troopModels[troopId] then
        _troopModels[troopId]:Destroy()
    end

    local model = createTroopModel(troopData.type, troopData.level or 1)
    model.Name = troopId

    -- Position
    local position = troopData.position or Vector3.new(0, 0, 0)
    if typeof(position) == "table" then
        position = Vector3.new(position.x or 0, 0, position.z or 0)
    end

    model:SetPrimaryPartCFrame(CFrame.new(position + Vector3.new(0, 0.5, 0)))
    model.Parent = _troopsFolder

    _troopModels[troopId] = model

    -- Spawn animation
    local body = model:FindFirstChild("Body")
    if body then
        body.Size = Vector3.new(0.1, 0.1, 0.1)
        TweenService:Create(body, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
            Size = model.PrimaryPart and model.PrimaryPart.Size or Vector3.new(0.5, 0.5, 0.5)
        }):Play()
    end
end

--[[
    Updates troop position (movement).
]]
function BattleRenderer:UpdateTroopPosition(troopId: string, position: Vector3)
    local model = _troopModels[troopId]
    if not model or not model.PrimaryPart then return end

    local targetCFrame = CFrame.new(position + Vector3.new(0, model.PrimaryPart.Size.Y / 2, 0))

    TweenService:Create(model.PrimaryPart, TweenInfo.new(0.1), {
        CFrame = targetCFrame
    }):Play()
end

--[[
    Updates troop health display.
]]
function BattleRenderer:UpdateTroopHealth(troopId: string, healthPercent: number)
    local model = _troopModels[troopId]
    if not model then return end

    local body = model:FindFirstChild("Body")
    if not body then return end

    local healthGui = body:FindFirstChild("HealthGui")
    if not healthGui then return end

    local healthBg = healthGui:FindFirstChild("Background")
    if not healthBg then return end

    local healthBar = healthBg:FindFirstChild("HealthBar")
    if healthBar then
        TweenService:Create(healthBar, TweenInfo.new(0.1), {
            Size = UDim2.new(math.clamp(healthPercent, 0, 1), 0, 1, 0)
        }):Play()

        -- Color based on health
        if healthPercent > 0.5 then
            healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        elseif healthPercent > 0.25 then
            healthBar.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
        else
            healthBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end
end

--[[
    Removes a troop (died).
]]
function BattleRenderer:RemoveTroop(troopId: string)
    local model = _troopModels[troopId]
    if model then
        -- Death effect
        self:ShowDeathEffect(model)

        task.delay(0.3, function()
            if model then model:Destroy() end
        end)

        _troopModels[troopId] = nil
    end
end

--[[
    Shows building destruction effect.
]]
function BattleRenderer:ShowDestructionEffect(model: Model)
    local position = model.PrimaryPart and model.PrimaryPart.Position or Vector3.new(0, 0, 0)

    -- Create debris
    for i = 1, 5 do
        local debris = Instance.new("Part")
        debris.Size = Vector3.new(0.5, 0.5, 0.5)
        debris.Position = position + Vector3.new(
            math.random(-2, 2),
            math.random(1, 3),
            math.random(-2, 2)
        )
        debris.Color = Color3.fromRGB(100, 100, 100)
        debris.Material = Enum.Material.SmoothPlastic
        debris.Anchored = false
        debris.Parent = _effectsFolder

        -- Clean up after a while
        game:GetService("Debris"):AddItem(debris, 2)
    end

    -- Explosion effect (particle)
    local explosion = Instance.new("Part")
    explosion.Shape = Enum.PartType.Ball
    explosion.Size = Vector3.new(1, 1, 1)
    explosion.Position = position
    explosion.Color = Color3.fromRGB(255, 100, 0)
    explosion.Material = Enum.Material.Neon
    explosion.Anchored = true
    explosion.CanCollide = false
    explosion.Parent = _effectsFolder

    TweenService:Create(explosion, TweenInfo.new(0.3), {
        Size = Vector3.new(5, 5, 5),
        Transparency = 1
    }):Play()

    game:GetService("Debris"):AddItem(explosion, 0.5)
end

--[[
    Shows troop death effect.
]]
function BattleRenderer:ShowDeathEffect(model: Model)
    local body = model:FindFirstChild("Body")
    if body then
        TweenService:Create(body, TweenInfo.new(0.2), {
            Size = Vector3.new(0.1, 0.1, 0.1),
            Transparency = 1
        }):Play()
    end
end

--[[
    Shows spell effect at position.
]]
function BattleRenderer:ShowSpellEffect(spellType: string, position: Vector3, radius: number)
    local effect = Instance.new("Part")
    effect.Shape = Enum.PartType.Cylinder
    effect.Size = Vector3.new(0.1, radius * 2, radius * 2)
    effect.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
    effect.Anchored = true
    effect.CanCollide = false
    effect.Transparency = 0.5
    effect.Parent = _effectsFolder

    -- Color based on spell type
    if spellType == "Lightning" then
        effect.Color = Color3.fromRGB(255, 255, 0)
        effect.Material = Enum.Material.Neon
    elseif spellType == "Heal" then
        effect.Color = Color3.fromRGB(0, 255, 100)
        effect.Material = Enum.Material.Neon
    elseif spellType == "Rage" then
        effect.Color = Color3.fromRGB(255, 50, 50)
        effect.Material = Enum.Material.Neon
    elseif spellType == "Freeze" then
        effect.Color = Color3.fromRGB(100, 200, 255)
        effect.Material = Enum.Material.Glass
    else
        effect.Color = Color3.fromRGB(200, 100, 255)
        effect.Material = Enum.Material.Neon
    end

    -- Animate
    TweenService:Create(effect, TweenInfo.new(0.2), {
        Size = Vector3.new(0.3, radius * 2, radius * 2)
    }):Play()

    task.delay(2, function()
        TweenService:Create(effect, TweenInfo.new(0.5), {
            Transparency = 1
        }):Play()
        game:GetService("Debris"):AddItem(effect, 0.6)
    end)
end

--[[
    Shows attack line from troop to target.
]]
function BattleRenderer:ShowAttackEffect(fromPosition: Vector3, toPosition: Vector3)
    local distance = (toPosition - fromPosition).Magnitude
    local midPoint = (fromPosition + toPosition) / 2

    local beam = Instance.new("Part")
    beam.Size = Vector3.new(0.1, 0.1, distance)
    beam.CFrame = CFrame.lookAt(midPoint, toPosition)
    beam.Anchored = true
    beam.CanCollide = false
    beam.Color = Color3.fromRGB(255, 255, 0)
    beam.Material = Enum.Material.Neon
    beam.Parent = _effectsFolder

    TweenService:Create(beam, TweenInfo.new(0.1), {
        Transparency = 1
    }):Play()

    game:GetService("Debris"):AddItem(beam, 0.15)
end

--[[
    Initializes the BattleRenderer.
]]
function BattleRenderer:Init()
    if _initialized then
        warn("BattleRenderer already initialized")
        return
    end

    -- Create folder structure (not parented initially)
    _battleFolder = Instance.new("Folder")
    _battleFolder.Name = "Battle"

    _buildingsFolder = Instance.new("Folder")
    _buildingsFolder.Name = "Buildings"
    _buildingsFolder.Parent = _battleFolder

    _troopsFolder = Instance.new("Folder")
    _troopsFolder.Name = "Troops"
    _troopsFolder.Parent = _battleFolder

    _effectsFolder = Instance.new("Folder")
    _effectsFolder.Name = "Effects"
    _effectsFolder.Parent = _battleFolder

    -- Create ground
    local ground = Instance.new("Part")
    ground.Name = "Ground"
    ground.Size = Vector3.new(GRID_SIZE * CELL_SIZE + 40, 1, GRID_SIZE * CELL_SIZE + 40)
    ground.Position = Vector3.new(GRID_SIZE * CELL_SIZE / 2, -0.5, GRID_SIZE * CELL_SIZE / 2)
    ground.Anchored = true
    ground.Material = Enum.Material.Grass
    ground.Color = Color3.fromRGB(60, 120, 0) -- Slightly different from city
    ground.Parent = _battleFolder

    -- Create deploy zone
    createDeployZone()

    _initialized = true
    print("BattleRenderer initialized")
end

return BattleRenderer
