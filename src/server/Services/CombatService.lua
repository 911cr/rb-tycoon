--!strict
--[[
    CombatService.lua

    Manages battle simulation, troop deployment, and combat outcomes.
    All operations are server-authoritative.

    SECURITY:
    - Battle simulation runs ENTIRELY on server
    - Client only sends deploy commands
    - Timers and damage calculations are server-side
    - Client receives state updates for rendering

    Dependencies:
    - DataService (for player data)
    - TroopService (for troop consumption)
    - EconomyService (for loot distribution)

    Events:
    - BattleStarted(attackerId, defenderId, battleId)
    - TroopDeployed(battleId, troopData)
    - SpellDeployed(battleId, spellData)
    - BattleTick(battleId, state)
    - BattleEnded(battleId, result)
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatTypes = require(ReplicatedStorage.Shared.Types.CombatTypes)
local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)
local SpellData = require(ReplicatedStorage.Shared.Constants.SpellData)
local BalanceConfig = require(ReplicatedStorage.Shared.Constants.BalanceConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declarations
local DataService
local TroopService
local EconomyService

local CombatService = {}
CombatService.__index = CombatService

-- Events
CombatService.BattleStarted = Signal.new()
CombatService.TroopDeployed = Signal.new()
CombatService.SpellDeployed = Signal.new()
CombatService.BattleTick = Signal.new()
CombatService.BattleEnded = Signal.new()

-- Private state
local _activeBattles: {[string]: CombatTypes.BattleState} = {}
local _initialized = false

-- Constants
local TICK_RATE = 0.1 -- 10 ticks per second
local DEPLOY_BOUNDARY_SIZE = 40 -- Grid size for deployment

-- Types for internal use
type BuildingTarget = {
    id: string,
    type: string,
    position: Vector3,
    currentHp: number,
    maxHp: number,
    isDestroyed: boolean,
    category: string,
    wasDowngraded: boolean?, -- True if farm was downgraded instead of destroyed
}

type StartBattleResult = {
    success: boolean,
    battleId: string?,
    error: string?,
}

type DeployResult = {
    success: boolean,
    deployedUnit: CombatTypes.DeployedTroop?,
    error: string?,
}

type SpellDeployResult = {
    success: boolean,
    deployedSpell: CombatTypes.DeployedSpell?,
    error: string?,
}

type ActiveSpell = {
    id: string,
    type: string,
    level: number,
    position: Vector3,
    radius: number,
    startTime: number,
    duration: number,
    levelData: any,
}

--[[
    Validates if a position is within the deployment zone.
    Troops can only be deployed on the edge of the map.
]]
local function isValidDeployPosition(position: Vector3): boolean
    local x, z = position.X, position.Z

    -- Must be on grid
    if x ~= math.floor(x) or z ~= math.floor(z) then
        return false
    end

    -- Must be within bounds
    if x < 0 or x >= DEPLOY_BOUNDARY_SIZE then return false end
    if z < 0 or z >= DEPLOY_BOUNDARY_SIZE then return false end

    -- Must be on the edge (first 2 or last 2 rows/columns)
    local onEdge = x < 2 or x >= DEPLOY_BOUNDARY_SIZE - 2 or
                   z < 2 or z >= DEPLOY_BOUNDARY_SIZE - 2

    return onEdge
end

--[[
    Gets the defender's buildings as targets.
]]
local function getDefenderBuildings(defenderData: any): {BuildingTarget}
    local targets = {}
    local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)

    for id, building in defenderData.buildings do
        local buildingDef = BuildingData.GetByType(building.type)
        if buildingDef then
            local levelData = buildingDef.levels[building.level]
            table.insert(targets, {
                id = id,
                type = building.type,
                position = building.position,
                currentHp = building.currentHp or (levelData and levelData.hp or 100),
                maxHp = levelData and levelData.hp or 100,
                isDestroyed = false,
                category = buildingDef.category or "other",
            })
        end
    end

    return targets
end

--[[
    Calculates total HP of all buildings (for destruction percentage).
]]
local function calculateTotalBuildingHp(targets: {BuildingTarget}): number
    local total = 0
    for _, target in targets do
        total += target.maxHp
    end
    return total
end

--[[
    Finds the nearest target for a troop based on its preferences.
]]
local function findNearestTarget(
    troop: CombatTypes.DeployedTroop,
    targets: {BuildingTarget},
    troopDef: any
): BuildingTarget?
    local preferredTarget = troopDef.preferredTarget or "any"
    local bestTarget: BuildingTarget? = nil
    local bestDistance = math.huge

    for _, target in targets do
        if target.isDestroyed then continue end

        -- Check if troop prefers this target type
        local isPreferred = preferredTarget == "any"
        if preferredTarget == "defenses" and target.category == "defense" then
            isPreferred = true
        elseif preferredTarget == "resources" and target.category == "resource" then
            isPreferred = true
        elseif preferredTarget == "walls" and target.category == "wall" then
            isPreferred = true
        end

        local distance = (target.position - troop.position).Magnitude

        -- Prefer matching targets, but fall back to any
        if isPreferred then
            if distance < bestDistance then
                bestTarget = target
                bestDistance = distance
            end
        elseif not bestTarget and preferredTarget ~= "any" then
            -- Only consider non-preferred if we have no match and not "any"
            if distance < bestDistance then
                bestTarget = target
                bestDistance = distance
            end
        end
    end

    -- If no preferred found, find any
    if not bestTarget then
        for _, target in targets do
            if target.isDestroyed then continue end
            local distance = (target.position - troop.position).Magnitude
            if distance < bestDistance then
                bestTarget = target
                bestDistance = distance
            end
        end
    end

    return bestTarget
end

--[[
    Starts a new battle between attacker and defender.

    @param attacker Player - The attacking player
    @param defenderUserId number - The defender's UserId
    @param options table? - Optional battle options:
        - isRevenge: boolean - If true, skip shield check and mark battle as revenge
    @return StartBattleResult
]]
function CombatService:StartBattle(attacker: Player, defenderUserId: number, options: {isRevenge: boolean?}?): StartBattleResult
    -- Validate attacker
    local attackerData = DataService:GetPlayerData(attacker)
    if not attackerData then
        return { success = false, battleId = nil, error = "NO_ATTACKER_DATA" }
    end

    -- Validate defender exists
    if typeof(defenderUserId) ~= "number" then
        return { success = false, battleId = nil, error = "INVALID_DEFENDER" }
    end

    -- Load defender data (may be offline)
    local defenderData = DataService:GetPlayerDataById(defenderUserId)
    if not defenderData then
        return { success = false, battleId = nil, error = "DEFENDER_NOT_FOUND" }
    end

    -- Check attacker isn't already in battle
    for _, battle in _activeBattles do
        if battle.attackerId == attacker.UserId then
            return { success = false, battleId = nil, error = "ALREADY_IN_BATTLE" }
        end
    end

    -- Check attacker has troops
    local availableTroops = TroopService:GetAvailableTroops(attacker)
    local hasTroops = false
    for _ in availableTroops do
        hasTroops = true
        break
    end
    if not hasTroops then
        return { success = false, battleId = nil, error = "NO_TROOPS" }
    end

    -- Check defender has shield (revenge attacks ignore shields)
    local isRevenge = options and options.isRevenge or false
    if not isRevenge then
        if defenderData.shield and defenderData.shield.active then
            if os.time() < defenderData.shield.expiresAt then
                return { success = false, battleId = nil, error = "DEFENDER_HAS_SHIELD" }
            end
        end
    end

    -- Calculate available loot
    local lootAvailable = EconomyService:CalculateAvailableLoot(defenderData)

    -- Generate battle ID
    local battleId = HttpService:GenerateGUID(false)
    local now = os.time()

    -- Create battle state
    local battleState: CombatTypes.BattleState = {
        id = battleId,
        attackerId = attacker.UserId,
        defenderId = defenderUserId,
        defenderCityId = defenderData.activeCityId or "",
        startedAt = now,
        endsAt = now + BalanceConfig.Combat.BattleDuration,
        scoutEndsAt = now + BalanceConfig.Combat.ScoutDuration,
        phase = "scout",
        troops = {},
        spells = {},
        destruction = 0,
        starsEarned = 0,
        townHallDestroyed = false,
        remainingTroops = table.clone(availableTroops),
        remainingSpells = {}, -- Populated below from player data
        lootAvailable = lootAvailable,
        lootClaimed = { gold = 0, wood = 0, food = 0 },
        isRevenge = isRevenge,
    }

    -- Populate remaining spells from player data
    local availableSpells = attackerData.spells or {}
    for spellType, count in availableSpells do
        if typeof(count) == "number" and count > 0 then
            local spellDef = SpellData.GetByType(spellType)
            if spellDef then
                battleState.remainingSpells[spellType] = count
            end
        end
    end

    -- Store battle state
    _activeBattles[battleId] = battleState

    -- Store building targets (internal, not in battle state)
    local targets = getDefenderBuildings(defenderData)

    -- Apply wall HP bonus from defense research
    local completedResearch = (defenderData.research and defenderData.research.completed) or {}
    local hasWallBonus = false
    for _, researchId in completedResearch do
        if researchId == "defense_walls" then
            hasWallBonus = true
            break
        end
    end
    if hasWallBonus then
        for _, target in targets do
            if target.category == "wall" then
                target.maxHp = math.floor(target.maxHp * 1.5) -- +50% HP
                target.currentHp = target.maxHp
            end
        end
    end

    _activeBattles[battleId .. "_targets"] = targets :: any
    _activeBattles[battleId .. "_totalHp"] = calculateTotalBuildingHp(targets) :: any
    _activeBattles[battleId .. "_defenderData"] = defenderData :: any
    _activeBattles[battleId .. "_defenderResearch"] = (defenderData.research and defenderData.research.completed) or {} :: any
    _activeBattles[battleId .. "_buildingLastAttack"] = {} :: any
    _activeBattles[battleId .. "_activeSpells"] = {} :: any

    -- Fire event
    CombatService.BattleStarted:Fire(attacker.UserId, defenderUserId, battleId)

    return { success = true, battleId = battleId, error = nil }
end

--[[
    Deploys a troop in the battle.
]]
function CombatService:DeployTroop(
    player: Player,
    battleId: string,
    troopType: string,
    position: Vector3
): DeployResult
    -- Validate battle
    local battle = _activeBattles[battleId]
    if not battle then
        return { success = false, deployedUnit = nil, error = "BATTLE_NOT_FOUND" }
    end

    -- Validate ownership
    if battle.attackerId ~= player.UserId then
        return { success = false, deployedUnit = nil, error = "NOT_YOUR_BATTLE" }
    end

    -- Validate phase
    local now = os.time()
    if now < battle.scoutEndsAt then
        return { success = false, deployedUnit = nil, error = "SCOUT_PHASE" }
    end
    if now > battle.endsAt then
        return { success = false, deployedUnit = nil, error = "BATTLE_ENDED" }
    end
    if battle.phase == "ended" then
        return { success = false, deployedUnit = nil, error = "BATTLE_ENDED" }
    end

    -- Switch to deploy phase if needed
    if battle.phase == "scout" then
        battle.phase = "deploy"
    end

    -- Validate troop type
    if typeof(troopType) ~= "string" then
        return { success = false, deployedUnit = nil, error = "INVALID_TROOP_TYPE" }
    end

    local troopDef = TroopData.GetByType(troopType)
    if not troopDef then
        return { success = false, deployedUnit = nil, error = "INVALID_TROOP_TYPE" }
    end

    -- Validate position
    if typeof(position) ~= "Vector3" then
        return { success = false, deployedUnit = nil, error = "INVALID_POSITION" }
    end

    if not isValidDeployPosition(position) then
        return { success = false, deployedUnit = nil, error = "INVALID_DEPLOY_POSITION" }
    end

    -- Check player has this troop type available
    local available = battle.remainingTroops[troopType] or 0
    if available <= 0 then
        return { success = false, deployedUnit = nil, error = "NO_TROOPS_AVAILABLE" }
    end

    -- Get troop level data
    local playerData = DataService:GetPlayerData(player)
    local level = 1 -- TODO: Get from lab upgrades
    local levelData = TroopData.GetLevelData(troopType, level)
    if not levelData then
        return { success = false, deployedUnit = nil, error = "NO_LEVEL_DATA" }
    end

    -- Consume from remaining
    battle.remainingTroops[troopType] = available - 1
    if battle.remainingTroops[troopType] <= 0 then
        battle.remainingTroops[troopType] = nil
    end

    -- Consume from player's army
    TroopService:ConsumeTroops(player, troopType, 1)

    -- Create deployed troop
    local deployedTroop: CombatTypes.DeployedTroop = {
        id = HttpService:GenerateGUID(false),
        type = troopType,
        level = level,
        position = position,
        targetPosition = nil,
        currentHp = levelData.hp,
        maxHp = levelData.hp,
        state = "moving",
        targetId = nil,
        deployedAt = now,
        lastAttackAt = nil,
    }

    table.insert(battle.troops, deployedTroop)

    -- Switch to battle phase
    if battle.phase == "deploy" then
        battle.phase = "battle"
    end

    -- Fire event
    CombatService.TroopDeployed:Fire(battleId, deployedTroop)

    return { success = true, deployedUnit = deployedTroop, error = nil }
end

--[[
    Deploys a spell in the battle.
]]
function CombatService:DeploySpell(
    player: Player,
    battleId: string,
    spellType: string,
    position: Vector3
): SpellDeployResult
    -- Validate battle
    local battle = _activeBattles[battleId]
    if not battle then
        return { success = false, deployedSpell = nil, error = "BATTLE_NOT_FOUND" }
    end

    -- Validate ownership
    if battle.attackerId ~= player.UserId then
        return { success = false, deployedSpell = nil, error = "NOT_YOUR_BATTLE" }
    end

    -- Validate phase
    local now = os.time()
    if now < battle.scoutEndsAt then
        return { success = false, deployedSpell = nil, error = "SCOUT_PHASE" }
    end
    if now > battle.endsAt then
        return { success = false, deployedSpell = nil, error = "BATTLE_ENDED" }
    end
    if battle.phase == "ended" then
        return { success = false, deployedSpell = nil, error = "BATTLE_ENDED" }
    end

    -- Validate spell type
    if typeof(spellType) ~= "string" then
        return { success = false, deployedSpell = nil, error = "INVALID_SPELL_TYPE" }
    end

    -- Validate position
    if typeof(position) ~= "Vector3" then
        return { success = false, deployedSpell = nil, error = "INVALID_POSITION" }
    end

    -- Look up spell data
    local spellDef = SpellData.GetByType(spellType)
    if not spellDef then
        return { success = false, deployedSpell = nil, error = "INVALID_SPELL_TYPE" }
    end

    -- Get level data (default level 1 for now)
    local spellLevel = 1
    local levelData = SpellData.GetLevelData(spellType, spellLevel)
    if not levelData then
        return { success = false, deployedSpell = nil, error = "INVALID_SPELL_LEVEL" }
    end

    -- Check the player has this spell available
    local remaining = battle.remainingSpells[spellType]
    if not remaining or remaining <= 0 then
        return { success = false, deployedSpell = nil, error = "NO_SPELLS_REMAINING" }
    end

    -- Decrement remaining count
    battle.remainingSpells[spellType] = remaining - 1
    if battle.remainingSpells[spellType] <= 0 then
        battle.remainingSpells[spellType] = nil
    end

    -- Switch to battle phase if needed
    if battle.phase == "scout" then
        battle.phase = "deploy"
    end
    if battle.phase == "deploy" then
        battle.phase = "battle"
    end

    local radius = levelData.radius or 3
    local duration = levelData.duration or 0

    -- Apply instant spells immediately
    if spellType == "Lightning" then
        -- Lightning: instant AoE damage to buildings in radius
        local targets = _activeBattles[battleId .. "_targets"] :: {BuildingTarget}
        if targets then
            local totalDamage = levelData.totalDamage or 150
            local numberOfStrikes = levelData.numberOfStrikes or 6
            local damagePerStrike = totalDamage / numberOfStrikes

            for _, target in targets do
                if target.isDestroyed then continue end
                local dist = (target.position - position).Magnitude
                if dist <= radius then
                    -- Apply all strikes as instant damage
                    local totalDmg = damagePerStrike * numberOfStrikes
                    target.currentHp -= totalDmg

                    if target.currentHp <= 0 then
                        if target.type == "Farm" then
                            target.isDestroyed = false
                            target.currentHp = 1
                            target.wasDowngraded = true
                        else
                            target.isDestroyed = true
                            if target.type == "TownHall" then
                                battle.townHallDestroyed = true
                            end
                        end
                    end
                end
            end
        end

    elseif spellType == "Earthquake" then
        -- Earthquake: instant % HP damage to buildings in radius
        local targets = _activeBattles[battleId .. "_targets"] :: {BuildingTarget}
        if targets then
            local damagePercent = (levelData.buildingDamagePercent or 14) / 100
            local wallMultiplier = levelData.wallDamageMultiplier or 4

            for _, target in targets do
                if target.isDestroyed then continue end
                local dist = (target.position - position).Magnitude
                if dist <= radius then
                    local percentDmg = damagePercent
                    if target.category == "wall" then
                        percentDmg = percentDmg * wallMultiplier
                    end

                    -- Earthquake deals % of max HP as damage
                    local damage = target.maxHp * percentDmg
                    target.currentHp -= damage

                    -- Earthquake cannot fully destroy buildings (minimum 1 HP)
                    -- but walls can be destroyed
                    if target.currentHp <= 0 then
                        if target.category == "wall" then
                            target.isDestroyed = true
                        elseif target.type == "Farm" then
                            target.isDestroyed = false
                            target.currentHp = 1
                            target.wasDowngraded = true
                        else
                            -- Earthquake leaves buildings at minimum 1 HP
                            target.currentHp = 1
                        end
                    end
                end
            end
        end

    else
        -- Duration-based spells: Heal, Rage, Freeze, Jump
        -- Add to active spells list for per-tick processing
        local activeSpells = _activeBattles[battleId .. "_activeSpells"] :: {ActiveSpell}
        if activeSpells then
            local activeSpell: ActiveSpell = {
                id = HttpService:GenerateGUID(false),
                type = spellType,
                level = spellLevel,
                position = position,
                radius = radius,
                startTime = now,
                duration = duration,
                levelData = levelData,
            }
            table.insert(activeSpells, activeSpell)
        end
    end

    -- Create deployed spell record
    local deployedSpell: CombatTypes.DeployedSpell = {
        id = HttpService:GenerateGUID(false),
        type = spellType,
        level = spellLevel,
        position = position,
        radius = radius,
        deployedAt = now,
        expiresAt = now + duration,
    }

    table.insert(battle.spells, deployedSpell)

    -- Fire event
    CombatService.SpellDeployed:Fire(battleId, deployedSpell)

    return { success = true, deployedSpell = deployedSpell, error = nil }
end

--[[
    Runs one tick of battle simulation.
]]
function CombatService:SimulateTick(battleId: string)
    local battle = _activeBattles[battleId]
    if not battle then return end
    if battle.phase ~= "battle" then return end

    local now = os.time()

    -- Check if battle ended by time
    if now >= battle.endsAt then
        self:EndBattle(battleId)
        return
    end

    local targets = _activeBattles[battleId .. "_targets"] :: {BuildingTarget}
    local totalHp = _activeBattles[battleId .. "_totalHp"] :: number
    local activeSpells = _activeBattles[battleId .. "_activeSpells"] :: {ActiveSpell}

    -- === PROCESS ACTIVE SPELLS: compute per-tick flags ===
    -- Clear per-tick spell flags on troops
    local troopRageBuff: {[string]: {damageBoost: number, speedBoost: number}} = {}
    local troopIgnoreWalls: {[string]: boolean} = {}
    local frozenBuildings: {[string]: boolean} = {}

    if activeSpells then
        -- Remove expired spells (iterate in reverse for safe removal)
        local i = #activeSpells
        while i >= 1 do
            local spell = activeSpells[i]
            if now >= spell.startTime + spell.duration then
                table.remove(activeSpells, i)
            end
            i -= 1
        end

        -- Apply per-tick effects for each active spell
        for _, spell in activeSpells do
            local ld = spell.levelData

            if spell.type == "Heal" then
                -- Heal: restore HP to troops within radius
                local healAmount = (ld.healPerSecond or 35) * TICK_RATE
                for _, troop in battle.troops do
                    if troop.state == "dead" then continue end
                    local dist = (troop.position - spell.position).Magnitude
                    if dist <= spell.radius then
                        troop.currentHp = math.min(troop.currentHp + healAmount, troop.maxHp)
                    end
                end

            elseif spell.type == "Rage" then
                -- Rage: flag troops in radius for damage/speed boost
                local damageBoost = ld.damageBoost or 1.3
                local speedBoost = ld.speedBoost or 1.2
                for _, troop in battle.troops do
                    if troop.state == "dead" then continue end
                    local dist = (troop.position - spell.position).Magnitude
                    if dist <= spell.radius then
                        -- Use the strongest rage buff if multiple overlap
                        local existing = troopRageBuff[troop.id]
                        if not existing or damageBoost > existing.damageBoost then
                            troopRageBuff[troop.id] = {
                                damageBoost = damageBoost,
                                speedBoost = speedBoost,
                            }
                        end
                    end
                end

            elseif spell.type == "Freeze" then
                -- Freeze: flag buildings in radius as frozen (skip defense firing)
                for _, building in targets do
                    if building.isDestroyed then continue end
                    local dist = (building.position - spell.position).Magnitude
                    if dist <= spell.radius then
                        frozenBuildings[building.id] = true
                    end
                end

            elseif spell.type == "Jump" then
                -- Jump: flag troops in radius to ignore walls
                for _, troop in battle.troops do
                    if troop.state == "dead" then continue end
                    local dist = (troop.position - spell.position).Magnitude
                    if dist <= spell.radius then
                        troopIgnoreWalls[troop.id] = true
                    end
                end
            end
        end
    end

    -- Simulate each troop
    for _, troop in battle.troops do
        if troop.state == "dead" then continue end

        local troopDef = TroopData.GetByType(troop.type)
        if not troopDef then continue end

        local levelData = TroopData.GetLevelData(troop.type, troop.level)
        if not levelData then continue end

        -- Find target (Jump spell makes troops ignore walls)
        local effectiveTargets = targets
        if troopIgnoreWalls[troop.id] then
            -- Filter out walls for troops under Jump spell effect
            effectiveTargets = {}
            for _, t in targets do
                if t.category ~= "wall" or t.isDestroyed then
                    table.insert(effectiveTargets, t)
                end
            end
            -- If all non-wall targets are destroyed, fall back to all targets
            local hasNonWall = false
            for _, t in effectiveTargets do
                if not t.isDestroyed then
                    hasNonWall = true
                    break
                end
            end
            if not hasNonWall then
                effectiveTargets = targets
            end
        end

        local target = findNearestTarget(troop, effectiveTargets, levelData)
        if not target then
            -- No targets left, battle complete
            troop.state = "moving"
            continue
        end

        local distance = (target.position - troop.position).Magnitude
        local attackRange = levelData.attackRange or 0.4

        if distance <= attackRange then
            -- In range, attack
            troop.state = "attacking"
            troop.targetId = target.id

            -- Check attack cooldown (1 attack per second based on DPS)
            local attackInterval = 1.0 -- 1 second between attacks
            if troop.lastAttackAt and (now - troop.lastAttackAt) < attackInterval then
                continue
            end

            troop.lastAttackAt = now

            -- Deal damage
            local damage = levelData.dps * attackInterval

            -- Apply Rage spell damage boost
            local rageBuff = troopRageBuff[troop.id]
            if rageBuff then
                damage = damage * rageBuff.damageBoost
            end

            -- Wall breaker bonus
            if target.category == "wall" and levelData.wallDamageMultiplier then
                damage = damage * levelData.wallDamageMultiplier
            end

            -- Splash damage
            if levelData.splashRadius and levelData.splashRadius > 0 then
                for _, otherTarget in targets do
                    if otherTarget.isDestroyed then continue end
                    if otherTarget.id == target.id then continue end

                    local splashDistance = (otherTarget.position - target.position).Magnitude
                    if splashDistance <= levelData.splashRadius then
                        otherTarget.currentHp -= damage * 0.5 -- 50% splash damage
                        if otherTarget.currentHp <= 0 then
                            otherTarget.isDestroyed = true
                        end
                    end
                end
            end

            -- Apply main damage
            target.currentHp -= damage
            if target.currentHp <= 0 then
                -- Special handling for Farms: downgrade instead of destroy
                if target.type == "Farm" then
                    target.isDestroyed = false
                    target.currentHp = 1
                    target.wasDowngraded = true
                else
                    target.isDestroyed = true

                    -- Check if Town Hall destroyed
                    if target.type == "TownHall" then
                        battle.townHallDestroyed = true
                    end
                end
            end
        else
            -- Move towards target
            troop.state = "moving"
            troop.targetId = target.id

            local direction = (target.position - troop.position).Unit
            local moveSpeed = levelData.moveSpeed or 16

            -- Apply Rage spell speed boost
            local rageBuff = troopRageBuff[troop.id]
            if rageBuff then
                moveSpeed = moveSpeed * rageBuff.speedBoost
            end

            local moveDistance = moveSpeed * TICK_RATE

            troop.position = troop.position + (direction * moveDistance)
        end
    end

    -- === DEFENSE BUILDING AI ===
    -- Buildings fire at troops based on defender's research
    local defenderResearch = _activeBattles[battleId .. "_defenderResearch"] :: {string}
    local buildingLastAttack = _activeBattles[battleId .. "_buildingLastAttack"] :: {[string]: number}

    if defenderResearch and #defenderResearch > 0 then
        -- Build lookup table for research
        local researchLookup = {}
        for _, researchId in defenderResearch do
            researchLookup[researchId] = true
        end

        -- Calculate defense bonuses from research
        local defenseDamageBonus = 1.0
        local defenseRangeBonus = 1.0
        if researchLookup["defense_damage_1"] then defenseDamageBonus = defenseDamageBonus + 0.15 end
        if researchLookup["defense_damage_2"] then defenseDamageBonus = defenseDamageBonus + 0.25 end
        if researchLookup["defense_range_1"] then defenseRangeBonus = defenseRangeBonus + 0.10 end

        -- Map building types to their research activation requirement
        local buildingToResearch = {
            Cannon = "defense_basic",
            ArcherTower = "defense_archery",
            Mortar = "defense_splash",
            AirDefense = "defense_anti_air",
            WizardTower = "defense_magic",
        }

        local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)

        for _, building in targets do
            if building.isDestroyed then continue end

            -- Skip frozen buildings (Freeze spell effect)
            if frozenBuildings[building.id] then continue end

            -- Check if this is a defense building
            local requiredResearch = buildingToResearch[building.type]
            if not requiredResearch then continue end

            -- Check if defender has researched this building's activation
            if not researchLookup[requiredResearch] then continue end

            -- Get building stats from BuildingData
            local buildingDef = BuildingData.GetByType(building.type)
            if not buildingDef then continue end

            -- Find the building's level (stored in defenderData)
            local defenderData2 = _activeBattles[battleId .. "_defenderData"]
            local buildingLevel = 1
            if defenderData2 and defenderData2.buildings and defenderData2.buildings[building.id] then
                buildingLevel = defenderData2.buildings[building.id].level or 1
            end

            local levelData = BuildingData.GetLevelData(building.type, buildingLevel)
            if not levelData then continue end

            -- Check attack cooldown
            local attackSpeed = levelData.attackSpeed or 1
            local attackInterval = 1.0 / attackSpeed
            local lastAttack = buildingLastAttack[building.id] or 0
            if (now - lastAttack) < attackInterval then continue end

            -- Get building range (with research bonus)
            local range = (levelData.range or 9) * defenseRangeBonus

            -- Get target type this building can attack
            local targetType = levelData.targetType or "ground"

            -- Find nearest troop in range
            local nearestTroop = nil
            local nearestDistance = math.huge

            for _, troop in battle.troops do
                if troop.state == "dead" then continue end

                -- Check target type compatibility
                local troopDef = TroopData.GetByType(troop.type)
                if not troopDef then continue end
                local troopLevelData = TroopData.GetLevelData(troop.type, troop.level)
                if not troopLevelData then continue end

                local troopTargetType = troopLevelData.targetType or "ground"

                -- Building targets "ground" can only hit ground troops
                -- Building targets "air" can only hit air troops
                -- Building targets "both" can hit either
                if targetType == "ground" and troopTargetType == "air" then continue end
                if targetType == "air" and troopTargetType ~= "air" then continue end

                local dist = (building.position - troop.position).Magnitude
                if dist <= range and dist < nearestDistance then
                    nearestTroop = troop
                    nearestDistance = dist
                end
            end

            if nearestTroop then
                -- Fire at troop!
                buildingLastAttack[building.id] = now

                -- Calculate damage (with research bonus)
                local damage = (levelData.damage or 10) * defenseDamageBonus

                -- Apply splash damage for Mortar and WizardTower
                local splashRadius = levelData.splashRadius
                if splashRadius and splashRadius > 0 then
                    for _, troop in battle.troops do
                        if troop.state == "dead" then continue end
                        if troop.id == nearestTroop.id then continue end

                        local splashDist = (troop.position - nearestTroop.position).Magnitude
                        if splashDist <= splashRadius then
                            troop.currentHp -= damage * 0.5
                            if troop.currentHp <= 0 then
                                troop.currentHp = 0
                                troop.state = "dead"
                            end
                        end
                    end
                end

                -- Apply main damage to target troop
                nearestTroop.currentHp -= damage
                if nearestTroop.currentHp <= 0 then
                    nearestTroop.currentHp = 0
                    nearestTroop.state = "dead"
                end
            end
        end
    end

    -- Calculate destruction percentage
    local destroyedHp = 0
    for _, target in targets do
        if target.isDestroyed then
            destroyedHp += target.maxHp
        else
            destroyedHp += (target.maxHp - target.currentHp)
        end
    end

    if totalHp > 0 then
        battle.destruction = math.floor((destroyedHp / totalHp) * 100)
    end

    -- Calculate stars
    local stars = 0
    for _, threshold in BalanceConfig.Combat.VictoryThresholds do
        if battle.destruction >= threshold.destruction then
            stars = threshold.stars
        end
    end

    -- Town Hall gives 1 star
    if battle.townHallDestroyed and stars < 1 then
        stars = 1
    end

    battle.starsEarned = stars

    -- Check if all buildings destroyed
    local allDestroyed = true
    for _, target in targets do
        if not target.isDestroyed then
            allDestroyed = false
            break
        end
    end

    if allDestroyed then
        self:EndBattle(battleId)
        return
    end

    -- Check if all troops dead
    local allDead = true
    for _, troop in battle.troops do
        if troop.state ~= "dead" then
            allDead = false
            break
        end
    end

    -- Check if no troops left and no more to deploy
    local hasTroopsRemaining = false
    for _ in battle.remainingTroops do
        hasTroopsRemaining = true
        break
    end

    if allDead and not hasTroopsRemaining then
        self:EndBattle(battleId)
        return
    end

    -- Fire tick event
    CombatService.BattleTick:Fire(battleId, battle)
end

--[[
    Ends a battle and calculates results.
]]
function CombatService:EndBattle(battleId: string): CombatTypes.BattleResult?
    local battle = _activeBattles[battleId]
    if not battle then return nil end
    if battle.phase == "ended" then return nil end

    battle.phase = "ended"

    local defenderData = _activeBattles[battleId .. "_defenderData"]
    local now = os.time()

    -- Determine victory threshold
    local victoryData = BalanceConfig.Combat.VictoryThresholds[1]
    for _, threshold in BalanceConfig.Combat.VictoryThresholds do
        if battle.destruction >= threshold.destruction then
            victoryData = threshold
        end
    end

    -- Calculate loot based on destruction
    local lootPercent = victoryData.lootPercent
    local loot = {
        gold = math.floor(battle.lootAvailable.gold * lootPercent),
        wood = math.floor(battle.lootAvailable.wood * lootPercent),
        food = math.floor(battle.lootAvailable.food * lootPercent),
    }

    -- Town Hall bonus
    if battle.townHallDestroyed then
        local thBonus = BalanceConfig.Economy.Loot.TownHallBonus
        loot.gold = math.floor(loot.gold * (1 + thBonus))
        loot.wood = math.floor(loot.wood * (1 + thBonus))
        loot.food = math.floor(loot.food * (1 + thBonus))
    end

    -- Revenge loot bonus (+20%)
    if battle.isRevenge then
        local revengeBonus = BalanceConfig.Combat.RevengeLootBonus
        loot.gold = math.floor(loot.gold * (1 + revengeBonus))
        loot.wood = math.floor(loot.wood * (1 + revengeBonus))
        loot.food = math.floor(loot.food * (1 + revengeBonus))
    end

    -- Calculate trophies with TH level difference multiplier
    local trophyConfig = BalanceConfig.Combat.Trophies
    local trophiesGained = 0
    local defenderTrophyLoss = 0

    -- Calculate TH level difference multiplier
    local attackerTHLevel = 1
    local defenderTHLevel = defenderData and defenderData.townHallLevel or 1
    local attacker = Players:GetPlayerByUserId(battle.attackerId)
    if attacker then
        local attackerData = DataService:GetPlayerData(attacker)
        if attackerData then
            attackerTHLevel = attackerData.townHallLevel or 1
        end
    end

    local thDifference = defenderTHLevel - attackerTHLevel -- positive = attacking higher TH
    local thMultiplier = 1.0
    if thDifference > 0 then
        -- Attacking higher TH = more trophies gained
        thMultiplier = math.pow(trophyConfig.THDifferenceMultiplier, thDifference)
    elseif thDifference < 0 then
        -- Attacking lower TH = fewer trophies gained
        thMultiplier = math.pow(1 / trophyConfig.THDifferenceMultiplier, math.abs(thDifference))
    end

    if battle.starsEarned > 0 then
        trophiesGained = math.floor(trophyConfig.BaseWin * (battle.starsEarned / 3) * thMultiplier)
        defenderTrophyLoss = math.floor(trophyConfig.BaseLoss * thMultiplier)
    else
        trophiesGained = -math.floor(trophyConfig.BaseLoss * thMultiplier)
        defenderTrophyLoss = 0 -- Defender gains trophies on successful defense
    end

    -- Calculate XP
    local xpGained = 0
    if battle.starsEarned > 0 then
        xpGained = BalanceConfig.Progression.XPRewards.BattleWin
    else
        xpGained = BalanceConfig.Progression.XPRewards.BattleLoss
    end

    -- Count troops lost
    local troopsLost = {}
    for _, troop in battle.troops do
        if troop.state == "dead" or troop.currentHp < troop.maxHp then
            troopsLost[troop.type] = (troopsLost[troop.type] or 0) + 1
        end
    end

    -- Count spells used
    local spellsUsed: {[string]: number} = {}
    for _, spell in battle.spells do
        spellsUsed[spell.type] = (spellsUsed[spell.type] or 0) + 1
    end

    -- Count buildings destroyed
    local buildingsDestroyed = 0
    local targets = _activeBattles[battleId .. "_targets"] :: {BuildingTarget}
    for _, target in targets do
        if target.isDestroyed then
            buildingsDestroyed += 1
        end
    end

    -- Create result
    local result: CombatTypes.BattleResult = {
        battleId = battleId,
        victory = battle.starsEarned > 0,
        destruction = battle.destruction,
        stars = battle.starsEarned,
        isConquest = battle.destruction >= 100,
        loot = loot,
        trophiesGained = trophiesGained,
        xpGained = xpGained,
        duration = now - battle.startedAt,
        troopsLost = troopsLost,
        spellsUsed = spellsUsed,
        buildingsDestroyed = buildingsDestroyed,
        isRevenge = battle.isRevenge or false,
        revengeLootBonus = battle.isRevenge and BalanceConfig.Combat.RevengeLootBonus or 0,
    }

    -- Apply rewards to attacker
    if attacker then
        -- Add loot
        DataService:UpdateResources(attacker, loot :: any)

        -- Update trophies and stats
        local attackerData = DataService:GetPlayerData(attacker)
        if attackerData then
            attackerData.trophies.current = math.max(0, attackerData.trophies.current + trophiesGained)
            attackerData.trophies.allTime = math.max(attackerData.trophies.allTime, attackerData.trophies.current)

            if result.victory then
                attackerData.stats.attacksWon += 1
            end
            attackerData.stats.buildingsDestroyed += buildingsDestroyed

            -- Add XP
            attackerData.stats.xp += xpGained
            -- TODO: Level up check
        end
    end

    -- Apply losses to defender
    if defenderData then
        -- Apply farm downgrades (farms are downgraded to level 1, not destroyed)
        for _, target in targets do
            if target.type == "Farm" and target.wasDowngraded then
                local building = defenderData.buildings[target.id]
                if building then
                    building.level = 1
                    -- Reset HP to level 1 HP
                    local farmDef = require(ReplicatedStorage.Shared.Constants.BuildingData).GetLevelData("Farm", 1)
                    if farmDef then
                        building.currentHp = farmDef.hp
                        building.maxHp = farmDef.hp
                    end
                end
            end
        end

        -- Deduct looted resources
        defenderData.resources.gold = math.max(0, defenderData.resources.gold - loot.gold)
        defenderData.resources.wood = math.max(0, defenderData.resources.wood - loot.wood)
        defenderData.resources.food = math.max(0, defenderData.resources.food - loot.food)

        -- Update defender trophies
        if result.victory then
            defenderData.trophies.current = math.max(0, defenderData.trophies.current - defenderTrophyLoss)
        else
            -- Successful defense: defender gains trophies
            local defenseGain = math.floor(trophyConfig.BaseWin * (1 / thMultiplier))
            defenderData.trophies.current += defenseGain
            defenderData.trophies.allTime = math.max(defenderData.trophies.allTime or 0, defenderData.trophies.current)
            defenderData.stats.defensesWon += 1
        end

        -- Apply shield based on stars
        local shieldDuration = 0
        if battle.starsEarned == 1 then
            shieldDuration = BalanceConfig.Combat.ShieldDuration.OneStar * 3600
        elseif battle.starsEarned == 2 then
            shieldDuration = BalanceConfig.Combat.ShieldDuration.TwoStar * 3600
        elseif battle.starsEarned >= 3 then
            shieldDuration = BalanceConfig.Combat.ShieldDuration.ThreeStar * 3600
        end

        if shieldDuration > 0 then
            defenderData.shield = {
                active = true,
                expiresAt = now + shieldDuration,
                source = "attack",
            }
        end

        -- Get attacker name (may be offline in edge cases)
        local attackerName = "Unknown"
        if attacker then
            attackerName = attacker.Name
        end

        -- Add to revenge list
        table.insert(defenderData.revengeList, {
            attackerId = battle.attackerId,
            attackerName = attackerName,
            attackTime = now,
            expiresAt = now + (BalanceConfig.Combat.RevengeWindow * 3600),
            used = false,
        })

        -- Add defense log entry (used by DefenseLogUI on client)
        if not defenderData.defenseLog then
            defenderData.defenseLog = {}
        end

        table.insert(defenderData.defenseLog, {
            attackerId = battle.attackerId,
            attackerName = attackerName,
            stars = result.stars,
            destruction = result.destruction,
            goldStolen = loot.gold,
            trophyChange = result.victory and -defenderTrophyLoss or math.floor(trophyConfig.BaseWin * (1 / thMultiplier)),
            timestamp = now,
            canRevenge = true,
        })

        -- Cap defense log to 50 entries (remove oldest)
        while #defenderData.defenseLog > 50 do
            table.remove(defenderData.defenseLog, 1)
        end

        -- Persist defender data: if defender is online, their cached data is already
        -- updated in memory and will be saved on next auto-save or logout.
        -- If defender is offline, save directly to DataStore.
        local defenderPlayer = Players:GetPlayerByUserId(battle.defenderId)
        if not defenderPlayer then
            -- Defender is offline - save directly to DataStore
            task.spawn(function()
                DataService:SavePlayerDataById(battle.defenderId, defenderData)
            end)
        end
    end

    -- Sync HUD for both players to reflect updated resources/trophies
    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    local syncEvent = eventsFolder and eventsFolder:FindFirstChild("SyncPlayerData")

    if syncEvent then
        -- Sync attacker HUD
        if attacker then
            local attackerData = DataService:GetPlayerData(attacker)
            if attackerData then
                syncEvent:FireClient(attacker, attackerData)
            end
        end

        -- Sync defender HUD if they are online
        local onlineDefender = Players:GetPlayerByUserId(battle.defenderId)
        if onlineDefender and defenderData then
            syncEvent:FireClient(onlineDefender, defenderData)
        end
    end

    -- Cleanup battle data
    task.delay(60, function()
        _activeBattles[battleId] = nil
        _activeBattles[battleId .. "_targets"] = nil
        _activeBattles[battleId .. "_totalHp"] = nil
        _activeBattles[battleId .. "_defenderData"] = nil
        _activeBattles[battleId .. "_defenderResearch"] = nil
        _activeBattles[battleId .. "_buildingLastAttack"] = nil
        _activeBattles[battleId .. "_activeSpells"] = nil
    end)

    -- Fire event
    CombatService.BattleEnded:Fire(battleId, result)

    return result
end

--[[
    Gets the current state of a battle.
]]
function CombatService:GetBattleState(battleId: string): CombatTypes.BattleState?
    return _activeBattles[battleId]
end

--[[
    Gets all active battles for a player.
]]
function CombatService:GetActiveBattlesForPlayer(player: Player): {CombatTypes.BattleState}
    local result = {}
    for _, battle in _activeBattles do
        if typeof(battle) == "table" and battle.attackerId == player.UserId then
            table.insert(result, battle)
        end
    end
    return result
end

--[[
    Initializes the CombatService.
]]
function CombatService:Init()
    if _initialized then
        warn("CombatService already initialized")
        return
    end

    -- Get service references
    local ServerScriptService = game:GetService("ServerScriptService")
    DataService = require(ServerScriptService.Services.DataService)
    TroopService = require(ServerScriptService.Services.TroopService)
    EconomyService = require(ServerScriptService.Services.EconomyService)

    -- Battle simulation loop
    task.spawn(function()
        while true do
            task.wait(TICK_RATE)

            for battleId, battle in _activeBattles do
                -- Only process actual battle states (not metadata)
                if typeof(battle) == "table" and battle.phase then
                    self:SimulateTick(battleId)
                end
            end
        end
    end)

    -- Cleanup abandoned battles
    task.spawn(function()
        while true do
            task.wait(60) -- Check every minute

            local now = os.time()
            for battleId, battle in _activeBattles do
                if typeof(battle) == "table" and battle.endsAt then
                    if now > battle.endsAt + 300 then -- 5 minutes after end time
                        if battle.phase ~= "ended" then
                            self:EndBattle(battleId)
                        end
                    end
                end
            end
        end
    end)

    _initialized = true
    print("CombatService initialized")
end

return CombatService
