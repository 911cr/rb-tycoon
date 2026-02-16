--!strict
--[[
    OverworldCombatService.lua

    Quick auto-clash combat system for overworld encounters.
    NOT an extension of CombatService (which does 3-minute real-time battles).

    This is a stat-pool resolution engine:
    1. Aggregate total DPS and HP for each side from TroopData
    2. Every 0.5s tick, both sides deal their DPS to enemy HP pool
    3. Spells apply flat effects (Rage: +30% DPS, Heal: restore 20% HP, Lightning: instant damage)
    4. When HP pool depletes a troop type's worth, that type loses units
    5. Battle ends when one side hits 0 troops or 60s timer expires
    6. Timer expiry: higher remaining HP% wins

    Returns AutoClashResult with troop losses and loot distribution.
    Troop consumption is REAL — DataService troops are deducted after combat.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)
local SpellData = require(ReplicatedStorage.Shared.Constants.SpellData)
local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local OverworldCombatService = {}
OverworldCombatService.__index = OverworldCombatService

-- ============================================================================
-- SIGNALS
-- ============================================================================

OverworldCombatService.CombatStarted = Signal.new()
OverworldCombatService.CombatEnded = Signal.new()

-- ============================================================================
-- TYPES
-- ============================================================================

export type TroopEntry = {
    troopType: string,
    level: number,
    count: number,
}

export type SpellEntry = {
    spellType: string,
    level: number,
}

export type ArmyComposition = {
    troops: {TroopEntry},
    spells: {SpellEntry}?,
}

export type TroopLoss = {
    troopType: string,
    lost: number,
    remaining: number,
}

export type AutoClashResult = {
    winner: "attacker" | "defender" | "draw",
    attackerLosses: {TroopLoss},
    defenderLosses: {TroopLoss},
    attackerHpPercent: number,
    defenderHpPercent: number,
    duration: number, -- seconds
    loot: {gold: number, wood: number, food: number, gems: number}?,
}

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

-- Track active combats to prevent double-engagement
local _activeCombats: {[number]: boolean} = {} -- userId -> inCombat

local TICK_INTERVAL = OverworldConfig.Wilderness.Combat.TickInterval
local MAX_DURATION = OverworldConfig.Wilderness.Combat.MaxDuration
local MIN_TICKS = math.ceil(OverworldConfig.Wilderness.Combat.MinDuration / TICK_INTERVAL)

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

--[[
    Gets the level stats for a troop type. Returns dps, hp from TroopData.
]]
local function getTroopStats(troopType: string, level: number): (number, number)
    local data = TroopData.GetLevelData(troopType, level)
    if not data then
        return 0, 0
    end
    return data.dps, data.hp
end

--[[
    Builds a combat pool from an army composition.
    Returns total DPS, total HP, and per-troop tracking for losses.
]]
local function buildPool(army: ArmyComposition): (number, number, {{troopType: string, level: number, count: number, hpPer: number, totalHp: number}})
    local totalDps = 0
    local totalHp = 0
    local troopPools = {}

    for _, entry in army.troops do
        if entry.count <= 0 then continue end

        local dps, hp = getTroopStats(entry.troopType, entry.level)
        local entryDps = dps * entry.count
        local entryHp = hp * entry.count

        totalDps += entryDps
        totalHp += entryHp

        table.insert(troopPools, {
            troopType = entry.troopType,
            level = entry.level,
            count = entry.count,
            hpPer = hp,
            totalHp = entryHp,
        })
    end

    return totalDps, totalHp, troopPools
end

--[[
    Applies a spell effect to the combat state.
    Returns (bonusDps, bonusHeal, instantDamageToEnemy).
]]
local function applySpellEffect(spell: SpellEntry): (number, number, number)
    local data = SpellData.GetLevelData(spell.spellType, spell.level)
    if not data then
        return 0, 0, 0
    end

    local spellType = spell.spellType

    if spellType == "Rage" then
        -- Rage: DPS boost expressed as flat bonus (30% of base, applied once)
        local boost = (data.damageBoost or 1.3) - 1.0
        return boost, 0, 0

    elseif spellType == "Heal" then
        -- Heal: restore a percentage of total HP (20%)
        return 0, 0.20, 0

    elseif spellType == "Lightning" then
        -- Lightning: instant damage to enemy
        return 0, 0, data.totalDamage or 500

    elseif spellType == "Freeze" then
        -- Freeze: reduce enemy DPS for this resolution (treated as 50% DPS reduction equivalent)
        -- Represented as negative damage to enemy DPS (handled specially)
        return 0, 0, 0

    elseif spellType == "Earthquake" then
        -- Earthquake: percentage damage (14-29% of total HP)
        -- In auto-clash, treat as percentage instant damage
        local percent = (data.buildingDamagePercent or 14) / 100
        return 0, 0, -percent -- negative signals percentage-based

    elseif spellType == "Jump" then
        -- Jump: no effect in auto-clash (wall-bypassing irrelevant)
        return 0, 0, 0
    end

    return 0, 0, 0
end

--[[
    Calculates troop losses from damage dealt to a pool.
    Removes troops from weakest to strongest as HP is depleted.
]]
local function calculateLosses(
    troopPools: {{troopType: string, level: number, count: number, hpPer: number, totalHp: number}},
    damage: number
): {TroopLoss}
    local losses: {TroopLoss} = {}
    local remainingDamage = damage

    -- Sort by HP per unit (weakest die first)
    local sorted = table.clone(troopPools)
    table.sort(sorted, function(a, b) return a.hpPer < b.hpPer end)

    for _, pool in sorted do
        if remainingDamage <= 0 then
            table.insert(losses, {
                troopType = pool.troopType,
                lost = 0,
                remaining = pool.count,
            })
            continue
        end

        -- How many full troops can this damage kill?
        local killed = math.min(pool.count, math.floor(remainingDamage / pool.hpPer))
        remainingDamage -= killed * pool.hpPer

        table.insert(losses, {
            troopType = pool.troopType,
            lost = killed,
            remaining = pool.count - killed,
        })
    end

    return losses
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Checks if a player is currently in combat.

    @param userId number
    @return boolean
]]
function OverworldCombatService:IsInCombat(userId: number): boolean
    return _activeCombats[userId] == true
end

--[[
    Marks a player as in/out of combat.

    @param userId number
    @param inCombat boolean
]]
function OverworldCombatService:SetCombatState(userId: number, inCombat: boolean)
    if inCombat then
        _activeCombats[userId] = true
    else
        _activeCombats[userId] = nil
    end
end

--[[
    Runs a quick auto-clash between two armies.
    This is the core combat resolution engine.

    The battle ticks every 0.5s. Each tick:
    - Both sides deal their DPS to the enemy HP pool
    - Spells are applied at the start (one-time effects)
    - Troops are removed as their HP worth is depleted

    @param attackerArmy ArmyComposition - Attacker's troops and spells
    @param defenderArmy ArmyComposition - Defender's troops and spells
    @param statMultiplier number? - Multiplier for defender stats (e.g. 2.5x for forbidden zone)
    @return AutoClashResult
]]
function OverworldCombatService:StartAutoClash(
    attackerArmy: ArmyComposition,
    defenderArmy: ArmyComposition,
    statMultiplier: number?
): AutoClashResult
    local multiplier = statMultiplier or 1.0

    -- Build combat pools
    local atkDps, atkTotalHp, atkPools = buildPool(attackerArmy)
    local defDps, defTotalHp, defPools = buildPool(defenderArmy)

    -- Apply stat multiplier to defender
    defDps *= multiplier
    defTotalHp *= multiplier
    for _, pool in defPools do
        pool.hpPer *= multiplier
        pool.totalHp *= multiplier
    end

    -- Store original HP for percentage calculations
    local atkOriginalHp = atkTotalHp
    local defOriginalHp = defTotalHp

    -- Apply spells (one-time effects at battle start)
    local atkDpsBonus = 0
    local defDpsBonus = 0
    local atkHealPercent = 0
    local defHealPercent = 0

    -- Attacker spells affect attacker DPS and deal damage to defender
    if attackerArmy.spells then
        for _, spell in attackerArmy.spells do
            local dpsBoost, healPct, instantDmg = applySpellEffect(spell)
            atkDpsBonus += dpsBoost

            if healPct > 0 then
                atkHealPercent += healPct
            end

            if instantDmg > 0 then
                -- Flat damage to defender
                defTotalHp -= instantDmg
            elseif instantDmg < 0 then
                -- Percentage damage (Earthquake)
                defTotalHp -= defTotalHp * math.abs(instantDmg)
            end
        end
    end

    -- Defender spells affect defender DPS and deal damage to attacker
    if defenderArmy.spells then
        for _, spell in defenderArmy.spells do
            local dpsBoost, healPct, instantDmg = applySpellEffect(spell)
            defDpsBonus += dpsBoost

            if healPct > 0 then
                defHealPercent += healPct
            end

            if instantDmg > 0 then
                atkTotalHp -= instantDmg
            elseif instantDmg < 0 then
                atkTotalHp -= atkTotalHp * math.abs(instantDmg)
            end
        end
    end

    -- Apply heal spells
    if atkHealPercent > 0 then
        atkTotalHp = math.min(atkOriginalHp, atkTotalHp + atkOriginalHp * atkHealPercent)
    end
    if defHealPercent > 0 then
        defTotalHp = math.min(defOriginalHp, defTotalHp + defOriginalHp * defHealPercent)
    end

    -- Apply DPS bonuses
    local effectiveAtkDps = atkDps * (1 + atkDpsBonus)
    local effectiveDefDps = defDps * (1 + defDpsBonus)

    -- Clamp HP to 0 minimum after spells
    atkTotalHp = math.max(0, atkTotalHp)
    defTotalHp = math.max(0, defTotalHp)

    -- Track total damage dealt for loss calculation
    local totalDmgToAttacker = 0
    local totalDmgToDefender = 0

    -- Tick-based combat resolution
    local maxTicks = math.ceil(MAX_DURATION / TICK_INTERVAL)
    local ticksElapsed = 0

    for _ = 1, maxTicks do
        ticksElapsed += 1

        -- Both sides deal damage simultaneously
        local atkDmgThisTick = effectiveAtkDps * TICK_INTERVAL
        local defDmgThisTick = effectiveDefDps * TICK_INTERVAL

        defTotalHp -= atkDmgThisTick
        atkTotalHp -= defDmgThisTick

        totalDmgToDefender += atkDmgThisTick
        totalDmgToAttacker += defDmgThisTick

        -- Scale DPS down as troops die (proportional to remaining HP)
        if defOriginalHp > 0 then
            local defHpRatio = math.max(0, defTotalHp) / defOriginalHp
            effectiveDefDps = defDps * (1 + defDpsBonus) * defHpRatio
        end
        if atkOriginalHp > 0 then
            local atkHpRatio = math.max(0, atkTotalHp) / atkOriginalHp
            effectiveAtkDps = atkDps * (1 + atkDpsBonus) * atkHpRatio
        end

        -- Check for battle end
        if ticksElapsed >= MIN_TICKS then
            if atkTotalHp <= 0 or defTotalHp <= 0 then
                break
            end
        end
    end

    -- Determine winner
    local atkHpPercent = math.max(0, atkTotalHp) / math.max(1, atkOriginalHp)
    local defHpPercent = math.max(0, defTotalHp) / math.max(1, defOriginalHp)

    local winner: "attacker" | "defender" | "draw"
    if atkTotalHp <= 0 and defTotalHp <= 0 then
        winner = "draw"
    elseif defTotalHp <= 0 then
        winner = "attacker"
    elseif atkTotalHp <= 0 then
        winner = "defender"
    elseif atkHpPercent > defHpPercent then
        winner = "attacker"
    elseif defHpPercent > atkHpPercent then
        winner = "defender"
    else
        winner = "draw"
    end

    -- Calculate troop losses
    local attackerLosses = calculateLosses(atkPools, totalDmgToAttacker)
    local defenderLosses = calculateLosses(defPools, totalDmgToDefender)

    local duration = ticksElapsed * TICK_INTERVAL

    local result: AutoClashResult = {
        winner = winner,
        attackerLosses = attackerLosses,
        defenderLosses = defenderLosses,
        attackerHpPercent = math.floor(atkHpPercent * 100),
        defenderHpPercent = math.floor(defHpPercent * 100),
        duration = duration,
        loot = nil, -- Caller sets loot based on context (bandit, PvP, boss)
    }

    return result
end

--[[
    Convenience wrapper for PvE encounters (bandits, bosses).
    Generates a defender army from a troop composition table
    and applies zone stat multiplier.

    @param attackerArmy ArmyComposition
    @param enemyTroops {TroopEntry} - Enemy troop composition
    @param zoneMult number? - Zone stat multiplier (default 1.0)
    @return AutoClashResult
]]
function OverworldCombatService:RunPvEClash(
    attackerArmy: ArmyComposition,
    enemyTroops: {TroopEntry},
    zoneMult: number?
): AutoClashResult
    local defenderArmy: ArmyComposition = {
        troops = enemyTroops,
        spells = nil, -- PvE enemies don't use spells
    }

    return self:StartAutoClash(attackerArmy, defenderArmy, zoneMult)
end

--[[
    Convenience wrapper for co-op encounters.
    Merges multiple player armies into one attacker pool.

    @param playerArmies {ArmyComposition} - Array of player armies
    @param enemyTroops {TroopEntry} - Enemy troop composition
    @param zoneMult number? - Zone stat multiplier
    @return AutoClashResult, {number} - Result and per-player contribution percentages
]]
function OverworldCombatService:RunCoopClash(
    playerArmies: {ArmyComposition},
    enemyTroops: {TroopEntry},
    zoneMult: number?
): (AutoClashResult, {number})
    -- Calculate contribution by housing space
    local contributions: {number} = {}
    local totalSpace = 0

    for i, army in playerArmies do
        local space = 0
        for _, entry in army.troops do
            local troopDef = TroopData.GetByType(entry.troopType)
            if troopDef then
                space += (troopDef.housingSpace or 1) * entry.count
            end
        end
        contributions[i] = space
        totalSpace += space
    end

    -- Normalize contributions to percentages
    for i, space in contributions do
        contributions[i] = if totalSpace > 0 then space / totalSpace else 0
    end

    -- Merge all armies into one
    local mergedTroops: {TroopEntry} = {}
    local mergedSpells: {SpellEntry} = {}

    for _, army in playerArmies do
        for _, troop in army.troops do
            -- Try to merge with existing entry of same type+level
            local found = false
            for _, existing in mergedTroops do
                if existing.troopType == troop.troopType and existing.level == troop.level then
                    existing.count += troop.count
                    found = true
                    break
                end
            end
            if not found then
                table.insert(mergedTroops, {
                    troopType = troop.troopType,
                    level = troop.level,
                    count = troop.count,
                })
            end
        end

        if army.spells then
            for _, spell in army.spells do
                table.insert(mergedSpells, spell)
            end
        end
    end

    local mergedArmy: ArmyComposition = {
        troops = mergedTroops,
        spells = if #mergedSpells > 0 then mergedSpells else nil,
    }

    local result = self:StartAutoClash(mergedArmy, {troops = enemyTroops}, zoneMult)

    return result, contributions
end

--[[
    Cleans up combat state for a player (e.g. on disconnect).

    @param userId number
]]
function OverworldCombatService:CleanupPlayer(userId: number)
    _activeCombats[userId] = nil
end

return OverworldCombatService
