--!strict
--[[
    BanditService.lua

    Manages roaming AI bandits in the overworld wilderness and forbidden zones.
    ~25 bandits patrol wilderness, ~8 patrol forbidden zone.

    Features:
    - R15 NPC creation with tier-specific appearance
    - Patrol AI: random waypoints within patrol radius
    - Engagement: player fires EngageBandit, server validates proximity + runs auto-clash
    - Respawn: defeated bandits respawn after 5 minutes
    - All NPCs are raycast-grounded on terrain surface
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local BanditData = require(ReplicatedStorage.Shared.Constants.BanditData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local BanditService = {}
BanditService.__index = BanditService

-- ============================================================================
-- SIGNALS
-- ============================================================================

BanditService.BanditDefeated = Signal.new()  -- (banditId, tier, player)
BanditService.BanditRespawned = Signal.new() -- (banditId)

-- ============================================================================
-- TYPES
-- ============================================================================

type BanditState = {
    id: string,
    tier: number,
    spawnX: number,
    spawnZ: number,
    alive: boolean,
    npc: Model?,
    defeatedAt: number?,
    inCombat: boolean,
}

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _bandits: {[string]: BanditState} = {}
local _initialized = false
local _patrolConnection: RBXScriptConnection? = nil

-- Load combat service lazily
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

local PATROL_RADIUS = OverworldConfig.Wilderness.Bandits.PatrolRadius
local PATROL_INTERVAL = OverworldConfig.Wilderness.Bandits.PatrolInterval
local AGGRO_RADIUS = OverworldConfig.Wilderness.Bandits.AggroRadius
local RESPAWN_TIME = OverworldConfig.Wilderness.Bandits.RespawnTime

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

--[[
    Raycasts terrain to find surface Y at given X,Z.
]]
local function getTerrainY(x: number, z: number): number
    return OverworldConfig.GetTerrainHeight(x, z)
end

--[[
    Creates a simple NPC model for a bandit.
    Uses Part-based construction (fallback for when Players:CreateHumanoidModelFromDescription fails).
]]
local function createBanditNPC(banditId: string, tier: number, x: number, z: number): Model?
    local tierData = BanditData.GetTierData(tier)
    if not tierData then return nil end

    local y = getTerrainY(x, z)

    local model = Instance.new("Model")
    model.Name = "Bandit_" .. banditId

    -- Body (torso)
    local torso = Instance.new("Part")
    torso.Name = "HumanoidRootPart"
    torso.Size = Vector3.new(2, 2, 1)
    torso.Anchored = true
    torso.CanCollide = false
    torso.Material = Enum.Material.SmoothPlastic
    torso.Color = tierData.appearance.shirtColor
    torso.CFrame = CFrame.new(x, y + 3, z)
    torso.Parent = model

    -- Head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Shape = Enum.PartType.Ball
    head.Size = Vector3.new(1.2, 1.2, 1.2)
    head.Anchored = true
    head.CanCollide = false
    head.Material = Enum.Material.SmoothPlastic
    head.Color = tierData.appearance.headColor
    head.CFrame = CFrame.new(x, y + 4.6, z)
    head.Parent = model

    -- Legs
    local legs = Instance.new("Part")
    legs.Name = "Legs"
    legs.Size = Vector3.new(2, 2, 1)
    legs.Anchored = true
    legs.CanCollide = false
    legs.Material = Enum.Material.SmoothPlastic
    legs.Color = tierData.appearance.pantsColor
    legs.CFrame = CFrame.new(x, y + 1, z)
    legs.Parent = model

    -- Humanoid (for walk animation targeting, not functional walking)
    local humanoid = Instance.new("Humanoid")
    humanoid.MaxHealth = 100
    humanoid.Health = 100
    humanoid.Parent = model

    -- BillboardGui with name
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "NameTag"
    billboard.Size = UDim2.new(0, 120, 0, 25)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 40
    billboard.Parent = head

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 1, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = tierData.name
    nameLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    -- Tier indicator
    local tierLabel = Instance.new("TextLabel")
    tierLabel.Size = UDim2.new(1, 0, 0, 15)
    tierLabel.Position = UDim2.new(0, 0, 1, 2)
    tierLabel.BackgroundTransparency = 1
    tierLabel.Text = "Tier " .. tostring(tier)
    tierLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    tierLabel.TextStrokeTransparency = 0.5
    tierLabel.TextScaled = true
    tierLabel.Font = Enum.Font.Gotham
    tierLabel.Parent = billboard

    model.PrimaryPart = torso

    -- Place in Overworld folder
    local owFolder = workspace:FindFirstChild("Overworld")
    if not owFolder then
        owFolder = Instance.new("Folder")
        owFolder.Name = "Overworld"
        owFolder.Parent = workspace
    end
    local banditFolder = owFolder:FindFirstChild("Bandits")
    if not banditFolder then
        banditFolder = Instance.new("Folder")
        banditFolder.Name = "Bandits"
        banditFolder.Parent = owFolder
    end

    model.Parent = banditFolder

    return model
end

--[[
    Moves a bandit NPC to a new position on terrain.
]]
local function moveBanditTo(state: BanditState, x: number, z: number)
    if not state.npc then return end
    local y = getTerrainY(x, z)
    local root = state.npc:FindFirstChild("HumanoidRootPart") :: BasePart?
    if root then
        root.CFrame = CFrame.new(x, y + 3, z)
    end
    local head = state.npc:FindFirstChild("Head") :: BasePart?
    if head then
        head.CFrame = CFrame.new(x, y + 4.6, z)
    end
    local legs = state.npc:FindFirstChild("Legs") :: BasePart?
    if legs then
        legs.CFrame = CFrame.new(x, y + 1, z)
    end
end

--[[
    Despawns a bandit NPC (on defeat).
]]
local function despawnBandit(state: BanditState)
    if state.npc then
        state.npc:Destroy()
        state.npc = nil
    end
    state.alive = false
    state.defeatedAt = os.time()
end

--[[
    Spawns a bandit at its original spawn point.
]]
local function spawnBandit(state: BanditState)
    if state.npc then
        state.npc:Destroy()
    end

    state.npc = createBanditNPC(state.id, state.tier, state.spawnX, state.spawnZ)
    state.alive = true
    state.defeatedAt = nil
    state.inCombat = false
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Initializes all bandits from BanditData spawn positions.
]]
function BanditService:Init()
    if _initialized then
        warn("[BanditService] Already initialized")
        return
    end
    _initialized = true

    -- Create all bandit states
    local allSpawns = BanditData.GetAllSpawns()
    for _, spawn in allSpawns do
        local state: BanditState = {
            id = spawn.id,
            tier = spawn.tier,
            spawnX = spawn.x,
            spawnZ = spawn.z,
            alive = false,
            npc = nil,
            defeatedAt = nil,
            inCombat = false,
        }
        _bandits[spawn.id] = state

        -- Spawn with slight delay to avoid overwhelming terrain raycast
        task.defer(function()
            spawnBandit(state)
        end)
    end

    -- Patrol loop: move bandits to random waypoints
    local patrolElapsed = 0
    _patrolConnection = RunService.Heartbeat:Connect(function(dt)
        patrolElapsed += dt
        if patrolElapsed < PATROL_INTERVAL then return end
        patrolElapsed = 0

        for _, state in _bandits do
            if not state.alive or state.inCombat then continue end
            if not state.npc then continue end

            -- Pick random waypoint within patrol radius
            local angle = math.random() * math.pi * 2
            local dist = math.random() * PATROL_RADIUS
            local newX = state.spawnX + math.cos(angle) * dist
            local newZ = state.spawnZ + math.sin(angle) * dist

            -- Clamp to map bounds
            newX = math.clamp(newX, 10, 1990)
            newZ = math.clamp(newZ, 10, 1990)

            moveBanditTo(state, newX, newZ)
        end
    end)

    -- Respawn loop
    task.spawn(function()
        while true do
            task.wait(30) -- Check every 30 seconds

            local now = os.time()
            for _, state in _bandits do
                if not state.alive and state.defeatedAt then
                    if now - state.defeatedAt >= RESPAWN_TIME then
                        spawnBandit(state)
                        self.BanditRespawned:Fire(state.id)
                    end
                end
            end
        end
    end)

    print(string.format("[BanditService] Initialized %d bandits", #allSpawns))
end

--[[
    Engages a bandit in auto-clash combat.

    @param player Player - The attacking player
    @param banditId string - The bandit ID to engage
    @param troops {any} - Player's selected troops
    @return AutoClashResult? - Combat result or nil on failure
]]
function BanditService:EngageBandit(player: Player, banditId: string, troops: {any}): any?
    local state = _bandits[banditId]
    if not state then
        warn("[BanditService] Bandit not found:", banditId)
        return nil
    end

    if not state.alive then
        return nil -- Already defeated
    end

    if state.inCombat then
        return nil -- Already fighting someone
    end

    -- Validate proximity
    local character = player.Character
    if not character then return nil end
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return nil end

    local banditRoot = state.npc and state.npc:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not banditRoot then return nil end

    local dist = (root.Position - banditRoot.Position).Magnitude
    if dist > AGGRO_RADIUS then
        return nil -- Too far
    end

    -- Build army compositions
    local attackerArmy = { troops = troops }
    local tierData = BanditData.GetTierData(state.tier)
    if not tierData then return nil end

    -- Get zone stat multiplier
    local zoneMult = 1.0
    if state.tier == 5 then
        zoneMult = OverworldConfig.ForbiddenZone.StatMultiplier
    end

    -- Mark as in combat
    state.inCombat = true
    local combatSvc = getCombatService()
    if not combatSvc then
        state.inCombat = false
        return nil
    end

    combatSvc:SetCombatState(player.UserId, true)

    -- Run auto-clash
    local result = combatSvc:RunPvEClash(attackerArmy, tierData.troops, zoneMult)

    -- Clear combat state
    combatSvc:SetCombatState(player.UserId, false)
    state.inCombat = false

    -- If player won, defeat bandit and roll loot
    if result.winner == "attacker" then
        result.loot = BanditData.RollLoot(state.tier)
        despawnBandit(state)
        self.BanditDefeated:Fire(banditId, state.tier, player)
    end

    return result
end

--[[
    Gets info about a specific bandit (for client display).

    @param banditId string
    @return table? - {id, tier, name, alive, position}
]]
function BanditService:GetBanditInfo(banditId: string): any?
    local state = _bandits[banditId]
    if not state then return nil end

    local pos = nil
    if state.npc then
        local root = state.npc:FindFirstChild("HumanoidRootPart") :: BasePart?
        if root then
            pos = root.Position
        end
    end

    local tierData = BanditData.GetTierData(state.tier)

    return {
        id = state.id,
        tier = state.tier,
        name = tierData and tierData.name or "Bandit",
        alive = state.alive,
        position = pos,
        inCombat = state.inCombat,
    }
end

--[[
    Gets all alive bandits for client sync.
    @return {table}
]]
function BanditService:GetAliveBandits(): {any}
    local result = {}
    for _, state in _bandits do
        if state.alive then
            local info = self:GetBanditInfo(state.id)
            if info then
                table.insert(result, info)
            end
        end
    end
    return result
end

--[[
    Cleans up on server shutdown.
]]
function BanditService:Destroy()
    if _patrolConnection then
        _patrolConnection:Disconnect()
        _patrolConnection = nil
    end

    for _, state in _bandits do
        if state.npc then
            state.npc:Destroy()
        end
    end
    _bandits = {}
    _initialized = false
end

return BanditService
