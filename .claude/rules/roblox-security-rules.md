# Roblox Security Rules

**Location**: `.claude/rules/roblox-security-rules.md`

This document defines the security requirements for Battle Tycoon: Conquest. **All agents MUST follow these rules.**

---

## The Golden Rule

**NEVER TRUST THE CLIENT.**

Every piece of data from the client is potentially malicious. The server is the ONLY source of truth.

---

## Server Authority

### What Runs on Server (ALWAYS)

| System | Why Server-Side |
|--------|-----------------|
| Resource calculations | Prevent resource hacks |
| Building placement | Prevent invalid placement |
| Upgrade completion | Prevent instant upgrades |
| Troop training | Prevent instant training |
| Combat simulation | Prevent battle manipulation |
| Loot distribution | Prevent loot hacks |
| Purchase validation | Prevent free purchases |
| Player data | Prevent data tampering |

### What Runs on Client (ONLY)

| System | Notes |
|--------|-------|
| UI rendering | Display server-provided state |
| Input handling | Send requests to server |
| Animations | Visual only, no game impact |
| Sound effects | Audio feedback |
| Camera control | View manipulation |

---

## RemoteEvent Security

### Server-Side Validation Template

```lua
-- EVERY RemoteEvent handler must follow this pattern
RemoteEvent.OnServerEvent:Connect(function(player, ...)
    -- 1. RATE LIMIT
    if not RateLimiter:Check(player, "EventName") then
        return -- Too many requests
    end

    -- 2. TYPE VALIDATION
    local args = {...}
    if not validateTypes(args, expectedTypes) then
        return -- Invalid types
    end

    -- 3. RANGE VALIDATION
    if not validateRanges(args) then
        return -- Values out of range
    end

    -- 4. PERMISSION VALIDATION
    if not canPlayerDoThis(player) then
        return -- Not allowed
    end

    -- 5. STATE VALIDATION
    if not isValidGameState() then
        return -- Wrong game state
    end

    -- 6. EXECUTE (only after all validation)
    executeAction(player, ...)
end)
```

### Example: PlaceBuilding

```lua
local PlaceBuilding = ReplicatedStorage.Events.PlaceBuilding

PlaceBuilding.OnServerEvent:Connect(function(player, buildingType, gridPosition)
    -- 1. Rate limit
    if not RateLimiter:Check(player, "PlaceBuilding", 1) then
        ErrorEvent:FireClient(player, "RATE_LIMITED")
        return
    end

    -- 2. Type validation
    if typeof(buildingType) ~= "string" then
        return -- Silent fail for obvious exploit
    end
    if typeof(gridPosition) ~= "Vector3" then
        return
    end

    -- 3. Range validation
    if not BuildingData[buildingType] then
        return -- Invalid building type
    end
    if not isValidGridPosition(gridPosition) then
        return -- Position off grid
    end

    -- 4. Permission validation
    local playerData = DataService:GetPlayerData(player)
    local cost = BuildingData[buildingType].cost

    if playerData.gold < cost.gold then
        ErrorEvent:FireClient(player, "INSUFFICIENT_GOLD")
        return
    end

    if not meetsThRequirement(playerData, buildingType) then
        ErrorEvent:FireClient(player, "TH_TOO_LOW")
        return
    end

    -- 5. State validation
    if isPositionOccupied(player, gridPosition) then
        ErrorEvent:FireClient(player, "POSITION_OCCUPIED")
        return
    end

    -- 6. Execute
    local building = BuildingService:Create(player, buildingType, gridPosition)
    DataService:DeductResources(player, cost)
    SuccessEvent:FireClient(player, building)
end)
```

---

## Rate Limiting

### Implementation

```lua
local RateLimiter = {}
local _requests = {} -- [userId][action] = {count, resetTime}

function RateLimiter:Check(player: Player, action: string, limit: number?): boolean
    limit = limit or 10 -- Default 10 requests per second
    local userId = player.UserId
    local now = os.clock()

    _requests[userId] = _requests[userId] or {}
    local data = _requests[userId][action] or {count = 0, reset = now + 1}

    if now > data.reset then
        data = {count = 0, reset = now + 1}
    end

    data.count += 1
    _requests[userId][action] = data

    if data.count > limit then
        warn("Rate limit exceeded:", player.Name, action)
        return false
    end

    return true
end

-- Cleanup on player leave
Players.PlayerRemoving:Connect(function(player)
    _requests[player.UserId] = nil
end)
```

### Rate Limits by Action

| Action | Limit/Second | Notes |
|--------|--------------|-------|
| PlaceBuilding | 2 | Slow, intentional action |
| CollectResource | 10 | Quick taps |
| DeployTroop | 20 | Rapid deployment |
| UseSpell | 5 | Combat pacing |
| SendChat | 3 | Spam prevention |
| RequestData | 5 | Data fetches |

---

## Input Validation

### Type Checking

```lua
local function validateTypes(args: {any}, expected: {string}): boolean
    if #args ~= #expected then
        return false
    end

    for i, expectedType in expected do
        if typeof(args[i]) ~= expectedType then
            return false
        end
    end

    return true
end

-- Usage
if not validateTypes({buildingType, position}, {"string", "Vector3"}) then
    return
end
```

### Range Checking

```lua
local function validateNumber(value: number, min: number, max: number): boolean
    return value >= min and value <= max
end

local function validatePosition(pos: Vector3, bounds: {min: Vector3, max: Vector3}): boolean
    return pos.X >= bounds.min.X and pos.X <= bounds.max.X
       and pos.Y >= bounds.min.Y and pos.Y <= bounds.max.Y
       and pos.Z >= bounds.min.Z and pos.Z <= bounds.max.Z
end
```

### Sanity Checking

```lua
-- Check for impossible values
local function sanitizeResourceAmount(amount: number): number
    -- Negative resources impossible
    if amount < 0 then return 0 end
    -- More than max storage impossible
    if amount > MAX_STORAGE then return MAX_STORAGE end
    -- NaN or infinity impossible
    if amount ~= amount or amount == math.huge then return 0 end
    return amount
end
```

---

## Data Integrity

### DataStore Security

```lua
-- Session locking to prevent duplication
local SessionLock = {}
local _locks = {}

function SessionLock:Lock(userId: number): boolean
    if _locks[userId] then
        return false -- Already locked
    end
    _locks[userId] = os.time()
    return true
end

function SessionLock:Unlock(userId: number)
    _locks[userId] = nil
end

-- Usage in PlayerAdded
Players.PlayerAdded:Connect(function(player)
    if not SessionLock:Lock(player.UserId) then
        player:Kick("Session already active elsewhere")
        return
    end

    -- Load data...
end)

Players.PlayerRemoving:Connect(function(player)
    -- Save data...
    SessionLock:Unlock(player.UserId)
end)
```

### Data Validation on Load

```lua
function DataService:ValidatePlayerData(data: PlayerData): PlayerData
    -- Ensure all required fields exist
    data.gold = data.gold or 0
    data.wood = data.wood or 0
    data.level = data.level or 1

    -- Sanitize values
    data.gold = sanitizeResourceAmount(data.gold)
    data.wood = sanitizeResourceAmount(data.wood)
    data.level = math.clamp(data.level, 1, MAX_LEVEL)

    -- Validate relationships
    if data.trophies and data.trophies < 0 then
        data.trophies = 0
    end

    return data
end
```

---

## Purchase Verification

### MarketplaceService Verification

```lua
local MarketplaceService = game:GetService("MarketplaceService")

-- ALWAYS verify purchases server-side
MarketplaceService.ProcessReceipt = function(receiptInfo)
    local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
    if not player then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local productId = receiptInfo.ProductId
    local productConfig = ProductData[productId]

    if not productConfig then
        warn("Unknown product:", productId)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Grant the purchase
    local success = GrantPurchase(player, productConfig)

    if success then
        -- Log for audit
        LogService:LogPurchase(player, productId, receiptInfo.PurchaseId)
        return Enum.ProductPurchaseDecision.PurchaseGranted
    else
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end
```

---

## Combat Security

### Server-Authoritative Battle

```lua
-- Battle simulation runs ENTIRELY on server
local BattleService = {}

function BattleService:StartBattle(attacker: Player, defenderData: CityData)
    local battleId = HttpService:GenerateGUID()

    -- Server creates battle state
    local battleState = {
        id = battleId,
        attacker = attacker.UserId,
        defender = defenderData.ownerId,
        startTime = os.time(),
        endTime = os.time() + 180, -- 3 minutes
        troopsDeployed = {},
        destruction = 0,
    }

    -- Store server-side
    _activeBattles[battleId] = battleState

    -- Client only receives battle ID and can send deploy commands
    return battleId
end

-- Client sends deploy request
function BattleService:DeployTroop(player: Player, battleId: string, troopType: string, position: Vector3)
    local battle = _activeBattles[battleId]

    -- Validate battle belongs to player
    if not battle or battle.attacker ~= player.UserId then
        return
    end

    -- Validate battle still active
    if os.time() > battle.endTime then
        return
    end

    -- Validate player has troops
    local available = TroopService:GetAvailable(player, troopType)
    if available <= 0 then
        return
    end

    -- Server adds troop to simulation
    table.insert(battle.troopsDeployed, {
        type = troopType,
        position = position,
        deployTime = os.time()
    })

    TroopService:ConsumeOne(player, troopType)
end
```

---

## Common Exploits to Prevent

### 1. Speed Hacks

```lua
-- Server tracks time, ignores client claims
function TrainingService:CompleteTraining(player: Player, queueId: string)
    local queue = _trainingQueues[player.UserId][queueId]

    -- Server checks if enough time passed
    if os.time() < queue.completesAt then
        return -- Not done yet
    end

    -- Complete training
    grantTroop(player, queue.troopType)
end
```

### 2. Teleport Hacks

```lua
-- Validate movement in battle
function BattleService:ValidateTroopPosition(troop, newPosition)
    local maxDistance = troop.speed * TICK_RATE * 1.1 -- 10% tolerance
    local actual = (newPosition - troop.position).Magnitude

    if actual > maxDistance then
        return false -- Moving too fast
    end

    return true
end
```

### 3. Resource Duplication

```lua
-- Session locking + atomic operations
function TradeService:ExecuteTrade(player1, player2, offer1, offer2)
    -- Lock both players
    local lock1 = TransactionLock:Acquire(player1.UserId)
    local lock2 = TransactionLock:Acquire(player2.UserId)

    if not lock1 or not lock2 then
        TransactionLock:Release(player1.UserId)
        TransactionLock:Release(player2.UserId)
        return { success = false, error = "LOCK_FAILED" }
    end

    -- Validate both have resources
    -- Deduct from both
    -- Add to both
    -- Save both

    TransactionLock:Release(player1.UserId)
    TransactionLock:Release(player2.UserId)
end
```

---

## Security Checklist

Before releasing ANY feature:

### Server Authority
- [ ] ALL game logic runs on server
- [ ] Client only sends requests
- [ ] Client renders server-provided state

### Input Validation
- [ ] All RemoteEvent inputs validated
- [ ] Type checking on all parameters
- [ ] Range checking on all numbers
- [ ] Rate limiting implemented

### Resource Security
- [ ] Resources calculated server-side
- [ ] Timers enforced server-side
- [ ] Purchases verified with MarketplaceService

### Data Integrity
- [ ] Session locking implemented
- [ ] Data validated on load
- [ ] Atomic transactions for multi-player operations

### Logging
- [ ] Security events logged
- [ ] Suspicious activity flagged
- [ ] Audit trail for purchases
