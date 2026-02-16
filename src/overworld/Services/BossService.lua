--!strict
--[[
    BossService.lua

    Manages boss monsters in the overworld.
    3-5 bosses: 2 wilderness, 2-3 forbidden zone.

    Features:
    - Large R15-style NPC with distinct appearance
    - BillboardGui HP bar visible to nearby players
    - Long respawn (2-4 hours)
    - Unique loot (high resources + gems in forbidden zone)
    - Co-op support: nearby players can pool troops
    - Grounded on terrain via raycast
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local BossData = require(ReplicatedStorage.Shared.Constants.BossData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local BossService = {}
BossService.__index = BossService

-- ============================================================================
-- SIGNALS
-- ============================================================================

BossService.BossDefeated = Signal.new()  -- (bossId, player, loot)
BossService.BossRespawned = Signal.new() -- (bossId)

-- ============================================================================
-- TYPES
-- ============================================================================

type BossState = {
    id: string,
    alive: boolean,
    npc: Model?,
    defeatedAt: number?,
    respawnTime: number,
    inCombat: boolean,
    zone: string,
}

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _bosses: {[string]: BossState} = {}
local _initialized = false

-- Lazy-load combat service
local _combatService: any = nil
local function getCombatService()
    if not _combatService then
        local module = ServerScriptService:FindFirstChild("Services")
            and ServerScriptService.Services:FindFirstChild("OverworldCombatService")
        if module then
            local ok, svc = pcall(require, module)
            if ok then _combatService = svc end
        end
    end
    return _combatService
end

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

local function getTerrainY(x: number, z: number): number
    return OverworldConfig.GetTerrainHeight(x, z)
end

--[[
    Creates a boss NPC model. Larger than bandits with HP bar.
]]
local function createBossNPC(bossId: string, bossInfo: any): Model?
    local x, z = bossInfo.x, bossInfo.z
    local y = getTerrainY(x, z)
    local scale = bossInfo.appearance.scale or 2.0

    local model = Instance.new("Model")
    model.Name = "Boss_" .. bossId

    -- Body (scaled up)
    local torso = Instance.new("Part")
    torso.Name = "HumanoidRootPart"
    torso.Size = Vector3.new(2 * scale, 2 * scale, 1 * scale)
    torso.Anchored = true
    torso.CanCollide = false
    torso.Material = Enum.Material.SmoothPlastic
    torso.Color = bossInfo.appearance.bodyColor
    torso.CFrame = CFrame.new(x, y + 3 * scale, z)
    torso.Parent = model

    -- Head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Shape = Enum.PartType.Ball
    head.Size = Vector3.new(1.4 * scale, 1.4 * scale, 1.4 * scale)
    head.Anchored = true
    head.CanCollide = false
    head.Material = Enum.Material.SmoothPlastic
    head.Color = bossInfo.appearance.headColor
    head.CFrame = CFrame.new(x, y + 4.6 * scale, z)
    head.Parent = model

    -- Legs
    local legs = Instance.new("Part")
    legs.Name = "Legs"
    legs.Size = Vector3.new(2 * scale, 2 * scale, 1 * scale)
    legs.Anchored = true
    legs.CanCollide = false
    legs.Material = Enum.Material.SmoothPlastic
    legs.Color = bossInfo.appearance.bodyColor
    legs.CFrame = CFrame.new(x, y + 1 * scale, z)
    legs.Parent = model

    -- Humanoid
    local humanoid = Instance.new("Humanoid")
    humanoid.MaxHealth = 100
    humanoid.Health = 100
    humanoid.Parent = model

    -- Name + HP Billboard
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BossInfo"
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 4 * scale, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = OverworldConfig.Wilderness.Bosses.HPBarDistance
    billboard.Parent = head

    -- Boss name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "BossName"
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = bossInfo.name
    nameLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    -- HP bar background
    local hpBg = Instance.new("Frame")
    hpBg.Name = "HPBackground"
    hpBg.Size = UDim2.new(0.8, 0, 0.25, 0)
    hpBg.Position = UDim2.new(0.1, 0, 0.55, 0)
    hpBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    hpBg.BorderSizePixel = 0
    hpBg.Parent = billboard

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.3, 0)
    corner.Parent = hpBg

    -- HP bar fill
    local hpFill = Instance.new("Frame")
    hpFill.Name = "HPFill"
    hpFill.Size = UDim2.new(1, 0, 1, 0)
    hpFill.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    hpFill.BorderSizePixel = 0
    hpFill.Parent = hpBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0.3, 0)
    fillCorner.Parent = hpFill

    -- Particle effect
    local particles = Instance.new("ParticleEmitter")
    particles.Color = ColorSequence.new(bossInfo.appearance.bodyColor)
    particles.Size = NumberSequence.new(0.5)
    particles.Rate = 5
    particles.Lifetime = NumberRange.new(1, 2)
    particles.Speed = NumberRange.new(1, 3)
    particles.Parent = torso

    model.PrimaryPart = torso

    -- Parent to Overworld/Bosses folder
    local owFolder = workspace:FindFirstChild("Overworld")
    if not owFolder then
        owFolder = Instance.new("Folder")
        owFolder.Name = "Overworld"
        owFolder.Parent = workspace
    end
    local bossFolder = owFolder:FindFirstChild("Bosses")
    if not bossFolder then
        bossFolder = Instance.new("Folder")
        bossFolder.Name = "Bosses"
        bossFolder.Parent = owFolder
    end

    model.Parent = bossFolder
    return model
end

local function despawnBoss(state: BossState)
    if state.npc then
        state.npc:Destroy()
        state.npc = nil
    end
    state.alive = false
    state.defeatedAt = os.time()
end

local function spawnBoss(state: BossState)
    local bossInfo = BossData.GetBossById(state.id)
    if not bossInfo then return end

    if state.npc then
        state.npc:Destroy()
    end

    state.npc = createBossNPC(state.id, bossInfo)
    state.alive = true
    state.defeatedAt = nil
    state.inCombat = false
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function BossService:Init()
    if _initialized then return end
    _initialized = true

    for _, bossInfo in BossData.GetAllBosses() do
        local state: BossState = {
            id = bossInfo.id,
            alive = false,
            npc = nil,
            defeatedAt = nil,
            respawnTime = bossInfo.respawnTime,
            inCombat = false,
            zone = bossInfo.zone,
        }
        _bosses[bossInfo.id] = state

        task.defer(function()
            spawnBoss(state)
        end)
    end

    -- Respawn loop
    task.spawn(function()
        while true do
            task.wait(60)

            local now = os.time()
            for _, state in _bosses do
                if not state.alive and state.defeatedAt then
                    if now - state.defeatedAt >= state.respawnTime then
                        spawnBoss(state)
                        self.BossRespawned:Fire(state.id)
                        print(string.format("[BossService] Boss %s respawned", state.id))
                    end
                end
            end
        end
    end)

    print(string.format("[BossService] Initialized %d bosses", #BossData.GetAllBosses()))
end

--[[
    Engages a boss in auto-clash combat.

    @param player Player
    @param bossId string
    @param troops {any} - Player's selected troops
    @return AutoClashResult?
]]
function BossService:EngageBoss(player: Player, bossId: string, troops: {any}): any?
    local state = _bosses[bossId]
    if not state then return nil end
    if not state.alive then return nil end
    if state.inCombat then return nil end

    local bossInfo = BossData.GetBossById(bossId)
    if not bossInfo then return nil end

    -- Proximity check
    local character = player.Character
    if not character then return nil end
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return nil end

    local bossRoot = state.npc and state.npc:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not bossRoot then return nil end

    local dist = (root.Position - bossRoot.Position).Magnitude
    if dist > OverworldConfig.Wilderness.Bandits.AggroRadius * 1.5 then
        return nil
    end

    local combatSvc = getCombatService()
    if not combatSvc then return nil end

    -- Zone stat multiplier
    local zoneMult = 1.0
    if state.zone == "forbidden" then
        zoneMult = OverworldConfig.ForbiddenZone.StatMultiplier
    end

    state.inCombat = true
    combatSvc:SetCombatState(player.UserId, true)

    local attackerArmy = { troops = troops }
    local result = combatSvc:RunPvEClash(attackerArmy, bossInfo.troops, zoneMult)

    combatSvc:SetCombatState(player.UserId, false)
    state.inCombat = false

    if result.winner == "attacker" then
        result.loot = BossData.RollLoot(bossId)
        despawnBoss(state)
        self.BossDefeated:Fire(bossId, player, result.loot)
        print(string.format("[BossService] Boss %s defeated by %s", bossInfo.name, player.Name))
    end

    return result
end

--[[
    Gets info about a boss for client display.
]]
function BossService:GetBossInfo(bossId: string): any?
    local state = _bosses[bossId]
    if not state then return nil end

    local bossInfo = BossData.GetBossById(bossId)
    local pos = nil
    if state.npc then
        local root = state.npc:FindFirstChild("HumanoidRootPart") :: BasePart?
        if root then pos = root.Position end
    end

    return {
        id = state.id,
        name = bossInfo and bossInfo.name or "Boss",
        description = bossInfo and bossInfo.description or "",
        alive = state.alive,
        position = pos,
        inCombat = state.inCombat,
        zone = state.zone,
    }
end

--[[
    Gets all bosses for client sync.
]]
function BossService:GetAllBossInfo(): {any}
    local result = {}
    for _, state in _bosses do
        local info = self:GetBossInfo(state.id)
        if info then table.insert(result, info) end
    end
    return result
end

function BossService:Destroy()
    for _, state in _bosses do
        if state.npc then state.npc:Destroy() end
    end
    _bosses = {}
    _initialized = false
end

return BossService
