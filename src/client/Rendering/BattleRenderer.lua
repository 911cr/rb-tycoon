--!strict
--[[
    BattleRenderer.lua

    Renders battle scenes with enemy buildings, deployed troops, and effects.
    Visualizes combat in real-time based on server state updates.

    Connects to:
    - BattleArenaReady (RemoteEvent) - arena data from BattleArenaService
    - BattleStateUpdate (RemoteEvent) - per-tick combat state
    - BattleComplete (RemoteEvent) - battle results
    - ReturnToOverworld (RemoteEvent) - signal to restore camera

    Dependencies:
    - TroopData (for troop visual properties)
    - BuildingData (for building visual properties)
    - Signal (for internal events)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local BattleRenderer = {}
BattleRenderer.__index = BattleRenderer

-- Events
BattleRenderer.DeployPositionClicked = Signal.new()

-- Private state
local _initialized = false
local _isRendering = false

-- Rendering containers
local _battleFolder: Folder? = nil
local _troopsFolder: Folder? = nil
local _effectsFolder: Folder? = nil
local _rubbleFolder: Folder? = nil

-- Arena data from server
local _arenaCenter: Vector3 = Vector3.new(0, 0, 0)
local _arenaSize: number = 160 -- studs (40 * 4)
local _currentBattleId: string? = nil

-- Model tracking
local _troopVisuals: {[string]: TroopVisual} = {}
local _buildingParts: {[string]: Part} = {} -- references to server-spawned building Parts
local _buildingPreviousHp: {[string]: number} = {} -- track HP for damage detection
local _buildingSmokeEmitters: {[string]: ParticleEmitter} = {} -- smoke for low-HP buildings
local _destroyedBuildings: {[string]: boolean} = {} -- track buildings already destroyed

-- Object pool for troop visuals
local _troopPool: {Part} = {}
local TROOP_POOL_MAX = 50

-- Camera state
local _savedCameraCFrame: CFrame? = nil
local _savedCameraType: Enum.CameraType? = nil
local _cameraConnection: RBXScriptConnection? = nil

-- Tick rate for troop interpolation (matches server TICK_RATE)
local TICK_RATE = 0.1

-- Troop type visual definitions
type TroopVisual = {
    part: Part,
    healthGui: BillboardGui,
    healthBar: Frame,
    labelGui: BillboardGui,
    troopType: string,
    lastPosition: Vector3,
    activeTween: Tween?,
}

-- Troop colors by specific type (as specified in requirements)
local TROOP_TYPE_COLORS: {[string]: Color3} = {
    Barbarian = Color3.fromRGB(220, 50, 50),   -- Red (warrior)
    Archer = Color3.fromRGB(50, 200, 50),       -- Green
    Giant = Color3.fromRGB(160, 110, 60),        -- Brown
    WallBreaker = Color3.fromRGB(200, 140, 60),  -- Sandy
    Wizard = Color3.fromRGB(160, 50, 200),       -- Purple
    Healer = Color3.fromRGB(240, 240, 240),      -- White
    Dragon = Color3.fromRGB(255, 140, 0),        -- Orange
    PEKKA = Color3.fromRGB(30, 30, 120),         -- Dark blue
}

-- Fallback color for unknown troop types
local DEFAULT_TROOP_COLOR = Color3.fromRGB(100, 150, 255)

-- ═══════════════════════════════════════════════════════════════════════════════
-- OBJECT POOLING
-- ═══════════════════════════════════════════════════════════════════════════════

--[[
    Gets a Part from the object pool, or creates a new one if pool is empty.
]]
local function acquireTroopPart(): Part
    local part = table.remove(_troopPool)
    if part then
        part.Transparency = 0
        part.CanCollide = false
        return part
    end

    -- Create new part
    local newPart = Instance.new("Part")
    newPart.Name = "TroopBody"
    newPart.Shape = Enum.PartType.Ball
    newPart.Size = Vector3.new(1.5, 1.5, 1.5)
    newPart.Anchored = true
    newPart.CanCollide = false
    newPart.Material = Enum.Material.SmoothPlastic
    newPart.TopSurface = Enum.SurfaceType.Smooth
    newPart.BottomSurface = Enum.SurfaceType.Smooth
    return newPart
end

--[[
    Returns a Part to the object pool for reuse.
]]
local function releaseTroopPart(part: Part)
    -- Strip children (GUIs, emitters) before pooling
    for _, child in part:GetChildren() do
        child:Destroy()
    end

    part.Parent = nil
    part.Transparency = 1
    part.Color = Color3.fromRGB(128, 128, 128)

    if #_troopPool < TROOP_POOL_MAX then
        table.insert(_troopPool, part)
    else
        part:Destroy()
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TROOP VISUAL CREATION
-- ═══════════════════════════════════════════════════════════════════════════════

--[[
    Gets the visual scale for a troop based on housing space.
]]
local function getTroopScale(troopType: string): number
    local troopDef = TroopData.GetByType(troopType)
    if not troopDef then return 1.5 end
    local housingSpace = troopDef.housingSpace or 1
    -- Scale from 1.0 (housingSpace=1) to 3.0 (housingSpace=25)
    return math.clamp(0.8 + (housingSpace * 0.08), 1.0, 3.0)
end

--[[
    Gets the Y offset for a troop (flying troops hover higher).
]]
local function getTroopYOffset(troopType: string): number
    local troopDef = TroopData.GetByType(troopType)
    if not troopDef or not troopDef.levels or not troopDef.levels[1] then return 0 end
    local levelData = troopDef.levels[1]
    if levelData.isFlying then
        return 5 -- Flying troops hover 5 studs above ground
    end
    return 0
end

--[[
    Creates a troop visual (Part with BillboardGuis for HP bar and label).
    Uses object pooling for the main Part.
]]
local function createTroopVisual(troopId: string, troopType: string, position: Vector3): TroopVisual
    local scale = getTroopScale(troopType)
    local yOffset = getTroopYOffset(troopType)
    local color = TROOP_TYPE_COLORS[troopType] or DEFAULT_TROOP_COLOR

    -- Acquire part from pool
    local part = acquireTroopPart()
    part.Name = "Troop_" .. troopId
    part.Size = Vector3.new(scale, scale, scale)
    part.Color = color
    part.Transparency = 0
    part.Position = Vector3.new(position.X, position.Y + (scale / 2) + yOffset, position.Z)

    -- Health bar BillboardGui
    local healthGui = Instance.new("BillboardGui")
    healthGui.Name = "HealthGui"
    healthGui.Size = UDim2.new(0, 50, 0, 6)
    healthGui.StudsOffset = Vector3.new(0, scale / 2 + 0.5, 0)
    healthGui.AlwaysOnTop = true
    healthGui.Parent = part

    local healthBg = Instance.new("Frame")
    healthBg.Name = "Background"
    healthBg.Size = UDim2.new(1, 0, 1, 0)
    healthBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    healthBg.BorderSizePixel = 0
    healthBg.Parent = healthGui

    local uiCornerBg = Instance.new("UICorner")
    uiCornerBg.CornerRadius = UDim.new(0, 2)
    uiCornerBg.Parent = healthBg

    local healthBar = Instance.new("Frame")
    healthBar.Name = "Fill"
    healthBar.Size = UDim2.new(1, 0, 1, 0)
    healthBar.BackgroundColor3 = Color3.fromRGB(0, 220, 0)
    healthBar.BorderSizePixel = 0
    healthBar.Parent = healthBg

    local uiCornerFill = Instance.new("UICorner")
    uiCornerFill.CornerRadius = UDim.new(0, 2)
    uiCornerFill.Parent = healthBar

    -- Label BillboardGui (troop type name)
    local labelGui = Instance.new("BillboardGui")
    labelGui.Name = "LabelGui"
    labelGui.Size = UDim2.new(0, 60, 0, 16)
    labelGui.StudsOffset = Vector3.new(0, scale / 2 + 1.2, 0)
    labelGui.AlwaysOnTop = true
    labelGui.Parent = part

    local label = Instance.new("TextLabel")
    label.Name = "TypeLabel"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = troopType
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.3
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = labelGui

    -- Parent to troops folder
    if _troopsFolder then
        part.Parent = _troopsFolder
    end

    -- Spawn-in animation: scale up from small
    local originalSize = part.Size
    part.Size = Vector3.new(0.2, 0.2, 0.2)
    TweenService:Create(part, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = originalSize,
    }):Play()

    -- Spawn poof particle
    local spawnEmitter = Instance.new("ParticleEmitter")
    spawnEmitter.Name = "SpawnPoof"
    spawnEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    spawnEmitter.Color = ColorSequence.new(color)
    spawnEmitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 0),
    })
    spawnEmitter.Lifetime = NumberRange.new(0.3, 0.5)
    spawnEmitter.Speed = NumberRange.new(2, 4)
    spawnEmitter.SpreadAngle = Vector2.new(180, 180)
    spawnEmitter.Rate = 0
    spawnEmitter.Parent = part
    spawnEmitter:Emit(8)
    Debris:AddItem(spawnEmitter, 1)

    local visual: TroopVisual = {
        part = part,
        healthGui = healthGui,
        healthBar = healthBar,
        labelGui = labelGui,
        troopType = troopType,
        lastPosition = position,
        activeTween = nil,
    }

    return visual
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TROOP MANAGEMENT
-- ═══════════════════════════════════════════════════════════════════════════════

--[[
    Updates troop position with smooth interpolation over TICK_RATE.
]]
local function updateTroopPosition(visual: TroopVisual, newPosition: Vector3)
    local yOffset = getTroopYOffset(visual.troopType)
    local scale = visual.part.Size.Y
    local targetPos = Vector3.new(newPosition.X, newPosition.Y + (scale / 2) + yOffset, newPosition.Z)

    -- Cancel existing tween if any
    if visual.activeTween then
        visual.activeTween:Cancel()
    end

    -- Smoothly tween to new position
    local tween = TweenService:Create(visual.part, TweenInfo.new(TICK_RATE, Enum.EasingStyle.Linear), {
        Position = targetPos,
    })
    visual.activeTween = tween
    tween:Play()

    visual.lastPosition = newPosition
end

--[[
    Updates the HP bar display for a troop.
]]
local function updateTroopHealthBar(visual: TroopVisual, currentHp: number, maxHp: number)
    local ratio = math.clamp(currentHp / math.max(maxHp, 1), 0, 1)

    TweenService:Create(visual.healthBar, TweenInfo.new(0.15), {
        Size = UDim2.new(ratio, 0, 1, 0),
    }):Play()

    -- Color gradient: green -> yellow -> red
    if ratio > 0.6 then
        visual.healthBar.BackgroundColor3 = Color3.fromRGB(0, 220, 0)
    elseif ratio > 0.3 then
        visual.healthBar.BackgroundColor3 = Color3.fromRGB(230, 200, 0)
    else
        visual.healthBar.BackgroundColor3 = Color3.fromRGB(230, 30, 30)
    end
end

--[[
    Plays a death poof effect and removes the troop visual.
]]
local function playTroopDeathEffect(visual: TroopVisual)
    local part = visual.part
    if not part or not part.Parent then return end

    -- Cancel movement tween
    if visual.activeTween then
        visual.activeTween:Cancel()
    end

    -- Death poof particle burst
    local deathEmitter = Instance.new("ParticleEmitter")
    deathEmitter.Name = "DeathPoof"
    deathEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
    deathEmitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 200, 200)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 100, 100)),
    })
    deathEmitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1.0),
        NumberSequenceKeypoint.new(1, 2.5),
    })
    deathEmitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    deathEmitter.Lifetime = NumberRange.new(0.4, 0.7)
    deathEmitter.Speed = NumberRange.new(3, 6)
    deathEmitter.SpreadAngle = Vector2.new(180, 180)
    deathEmitter.Rate = 0
    deathEmitter.Parent = part
    deathEmitter:Emit(15)

    -- Shrink and fade out the troop body
    TweenService:Create(part, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = Vector3.new(0.1, 0.1, 0.1),
        Transparency = 1,
    }):Play()

    -- Hide health and label immediately
    visual.healthGui.Enabled = false
    visual.labelGui.Enabled = false

    -- Release the part back to pool after effects finish
    task.delay(0.8, function()
        releaseTroopPart(part)
    end)
end

--[[
    Cleans up a single troop visual by ID.
]]
function BattleRenderer:CleanupTroop(troopId: string)
    local visual = _troopVisuals[troopId]
    if not visual then return end

    playTroopDeathEffect(visual)
    _troopVisuals[troopId] = nil
end

--[[
    Cleans up all troop visuals.
]]
function BattleRenderer:CleanupAllTroops()
    for troopId, visual in _troopVisuals do
        if visual.activeTween then
            visual.activeTween:Cancel()
        end
        releaseTroopPart(visual.part)
    end
    table.clear(_troopVisuals)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- BUILDING DAMAGE EFFECTS
-- ═══════════════════════════════════════════════════════════════════════════════

--[[
    Shows a floating damage number above a building.
    Red text that floats upward and fades out.
]]
local function showFloatingDamage(part: Part, damage: number)
    if not part or not part.Parent then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "DamageNumber"
    billboard.Size = UDim2.new(0, 60, 0, 30)
    billboard.StudsOffset = Vector3.new(
        (math.random() - 0.5) * 2, -- slight horizontal randomness
        part.Size.Y / 2 + 1,
        0
    )
    billboard.AlwaysOnTop = true
    billboard.Parent = part

    local damageLabel = Instance.new("TextLabel")
    damageLabel.Name = "DamageText"
    damageLabel.Size = UDim2.new(1, 0, 1, 0)
    damageLabel.BackgroundTransparency = 1
    damageLabel.Text = "-" .. tostring(math.floor(damage))
    damageLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
    damageLabel.TextStrokeTransparency = 0.3
    damageLabel.TextStrokeColor3 = Color3.fromRGB(80, 0, 0)
    damageLabel.TextScaled = true
    damageLabel.Font = Enum.Font.GothamBold
    damageLabel.Parent = billboard

    -- Float upward and fade out
    TweenService:Create(billboard, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        StudsOffset = billboard.StudsOffset + Vector3.new(0, 3, 0),
    }):Play()

    TweenService:Create(damageLabel, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    }):Play()

    Debris:AddItem(billboard, 1.0)
end

--[[
    Flashes a building part white briefly when it takes damage.
]]
local function flashBuildingDamage(part: Part)
    if not part or not part.Parent then return end

    local originalColor = part.Color
    local originalMaterial = part.Material

    part.Color = Color3.fromRGB(255, 255, 255)
    part.Material = Enum.Material.Neon

    task.delay(0.1, function()
        if part and part.Parent then
            part.Color = originalColor
            part.Material = originalMaterial
        end
    end)
end

--[[
    Adds or removes smoke particles on a building based on HP ratio.
    Smoke appears below 30% HP and intensifies as HP drops.
]]
local function updateBuildingSmoke(buildingId: string, part: Part, hpRatio: number)
    if hpRatio < 0.3 and hpRatio > 0 then
        -- Add smoke if not already present
        if not _buildingSmokeEmitters[buildingId] then
            local smoke = Instance.new("ParticleEmitter")
            smoke.Name = "DamageSmoke"
            smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
            smoke.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 80, 80)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 40, 40)),
            })
            smoke.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.5),
                NumberSequenceKeypoint.new(0.5, 2.0),
                NumberSequenceKeypoint.new(1, 3.0),
            })
            smoke.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.3),
                NumberSequenceKeypoint.new(1, 1),
            })
            smoke.Lifetime = NumberRange.new(1.5, 2.5)
            smoke.Speed = NumberRange.new(1, 3)
            smoke.SpreadAngle = Vector2.new(15, 15)
            smoke.RotSpeed = NumberRange.new(-30, 30)
            smoke.Rate = 5
            smoke.Parent = part
            _buildingSmokeEmitters[buildingId] = smoke
        end

        -- Intensify smoke as HP drops
        local smoke = _buildingSmokeEmitters[buildingId]
        if smoke then
            smoke.Rate = math.floor(5 + (1 - hpRatio / 0.3) * 15) -- 5-20 particles/sec
        end
    else
        -- Remove smoke if HP recovered above 30% (unlikely in battle, but safe)
        local smoke = _buildingSmokeEmitters[buildingId]
        if smoke and hpRatio >= 0.3 then
            smoke:Destroy()
            _buildingSmokeEmitters[buildingId] = nil
        end
    end
end

--[[
    Plays a building explosion effect when HP reaches 0.
    Orange/yellow burst with debris particles.
]]
local function playBuildingExplosion(part: Part)
    if not part or not part.Parent then return end

    local position = part.Position
    local size = part.Size

    -- Create explosion flash (neon sphere that expands and fades)
    local explosionPart = Instance.new("Part")
    explosionPart.Name = "Explosion"
    explosionPart.Shape = Enum.PartType.Ball
    explosionPart.Size = Vector3.new(1, 1, 1)
    explosionPart.Position = position
    explosionPart.Anchored = true
    explosionPart.CanCollide = false
    explosionPart.Material = Enum.Material.Neon
    explosionPart.Color = Color3.fromRGB(255, 160, 0)
    explosionPart.Transparency = 0
    if _effectsFolder then
        explosionPart.Parent = _effectsFolder
    end

    -- Expand and fade
    local maxExplosionSize = math.max(size.X, size.Y, size.Z) * 2
    TweenService:Create(explosionPart, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(maxExplosionSize, maxExplosionSize, maxExplosionSize),
        Transparency = 1,
        Color = Color3.fromRGB(255, 255, 100),
    }):Play()
    Debris:AddItem(explosionPart, 0.6)

    -- Fire/smoke particle burst on the building itself
    local fireEmitter = Instance.new("ParticleEmitter")
    fireEmitter.Name = "ExplosionFire"
    fireEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
    fireEmitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 50)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 50, 0)),
    })
    fireEmitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1.0),
        NumberSequenceKeypoint.new(0.3, 3.0),
        NumberSequenceKeypoint.new(1, 0.5),
    })
    fireEmitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    fireEmitter.Lifetime = NumberRange.new(0.5, 1.0)
    fireEmitter.Speed = NumberRange.new(5, 10)
    fireEmitter.SpreadAngle = Vector2.new(60, 60)
    fireEmitter.RotSpeed = NumberRange.new(-60, 60)
    fireEmitter.Rate = 0
    fireEmitter.Parent = part
    fireEmitter:Emit(25)
    Debris:AddItem(fireEmitter, 2)

    -- Tween building transparency to fade it out
    TweenService:Create(part, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Transparency = 1,
    }):Play()

    -- Also fade out any children of the building (labels, HP bars)
    for _, child in part:GetChildren() do
        if child:IsA("BillboardGui") then
            child.Enabled = false
        end
    end

    -- Scatter rubble pieces
    local rubbleCount = math.clamp(math.floor(size.X * size.Z / 4), 3, 8)
    for i = 1, rubbleCount do
        local rubble = Instance.new("Part")
        rubble.Name = "Rubble"
        rubble.Size = Vector3.new(
            math.random() * 1.0 + 0.3,
            math.random() * 0.5 + 0.2,
            math.random() * 1.0 + 0.3
        )
        rubble.Position = Vector3.new(
            position.X + (math.random() - 0.5) * size.X,
            position.Y - size.Y / 2 + rubble.Size.Y / 2 + 0.1,
            position.Z + (math.random() - 0.5) * size.Z
        )
        rubble.Anchored = true
        rubble.CanCollide = false
        rubble.Material = Enum.Material.Slate
        rubble.Color = Color3.fromRGB(
            math.random(80, 130),
            math.random(80, 130),
            math.random(80, 130)
        )
        rubble.Rotation = Vector3.new(
            math.random(0, 360),
            math.random(0, 360),
            math.random(0, 360)
        )

        if _rubbleFolder then
            rubble.Parent = _rubbleFolder
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- BUILDING STATE TRACKING
-- ═══════════════════════════════════════════════════════════════════════════════

--[[
    Discovers and caches references to building Parts spawned by
    BattleArenaService inside workspace.BattleArenas.
]]
local function discoverBuildingParts(arenaCenter: Vector3)
    table.clear(_buildingParts)
    table.clear(_buildingPreviousHp)
    table.clear(_destroyedBuildings)

    -- Clean up any existing smoke emitters
    for id, emitter in _buildingSmokeEmitters do
        if emitter and emitter.Parent then
            emitter:Destroy()
        end
    end
    table.clear(_buildingSmokeEmitters)

    -- Find the arena folder in workspace.BattleArenas
    local arenasFolder = Workspace:FindFirstChild("BattleArenas")
    if not arenasFolder then return end

    for _, arenaFolder in arenasFolder:GetChildren() do
        if arenaFolder:IsA("Folder") then
            for _, child in arenaFolder:GetChildren() do
                if child:IsA("Part") then
                    local buildingId = child:GetAttribute("BuildingId")
                    if buildingId and typeof(buildingId) == "string" then
                        _buildingParts[buildingId] = child
                        local maxHp = child:GetAttribute("MaxHp") or 100
                        _buildingPreviousHp[buildingId] = maxHp
                    end
                end
            end
        end
    end

    print(string.format("[BattleRenderer] Discovered %d building parts", #_buildingParts))
end

--[[
    Updates building visuals based on the tick state data.
    Detects damage, triggers effects, and handles destruction.
]]
local function updateBuildings(buildingUpdates: {any})
    if not buildingUpdates then return end

    for _, update in buildingUpdates do
        local buildingId = update.buildingId
        local currentHp = update.currentHp or 0
        local maxHp = update.maxHp or 1
        local hpRatio = math.clamp(currentHp / math.max(maxHp, 1), 0, 1)

        local part = _buildingParts[buildingId]
        if not part or not part.Parent then continue end

        -- Already destroyed, skip
        if _destroyedBuildings[buildingId] then continue end

        local previousHp = _buildingPreviousHp[buildingId] or maxHp

        -- Detect damage
        if currentHp < previousHp then
            local damage = previousHp - currentHp

            -- Floating damage number
            showFloatingDamage(part, damage)

            -- Flash the building white
            flashBuildingDamage(part)
        end

        -- Update smoke effect based on HP ratio
        updateBuildingSmoke(buildingId, part, hpRatio)

        -- Building destroyed
        if currentHp <= 0 and not _destroyedBuildings[buildingId] then
            _destroyedBuildings[buildingId] = true

            -- Remove smoke first
            local smoke = _buildingSmokeEmitters[buildingId]
            if smoke then
                smoke:Destroy()
                _buildingSmokeEmitters[buildingId] = nil
            end

            -- Play explosion and destruction effect
            playBuildingExplosion(part)
        end

        -- Store for next tick comparison
        _buildingPreviousHp[buildingId] = currentHp
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TROOP STATE PROCESSING
-- ═══════════════════════════════════════════════════════════════════════════════

--[[
    Updates all troop visuals based on the tick state data.
    Creates new troop visuals, updates positions, handles deaths.
]]
local function updateTroops(troopUpdates: {any})
    if not troopUpdates then return end

    -- Track which troops are still alive this tick
    local aliveTroops: {[string]: boolean} = {}

    for _, troopData in troopUpdates do
        local troopId = troopData.id
        local troopType = troopData.type or "Barbarian"
        local state = troopData.state or "moving"
        local currentHp = troopData.currentHp or 0
        local maxHp = troopData.maxHp or 1
        local position = troopData.position

        -- Convert table position to Vector3 if needed
        if position and typeof(position) ~= "Vector3" then
            if typeof(position) == "table" then
                position = Vector3.new(position.x or position.X or 0, position.y or position.Y or 0, position.z or position.Z or 0)
            else
                position = Vector3.new(0, 0, 0)
            end
        end

        if not position then continue end

        -- Dead troop: play death effect and remove
        if state == "dead" or currentHp <= 0 then
            if _troopVisuals[troopId] then
                BattleRenderer:CleanupTroop(troopId)
            end
            continue
        end

        aliveTroops[troopId] = true

        -- Create visual if it does not exist
        if not _troopVisuals[troopId] then
            local visual = createTroopVisual(troopId, troopType, position)
            _troopVisuals[troopId] = visual
        end

        local visual = _troopVisuals[troopId]

        -- Update position
        updateTroopPosition(visual, position)

        -- Update health bar
        updateTroopHealthBar(visual, currentHp, maxHp)
    end

    -- Remove troops that were not in this tick's update (they may have died
    -- between ticks or the server stopped sending them)
    for troopId, visual in _troopVisuals do
        if not aliveTroops[troopId] then
            BattleRenderer:CleanupTroop(troopId)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- CAMERA MANAGEMENT
-- ═══════════════════════════════════════════════════════════════════════════════

--[[
    Positions the camera to look down at the arena from an isometric-like angle.
    Camera is set to Scriptable mode for full control.
]]
local function setupArenaCamera(arenaCenter: Vector3, arenaSize: number)
    local camera = Workspace.CurrentCamera
    if not camera then return end

    -- Save current camera state for restoration
    _savedCameraCFrame = camera.CFrame
    _savedCameraType = camera.CameraType

    -- Set to scriptable for full control
    camera.CameraType = Enum.CameraType.Scriptable

    -- Isometric-ish angle: offset upward and back, looking down at arena center
    local cameraHeight = arenaSize * 0.6
    local cameraDistance = arenaSize * 0.4
    local cameraPosition = Vector3.new(
        arenaCenter.X - cameraDistance,
        arenaCenter.Y + cameraHeight,
        arenaCenter.Z - cameraDistance
    )

    local targetCFrame = CFrame.lookAt(cameraPosition, arenaCenter)

    -- Tween camera to arena view
    TweenService:Create(camera, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
        CFrame = targetCFrame,
    }):Play()

    -- Allow camera to be moved within bounds during battle using mouse drag
    -- We use RenderStepped to keep the camera looking at roughly the arena area
    -- but allow panning and zooming within bounds
    local isDragging = false
    local lastMousePos: Vector3? = nil
    local currentOffset = Vector3.new(0, 0, 0)
    local currentZoom = 1.0
    local MIN_ZOOM = 0.4
    local MAX_ZOOM = 1.8

    local mouse = Players.LocalPlayer:GetMouse()

    -- Set up mouse wheel zoom
    local wheelConnection: RBXScriptConnection? = nil
    wheelConnection = mouse.WheelForward:Connect(function()
        currentZoom = math.clamp(currentZoom - 0.1, MIN_ZOOM, MAX_ZOOM)
    end)

    local wheelBackConnection: RBXScriptConnection? = nil
    wheelBackConnection = mouse.WheelBackward:Connect(function()
        currentZoom = math.clamp(currentZoom + 0.1, MIN_ZOOM, MAX_ZOOM)
    end)

    -- Middle mouse drag for panning
    local UIS = game:GetService("UserInputService")
    local dragStartConnection: RBXScriptConnection? = nil
    local dragEndConnection: RBXScriptConnection? = nil
    local dragMoveConnection: RBXScriptConnection? = nil

    dragStartConnection = UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton3 or
           input.UserInputType == Enum.UserInputType.MouseButton2 then
            isDragging = true
            lastMousePos = Vector3.new(input.Position.X, input.Position.Y, 0)
        end
    end)

    dragEndConnection = UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton3 or
           input.UserInputType == Enum.UserInputType.MouseButton2 then
            isDragging = false
            lastMousePos = nil
        end
    end)

    dragMoveConnection = UIS.InputChanged:Connect(function(input)
        if not isDragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local currentMousePos = Vector3.new(input.Position.X, input.Position.Y, 0)
            if lastMousePos then
                local delta = currentMousePos - lastMousePos
                -- Convert screen delta to world offset (approximate)
                local panSpeed = 0.3 * currentZoom
                currentOffset = currentOffset + Vector3.new(-delta.X * panSpeed, 0, -delta.Y * panSpeed)

                -- Clamp offset to arena bounds
                local maxPan = arenaSize * 0.5
                currentOffset = Vector3.new(
                    math.clamp(currentOffset.X, -maxPan, maxPan),
                    0,
                    math.clamp(currentOffset.Z, -maxPan, maxPan)
                )
            end
            lastMousePos = currentMousePos
        end
    end)

    -- Render step to keep camera updated with zoom and pan
    _cameraConnection = RunService.RenderStepped:Connect(function()
        if not _isRendering then return end

        local cam = Workspace.CurrentCamera
        if not cam then return end

        local zoomedHeight = cameraHeight * currentZoom
        local zoomedDistance = cameraDistance * currentZoom
        local lookTarget = arenaCenter + currentOffset

        local camPos = Vector3.new(
            lookTarget.X - zoomedDistance,
            arenaCenter.Y + zoomedHeight,
            lookTarget.Z - zoomedDistance
        )

        cam.CFrame = CFrame.lookAt(camPos, lookTarget)
    end)

    -- Store connections for cleanup
    -- We will clean them up in StopRendering
    -- Store in a table on the module for access
    BattleRenderer._cameraConnections = {
        wheelConnection,
        wheelBackConnection,
        dragStartConnection,
        dragEndConnection,
        dragMoveConnection,
    }
end

--[[
    Restores the camera back to the player character (overworld view).
]]
local function restoreCamera()
    -- Disconnect camera control connections
    if _cameraConnection then
        _cameraConnection:Disconnect()
        _cameraConnection = nil
    end

    if BattleRenderer._cameraConnections then
        for _, conn in BattleRenderer._cameraConnections do
            if conn then
                conn:Disconnect()
            end
        end
        BattleRenderer._cameraConnections = nil
    end

    local camera = Workspace.CurrentCamera
    if not camera then return end

    -- Restore camera type
    if _savedCameraType then
        camera.CameraType = _savedCameraType
        _savedCameraType = nil
    else
        camera.CameraType = Enum.CameraType.Custom
    end

    -- Tween camera back to character if saved CFrame exists
    if _savedCameraCFrame then
        -- We set the type first, then the game will handle the transition
        -- back to the character. Setting the CFrame is optional here since
        -- Enum.CameraType.Custom will snap to the character anyway.
        _savedCameraCFrame = nil
    end

    -- Ensure camera focuses on player character
    local player = Players.LocalPlayer
    if player and player.Character then
        camera.CameraSubject = player.Character:FindFirstChildOfClass("Humanoid")
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- DEPLOY ZONE
-- ═══════════════════════════════════════════════════════════════════════════════

--[[
    Creates a deploy zone indicator along the edge of the arena.
    Players click here to deploy troops.
]]
local function createDeployZone(arenaCenter: Vector3, arenaSize: number)
    local deployZone = Instance.new("Part")
    deployZone.Name = "DeployZone"
    deployZone.Size = Vector3.new(arenaSize, 0.15, 15)
    deployZone.Position = Vector3.new(
        arenaCenter.X,
        arenaCenter.Y + 0.08,
        arenaCenter.Z - arenaSize / 2 - 7.5
    )
    deployZone.Anchored = true
    deployZone.CanCollide = false
    deployZone.Material = Enum.Material.Neon
    deployZone.Color = Color3.fromRGB(0, 200, 100)
    deployZone.Transparency = 0.5

    if _battleFolder then
        deployZone.Parent = _battleFolder
    end

    -- Click detection for deployment
    local clickDetector = Instance.new("ClickDetector")
    clickDetector.MaxActivationDistance = 500
    clickDetector.Parent = deployZone

    clickDetector.MouseClick:Connect(function()
        local mouse = Players.LocalPlayer:GetMouse()
        if mouse.Hit then
            BattleRenderer.DeployPositionClicked:Fire(Vector3.new(mouse.Hit.X, arenaCenter.Y, mouse.Hit.Z))
        end
    end)

    -- Pulsing animation to indicate it is interactive
    task.spawn(function()
        while deployZone and deployZone.Parent do
            TweenService:Create(deployZone, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                Transparency = 0.3,
            }):Play()
            task.wait(1.0)
            if not deployZone or not deployZone.Parent then break end
            TweenService:Create(deployZone, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                Transparency = 0.7,
            }):Play()
            task.wait(1.0)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════════

--[[
    Starts rendering the battle arena. Called when BattleArenaReady fires.

    @param arenaData table - Data from BattleArenaReady event:
        { battleId, arenaCenter, arenaSize, buildings, defenderName, defenderTownHallLevel }
]]
function BattleRenderer:StartRendering(arenaData: any)
    if _isRendering then
        warn("[BattleRenderer] Already rendering, stopping previous session")
        self:StopRendering()
    end

    _isRendering = true
    _currentBattleId = arenaData.battleId
    _arenaCenter = arenaData.arenaCenter or Vector3.new(0, 500, 0)
    _arenaSize = arenaData.arenaSize or 160

    -- Create rendering folders
    _battleFolder = Instance.new("Folder")
    _battleFolder.Name = "BattleEffects_" .. (arenaData.battleId or "unknown")
    _battleFolder.Parent = Workspace

    _troopsFolder = Instance.new("Folder")
    _troopsFolder.Name = "Troops"
    _troopsFolder.Parent = _battleFolder

    _effectsFolder = Instance.new("Folder")
    _effectsFolder.Name = "Effects"
    _effectsFolder.Parent = _battleFolder

    _rubbleFolder = Instance.new("Folder")
    _rubbleFolder.Name = "Rubble"
    _rubbleFolder.Parent = _battleFolder

    -- Discover building parts spawned by BattleArenaService
    -- Allow a brief delay for server parts to replicate
    task.delay(0.2, function()
        discoverBuildingParts(_arenaCenter)
    end)

    -- Create deploy zone
    createDeployZone(_arenaCenter, _arenaSize)

    -- Set up camera
    setupArenaCamera(_arenaCenter, _arenaSize)

    print(string.format(
        "[BattleRenderer] StartRendering: battleId=%s, center=%s, size=%d",
        tostring(arenaData.battleId),
        tostring(_arenaCenter),
        _arenaSize
    ))
end

--[[
    Processes a per-tick state update from the server.

    @param stateData table - BattleStateUpdate data:
        { battleId, destruction, starsEarned, phase, timeRemaining, buildings, troops }
]]
function BattleRenderer:UpdateTick(stateData: any)
    if not _isRendering then return end
    if not stateData then return end

    -- Verify this is for our current battle
    if stateData.battleId and stateData.battleId ~= _currentBattleId then return end

    -- If building parts have not been discovered yet, try now
    if next(_buildingParts) == nil then
        discoverBuildingParts(_arenaCenter)
    end

    -- Update buildings (damage effects, destruction)
    updateBuildings(stateData.buildings)

    -- Update troops (movement, health, deaths)
    updateTroops(stateData.troops)
end

--[[
    Stops rendering and cleans up all visual objects. Restores camera.
]]
function BattleRenderer:StopRendering()
    if not _isRendering then return end
    _isRendering = false
    _currentBattleId = nil

    -- Clean up all troop visuals
    self:CleanupAllTroops()

    -- Clean up smoke emitters
    for id, emitter in _buildingSmokeEmitters do
        if emitter and emitter.Parent then
            emitter:Destroy()
        end
    end
    table.clear(_buildingSmokeEmitters)

    -- Clear building tracking
    table.clear(_buildingParts)
    table.clear(_buildingPreviousHp)
    table.clear(_destroyedBuildings)

    -- Destroy rendering folders (and all contents)
    if _battleFolder then
        _battleFolder:Destroy()
        _battleFolder = nil
    end
    _troopsFolder = nil
    _effectsFolder = nil
    _rubbleFolder = nil

    -- Restore camera
    restoreCamera()

    -- Clear troop pool
    for _, part in _troopPool do
        part:Destroy()
    end
    table.clear(_troopPool)

    print("[BattleRenderer] StopRendering: cleanup complete")
end

--[[
    Initializes the BattleRenderer.
    Sets up connections to RemoteEvents from BattleArenaService.
]]
function BattleRenderer:Init()
    if _initialized then
        warn("BattleRenderer already initialized")
        return
    end

    -- Wait for Events folder
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if not Events then
        local waitStart = tick()
        repeat
            task.wait(0.1)
            Events = ReplicatedStorage:FindFirstChild("Events")
        until Events or (tick() - waitStart > 10)
    end

    if not Events then
        warn("[BattleRenderer] Events folder not found, cannot initialize")
        return
    end

    -- Connect to BattleArenaReady: arena is spawned and ready for rendering
    local arenaReadyEvent = Events:FindFirstChild("BattleArenaReady")
    if arenaReadyEvent then
        arenaReadyEvent.OnClientEvent:Connect(function(arenaData: any)
            if arenaData and arenaData.battleId then
                BattleRenderer:StartRendering(arenaData)
            elseif arenaData and arenaData.error then
                warn("[BattleRenderer] Arena creation failed:", arenaData.error)
            end
        end)
        print("[BattleRenderer] Connected to BattleArenaReady")
    else
        warn("[BattleRenderer] BattleArenaReady event not found")
    end

    -- Connect to BattleStateUpdate: per-tick state updates
    local stateUpdateEvent = Events:FindFirstChild("BattleStateUpdate")
    if stateUpdateEvent then
        stateUpdateEvent.OnClientEvent:Connect(function(stateData: any)
            BattleRenderer:UpdateTick(stateData)
        end)
        print("[BattleRenderer] Connected to BattleStateUpdate")
    else
        warn("[BattleRenderer] BattleStateUpdate event not found")
    end

    -- Connect to BattleComplete: battle ended, show final state
    local battleCompleteEvent = Events:FindFirstChild("BattleComplete")
    if battleCompleteEvent then
        battleCompleteEvent.OnClientEvent:Connect(function(resultData: any)
            -- Keep rendering for a few seconds so the player sees the final state
            -- Cleanup will be triggered by ReturnToOverworld
            print(string.format(
                "[BattleRenderer] Battle complete: stars=%s, destruction=%s%%",
                tostring(resultData and resultData.stars),
                tostring(resultData and resultData.destruction)
            ))
        end)
        print("[BattleRenderer] Connected to BattleComplete")
    else
        warn("[BattleRenderer] BattleComplete event not found")
    end

    -- Connect to ReturnToOverworld: clean up and restore camera
    local returnEvent = Events:FindFirstChild("ReturnToOverworld")
    if returnEvent then
        returnEvent.OnClientEvent:Connect(function(data: any)
            BattleRenderer:StopRendering()
            print("[BattleRenderer] Returned to overworld")
        end)
        print("[BattleRenderer] Connected to ReturnToOverworld")
    else
        warn("[BattleRenderer] ReturnToOverworld event not found")
    end

    _initialized = true
    print("BattleRenderer initialized")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- LEGACY COMPATIBILITY API
-- These methods maintain backward compatibility with the wiring in
-- init.client.lua that references Activate/Deactivate/RenderTroop/etc.
-- ═══════════════════════════════════════════════════════════════════════════════

--[[
    Activates the battle renderer (legacy compatibility).
    New code should use StartRendering() instead.
]]
function BattleRenderer:Activate()
    -- StartRendering is called by the BattleArenaReady event handler,
    -- so Activate is now a no-op. The init.client.lua BattleStarted
    -- connection can call this safely.
    print("[BattleRenderer] Activate called (handled via BattleArenaReady)")
end

--[[
    Deactivates the battle renderer (legacy compatibility).
    New code should use StopRendering() instead.
]]
function BattleRenderer:Deactivate()
    self:StopRendering()
end

--[[
    Legacy: Renders a troop (used by init.client.lua BattleTick handler).
]]
function BattleRenderer:RenderTroop(troopId: string, troopData: any)
    if not _isRendering then return end

    local position = troopData.position or Vector3.new(0, 0, 0)
    if typeof(position) ~= "Vector3" then
        if typeof(position) == "table" then
            position = Vector3.new(position.x or 0, position.y or 0, position.z or 0)
        end
    end

    if not _troopVisuals[troopId] then
        local visual = createTroopVisual(troopId, troopData.type or "Barbarian", position)
        _troopVisuals[troopId] = visual
    end
end

--[[
    Legacy: Updates troop position (used by init.client.lua).
    Returns true if the troop existed, nil/false if it did not (so caller
    knows to call RenderTroop).
]]
function BattleRenderer:UpdateTroopPosition(troopId: string, position: Vector3): boolean?
    local visual = _troopVisuals[troopId]
    if not visual then return nil end

    updateTroopPosition(visual, position)
    return true
end

--[[
    Legacy: Updates troop health (used by init.client.lua).
]]
function BattleRenderer:UpdateTroopHealth(troopId: string, healthPercent: number)
    local visual = _troopVisuals[troopId]
    if not visual then return end

    -- healthPercent is 0-1 ratio
    local maxHp = 100
    local currentHp = healthPercent * maxHp
    updateTroopHealthBar(visual, currentHp, maxHp)
end

--[[
    Legacy: Removes a troop (used by init.client.lua).
]]
function BattleRenderer:RemoveTroop(troopId: string)
    self:CleanupTroop(troopId)
end

--[[
    Legacy: Updates building health display.
]]
function BattleRenderer:UpdateBuildingHealth(buildingId: string, healthPercent: number)
    local part = _buildingParts[buildingId]
    if not part then return end

    -- Simulate a building update
    local maxHp = part:GetAttribute("MaxHp") or 100
    local currentHp = healthPercent * maxHp
    updateBuildings({{
        buildingId = buildingId,
        currentHp = currentHp,
        maxHp = maxHp,
    }})
end

--[[
    Legacy: Removes a building (destroyed).
]]
function BattleRenderer:RemoveBuilding(buildingId: string)
    local part = _buildingParts[buildingId]
    if part and part.Parent then
        playBuildingExplosion(part)
        _buildingParts[buildingId] = nil
    end
end

--[[
    Legacy: Shows spell effect.
]]
function BattleRenderer:ShowSpellEffect(spellType: string, position: Vector3, radius: number)
    if not _effectsFolder then return end

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
        Size = Vector3.new(0.3, radius * 2, radius * 2),
    }):Play()

    task.delay(2, function()
        TweenService:Create(effect, TweenInfo.new(0.5), {
            Transparency = 1,
        }):Play()
        Debris:AddItem(effect, 0.6)
    end)
end

--[[
    Legacy: Shows attack line from troop to target.
]]
function BattleRenderer:ShowAttackEffect(fromPosition: Vector3, toPosition: Vector3)
    if not _effectsFolder then return end

    local distance = (toPosition - fromPosition).Magnitude
    if distance < 0.1 then return end

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
        Transparency = 1,
    }):Play()

    Debris:AddItem(beam, 0.15)
end

return BattleRenderer
