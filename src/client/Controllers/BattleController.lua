--!strict
--[[
    BattleController.lua

    Manages battle UI and user input during combat.
    Handles troop deployment, spell casting, and battle visualization.

    All combat logic is server-authoritative.
    Client only sends deploy commands and receives state updates.

    Listens for BattleArenaService RemoteEvents:
    - BattleArenaReady  (Server -> Client): Arena spawned, transition camera
    - BattleStateUpdate (Server -> Client): Per-tick state (buildings, troops, destruction)
    - BattleComplete    (Server -> Client): End results (victory, loot, stars)
    - ReturnToOverworld (Client -> Server): Player clicks "Return" after results
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)

local BattleController = {}
BattleController.__index = BattleController

-- Events
BattleController.BattleStarted = Signal.new()
BattleController.BattleEnded = Signal.new()
BattleController.TroopSelected = Signal.new()
BattleController.SpellSelected = Signal.new()
BattleController.DeploymentModeChanged = Signal.new()
BattleController.ArenaReady = Signal.new() -- Fired when arena is ready (camera transition)
BattleController.ReturnedToOverworld = Signal.new() -- Fired when player returns from battle

-- Private state
local _initialized = false
local _player = Players.LocalPlayer
local _currentBattleId: string? = nil
local _isInBattle = false
local _selectedTroopType: string? = nil
local _selectedSpellType: string? = nil
local _deploymentMode: string = "none" -- "none" | "troop" | "spell"
local _battleState = nil
local _arenaCenter: Vector3? = nil
local _arenaSize: number = 0
local _defenderName: string? = nil
local _defenderTownHallLevel: number = 0
local _battleResults: any = nil

-- RemoteEvent references (resolved in Init)
local _returnToOverworldEvent: RemoteEvent? = nil

-- Constants
local GRID_SIZE = 40
local CELL_SIZE = 3

--[[
    Checks if player is currently in a battle.
]]
function BattleController:IsInBattle(): boolean
    return _isInBattle
end

--[[
    Gets the current battle ID.
]]
function BattleController:GetCurrentBattleId(): string?
    return _currentBattleId
end

--[[
    Gets the current battle state.
]]
function BattleController:GetBattleState(): any
    return _battleState
end

--[[
    Starts a battle against a defender by firing the RequestBattle RemoteEvent.
    BattleArenaService handles arena creation server-side and fires BattleArenaReady
    back to this client when ready.

    @param defenderUserId number - The defender's UserId
]]
function BattleController:StartBattle(defenderUserId: number)
    if _isInBattle then
        warn("Already in battle")
        return
    end

    local Events = ReplicatedStorage:FindFirstChild("Events")
    if Events then
        local requestBattle = Events:FindFirstChild("RequestBattle") :: RemoteEvent?
        if requestBattle then
            requestBattle:FireServer(defenderUserId)
        else
            warn("[BattleController] RequestBattle event not found")
        end
    end
end

--[[
    Enters troop deployment mode.
]]
function BattleController:SelectTroop(troopType: string)
    if not _isInBattle then
        warn("Not in battle")
        return
    end

    local troopDef = TroopData.GetByType(troopType)
    if not troopDef then
        warn("Invalid troop type:", troopType)
        return
    end

    _selectedTroopType = troopType
    _selectedSpellType = nil
    _deploymentMode = "troop"

    BattleController.TroopSelected:Fire(troopType, troopDef)
    BattleController.DeploymentModeChanged:Fire(_deploymentMode)
end

--[[
    Enters spell deployment mode.
]]
function BattleController:SelectSpell(spellType: string)
    if not _isInBattle then
        warn("Not in battle")
        return
    end

    -- TODO: Validate spell type when SpellData is implemented
    _selectedSpellType = spellType
    _selectedTroopType = nil
    _deploymentMode = "spell"

    BattleController.SpellSelected:Fire(spellType)
    BattleController.DeploymentModeChanged:Fire(_deploymentMode)
end

--[[
    Cancels deployment mode.
]]
function BattleController:CancelDeployment()
    _selectedTroopType = nil
    _selectedSpellType = nil
    _deploymentMode = "none"

    BattleController.DeploymentModeChanged:Fire(_deploymentMode)
end

--[[
    Deploys a troop at the specified world position.
]]
function BattleController:DeployTroopAt(worldPosition: Vector3)
    if not _isInBattle or not _currentBattleId then
        warn("Not in battle")
        return
    end

    if _deploymentMode ~= "troop" or not _selectedTroopType then
        warn("No troop selected")
        return
    end

    -- Snap to grid
    local gridX = math.floor(worldPosition.X / CELL_SIZE)
    local gridZ = math.floor(worldPosition.Z / CELL_SIZE)
    local snappedPosition = Vector3.new(gridX, 0, gridZ)

    if ClientAPI then
        ClientAPI.DeployTroop(_currentBattleId, _selectedTroopType, snappedPosition)
    end
end

--[[
    Deploys a spell at the specified world position.
]]
function BattleController:DeploySpellAt(worldPosition: Vector3)
    if not _isInBattle or not _currentBattleId then
        warn("Not in battle")
        return
    end

    if _deploymentMode ~= "spell" or not _selectedSpellType then
        warn("No spell selected")
        return
    end

    -- Snap to grid
    local gridX = math.floor(worldPosition.X / CELL_SIZE)
    local gridZ = math.floor(worldPosition.Z / CELL_SIZE)
    local snappedPosition = Vector3.new(gridX, 0, gridZ)

    if ClientAPI then
        ClientAPI.DeploySpell(_currentBattleId, _selectedSpellType, snappedPosition)
    end
end

--[[
    Handles click/tap to deploy.
]]
function BattleController:HandleDeployInput(worldPosition: Vector3)
    if _deploymentMode == "troop" then
        self:DeployTroopAt(worldPosition)
    elseif _deploymentMode == "spell" then
        self:DeploySpellAt(worldPosition)
    end
end

--[[
    Surrenders the current battle.
]]
function BattleController:Surrender()
    if not _isInBattle then
        warn("Not in battle")
        return
    end

    -- TODO: Implement surrender event via CombatService
    print("[Battle] Surrender requested")
end

--[[
    Requests to return to the overworld after a battle ends.
    Fires the ReturnToOverworld RemoteEvent to BattleArenaService.
]]
function BattleController:RequestReturnToOverworld()
    if _returnToOverworldEvent then
        _returnToOverworldEvent:FireServer({ battleId = _currentBattleId })
    end

    -- Reset local state
    _arenaCenter = nil
    _arenaSize = 0
    _defenderName = nil
    _defenderTownHallLevel = 0
    _battleResults = nil

    BattleController.ReturnedToOverworld:Fire()
    print("[Battle] Requested return to overworld")
end

--[[
    Gets the arena center position (where the camera should look during battle).
]]
function BattleController:GetArenaCenter(): Vector3?
    return _arenaCenter
end

--[[
    Gets the arena size in studs.
]]
function BattleController:GetArenaSize(): number
    return _arenaSize
end

--[[
    Gets the defender's display name for the current battle.
]]
function BattleController:GetDefenderName(): string?
    return _defenderName
end

--[[
    Gets the defender's Town Hall level for the current battle.
]]
function BattleController:GetDefenderTownHallLevel(): number
    return _defenderTownHallLevel
end

--[[
    Gets the battle results after the battle has ended.
]]
function BattleController:GetBattleResults(): any
    return _battleResults
end

--[[
    Gets the currently selected troop type.
]]
function BattleController:GetSelectedTroop(): string?
    return _selectedTroopType
end

--[[
    Gets the currently selected spell type.
]]
function BattleController:GetSelectedSpell(): string?
    return _selectedSpellType
end

--[[
    Gets the current deployment mode.
]]
function BattleController:GetDeploymentMode(): string
    return _deploymentMode
end

--[[
    Converts world position to grid position.
]]
function BattleController:WorldToGrid(worldPos: Vector3): (number, number)
    local gridX = math.floor(worldPos.X / CELL_SIZE)
    local gridZ = math.floor(worldPos.Z / CELL_SIZE)

    -- Clamp to battle grid bounds
    gridX = math.clamp(gridX, 0, GRID_SIZE - 1)
    gridZ = math.clamp(gridZ, 0, GRID_SIZE - 1)

    return gridX, gridZ
end

--[[
    Initializes the BattleController.
    Connects to BattleArenaService RemoteEvents for arena-based battles.
]]
function BattleController:Init()
    if _initialized then
        warn("BattleController already initialized")
        return
    end

    local Events = ReplicatedStorage:WaitForChild("Events")

    -- Resolve ReturnToOverworld event reference for firing later
    _returnToOverworldEvent = Events:WaitForChild("ReturnToOverworld", 2) :: RemoteEvent?

    -- ========================================================================
    -- BattleArenaReady: Server notifies that the arena has been spawned.
    -- Transition the camera to the arena and show battle UI.
    -- ========================================================================
    local battleArenaReadyEvent = Events:WaitForChild("BattleArenaReady", 2) :: RemoteEvent?
    if battleArenaReadyEvent then
        battleArenaReadyEvent.OnClientEvent:Connect(function(data: any)
            -- Check for error response (arena creation failed)
            if data.error then
                warn("[BattleController] Arena creation failed:", data.error)
                return
            end

            _currentBattleId = data.battleId
            _isInBattle = true
            _battleState = nil
            _arenaCenter = data.arenaCenter
            _arenaSize = data.arenaSize or 0
            _defenderName = data.defenderName
            _defenderTownHallLevel = data.defenderTownHallLevel or 1
            _battleResults = nil

            BattleController.BattleStarted:Fire(data.battleId)
            BattleController.ArenaReady:Fire({
                battleId = data.battleId,
                arenaCenter = data.arenaCenter,
                arenaSize = data.arenaSize,
                buildings = data.buildings,
                defenderName = data.defenderName,
                defenderTownHallLevel = data.defenderTownHallLevel,
            })

            print(string.format(
                "[BattleController] Arena ready: battleId=%s, defender=%s (TH Lv.%d)",
                tostring(data.battleId),
                tostring(data.defenderName),
                data.defenderTownHallLevel or 1
            ))
        end)
    else
        warn("[BattleController] BattleArenaReady event not found")
    end

    -- ========================================================================
    -- BattleStateUpdate: Per-tick updates from the server during battle.
    -- Contains destruction %, stars, time remaining, building HP, troop positions.
    -- ========================================================================
    local battleStateUpdateEvent = Events:WaitForChild("BattleStateUpdate", 2) :: RemoteEvent?
    if battleStateUpdateEvent then
        battleStateUpdateEvent.OnClientEvent:Connect(function(state: any)
            if not state or state.battleId ~= _currentBattleId then return end

            _battleState = state

            -- TODO: Update battle UI with new state
            -- - Update destruction meter (state.destruction)
            -- - Update star display (state.starsEarned)
            -- - Update timer (state.timeRemaining)
            -- - Update troop positions (state.troops)
            -- - Update building HP bars (state.buildings)
        end)
    else
        warn("[BattleController] BattleStateUpdate event not found")
    end

    -- ========================================================================
    -- BattleComplete: Server notifies that the battle has ended.
    -- Show end screen with results (victory, loot, stars, trophies).
    -- ========================================================================
    local battleCompleteEvent = Events:WaitForChild("BattleComplete", 2) :: RemoteEvent?
    if battleCompleteEvent then
        battleCompleteEvent.OnClientEvent:Connect(function(result: any)
            if not result or result.battleId ~= _currentBattleId then return end

            _isInBattle = false
            _battleState = nil
            _battleResults = result
            _selectedTroopType = nil
            _selectedSpellType = nil
            _deploymentMode = "none"

            BattleController.BattleEnded:Fire(result)

            print(string.format(
                "[BattleController] Battle ended - Victory: %s, Destruction: %d%%, Stars: %d",
                tostring(result.victory),
                result.destruction or 0,
                result.stars or 0
            ))

            -- TODO: Show battle results UI with:
            --   result.victory, result.destruction, result.stars, result.isConquest,
            --   result.loot, result.trophiesGained, result.xpGained,
            --   result.duration, result.troopsLost, result.buildingsDestroyed
            -- When player clicks "Return", call self:RequestReturnToOverworld()
        end)
    else
        warn("[BattleController] BattleComplete event not found")
    end

    -- ========================================================================
    -- ReturnToOverworld: Server tells client to transition camera back.
    -- This fires if the server auto-cleans the arena after the post-battle delay.
    -- ========================================================================
    if _returnToOverworldEvent then
        _returnToOverworldEvent.OnClientEvent:Connect(function(data: any)
            -- Server-initiated return (auto-cleanup after timeout)
            _currentBattleId = nil
            _arenaCenter = nil
            _arenaSize = 0
            _defenderName = nil
            _defenderTownHallLevel = 0

            BattleController.ReturnedToOverworld:Fire()
            print("[BattleController] Server returned player to overworld")
        end)
    end

    -- ========================================================================
    -- Input handling
    -- ========================================================================

    -- Handle escape key to cancel deployment or surrender
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        if input.KeyCode == Enum.KeyCode.Escape then
            if _deploymentMode ~= "none" then
                self:CancelDeployment()
            elseif _isInBattle then
                -- TODO: Show surrender confirmation UI
                print("[Battle] Press again to surrender")
            end
        end
    end)

    -- Handle number keys for quick troop selection (1-9)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed or not _isInBattle then return end

        local keyNumber = nil
        if input.KeyCode == Enum.KeyCode.One then keyNumber = 1
        elseif input.KeyCode == Enum.KeyCode.Two then keyNumber = 2
        elseif input.KeyCode == Enum.KeyCode.Three then keyNumber = 3
        elseif input.KeyCode == Enum.KeyCode.Four then keyNumber = 4
        elseif input.KeyCode == Enum.KeyCode.Five then keyNumber = 5
        elseif input.KeyCode == Enum.KeyCode.Six then keyNumber = 6
        elseif input.KeyCode == Enum.KeyCode.Seven then keyNumber = 7
        elseif input.KeyCode == Enum.KeyCode.Eight then keyNumber = 8
        elseif input.KeyCode == Enum.KeyCode.Nine then keyNumber = 9
        end

        if keyNumber then
            -- TODO: Select troop from player's available troops by index
            print("[Battle] Troop slot", keyNumber, "selected")
        end
    end)

    _initialized = true
    print("[BattleController] Initialized (BattleArenaService mode)")
end

return BattleController
