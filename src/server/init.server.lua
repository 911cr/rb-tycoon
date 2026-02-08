--!strict
--[[
    Server Entry Point

    Initializes all server services in correct order.
    This script runs when the server starts.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("Battle Tycoon: Conquest - Server Starting...")

-- Wait for shared modules to be accessible
repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Shared")

-- Service initialization order matters
-- DataService must be first as other services depend on it
local Services = ServerScriptService:WaitForChild("Services")

-- Initialize services in dependency order
local initOrder = {
    "DataService",
    "BuildingService",
    "EconomyService",
    -- "TroopService",     -- TODO: Implement
    -- "CombatService",    -- TODO: Implement
    -- "AllianceService",  -- TODO: Implement
}

for _, serviceName in initOrder do
    local serviceModule = Services:FindFirstChild(serviceName)
    if serviceModule then
        local success, err = pcall(function()
            local service = require(serviceModule)
            if service.Init then
                service:Init()
            end
        end)

        if success then
            print(string.format("[SERVER] %s initialized", serviceName))
        else
            warn(string.format("[SERVER] Failed to initialize %s: %s", serviceName, err))
        end
    else
        warn(string.format("[SERVER] Service not found: %s", serviceName))
    end
end

-- Setup RemoteEvents for client-server communication
local function setupRemoteEvents()
    local Events = Instance.new("Folder")
    Events.Name = "Events"
    Events.Parent = ReplicatedStorage

    -- Building events
    local PlaceBuilding = Instance.new("RemoteEvent")
    PlaceBuilding.Name = "PlaceBuilding"
    PlaceBuilding.Parent = Events

    local UpgradeBuilding = Instance.new("RemoteEvent")
    UpgradeBuilding.Name = "UpgradeBuilding"
    UpgradeBuilding.Parent = Events

    local CollectResources = Instance.new("RemoteEvent")
    CollectResources.Name = "CollectResources"
    CollectResources.Parent = Events

    local SpeedUpUpgrade = Instance.new("RemoteEvent")
    SpeedUpUpgrade.Name = "SpeedUpUpgrade"
    SpeedUpUpgrade.Parent = Events

    -- Response events
    local ServerResponse = Instance.new("RemoteEvent")
    ServerResponse.Name = "ServerResponse"
    ServerResponse.Parent = Events

    -- Data sync event
    local SyncPlayerData = Instance.new("RemoteEvent")
    SyncPlayerData.Name = "SyncPlayerData"
    SyncPlayerData.Parent = Events

    return Events
end

local Events = setupRemoteEvents()

-- Connect RemoteEvent handlers with security validation
local RateLimiter = {}
local function checkRateLimit(player: Player, action: string, limit: number): boolean
    local now = os.clock()
    RateLimiter[player.UserId] = RateLimiter[player.UserId] or {}
    local playerLimits = RateLimiter[player.UserId]

    playerLimits[action] = playerLimits[action] or { count = 0, reset = now + 1 }
    local data = playerLimits[action]

    if now > data.reset then
        data.count = 0
        data.reset = now + 1
    end

    data.count += 1
    return data.count <= limit
end

-- Building placement handler
Events.PlaceBuilding.OnServerEvent:Connect(function(player, buildingType, position)
    -- Rate limit
    if not checkRateLimit(player, "PlaceBuilding", 2) then
        Events.ServerResponse:FireClient(player, "PlaceBuilding", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if typeof(buildingType) ~= "string" then return end
    if typeof(position) ~= "Vector3" then return end

    -- Execute
    local BuildingService = require(Services.BuildingService)
    local result = BuildingService:PlaceBuilding(player, buildingType, position)

    Events.ServerResponse:FireClient(player, "PlaceBuilding", result)
end)

-- Building upgrade handler
Events.UpgradeBuilding.OnServerEvent:Connect(function(player, buildingId)
    -- Rate limit
    if not checkRateLimit(player, "UpgradeBuilding", 2) then
        Events.ServerResponse:FireClient(player, "UpgradeBuilding", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if typeof(buildingId) ~= "string" then return end

    -- Execute
    local BuildingService = require(Services.BuildingService)
    local result = BuildingService:UpgradeBuilding(player, buildingId)

    Events.ServerResponse:FireClient(player, "UpgradeBuilding", result)
end)

-- Resource collection handler
Events.CollectResources.OnServerEvent:Connect(function(player, buildingId)
    -- Rate limit
    if not checkRateLimit(player, "CollectResources", 10) then
        Events.ServerResponse:FireClient(player, "CollectResources", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if typeof(buildingId) ~= "string" then return end

    -- Execute
    local BuildingService = require(Services.BuildingService)
    local result = BuildingService:CollectResources(player, buildingId)

    Events.ServerResponse:FireClient(player, "CollectResources", result)
end)

-- Speed up handler
Events.SpeedUpUpgrade.OnServerEvent:Connect(function(player, buildingId)
    -- Rate limit
    if not checkRateLimit(player, "SpeedUpUpgrade", 5) then
        Events.ServerResponse:FireClient(player, "SpeedUpUpgrade", { success = false, error = "RATE_LIMITED" })
        return
    end

    -- Type validation
    if typeof(buildingId) ~= "string" then return end

    -- Execute
    local EconomyService = require(Services.EconomyService)
    local success = EconomyService:SpeedUpUpgrade(player, buildingId)

    Events.ServerResponse:FireClient(player, "SpeedUpUpgrade", { success = success })
end)

-- Sync player data on request
Events.SyncPlayerData.OnServerEvent:Connect(function(player)
    -- Rate limit
    if not checkRateLimit(player, "SyncPlayerData", 5) then return end

    local DataService = require(Services.DataService)
    local playerData = DataService:GetPlayerData(player)

    if playerData then
        -- Only send safe data to client (not sensitive fields)
        local safeData = {
            resources = playerData.resources,
            townHallLevel = playerData.townHallLevel,
            buildings = playerData.buildings,
            troops = playerData.troops,
            spells = playerData.spells,
            armyCampCapacity = playerData.armyCampCapacity,
            builders = playerData.builders,
            shield = playerData.shield,
            trophies = playerData.trophies,
            stats = playerData.stats,
            vipActive = playerData.vipActive,
        }

        Events.SyncPlayerData:FireClient(player, safeData)
    end
end)

-- Cleanup rate limiter on player leave
game:GetService("Players").PlayerRemoving:Connect(function(player)
    RateLimiter[player.UserId] = nil
end)

print("Battle Tycoon: Conquest - Server Ready!")
