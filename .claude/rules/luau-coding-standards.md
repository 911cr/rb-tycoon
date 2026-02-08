# Luau Coding Standards

**Location**: `.claude/rules/luau-coding-standards.md`

This document defines the coding standards for all Luau code in Battle Tycoon: Conquest.

---

## General Principles

1. **Readability First**: Code is read more than written
2. **Explicit Over Implicit**: Be clear about intentions
3. **Type Safety**: Use Luau's type system
4. **Performance Aware**: Consider memory and CPU
5. **Security Conscious**: Never trust client data

---

## Naming Conventions

### Variables and Functions

```lua
-- Local variables: camelCase
local playerData = {}
local goldAmount = 100

-- Constants: UPPER_SNAKE_CASE
local MAX_BUILDINGS = 100
local TICK_RATE = 0.1

-- Private members: prefix with underscore
local Service = {}
Service._cache = {}
Service._initialized = false

-- Boolean variables: use "is", "has", "can" prefix
local isReady = true
local hasShield = player.shield ~= nil
local canUpgrade = level < MAX_LEVEL
```

### Types and Classes

```lua
-- Types: PascalCase
type PlayerData = {
    userId: number,
    username: string,
    level: number,
}

-- Modules/Classes: PascalCase
local BuildingService = {}
local CombatController = {}

-- Enums: PascalCase with UPPER values
local BuildingState = {
    IDLE = "Idle",
    UPGRADING = "Upgrading",
    PRODUCING = "Producing",
}
```

### Files and Folders

```
-- Services: [Name]Service.lua
BuildingService.lua
CombatService.lua

-- Controllers: [Name]Controller.lua
CityController.lua
BattleController.lua

-- Types: [Name]Types.lua
BuildingTypes.lua
TroopTypes.lua

-- Constants: [Name]Data.lua or [Name]Config.lua
BuildingData.lua
BalanceConfig.lua
```

---

## Code Structure

### Module Template

```lua
--!strict
-- BuildingService.lua
-- Handles building placement, upgrades, and production

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Dependencies
local Types = require(ReplicatedStorage.Shared.Types.BuildingTypes)
local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Module
local BuildingService = {}
BuildingService.__index = BuildingService

-- Private state
local _buildings: {[string]: Types.Building} = {}
local _initialized = false

-- Events
BuildingService.BuildingPlaced = Signal.new()
BuildingService.BuildingUpgraded = Signal.new()

-- Public API
function BuildingService:Init()
    if _initialized then
        warn("BuildingService already initialized")
        return
    end
    _initialized = true
end

function BuildingService:PlaceBuilding(player: Player, buildingType: string, position: Vector3): Types.BuildResult
    -- Implementation
end

function BuildingService:GetBuilding(buildingId: string): Types.Building?
    return _buildings[buildingId]
end

-- Private functions
local function validatePosition(position: Vector3): boolean
    -- Implementation
    return true
end

return BuildingService
```

### Function Structure

```lua
-- Good: Clear, typed, documented
function BuildingService:PlaceBuilding(
    player: Player,
    buildingType: string,
    position: Vector3
): Types.BuildResult
    -- Validate inputs
    if not player then
        return { success = false, error = "INVALID_PLAYER" }
    end

    if not BuildingData[buildingType] then
        return { success = false, error = "INVALID_BUILDING_TYPE" }
    end

    -- Check resources
    local cost = BuildingData[buildingType].cost
    local playerData = DataService:GetPlayerData(player)

    if playerData.gold < cost.gold then
        return { success = false, error = "INSUFFICIENT_GOLD" }
    end

    -- Execute
    local building = createBuilding(buildingType, position)
    DataService:DeductResources(player, cost)

    -- Fire event
    self.BuildingPlaced:Fire(player, building)

    return { success = true, building = building }
end
```

---

## Type System

### Always Use Strict Mode

```lua
--!strict

-- At the top of every file
```

### Define Types Explicitly

```lua
-- Types/BuildingTypes.lua
export type Building = {
    id: string,
    type: string,
    level: number,
    position: Vector3,
    state: string,
    upgradeCompletes: number?,
}

export type BuildResult = {
    success: boolean,
    building: Building?,
    error: string?,
}

export type UpgradeResult = {
    success: boolean,
    error: string?,
    completes: number?,
}
```

### Type Function Parameters and Returns

```lua
-- Good
function calculateDamage(attacker: TroopData, defender: TroopData): number
    return attacker.dps * getTypeModifier(attacker.type, defender.type)
end

-- Bad (no types)
function calculateDamage(attacker, defender)
    return attacker.dps * getTypeModifier(attacker.type, defender.type)
end
```

---

## Error Handling

### Use pcall for External Operations

```lua
-- DataStore operations
local success, result = pcall(function()
    return dataStore:GetAsync(key)
end)

if not success then
    warn("DataStore error:", result)
    return nil
end

return result
```

### Return Result Objects

```lua
-- Good: Return structured result
function BuildingService:Upgrade(buildingId: string): UpgradeResult
    local building = self:GetBuilding(buildingId)
    if not building then
        return { success = false, error = "BUILDING_NOT_FOUND" }
    end

    if building.level >= MAX_LEVEL then
        return { success = false, error = "MAX_LEVEL_REACHED" }
    end

    -- Success
    return { success = true, completes = os.time() + upgradeTime }
end

-- Bad: Return nil or throw
function BuildingService:Upgrade(buildingId: string)
    local building = self:GetBuilding(buildingId)
    if not building then
        error("Building not found") -- Don't throw
    end
    return building
end
```

---

## Performance Guidelines

### Avoid Creating Objects in Loops

```lua
-- Bad: Creates new Vector3 every iteration
for i = 1, 100 do
    local pos = Vector3.new(i, 0, 0)
    checkPosition(pos)
end

-- Good: Reuse or pool objects
local pos = Vector3.new(0, 0, 0)
for i = 1, 100 do
    pos = Vector3.new(i, 0, 0) -- Still allocates, but...
    checkPosition(pos)
end

-- Better: Use object pooling for expensive objects
local pool = {}
local function getFromPool()
    return table.remove(pool) or createExpensiveObject()
end
```

### Use task Library

```lua
-- Good
task.wait(1)
task.spawn(function() asyncWork() end)
task.delay(5, function() delayedWork() end)

-- Bad (deprecated)
wait(1)
spawn(function() asyncWork() end)
delay(5, function() delayedWork() end)
```

### Limit Event Connections

```lua
-- Good: Store and disconnect
local connection
connection = event:Connect(function()
    -- work
end)

-- Later
connection:Disconnect()

-- Bad: Never disconnect
event:Connect(function()
    -- Leaks memory
end)
```

### Cache Service References

```lua
-- Good: Cache at top of module
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Bad: Get every time
local function update()
    local rs = game:GetService("RunService") -- Slow
end
```

---

## Security Rules

### Never Trust Client Data

```lua
-- Server handling RemoteEvent
event.OnServerEvent:Connect(function(player, requestedGold)
    -- WRONG: Trust client
    playerData.gold = requestedGold

    -- RIGHT: Ignore client value, calculate server-side
    local gold = DataService:GetGold(player)
end)
```

### Validate All Inputs

```lua
function handleBuildingPlace(player, buildingType, position)
    -- Type validation
    if typeof(buildingType) ~= "string" then return end
    if typeof(position) ~= "Vector3" then return end

    -- Value validation
    if not BuildingData[buildingType] then return end
    if not isValidGridPosition(position) then return end

    -- Permission validation
    if not canPlayerBuild(player) then return end

    -- Now safe to proceed
end
```

### Rate Limit Requests

```lua
local lastRequest = {}
local RATE_LIMIT = 0.5 -- seconds

function handleRequest(player, ...)
    local now = os.clock()
    local last = lastRequest[player.UserId] or 0

    if now - last < RATE_LIMIT then
        return -- Too fast, ignore
    end

    lastRequest[player.UserId] = now
    -- Process request
end
```

---

## Documentation

### File Headers

```lua
--!strict
--[[
    BuildingService.lua

    Manages building placement, upgrades, and resource production.

    Dependencies:
    - DataService (for player data)
    - EconomyService (for resource transactions)

    Events:
    - BuildingPlaced(player, building)
    - BuildingUpgraded(player, building, newLevel)
]]

local BuildingService = {}
```

### Function Documentation

```lua
--[[
    Places a new building in the player's city.

    @param player Player - The player placing the building
    @param buildingType string - Type from BuildingData
    @param position Vector3 - Grid position for placement
    @return BuildResult - Success/failure with building or error

    @example
    local result = BuildingService:PlaceBuilding(player, "GoldMine", Vector3.new(5, 0, 10))
    if result.success then
        print("Placed:", result.building.id)
    end
]]
function BuildingService:PlaceBuilding(player: Player, buildingType: string, position: Vector3): BuildResult
```

---

## Common Patterns

### Singleton Service

```lua
local Service = {}
local instance = nil

function Service.new()
    if instance then
        return instance
    end
    instance = setmetatable({}, Service)
    return instance
end
```

### Event-Driven Communication

```lua
-- Signal implementation
local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _connections = {} }, Signal)
end

function Signal:Connect(callback)
    table.insert(self._connections, callback)
    return {
        Disconnect = function()
            local idx = table.find(self._connections, callback)
            if idx then
                table.remove(self._connections, idx)
            end
        end
    }
end

function Signal:Fire(...)
    for _, callback in self._connections do
        task.spawn(callback, ...)
    end
end
```

### Promise Pattern

```lua
local Promise = require(ReplicatedStorage.Shared.Modules.Promise)

function DataService:LoadPlayerDataAsync(player)
    return Promise.new(function(resolve, reject)
        local success, data = pcall(function()
            return dataStore:GetAsync(player.UserId)
        end)

        if success then
            resolve(data)
        else
            reject(data) -- error message
        end
    end)
end

-- Usage
DataService:LoadPlayerDataAsync(player)
    :andThen(function(data)
        print("Loaded:", data)
    end)
    :catch(function(err)
        warn("Failed:", err)
    end)
```

---

## Anti-Patterns to Avoid

```lua
-- DON'T: Global variables
MyGlobal = {} -- Pollutes global namespace

-- DO: Local modules
local MyModule = {}

-- DON'T: Magic numbers
if player.level > 5 then

-- DO: Named constants
local REQUIRED_LEVEL = 5
if player.level > REQUIRED_LEVEL then

-- DON'T: Long functions (>50 lines)
function doEverything()
    -- 200 lines of code
end

-- DO: Small, focused functions
function validateInput() end
function processData() end
function formatOutput() end

-- DON'T: Nested callbacks (callback hell)
getData(function(data)
    process(data, function(result)
        save(result, function()
            -- Deep nesting
        end)
    end)
end)

-- DO: Use Promises or structured flow
getData()
    :andThen(process)
    :andThen(save)
```
