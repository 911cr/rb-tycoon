--!strict
--[[
    BaseInteractionController.lua

    Client-side controller for detecting proximity to bases and handling
    interaction (enter, scout, attack).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local BaseInteractionController = {}
BaseInteractionController.__index = BaseInteractionController

-- ============================================================================
-- SIGNALS
-- ============================================================================

BaseInteractionController.ApproachedBase = Signal.new()
BaseInteractionController.LeftBase = Signal.new()
BaseInteractionController.InteractionRequested = Signal.new()

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _initialized = false
local _player = Players.LocalPlayer
local _humanoidRootPart: Part? = nil

local _proximityConnection: RBXScriptConnection? = nil
local _updateInterval = OverworldConfig.Interaction.UpdateInterval

local _nearestBase: any? = nil
local _isNearGate = false
local _currentlyApproaching: number? = nil -- userId of base being approached

-- Events
local _events: Folder? = nil
local _approachBase: RemoteEvent? = nil
local _leaveBase: RemoteEvent? = nil
local _requestTeleportToVillage: RemoteEvent? = nil
local _requestTeleportToBattle: RemoteEvent? = nil

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Gets the Events folder.
]]
local function getEvents(): Folder?
    if _events then return _events end
    _events = ReplicatedStorage:WaitForChild("Events", 5) :: Folder?
    return _events
end

--[[
    Finds the nearest base to the player.
]]
local function findNearestBase(): (any?, number)
    if not _humanoidRootPart then
        return nil, math.huge
    end

    local playerPos = _humanoidRootPart.Position
    local nearestData: any? = nil
    local nearestDistance = math.huge

    -- Check all spawned bases
    local overworldFolder = workspace:FindFirstChild("Overworld")
    if not overworldFolder then return nil, math.huge end

    local basesFolder = overworldFolder:FindFirstChild("Bases")
    if not basesFolder then return nil, math.huge end

    for _, base in basesFolder:GetChildren() do
        if base:IsA("Model") then
            local keep = base:FindFirstChild("Keep")
            if keep then
                -- Keep is a Model, not a Part - use GetPivot() for position
                local basePos = keep:GetPivot().Position
                basePos = Vector3.new(basePos.X, playerPos.Y, basePos.Z) -- Same Y plane

                local distance = (playerPos - basePos).Magnitude

                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestData = {
                        model = base,
                        userId = base:GetAttribute("UserId") :: number,
                        isOwnBase = base:GetAttribute("IsOwnBase") :: boolean,
                        position = keep:GetPivot().Position,
                    }
                end
            end
        end
    end

    return nearestData, nearestDistance
end

--[[
    Handles the Enter/Interact key press.
]]
local function onInteractPressed(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
    if inputState ~= Enum.UserInputState.Begin then
        return Enum.ContextActionResult.Pass
    end

    if not _nearestBase then
        return Enum.ContextActionResult.Pass
    end

    local distance = 0
    if _humanoidRootPart and _nearestBase.position then
        distance = (_humanoidRootPart.Position - _nearestBase.position).Magnitude
    end

    -- Check if near gate
    if distance <= OverworldConfig.Interaction.GateDistance then
        if _nearestBase.isOwnBase then
            -- Enter own village
            print("[BaseInteraction] Entering village...")
            if _requestTeleportToVillage then
                _requestTeleportToVillage:FireServer()
            end
            BaseInteractionController.InteractionRequested:Fire("Enter", _nearestBase.userId)
        else
            -- Attack enemy base
            print("[BaseInteraction] Attacking base:", _nearestBase.userId)
            if _requestTeleportToBattle then
                _requestTeleportToBattle:FireServer(_nearestBase.userId)
            end
            BaseInteractionController.InteractionRequested:Fire("Attack", _nearestBase.userId)
        end
        return Enum.ContextActionResult.Sink
    end

    return Enum.ContextActionResult.Pass
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Initializes the BaseInteractionController.
]]
function BaseInteractionController:Init()
    if _initialized then
        warn("[BaseInteractionController] Already initialized")
        return
    end

    -- Get events
    local events = getEvents()
    if events then
        _approachBase = events:FindFirstChild("ApproachBase") :: RemoteEvent?
        _leaveBase = events:FindFirstChild("LeaveBase") :: RemoteEvent?
        _requestTeleportToVillage = events:FindFirstChild("RequestTeleportToVillage") :: RemoteEvent?
        _requestTeleportToBattle = events:FindFirstChild("RequestTeleportToBattle") :: RemoteEvent?
    end

    -- Bind interact action
    ContextActionService:BindAction(
        "InteractWithBase",
        onInteractPressed,
        false,
        Enum.KeyCode.E,
        Enum.KeyCode.ButtonX
    )

    _initialized = true
    print("[BaseInteractionController] Initialized")
end

--[[
    Starts the proximity detection loop.

    @param humanoidRootPart Part - The player's HumanoidRootPart
]]
function BaseInteractionController:StartProximityDetection(humanoidRootPart: Part)
    _humanoidRootPart = humanoidRootPart

    -- Disconnect existing connection
    if _proximityConnection then
        _proximityConnection:Disconnect()
    end

    local lastCheck = 0

    _proximityConnection = RunService.Heartbeat:Connect(function(dt)
        local now = os.clock()
        if now - lastCheck < _updateInterval then
            return
        end
        lastCheck = now

        if not _humanoidRootPart then return end

        -- Find nearest base
        local nearestBase, distance = findNearestBase()

        -- Check if within info distance
        if nearestBase and distance <= OverworldConfig.Interaction.InfoDistance then
            -- Approaching a base
            if _currentlyApproaching ~= nearestBase.userId then
                -- Left previous base
                if _currentlyApproaching then
                    if _leaveBase then
                        _leaveBase:FireServer(_currentlyApproaching)
                    end
                    self.LeftBase:Fire(_currentlyApproaching)
                end

                -- Approaching new base
                _currentlyApproaching = nearestBase.userId
                _nearestBase = nearestBase

                if _approachBase then
                    _approachBase:FireServer(nearestBase.userId)
                end
                self.ApproachedBase:Fire(nearestBase)

                print(string.format("[BaseInteraction] Approaching base: %d (distance: %.1f)",
                    nearestBase.userId, distance))
            end

            -- Check if near gate
            local wasNearGate = _isNearGate
            _isNearGate = distance <= OverworldConfig.Interaction.GateDistance

            if _isNearGate and not wasNearGate then
                print("[BaseInteraction] Near gate - press E to " ..
                    (nearestBase.isOwnBase and "enter" or "attack"))
            end
        else
            -- Not near any base
            if _currentlyApproaching then
                if _leaveBase then
                    _leaveBase:FireServer(_currentlyApproaching)
                end
                self.LeftBase:Fire(_currentlyApproaching)

                _currentlyApproaching = nil
                _nearestBase = nil
                _isNearGate = false

                print("[BaseInteraction] Left base area")
            end
        end
    end)

    print("[BaseInteractionController] Proximity detection started")
end

--[[
    Stops proximity detection.
]]
function BaseInteractionController:StopProximityDetection()
    if _proximityConnection then
        _proximityConnection:Disconnect()
        _proximityConnection = nil
    end
end

--[[
    Called when server sends interaction result.

    @param action string - The action type
    @param baseData table? - The base data
]]
function BaseInteractionController:OnInteractionResult(action: string, baseData: any?)
    if action == "approach" and baseData then
        -- Update nearest base with full data from server
        if _nearestBase and _nearestBase.userId == baseData.userId then
            _nearestBase = baseData
        end
    elseif action == "leave" then
        -- Clear state
        _nearestBase = nil
        _isNearGate = false
    end
end

--[[
    Gets the currently approaching base.

    @return table? - Base data or nil
]]
function BaseInteractionController:GetApproachingBase(): any?
    return _nearestBase
end

--[[
    Checks if player is near a gate.

    @return boolean - True if near gate
]]
function BaseInteractionController:IsNearGate(): boolean
    return _isNearGate
end

--[[
    Manually requests to enter village.
]]
function BaseInteractionController:RequestEnterVillage()
    if _nearestBase and _nearestBase.isOwnBase and _isNearGate then
        if _requestTeleportToVillage then
            _requestTeleportToVillage:FireServer()
        end
        self.InteractionRequested:Fire("Enter", _nearestBase.userId)
    end
end

--[[
    Manually requests to attack a base.

    @param targetUserId number - The target user ID
]]
function BaseInteractionController:RequestAttack(targetUserId: number)
    if _requestTeleportToBattle then
        _requestTeleportToBattle:FireServer(targetUserId)
    end
    self.InteractionRequested:Fire("Attack", targetUserId)
end

return BaseInteractionController
