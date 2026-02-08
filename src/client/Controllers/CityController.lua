--!strict
--[[
    CityController.lua

    Manages the city view - building placement, selection, and interaction.
    Handles user input for city editing mode.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)

local CityController = {}
CityController.__index = CityController

-- Events
CityController.BuildingSelected = Signal.new()
CityController.BuildingDeselected = Signal.new()
CityController.PlacementModeEntered = Signal.new()
CityController.PlacementModeExited = Signal.new()

-- Private state
local _initialized = false
local _player = Players.LocalPlayer
local _selectedBuildingId: string? = nil
local _placementMode = false
local _placementBuildingType: string? = nil
local _gridSize = 40
local _cellSize = 3 -- studs per grid cell

--[[
    Enters building placement mode.
]]
function CityController:EnterPlacementMode(buildingType: string)
    local buildingDef = BuildingData.GetByType(buildingType)
    if not buildingDef then
        warn("Invalid building type:", buildingType)
        return
    end

    _placementMode = true
    _placementBuildingType = buildingType

    -- Deselect any current building
    self:DeselectBuilding()

    CityController.PlacementModeEntered:Fire(buildingType, buildingDef)
    print("[City] Entered placement mode for", buildingType)
end

--[[
    Exits building placement mode.
]]
function CityController:ExitPlacementMode()
    if not _placementMode then return end

    _placementMode = false
    _placementBuildingType = nil

    CityController.PlacementModeExited:Fire()
    print("[City] Exited placement mode")
end

--[[
    Confirms placement at a grid position.
]]
function CityController:ConfirmPlacement(gridX: number, gridZ: number)
    if not _placementMode or not _placementBuildingType then
        return
    end

    local position = Vector3.new(gridX, 0, gridZ)

    -- Request server to place building
    if ClientAPI then
        ClientAPI.PlaceBuilding(_placementBuildingType, position)
    end

    -- Exit placement mode
    self:ExitPlacementMode()
end

--[[
    Selects a building for viewing/upgrading.
]]
function CityController:SelectBuilding(buildingId: string)
    -- Deselect previous
    if _selectedBuildingId then
        self:DeselectBuilding()
    end

    _selectedBuildingId = buildingId

    CityController.BuildingSelected:Fire(buildingId)
    print("[City] Selected building:", buildingId)
end

--[[
    Deselects the current building.
]]
function CityController:DeselectBuilding()
    if not _selectedBuildingId then return end

    local previousId = _selectedBuildingId
    _selectedBuildingId = nil

    CityController.BuildingDeselected:Fire(previousId)
    print("[City] Deselected building:", previousId)
end

--[[
    Gets the currently selected building ID.
]]
function CityController:GetSelectedBuilding(): string?
    return _selectedBuildingId
end

--[[
    Checks if in placement mode.
]]
function CityController:IsInPlacementMode(): boolean
    return _placementMode
end

--[[
    Converts world position to grid position.
]]
function CityController:WorldToGrid(worldPos: Vector3): (number, number)
    local gridX = math.floor(worldPos.X / _cellSize)
    local gridZ = math.floor(worldPos.Z / _cellSize)

    -- Clamp to grid bounds
    gridX = math.clamp(gridX, 0, _gridSize - 1)
    gridZ = math.clamp(gridZ, 0, _gridSize - 1)

    return gridX, gridZ
end

--[[
    Converts grid position to world position (center of cell).
]]
function CityController:GridToWorld(gridX: number, gridZ: number): Vector3
    return Vector3.new(
        gridX * _cellSize + _cellSize / 2,
        0,
        gridZ * _cellSize + _cellSize / 2
    )
end

--[[
    Requests upgrade for selected building.
]]
function CityController:UpgradeSelected()
    if not _selectedBuildingId then
        warn("No building selected")
        return
    end

    if ClientAPI then
        ClientAPI.UpgradeBuilding(_selectedBuildingId)
    end
end

--[[
    Requests resource collection from selected building.
]]
function CityController:CollectFromSelected()
    if not _selectedBuildingId then
        warn("No building selected")
        return
    end

    if ClientAPI then
        ClientAPI.CollectResources(_selectedBuildingId)
    end
end

--[[
    Requests speed up for selected building.
]]
function CityController:SpeedUpSelected()
    if not _selectedBuildingId then
        warn("No building selected")
        return
    end

    if ClientAPI then
        ClientAPI.SpeedUpUpgrade(_selectedBuildingId)
    end
end

--[[
    Initializes the CityController.
]]
function CityController:Init()
    if _initialized then
        warn("CityController already initialized")
        return
    end

    -- Handle escape key to exit placement mode
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        if input.KeyCode == Enum.KeyCode.Escape then
            if _placementMode then
                self:ExitPlacementMode()
            else
                self:DeselectBuilding()
            end
        end
    end)

    -- TODO: Setup mouse/touch input for building selection and placement
    -- TODO: Setup camera controls for city view
    -- TODO: Create building preview ghost for placement mode

    _initialized = true
    print("CityController initialized")
end

return CityController
