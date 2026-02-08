--!strict
--[[
    BattleController.lua

    Manages battle UI and user input during combat.
    Handles troop deployment, spell casting, and battle visualization.

    All combat logic is server-authoritative.
    Client only sends deploy commands and receives state updates.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)

local BattleController = {}
BattleController.__index = BattleController

-- Events
BattleController.BattleStarted = Signal.new()
BattleController.BattleEnded = Signal.new()
BattleController.TroopSelected = Signal.new()
BattleController.SpellSelected = Signal.new()
BattleController.DeploymentModeChanged = Signal.new()

-- Private state
local _initialized = false
local _player = Players.LocalPlayer
local _currentBattleId: string? = nil
local _isInBattle = false
local _selectedTroopType: string? = nil
local _selectedSpellType: string? = nil
local _deploymentMode: string = "none" -- "none" | "troop" | "spell"
local _battleState = nil

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
    Starts a battle against a defender.
]]
function BattleController:StartBattle(defenderUserId: number)
    if _isInBattle then
        warn("Already in battle")
        return
    end

    if _G.ClientActions then
        _G.ClientActions.StartBattle(defenderUserId)
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

    if _G.ClientActions then
        _G.ClientActions.DeployTroop(_currentBattleId, _selectedTroopType, snappedPosition)
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

    if _G.ClientActions then
        _G.ClientActions.DeploySpell(_currentBattleId, _selectedSpellType, snappedPosition)
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

    -- TODO: Implement surrender event
    print("[Battle] Surrender requested")
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
]]
function BattleController:Init()
    if _initialized then
        warn("BattleController already initialized")
        return
    end

    local Events = ReplicatedStorage:WaitForChild("Events")

    -- Listen for battle start response
    Events.ServerResponse.OnClientEvent:Connect(function(action: string, result: any)
        if action == "StartBattle" and result.success then
            _currentBattleId = result.battleId
            _isInBattle = true
            _battleState = nil

            BattleController.BattleStarted:Fire(result.battleId)
            print("[Battle] Battle started:", result.battleId)
        end
    end)

    -- TODO: Listen for BattleTick events for state updates
    -- TODO: Listen for BattleEnded events

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
    print("BattleController initialized")
end

return BattleController
