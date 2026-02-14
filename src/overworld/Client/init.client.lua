--!strict
--[[
    init.client.lua - Overworld Client Entry Point

    Initializes all client controllers for the overworld experience.
    Handles camera setup, movement, and base interaction.
]]

print("========================================")
print("BATTLE TYCOON: CONQUEST - OVERWORLD CLIENT")
print("========================================")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Wait for shared modules
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Waiting for shared modules...")

repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Shared")

print("[CLIENT] Shared modules loaded")

-- Wait for events
repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Events")

print("[CLIENT] Events folder found")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Load modules and configuration
-- ═══════════════════════════════════════════════════════════════════════════════
local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Get services
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Get events
local Events = ReplicatedStorage:WaitForChild("Events")
local UpdatePosition = Events:WaitForChild("UpdatePosition") :: RemoteEvent
local GetNearbyBases = Events:WaitForChild("GetNearbyBases") :: RemoteFunction
local GetBaseData = Events:WaitForChild("GetBaseData") :: RemoteFunction
local GetOwnBaseData = Events:WaitForChild("GetOwnBaseData") :: RemoteFunction
local SpawnBase = Events:WaitForChild("SpawnBase") :: RemoteEvent
local RemoveBase = Events:WaitForChild("RemoveBase") :: RemoteEvent
local PositionSync = Events:WaitForChild("PositionSync") :: RemoteEvent
local ApproachBase = Events:WaitForChild("ApproachBase") :: RemoteEvent
local LeaveBase = Events:WaitForChild("LeaveBase") :: RemoteEvent
local BaseInteractionResult = Events:WaitForChild("BaseInteractionResult") :: RemoteEvent
local RequestTeleportToVillage = Events:WaitForChild("RequestTeleportToVillage") :: RemoteEvent
local RequestTeleportToBattle = Events:WaitForChild("RequestTeleportToBattle") :: RemoteEvent
local TeleportStarted = Events:WaitForChild("TeleportStarted") :: RemoteEvent
local TeleportFailed = Events:WaitForChild("TeleportFailed") :: RemoteEvent
local ServerResponse = Events:WaitForChild("ServerResponse") :: RemoteEvent

-- ═══════════════════════════════════════════════════════════════════════════════
-- Load controllers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Loading controllers...")

-- Controllers and UI are siblings in StarterPlayerScripts
local ControllersFolder = script.Parent:FindFirstChild("Controllers")

-- Load individual controllers
local OverworldController: any
local BaseInteractionController: any

local function loadController(name: string): any?
    if ControllersFolder then
        local module = ControllersFolder:FindFirstChild(name)
        if module then
            local success, result = pcall(function()
                return require(module)
            end)
            if success then
                print(string.format("[CLIENT] Loaded: %s", name))
                return result
            else
                warn(string.format("[CLIENT] Failed to load %s: %s", name, tostring(result)))
            end
        end
    end
    return nil
end

OverworldController = loadController("OverworldController")
BaseInteractionController = loadController("BaseInteractionController")

-- Load UI modules
local UIFolder = script.Parent:FindFirstChild("UI")

local BaseInfoUI: any
local OverworldHUD: any

local function loadUI(name: string): any?
    if UIFolder then
        local module = UIFolder:FindFirstChild(name)
        if module then
            local success, result = pcall(function()
                return require(module)
            end)
            if success then
                print(string.format("[CLIENT] Loaded UI: %s", name))
                return result
            else
                warn(string.format("[CLIENT] Failed to load UI %s: %s", name, tostring(result)))
            end
        end
    end
    return nil
end

BaseInfoUI = loadUI("BaseInfoUI")
OverworldHUD = loadUI("OverworldHUD")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Initialize controllers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Initializing controllers...")

local function initController(controller: any, name: string)
    if controller and controller.Init then
        local success, err = pcall(function()
            controller:Init()
        end)
        if success then
            print(string.format("[CLIENT] Initialized: %s", name))
        else
            warn(string.format("[CLIENT] Failed to init %s: %s", name, tostring(err)))
        end
    end
end

initController(OverworldController, "OverworldController")
initController(BaseInteractionController, "BaseInteractionController")
initController(BaseInfoUI, "BaseInfoUI")
initController(OverworldHUD, "OverworldHUD")

-- Connect Go to City button
if OverworldHUD and OverworldHUD.GoToCityClicked then
    OverworldHUD.GoToCityClicked:Connect(function()
        print("[CLIENT] Go to City clicked - requesting teleport to village")
        RequestTeleportToVillage:FireServer()
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Event connections
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Connecting events...")

-- Handle base spawns from server
SpawnBase.OnClientEvent:Connect(function(baseData)
    if OverworldController and OverworldController.OnBaseSpawned then
        OverworldController:OnBaseSpawned(baseData)
    end
end)

-- Handle base removals
RemoveBase.OnClientEvent:Connect(function(userId)
    if OverworldController and OverworldController.OnBaseRemoved then
        OverworldController:OnBaseRemoved(userId)
    end
end)

-- Handle position sync updates
PositionSync.OnClientEvent:Connect(function(nearbyBases)
    if OverworldController and OverworldController.OnPositionSync then
        OverworldController:OnPositionSync(nearbyBases)
    end
end)

-- Handle base interaction results
BaseInteractionResult.OnClientEvent:Connect(function(action, baseData)
    if BaseInteractionController and BaseInteractionController.OnInteractionResult then
        BaseInteractionController:OnInteractionResult(action, baseData)
    end

    if action == "approach" and baseData and BaseInfoUI and BaseInfoUI.Show then
        BaseInfoUI:Show(baseData)
    elseif action == "leave" and BaseInfoUI and BaseInfoUI.Hide then
        BaseInfoUI:Hide()
    end
end)

-- Handle teleport started
TeleportStarted.OnClientEvent:Connect(function(destination)
    print(string.format("[CLIENT] Teleporting to: %s", destination))
    -- Show loading screen
    if OverworldHUD and OverworldHUD.ShowTeleportLoading then
        OverworldHUD:ShowTeleportLoading(destination)
    end
end)

-- Handle teleport failed
TeleportFailed.OnClientEvent:Connect(function(destination, errorMsg)
    warn(string.format("[CLIENT] Teleport failed: %s - %s", destination, errorMsg))
    if OverworldHUD and OverworldHUD.HideTeleportLoading then
        OverworldHUD:HideTeleportLoading()
    end
    if OverworldHUD and OverworldHUD.ShowError then
        OverworldHUD:ShowError("Teleport Failed: " .. errorMsg)
    end
end)

-- Server response handler
ServerResponse.OnClientEvent:Connect(function(eventName, result)
    print(string.format("[CLIENT] Server response for %s: %s", eventName, result.success and "success" or "failed"))

    if not result.success and OverworldHUD and OverworldHUD.ShowError then
        OverworldHUD:ShowError(result.error or "Unknown error")
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- Player setup
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Setting up player...")

-- Wait for character
local function onCharacterAdded(character: Model)
    print("[CLIENT] Character loaded")

    -- Wait for humanoid root part
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)
    if not humanoidRootPart then
        warn("[CLIENT] HumanoidRootPart not found!")
        return
    end

    -- Start position update loop
    if OverworldController and OverworldController.StartPositionUpdates then
        OverworldController:StartPositionUpdates(humanoidRootPart :: Part)
    end

    -- Start proximity detection loop
    if BaseInteractionController and BaseInteractionController.StartProximityDetection then
        BaseInteractionController:StartProximityDetection(humanoidRootPart :: Part)
    end
end

-- Connect character added
Player.CharacterAdded:Connect(onCharacterAdded)

-- If character already exists, run setup
if Player.Character then
    onCharacterAdded(Player.Character)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Expose public API for other scripts
-- ═══════════════════════════════════════════════════════════════════════════════
local OverworldClient = {}

function OverworldClient.RequestEnterVillage()
    RequestTeleportToVillage:FireServer()
end

function OverworldClient.RequestAttack(targetUserId: number)
    RequestTeleportToBattle:FireServer(targetUserId)
end

function OverworldClient.GetNearbyBases(centerPos: Vector3?, maxCount: number?): {any}
    return GetNearbyBases:InvokeServer(centerPos, maxCount)
end

function OverworldClient.GetBaseData(targetUserId: number): any?
    return GetBaseData:InvokeServer(targetUserId)
end

function OverworldClient.GetOwnBaseData(): any?
    return GetOwnBaseData:InvokeServer()
end

print("========================================")
print("BATTLE TYCOON: CONQUEST - OVERWORLD CLIENT READY!")
print("========================================")

return OverworldClient
