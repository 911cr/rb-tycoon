--!strict
--[[
    BanditService.lua

    Manages roaming AI bandits in the overworld wilderness and forbidden zones.
    ~25 bandits patrol wilderness, ~8 patrol forbidden zone.

    Features:
    - Part-based NPC creation with tier-specific appearance
    - Smooth lerp-based walking (no instant teleport)
    - Aggro chase: bandits detect nearby players and pursue them
    - ProximityPrompt: press E to voluntarily engage a bandit
    - Forced combat: bandits auto-ambush players they catch
    - Server-authoritative: reads troops from DataService, no client trust
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
    aggroTarget: Player?,
    lastForcedCombat: {[number]: number}, -- userId -> timestamp of last forced combat
}

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _bandits: {[string]: BanditState} = {}
local _initialized = false
local _patrolConnection: RBXScriptConnection? = nil
local _walkConnections: {[string]: RBXScriptConnection} = {} -- banditId -> active walk heartbeat

-- Lazy-loaded service references
local _combatService: any = nil
local _dataService: any = nil
local _lootCarryService: any = nil

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

local function getDataService()
    if not _dataService then
        local module = ServerScriptService:FindFirstChild("Services")
            and ServerScriptService.Services:FindFirstChild("DataService")
        if module then
            local ok, svc = pcall(require, module)
            if ok then _dataService = svc end
        end
    end
    return _dataService
end

local function getLootCarryService()
    if not _lootCarryService then
        local module = ServerScriptService:FindFirstChild("Services")
            and ServerScriptService.Services:FindFirstChild("LootCarryService")
        if module then
            local ok, svc = pcall(require, module)
            if ok then _lootCarryService = svc end
        end
    end
    return _lootCarryService
end

-- Lazy-loaded remote event references (created by Main.server.lua in Events folder)
local _autoClashResultEvent: RemoteEvent? = nil
local _serverResponseEvent: RemoteEvent? = nil

local function getAutoClashResultEvent(): RemoteEvent?
    if not _autoClashResultEvent then
        local events = ReplicatedStorage:FindFirstChild("Events")
        if events then
            _autoClashResultEvent = events:FindFirstChild("AutoClashResult") :: RemoteEvent?
        end
    end
    return _autoClashResultEvent
end

local function getServerResponseEvent(): RemoteEvent?
    if not _serverResponseEvent then
        local events = ReplicatedStorage:FindFirstChild("Events")
        if events then
            _serverResponseEvent = events:FindFirstChild("ServerResponse") :: RemoteEvent?
        end
    end
    return _serverResponseEvent
end

-- Config constants
local PATROL_RADIUS = OverworldConfig.Wilderness.Bandits.PatrolRadius
local PATROL_INTERVAL = OverworldConfig.Wilderness.Bandits.PatrolInterval
local AGGRO_RADIUS = OverworldConfig.Wilderness.Bandits.AggroRadius
local RESPAWN_TIME = OverworldConfig.Wilderness.Bandits.RespawnTime
local AGGRO_LEASH = AGGRO_RADIUS * 1.5 -- max distance from spawn before losing aggro
local AMBUSH_RANGE = 8 -- studs: forced combat triggers at this distance
local FORCED_COMBAT_COOLDOWN = 30 -- seconds before same bandit can re-ambush same player
local WALK_SPEED_PATROL = 6 -- studs/s for normal patrol
local WALK_SPEED_CHASE = 10 -- studs/s when chasing a player
local PROMPT_ENGAGE_COOLDOWN = 2 -- seconds between voluntary engagements per player

-- Per-player rate limit for ProximityPrompt engagement
local _promptCooldowns: {[number]: number} = {} -- userId -> last engage time

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
    Gets the current position of a bandit's torso (HumanoidRootPart).
]]
local function getBanditPosition(state: BanditState): Vector3?
    if not state.npc then return nil end
    local root = state.npc:FindFirstChild("HumanoidRootPart") :: BasePart?
    return root and root.Position or nil
end

--[[
    Cancels any active walk connection for a bandit.
]]
local function cancelWalk(banditId: string)
    local conn = _walkConnections[banditId]
    if conn then
        conn:Disconnect()
        _walkConnections[banditId] = nil
    end
end

--[[
    Smoothly walks a bandit NPC from current position to target X,Z.
    Uses lerp-based movement with leg animation (sine wave swing).
    Cancels any existing walk for this bandit.
]]
local function walkBanditTo(state: BanditState, targetX: number, targetZ: number, speed: number)
    if not state.npc then return end
    cancelWalk(state.id)

    local root = state.npc:FindFirstChild("HumanoidRootPart") :: BasePart?
    local head = state.npc:FindFirstChild("Head") :: BasePart?
    local legs = state.npc:FindFirstChild("Legs") :: BasePart?
    if not root then return end

    local startPos = root.Position
    local targetY = getTerrainY(targetX, targetZ)
    local targetPos = Vector3.new(targetX, targetY + 3, targetZ)

    local distance = (Vector3.new(targetX, startPos.Y, targetZ) - Vector3.new(startPos.X, startPos.Y, startPos.Z)).Magnitude
    if distance < 0.5 then return end -- Already there

    local duration = distance / speed
    local elapsed = 0
    local phase = 0

    -- Calculate facing direction
    local dx = targetX - startPos.X
    local dz = targetZ - startPos.Z
    local facingAngle = math.atan2(dx, dz)

    _walkConnections[state.id] = RunService.Heartbeat:Connect(function(dt)
        if not state.alive or state.inCombat then
            cancelWalk(state.id)
            return
        end
        if not state.npc then
            cancelWalk(state.id)
            return
        end

        elapsed += dt
        local alpha = math.min(elapsed / duration, 1)

        -- Lerp position
        local currentY = getTerrainY(
            startPos.X + (targetX - startPos.X) * alpha,
            startPos.Z + (targetZ - startPos.Z) * alpha
        )
        local currentX = startPos.X + (targetX - startPos.X) * alpha
        local currentZ = startPos.Z + (targetZ - startPos.Z) * alpha

        -- Face direction of movement
        local facingCF = CFrame.new(currentX, currentY + 3, currentZ)
            * CFrame.Angles(0, facingAngle, 0)

        if root and root.Parent then
            root.CFrame = facingCF
        end
        if head and head.Parent then
            head.CFrame = CFrame.new(currentX, currentY + 4.6, currentZ)
                * CFrame.Angles(0, facingAngle, 0)
        end

        -- Leg animation: sine wave swing
        if legs and legs.Parent then
            phase += dt * speed * 1.2
            local legSwing = math.sin(phase) * 0.5
            legs.CFrame = CFrame.new(currentX, currentY + 1, currentZ)
                * CFrame.Angles(0, facingAngle, 0)
                * CFrame.Angles(legSwing, 0, 0)
        end

        -- Done
        if alpha >= 1 then
            cancelWalk(state.id)
        end
    end)
end

--[[
    Reads a player's troops from DataService server-side.
    Returns a troop list suitable for OverworldCombatService, or nil if no troops.
]]
local function getPlayerTroops(player: Player): {any}?
    local ds = getDataService()
    if not ds then return nil end

    local playerData = ds:GetPlayerData(player)
    if not playerData or not playerData.troops then return nil end

    local troops = {}
    for troopType, troopInfo in playerData.troops do
        if typeof(troopInfo) == "table" and (troopInfo.count or 0) > 0 then
            table.insert(troops, {
                troopType = troopType,
                level = troopInfo.level or 1,
                count = troopInfo.count,
            })
        end
    end

    return if #troops > 0 then troops else nil
end

--[[
    Loot steal percentage based on bandit tier (for forced combat with no troops).
]]
local function getStealPercent(tier: number): number
    if tier <= 2 then return 0.25 end
    if tier == 3 then return 0.50 end
    return 0.75 -- tier 4-5
end

--[[
    Creates a simple NPC model for a bandit.
    Uses Part-based construction. Includes ProximityPrompt for voluntary engagement.
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

    -- ProximityPrompt for voluntary engagement
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Battle"
    prompt.ObjectText = tierData.name
    prompt.MaxActivationDistance = 12
    prompt.HoldDuration = 0
    prompt.RequiresLineOfSight = false
    prompt.Parent = torso

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
    Despawns a bandit NPC (on defeat).
]]
local function despawnBandit(state: BanditState)
    cancelWalk(state.id)
    if state.npc then
        state.npc:Destroy()
        state.npc = nil
    end
    state.alive = false
    state.aggroTarget = nil
    state.defeatedAt = os.time()
end

--[[
    Hides or shows the ProximityPrompt on a bandit's NPC.
]]
local function setPromptEnabled(state: BanditState, enabled: boolean)
    if not state.npc then return end
    local root = state.npc:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local prompt = root:FindFirstChildOfClass("ProximityPrompt")
    if prompt then
        prompt.Enabled = enabled
    end
end

--[[
    Spawns a bandit at its original spawn point.
]]
local function spawnBandit(state: BanditState)
    if state.npc then
        cancelWalk(state.id)
        state.npc:Destroy()
    end

    state.npc = createBanditNPC(state.id, state.tier, state.spawnX, state.spawnZ)
    state.alive = true
    state.defeatedAt = nil
    state.inCombat = false
    state.aggroTarget = nil
end

--[[
    Runs combat between a player and a bandit. Server-authoritative.
    Returns the AutoClashResult or nil on failure.
]]
local function runBanditCombat(state: BanditState, player: Player, troops: {any}): any?
    local tierData = BanditData.GetTierData(state.tier)
    if not tierData then return nil end

    local combatSvc = getCombatService()
    if not combatSvc then return nil end

    -- Get zone stat multiplier
    local zoneMult = 1.0
    if state.tier == 5 then
        zoneMult = OverworldConfig.ForbiddenZone.StatMultiplier
    end

    -- Mark as in combat
    state.inCombat = true
    setPromptEnabled(state, false)
    cancelWalk(state.id)
    combatSvc:SetCombatState(player.UserId, true)

    -- Run auto-clash
    local attackerArmy = { troops = troops }
    local result = combatSvc:RunPvEClash(attackerArmy, tierData.troops, zoneMult)

    -- Clear combat state
    combatSvc:SetCombatState(player.UserId, false)
    state.inCombat = false
    setPromptEnabled(state, true)

    -- If player won, defeat bandit and roll loot
    if result.winner == "attacker" then
        result.loot = BanditData.RollLoot(state.tier)
        despawnBandit(state)
        BanditService.BanditDefeated:Fire(state.id, state.tier, player)
    end

    return result
end

--[[
    Triggers forced combat when a bandit catches a player during chase.
    Handles three scenarios:
    1. Player has troops → normal auto-clash
    2. Player has no troops but carries loot → bandit steals a percentage
    3. Player has no troops and no loot → bandit ignores
]]
local function triggerForcedCombat(state: BanditState, player: Player)
    -- Check forced combat cooldown
    local now = os.clock()
    local lastForced = state.lastForcedCombat[player.UserId] or 0
    if now - lastForced < FORCED_COMBAT_COOLDOWN then return end

    -- Check player not already in combat
    local combatSvc = getCombatService()
    if not combatSvc then return end
    if combatSvc:IsInCombat(player.UserId) then return end

    -- Record cooldown
    state.lastForcedCombat[player.UserId] = now

    -- Read player troops server-side
    local troops = getPlayerTroops(player)
    local lootSvc = getLootCarryService()
    local isCarryingLoot = lootSvc and lootSvc:IsCarryingLoot(player) or false

    local autoClashEvent = getAutoClashResultEvent()
    local serverResponseEvent = getServerResponseEvent()

    if troops then
        -- Scenario 1: Has troops → normal combat
        local result = runBanditCombat(state, player, troops)
        if result and autoClashEvent then
            autoClashEvent:FireClient(player, result)
            -- If won, add loot to carried
            if result.winner == "attacker" and result.loot and lootSvc then
                lootSvc:AddLoot(player, result.loot)
            end
            -- If lost and carrying loot, bandit steals some
            if result.winner == "defender" and isCarryingLoot and lootSvc then
                local stolen = lootSvc:StealPartialLoot(player, getStealPercent(state.tier))
                if stolen then
                    result.stolenLoot = stolen
                end
            end
        end
    elseif isCarryingLoot and lootSvc then
        -- Scenario 2: No troops, carrying loot → bandit auto-steals
        local stolen = lootSvc:StealPartialLoot(player, getStealPercent(state.tier))
        if stolen and autoClashEvent then
            autoClashEvent:FireClient(player, {
                winner = "defender",
                attackerLosses = {},
                defenderLosses = {},
                attackerHpPercent = 0,
                defenderHpPercent = 100,
                duration = 0,
                loot = nil,
                stolenLoot = stolen,
                forced = true,
            })
        end
    else
        -- Scenario 3: No troops, no loot → bandit ignores
        if serverResponseEvent then
            serverResponseEvent:FireClient(player, "BanditWarning", {
                success = false,
                error = "NO_LOOT_WARNING",
                message = "The bandit eyes you but finds nothing worth stealing.",
            })
        end
    end
end

--[[
    Wires the ProximityPrompt on a bandit NPC for voluntary combat engagement.
]]
local function wirePrompt(state: BanditState)
    if not state.npc then return end
    local root = state.npc:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local prompt = root:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then return end

    prompt.Triggered:Connect(function(player: Player)
        if not state.alive or state.inCombat then return end

        -- Rate limit
        local now = os.clock()
        local last = _promptCooldowns[player.UserId] or 0
        if now - last < PROMPT_ENGAGE_COOLDOWN then
            local srEvent = getServerResponseEvent()
            if srEvent then
                srEvent:FireClient(player, "EngageBandit", { success = false, error = "RATE_LIMITED" })
            end
            return
        end
        _promptCooldowns[player.UserId] = now

        -- Check not already in combat
        local combatSvc = getCombatService()
        if combatSvc and combatSvc:IsInCombat(player.UserId) then
            local srEvent = getServerResponseEvent()
            if srEvent then
                srEvent:FireClient(player, "EngageBandit", { success = false, error = "ALREADY_IN_COMBAT" })
            end
            return
        end

        -- Read troops server-side
        local troops = getPlayerTroops(player)
        if not troops then
            local srEvent = getServerResponseEvent()
            if srEvent then
                srEvent:FireClient(player, "EngageBandit", { success = false, error = "NO_TROOPS" })
            end
            return
        end

        -- Run combat
        local result = runBanditCombat(state, player, troops)
        local autoClashEvent = getAutoClashResultEvent()
        local lootSvc = getLootCarryService()

        if result and autoClashEvent then
            autoClashEvent:FireClient(player, result)
            if result.winner == "attacker" and result.loot and lootSvc then
                lootSvc:AddLoot(player, result.loot)
            end
        else
            local srEvent = getServerResponseEvent()
            if srEvent then
                srEvent:FireClient(player, "EngageBandit", { success = false, error = "ENGAGE_FAILED" })
            end
        end
    end)
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
            aggroTarget = nil,
            lastForcedCombat = {},
        }
        _bandits[spawn.id] = state

        -- Spawn with slight delay to avoid overwhelming terrain raycast
        task.defer(function()
            spawnBandit(state)
            wirePrompt(state)
        end)
    end

    -- Patrol + aggro loop: runs every frame but only acts on patrol interval
    local patrolElapsed = 0
    _patrolConnection = RunService.Heartbeat:Connect(function(dt)
        patrolElapsed += dt
        if patrolElapsed < PATROL_INTERVAL then return end
        patrolElapsed = 0

        for _, state in _bandits do
            if not state.alive or state.inCombat then continue end
            if not state.npc then continue end

            local banditPos = getBanditPosition(state)
            if not banditPos then continue end

            -- Check for nearby players (aggro detection)
            local closestPlayer: Player? = nil
            local closestDist = AGGRO_RADIUS

            for _, player in Players:GetPlayers() do
                local character = player.Character
                if not character then continue end
                local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if not hrp then continue end

                -- Skip players already in combat
                local combatSvc = getCombatService()
                if combatSvc and combatSvc:IsInCombat(player.UserId) then continue end

                local dist = (hrp.Position - banditPos).Magnitude
                if dist < closestDist then
                    closestPlayer = player
                    closestDist = dist
                end
            end

            if closestPlayer then
                -- Chase: walk toward player
                local character = closestPlayer.Character
                if character then
                    local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if hrp then
                        local playerPos = hrp.Position
                        walkBanditTo(state, playerPos.X, playerPos.Z, WALK_SPEED_CHASE)
                        state.aggroTarget = closestPlayer

                        -- AUTO-AMBUSH: bandit caught the player
                        if closestDist < AMBUSH_RANGE then
                            triggerForcedCombat(state, closestPlayer)
                        end
                    end
                end

                -- Aggro leash: check distance from spawn
                local distFromSpawn = (banditPos - Vector3.new(state.spawnX, banditPos.Y, state.spawnZ)).Magnitude
                if distFromSpawn > AGGRO_LEASH then
                    -- Too far from home, walk back
                    walkBanditTo(state, state.spawnX, state.spawnZ, WALK_SPEED_PATROL)
                    state.aggroTarget = nil
                end
            elseif state.aggroTarget then
                -- Lost aggro: walk back to spawn area
                walkBanditTo(state, state.spawnX, state.spawnZ, WALK_SPEED_PATROL)
                state.aggroTarget = nil
            else
                -- Normal patrol: random wander
                local angle = math.random() * math.pi * 2
                local dist = math.random() * PATROL_RADIUS
                local newX = state.spawnX + math.cos(angle) * dist
                local newZ = state.spawnZ + math.sin(angle) * dist

                -- Clamp to map bounds
                newX = math.clamp(newX, 10, 1990)
                newZ = math.clamp(newZ, 10, 1990)

                walkBanditTo(state, newX, newZ, WALK_SPEED_PATROL)
            end
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
                        wirePrompt(state)
                        self.BanditRespawned:Fire(state.id)
                    end
                end
            end
        end
    end)

    -- Cleanup prompt cooldowns when players leave
    Players.PlayerRemoving:Connect(function(player)
        _promptCooldowns[player.UserId] = nil
        -- Clean up forced combat cooldowns
        for _, state in _bandits do
            state.lastForcedCombat[player.UserId] = nil
        end
    end)

    print(string.format("[BanditService] Initialized %d bandits", #allSpawns))
end

--[[
    Engages a bandit in auto-clash combat.
    Called from Main.server.lua EngageBandit handler (legacy RemoteEvent path).

    @param player Player - The attacking player
    @param banditId string - The bandit ID to engage
    @param troops {any} - Player's troops (validated server-side)
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
    local playerRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not playerRoot then return nil end

    local banditPos = getBanditPosition(state)
    if not banditPos then return nil end

    local dist = (playerRoot.Position - banditPos).Magnitude
    if dist > AGGRO_RADIUS then
        return nil -- Too far
    end

    return runBanditCombat(state, player, troops)
end

--[[
    Gets info about a specific bandit (for client display).

    @param banditId string
    @return table? - {id, tier, name, alive, position}
]]
function BanditService:GetBanditInfo(banditId: string): any?
    local state = _bandits[banditId]
    if not state then return nil end

    local pos = getBanditPosition(state)
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

    -- Clean up all walk connections
    for banditId, _ in _walkConnections do
        cancelWalk(banditId)
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
