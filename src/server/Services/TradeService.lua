--!strict
--[[
    TradeService.lua

    Manages player-to-player resource trading.
    Server-authoritative: validates resources, atomic swaps, prevents exploits.

    SECURITY:
    - All trade logic is server-authoritative
    - Client only sends trade requests (propose, respond, cancel)
    - Resources are validated before and during trade execution
    - Rate limited: 5 seconds between proposals per player
    - One active trade per player at a time
    - Trades expire after 60 seconds

    Dependencies:
    - DataService (player data / resource operations)
    - Signal (event system)
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declaration for DataService (resolved in Init)
local DataService

local TradeService = {}
TradeService.__index = TradeService

-- Events
TradeService.TradeProposed = Signal.new()   -- (proposer, target, tradeState)
TradeService.TradeCompleted = Signal.new()  -- (tradeState)
TradeService.TradeCancelled = Signal.new()  -- (tradeState, reason)

-- Private state
local _initialized = false

-- [tradeId] = TradeState
local _activeTrades: {[string]: {
    id: string,
    proposer: Player,
    proposerUserId: number,
    target: Player,
    targetUserId: number,
    offering: { gold: number, wood: number, food: number },
    requesting: { gold: number, wood: number, food: number },
    status: string,
    createdAt: number,
    expiresAt: number,
}} = {}

-- [userId] = tradeId (one active trade per player)
local _playerTrades: {[number]: string} = {}

-- [userId] = lastTradeTime (rate limiting)
local _rateLimits: {[number]: number} = {}

-- Constants
local TRADE_RATE_LIMIT = 5 -- seconds between proposals per player
local TRADE_EXPIRY = 60 -- seconds before a trade auto-expires
local MAX_RESOURCE_VALUE = 99999999999999 -- sanity cap per resource type

--[[
    Cleans up a trade from all tracking tables.
    Removes references from _activeTrades and _playerTrades for both players.
]]
local function cleanupTrade(tradeId: string)
    local trade = _activeTrades[tradeId]
    if trade then
        _playerTrades[trade.proposerUserId] = nil
        _playerTrades[trade.targetUserId] = nil
        _activeTrades[tradeId] = nil
    end
end

--[[
    Validates that a resource table has valid non-negative integer values
    for gold, wood, and food. Also checks sanity caps.

    @param resources table - The resource table to validate
    @return boolean - True if all values are valid
]]
local function validateResourceTable(resources: any): boolean
    if typeof(resources) ~= "table" then return false end

    local gold = resources.gold
    local wood = resources.wood
    local food = resources.food

    -- All fields must be numbers
    if typeof(gold) ~= "number" then return false end
    if typeof(wood) ~= "number" then return false end
    if typeof(food) ~= "number" then return false end

    -- Check for NaN/Infinity
    if gold ~= gold or gold == math.huge or gold == -math.huge then return false end
    if wood ~= wood or wood == math.huge or wood == -math.huge then return false end
    if food ~= food or food == math.huge or food == -math.huge then return false end

    -- Must be non-negative
    if gold < 0 or wood < 0 or food < 0 then return false end

    -- Sanity cap
    if gold > MAX_RESOURCE_VALUE or wood > MAX_RESOURCE_VALUE or food > MAX_RESOURCE_VALUE then return false end

    return true
end

--[[
    Checks if a resource table has at least one non-zero value.

    @param resources table - The resource table to check
    @return boolean - True if at least one resource is > 0
]]
local function hasNonZeroResources(resources: {gold: number, wood: number, food: number}): boolean
    return resources.gold > 0 or resources.wood > 0 or resources.food > 0
end

--[[
    Initializes TradeService. Resolves DataService reference and
    sets up player cleanup on disconnect.
]]
function TradeService:Init()
    if _initialized then
        warn("[TradeService] Already initialized")
        return
    end

    -- Resolve service references
    DataService = require(ServerScriptService.Services.DataService)

    -- Clean up trades when players leave
    Players.PlayerRemoving:Connect(function(player)
        local tradeId = _playerTrades[player.UserId]
        if tradeId then
            local trade = _activeTrades[tradeId]
            if trade and trade.status == "pending" then
                trade.status = "cancelled"
                -- Notify the other player via signal
                TradeService.TradeCancelled:Fire(trade, "player_left")
            end
            cleanupTrade(tradeId)
        end
        _rateLimits[player.UserId] = nil
    end)

    _initialized = true
    print("[TradeService] Initialized")
end

--[[
    Proposes a new trade from one player to another.

    @param proposer Player - The player initiating the trade
    @param targetUserId number - UserId of the player to trade with
    @param offering table - Resources the proposer is giving { gold, wood, food }
    @param requesting table - Resources the proposer wants in return { gold, wood, food }
    @return boolean, string? - Success flag, and tradeId on success or error string on failure
]]
function TradeService:ProposeTrade(
    proposer: Player,
    targetUserId: number,
    offering: { gold: number, wood: number, food: number },
    requesting: { gold: number, wood: number, food: number }
): (boolean, string?)
    -- 1. Rate limit: 5 seconds between proposals
    local now = os.clock()
    local lastTrade = _rateLimits[proposer.UserId] or 0
    if now - lastTrade < TRADE_RATE_LIMIT then
        return false, "RATE_LIMITED"
    end
    _rateLimits[proposer.UserId] = now

    -- 2. Validate proposer is not already in a trade
    if _playerTrades[proposer.UserId] then
        return false, "ALREADY_IN_TRADE"
    end

    -- 3. Validate target is not already in a trade
    if _playerTrades[targetUserId] then
        return false, "TARGET_IN_TRADE"
    end

    -- 4. Validate target is online
    local target = Players:GetPlayerByUserId(targetUserId)
    if not target then
        return false, "TARGET_OFFLINE"
    end

    -- 5. Validate proposer is not targeting themselves
    if proposer.UserId == targetUserId then
        return false, "CANNOT_TRADE_SELF"
    end

    -- 6. Validate offering and requesting tables
    if not validateResourceTable(offering) then
        return false, "INVALID_OFFERING"
    end
    if not validateResourceTable(requesting) then
        return false, "INVALID_REQUESTING"
    end

    -- 7. Validate at least one side has non-zero resources
    if not hasNonZeroResources(offering) and not hasNonZeroResources(requesting) then
        return false, "EMPTY_TRADE"
    end

    -- 8. Validate proposer can afford their offering
    if not DataService then
        return false, "SERVICE_UNAVAILABLE"
    end

    local canAfford = DataService:CanAfford(proposer, {
        gold = offering.gold,
        wood = offering.wood,
        food = offering.food,
    })
    if not canAfford then
        return false, "INSUFFICIENT_RESOURCES"
    end

    -- 9. Generate trade ID
    local tradeId = HttpService:GenerateGUID(false)

    -- 10. Create TradeState
    local createdAt = os.time()
    local trade = {
        id = tradeId,
        proposer = proposer,
        proposerUserId = proposer.UserId,
        target = target,
        targetUserId = targetUserId,
        offering = {
            gold = offering.gold,
            wood = offering.wood,
            food = offering.food,
        },
        requesting = {
            gold = requesting.gold,
            wood = requesting.wood,
            food = requesting.food,
        },
        status = "pending",
        createdAt = createdAt,
        expiresAt = createdAt + TRADE_EXPIRY,
    }

    -- 11. Store in tracking tables
    _activeTrades[tradeId] = trade
    _playerTrades[proposer.UserId] = tradeId
    _playerTrades[targetUserId] = tradeId

    -- 12. Start expiry timer
    task.delay(TRADE_EXPIRY, function()
        self:ExpireTrade(tradeId)
    end)

    -- 13. Fire signal
    TradeService.TradeProposed:Fire(proposer, target, trade)

    print(string.format(
        "[TradeService] Trade proposed: %s -> %s (id=%s) offering G:%d W:%d F:%d, requesting G:%d W:%d F:%d",
        proposer.Name, target.Name, tradeId,
        offering.gold, offering.wood, offering.food,
        requesting.gold, requesting.wood, requesting.food
    ))

    return true, tradeId
end

--[[
    Responds to a pending trade (accept or decline).

    @param responder Player - The player responding (must be the target)
    @param tradeId string - The trade ID to respond to
    @param accepted boolean - True to accept, false to decline
    @return boolean, string? - Success flag and optional error string
]]
function TradeService:RespondToTrade(responder: Player, tradeId: string, accepted: boolean): (boolean, string?)
    -- 1. Validate trade exists and is pending
    local trade = _activeTrades[tradeId]
    if not trade then
        return false, "TRADE_NOT_FOUND"
    end
    if trade.status ~= "pending" then
        return false, "TRADE_NOT_PENDING"
    end

    -- 2. Validate responder is the target
    if responder.UserId ~= trade.targetUserId then
        return false, "NOT_TRADE_TARGET"
    end

    -- 3. Handle decline
    if not accepted then
        trade.status = "declined"
        TradeService.TradeCancelled:Fire(trade, "declined")
        cleanupTrade(tradeId)
        print(string.format("[TradeService] Trade %s declined by %s", tradeId, responder.Name))
        return true, nil
    end

    -- 4. Handle accept: re-validate both players still have resources
    if not DataService then
        trade.status = "cancelled"
        TradeService.TradeCancelled:Fire(trade, "service_unavailable")
        cleanupTrade(tradeId)
        return false, "SERVICE_UNAVAILABLE"
    end

    -- Check proposer is still online
    local proposer = Players:GetPlayerByUserId(trade.proposerUserId)
    if not proposer then
        trade.status = "cancelled"
        TradeService.TradeCancelled:Fire(trade, "proposer_left")
        cleanupTrade(tradeId)
        return false, "PROPOSER_OFFLINE"
    end

    -- Re-validate proposer can afford their offering
    local proposerCanAfford = DataService:CanAfford(proposer, {
        gold = trade.offering.gold,
        wood = trade.offering.wood,
        food = trade.offering.food,
    })
    if not proposerCanAfford then
        trade.status = "cancelled"
        TradeService.TradeCancelled:Fire(trade, "proposer_insufficient")
        cleanupTrade(tradeId)
        return false, "PROPOSER_INSUFFICIENT_RESOURCES"
    end

    -- Validate target can afford the requesting amounts (what target gives)
    local targetCanAfford = DataService:CanAfford(responder, {
        gold = trade.requesting.gold,
        wood = trade.requesting.wood,
        food = trade.requesting.food,
    })
    if not targetCanAfford then
        trade.status = "cancelled"
        TradeService.TradeCancelled:Fire(trade, "target_insufficient")
        cleanupTrade(tradeId)
        return false, "TARGET_INSUFFICIENT_RESOURCES"
    end

    -- 5. Perform atomic swap
    -- Step A: Deduct offering from proposer
    local deductProposer = DataService:DeductResources(proposer, {
        gold = trade.offering.gold,
        wood = trade.offering.wood,
        food = trade.offering.food,
    })
    if not deductProposer then
        trade.status = "cancelled"
        TradeService.TradeCancelled:Fire(trade, "deduct_failed")
        cleanupTrade(tradeId)
        return false, "DEDUCT_FAILED"
    end

    -- Step B: Deduct requesting from target
    local deductTarget = DataService:DeductResources(responder, {
        gold = trade.requesting.gold,
        wood = trade.requesting.wood,
        food = trade.requesting.food,
    })
    if not deductTarget then
        -- Rollback: give back proposer's resources
        DataService:UpdateResources(proposer, {
            gold = trade.offering.gold,
            wood = trade.offering.wood,
            food = trade.offering.food,
        })
        trade.status = "cancelled"
        TradeService.TradeCancelled:Fire(trade, "deduct_failed")
        cleanupTrade(tradeId)
        return false, "DEDUCT_FAILED"
    end

    -- Step C: Add offering to target
    DataService:UpdateResources(responder, {
        gold = trade.offering.gold,
        wood = trade.offering.wood,
        food = trade.offering.food,
    })

    -- Step D: Add requesting to proposer
    DataService:UpdateResources(proposer, {
        gold = trade.requesting.gold,
        wood = trade.requesting.wood,
        food = trade.requesting.food,
    })

    -- 6. Sync HUD for both players
    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    local syncEvent = eventsFolder and eventsFolder:FindFirstChild("SyncPlayerData")
    if syncEvent then
        local proposerData = DataService:GetPlayerData(proposer)
        if proposerData then
            (syncEvent :: RemoteEvent):FireClient(proposer, proposerData)
        end

        local targetData = DataService:GetPlayerData(responder)
        if targetData then
            (syncEvent :: RemoteEvent):FireClient(responder, targetData)
        end
    end

    -- 7. Mark trade as accepted and clean up
    trade.status = "accepted"
    TradeService.TradeCompleted:Fire(trade)
    cleanupTrade(tradeId)

    print(string.format(
        "[TradeService] Trade %s completed: %s <-> %s",
        tradeId, proposer.Name, responder.Name
    ))

    return true, nil
end

--[[
    Cancels a pending trade. Only the proposer can cancel.

    @param player Player - The player cancelling (must be the proposer)
    @param tradeId string - The trade ID to cancel
    @return boolean, string? - Success flag and optional error string
]]
function TradeService:CancelTrade(player: Player, tradeId: string): (boolean, string?)
    -- 1. Validate trade exists and is pending
    local trade = _activeTrades[tradeId]
    if not trade then
        return false, "TRADE_NOT_FOUND"
    end
    if trade.status ~= "pending" then
        return false, "TRADE_NOT_PENDING"
    end

    -- 2. Validate player is the proposer
    if player.UserId ~= trade.proposerUserId then
        return false, "NOT_TRADE_PROPOSER"
    end

    -- 3. Cancel the trade
    trade.status = "cancelled"
    TradeService.TradeCancelled:Fire(trade, "cancelled")
    cleanupTrade(tradeId)

    print(string.format("[TradeService] Trade %s cancelled by %s", tradeId, player.Name))

    return true, nil
end

--[[
    Expires a trade if it is still pending after the expiry timeout.
    Called automatically via task.delay when the trade is created.

    @param tradeId string - The trade ID to expire
]]
function TradeService:ExpireTrade(tradeId: string)
    local trade = _activeTrades[tradeId]
    if not trade then return end
    if trade.status ~= "pending" then return end

    trade.status = "expired"
    TradeService.TradeCancelled:Fire(trade, "expired")
    cleanupTrade(tradeId)

    print(string.format("[TradeService] Trade %s expired", tradeId))
end

--[[
    Returns the active trade for a player, if any.

    @param player Player - The player to check
    @return table? - The trade state or nil
]]
function TradeService:GetActiveTrade(player: Player): any?
    local tradeId = _playerTrades[player.UserId]
    if not tradeId then return nil end
    return _activeTrades[tradeId]
end

--[[
    Returns a trade state by ID (for Main.server.lua handlers).

    @param tradeId string - The trade ID to look up
    @return table? - The trade state or nil
]]
function TradeService:GetTradeById(tradeId: string): any?
    return _activeTrades[tradeId]
end

return TradeService
