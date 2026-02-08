--!strict
--[[
    Client Entry Point

    Initializes all client controllers and sets up UI.
    This script runs when a player joins.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local player = Players.LocalPlayer

print("Battle Tycoon: Conquest - Client Starting...")

-- Wait for shared modules
repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Shared")

-- Wait for server events to be ready
repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Events")

local Events = ReplicatedStorage.Events

-- Client state
local PlayerData = nil

-- Request initial data sync
Events.SyncPlayerData:FireServer()

-- Handle data sync from server
Events.SyncPlayerData.OnClientEvent:Connect(function(data)
    PlayerData = data
    print("[CLIENT] Player data synced")

    -- TODO: Update UI with new data
end)

-- Handle server responses
Events.ServerResponse.OnClientEvent:Connect(function(action: string, result: any)
    if result.success then
        print(string.format("[CLIENT] %s succeeded", action))

        -- Request data refresh after successful action
        Events.SyncPlayerData:FireServer()
    else
        warn(string.format("[CLIENT] %s failed: %s", action, result.error or "Unknown"))

        -- TODO: Show error UI to player
    end
end)

-- Controller initialization
local Controllers = StarterPlayer:WaitForChild("StarterPlayerScripts"):FindFirstChild("Controllers")

if Controllers then
    local initOrder = {
        "UIController",
        "CityController",
        -- "BattleController", -- TODO: Implement
    }

    for _, controllerName in initOrder do
        local controllerModule = Controllers:FindFirstChild(controllerName)
        if controllerModule then
            local success, err = pcall(function()
                local controller = require(controllerModule)
                if controller.Init then
                    controller:Init()
                end
            end)

            if success then
                print(string.format("[CLIENT] %s initialized", controllerName))
            else
                warn(string.format("[CLIENT] Failed to initialize %s: %s", controllerName, err))
            end
        end
    end
end

-- Helper functions for client actions

local ClientActions = {}

function ClientActions.PlaceBuilding(buildingType: string, position: Vector3)
    Events.PlaceBuilding:FireServer(buildingType, position)
end

function ClientActions.UpgradeBuilding(buildingId: string)
    Events.UpgradeBuilding:FireServer(buildingId)
end

function ClientActions.CollectResources(buildingId: string)
    Events.CollectResources:FireServer(buildingId)
end

function ClientActions.SpeedUpUpgrade(buildingId: string)
    Events.SpeedUpUpgrade:FireServer(buildingId)
end

function ClientActions.GetPlayerData()
    return PlayerData
end

-- Make available globally for UI scripts
_G.ClientActions = ClientActions

print("Battle Tycoon: Conquest - Client Ready!")
