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
]]
function CombatService:StartBattle(attacker: Player, defenderUserId: number): StartBattleResult
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

    -- Check defender has shield
    if defenderData.shield and defenderData.shield.active then
        if os.time() < defenderData.shield.expiresAt then
            return { success = false, battleId = nil, error = "DEFENDER_HAS_SHIELD" }
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
        remainingSpells = {}, -- TODO: Add spell support
        lootAvailable = lootAvailable,
        lootClaimed = { gold = 0, wood = 0, food = 0 },
    }

    -- Store battle state
    _activeBattles[battleId] = battleState

    -- Store building targets (internal, not in battle state)
    local targets = getDefenderBuildings(defenderData)
    _activeBattles[battleId .. "_targets"] = targets :: any
    _activeBattles[battleId .. "_totalHp"] = calculateTotalBuildingHp(targets) :: any
    _activeBattles[battleId .. "_defenderData"] = defenderData :: any

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

    -- TODO: Load SpellData similar to TroopData
    -- For now, return not implemented
    return { success = false, deployedSpell = nil, error = "SPELLS_NOT_IMPLEMENTED" }
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

    -- Simulate each troop
    for _, troop in battle.troops do
        if troop.state == "dead" then continue end

        local troopDef = TroopData.GetByType(troop.type)
        if not troopDef then continue end

        local levelData = TroopData.GetLevelData(troop.type, troop.level)
        if not levelData then continue end

        -- Find target
        local target = findNearestTarget(troop, targets, levelData)
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
                target.isDestroyed = true

                -- Check if Town Hall destroyed
                if target.type == "TownHall" then
                    battle.townHallDestroyed = true
                end
            end
        else
            -- Move towards target
            troop.state = "moving"
            troop.targetId = target.id

            local direction = (target.position - troop.position).Unit
            local moveSpeed = levelData.moveSpeed or 16
            local moveDistance = moveSpeed * TICK_RATE

            troop.position = troop.position + (direction * moveDistance)
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

    -- Calculate trophies
    local trophyConfig = BalanceConfig.Combat.Trophies
    local trophiesGained = 0
    if battle.starsEarned > 0 then
        trophiesGained = math.floor(trophyConfig.BaseWin * (battle.starsEarned / 3))
    else
        trophiesGained = -trophyConfig.BaseLoss
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
        spellsUsed = {},
        buildingsDestroyed = buildingsDestroyed,
    }

    -- Apply rewards to attacker
    local attacker = Players:GetPlayerByUserId(battle.attackerId)
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
        -- Deduct looted resources
        defenderData.resources.gold = math.max(0, defenderData.resources.gold - loot.gold)
        defenderData.resources.wood = math.max(0, defenderData.resources.wood - loot.wood)
        defenderData.resources.food = math.max(0, defenderData.resources.food - loot.food)

        -- Update defender trophies
        if result.victory then
            defenderData.trophies.current = math.max(0, defenderData.trophies.current - trophyConfig.BaseLoss)
        else
            defenderData.trophies.current += trophyConfig.BaseWin
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

        -- Add to revenge list
        if attacker then
            table.insert(defenderData.revengeList, {
                attackerId = battle.attackerId,
                attackerName = attacker.Name,
                attackTime = now,
                expiresAt = now + (BalanceConfig.Combat.RevengeWindow * 3600),
                used = false,
            })
        end

        -- Note: Defender data will be saved when they next login or by periodic save
    end

    -- Cleanup battle data
    task.delay(60, function()
        _activeBattles[battleId] = nil
        _activeBattles[battleId .. "_targets"] = nil
        _activeBattles[battleId .. "_totalHp"] = nil
        _activeBattles[battleId .. "_defenderData"] = nil
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
