--!strict
--[[
    ClientAPI.lua

    Shared module for accessing client actions from any controller/UI script.
    Replaces _G.ClientActions pattern with a proper module approach.

    Usage:
        local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
        ClientAPI.PlaceBuilding("GoldMine", Vector3.new(10, 0, 20))

    Note: Actions are registered by the main client script on initialization.
    Calling actions before registration will queue them until ready.
]]

local ClientAPI = {}

-- Internal state
local _actions: {[string]: (...any) -> ...any} = {}
local _queuedCalls: {{name: string, args: {any}}} = {}
local _isReady = false

--[[
    Registers a client action.
    Called by init.client.lua during setup.
]]
function ClientAPI.RegisterAction(name: string, action: (...any) -> ...any)
    _actions[name] = action
end

--[[
    Marks the API as ready and processes queued calls.
]]
function ClientAPI.SetReady()
    _isReady = true

    -- Process queued calls
    for _, call in _queuedCalls do
        local action = _actions[call.name]
        if action then
            action(table.unpack(call.args))
        else
            warn("[ClientAPI] Unknown action:", call.name)
        end
    end

    _queuedCalls = {}
end

--[[
    Checks if the API is ready.
]]
function ClientAPI.IsReady(): boolean
    return _isReady
end

-- Building actions
function ClientAPI.PlaceBuilding(buildingType: string, position: Vector3)
    if _isReady then
        local action = _actions["PlaceBuilding"]
        if action then action(buildingType, position) end
    else
        table.insert(_queuedCalls, {name = "PlaceBuilding", args = {buildingType, position}})
    end
end

function ClientAPI.UpgradeBuilding(buildingId: string)
    if _isReady then
        local action = _actions["UpgradeBuilding"]
        if action then action(buildingId) end
    else
        table.insert(_queuedCalls, {name = "UpgradeBuilding", args = {buildingId}})
    end
end

function ClientAPI.CollectResources(buildingId: string)
    if _isReady then
        local action = _actions["CollectResources"]
        if action then action(buildingId) end
    else
        table.insert(_queuedCalls, {name = "CollectResources", args = {buildingId}})
    end
end

function ClientAPI.SpeedUpUpgrade(buildingId: string)
    if _isReady then
        local action = _actions["SpeedUpUpgrade"]
        if action then action(buildingId) end
    else
        table.insert(_queuedCalls, {name = "SpeedUpUpgrade", args = {buildingId}})
    end
end

-- Troop actions
function ClientAPI.TrainTroop(troopType: string, quantity: number)
    if _isReady then
        local action = _actions["TrainTroop"]
        if action then action(troopType, quantity) end
    else
        table.insert(_queuedCalls, {name = "TrainTroop", args = {troopType, quantity}})
    end
end

function ClientAPI.CancelTraining(queueIndex: number)
    if _isReady then
        local action = _actions["CancelTraining"]
        if action then action(queueIndex) end
    else
        table.insert(_queuedCalls, {name = "CancelTraining", args = {queueIndex}})
    end
end

-- Combat actions
function ClientAPI.StartBattle(defenderUserId: number)
    if _isReady then
        local action = _actions["StartBattle"]
        if action then action(defenderUserId) end
    else
        table.insert(_queuedCalls, {name = "StartBattle", args = {defenderUserId}})
    end
end

function ClientAPI.DeployTroop(battleId: string, troopType: string, position: Vector3)
    if _isReady then
        local action = _actions["DeployTroop"]
        if action then action(battleId, troopType, position) end
    else
        table.insert(_queuedCalls, {name = "DeployTroop", args = {battleId, troopType, position}})
    end
end

function ClientAPI.DeploySpell(battleId: string, spellType: string, position: Vector3)
    if _isReady then
        local action = _actions["DeploySpell"]
        if action then action(battleId, spellType, position) end
    else
        table.insert(_queuedCalls, {name = "DeploySpell", args = {battleId, spellType, position}})
    end
end

-- Alliance actions
function ClientAPI.CreateAlliance(name: string, description: string?)
    if _isReady then
        local action = _actions["CreateAlliance"]
        if action then action(name, description or "") end
    else
        table.insert(_queuedCalls, {name = "CreateAlliance", args = {name, description or ""}})
    end
end

function ClientAPI.JoinAlliance(allianceId: string)
    if _isReady then
        local action = _actions["JoinAlliance"]
        if action then action(allianceId) end
    else
        table.insert(_queuedCalls, {name = "JoinAlliance", args = {allianceId}})
    end
end

function ClientAPI.LeaveAlliance()
    if _isReady then
        local action = _actions["LeaveAlliance"]
        if action then action() end
    else
        table.insert(_queuedCalls, {name = "LeaveAlliance", args = {}})
    end
end

function ClientAPI.DonateTroops(recipientUserId: number, troopType: string, count: number)
    if _isReady then
        local action = _actions["DonateTroops"]
        if action then action(recipientUserId, troopType, count) end
    else
        table.insert(_queuedCalls, {name = "DonateTroops", args = {recipientUserId, troopType, count}})
    end
end

-- Data access
function ClientAPI.GetPlayerData(): any?
    if _isReady then
        local action = _actions["GetPlayerData"]
        if action then return action() end
    end
    return nil
end

function ClientAPI.RequestDataSync()
    if _isReady then
        local action = _actions["RequestDataSync"]
        if action then action() end
    else
        table.insert(_queuedCalls, {name = "RequestDataSync", args = {}})
    end
end

-- Shop actions
function ClientAPI.ShopPurchase(itemId: string)
    if _isReady then
        local action = _actions["ShopPurchase"]
        if action then action(itemId) end
    else
        table.insert(_queuedCalls, {name = "ShopPurchase", args = {itemId}})
    end
end

-- Farm building (walk-through tycoon)
function ClientAPI.BuildFarm(farmNumber: number): {success: boolean, error: string?}?
    if _isReady then
        local action = _actions["BuildFarm"]
        if action then
            return action(farmNumber)
        else
            return { success = false, error = "BuildFarm action not registered" }
        end
    else
        -- For synchronous result, we can't queue this
        return { success = false, error = "Client API not ready" }
    end
end

function ClientAPI.PurchaseFarmPlot(plotNumber: number): {success: boolean, error: string?}?
    if _isReady then
        local action = _actions["PurchaseFarmPlot"]
        if action then
            return action(plotNumber)
        else
            return { success = false, error = "PurchaseFarmPlot action not registered" }
        end
    else
        return { success = false, error = "Client API not ready" }
    end
end

-- Matchmaking actions
function ClientAPI.FindOpponent()
    if _isReady then
        local action = _actions["FindOpponent"]
        if action then action() end
    else
        table.insert(_queuedCalls, {name = "FindOpponent", args = {}})
    end
end

function ClientAPI.NextOpponent()
    if _isReady then
        local action = _actions["NextOpponent"]
        if action then action() end
    else
        table.insert(_queuedCalls, {name = "NextOpponent", args = {}})
    end
end

-- Tutorial actions
function ClientAPI.CompleteTutorial()
    if _isReady then
        local action = _actions["CompleteTutorial"]
        if action then action() end
    else
        table.insert(_queuedCalls, {name = "CompleteTutorial", args = {}})
    end
end

-- Quest actions
function ClientAPI.GetDailyQuests(): any?
    if _isReady then
        local action = _actions["GetDailyQuests"]
        if action then return action() end
    end
    return {}
end

function ClientAPI.GetAchievements(): any?
    if _isReady then
        local action = _actions["GetAchievements"]
        if action then return action() end
    end
    return {}
end

function ClientAPI.ClaimQuestReward(questId: string)
    if _isReady then
        local action = _actions["ClaimQuestReward"]
        if action then action(questId) end
    else
        table.insert(_queuedCalls, {name = "ClaimQuestReward", args = {questId}})
    end
end

-- Daily reward actions
function ClientAPI.GetDailyRewardInfo(): any?
    if _isReady then
        local action = _actions["GetDailyRewardInfo"]
        if action then return action() end
    end
    return nil
end

function ClientAPI.ClaimDailyReward()
    if _isReady then
        local action = _actions["ClaimDailyReward"]
        if action then action() end
    else
        table.insert(_queuedCalls, {name = "ClaimDailyReward", args = {}})
    end
end

-- Spell actions
function ClientAPI.BrewSpell(spellType: string)
    if _isReady then
        local action = _actions["BrewSpell"]
        if action then action(spellType) end
    else
        table.insert(_queuedCalls, {name = "BrewSpell", args = {spellType}})
    end
end

function ClientAPI.CancelSpellBrewing(queueIndex: number)
    if _isReady then
        local action = _actions["CancelSpellBrewing"]
        if action then action(queueIndex) end
    else
        table.insert(_queuedCalls, {name = "CancelSpellBrewing", args = {queueIndex}})
    end
end

function ClientAPI.GetSpellQueue(): any?
    if _isReady then
        local action = _actions["GetSpellQueue"]
        if action then return action() end
    end
    return {}
end

-- Leaderboard actions
function ClientAPI.GetLeaderboard(count: number?): any?
    if _isReady then
        local action = _actions["GetLeaderboard"]
        if action then return action(count or 100) end
    end
    return {}
end

function ClientAPI.GetPlayerRank(): any?
    if _isReady then
        local action = _actions["GetPlayerRank"]
        if action then return action() end
    end
    return nil
end

function ClientAPI.GetLeaderboardInfo(): any?
    if _isReady then
        local action = _actions["GetLeaderboardInfo"]
        if action then return action() end
    end
    return nil
end

return ClientAPI
