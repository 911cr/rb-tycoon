-- Medieval Village - GAMEPLAY BUILDINGS WITH MINI-GAMES
-- Buildings match their actual function with interactive mini-games inside
-- Players work in buildings to generate resources and level them up

print("========================================")
print("VILLAGE BUILDER - GAMEPLAY BUILDINGS")
print("========================================")

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local PathfindingService = game:GetService("PathfindingService")

-- DataService for persisting player resources
local DataService = nil
task.defer(function()
    -- Wait briefly for services to initialize
    task.wait(1)
    local success, result = pcall(function()
        return require(ServerScriptService.Services.DataService)
    end)
    if success then
        DataService = result
        print("[SimpleTest] DataService connected for resource updates")
    else
        warn("[SimpleTest] DataService not available, resources won't persist to HUD")
    end
end)

-- VillageStateService for per-player village persistence
local VillageStateService = nil
local _villageOwnerUserId = nil -- Set by Main.server.lua or first player
local _playerRoles = {} -- [userId] = "owner" | "visitor"
pcall(function()
    VillageStateService = require(ServerScriptService.Services.VillageStateService)
end)

-- Helper: check if player is the village owner
local function isVillageOwner(player)
    return _playerRoles[player.UserId] == "owner"
end

-- Action button callback registry: maps Part → callback function
local _interactionCallbacks = {}

-- Parts where visitors can interact (help the owner mine/chop/farm)
local _visitorAllowedParts = {}

-- Helper: send notification to player via ServerResponse event
local function notifyPlayer(player, action, success, message)
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if Events then
        local ServerResponse = Events:FindFirstChild("ServerResponse")
        if ServerResponse then
            if success then
                ServerResponse:FireClient(player, action, { success = true, message = message })
            else
                ServerResponse:FireClient(player, action, { success = false, error = message })
            end
        end
    end
end

-- Helper: deduct resources from player, sync HUD, return true/false
local function deductPlayerResources(player, costs, contextMsg)
    if not DataService then
        print("[" .. contextMsg .. "] DataService not available - demo mode")
        return true
    end
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return false end
    if costs.gold and (playerData.resources.gold or 0) < costs.gold then
        print(string.format("[%s] %s: Not enough gold! Need %d, have %d",
            contextMsg, player.Name, costs.gold, playerData.resources.gold or 0))
        return false
    end
    if costs.food and (playerData.resources.food or 0) < costs.food then
        print(string.format("[%s] %s: Not enough food! Need %d, have %d",
            contextMsg, player.Name, costs.food, playerData.resources.food or 0))
        return false
    end
    if costs.wood and (playerData.resources.wood or 0) < costs.wood then
        print(string.format("[%s] %s: Not enough wood! Need %d, have %d",
            contextMsg, player.Name, costs.wood, playerData.resources.wood or 0))
        return false
    end
    DataService:DeductResources(player, costs)
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if Events then
        local SyncPlayerData = Events:FindFirstChild("SyncPlayerData")
        if SyncPlayerData then SyncPlayerData:FireClient(player, playerData) end
    end
    return true
end

-- Constants
local GROUND_Y = 2
local WALL_THICKNESS = 1

-- Player farm data (tracks purchased plots and built farms per player)
local PlayerFarmData = {} -- [userId] = { farmPlots = 1, builtFarms = { [1] = true } }

local function getPlayerFarmData(player)
    local userId = player.UserId
    if not PlayerFarmData[userId] then
        PlayerFarmData[userId] = {
            farmPlots = 1, -- Start with 1 farm plot (Farm 1)
            builtFarms = { [1] = true }, -- Farm 1 is built by default
        }
    end
    return PlayerFarmData[userId]
end

-- Forward declaration for createFarm (defined later)
local createFarm

-- Create RemoteEvents for farm management
local function setupFarmRemotes()
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then
        remoteFolder = Instance.new("Folder")
        remoteFolder.Name = "Remotes"
        remoteFolder.Parent = ReplicatedStorage
    end

    -- BuildFarm remote
    local buildFarmRemote = Instance.new("RemoteFunction")
    buildFarmRemote.Name = "BuildFarm"
    buildFarmRemote.Parent = remoteFolder

    buildFarmRemote.OnServerInvoke = function(player, farmNumber)
        local farmData = getPlayerFarmData(player)

        -- Check if farm is already built
        if farmData.builtFarms[farmNumber] then
            return { success = false, error = "Farm " .. farmNumber .. " is already built" }
        end

        -- Check if player has the plot unlocked
        if farmNumber > farmData.farmPlots then
            return { success = false, error = "You need to purchase Farm Plot " .. farmNumber .. " first" }
        end

        -- Build the farm
        print(string.format("[Farm] Player %s building Farm %d", player.Name, farmNumber))
        farmData.builtFarms[farmNumber] = true

        -- Create the farm on the server
        task.defer(function()
            if createFarm then
                createFarm(farmNumber)
            end
        end)

        return { success = true }
    end

    -- PurchaseFarmPlot remote
    local purchasePlotRemote = Instance.new("RemoteFunction")
    purchasePlotRemote.Name = "PurchaseFarmPlot"
    purchasePlotRemote.Parent = remoteFolder

    purchasePlotRemote.OnServerInvoke = function(player, plotNumber)
        local farmData = getPlayerFarmData(player)

        -- Check if already purchased
        if plotNumber <= farmData.farmPlots then
            return { success = false, error = "Farm Plot " .. plotNumber .. " already purchased" }
        end

        -- Check if it's the next plot (must purchase in order)
        if plotNumber ~= farmData.farmPlots + 1 then
            return { success = false, error = "Must purchase plots in order" }
        end

        -- Check costs (from BuildingData)
        local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
        local plotCost = BuildingData.FarmPlotCosts[plotNumber]
        if not plotCost then
            return { success = false, error = "Invalid plot number" }
        end

        -- TODO: Check player has enough resources and deduct them
        -- For now, just grant the plot
        print(string.format("[Farm] Player %s purchased Farm Plot %d", player.Name, plotNumber))
        farmData.farmPlots = plotNumber

        return { success = true }
    end

    -- GetFarmData remote (for client to query farm status)
    local getFarmDataRemote = Instance.new("RemoteFunction")
    getFarmDataRemote.Name = "GetFarmData"
    getFarmDataRemote.Parent = remoteFolder

    getFarmDataRemote.OnServerInvoke = function(player)
        return getPlayerFarmData(player)
    end

    print("[SimpleTest] Farm remotes initialized")
end

-- Setup remotes
setupFarmRemotes()

-- Village folder
local villageFolder = Instance.new("Folder")
villageFolder.Name = "Village"
villageFolder.Parent = workspace

-- Decorations folder
local decorFolder = Instance.new("Folder")
decorFolder.Name = "Decorations"
decorFolder.Parent = villageFolder

-- Building data storage (tracks mini-game progress)
local BuildingProgress = {}

-- Interiors folder (instanced building interiors)
local interiorsFolder = Instance.new("Folder")
interiorsFolder.Name = "BuildingInteriors"
interiorsFolder.Parent = workspace

-- Interior Y positions (each building has its own "floor")
-- Farm 1-6 each have separate interiors at different Y levels
local INTERIOR_POSITIONS = {
    GoldMine = Vector3.new(0, 500, 0),
    LumberMill = Vector3.new(0, 600, 0),
    Farm1 = Vector3.new(0, 700, 0),
    Farm2 = Vector3.new(0, 720, 0),
    Farm3 = Vector3.new(0, 740, 0),
    Farm4 = Vector3.new(0, 760, 0),
    Farm5 = Vector3.new(0, 780, 0),
    Farm6 = Vector3.new(0, 800, 0),
    Barracks = Vector3.new(0, 850, 0),
    TownHall = Vector3.new(0, 950, 0),
}

-- Farm exterior positions in the village (purchased through shop)
local FARM_EXTERIOR_POSITIONS = {
    [1] = { x = 25, z = 100, facing = "east" },    -- Farm 1 - left of path (default)
    [2] = { x = 25, z = 130, facing = "east" },    -- Farm 2 - behind Farm 1
    [3] = { x = 95, z = 130, facing = "west" },    -- Farm 3 - right side, behind Barracks
    [4] = { x = 10, z = 115, facing = "east" },    -- Farm 4 - far left
    [5] = { x = 110, z = 115, facing = "west" },   -- Farm 5 - far right
    [6] = { x = 60, z = 140, facing = "south" },   -- Farm 6 - center back
}

-- Spawn offsets for each building (relative to INTERIOR_POSITIONS)
-- Positions players near the entrance, not in the middle of equipment
local INTERIOR_SPAWN_OFFSETS = {
    GoldMine = Vector3.new(0, 3, 22),      -- Near cave entrance (exit portal at Z=28)
    LumberMill = Vector3.new(0, 3, 22),    -- Near forest entrance
    Farm1 = Vector3.new(0, 3, 22),         -- Near farm entrance
    Farm2 = Vector3.new(0, 3, 22),         -- Near farm entrance
    Farm3 = Vector3.new(0, 3, 22),         -- Near farm entrance
    Farm4 = Vector3.new(0, 3, 22),         -- Near farm entrance
    Farm5 = Vector3.new(0, 3, 22),         -- Near farm entrance
    Farm6 = Vector3.new(0, 3, 22),         -- Near farm entrance
    Barracks = Vector3.new(0, 3, 22),      -- Near barracks entrance
    TownHall = Vector3.new(0, 3, 22),      -- Near town hall entrance
}

-- Store return positions for each player
local PlayerReturnPositions = {}

-- Store which building each player is currently in (for exit orientation)
local PlayerCurrentBuilding = {}

-- Global teleport cooldown to prevent rapid entrance/exit cycling
-- Both entrance and exit portals check this before teleporting
local TeleportCooldown = {}

-- Building exterior positions in the village (for exit orientation)
-- The position where players exit to, and the building center to face away from
-- IMPORTANT: exitPos must be far enough from entrance triggers to avoid re-teleporting!
local BUILDING_EXTERIOR_POSITIONS = {
    GoldMine = { exitPos = Vector3.new(38, 3, 50), buildingPos = Vector3.new(25, 0, 50) },        -- Exit east of building (X=38 clears entrance trigger at X=30-32)
    LumberMill = { exitPos = Vector3.new(90, 3, 50), buildingPos = Vector3.new(95, 0, 50) },     -- Exit west of building, face toward path
    Farm1 = { exitPos = Vector3.new(45, 3, 100), buildingPos = Vector3.new(25, 0, 100) },        -- Exit east of barn (facing east, door on +X)
    Farm2 = { exitPos = Vector3.new(45, 3, 130), buildingPos = Vector3.new(25, 0, 130) },        -- Exit east of barn
    Farm3 = { exitPos = Vector3.new(75, 3, 130), buildingPos = Vector3.new(95, 0, 130) },        -- Exit west of barn (facing west, door on -X)
    Farm4 = { exitPos = Vector3.new(30, 3, 115), buildingPos = Vector3.new(10, 0, 115) },        -- Exit east of barn
    Farm5 = { exitPos = Vector3.new(90, 3, 115), buildingPos = Vector3.new(110, 0, 115) },       -- Exit west of barn
    Farm6 = { exitPos = Vector3.new(60, 3, 160), buildingPos = Vector3.new(60, 0, 140) },        -- Exit south of barn (facing south, door on +Z)
    Barracks = { exitPos = Vector3.new(90, 3, 100), buildingPos = Vector3.new(95, 0, 100) },     -- Exit west of building
    TownHall = { exitPos = Vector3.new(60, 3, 135), buildingPos = Vector3.new(60, 0, 155) },     -- Exit south of building (clear of walls)
}

-- ============================================================================
-- HELPER FUNCTIONS (must be defined before they are used)
-- ============================================================================

local function createSign(parent, text, position, size)
    local signBoard = Instance.new("Part")
    signBoard.Name = "Sign"
    signBoard.Size = size or Vector3.new(4, 2, 0.3)
    signBoard.Position = position
    signBoard.Anchored = true
    signBoard.Material = Enum.Material.Wood
    signBoard.Color = Color3.fromRGB(60, 40, 25)
    signBoard.Parent = parent

    -- Add text on both sides so signs are readable from any direction
    for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
        local gui = Instance.new("SurfaceGui")
        gui.Face = face
        gui.Parent = signBoard

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = Color3.fromRGB(255, 230, 180)
        label.TextScaled = true
        label.Font = Enum.Font.Antique
        label.Parent = gui
    end
    return signBoard
end

-- Make any sign part readable from both sides by cloning SurfaceGuis to opposite face
local OPPOSITE_FACE = {
    [Enum.NormalId.Front] = Enum.NormalId.Back,
    [Enum.NormalId.Back] = Enum.NormalId.Front,
    [Enum.NormalId.Left] = Enum.NormalId.Right,
    [Enum.NormalId.Right] = Enum.NormalId.Left,
    [Enum.NormalId.Top] = Enum.NormalId.Bottom,
    [Enum.NormalId.Bottom] = Enum.NormalId.Top,
}
local function makeSignDoubleSided(part)
    for _, gui in part:GetChildren() do
        if gui:IsA("SurfaceGui") and not gui.Name:match("_Back$") then
            local backGui = gui:Clone()
            backGui.Face = OPPOSITE_FACE[gui.Face] or Enum.NormalId.Back
            backGui.Name = gui.Name .. "_Back"
            backGui.Parent = part
        end
    end
end

local function createTorch(parent, position)
    local torch = Instance.new("Part")
    torch.Name = "Torch"
    torch.Size = Vector3.new(0.3, 1.5, 0.3)
    torch.Position = position
    torch.Anchored = true
    torch.Material = Enum.Material.Wood
    torch.Color = Color3.fromRGB(80, 50, 30)
    torch.Parent = parent

    local fire = Instance.new("Fire")
    fire.Size = 2
    fire.Heat = 3
    fire.Parent = torch

    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 150, 50)
    light.Brightness = 1.5
    light.Range = 15
    light.Parent = torch
    return torch
end

local function createInteraction(part, actionText, objectText, holdDuration, callback, allowVisitors)
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = actionText or "Interact"
    prompt.ObjectText = objectText or ""
    prompt.HoldDuration = 0 -- Instant activation for both ProximityPrompt and action button
    prompt.MaxActivationDistance = 8
    prompt.RequiresLineOfSight = false
    prompt.Parent = part

    -- Mark part as visitor-allowed for action button handler
    if allowVisitors then
        _visitorAllowedParts[part] = true
    end

    if callback then
        -- Register callback for action button RemoteEvent
        _interactionCallbacks[part] = callback

        prompt.Triggered:Connect(function(player)
            -- Visitor guard: only the village owner can interact (unless visitor-allowed)
            if not isVillageOwner(player) and not allowVisitors then
                return
            end
            callback(player)
        end)
    end

    return prompt
end

-- Action button: handle instant interaction from client button
task.defer(function()
    local Events = ReplicatedStorage:WaitForChild("Events", 10)
    if not Events then return end
    local ActionButtonPressed = Events:WaitForChild("ActionButtonPressed", 10)
    if not ActionButtonPressed then return end

    ActionButtonPressed.OnServerEvent:Connect(function(player, targetPart)
        if typeof(targetPart) ~= "Instance" then return end
        if not isVillageOwner(player) and not _visitorAllowedParts[targetPart] then return end
        local callback = _interactionCallbacks[targetPart]
        if not callback then return end
        -- Validate distance (MaxActivationDistance=8 + 4 tolerance)
        local char = player.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        if (hrp.Position - targetPart.Position).Magnitude > 12 then return end
        callback(player)
    end)
end)

-- ============================================================================
-- TELEPORT SYSTEM
-- ============================================================================

local function teleportToInterior(player, buildingName)
    local character = player.Character
    if not character then return end
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    -- Check global teleport cooldown to prevent rapid entrance/exit cycling
    if TeleportCooldown[player.UserId] then return end
    TeleportCooldown[player.UserId] = true
    task.delay(2, function() TeleportCooldown[player.UserId] = nil end)

    -- Save return position and which building the player entered
    PlayerReturnPositions[player.UserId] = humanoidRootPart.Position
    PlayerCurrentBuilding[player.UserId] = buildingName

    -- Teleport to interior
    local interiorPos = INTERIOR_POSITIONS[buildingName]
    local spawnOffset = INTERIOR_SPAWN_OFFSETS[buildingName] or Vector3.new(0, 3, 22)
    if interiorPos then
        -- Spawn near entrance, facing INTO the building (toward room center)
        -- Player spawns near Z=22 (near exit portal), should face toward Z=0 (room center)
        local spawnPos = interiorPos + spawnOffset
        local lookAtPos = Vector3.new(spawnPos.X, spawnPos.Y, interiorPos.Z) -- Look toward room center
        humanoidRootPart.CFrame = CFrame.lookAt(spawnPos, lookAtPos)
        print(string.format("[Teleport] %s entered %s interior", player.Name, buildingName))
    end
end

local function teleportToVillage(player)
    local character = player.Character
    if not character then return end
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    -- Check global teleport cooldown to prevent rapid entrance/exit cycling
    if TeleportCooldown[player.UserId] then return end
    TeleportCooldown[player.UserId] = true
    task.delay(2, function() TeleportCooldown[player.UserId] = nil end)

    -- Get which building the player is exiting from
    local buildingName = PlayerCurrentBuilding[player.UserId]
    local exteriorData = buildingName and BUILDING_EXTERIOR_POSITIONS[buildingName]

    -- Return to saved position or default spawn
    local returnPos = PlayerReturnPositions[player.UserId] or Vector3.new(60, GROUND_Y + 3, 20)
    local exitPos = returnPos + Vector3.new(0, 2, 0)

    if exteriorData then
        -- Use the predefined exit position and face away from the building
        exitPos = exteriorData.exitPos + Vector3.new(0, 2, 0)
        local buildingPos = exteriorData.buildingPos

        -- Calculate direction away from building (at same Y level)
        local awayDirection = (Vector3.new(exitPos.X, 0, exitPos.Z) - Vector3.new(buildingPos.X, 0, buildingPos.Z)).Unit
        local lookAtPos = exitPos + awayDirection * 10

        humanoidRootPart.CFrame = CFrame.lookAt(exitPos, lookAtPos)
    else
        -- Fallback: just set position without specific orientation
        humanoidRootPart.CFrame = CFrame.new(exitPos)
    end

    -- Clear the stored building
    PlayerCurrentBuilding[player.UserId] = nil

    print(string.format("[Teleport] %s returned to village from %s", player.Name, buildingName or "unknown"))
end

-- Create exit portal for interiors
local function createExitPortal(parent, position)
    local portal = Instance.new("Part")
    portal.Name = "ExitPortal"
    portal.Size = Vector3.new(14, 12, 2)
    portal.Position = position
    portal.Anchored = true
    portal.Material = Enum.Material.Neon
    portal.Color = Color3.fromRGB(100, 200, 255)
    portal.Transparency = 0.3
    portal.CanCollide = false
    portal.Parent = parent

    -- Portal glow
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(100, 200, 255)
    light.Brightness = 2
    light.Range = 15
    light.Parent = portal

    -- Walk-through exit (Touched event)
    local debounce = {}
    portal.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end

        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end

        -- Debounce check
        if debounce[player.UserId] then return end
        debounce[player.UserId] = true

        teleportToVillage(player)

        -- Reset debounce after delay
        task.delay(1, function()
            debounce[player.UserId] = nil
        end)
    end)

    -- Sign above portal
    createSign(parent, "EXIT", position + Vector3.new(0, 5, 0), Vector3.new(3, 1, 0.3))

    return portal
end

-- Create BARN exterior (red barn with gambrel roof for Farms)
-- facingDirection: "north" (default/-Z back), "south" (+Z back), "east" (+X door), "west" (-X door)
local function createBarnExterior(name, position, size, buildingName, facingDirection)
    facingDirection = facingDirection or "north"

    local exterior = Instance.new("Model")
    exterior.Name = name .. "_Exterior"

    local wallHeight = size.Y
    local wallThickness = 1

    -- Classic barn colors
    local barnRed = Color3.fromRGB(139, 35, 35)
    local barnRedDark = Color3.fromRGB(110, 28, 28)
    local whiteTrim = Color3.fromRGB(245, 245, 240)
    local roofGray = Color3.fromRGB(80, 80, 85)
    local floorColor = Color3.fromRGB(90, 65, 40)

    -- Calculate rotation based on facing direction
    local rotation = 0
    if facingDirection == "south" then
        rotation = 180
    elseif facingDirection == "east" then
        rotation = -90
    elseif facingDirection == "west" then
        rotation = 90
    end

    -- Helper to rotate offset around Y axis
    local function rotateOffset(offset)
        local rad = math.rad(rotation)
        local cos, sin = math.cos(rad), math.sin(rad)
        return Vector3.new(
            offset.X * cos - offset.Z * sin,
            offset.Y,
            offset.X * sin + offset.Z * cos
        )
    end

    -- Dirt floor inside barn
    local floor = Instance.new("Part")
    floor.Name = "BarnFloor"
    floor.Size = Vector3.new(size.X, 0.5, size.Z)
    floor.Position = position + Vector3.new(0, 0.25, 0)
    floor.Orientation = Vector3.new(0, rotation, 0)
    floor.Anchored = true
    floor.Material = Enum.Material.Ground
    floor.Color = floorColor
    floor.Parent = exterior

    -- Back wall (solid red)
    local backWall = Instance.new("Part")
    backWall.Name = "BarnBackWall"
    backWall.Size = Vector3.new(size.X, wallHeight, wallThickness)
    backWall.Position = position + rotateOffset(Vector3.new(0, wallHeight/2, -size.Z/2 + wallThickness/2))
    backWall.Orientation = Vector3.new(0, rotation, 0)
    backWall.Anchored = true
    backWall.Material = Enum.Material.Wood
    backWall.Color = barnRed
    backWall.Parent = exterior

    -- Left wall
    local leftWall = Instance.new("Part")
    leftWall.Name = "BarnLeftWall"
    leftWall.Size = Vector3.new(wallThickness, wallHeight, size.Z)
    leftWall.Position = position + rotateOffset(Vector3.new(-size.X/2 + wallThickness/2, wallHeight/2, 0))
    leftWall.Orientation = Vector3.new(0, rotation, 0)
    leftWall.Anchored = true
    leftWall.Material = Enum.Material.Wood
    leftWall.Color = barnRed
    leftWall.Parent = exterior

    -- Right wall
    local rightWall = Instance.new("Part")
    rightWall.Name = "BarnRightWall"
    rightWall.Size = Vector3.new(wallThickness, wallHeight, size.Z)
    rightWall.Position = position + rotateOffset(Vector3.new(size.X/2 - wallThickness/2, wallHeight/2, 0))
    rightWall.Orientation = Vector3.new(0, rotation, 0)
    rightWall.Anchored = true
    rightWall.Material = Enum.Material.Wood
    rightWall.Color = barnRed
    rightWall.Parent = exterior

    -- Front wall left (beside large barn doors)
    local doorWidth = 8 -- Large barn doors
    local frontLeft = Instance.new("Part")
    frontLeft.Name = "BarnFrontLeft"
    frontLeft.Size = Vector3.new((size.X - doorWidth) / 2, wallHeight, wallThickness)
    frontLeft.Position = position + rotateOffset(Vector3.new(-(size.X/4 + doorWidth/4), wallHeight/2, size.Z/2 - wallThickness/2))
    frontLeft.Orientation = Vector3.new(0, rotation, 0)
    frontLeft.Anchored = true
    frontLeft.Material = Enum.Material.Wood
    frontLeft.Color = barnRed
    frontLeft.Parent = exterior

    -- Front wall right (beside large barn doors)
    local frontRight = Instance.new("Part")
    frontRight.Name = "BarnFrontRight"
    frontRight.Size = Vector3.new((size.X - doorWidth) / 2, wallHeight, wallThickness)
    frontRight.Position = position + rotateOffset(Vector3.new((size.X/4 + doorWidth/4), wallHeight/2, size.Z/2 - wallThickness/2))
    frontRight.Orientation = Vector3.new(0, rotation, 0)
    frontRight.Anchored = true
    frontRight.Material = Enum.Material.Wood
    frontRight.Color = barnRed
    frontRight.Parent = exterior

    -- Door frame top (above barn doors)
    local doorTop = Instance.new("Part")
    doorTop.Name = "BarnDoorTop"
    doorTop.Size = Vector3.new(doorWidth, 2, wallThickness)
    doorTop.Position = position + rotateOffset(Vector3.new(0, wallHeight - 1, size.Z/2 - wallThickness/2))
    doorTop.Orientation = Vector3.new(0, rotation, 0)
    doorTop.Anchored = true
    doorTop.Material = Enum.Material.Wood
    doorTop.Color = barnRed
    doorTop.Parent = exterior

    -- White trim around door frame
    local doorFrameLeft = Instance.new("Part")
    doorFrameLeft.Name = "DoorFrameLeft"
    doorFrameLeft.Size = Vector3.new(0.4, wallHeight - 2, wallThickness + 0.1)
    doorFrameLeft.Position = position + rotateOffset(Vector3.new(-doorWidth/2, (wallHeight - 2)/2, size.Z/2 - wallThickness/2))
    doorFrameLeft.Orientation = Vector3.new(0, rotation, 0)
    doorFrameLeft.Anchored = true
    doorFrameLeft.Material = Enum.Material.Wood
    doorFrameLeft.Color = whiteTrim
    doorFrameLeft.Parent = exterior

    local doorFrameRight = Instance.new("Part")
    doorFrameRight.Name = "DoorFrameRight"
    doorFrameRight.Size = Vector3.new(0.4, wallHeight - 2, wallThickness + 0.1)
    doorFrameRight.Position = position + rotateOffset(Vector3.new(doorWidth/2, (wallHeight - 2)/2, size.Z/2 - wallThickness/2))
    doorFrameRight.Orientation = Vector3.new(0, rotation, 0)
    doorFrameRight.Anchored = true
    doorFrameRight.Material = Enum.Material.Wood
    doorFrameRight.Color = whiteTrim
    doorFrameRight.Parent = exterior

    local doorFrameTopTrim = Instance.new("Part")
    doorFrameTopTrim.Name = "DoorFrameTopTrim"
    doorFrameTopTrim.Size = Vector3.new(doorWidth + 0.8, 0.4, wallThickness + 0.1)
    doorFrameTopTrim.Position = position + rotateOffset(Vector3.new(0, wallHeight - 2.2, size.Z/2 - wallThickness/2))
    doorFrameTopTrim.Orientation = Vector3.new(0, rotation, 0)
    doorFrameTopTrim.Anchored = true
    doorFrameTopTrim.Material = Enum.Material.Wood
    doorFrameTopTrim.Color = whiteTrim
    doorFrameTopTrim.Parent = exterior

    -- Open barn doors (swung outward)
    local doorHeight = wallHeight - 2.5
    local singleDoorWidth = doorWidth / 2 - 0.3

    local leftDoor = Instance.new("Part")
    leftDoor.Name = "BarnDoorLeft"
    leftDoor.Size = Vector3.new(singleDoorWidth, doorHeight, 0.3)
    local leftDoorPos = position + rotateOffset(Vector3.new(-doorWidth/2 - singleDoorWidth/3, doorHeight/2, size.Z/2 + 1))
    leftDoor.CFrame = CFrame.new(leftDoorPos) * CFrame.Angles(0, math.rad(rotation + 50), 0)
    leftDoor.Anchored = true
    leftDoor.Material = Enum.Material.Wood
    leftDoor.Color = barnRedDark
    leftDoor.Parent = exterior

    local rightDoor = Instance.new("Part")
    rightDoor.Name = "BarnDoorRight"
    rightDoor.Size = Vector3.new(singleDoorWidth, doorHeight, 0.3)
    local rightDoorPos = position + rotateOffset(Vector3.new(doorWidth/2 + singleDoorWidth/3, doorHeight/2, size.Z/2 + 1))
    rightDoor.CFrame = CFrame.new(rightDoorPos) * CFrame.Angles(0, math.rad(rotation - 50), 0)
    rightDoor.Anchored = true
    rightDoor.Material = Enum.Material.Wood
    rightDoor.Color = barnRedDark
    rightDoor.Parent = exterior

    -- X pattern on doors (classic barn style)
    local function addDoorX(door)
        local x1 = Instance.new("Part")
        x1.Name = "DoorX1"
        x1.Size = Vector3.new(0.15, doorHeight * 0.7, 0.05)
        x1.CFrame = door.CFrame * CFrame.new(0, 0, 0.18) * CFrame.Angles(0, 0, math.rad(25))
        x1.Anchored = true
        x1.Material = Enum.Material.Wood
        x1.Color = whiteTrim
        x1.Parent = exterior

        local x2 = Instance.new("Part")
        x2.Name = "DoorX2"
        x2.Size = Vector3.new(0.15, doorHeight * 0.7, 0.05)
        x2.CFrame = door.CFrame * CFrame.new(0, 0, 0.18) * CFrame.Angles(0, 0, math.rad(-25))
        x2.Anchored = true
        x2.Material = Enum.Material.Wood
        x2.Color = whiteTrim
        x2.Parent = exterior
    end
    addDoorX(leftDoor)
    addDoorX(rightDoor)

    -- White trim along top of walls
    local topTrim = Instance.new("Part")
    topTrim.Name = "TopTrim"
    topTrim.Size = Vector3.new(size.X + 0.5, 0.4, size.Z + 0.5)
    topTrim.Position = position + Vector3.new(0, wallHeight + 0.2, 0)
    topTrim.Orientation = Vector3.new(0, rotation, 0)
    topTrim.Anchored = true
    topTrim.Material = Enum.Material.Wood
    topTrim.Color = whiteTrim
    topTrim.Parent = exterior

    -- GAMBREL ROOF (classic 4-panel barn roof)
    -- Lower panels are steep (~60°), upper panels are shallow (~30°)
    local roofOverhang = 1.5
    local roofPeakHeight = 6 -- Total height from wall top to ridge
    local roofLength = size.Z + roofOverhang * 2
    local halfWidth = size.X / 2

    -- Define the knee point (where lower meets upper) - 65% up the roof height
    local kneeHeight = roofPeakHeight * 0.65 -- About 3.9 studs up
    local lowerAngle = 60 -- Steep lower panels

    -- Calculate lower panel horizontal run based on angle and height
    local lowerRun = kneeHeight / math.tan(math.rad(lowerAngle))
    -- Knee X position (from center)
    local kneeX = halfWidth - lowerRun

    -- Lower panel length along slope
    local lowerLength = math.sqrt(lowerRun^2 + kneeHeight^2)

    -- Upper panel geometry - from knee to peak
    local upperRun = kneeX -- Horizontal distance from knee to center
    local upperRise = roofPeakHeight - kneeHeight -- Vertical distance to peak
    local upperLength = math.sqrt(upperRun^2 + upperRise^2)
    local upperAngle = math.deg(math.atan2(upperRise, upperRun))

    -- LOWER LEFT PANEL (steep, outer)
    local lowerLeft = Instance.new("Part")
    lowerLeft.Name = "RoofLowerLeft"
    lowerLeft.Size = Vector3.new(lowerLength + 0.3, 0.4, roofLength)
    -- Position at center of panel
    local lowerLeftX = -(halfWidth - lowerRun/2)
    local lowerLeftY = wallHeight + kneeHeight/2
    lowerLeft.Position = position + rotateOffset(Vector3.new(lowerLeftX, lowerLeftY, 0))
    lowerLeft.Orientation = Vector3.new(0, rotation, -lowerAngle)
    lowerLeft.Anchored = true
    lowerLeft.Material = Enum.Material.Metal
    lowerLeft.Color = roofGray
    lowerLeft.Parent = exterior

    -- LOWER RIGHT PANEL (steep, outer) - mirror of left
    local lowerRight = Instance.new("Part")
    lowerRight.Name = "RoofLowerRight"
    lowerRight.Size = Vector3.new(lowerLength + 0.3, 0.4, roofLength)
    local lowerRightX = halfWidth - lowerRun/2
    lowerRight.Position = position + rotateOffset(Vector3.new(lowerRightX, lowerLeftY, 0))
    lowerRight.Orientation = Vector3.new(0, rotation, lowerAngle)
    lowerRight.Anchored = true
    lowerRight.Material = Enum.Material.Metal
    lowerRight.Color = roofGray
    lowerRight.Parent = exterior

    -- UPPER LEFT PANEL (shallow, inner) - from knee up to ridge
    local upperLeft = Instance.new("Part")
    upperLeft.Name = "RoofUpperLeft"
    upperLeft.Size = Vector3.new(upperLength + 0.3, 0.4, roofLength)
    -- Position at center of upper panel
    local upperLeftX = -(kneeX/2) -- Halfway between knee and center
    local upperLeftY = wallHeight + kneeHeight + upperRise/2
    upperLeft.Position = position + rotateOffset(Vector3.new(upperLeftX, upperLeftY, 0))
    -- Negative angle = slopes UP toward center (right)
    upperLeft.Orientation = Vector3.new(0, rotation, -upperAngle)
    upperLeft.Anchored = true
    upperLeft.Material = Enum.Material.Metal
    upperLeft.Color = roofGray
    upperLeft.Parent = exterior

    -- UPPER RIGHT PANEL (shallow, inner) - mirror of left
    local upperRight = Instance.new("Part")
    upperRight.Name = "RoofUpperRight"
    upperRight.Size = Vector3.new(upperLength + 0.3, 0.4, roofLength)
    local upperRightX = kneeX/2 -- Halfway between knee and center
    upperRight.Position = position + rotateOffset(Vector3.new(upperRightX, upperLeftY, 0))
    -- Positive angle = slopes UP toward center (left)
    upperRight.Orientation = Vector3.new(0, rotation, upperAngle)
    upperRight.Anchored = true
    upperRight.Material = Enum.Material.Metal
    upperRight.Color = roofGray
    upperRight.Parent = exterior

    -- ROOF RIDGE CAP (peak)
    local roofRidge = Instance.new("Part")
    roofRidge.Name = "RoofRidge"
    roofRidge.Size = Vector3.new(1.5, 0.5, roofLength)
    roofRidge.Position = position + Vector3.new(0, wallHeight + roofPeakHeight + 0.2, 0)
    roofRidge.Orientation = Vector3.new(0, rotation, 0)
    roofRidge.Anchored = true
    roofRidge.Material = Enum.Material.Metal
    roofRidge.Color = Color3.fromRGB(60, 60, 65)
    roofRidge.Parent = exterior

    -- GABLE FILL (red barn wall under roof at front and back)
    -- Reduce heights slightly so they don't poke through angled roof
    local gableInset = 0.8 -- How much shorter to make gable fills

    -- Front gable - fill the gambrel shape with barn red
    local upperGableHeight = (roofPeakHeight - kneeHeight) - gableInset
    local frontGableUpper = Instance.new("Part")
    frontGableUpper.Name = "FrontGableUpper"
    frontGableUpper.Size = Vector3.new(kneeX * 2 - gableInset, upperGableHeight, 0.4)
    frontGableUpper.Position = position + rotateOffset(Vector3.new(0, wallHeight + kneeHeight + upperGableHeight/2, size.Z/2 + 0.2))
    frontGableUpper.Orientation = Vector3.new(0, rotation, 0)
    frontGableUpper.Anchored = true
    frontGableUpper.Material = Enum.Material.Wood
    frontGableUpper.Color = barnRed
    frontGableUpper.Parent = exterior

    local lowerGableHeight = kneeHeight - gableInset
    local frontGableLowerLeft = Instance.new("Part")
    frontGableLowerLeft.Name = "FrontGableLowerLeft"
    frontGableLowerLeft.Size = Vector3.new(lowerRun - gableInset/2, lowerGableHeight, 0.4)
    frontGableLowerLeft.Position = position + rotateOffset(Vector3.new(-(kneeX + lowerRun/2), wallHeight + lowerGableHeight/2, size.Z/2 + 0.2))
    frontGableLowerLeft.Orientation = Vector3.new(0, rotation, 0)
    frontGableLowerLeft.Anchored = true
    frontGableLowerLeft.Material = Enum.Material.Wood
    frontGableLowerLeft.Color = barnRed
    frontGableLowerLeft.Parent = exterior

    local frontGableLowerRight = Instance.new("Part")
    frontGableLowerRight.Name = "FrontGableLowerRight"
    frontGableLowerRight.Size = Vector3.new(lowerRun - gableInset/2, lowerGableHeight, 0.4)
    frontGableLowerRight.Position = position + rotateOffset(Vector3.new(kneeX + lowerRun/2, wallHeight + lowerGableHeight/2, size.Z/2 + 0.2))
    frontGableLowerRight.Orientation = Vector3.new(0, rotation, 0)
    frontGableLowerRight.Anchored = true
    frontGableLowerRight.Material = Enum.Material.Wood
    frontGableLowerRight.Color = barnRed
    frontGableLowerRight.Parent = exterior

    -- Back gable - same fill pattern
    local backGableUpper = Instance.new("Part")
    backGableUpper.Name = "BackGableUpper"
    backGableUpper.Size = Vector3.new(kneeX * 2 - gableInset, upperGableHeight, 0.4)
    backGableUpper.Position = position + rotateOffset(Vector3.new(0, wallHeight + kneeHeight + upperGableHeight/2, -size.Z/2 - 0.2))
    backGableUpper.Orientation = Vector3.new(0, rotation, 0)
    backGableUpper.Anchored = true
    backGableUpper.Material = Enum.Material.Wood
    backGableUpper.Color = barnRed
    backGableUpper.Parent = exterior

    local backGableLowerLeft = Instance.new("Part")
    backGableLowerLeft.Name = "BackGableLowerLeft"
    backGableLowerLeft.Size = Vector3.new(lowerRun - gableInset/2, lowerGableHeight, 0.4)
    backGableLowerLeft.Position = position + rotateOffset(Vector3.new(-(kneeX + lowerRun/2), wallHeight + lowerGableHeight/2, -size.Z/2 - 0.2))
    backGableLowerLeft.Orientation = Vector3.new(0, rotation, 0)
    backGableLowerLeft.Anchored = true
    backGableLowerLeft.Material = Enum.Material.Wood
    backGableLowerLeft.Color = barnRed
    backGableLowerLeft.Parent = exterior

    local backGableLowerRight = Instance.new("Part")
    backGableLowerRight.Name = "BackGableLowerRight"
    backGableLowerRight.Size = Vector3.new(lowerRun - gableInset/2, lowerGableHeight, 0.4)
    backGableLowerRight.Position = position + rotateOffset(Vector3.new(kneeX + lowerRun/2, wallHeight + lowerGableHeight/2, -size.Z/2 - 0.2))
    backGableLowerRight.Orientation = Vector3.new(0, rotation, 0)
    backGableLowerRight.Anchored = true
    backGableLowerRight.Material = Enum.Material.Wood
    backGableLowerRight.Color = barnRed
    backGableLowerRight.Parent = exterior

    -- Hay bales outside barn (decorative)
    local hayColors = {
        Color3.fromRGB(218, 190, 130),
        Color3.fromRGB(195, 170, 115),
    }
    for i = 1, 3 do
        local hay = Instance.new("Part")
        hay.Name = "HayBale" .. i
        hay.Size = Vector3.new(1.2, 0.8, 1)
        hay.Position = position + rotateOffset(Vector3.new(-size.X/2 - 2 + (i-1) * 1.5, 0.9, size.Z/4))
        hay.Orientation = Vector3.new(0, rotation + (i * 15), 0)
        hay.Anchored = true
        hay.Material = Enum.Material.Fabric
        hay.Color = hayColors[(i % 2) + 1]
        hay.Parent = exterior
    end

    -- Window shutters (on side walls)
    for _, side in {-1, 1} do
        for _, wz in {-size.Z/4, size.Z/4} do
            -- Window opening (dark inset)
            local windowFrame = Instance.new("Part")
            windowFrame.Name = "Window"
            windowFrame.Size = Vector3.new(0.3, 2, 1.5)
            windowFrame.Position = position + rotateOffset(Vector3.new(side * (size.X/2 + 0.1), wallHeight * 0.6, wz))
            windowFrame.Orientation = Vector3.new(0, rotation, 0)
            windowFrame.Anchored = true
            windowFrame.Material = Enum.Material.Slate
            windowFrame.Color = Color3.fromRGB(20, 15, 10)
            windowFrame.CanCollide = false
            windowFrame.Parent = exterior

            -- Shutter (angled open)
            local shutter = Instance.new("Part")
            shutter.Name = "Shutter"
            shutter.Size = Vector3.new(0.15, 2, 0.8)
            shutter.Position = position + rotateOffset(Vector3.new(side * (size.X/2 + 0.3), wallHeight * 0.6, wz + 1))
            shutter.Orientation = Vector3.new(0, rotation + side * 30, 0)
            shutter.Anchored = true
            shutter.Material = Enum.Material.Wood
            shutter.Color = barnRedDark
            shutter.CanCollide = false
            shutter.Parent = exterior
        end
    end

    -- Weathervane on roof ridge
    local vanePost = Instance.new("Part")
    vanePost.Name = "WeathervanePost"
    vanePost.Size = Vector3.new(0.15, 2, 0.15)
    vanePost.Position = position + Vector3.new(0, wallHeight + roofPeakHeight + 1.5, 0)
    vanePost.Anchored = true
    vanePost.Material = Enum.Material.Metal
    vanePost.Color = Color3.fromRGB(50, 50, 55)
    vanePost.CanCollide = false
    vanePost.Parent = exterior

    local vaneArrow = Instance.new("Part")
    vaneArrow.Name = "WeathervaneArrow"
    vaneArrow.Size = Vector3.new(0.1, 0.1, 2)
    vaneArrow.Position = position + Vector3.new(0, wallHeight + roofPeakHeight + 2.5, 0)
    vaneArrow.Orientation = Vector3.new(0, 30, 0)
    vaneArrow.Anchored = true
    vaneArrow.Material = Enum.Material.Metal
    vaneArrow.Color = Color3.fromRGB(50, 50, 55)
    vaneArrow.CanCollide = false
    vaneArrow.Parent = exterior

    -- Entrance trigger (invisible, walk-through teleport)
    local entrance = Instance.new("Part")
    entrance.Name = "Entrance"
    entrance.Size = Vector3.new(doorWidth - 1, wallHeight - 2, 2)
    entrance.Position = position + rotateOffset(Vector3.new(0, (wallHeight - 2)/2, size.Z/2 + 1))
    entrance.Orientation = Vector3.new(0, rotation, 0)
    entrance.Anchored = true
    entrance.Transparency = 1
    entrance.CanCollide = false
    entrance.Parent = exterior

    -- Debounce to prevent multiple teleports
    local debounce = {}
    entrance.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end

        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end

        if debounce[player.UserId] then return end
        debounce[player.UserId] = true

        teleportToInterior(player, buildingName)

        task.delay(1, function()
            debounce[player.UserId] = nil
        end)
    end)

    -- Building sign (centered above door)
    createSign(exterior, name, position + rotateOffset(Vector3.new(0, wallHeight + roofPeakHeight + 1.5, size.Z/2 + 1)), Vector3.new(8, 2.5, 0.3))

    -- Torches by entrance
    createTorch(exterior, position + rotateOffset(Vector3.new(-doorWidth/2 - 1.5, 4, size.Z/2 + 0.5)))
    createTorch(exterior, position + rotateOffset(Vector3.new(doorWidth/2 + 1.5, 4, size.Z/2 + 0.5)))

    exterior.Parent = villageFolder
    return exterior
end

-- Create building exterior (shell with entrance)
-- facingDirection: "north" (default/-Z back), "south" (+Z back), "east" (+X door), "west" (-X door)
local function createBuildingExterior(name, position, size, roofColor, wallColor, buildingName, facingDirection)
    facingDirection = facingDirection or "north"

    local exterior = Instance.new("Model")
    exterior.Name = name .. "_Exterior"

    local wallHeight = size.Y
    local wallThickness = 1

    -- Calculate rotation based on facing direction (rotation around Y axis)
    local rotation = 0
    if facingDirection == "south" then
        rotation = 180
    elseif facingDirection == "east" then
        rotation = -90  -- Door faces +X (toward path on the right)
    elseif facingDirection == "west" then
        rotation = 90   -- Door faces -X (toward path on the left)
    end

    -- Helper to rotate offset around Y axis
    local function rotateOffset(offset)
        local rad = math.rad(rotation)
        local cos, sin = math.cos(rad), math.sin(rad)
        return Vector3.new(
            offset.X * cos - offset.Z * sin,
            offset.Y,
            offset.X * sin + offset.Z * cos
        )
    end

    -- Floor
    local floor = Instance.new("Part")
    floor.Name = "Floor"
    floor.Size = Vector3.new(size.X, 0.5, size.Z)
    floor.Position = position + Vector3.new(0, 0.25, 0)
    floor.Orientation = Vector3.new(0, rotation, 0)
    floor.Anchored = true
    floor.Material = Enum.Material.Cobblestone
    floor.Color = Color3.fromRGB(100, 95, 90)
    floor.Parent = exterior

    -- Back wall
    local backWall = Instance.new("Part")
    backWall.Name = "BackWall"
    backWall.Size = Vector3.new(size.X, wallHeight, wallThickness)
    backWall.Position = position + rotateOffset(Vector3.new(0, wallHeight/2, -size.Z/2 + wallThickness/2))
    backWall.Orientation = Vector3.new(0, rotation, 0)
    backWall.Anchored = true
    backWall.Material = Enum.Material.Brick
    backWall.Color = wallColor
    backWall.Parent = exterior

    -- Left wall
    local leftWall = Instance.new("Part")
    leftWall.Name = "LeftWall"
    leftWall.Size = Vector3.new(wallThickness, wallHeight, size.Z)
    leftWall.Position = position + rotateOffset(Vector3.new(-size.X/2 + wallThickness/2, wallHeight/2, 0))
    leftWall.Orientation = Vector3.new(0, rotation, 0)
    leftWall.Anchored = true
    leftWall.Material = Enum.Material.Brick
    leftWall.Color = wallColor
    leftWall.Parent = exterior

    -- Right wall
    local rightWall = Instance.new("Part")
    rightWall.Name = "RightWall"
    rightWall.Size = Vector3.new(wallThickness, wallHeight, size.Z)
    rightWall.Position = position + rotateOffset(Vector3.new(size.X/2 - wallThickness/2, wallHeight/2, 0))
    rightWall.Orientation = Vector3.new(0, rotation, 0)
    rightWall.Anchored = true
    rightWall.Material = Enum.Material.Brick
    rightWall.Color = wallColor
    rightWall.Parent = exterior

    -- Front wall left (with door gap)
    local frontLeft = Instance.new("Part")
    frontLeft.Name = "FrontWallLeft"
    frontLeft.Size = Vector3.new((size.X - 6) / 2, wallHeight, wallThickness)
    frontLeft.Position = position + rotateOffset(Vector3.new(-(size.X/4 + 1.5), wallHeight/2, size.Z/2 - wallThickness/2))
    frontLeft.Orientation = Vector3.new(0, rotation, 0)
    frontLeft.Anchored = true
    frontLeft.Material = Enum.Material.Brick
    frontLeft.Color = wallColor
    frontLeft.Parent = exterior

    -- Front wall right (with door gap)
    local frontRight = Instance.new("Part")
    frontRight.Name = "FrontWallRight"
    frontRight.Size = Vector3.new((size.X - 6) / 2, wallHeight, wallThickness)
    frontRight.Position = position + rotateOffset(Vector3.new((size.X/4 + 1.5), wallHeight/2, size.Z/2 - wallThickness/2))
    frontRight.Orientation = Vector3.new(0, rotation, 0)
    frontRight.Anchored = true
    frontRight.Material = Enum.Material.Brick
    frontRight.Color = wallColor
    frontRight.Parent = exterior

    -- Door frame top
    local doorTop = Instance.new("Part")
    doorTop.Name = "DoorTop"
    doorTop.Size = Vector3.new(6, 2, wallThickness)
    doorTop.Position = position + rotateOffset(Vector3.new(0, wallHeight - 1, size.Z/2 - wallThickness/2))
    doorTop.Orientation = Vector3.new(0, rotation, 0)
    doorTop.Anchored = true
    doorTop.Material = Enum.Material.Brick
    doorTop.Color = wallColor
    doorTop.Parent = exterior

    -- Peaked roof (two sloped panels instead of flat)
    local roofOverhang = 1
    local roofPeakH = 4
    local roofHalfWidth = (size.X + 2) / 2
    local roofSlopeLen = math.sqrt(roofHalfWidth^2 + roofPeakH^2)
    local roofAngle = math.deg(math.atan2(roofPeakH, roofHalfWidth))

    local roofLeft = Instance.new("Part")
    roofLeft.Name = "RoofLeft"
    roofLeft.Size = Vector3.new(roofSlopeLen, 0.5, size.Z + 2)
    roofLeft.Position = position + rotateOffset(Vector3.new(-roofHalfWidth/2, wallHeight + roofPeakH/2, 0))
    roofLeft.Orientation = Vector3.new(0, rotation, -roofAngle)
    roofLeft.Anchored = true
    roofLeft.Material = Enum.Material.Slate
    roofLeft.Color = roofColor
    roofLeft.Parent = exterior

    local roofRight = Instance.new("Part")
    roofRight.Name = "RoofRight"
    roofRight.Size = Vector3.new(roofSlopeLen, 0.5, size.Z + 2)
    roofRight.Position = position + rotateOffset(Vector3.new(roofHalfWidth/2, wallHeight + roofPeakH/2, 0))
    roofRight.Orientation = Vector3.new(0, rotation, roofAngle)
    roofRight.Anchored = true
    roofRight.Material = Enum.Material.Slate
    roofRight.Color = roofColor
    roofRight.Parent = exterior

    -- Ridge cap
    local ridge = Instance.new("Part")
    ridge.Name = "RoofRidge"
    ridge.Size = Vector3.new(1, 0.4, size.Z + 2)
    ridge.Position = position + Vector3.new(0, wallHeight + roofPeakH + 0.2, 0)
    ridge.Orientation = Vector3.new(0, rotation, 0)
    ridge.Anchored = true
    ridge.Material = Enum.Material.Slate
    ridge.Color = Color3.fromRGB(roofColor.R * 200, roofColor.G * 200, roofColor.B * 200)
    ridge.Parent = exterior

    -- Entrance trigger (invisible, walk-through teleport)
    local entrance = Instance.new("Part")
    entrance.Name = "Entrance"
    entrance.Size = Vector3.new(5, 7, 2)
    entrance.Position = position + rotateOffset(Vector3.new(0, 3.5, size.Z/2 + 1))
    entrance.Orientation = Vector3.new(0, rotation, 0)
    entrance.Anchored = true
    entrance.Transparency = 1
    entrance.CanCollide = false
    entrance.Parent = exterior

    -- Debounce to prevent multiple teleports
    local debounce = {}
    entrance.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end

        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end

        -- Debounce check
        if debounce[player.UserId] then return end
        debounce[player.UserId] = true

        teleportToInterior(player, buildingName)

        -- Reset debounce after delay
        task.delay(1, function()
            debounce[player.UserId] = nil
        end)
    end)

    -- Window openings with glass
    for _, side in {-1, 1} do
        local windowGlass = Instance.new("Part")
        windowGlass.Name = "Window"
        windowGlass.Size = Vector3.new(0.3, 2.5, 2)
        windowGlass.Position = position + rotateOffset(Vector3.new(side * (size.X/2 + 0.1), wallHeight * 0.5, 0))
        windowGlass.Orientation = Vector3.new(0, rotation, 0)
        windowGlass.Anchored = true
        windowGlass.Material = Enum.Material.Glass
        windowGlass.Color = Color3.fromRGB(180, 210, 230)
        windowGlass.Transparency = 0.4
        windowGlass.CanCollide = false
        windowGlass.Parent = exterior
    end

    -- Door frame trim (wooden beams around entrance)
    local doorFrameColor = Color3.fromRGB(70, 48, 30)
    for _, dx in {-3.2, 3.2} do
        local dFrame = Instance.new("Part")
        dFrame.Name = "DoorFrame"
        dFrame.Size = Vector3.new(0.4, wallHeight - 2, 0.4)
        dFrame.Position = position + rotateOffset(Vector3.new(dx, (wallHeight - 2)/2, size.Z/2))
        dFrame.Orientation = Vector3.new(0, rotation, 0)
        dFrame.Anchored = true
        dFrame.Material = Enum.Material.Wood
        dFrame.Color = doorFrameColor
        dFrame.CanCollide = false
        dFrame.Parent = exterior
    end
    local dFrameTop = Instance.new("Part")
    dFrameTop.Name = "DoorFrameTop"
    dFrameTop.Size = Vector3.new(6.8, 0.4, 0.4)
    dFrameTop.Position = position + rotateOffset(Vector3.new(0, wallHeight - 2.2, size.Z/2))
    dFrameTop.Orientation = Vector3.new(0, rotation, 0)
    dFrameTop.Anchored = true
    dFrameTop.Material = Enum.Material.Wood
    dFrameTop.Color = doorFrameColor
    dFrameTop.CanCollide = false
    dFrameTop.Parent = exterior

    -- Banner/flag on wall
    local flagPole = Instance.new("Part")
    flagPole.Name = "FlagPole"
    flagPole.Size = Vector3.new(0.2, 4, 0.2)
    flagPole.Position = position + rotateOffset(Vector3.new(size.X/2 - 1, wallHeight + 2, size.Z/2 - 0.5))
    flagPole.Orientation = Vector3.new(0, rotation, -15)
    flagPole.Anchored = true
    flagPole.Material = Enum.Material.Metal
    flagPole.Color = Color3.fromRGB(60, 55, 50)
    flagPole.CanCollide = false
    flagPole.Parent = exterior

    local flag = Instance.new("Part")
    flag.Name = "Flag"
    flag.Size = Vector3.new(0.1, 2, 1.5)
    flag.Position = position + rotateOffset(Vector3.new(size.X/2 - 0.5, wallHeight + 3, size.Z/2 + 0.3))
    flag.Orientation = Vector3.new(0, rotation, 0)
    flag.Anchored = true
    flag.Material = Enum.Material.Fabric
    flag.Color = Color3.fromRGB(180, 30, 30)
    flag.CanCollide = false
    flag.Parent = exterior

    -- Building sign
    createSign(exterior, name, position + Vector3.new(0, wallHeight + 2, size.Z/2), Vector3.new(6, 2, 0.3))

    -- Torches by entrance
    createTorch(exterior, position + Vector3.new(-4, 3, size.Z/2))
    createTorch(exterior, position + Vector3.new(4, 3, size.Z/2))

    exterior.Parent = villageFolder
    return exterior
end

-- Create interior space (floor, walls, lighting, exit portal)
local function createInteriorSpace(buildingName, floorSize, wallHeight)
    local basePos = INTERIOR_POSITIONS[buildingName]
    local interior = Instance.new("Model")
    interior.Name = buildingName .. "_Interior"

    -- Large floor
    local floor = Instance.new("Part")
    floor.Name = "InteriorFloor"
    floor.Size = Vector3.new(floorSize.X, 2, floorSize.Z)
    floor.Position = basePos + Vector3.new(0, 1, 0)
    floor.Anchored = true
    floor.Material = Enum.Material.Cobblestone
    floor.Color = Color3.fromRGB(110, 105, 100)
    floor.Parent = interior

    -- Walls around interior
    local wallColor = Color3.fromRGB(90, 80, 70)
    local wh = wallHeight or 15

    -- Back wall
    local backWall = Instance.new("Part")
    backWall.Name = "BackWall"
    backWall.Size = Vector3.new(floorSize.X, wh, 2)
    backWall.Position = basePos + Vector3.new(0, wh/2 + 2, -floorSize.Z/2)
    backWall.Anchored = true
    backWall.Material = Enum.Material.Brick
    backWall.Color = wallColor
    backWall.Parent = interior

    -- Left wall
    local leftWall = Instance.new("Part")
    leftWall.Name = "LeftWall"
    leftWall.Size = Vector3.new(2, wh, floorSize.Z)
    leftWall.Position = basePos + Vector3.new(-floorSize.X/2, wh/2 + 2, 0)
    leftWall.Anchored = true
    leftWall.Material = Enum.Material.Brick
    leftWall.Color = wallColor
    leftWall.Parent = interior

    -- Right wall
    local rightWall = Instance.new("Part")
    rightWall.Name = "RightWall"
    rightWall.Size = Vector3.new(2, wh, floorSize.Z)
    rightWall.Position = basePos + Vector3.new(floorSize.X/2, wh/2 + 2, 0)
    rightWall.Anchored = true
    rightWall.Material = Enum.Material.Brick
    rightWall.Color = wallColor
    rightWall.Parent = interior

    -- Front wall (with exit gap)
    local frontLeft = Instance.new("Part")
    frontLeft.Name = "FrontLeft"
    frontLeft.Size = Vector3.new((floorSize.X - 8) / 2, wh, 2)
    frontLeft.Position = basePos + Vector3.new(-(floorSize.X/4 + 2), wh/2 + 2, floorSize.Z/2)
    frontLeft.Anchored = true
    frontLeft.Material = Enum.Material.Brick
    frontLeft.Color = wallColor
    frontLeft.Parent = interior

    local frontRight = Instance.new("Part")
    frontRight.Name = "FrontRight"
    frontRight.Size = Vector3.new((floorSize.X - 8) / 2, wh, 2)
    frontRight.Position = basePos + Vector3.new((floorSize.X/4 + 2), wh/2 + 2, floorSize.Z/2)
    frontRight.Anchored = true
    frontRight.Material = Enum.Material.Brick
    frontRight.Color = wallColor
    frontRight.Parent = interior

    -- Ceiling with skylights
    local ceiling = Instance.new("Part")
    ceiling.Name = "Ceiling"
    ceiling.Size = Vector3.new(floorSize.X, 1, floorSize.Z)
    ceiling.Position = basePos + Vector3.new(0, wh + 2.5, 0)
    ceiling.Anchored = true
    ceiling.Material = Enum.Material.Slate
    ceiling.Color = Color3.fromRGB(60, 55, 50)
    ceiling.Parent = interior

    -- Ambient lighting
    for x = -1, 1 do
        for z = -1, 1 do
            local light = Instance.new("Part")
            light.Name = "Light"
            light.Size = Vector3.new(2, 0.5, 2)
            light.Position = basePos + Vector3.new(x * (floorSize.X/4), wh + 2, z * (floorSize.Z/4))
            light.Anchored = true
            light.Material = Enum.Material.Neon
            light.Color = Color3.fromRGB(255, 240, 200)
            light.Parent = interior

            local pointLight = Instance.new("PointLight")
            pointLight.Color = Color3.fromRGB(255, 240, 200)
            pointLight.Brightness = 1
            pointLight.Range = 30
            pointLight.Parent = light
        end
    end

    -- Exit portal
    createExitPortal(interior, basePos + Vector3.new(0, 6, floorSize.Z/2 + 2))

    -- Building name sign inside
    createSign(interior, buildingName:upper() .. " INTERIOR", basePos + Vector3.new(0, wh, -floorSize.Z/2 + 2), Vector3.new(10, 2, 0.3))

    interior.Parent = interiorsFolder
    return interior, basePos + Vector3.new(0, 2, 0) -- Return interior model and base position for stations
end

-- Player resources storage (per player)
local PlayerResources = {}

local function getPlayerResources(player)
    if not PlayerResources[player.UserId] then
        PlayerResources[player.UserId] = {
            gold = 0,
            wood = 0,
            food = 0,
            stone = 0,
        }
    end
    return PlayerResources[player.UserId]
end

-- Mini-game reward function - ACTUALLY stores resources AND updates HUD
local function rewardPlayer(player, resourceType, amount, buildingName)
    -- Determine reward recipient: if visitor, redirect rewards to base owner
    local recipient = player
    local isHelper = false
    if not isVillageOwner(player) and _villageOwnerUserId then
        isHelper = true
        local ownerPlayer = Players:GetPlayerByUserId(_villageOwnerUserId)
        if ownerPlayer then
            recipient = ownerPlayer
            print(string.format("[REWARD] Visitor %s helping! Redirecting +%d %s to owner %s",
                player.Name, amount, resourceType, ownerPlayer.Name))
        else
            -- Owner offline: skip reward (no player object to award to)
            print(string.format("[REWARD] Visitor %s helping but owner (ID %d) is offline, skipping reward",
                player.Name, _villageOwnerUserId))
            return
        end
    end

    -- Add resources to recipient's local storage (for mini-game tracking)
    local resources = getPlayerResources(recipient)
    if resources[resourceType] then
        resources[resourceType] = resources[resourceType] + amount
        print(string.format("[REWARD] %s gained +%d %s! (Local total: %d)",
            recipient.Name, amount, resourceType, resources[resourceType]))
    else
        warn("[REWARD] Unknown resource type:", resourceType)
    end

    -- UPDATE DATASERVICE (this is what the HUD reads from!)
    if DataService then
        local playerData = DataService:GetPlayerData(recipient)
        if playerData then
            -- Build resource change table based on type
            local changes = {}
            changes[resourceType] = amount

            -- Update resources in DataService
            local success = DataService:UpdateResources(recipient, changes)
            if success then
                print(string.format("[REWARD] Updated DataService: %s +%d %s (DataService total: %d)",
                    recipient.Name, amount, resourceType, playerData.resources[resourceType] or 0))

                -- Fire SyncPlayerData to update the owner's HUD
                local Events = ReplicatedStorage:FindFirstChild("Events")
                if Events then
                    local SyncPlayerData = Events:FindFirstChild("SyncPlayerData")
                    if SyncPlayerData then
                        SyncPlayerData:FireClient(recipient, playerData)
                        print(string.format("[REWARD] Synced HUD for %s", recipient.Name))
                    end
                end
            else
                warn("[REWARD] Failed to update DataService for", recipient.Name)
            end
        else
            warn("[REWARD] No player data found for", recipient.Name)
        end
    else
        warn("[REWARD] DataService not available yet")
    end

    -- Fire reward notification to the acting player
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if Events then
        local ServerResponse = Events:FindFirstChild("ServerResponse")
        if ServerResponse then
            if isHelper then
                -- Visitor sees "Helped +X resource!" notification
                ServerResponse:FireClient(player, "MiniGameReward", {
                    success = true,
                    resourceType = resourceType,
                    amount = amount,
                    building = buildingName,
                    newTotal = resources[resourceType],
                    isHelper = true,
                })
            else
                -- Owner sees normal reward notification
                ServerResponse:FireClient(player, "MiniGameReward", {
                    success = true,
                    resourceType = resourceType,
                    amount = amount,
                    building = buildingName,
                    newTotal = resources[resourceType]
                })
            end
        end
    end

    -- Update building progress
    if not BuildingProgress[buildingName] then
        BuildingProgress[buildingName] = { xp = 0, level = 1 }
    end
    BuildingProgress[buildingName].xp = BuildingProgress[buildingName].xp + amount

    -- Level up check (every 100 XP)
    local progress = BuildingProgress[buildingName]
    if progress.xp >= progress.level * 100 then
        progress.level = progress.level + 1
        print(string.format("[MiniGame] %s leveled up to %d!", buildingName, progress.level))
    end
end

-- Clean up player resources when they leave
Players.PlayerRemoving:Connect(function(player)
    PlayerResources[player.UserId] = nil
    PlayerReturnPositions[player.UserId] = nil
    PlayerCurrentBuilding[player.UserId] = nil
end)

-- ============================================================================
-- GROUND AND SPAWN
-- ============================================================================

local function createGround()
    print("[1/8] Creating ground, paths, and village walls...")

    -- Main village ground (extended for new layout)
    local ground = Instance.new("Part")
    ground.Name = "VillageGround"
    ground.Size = Vector3.new(130, 2, 170)
    ground.Position = Vector3.new(60, 1, 90)
    ground.Anchored = true
    ground.Material = Enum.Material.Cobblestone
    ground.Color = Color3.fromRGB(90, 85, 80)
    ground.Parent = villageFolder

    -- Grass patches around village edges
    local grassPositions = {
        {pos = Vector3.new(10, GROUND_Y + 0.05, 25), size = Vector3.new(18, 0.1, 20)},
        {pos = Vector3.new(110, GROUND_Y + 0.05, 25), size = Vector3.new(18, 0.1, 20)},
        {pos = Vector3.new(10, GROUND_Y + 0.05, 155), size = Vector3.new(18, 0.1, 20)},
        {pos = Vector3.new(110, GROUND_Y + 0.05, 155), size = Vector3.new(18, 0.1, 20)},
        {pos = Vector3.new(5, GROUND_Y + 0.05, 90), size = Vector3.new(12, 0.1, 60)},
        {pos = Vector3.new(115, GROUND_Y + 0.05, 90), size = Vector3.new(12, 0.1, 60)},
    }
    for i, gp in grassPositions do
        local grass = Instance.new("Part")
        grass.Name = "GrassPatch" .. i
        grass.Size = gp.size
        grass.Position = gp.pos
        grass.Anchored = true
        grass.Material = Enum.Material.Grass
        grass.Color = Color3.fromRGB(60 + math.random(20), 110 + math.random(30), 45 + math.random(15))
        grass.CanCollide = false
        grass.Parent = villageFolder
    end

    -- Main cobblestone path (runs from entrance to Town Hall at the end)
    local mainPath = Instance.new("Part")
    mainPath.Name = "MainPath"
    mainPath.Size = Vector3.new(12, 0.1, 150)  -- Wider, longer path
    mainPath.Position = Vector3.new(60, GROUND_Y + 0.15, 90)
    mainPath.Anchored = true
    mainPath.Material = Enum.Material.Cobblestone
    mainPath.Color = Color3.fromRGB(100, 95, 90)
    mainPath.Parent = villageFolder

    -- Cross path at first row of buildings (Gold Mine / Lumber Mill)
    local crossPath1 = Instance.new("Part")
    crossPath1.Name = "CrossPath1"
    crossPath1.Size = Vector3.new(90, 0.1, 8)
    crossPath1.Position = Vector3.new(60, GROUND_Y + 0.15, 50)
    crossPath1.Anchored = true
    crossPath1.Material = Enum.Material.Cobblestone
    crossPath1.Color = Color3.fromRGB(100, 95, 90)
    crossPath1.Parent = villageFolder

    -- Cross path at second row of buildings (Farm / Barracks)
    local crossPath2 = Instance.new("Part")
    crossPath2.Name = "CrossPath2"
    crossPath2.Size = Vector3.new(90, 0.1, 8)
    crossPath2.Position = Vector3.new(60, GROUND_Y + 0.15, 100)
    crossPath2.Anchored = true
    crossPath2.Material = Enum.Material.Cobblestone
    crossPath2.Color = Color3.fromRGB(100, 95, 90)
    crossPath2.Parent = villageFolder

    -- Town Hall plaza at the end
    local plaza = Instance.new("Part")
    plaza.Name = "TownHallPlaza"
    plaza.Size = Vector3.new(40, 0.1, 30)
    plaza.Position = Vector3.new(60, GROUND_Y + 0.15, 155)
    plaza.Anchored = true
    plaza.Material = Enum.Material.Cobblestone
    plaza.Color = Color3.fromRGB(110, 105, 100)
    plaza.Parent = villageFolder

    -- Spawn location at entrance (facing into village)
    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "VillageSpawn"
    spawn.Size = Vector3.new(6, 1, 6)
    spawn.Position = Vector3.new(60, GROUND_Y + 0.5, 18)
    spawn.Orientation = Vector3.new(0, 0, 0) -- Face into village (positive Z)
    spawn.Anchored = true
    spawn.Material = Enum.Material.Cobblestone
    spawn.Color = Color3.fromRGB(110, 105, 100)
    spawn.Neutral = true
    spawn.Duration = 0
    spawn.CanCollide = false
    spawn.Transparency = 0.5
    spawn.Parent = villageFolder

    -- ========== VILLAGE WALLS ==========
    local wallHeight = 8
    local wallThickness = 3
    local wallColor = Color3.fromRGB(75, 70, 65)

    -- Left wall
    local leftWall = Instance.new("Part")
    leftWall.Name = "LeftWall"
    leftWall.Size = Vector3.new(wallThickness, wallHeight, 160)
    leftWall.Position = Vector3.new(-5, GROUND_Y + wallHeight/2, 90)
    leftWall.Anchored = true
    leftWall.Material = Enum.Material.Cobblestone
    leftWall.Color = wallColor
    leftWall.Parent = villageFolder

    -- Right wall
    local rightWall = Instance.new("Part")
    rightWall.Name = "RightWall"
    rightWall.Size = Vector3.new(wallThickness, wallHeight, 160)
    rightWall.Position = Vector3.new(125, GROUND_Y + wallHeight/2, 90)
    rightWall.Anchored = true
    rightWall.Material = Enum.Material.Cobblestone
    rightWall.Color = wallColor
    rightWall.Parent = villageFolder

    -- Back wall (behind Town Hall)
    local backWall = Instance.new("Part")
    backWall.Name = "BackWall"
    backWall.Size = Vector3.new(133, wallHeight, wallThickness)
    backWall.Position = Vector3.new(60, GROUND_Y + wallHeight/2, 172)
    backWall.Anchored = true
    backWall.Material = Enum.Material.Cobblestone
    backWall.Color = wallColor
    backWall.Parent = villageFolder

    -- Front wall left (with gate gap)
    local frontWallLeft = Instance.new("Part")
    frontWallLeft.Name = "FrontWallLeft"
    frontWallLeft.Size = Vector3.new(50, wallHeight, wallThickness)
    frontWallLeft.Position = Vector3.new(22, GROUND_Y + wallHeight/2, 8)
    frontWallLeft.Anchored = true
    frontWallLeft.Material = Enum.Material.Cobblestone
    frontWallLeft.Color = wallColor
    frontWallLeft.Parent = villageFolder

    -- Front wall right (with gate gap)
    local frontWallRight = Instance.new("Part")
    frontWallRight.Name = "FrontWallRight"
    frontWallRight.Size = Vector3.new(50, wallHeight, wallThickness)
    frontWallRight.Position = Vector3.new(98, GROUND_Y + wallHeight/2, 8)
    frontWallRight.Anchored = true
    frontWallRight.Material = Enum.Material.Cobblestone
    frontWallRight.Color = wallColor
    frontWallRight.Parent = villageFolder

    -- Wall battlements (decorative top)
    for _, wall in {leftWall, rightWall, backWall, frontWallLeft, frontWallRight} do
        local battlement = Instance.new("Part")
        battlement.Name = "Battlement"
        battlement.Size = Vector3.new(wall.Size.X + 0.5, 1.5, wall.Size.Z + 0.5)
        battlement.Position = wall.Position + Vector3.new(0, wallHeight/2 + 0.75, 0)
        battlement.Anchored = true
        battlement.Material = Enum.Material.Cobblestone
        battlement.Color = Color3.fromRGB(65, 60, 55)
        battlement.Parent = villageFolder
    end

    -- Invisible barriers above walls to prevent jump exploits
    local barrierHeight = 50
    for _, wall in {leftWall, rightWall, backWall, frontWallLeft, frontWallRight} do
        local barrier = Instance.new("Part")
        barrier.Name = wall.Name .. "_Barrier"
        barrier.Size = Vector3.new(wall.Size.X, barrierHeight, wall.Size.Z)
        barrier.Position = wall.Position + Vector3.new(0, wallHeight/2 + barrierHeight/2, 0)
        barrier.Anchored = true
        barrier.Transparency = 1
        barrier.CanCollide = true
        barrier.Parent = villageFolder
    end
    -- Gate ceiling barrier (above the opening between towers)
    local gateCeiling = Instance.new("Part")
    gateCeiling.Name = "GateCeilingBarrier"
    gateCeiling.Size = Vector3.new(26, barrierHeight, wallThickness)
    gateCeiling.Position = Vector3.new(60, GROUND_Y + wallHeight + barrierHeight/2, 8)
    gateCeiling.Anchored = true
    gateCeiling.Transparency = 1
    gateCeiling.CanCollide = true
    gateCeiling.Parent = villageFolder

    -- Corner barrier pillars (fill any seam gaps at wall intersections)
    local corners = {
        Vector3.new(-5, GROUND_Y + 25, 8),
        Vector3.new(125, GROUND_Y + 25, 8),
        Vector3.new(-5, GROUND_Y + 25, 172),
        Vector3.new(125, GROUND_Y + 25, 172),
    }
    for _, pos in corners do
        local corner = Instance.new("Part")
        corner.Name = "CornerBarrier"
        corner.Size = Vector3.new(5, 50, 5)
        corner.Position = pos
        corner.Anchored = true
        corner.Transparency = 1
        corner.CanCollide = true
        corner.Parent = villageFolder
    end

    -- Wall torch brackets (along walls every ~25 studs)
    local wallTorchPositions = {
        -- Left wall torches (facing inward, +X direction)
        {pos = Vector3.new(-3.5, GROUND_Y + 5, 30), face = "right"},
        {pos = Vector3.new(-3.5, GROUND_Y + 5, 60), face = "right"},
        {pos = Vector3.new(-3.5, GROUND_Y + 5, 90), face = "right"},
        {pos = Vector3.new(-3.5, GROUND_Y + 5, 120), face = "right"},
        {pos = Vector3.new(-3.5, GROUND_Y + 5, 150), face = "right"},
        -- Right wall torches (facing inward, -X direction)
        {pos = Vector3.new(123.5, GROUND_Y + 5, 30), face = "left"},
        {pos = Vector3.new(123.5, GROUND_Y + 5, 60), face = "left"},
        {pos = Vector3.new(123.5, GROUND_Y + 5, 90), face = "left"},
        {pos = Vector3.new(123.5, GROUND_Y + 5, 120), face = "left"},
        {pos = Vector3.new(123.5, GROUND_Y + 5, 150), face = "left"},
        -- Back wall torches
        {pos = Vector3.new(30, GROUND_Y + 5, 170.5), face = "front"},
        {pos = Vector3.new(60, GROUND_Y + 5, 170.5), face = "front"},
        {pos = Vector3.new(90, GROUND_Y + 5, 170.5), face = "front"},
    }
    for i, wt in wallTorchPositions do
        -- Metal bracket (L-shaped mount)
        local bracket = Instance.new("Part")
        bracket.Name = "WallBracket" .. i
        bracket.Size = Vector3.new(0.3, 0.3, 0.8)
        bracket.Position = wt.pos
        bracket.Anchored = true
        bracket.Material = Enum.Material.Metal
        bracket.Color = Color3.fromRGB(50, 45, 40)
        bracket.CanCollide = false
        bracket.Parent = villageFolder

        createTorch(villageFolder, wt.pos + Vector3.new(0, 0.3, 0))
    end

    -- Path edge stones (small stone borders along main path)
    for z = 15, 165, 5 do
        for _, xOff in {-6.5, 6.5} do
            local edgeStone = Instance.new("Part")
            edgeStone.Name = "PathEdge"
            edgeStone.Size = Vector3.new(0.6, 0.3, 1.5)
            edgeStone.Position = Vector3.new(60 + xOff, GROUND_Y + 0.15, z)
            edgeStone.Anchored = true
            edgeStone.Material = Enum.Material.Cobblestone
            edgeStone.Color = Color3.fromRGB(80, 75, 70)
            edgeStone.CanCollide = false
            edgeStone.Parent = villageFolder
        end
    end

    print("  ✓ Ground, paths, and village walls created")
end

-- ============================================================================
-- ENTRANCE GATE
-- ============================================================================

local function createEntranceGate()
    print("[2/8] Creating entrance gate...")

    local gateModel = Instance.new("Model")
    gateModel.Name = "EntranceGate"

    -- Left tower (larger, grander entrance)
    local leftTower = Instance.new("Part")
    leftTower.Size = Vector3.new(8, 20, 8)
    leftTower.Position = Vector3.new(45, GROUND_Y + 10, 8)
    leftTower.Anchored = true
    leftTower.Material = Enum.Material.Cobblestone
    leftTower.Color = Color3.fromRGB(80, 75, 70)
    leftTower.Parent = gateModel

    -- Right tower
    local rightTower = Instance.new("Part")
    rightTower.Size = Vector3.new(8, 20, 8)
    rightTower.Position = Vector3.new(75, GROUND_Y + 10, 8)
    rightTower.Anchored = true
    rightTower.Material = Enum.Material.Cobblestone
    rightTower.Color = Color3.fromRGB(80, 75, 70)
    rightTower.Parent = gateModel

    -- Tower tops (conical shapes using SpecialMesh)
    for _, tower in {leftTower, rightTower} do
        local top = Instance.new("Part")
        top.Name = "TowerTop"
        top.Size = Vector3.new(10, 8, 10)
        top.Position = tower.Position + Vector3.new(0, 14, 0)
        top.Anchored = true
        top.Material = Enum.Material.Slate
        top.Color = Color3.fromRGB(60, 55, 50)
        top.Parent = gateModel

        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.Sphere
        mesh.Scale = Vector3.new(1, 1.5, 1)
        mesh.Parent = top

        -- Flag pole on tower top
        local flagPole = Instance.new("Part")
        flagPole.Name = "FlagPole"
        flagPole.Size = Vector3.new(0.3, 6, 0.3)
        flagPole.Position = tower.Position + Vector3.new(0, 22, 0)
        flagPole.Anchored = true
        flagPole.Material = Enum.Material.Metal
        flagPole.Color = Color3.fromRGB(60, 55, 50)
        flagPole.CanCollide = false
        flagPole.Parent = gateModel

        -- Banner/flag
        local banner = Instance.new("Part")
        banner.Name = "Banner"
        banner.Size = Vector3.new(0.1, 3, 2)
        banner.Position = tower.Position + Vector3.new(0, 23, 1.5)
        banner.Anchored = true
        banner.Material = Enum.Material.Fabric
        banner.Color = Color3.fromRGB(180, 30, 30)
        banner.CanCollide = false
        banner.Parent = gateModel
    end

    -- Arch connecting towers
    local arch = Instance.new("Part")
    arch.Size = Vector3.new(38, 5, 8)
    arch.Position = Vector3.new(60, GROUND_Y + 18, 8)
    arch.Anchored = true
    arch.Material = Enum.Material.Cobblestone
    arch.Color = Color3.fromRGB(70, 65, 60)
    arch.Parent = gateModel

    -- Welcome sign
    createSign(gateModel, "BATTLE TYCOON", Vector3.new(60, GROUND_Y + 14, 12), Vector3.new(14, 3.5, 0.5))

    -- Subtitle
    createSign(gateModel, "~ CONQUEST ~", Vector3.new(60, GROUND_Y + 10.5, 12), Vector3.new(10, 2, 0.3))

    -- Torches on towers
    createTorch(gateModel, Vector3.new(45, GROUND_Y + 21, 12))
    createTorch(gateModel, Vector3.new(75, GROUND_Y + 21, 12))
    createTorch(gateModel, Vector3.new(52, GROUND_Y + 8, 12))
    createTorch(gateModel, Vector3.new(68, GROUND_Y + 8, 12))

    -- Portcullis (iron gate bars in gate opening)
    for i = 0, 5 do
        local bar = Instance.new("Part")
        bar.Name = "PortcullisBar" .. i
        bar.Size = Vector3.new(0.4, 14, 0.4)
        bar.Position = Vector3.new(49 + i * 4.4, GROUND_Y + 7, 8)
        bar.Anchored = true
        bar.Material = Enum.Material.Metal
        bar.Color = Color3.fromRGB(45, 42, 38)
        bar.CanCollide = false
        bar.Transparency = 0.3
        bar.Parent = gateModel
    end
    -- Horizontal portcullis bars
    for i = 0, 2 do
        local hbar = Instance.new("Part")
        hbar.Name = "PortcullisHBar" .. i
        hbar.Size = Vector3.new(26, 0.4, 0.4)
        hbar.Position = Vector3.new(60, GROUND_Y + 4 + i * 5, 8)
        hbar.Anchored = true
        hbar.Material = Enum.Material.Metal
        hbar.Color = Color3.fromRGB(45, 42, 38)
        hbar.CanCollide = false
        hbar.Transparency = 0.3
        hbar.Parent = gateModel
    end

    -- Arrow slits on tower faces (narrow dark openings)
    for _, tower in {leftTower, rightTower} do
        for _, yOff in {5, 10, 15} do
            local slit = Instance.new("Part")
            slit.Name = "ArrowSlit"
            slit.Size = Vector3.new(0.3, 2.5, 0.6)
            slit.Position = tower.Position + Vector3.new(0, yOff - 10, -4.1)
            slit.Anchored = true
            slit.Material = Enum.Material.Slate
            slit.Color = Color3.fromRGB(15, 12, 10)
            slit.CanCollide = false
            slit.Parent = gateModel
        end
    end

    -- Guard armor stands flanking entrance
    for _, xPos in {52, 68} do
        -- Armor stand base
        local armorBase = Instance.new("Part")
        armorBase.Name = "ArmorStand"
        armorBase.Size = Vector3.new(1.5, 0.5, 1.5)
        armorBase.Position = Vector3.new(xPos, GROUND_Y + 0.25, 12)
        armorBase.Anchored = true
        armorBase.Material = Enum.Material.Wood
        armorBase.Color = Color3.fromRGB(60, 40, 25)
        armorBase.CanCollide = false
        armorBase.Parent = gateModel

        -- Armor body (chest piece)
        local armorBody = Instance.new("Part")
        armorBody.Name = "ArmorBody"
        armorBody.Size = Vector3.new(1.2, 2, 0.8)
        armorBody.Position = Vector3.new(xPos, GROUND_Y + 2, 12)
        armorBody.Anchored = true
        armorBody.Material = Enum.Material.Metal
        armorBody.Color = Color3.fromRGB(120, 115, 110)
        armorBody.CanCollide = false
        armorBody.Parent = gateModel

        -- Helmet
        local helmet = Instance.new("Part")
        helmet.Name = "Helmet"
        helmet.Shape = Enum.PartType.Ball
        helmet.Size = Vector3.new(1, 1, 1)
        helmet.Position = Vector3.new(xPos, GROUND_Y + 3.5, 12)
        helmet.Anchored = true
        helmet.Material = Enum.Material.Metal
        helmet.Color = Color3.fromRGB(120, 115, 110)
        helmet.CanCollide = false
        helmet.Parent = gateModel

        -- Shield
        local shield = Instance.new("Part")
        shield.Name = "Shield"
        shield.Size = Vector3.new(0.15, 1.8, 1.2)
        shield.Position = Vector3.new(xPos - 0.8, GROUND_Y + 2, 12)
        shield.Anchored = true
        shield.Material = Enum.Material.Metal
        shield.Color = Color3.fromRGB(80, 30, 30)
        shield.CanCollide = false
        shield.Parent = gateModel

        -- Sword (on other side)
        local sword = Instance.new("Part")
        sword.Name = "Sword"
        sword.Size = Vector3.new(0.15, 3, 0.3)
        sword.Position = Vector3.new(xPos + 0.8, GROUND_Y + 2.5, 12)
        sword.Anchored = true
        sword.Material = Enum.Material.Metal
        sword.Color = Color3.fromRGB(170, 170, 175)
        sword.CanCollide = false
        sword.Parent = gateModel
    end

    gateModel.Parent = villageFolder
    print("  ✓ Entrance gate created")
end

-- ============================================================================
-- VILLAGE RESOURCE BOARD (visible to visitors near entrance)
-- Shows the village owner's current resource totals on a sign by the gate
-- ============================================================================

local _resourceBoardGui: SurfaceGui? = nil

local function createResourceBoard()
    local board = Instance.new("Part")
    board.Name = "ResourceBoard"
    board.Size = Vector3.new(6, 4, 0.5)
    board.Position = Vector3.new(42, GROUND_Y + 4, 14) -- Left side of gate entrance
    board.Anchored = true
    board.Material = Enum.Material.Wood
    board.Color = Color3.fromRGB(50, 35, 20)
    board.Parent = villageFolder

    -- Post to hold the sign
    local post = Instance.new("Part")
    post.Name = "BoardPost"
    post.Size = Vector3.new(0.5, 6, 0.5)
    post.Position = Vector3.new(42, GROUND_Y + 3, 14)
    post.Anchored = true
    post.Material = Enum.Material.Wood
    post.Color = Color3.fromRGB(60, 40, 25)
    post.Parent = villageFolder

    -- SurfaceGui on the front face
    local gui = Instance.new("SurfaceGui")
    gui.Name = "ResourceDisplay"
    gui.Face = Enum.NormalId.Front
    gui.CanvasSize = Vector2.new(400, 280)
    gui.Parent = board

    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 50)
    title.Position = UDim2.new(0, 0, 0, 5)
    title.BackgroundTransparency = 1
    title.Text = "Village Resources"
    title.TextColor3 = Color3.fromRGB(255, 215, 0)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 36
    title.Parent = gui

    -- Gold row
    local goldLabel = Instance.new("TextLabel")
    goldLabel.Name = "GoldLabel"
    goldLabel.Size = UDim2.new(1, 0, 0, 45)
    goldLabel.Position = UDim2.new(0, 0, 0, 60)
    goldLabel.BackgroundTransparency = 1
    goldLabel.Text = "Gold: ---"
    goldLabel.TextColor3 = Color3.fromRGB(255, 215, 50)
    goldLabel.Font = Enum.Font.GothamBold
    goldLabel.TextSize = 32
    goldLabel.Parent = gui

    -- Wood row
    local woodLabel = Instance.new("TextLabel")
    woodLabel.Name = "WoodLabel"
    woodLabel.Size = UDim2.new(1, 0, 0, 45)
    woodLabel.Position = UDim2.new(0, 0, 0, 115)
    woodLabel.BackgroundTransparency = 1
    woodLabel.Text = "Wood: ---"
    woodLabel.TextColor3 = Color3.fromRGB(160, 120, 60)
    woodLabel.Font = Enum.Font.GothamBold
    woodLabel.TextSize = 32
    woodLabel.Parent = gui

    -- Food row
    local foodLabel = Instance.new("TextLabel")
    foodLabel.Name = "FoodLabel"
    foodLabel.Size = UDim2.new(1, 0, 0, 45)
    foodLabel.Position = UDim2.new(0, 0, 0, 170)
    foodLabel.BackgroundTransparency = 1
    foodLabel.Text = "Food: ---"
    foodLabel.TextColor3 = Color3.fromRGB(80, 200, 80)
    foodLabel.Font = Enum.Font.GothamBold
    foodLabel.TextSize = 32
    foodLabel.Parent = gui

    -- Owner name label
    local ownerLabel = Instance.new("TextLabel")
    ownerLabel.Name = "OwnerLabel"
    ownerLabel.Size = UDim2.new(1, 0, 0, 35)
    ownerLabel.Position = UDim2.new(0, 0, 0, 230)
    ownerLabel.BackgroundTransparency = 1
    ownerLabel.Text = ""
    ownerLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    ownerLabel.Font = Enum.Font.Gotham
    ownerLabel.TextSize = 22
    ownerLabel.Parent = gui

    -- Also add a gui on the back face
    local guiBack = gui:Clone()
    guiBack.Face = Enum.NormalId.Back
    guiBack.Parent = board

    _resourceBoardGui = gui

    print("  ✓ Resource board created at entrance")
end

-- Update the resource board with current owner resources
local function updateResourceBoard()
    if not _resourceBoardGui then return end
    if not _villageOwnerUserId then return end
    if not DataService then return end

    local ownerPlayer = Players:GetPlayerByUserId(_villageOwnerUserId)
    if not ownerPlayer then return end

    local playerData = DataService:GetPlayerData(ownerPlayer)
    if not playerData or not playerData.resources then return end

    local gold = playerData.resources.gold or 0
    local wood = playerData.resources.wood or 0
    local food = playerData.resources.food or 0

    -- Format numbers with commas
    local function formatNum(n: number): string
        local s = tostring(math.floor(n))
        local result = ""
        for i = #s, 1, -1 do
            result = s:sub(i, i) .. result
            if (#s - i + 1) % 3 == 0 and i > 1 then
                result = "," .. result
            end
        end
        return result
    end

    -- Update all SurfaceGuis on the board
    local board = villageFolder and villageFolder:FindFirstChild("ResourceBoard")
    if board then
        for _, child in board:GetChildren() do
            if child:IsA("SurfaceGui") then
                local gLabel = child:FindFirstChild("GoldLabel") :: TextLabel?
                local wLabel = child:FindFirstChild("WoodLabel") :: TextLabel?
                local fLabel = child:FindFirstChild("FoodLabel") :: TextLabel?
                local oLabel = child:FindFirstChild("OwnerLabel") :: TextLabel?
                if gLabel then gLabel.Text = "Gold: " .. formatNum(gold) end
                if wLabel then wLabel.Text = "Wood: " .. formatNum(wood) end
                if fLabel then fLabel.Text = "Food: " .. formatNum(food) end
                if oLabel then oLabel.Text = ownerPlayer.Name .. "'s Village" end
            end
        end
    end
end

-- Start periodic updates for the resource board (every 5 seconds)
task.spawn(function()
    task.wait(5) -- Wait for village to be set up
    while true do
        updateResourceBoard()
        task.wait(5)
    end
end)

-- ============================================================================
-- NPC WORKER SYSTEM
-- Creates visible R15 humanoid workers that walk between stations
-- Falls back to box-part NPCs if R15 creation fails
-- ============================================================================

-- Fallback: Create a simple box-part NPC worker model (legacy style)
local function createFallbackNPC(name, position, color)
    local npc = Instance.new("Model")
    npc.Name = name

    -- Body (torso)
    local torso = Instance.new("Part")
    torso.Name = "Torso"
    torso.Size = Vector3.new(1.5, 2, 1)
    torso.Position = position + Vector3.new(0, 3, 0)
    torso.Anchored = true
    torso.CanCollide = false
    torso.Material = Enum.Material.SmoothPlastic
    torso.Color = color or Color3.fromRGB(100, 80, 60)
    torso.Parent = npc

    -- Head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Shape = Enum.PartType.Ball
    head.Size = Vector3.new(1.2, 1.2, 1.2)
    head.Position = position + Vector3.new(0, 4.5, 0)
    head.Anchored = true
    head.CanCollide = false
    head.Material = Enum.Material.SmoothPlastic
    head.Color = Color3.fromRGB(255, 205, 170)
    head.Parent = npc

    -- Left arm
    local leftArm = Instance.new("Part")
    leftArm.Name = "LeftArm"
    leftArm.Size = Vector3.new(0.5, 1.8, 0.5)
    leftArm.Position = position + Vector3.new(-1, 3, 0)
    leftArm.Anchored = true
    leftArm.CanCollide = false
    leftArm.Material = Enum.Material.SmoothPlastic
    leftArm.Color = color or Color3.fromRGB(100, 80, 60)
    leftArm.Parent = npc

    -- Right arm
    local rightArm = Instance.new("Part")
    rightArm.Name = "RightArm"
    rightArm.Size = Vector3.new(0.5, 1.8, 0.5)
    rightArm.Position = position + Vector3.new(1, 3, 0)
    rightArm.Anchored = true
    rightArm.CanCollide = false
    rightArm.Material = Enum.Material.SmoothPlastic
    rightArm.Color = color or Color3.fromRGB(100, 80, 60)
    rightArm.Parent = npc

    -- Left leg
    local leftLeg = Instance.new("Part")
    leftLeg.Name = "LeftLeg"
    leftLeg.Size = Vector3.new(0.6, 2, 0.6)
    leftLeg.Position = position + Vector3.new(-0.4, 1, 0)
    leftLeg.Anchored = true
    leftLeg.CanCollide = false
    leftLeg.Material = Enum.Material.SmoothPlastic
    leftLeg.Color = Color3.fromRGB(60, 50, 40)
    leftLeg.Parent = npc

    -- Right leg
    local rightLeg = Instance.new("Part")
    rightLeg.Name = "RightLeg"
    rightLeg.Size = Vector3.new(0.6, 2, 0.6)
    rightLeg.Position = position + Vector3.new(0.4, 1, 0)
    rightLeg.Anchored = true
    rightLeg.CanCollide = false
    rightLeg.Material = Enum.Material.SmoothPlastic
    rightLeg.Color = Color3.fromRGB(60, 50, 40)
    rightLeg.Parent = npc

    -- Name tag with status
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "StatusBillboard"
    billboard.Size = UDim2.new(5, 0, 1.5, 0)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = head

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = name
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextStrokeTransparency = 0.5
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(1, 0, 0.5, 0)
    statusLabel.Position = UDim2.new(0, 0, 0.5, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Idle"
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    statusLabel.TextStrokeTransparency = 0.5
    statusLabel.TextScaled = true
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.Parent = billboard

    npc.PrimaryPart = torso
    return npc
end

-- Fallback: Move all parts of a legacy box NPC to a new position
local function moveNPCLegacy(npc, newPosition)
    local torso = npc:FindFirstChild("Torso")
    if not torso then return end

    local offset = newPosition - (torso.Position - Vector3.new(0, 3, 0))

    local function moveParts(parent)
        for _, child in parent:GetChildren() do
            if child:IsA("BasePart") then
                child.Position = child.Position + offset
            elseif child:IsA("Model") then
                moveParts(child)
            end
        end
    end

    moveParts(npc)
end

-- Fallback: Animate legacy box NPC walking to a destination
local function walkNPCToLegacy(npc, destination, speed, callback)
    local torso = npc:FindFirstChild("Torso")
    if not torso then return end

    local startPos = torso.Position - Vector3.new(0, 3, 0)
    local endPos = Vector3.new(destination.X, startPos.Y, destination.Z)
    local distance = (endPos - startPos).Magnitude
    local duration = distance / (speed or 8)

    local elapsed = 0
    local walkConnection
    local legPhase = 0

    walkConnection = RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        local alpha = math.min(elapsed / duration, 1)

        local currentPos = startPos:Lerp(endPos, alpha)
        moveNPCLegacy(npc, currentPos)

        legPhase = legPhase + dt * 10
        local leftLeg = npc:FindFirstChild("LeftLeg")
        local rightLeg = npc:FindFirstChild("RightLeg")
        local leftArm = npc:FindFirstChild("LeftArm")
        local rightArm = npc:FindFirstChild("RightArm")

        if leftLeg and rightLeg then
            local legSwing = math.sin(legPhase) * 0.5
            leftLeg.Position = currentPos + Vector3.new(-0.4, 1, legSwing)
            rightLeg.Position = currentPos + Vector3.new(0.4, 1, -legSwing)
        end
        if leftArm and rightArm then
            local armSwing = math.sin(legPhase) * 0.3
            leftArm.Position = currentPos + Vector3.new(-1, 3, -armSwing)
            rightArm.Position = currentPos + Vector3.new(1, 3, armSwing)
        end

        if alpha >= 1 then
            walkConnection:Disconnect()
            if leftLeg then leftLeg.Position = currentPos + Vector3.new(-0.4, 1, 0) end
            if rightLeg then rightLeg.Position = currentPos + Vector3.new(0.4, 1, 0) end
            if leftArm then leftArm.Position = currentPos + Vector3.new(-1, 3, 0) end
            if rightArm then rightArm.Position = currentPos + Vector3.new(1, 3, 0) end
            if callback then callback() end
        end
    end)

    return walkConnection
end

-- Worker appearance definitions for R15 humanoid NPCs
local WorkerAppearances = {
    Miner = {
        torsoColor = Color3.fromRGB(139, 90, 43),
        legColor = Color3.fromRGB(80, 60, 40),
        headColor = Color3.fromRGB(255, 205, 170),
        heightScale = 0.9,
        widthScale = 1.05,
    },
    Collector = {
        torsoColor = Color3.fromRGB(60, 100, 60),
        legColor = Color3.fromRGB(50, 50, 40),
        headColor = Color3.fromRGB(255, 205, 170),
        heightScale = 1.0,
        widthScale = 1.0,
    },
    Logger = {
        torsoColor = Color3.fromRGB(180, 50, 50),
        legColor = Color3.fromRGB(50, 70, 100),
        headColor = Color3.fromRGB(255, 205, 170),
        heightScale = 1.05,
        widthScale = 1.1,
    },
    Hauler = {
        torsoColor = Color3.fromRGB(60, 100, 60),
        legColor = Color3.fromRGB(60, 50, 40),
        headColor = Color3.fromRGB(255, 205, 170),
        heightScale = 1.0,
        widthScale = 1.1,
    },
    Farmer = {
        torsoColor = Color3.fromRGB(100, 140, 100),
        legColor = Color3.fromRGB(100, 140, 100),
        headColor = Color3.fromRGB(255, 205, 170),
        heightScale = 1.0,
        widthScale = 1.0,
    },
    Carrier = {
        torsoColor = Color3.fromRGB(60, 100, 60),
        legColor = Color3.fromRGB(60, 50, 40),
        headColor = Color3.fromRGB(255, 205, 170),
        heightScale = 1.0,
        widthScale = 1.05,
    },
}

-- Add role-specific Part-based accessories to an R15 NPC
local function addWorkerAccessories(npc, workerType)
    if not workerType then return end

    -- Helper to create a Part welded to a body part
    local function weldAccessory(parent, props, offset)
        local part = Instance.new("Part")
        part.Name = props.name or "Accessory"
        part.Size = props.size or Vector3.new(0.5, 0.5, 0.5)
        part.Anchored = false
        part.CanCollide = false
        part.Material = props.material or Enum.Material.SmoothPlastic
        part.Color = props.color or Color3.new(1, 1, 1)
        if props.shape then
            part.Shape = props.shape
        end
        part.Parent = npc

        local weld = Instance.new("Weld")
        weld.Part0 = parent
        weld.Part1 = part
        weld.C0 = offset
        weld.Parent = part

        return part
    end

    local head = npc:FindFirstChild("Head")
    local upperTorso = npc:FindFirstChild("UpperTorso")
    local rightHand = npc:FindFirstChild("RightHand") or npc:FindFirstChild("RightLowerArm")

    if workerType == "Miner" then
        -- Hard hat (yellow cylinder on head)
        if head then
            local hat = weldAccessory(head, {
                name = "HardHat",
                size = Vector3.new(1.1, 0.4, 1.1),
                shape = Enum.PartType.Cylinder,
                material = Enum.Material.SmoothPlastic,
                color = Color3.fromRGB(255, 210, 50),
            }, CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)))

            -- Headlamp on hat
            weldAccessory(hat, {
                name = "Headlamp",
                size = Vector3.new(0.2, 0.2, 0.2),
                material = Enum.Material.Neon,
                color = Color3.fromRGB(255, 255, 200),
            }, CFrame.new(0, 0, -0.5))
        end

        -- Pickaxe welded to right hand
        if rightHand then
            local handle = weldAccessory(rightHand, {
                name = "PickaxeHandle",
                size = Vector3.new(0.15, 1.6, 0.15),
                material = Enum.Material.Wood,
                color = Color3.fromRGB(100, 70, 45),
            }, CFrame.new(0, -0.8, 0))

            weldAccessory(handle, {
                name = "PickaxeHead",
                size = Vector3.new(0.7, 0.25, 0.15),
                material = Enum.Material.Metal,
                color = Color3.fromRGB(140, 140, 150),
            }, CFrame.new(0.35, -0.7, 0))
        end

    elseif workerType == "Collector" then
        -- Cloth cap (brown flat part on head)
        if head then
            weldAccessory(head, {
                name = "ClothCap",
                size = Vector3.new(1.0, 0.2, 1.1),
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(120, 80, 50),
            }, CFrame.new(0, 0.5, -0.1))
        end

        -- Leather apron on torso
        if upperTorso then
            weldAccessory(upperTorso, {
                name = "Apron",
                size = Vector3.new(0.9, 1.2, 0.15),
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(120, 80, 50),
            }, CFrame.new(0, -0.2, -0.55))
        end

    elseif workerType == "Logger" then
        -- Knit beanie (red cylinder on head)
        if head then
            weldAccessory(head, {
                name = "Beanie",
                size = Vector3.new(0.9, 0.5, 0.9),
                shape = Enum.PartType.Cylinder,
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(180, 40, 40),
            }, CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)))
        end

        -- Axe welded to right hand
        if rightHand then
            local axeHandle = weldAccessory(rightHand, {
                name = "AxeHandle",
                size = Vector3.new(0.15, 1.8, 0.15),
                material = Enum.Material.Wood,
                color = Color3.fromRGB(100, 70, 45),
            }, CFrame.new(0, -0.9, 0))

            weldAccessory(axeHandle, {
                name = "AxeHead",
                size = Vector3.new(0.5, 0.6, 0.15),
                material = Enum.Material.Metal,
                color = Color3.fromRGB(160, 160, 170),
            }, CFrame.new(0.25, -0.8, 0))
        end

    elseif workerType == "Hauler" then
        -- Bandana (dark green wedge on head)
        if head then
            weldAccessory(head, {
                name = "Bandana",
                size = Vector3.new(1.0, 0.3, 1.0),
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(40, 80, 40),
            }, CFrame.new(0, 0.45, 0))
        end

        -- Shoulder strap across torso
        if upperTorso then
            weldAccessory(upperTorso, {
                name = "ShoulderStrap",
                size = Vector3.new(0.2, 1.6, 0.1),
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(100, 70, 40),
            }, CFrame.new(-0.2, 0, -0.4) * CFrame.Angles(0, 0, math.rad(30)))
        end

    elseif workerType == "Farmer" then
        -- Straw hat (wide brim: cylinder + disc)
        if head then
            -- Hat crown
            weldAccessory(head, {
                name = "StrawHatCrown",
                size = Vector3.new(0.9, 0.4, 0.9),
                shape = Enum.PartType.Cylinder,
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(230, 210, 140),
            }, CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)))

            -- Hat brim
            weldAccessory(head, {
                name = "StrawHatBrim",
                size = Vector3.new(1.6, 0.08, 1.6),
                shape = Enum.PartType.Cylinder,
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(230, 210, 140),
            }, CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0, math.rad(90)))
        end

        -- Seed pouch on hip
        if upperTorso then
            weldAccessory(upperTorso, {
                name = "SeedPouch",
                size = Vector3.new(0.4, 0.5, 0.3),
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(180, 150, 100),
            }, CFrame.new(0.55, -0.5, 0))
        end

    elseif workerType == "Carrier" then
        -- Flat cap (green part on head)
        if head then
            weldAccessory(head, {
                name = "FlatCap",
                size = Vector3.new(1.0, 0.2, 1.1),
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(60, 90, 60),
            }, CFrame.new(0, 0.5, -0.1))
        end

        -- Backpack frame (brown parts on back)
        if upperTorso then
            -- Main frame
            weldAccessory(upperTorso, {
                name = "BackpackFrame",
                size = Vector3.new(0.8, 1.2, 0.15),
                material = Enum.Material.Wood,
                color = Color3.fromRGB(100, 70, 40),
            }, CFrame.new(0, 0, 0.5))

            -- Side struts
            weldAccessory(upperTorso, {
                name = "BackpackStrut1",
                size = Vector3.new(0.1, 1.0, 0.1),
                material = Enum.Material.Wood,
                color = Color3.fromRGB(100, 70, 40),
            }, CFrame.new(-0.35, 0, 0.55))
            weldAccessory(upperTorso, {
                name = "BackpackStrut2",
                size = Vector3.new(0.1, 1.0, 0.1),
                material = Enum.Material.Wood,
                color = Color3.fromRGB(100, 70, 40),
            }, CFrame.new(0.35, 0, 0.55))
        end
    end
end

-- R15 animation asset IDs (built-in Roblox animations)
local NPC_ANIMS = {
    idle = "rbxassetid://507766666",
    walk = "rbxassetid://507777826",
}

-- Module-level table to store AnimationTrack references per NPC
-- Keyed by NPC model, value = {idle = AnimationTrack, walk = AnimationTrack}
local _npcAnimTracks = {}

-- Create an R15 humanoid NPC worker, or fall back to box-part NPC
local function createWorkerNPC(name, position, color, workerType)
    -- Look up appearance config for this worker type
    local appearance = workerType and WorkerAppearances[workerType]
    local torsoColor = (appearance and appearance.torsoColor) or color or Color3.fromRGB(100, 80, 60)
    local legColor = (appearance and appearance.legColor) or Color3.fromRGB(60, 50, 40)
    local headColor = (appearance and appearance.headColor) or Color3.fromRGB(255, 205, 170)

    -- Try to create R15 humanoid NPC
    local npc
    local r15Success = false

    local ok, err = pcall(function()
        -- Build HumanoidDescription with body colors and scaling
        local desc = Instance.new("HumanoidDescription")
        desc.HeadColor = headColor
        desc.TorsoColor = torsoColor
        desc.LeftArmColor = torsoColor
        desc.RightArmColor = torsoColor
        desc.LeftLegColor = legColor
        desc.RightLegColor = legColor

        -- Apply per-role scaling
        if appearance then
            desc.HeightScale = appearance.heightScale or 1.0
            desc.WidthScale = appearance.widthScale or 1.0
            desc.DepthScale = appearance.widthScale or 1.0
            desc.HeadScale = 1.0
        end

        -- Create R15 model from description
        npc = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
        npc.Name = name

        -- Clean up the description after use
        desc:Destroy()

        -- Configure humanoid
        local humanoid = npc:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            humanoid.RequiresNeck = false
            humanoid.WalkSpeed = 8
        end

        -- Set all parts non-collidable and ensure body parts are visible
        -- (CreateHumanoidModelFromDescription can leave MeshParts at Transparency=1
        --  because the avatar pipeline normally renders them for player characters,
        --  but server-created NPCs bypass that pipeline)
        -- Only anchor HumanoidRootPart; other parts stay unanchored so Motor6D joints
        -- and the Animator can move them for animations (idle, walk)
        for _, part in npc:GetDescendants() do
            if part:IsA("BasePart") then
                part.CanCollide = false
                if part.Name == "HumanoidRootPart" then
                    part.Transparency = 1 -- Physics root is always invisible
                else
                    part.Transparency = 0 -- Force body parts visible
                end
            end
        end
        local rootPart = npc:FindFirstChild("HumanoidRootPart")
        if rootPart then
            rootPart.Anchored = true
        end

        -- Position the NPC (PivotTo moves ALL parts, not just rootPart,
        -- avoiding Motor6D desync where body parts stay at origin)
        npc:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))

        -- Remove default Animate LocalScript (won't work on server NPCs)
        local animScript = npc:FindFirstChild("Animate")
        if animScript then animScript:Destroy() end

        -- Create Animator and load idle animation
        if humanoid then
            local animator = humanoid:FindFirstChildOfClass("Animator")
            if not animator then
                animator = Instance.new("Animator")
                animator.Parent = humanoid
            end

            local idleAnim = Instance.new("Animation")
            idleAnim.AnimationId = NPC_ANIMS.idle
            local idleTrack = animator:LoadAnimation(idleAnim)
            idleTrack.Looped = true
            idleTrack.Priority = Enum.AnimationPriority.Idle
            idleTrack:Play()
            idleAnim:Destroy()

            -- Store walk animation reference for walkNPCTo
            local walkAnim = Instance.new("Animation")
            walkAnim.AnimationId = NPC_ANIMS.walk
            local walkTrack = animator:LoadAnimation(walkAnim)
            walkTrack.Looped = true
            walkTrack.Priority = Enum.AnimationPriority.Movement
            walkAnim:Destroy()

            -- Store animation tracks in module-level table for walkNPCTo access
            _npcAnimTracks[npc] = {
                idle = idleTrack,
                walk = walkTrack,
            }
        end

        r15Success = true
    end)

    if not r15Success then
        -- Fallback to box-part NPC
        if err then
            warn("[NPC] R15 creation failed for " .. name .. ": " .. tostring(err))
        end
        npc = createFallbackNPC(name, position, color)
        return npc
    end

    -- Add billboard GUI to head
    local head = npc:FindFirstChild("Head")
    if head then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "StatusBillboard"
        billboard.Size = UDim2.new(5, 0, 1.5, 0)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = head

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NameLabel"
        nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
        nameLabel.Position = UDim2.new(0, 0, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = name
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextStrokeTransparency = 0.5
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Parent = billboard

        local statusLabel = Instance.new("TextLabel")
        statusLabel.Name = "StatusLabel"
        statusLabel.Size = UDim2.new(1, 0, 0.5, 0)
        statusLabel.Position = UDim2.new(0, 0, 0.5, 0)
        statusLabel.BackgroundTransparency = 1
        statusLabel.Text = "Idle"
        statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        statusLabel.TextStrokeTransparency = 0.5
        statusLabel.TextScaled = true
        statusLabel.Font = Enum.Font.Gotham
        statusLabel.Parent = billboard
    end

    -- Add worker-type-specific accessories (hats, tools, etc.)
    addWorkerAccessories(npc, workerType)

    return npc
end

-- Update NPC status text
local function setNPCStatus(npc, status)
    local head = npc:FindFirstChild("Head")
    if not head then return end
    local billboard = head:FindFirstChild("StatusBillboard")
    if not billboard then return end
    local statusLabel = billboard:FindFirstChild("StatusLabel")
    if statusLabel then
        statusLabel.Text = status
    end
end

-- Move all parts of an NPC to a new position (including carried items)
local function moveNPC(npc, newPosition)
    -- R15 path: PivotTo moves entire model (avoids Motor6D desync)
    local rootPart = npc:FindFirstChild("HumanoidRootPart")
    if rootPart then
        npc:PivotTo(CFrame.new(newPosition + Vector3.new(0, 3, 0)))
        return
    end

    -- Legacy fallback: move all parts by offset
    moveNPCLegacy(npc, newPosition)
end

-- Animate NPC walking to a destination using PathfindingService waypoints
-- R15 NPCs use pathfinding to navigate around walls, then CFrame lerp along waypoints
-- Legacy box-part NPCs fall back to direct lerp
local function walkNPCTo(npc, destination, speed, callback)
    -- Check if this is an R15 NPC (has HumanoidRootPart)
    local rootPart = npc:FindFirstChild("HumanoidRootPart")

    if rootPart then
        local startPos = rootPart.Position - Vector3.new(0, 3, 0)
        local endPos = Vector3.new(destination.X, startPos.Y, destination.Z)

        -- Build waypoint list using PathfindingService (navigates around walls)
        local waypoints = { endPos } -- fallback: direct path
        local pathOk, pathErr = pcall(function()
            local path = PathfindingService:CreatePath({
                AgentRadius = 2,
                AgentHeight = 5,
                AgentCanJump = false,
            })
            path:ComputeAsync(rootPart.Position, endPos + Vector3.new(0, 3, 0))
            if path.Status == Enum.PathStatus.Success then
                local pts = path:GetWaypoints()
                if #pts > 1 then
                    waypoints = {}
                    for i = 2, #pts do -- skip first waypoint (current position)
                        table.insert(waypoints, Vector3.new(pts[i].Position.X, startPos.Y, pts[i].Position.Z))
                    end
                end
            end
        end)

        if not pathOk then
            -- PathfindingService failed, use direct path (single waypoint)
            waypoints = { endPos }
        end

        -- Start walk animation
        local tracks = _npcAnimTracks[npc]
        if tracks then
            if tracks.walk then tracks.walk:Play() end
            if tracks.idle and tracks.idle.IsPlaying then tracks.idle:Stop() end
        end

        -- Walk through waypoints sequentially via CFrame lerp
        local wpIndex = 1
        local segStart = startPos
        local segEnd = waypoints[1]
        local segDist = (segEnd - segStart).Magnitude
        local segDuration = segDist / math.max(speed or 8, 0.1)
        local segElapsed = 0

        -- Face initial direction (PivotTo moves ALL body parts, not just rootPart)
        local segDir = (segEnd - segStart)
        if segDir.Magnitude > 0.1 then
            npc:PivotTo(CFrame.lookAt(segStart + Vector3.new(0, 3, 0), segEnd + Vector3.new(0, 3, 0)))
        end

        local walkConnection
        walkConnection = RunService.Heartbeat:Connect(function(dt)
            if not npc.Parent then
                walkConnection:Disconnect()
                return
            end

            segElapsed = segElapsed + dt
            local alpha = math.min(segElapsed / math.max(segDuration, 0.01), 1)

            local currentPos = segStart:Lerp(segEnd, alpha)
            local dir = (segEnd - segStart)
            if dir.Magnitude > 0.1 then
                npc:PivotTo(CFrame.lookAt(currentPos + Vector3.new(0, 3, 0), segEnd + Vector3.new(0, 3, 0)))
            else
                npc:PivotTo(CFrame.new(currentPos + Vector3.new(0, 3, 0)))
            end

            if alpha >= 1 then
                -- Move to next waypoint
                wpIndex = wpIndex + 1
                if wpIndex <= #waypoints then
                    segStart = segEnd
                    segEnd = waypoints[wpIndex]
                    segDist = (segEnd - segStart).Magnitude
                    segDuration = segDist / math.max(speed or 8, 0.1)
                    segElapsed = 0

                    -- Face new direction
                    dir = (segEnd - segStart)
                    if dir.Magnitude > 0.1 then
                        npc:PivotTo(CFrame.lookAt(segStart + Vector3.new(0, 3, 0), segEnd + Vector3.new(0, 3, 0)))
                    end
                else
                    -- All waypoints reached
                    walkConnection:Disconnect()
                    if tracks then
                        if tracks.walk then tracks.walk:Stop() end
                        if tracks.idle and not tracks.idle.IsPlaying then tracks.idle:Play() end
                    end
                    if callback then callback() end
                end
            end
        end)

        -- Return a disconnect-able object for API compatibility
        return {
            Disconnect = function()
                if walkConnection then walkConnection:Disconnect() end
                if tracks then
                    if tracks.walk then tracks.walk:Stop() end
                    if tracks.idle and not tracks.idle.IsPlaying then tracks.idle:Play() end
                end
            end
        }
    end

    -- Legacy fallback: box-part NPC with lerp + sinusoidal animation
    return walkNPCToLegacy(npc, destination, speed, callback)
end

-- Add carried item visual to NPC (uses welds so items follow NPC movement)
local function setNPCCarrying(npc, itemType, amount)
    -- Remove existing carried item
    local existingItem = npc:FindFirstChild("CarriedItem")
    if existingItem then existingItem:Destroy() end

    if not itemType or amount <= 0 then return end

    local torso = npc:FindFirstChild("UpperTorso") or npc:FindFirstChild("Torso")
    if not torso then return end

    local carried = Instance.new("Model")
    carried.Name = "CarriedItem"
    carried.Parent = npc

    -- Helper function to create a welded part attached to torso
    local function createWeldedPart(props, offset)
        local part = Instance.new("Part")
        part.Name = props.name or "CarriedPart"
        part.Size = props.size or Vector3.new(1, 1, 1)
        part.Anchored = false
        part.CanCollide = false
        part.Material = props.material or Enum.Material.Plastic
        part.Color = props.color or Color3.new(1, 1, 1)
        if props.shape then
            part.Shape = props.shape
        end
        part.Parent = carried

        -- Create weld to attach to torso
        local weld = Instance.new("Weld")
        weld.Part0 = torso
        weld.Part1 = part
        weld.C0 = offset -- Offset from torso center
        weld.Parent = part

        return part
    end

    if itemType == "ore" then
        -- Sack with ore on back
        local sackHeight = 0.8 + (amount * 0.1)
        createWeldedPart({
            name = "Sack",
            size = Vector3.new(1, sackHeight, 0.8),
            material = Enum.Material.Fabric,
            color = Color3.fromRGB(120, 90, 60)
        }, CFrame.new(0, 0.5, 0.8)) -- Behind torso, slightly up

        -- Ore chunks on top of sack (jagged rock shapes with random orientation)
        for i = 1, math.min(amount, 3) do
            local ore = createWeldedPart({
                name = "Ore" .. i,
                size = Vector3.new(0.3, 0.3, 0.3),
                material = Enum.Material.Slate,
                color = Color3.fromRGB(90 + i * 10, 75 + i * 8, 60 + i * 5)
            }, CFrame.new((i-2) * 0.25, 0.5 + sackHeight/2 + 0.15, 0.8) * CFrame.Angles(math.rad(i * 20), math.rad(i * 45), math.rad(i * 15)))
            if ore then
                local mesh = Instance.new("SpecialMesh")
                mesh.MeshType = Enum.MeshType.Sphere
                mesh.Scale = Vector3.new(0.8 + i * 0.1, 0.7 + i * 0.15, 0.9)
                mesh.Parent = ore
            end
        end
    elseif itemType == "gold" then
        -- Gold bars/ingots stacked on back (with trapezoidal mesh)
        for i = 1, math.min(amount, 3) do
            local bar = createWeldedPart({
                name = "GoldBar" .. i,
                size = Vector3.new(0.6, 0.3, 0.3),
                material = Enum.Material.Metal,
                color = Color3.fromRGB(255, 200, 50)
            }, CFrame.new((i-2) * 0.3, 0.5 + (i-1) * 0.35, 0.7))
            if bar then
                local mesh = Instance.new("SpecialMesh")
                mesh.MeshType = Enum.MeshType.Brick
                mesh.Scale = Vector3.new(1.2, 0.8, 1)
                mesh.Parent = bar
            end
        end
    elseif itemType == "logs" then
        -- Log bundle on back
        local bundleHeight = 0.8 + (amount * 0.15)
        createWeldedPart({
            name = "LogBundle",
            size = Vector3.new(1, bundleHeight, 1.8),
            material = Enum.Material.Wood,
            color = Color3.fromRGB(100, 70, 45)
        }, CFrame.new(0, 0.3, 0.8))

        -- Individual log visuals with end-cap discs
        for i = 1, math.min(amount, 4) do
            local logColor = Color3.fromRGB(85 + i * 8, 55 + i * 5, 35 + i * 3)
            createWeldedPart({
                name = "Log" .. i,
                size = Vector3.new(1.6, 0.35, 0.35),
                shape = Enum.PartType.Cylinder,
                material = Enum.Material.Wood,
                color = logColor
            }, CFrame.new(0, 0.3 + bundleHeight/2 + (i-1) * 0.2, 0.8) * CFrame.Angles(0, math.rad(90), 0))
            -- End-cap disc (lighter cross-section)
            createWeldedPart({
                name = "LogCap" .. i,
                size = Vector3.new(0.05, 0.32, 0.32),
                shape = Enum.PartType.Cylinder,
                material = Enum.Material.Wood,
                color = Color3.fromRGB(170, 145, 100)
            }, CFrame.new(0.8, 0.3 + bundleHeight/2 + (i-1) * 0.2, 0.8) * CFrame.Angles(0, math.rad(90), 0))
        end
    elseif itemType == "planks" then
        -- Plank stack on back
        for i = 1, math.min(amount, 5) do
            createWeldedPart({
                name = "Plank" .. i,
                size = Vector3.new(1.4, 0.15, 0.7),
                material = Enum.Material.Wood,
                color = Color3.fromRGB(200, 170, 120)
            }, CFrame.new(0, 0.2 + (i-1) * 0.18, 0.7))
        end
    elseif itemType == "crops" then
        -- Basket with crops
        local basketHeight = 0.8 + (amount * 0.1)
        createWeldedPart({
            name = "Basket",
            size = Vector3.new(1.2, basketHeight, 1.2),
            material = Enum.Material.WoodPlanks,
            color = Color3.fromRGB(180, 150, 100)
        }, CFrame.new(0, 0.5, 0.8))

        -- Crop visuals on top (wheat-colored with leaf accents)
        for i = 1, math.min(amount, 3) do
            local crop = createWeldedPart({
                name = "Crop" .. i,
                size = Vector3.new(0.4, 0.4, 0.4),
                material = Enum.Material.Grass,
                color = Color3.fromRGB(220, 195, 70)
            }, CFrame.new((i-2) * 0.3, 0.5 + basketHeight/2 + 0.2, 0.8))
            if crop then
                local mesh = Instance.new("SpecialMesh")
                mesh.MeshType = Enum.MeshType.Sphere
                mesh.Scale = Vector3.new(1, 1.2, 1)
                mesh.Parent = crop
            end
            -- Small green leaf poking out
            createWeldedPart({
                name = "CropLeaf" .. i,
                size = Vector3.new(0.15, 0.25, 0.08),
                material = Enum.Material.Grass,
                color = Color3.fromRGB(60, 140, 50)
            }, CFrame.new((i-2) * 0.3 + 0.15, 0.5 + basketHeight/2 + 0.4, 0.8))
        end
    elseif itemType == "grain" then
        -- Grain sacks (round sack shape with rope tie)
        for i = 1, math.min(amount, 3) do
            local sack = createWeldedPart({
                name = "GrainSack" .. i,
                size = Vector3.new(0.6, 0.8, 0.5),
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(210, 190, 150)
            }, CFrame.new((i-2) * 0.35, 0.4 + (i-1) * 0.2, 0.7))
            if sack then
                local mesh = Instance.new("SpecialMesh")
                mesh.MeshType = Enum.MeshType.Sphere
                mesh.Scale = Vector3.new(1, 1.3, 0.9)
                mesh.Parent = sack
            end
            -- Rope tie at top
            createWeldedPart({
                name = "SackRope" .. i,
                size = Vector3.new(0.35, 0.1, 0.35),
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(150, 130, 90)
            }, CFrame.new((i-2) * 0.35, 0.4 + (i-1) * 0.2 + 0.45, 0.7))
        end
    elseif itemType == "food" then
        -- Food crates/baskets
        local crateHeight = 0.8 + (amount * 0.1)
        createWeldedPart({
            name = "FoodCrate",
            size = Vector3.new(1.2, crateHeight, 1),
            material = Enum.Material.WoodPlanks,
            color = Color3.fromRGB(160, 130, 90)
        }, CFrame.new(0, 0.5, 0.8))

        -- Crate lid (slightly offset, looks open)
        createWeldedPart({
            name = "CrateLid",
            size = Vector3.new(1.3, 0.1, 1.1),
            material = Enum.Material.WoodPlanks,
            color = Color3.fromRGB(150, 120, 80)
        }, CFrame.new(0.3, 0.5 + crateHeight/2 + 0.1, 0.8) * CFrame.Angles(0, 0, math.rad(15)))
        -- Food items with varied colors (bread, apple, cheese)
        local foodColors = {
            Color3.fromRGB(210, 180, 120), -- Bread
            Color3.fromRGB(200, 50, 40),   -- Apple
            Color3.fromRGB(240, 210, 80),  -- Cheese
        }
        for i = 1, math.min(amount, 3) do
            createWeldedPart({
                name = "Food" .. i,
                size = Vector3.new(0.35, 0.35, 0.35),
                material = Enum.Material.SmoothPlastic,
                color = foodColors[(i % #foodColors) + 1]
            }, CFrame.new((i-2) * 0.3, 0.5 + crateHeight/2 + 0.2, 0.8))
        end
    end
end

-- ============================================================================
-- GEM SYSTEM - Prospecting and Trophy Case
-- Gems provide city-wide production bonuses when displayed in Town Hall
-- ============================================================================

-- Gem type definitions with colors, boost types, rarity tier, and gold values
local GemTypes = {
    -- Common gems (worth 50-100 gold)
    Quartz = { color = Color3.fromRGB(255, 255, 255), boost = "production", rarity = "Common", minValue = 50, maxValue = 100 },
    Amethyst = { color = Color3.fromRGB(153, 102, 204), boost = "speed", rarity = "Common", minValue = 50, maxValue = 100 },
    -- Uncommon gems (worth 200-500 gold)
    Topaz = { color = Color3.fromRGB(255, 200, 50), boost = "production", rarity = "Uncommon", minValue = 200, maxValue = 500 },
    Emerald = { color = Color3.fromRGB(0, 201, 87), boost = "speed", rarity = "Uncommon", minValue = 200, maxValue = 500 },
    -- Rare gems (worth 1,000-2,500 gold)
    Sapphire = { color = Color3.fromRGB(15, 82, 186), boost = "defense", rarity = "Rare", minValue = 1000, maxValue = 2500 },
    Ruby = { color = Color3.fromRGB(220, 20, 60), boost = "production", rarity = "Rare", minValue = 1000, maxValue = 2500 },
    -- Epic gems (worth 5,000-10,000 gold)
    Diamond = { color = Color3.fromRGB(185, 242, 255), boost = "all", rarity = "Epic", minValue = 5000, maxValue = 10000 },
    -- Legendary gems (worth 25,000-50,000 gold)
    StarRuby = { color = Color3.fromRGB(255, 50, 100), boost = "all", rarity = "Legendary", minValue = 25000, maxValue = 50000 },
    BlackDiamond = { color = Color3.fromRGB(30, 30, 40), boost = "all", rarity = "Legendary", minValue = 25000, maxValue = 50000 },
}

-- Gem size multipliers (affects bonus, not value)
local GemSizes = {
    Chip = { multiplier = 1.05, rarity = 0.50 },   -- 50% of successful prospects
    Stone = { multiplier = 1.10, rarity = 0.30 },  -- 30% of successful prospects
    Gem = { multiplier = 1.20, rarity = 0.15 },    -- 15% of successful prospects
    Jewel = { multiplier = 1.35, rarity = 0.05 },  -- 5% of successful prospects
}

-- Gem lists by rarity tier
local GemsByRarity = {
    Common = { "Quartz", "Amethyst" },
    Uncommon = { "Topaz", "Emerald" },
    Rare = { "Sapphire", "Ruby" },
    Epic = { "Diamond" },
    Legendary = { "StarRuby", "BlackDiamond" },
}

-- Rarity tier colors for UI
local RarityColors = {
    Common = Color3.fromRGB(180, 180, 180),
    Uncommon = Color3.fromRGB(30, 200, 30),
    Rare = Color3.fromRGB(30, 100, 255),
    Epic = Color3.fromRGB(163, 53, 238),
    Legendary = Color3.fromRGB(255, 165, 0),
}

-- Prospecting tier configurations
-- Each tier has: name, cost, findChance, and rarity probabilities
local ProspectingTiers = {
    [1] = {
        name = "Basic",
        cost = 100,
        findChance = 0.50,  -- 50% chance to find something
        description = "Common gems only",
        rarityChances = { Common = 0.80, Uncommon = 0.20, Rare = 0, Epic = 0, Legendary = 0 },
    },
    [2] = {
        name = "Advanced",
        cost = 500,
        findChance = 0.65,  -- 65% chance to find something
        description = "Common + Uncommon gems",
        rarityChances = { Common = 0.50, Uncommon = 0.40, Rare = 0.10, Epic = 0, Legendary = 0 },
    },
    [3] = {
        name = "Expert",
        cost = 2000,
        findChance = 0.80,  -- 80% chance to find something
        description = "Common + Uncommon + Rare gems",
        rarityChances = { Common = 0.30, Uncommon = 0.40, Rare = 0.25, Epic = 0.05, Legendary = 0 },
    },
    [4] = {
        name = "Master",
        cost = 10000,
        findChance = 0.90,  -- 90% chance, better rare odds
        description = "All gems including Legendary",
        rarityChances = { Common = 0.20, Uncommon = 0.30, Rare = 0.30, Epic = 0.15, Legendary = 0.05 },
    },
}

-- ============================================================================
-- RESEARCH TREE - Unlock city-wide improvements
-- ============================================================================
local ResearchTree = {
    -- Mining Category
    mining_efficiency_1 = {
        name = "Mining Efficiency I",
        category = "Mining",
        description = "+10% Gold Mine production",
        bonus = { target = "goldMine", type = "production", value = 0.10 },
        cost = { gold = 2000, wood = 500 },
        duration = 300, -- 5 minutes
        prerequisites = {},
        thRequired = 1,
    },
    mining_efficiency_2 = {
        name = "Mining Efficiency II",
        category = "Mining",
        description = "+15% Gold Mine production",
        bonus = { target = "goldMine", type = "production", value = 0.15 },
        cost = { gold = 8000, wood = 2000 },
        duration = 900, -- 15 minutes
        prerequisites = { "mining_efficiency_1" },
        thRequired = 3,
    },
    smelting_mastery = {
        name = "Smelting Mastery",
        category = "Mining",
        description = "+20% Smelter production",
        bonus = { target = "smelter", type = "production", value = 0.20 },
        cost = { gold = 5000, wood = 1500 },
        duration = 600, -- 10 minutes
        prerequisites = { "mining_efficiency_1" },
        thRequired = 2,
    },

    -- Forestry Category
    forestry_efficiency_1 = {
        name = "Forestry Efficiency I",
        category = "Forestry",
        description = "+10% Lumber Mill production",
        bonus = { target = "lumberMill", type = "production", value = 0.10 },
        cost = { gold = 2000, wood = 500 },
        duration = 300, -- 5 minutes
        prerequisites = {},
        thRequired = 1,
    },
    forestry_efficiency_2 = {
        name = "Forestry Efficiency II",
        category = "Forestry",
        description = "+15% Lumber Mill production",
        bonus = { target = "lumberMill", type = "production", value = 0.15 },
        cost = { gold = 8000, wood = 2000 },
        duration = 900, -- 15 minutes
        prerequisites = { "forestry_efficiency_1" },
        thRequired = 3,
    },
    sawmill_precision = {
        name = "Sawmill Precision",
        category = "Forestry",
        description = "+25% Sawmill speed",
        bonus = { target = "sawmill", type = "speed", value = 0.25 },
        cost = { gold = 6000, wood = 3000 },
        duration = 720, -- 12 minutes
        prerequisites = { "forestry_efficiency_1" },
        thRequired = 2,
    },

    -- Agriculture Category
    agriculture_efficiency_1 = {
        name = "Agriculture Efficiency I",
        category = "Agriculture",
        description = "+10% Farm production",
        bonus = { target = "farm", type = "production", value = 0.10 },
        cost = { gold = 1500, food = 300 },
        duration = 300, -- 5 minutes
        prerequisites = {},
        thRequired = 1,
    },
    agriculture_efficiency_2 = {
        name = "Agriculture Efficiency II",
        category = "Agriculture",
        description = "+15% Farm production",
        bonus = { target = "farm", type = "production", value = 0.15 },
        cost = { gold = 6000, food = 1200 },
        duration = 900, -- 15 minutes
        prerequisites = { "agriculture_efficiency_1" },
        thRequired = 3,
    },
    windmill_efficiency = {
        name = "Windmill Efficiency",
        category = "Agriculture",
        description = "+20% Windmill speed",
        bonus = { target = "windmill", type = "speed", value = 0.20 },
        cost = { gold = 4000, food = 800 },
        duration = 600, -- 10 minutes
        prerequisites = { "agriculture_efficiency_1" },
        thRequired = 2,
    },

    -- Military Category
    military_training_1 = {
        name = "Military Training I",
        category = "Military",
        description = "+15% Training speed",
        bonus = { target = "barracks", type = "speed", value = 0.15 },
        cost = { gold = 3000, food = 600 },
        duration = 480, -- 8 minutes
        prerequisites = {},
        thRequired = 2,
    },
    military_training_2 = {
        name = "Military Training II",
        category = "Military",
        description = "+25% Training speed",
        bonus = { target = "barracks", type = "speed", value = 0.25 },
        cost = { gold = 12000, food = 2400 },
        duration = 1200, -- 20 minutes
        prerequisites = { "military_training_1" },
        thRequired = 5,
    },

    -- Universal Category
    productivity_1 = {
        name = "Productivity I",
        category = "Universal",
        description = "+5% ALL production",
        bonus = { target = "all", type = "production", value = 0.05 },
        cost = { gold = 15000, wood = 5000, food = 2000 },
        duration = 1800, -- 30 minutes
        prerequisites = { "mining_efficiency_2", "forestry_efficiency_2", "agriculture_efficiency_2" },
        thRequired = 5,
    },

    -- ====== DEFENSE CATEGORY ======
    defense_basic = {
        name = "Basic Fortifications",
        category = "Defense",
        description = "Enables Cannon targeting during base defense",
        bonus = {
            target = "cannon",
            type = "activation",
            value = 1
        },
        cost = { gold = 1500, wood = 500 },
        duration = 300, -- 5 minutes
        prerequisites = {},
        thRequired = 1,
    },
    defense_archery = {
        name = "Archer Towers",
        category = "Defense",
        description = "Enables Archer Tower targeting during base defense",
        bonus = {
            target = "archerTower",
            type = "activation",
            value = 1
        },
        cost = { gold = 3000, wood = 1000 },
        duration = 600, -- 10 minutes
        prerequisites = {"defense_basic"},
        thRequired = 2,
    },
    defense_splash = {
        name = "Mortar Emplacements",
        category = "Defense",
        description = "Enables Mortar targeting during base defense",
        bonus = {
            target = "mortar",
            type = "activation",
            value = 1
        },
        cost = { gold = 6000, wood = 2000 },
        duration = 900, -- 15 minutes
        prerequisites = {"defense_basic"},
        thRequired = 3,
    },
    defense_walls = {
        name = "Stone Walls",
        category = "Defense",
        description = "+50% Wall HP during base defense",
        bonus = {
            target = "wall",
            type = "defense_hp",
            value = 0.50
        },
        cost = { gold = 3000, wood = 2000 },
        duration = 600, -- 10 minutes
        prerequisites = {"defense_basic"},
        thRequired = 2,
    },
    defense_anti_air = {
        name = "Air Defense",
        category = "Defense",
        description = "Enables Air Defense targeting during base defense",
        bonus = {
            target = "airDefense",
            type = "activation",
            value = 1
        },
        cost = { gold = 10000, wood = 3000 },
        duration = 1200, -- 20 minutes
        prerequisites = {"defense_archery"},
        thRequired = 4,
    },
    defense_magic = {
        name = "Wizard Towers",
        category = "Defense",
        description = "Enables Wizard Tower targeting during base defense",
        bonus = {
            target = "wizardTower",
            type = "activation",
            value = 1
        },
        cost = { gold = 15000, wood = 5000, food = 1000 },
        duration = 1500, -- 25 minutes
        prerequisites = {"defense_splash"},
        thRequired = 5,
    },
    defense_damage_1 = {
        name = "Reinforced Ammo",
        category = "Defense",
        description = "+15% damage for all defense buildings",
        bonus = {
            target = "all_defense",
            type = "defense_damage",
            value = 0.15
        },
        cost = { gold = 5000, wood = 2000 },
        duration = 720, -- 12 minutes
        prerequisites = {"defense_basic"},
        thRequired = 3,
    },
    defense_damage_2 = {
        name = "Enhanced Ballistics",
        category = "Defense",
        description = "+25% damage for all defense buildings",
        bonus = {
            target = "all_defense",
            type = "defense_damage",
            value = 0.25
        },
        cost = { gold = 12000, wood = 4000 },
        duration = 1200, -- 20 minutes
        prerequisites = {"defense_damage_1"},
        thRequired = 5,
    },
    defense_range_1 = {
        name = "Extended Range",
        category = "Defense",
        description = "+10% range for all defense buildings",
        bonus = {
            target = "all_defense",
            type = "defense_range",
            value = 0.10
        },
        cost = { gold = 8000, wood = 3000 },
        duration = 900, -- 15 minutes
        prerequisites = {"defense_archery"},
        thRequired = 4,
    },
}

-- ============================================================================
-- BUILDING UPGRADE COSTS - Scaling costs per building type
-- ============================================================================
-- Cost formula: base * (1.5 ^ (level - 1))
local BuildingUpgradeCosts = {
    goldMine = { base = { gold = 500, wood = 100 }, maxLevel = 10 },
    lumberMill = { base = { gold = 500, wood = 100 }, maxLevel = 10 },
    barracks = { base = { gold = 800, food = 200 }, maxLevel = 10 },
    farm1 = { base = { gold = 300, wood = 50 }, maxLevel = 10 },
    farm2 = { base = { gold = 300, wood = 50 }, maxLevel = 10 },
    farm3 = { base = { gold = 300, wood = 50 }, maxLevel = 10 },
    farm4 = { base = { gold = 300, wood = 50 }, maxLevel = 10 },
    farm5 = { base = { gold = 300, wood = 50 }, maxLevel = 10 },
    farm6 = { base = { gold = 300, wood = 50 }, maxLevel = 10 },
}

-- Town Hall direct upgrade costs (gold only, per current level)
local TownHallUpgradeCosts = {
    [1] = { gold = 1000 },
    [2] = { gold = 4000 },
    [3] = { gold = 25000 },
    [4] = { gold = 150000 },
    [5] = { gold = 750000 },
    [6] = { gold = 1200000 },
    [7] = { gold = 2000000 },
    [8] = { gold = 3000000 },
    [9] = { gold = 5000000 },
}

-- Calculate upgrade cost for a building at current level
local function getUpgradeCost(buildingName, currentLevel)
    local config = BuildingUpgradeCosts[buildingName]
    if not config then return nil end
    if currentLevel >= config.maxLevel then return nil end

    local multiplier = math.pow(1.5, currentLevel - 1)
    local cost = {}
    for resource, amount in pairs(config.base) do
        cost[resource] = math.floor(amount * multiplier)
    end
    return cost
end

-- Roll a gem based on prospecting tier (returns gem data or nil)
local function rollGem(tier)
    local tierData = ProspectingTiers[tier] or ProspectingTiers[1]
    local rarityChances = tierData.rarityChances

    -- Step 1: Determine rarity tier based on tier's rarity chances
    local roll = math.random()
    local cumulative = 0
    local selectedRarity = "Common" -- Default fallback

    -- Order matters for cumulative probability
    local rarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
    for _, rarityTier in ipairs(rarityOrder) do
        local chance = rarityChances[rarityTier] or 0
        cumulative = cumulative + chance
        if roll <= cumulative then
            selectedRarity = rarityTier
            break
        end
    end

    -- Step 2: Pick a random gem from that rarity tier
    local gemsInRarity = GemsByRarity[selectedRarity]
    local gemType = gemsInRarity[math.random(#gemsInRarity)]

    -- Step 3: Determine gem size
    roll = math.random()
    cumulative = 0
    local gemSize = "Chip" -- Default fallback

    for sName, sData in pairs(GemSizes) do
        cumulative = cumulative + sData.rarity
        if roll <= cumulative then
            gemSize = sName
            break
        end
    end

    -- Step 4: Calculate gem value (random between min and max)
    local gemData = GemTypes[gemType]
    local gemValue = math.random(gemData.minValue, gemData.maxValue)

    return {
        type = gemType,
        size = gemSize,
        rarity = selectedRarity,
        color = gemData.color,
        boost = gemData.boost,
        multiplier = GemSizes[gemSize].multiplier,
        value = gemValue,
    }
end

-- ============================================================================
-- GOLD MINE - Simplified flow with visible workers
-- ORE VEIN → SMELTER → GOLD CHEST
-- Miners carry ore to smelter, Collectors carry gold to chest
-- ============================================================================

-- Gold Mine state
local GoldMineState = {
    level = 1,
    xp = 0,
    miners = {},        -- NPC miners (ore vein → smelter)
    collectors = {},    -- NPC collectors (smelter → chest)
    equipment = {
        pickaxeLevel = 1,
        smelterLevel = 1,
        minerLevel = 1,
        collectorLevel = 1,
    },
    playerOre = {},     -- [playerId] = ore count being carried
    playerGold = {},    -- [playerId] = gold bars being carried
    smelterOre = 0,     -- Ore waiting to be smelted
    smelterGold = 0,    -- Gold ready to collect from smelter
    chestGold = 0,      -- Gold in chest ready for player
    -- Station positions (set during creation)
    positions = {},
    -- Visual update functions (set during creation)
    updateGoldBarVisuals = nil,
    updateChestGoldVisuals = nil,
    -- Waiting workers at hiring stands (workers that leave when hired)
    waitingMiners = {},     -- Array of 3 worker models waiting to be hired
    waitingCollectors = {}, -- Array of 3 worker models waiting to be hired
    -- UI elements for hiring stands
    minerSign = nil,        -- Reference to miner sign label for updating text
    collectorSign = nil,    -- Reference to collector sign label for updating text
    minerPrompt = nil,      -- Reference to miner hire prompt
    collectorPrompt = nil,  -- Reference to collector hire prompt
    -- Gem Prospecting Station state
    prospecting = {
        isActive = false,       -- Is a prospect currently running?
        tier = nil,             -- 1=Basic, 2=Advanced, 3=Premium
        startTime = 0,          -- When prospecting started
        endTime = 0,            -- When prospecting completes
    },
    -- Player's held gem from prospecting (before placing in Town Hall)
    playerHeldGem = {},         -- [playerId] = gem data or nil
}

-- Equipment stats - LEVEL BASED (scales infinitely)
-- Returns stats for a given level, with scaling costs

local function getPickaxeStats(level)
    return {
        orePerSwing = level,                           -- Level 1 = 1 ore, Level 5 = 5 ore
        speed = 1.0 + (level - 1) * 0.2,               -- Gets faster
        upgradeCost = math.floor(100 * (level ^ 1.8)), -- Exponential cost: 100, 348, 728, 1234...
    }
end

local function getSmelterStats(level)
    -- Speed only increases at milestone levels: 10, 20, 50, 100, 200, 500...
    local speedBoosts = 0
    if level >= 10 then speedBoosts = speedBoosts + 1 end
    if level >= 20 then speedBoosts = speedBoosts + 1 end
    if level >= 50 then speedBoosts = speedBoosts + 1 end
    if level >= 100 then speedBoosts = speedBoosts + 1 end
    if level >= 200 then speedBoosts = speedBoosts + 1 end
    if level >= 500 then speedBoosts = speedBoosts + 1 end
    if level >= 1000 then speedBoosts = speedBoosts + 1 end

    local smeltTime = math.max(0.2, 2.0 - (speedBoosts * 0.25)) -- 2.0s → 1.75s → 1.5s → 1.25s → 1.0s → 0.75s → 0.5s → 0.25s

    return {
        goldPerOre = level,                            -- Level 1 = 1 gold/ore, increases every level
        smeltTime = smeltTime,                         -- Only faster at milestones
        speedBoosts = speedBoosts,                     -- For display purposes
        upgradeCost = math.floor(200 * (level ^ 1.8)), -- 200, 696, 1456, 2468...
    }
end

local function getMinerStats(level)
    return {
        oreCapacity = 5 + (level * 5),                 -- 10, 15, 20, 25...
        walkSpeed = 4 + level,                         -- 5, 6, 7, 8...
        miningTime = math.max(0.2, 0.5 - (level - 1) * 0.05), -- Faster mining per ore
        upgradeCost = math.floor(150 * (level ^ 1.8)), -- 150, 522, 1092, 1851...
    }
end

local function getCollectorStats(level)
    return {
        goldCapacity = 2 + level,                      -- 3, 4, 5, 6...
        walkSpeed = 4 + level,                         -- 5, 6, 7, 8...
        upgradeCost = math.floor(100 * (level ^ 1.8)), -- 100, 348, 728, 1234...
    }
end

local MinerCosts = {
    [1] = { gold = 1500, food = 300 },
    [2] = { gold = 4500, food = 900 },
    [3] = { gold = 15000, food = 3000 },
}

local CollectorCosts = {
    [1] = { gold = 900, food = 150 },
    [2] = { gold = 3000, food = 600 },
    [3] = { gold = 9000, food = 1800 },
}

local function getPlayerOre(player)
    return GoldMineState.playerOre[player.UserId] or 0
end

-- Update visual ore on player's back
local function updatePlayerOreVisual(player, amount)
    local character = player.Character
    if not character then return end

    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    if not torso then return end

    -- Remove existing ore backpack
    local existingBackpack = character:FindFirstChild("OreBackpack")
    if existingBackpack then
        existingBackpack:Destroy()
    end

    -- If no ore, don't add visual
    if amount <= 0 then return end

    -- Create backpack model
    local backpack = Instance.new("Model")
    backpack.Name = "OreBackpack"
    backpack.Parent = character

    -- Backpack base (sack)
    local sack = Instance.new("Part")
    sack.Name = "Sack"
    sack.Size = Vector3.new(1.5, 1.2 + (amount * 0.1), 1)
    sack.Anchored = false
    sack.CanCollide = false
    sack.Material = Enum.Material.Fabric
    sack.Color = Color3.fromRGB(120, 90, 60)
    sack.Parent = backpack

    -- Weld to torso
    local weld = Instance.new("Weld")
    weld.Part0 = torso
    weld.Part1 = sack
    weld.C0 = CFrame.new(0, 0.2, 0.9) -- Position on back
    weld.Parent = sack

    -- Add ore chunks on top based on amount
    local oreCount = math.min(amount, 5) -- Show up to 5 visible ore chunks
    for i = 1, oreCount do
        local ore = Instance.new("Part")
        ore.Name = "Ore" .. i
        ore.Size = Vector3.new(0.4, 0.4, 0.4)
        ore.Anchored = false
        ore.CanCollide = false
        ore.Material = Enum.Material.Metal
        ore.Color = Color3.fromRGB(255, 200, 50) -- Gold ore color
        ore.Parent = backpack

        local oreWeld = Instance.new("Weld")
        oreWeld.Part0 = sack
        oreWeld.Part1 = ore
        -- Arrange ore chunks on top of sack
        local angle = (i - 1) * (math.pi * 2 / oreCount)
        local radius = 0.3
        oreWeld.C0 = CFrame.new(
            math.cos(angle) * radius,
            sack.Size.Y / 2 + 0.1,
            math.sin(angle) * radius
        )
        oreWeld.Parent = ore
    end

    -- Add text showing count
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "OreCount"
    billboard.Size = UDim2.new(2, 0, 1, 0)
    billboard.StudsOffset = Vector3.new(0, 1.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = sack

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = string.format("Ore: %d/10", amount)
    label.TextColor3 = Color3.fromRGB(255, 215, 0)
    label.TextStrokeTransparency = 0.5
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard
end

local function setPlayerOre(player, amount)
    local newAmount = math.max(0, math.min(amount, 10)) -- Max 10 ore carried
    GoldMineState.playerOre[player.UserId] = newAmount
    updatePlayerOreVisual(player, newAmount)
end

local function addMineXP(amount)
    GoldMineState.xp = GoldMineState.xp + amount
    local requiredXP = GoldMineState.level * 100
    if GoldMineState.xp >= requiredXP then
        GoldMineState.level = GoldMineState.level + 1
        GoldMineState.xp = GoldMineState.xp - requiredXP
        print(string.format("[GoldMine] LEVEL UP! Now level %d", GoldMineState.level))
    end
end

local function createGoldMine()
    print("[3/8] Creating Gold Mine with CAVE interior...")

    -- ========== EXTERIOR IN VILLAGE (Mine entrance) ==========
    -- Left side of path, entrance facing EAST (toward main path at X=60)
    local exteriorX, exteriorZ = 25, 50
    local extGround = GROUND_Y

    -- Create mine entrance (rocky hillside with cave opening)
    local mineEntrance = Instance.new("Model")
    mineEntrance.Name = "GoldMine_Exterior"

    -- Main rocky hillside/cliff (irregular shape using multiple rocks)
    local rockColors = {
        Color3.fromRGB(75, 70, 65),
        Color3.fromRGB(85, 80, 75),
        Color3.fromRGB(70, 65, 60),
        Color3.fromRGB(90, 85, 80),
    }

    -- Large back rock (forms the main cliff face)
    local mainCliff = Instance.new("Part")
    mainCliff.Name = "MainCliff"
    mainCliff.Size = Vector3.new(12, 14, 18)
    mainCliff.Position = Vector3.new(exteriorX - 2, extGround + 5, exteriorZ)
    mainCliff.Anchored = true
    mainCliff.Material = Enum.Material.Rock
    mainCliff.Color = rockColors[1]
    mainCliff.Parent = mineEntrance

    -- Upper rock formation (makes it look more natural/irregular)
    local upperRock = Instance.new("Part")
    upperRock.Name = "UpperRock"
    upperRock.Size = Vector3.new(10, 6, 14)
    upperRock.Position = Vector3.new(exteriorX - 1, extGround + 13, exteriorZ + 1)
    upperRock.Orientation = Vector3.new(5, 10, -8)
    upperRock.Anchored = true
    upperRock.Material = Enum.Material.Rock
    upperRock.Color = rockColors[2]
    upperRock.Parent = mineEntrance

    -- Side rock (left side of entrance)
    local leftRock = Instance.new("Part")
    leftRock.Name = "LeftRock"
    leftRock.Size = Vector3.new(8, 10, 8)
    leftRock.Position = Vector3.new(exteriorX, extGround + 4, exteriorZ - 8)
    leftRock.Orientation = Vector3.new(-5, 15, 10)
    leftRock.Anchored = true
    leftRock.Material = Enum.Material.Rock
    leftRock.Color = rockColors[3]
    leftRock.Parent = mineEntrance

    -- Side rock (right side of entrance)
    local rightRock = Instance.new("Part")
    rightRock.Name = "RightRock"
    rightRock.Size = Vector3.new(8, 10, 8)
    rightRock.Position = Vector3.new(exteriorX, extGround + 4, exteriorZ + 8)
    rightRock.Orientation = Vector3.new(8, -12, -6)
    rightRock.Anchored = true
    rightRock.Material = Enum.Material.Rock
    rightRock.Color = rockColors[4]
    rightRock.Parent = mineEntrance

    -- Scattered boulders BEHIND and to the SIDES of entrance (not blocking path)
    -- Path comes from +X (east), so boulders go at -X (west/behind) or far Z (sides)
    local boulderPositions = {
        -- Behind the cliff (west side, not visible from path but adds depth)
        { pos = Vector3.new(exteriorX - 8, extGround + 1, exteriorZ - 4), size = Vector3.new(3, 2.5, 3), rot = Vector3.new(10, 25, 5) },
        { pos = Vector3.new(exteriorX - 6, extGround + 0.8, exteriorZ + 5), size = Vector3.new(2.5, 2, 2.5), rot = Vector3.new(-8, 40, 12) },
        -- Far to the sides (won't block approach)
        { pos = Vector3.new(exteriorX + 2, extGround + 0.5, exteriorZ - 14), size = Vector3.new(2, 1.5, 2), rot = Vector3.new(15, -20, 8) },
        { pos = Vector3.new(exteriorX + 2, extGround + 0.6, exteriorZ + 14), size = Vector3.new(2.2, 1.8, 2.2), rot = Vector3.new(5, 60, -10) },
        -- Small ones tucked against the cliff sides
        { pos = Vector3.new(exteriorX + 3, extGround + 0.4, exteriorZ - 10), size = Vector3.new(1.5, 1.2, 1.5), rot = Vector3.new(-5, 30, 15) },
        { pos = Vector3.new(exteriorX + 3, extGround + 0.5, exteriorZ + 10), size = Vector3.new(1.8, 1.4, 1.8), rot = Vector3.new(12, -45, 5) },
    }

    for i, boulder in ipairs(boulderPositions) do
        local rock = Instance.new("Part")
        rock.Name = "Boulder" .. i
        rock.Size = boulder.size
        rock.Position = boulder.pos
        rock.Orientation = boulder.rot
        rock.Anchored = true
        rock.Material = Enum.Material.Rock
        rock.Color = rockColors[(i % #rockColors) + 1]
        rock.Parent = mineEntrance
    end

    -- Small rock debris along the SIDES of the entrance path (not in the middle)
    for i = 1, 8 do
        local debris = Instance.new("Part")
        debris.Name = "Debris" .. i
        -- Alternate between left side (Z-) and right side (Z+) of the path
        local sideOffset = (i % 2 == 0) and (exteriorZ + 6 + math.random() * 4) or (exteriorZ - 6 - math.random() * 4)
        debris.Size = Vector3.new(0.5 + math.random() * 0.8, 0.4 + math.random() * 0.5, 0.5 + math.random() * 0.8)
        debris.Position = Vector3.new(
            exteriorX + 4 + math.random() * 4,  -- Near the entrance but to the sides
            extGround + 0.2,
            sideOffset
        )
        debris.Orientation = Vector3.new(math.random() * 30, math.random() * 360, math.random() * 30)
        debris.Anchored = true
        debris.Material = Enum.Material.Rock
        debris.Color = rockColors[(i % #rockColors) + 1]
        debris.Parent = mineEntrance
    end

    -- THE CAVE ENTRANCE (dark hole carved into rock)
    local caveOpening = Instance.new("Part")
    caveOpening.Name = "CaveOpening"
    caveOpening.Size = Vector3.new(3, 7, 8)
    caveOpening.Position = Vector3.new(exteriorX + 4, extGround + 3.5, exteriorZ)
    caveOpening.Anchored = true
    caveOpening.Material = Enum.Material.Slate
    caveOpening.Color = Color3.fromRGB(10, 8, 5) -- Very dark, almost black
    caveOpening.Parent = mineEntrance

    -- Inner darkness (makes the hole look deeper)
    local innerDark = Instance.new("Part")
    innerDark.Name = "InnerDarkness"
    innerDark.Size = Vector3.new(2, 6, 6)
    innerDark.Position = Vector3.new(exteriorX + 2, extGround + 3, exteriorZ)
    innerDark.Anchored = true
    innerDark.Material = Enum.Material.Slate
    innerDark.Color = Color3.fromRGB(5, 3, 2) -- Even darker inside
    innerDark.Parent = mineEntrance

    -- Wooden mine supports at entrance
    local supportColor = Color3.fromRGB(60, 40, 25)
    -- Left support beam
    local leftBeam = Instance.new("Part")
    leftBeam.Name = "LeftSupport"
    leftBeam.Size = Vector3.new(0.8, 7, 0.8)
    leftBeam.Position = Vector3.new(exteriorX + 5, extGround + 3.5, exteriorZ - 3.5)
    leftBeam.Anchored = true
    leftBeam.Material = Enum.Material.Wood
    leftBeam.Color = supportColor
    leftBeam.Parent = mineEntrance

    -- Right support beam
    local rightBeam = Instance.new("Part")
    rightBeam.Name = "RightSupport"
    rightBeam.Size = Vector3.new(0.8, 7, 0.8)
    rightBeam.Position = Vector3.new(exteriorX + 5, extGround + 3.5, exteriorZ + 3.5)
    rightBeam.Anchored = true
    rightBeam.Material = Enum.Material.Wood
    rightBeam.Color = supportColor
    rightBeam.Parent = mineEntrance

    -- Top support beam (horizontal)
    local topBeam = Instance.new("Part")
    topBeam.Name = "TopSupport"
    topBeam.Size = Vector3.new(0.8, 0.6, 8)
    topBeam.Position = Vector3.new(exteriorX + 5, extGround + 7.3, exteriorZ)
    topBeam.Anchored = true
    topBeam.Material = Enum.Material.Wood
    topBeam.Color = supportColor
    topBeam.Parent = mineEntrance

    -- Torches on either side of entrance
    createTorch(mineEntrance, Vector3.new(exteriorX + 6, extGround + 5, exteriorZ - 4.5))
    createTorch(mineEntrance, Vector3.new(exteriorX + 6, extGround + 5, exteriorZ + 4.5))

    -- Warm cave glow (visible from outside)
    local caveGlow = Instance.new("PointLight")
    caveGlow.Name = "CaveGlow"
    caveGlow.Color = Color3.fromRGB(255, 160, 60)
    caveGlow.Brightness = 2
    caveGlow.Range = 20
    caveGlow.Parent = caveOpening

    -- Ore vein streaks on cliff face (gold-colored thin Parts embedded in rock)
    local veinPositions = {
        {pos = Vector3.new(exteriorX - 1, extGround + 8, exteriorZ - 3), rot = Vector3.new(5, 20, 45)},
        {pos = Vector3.new(exteriorX - 2, extGround + 6, exteriorZ + 2), rot = Vector3.new(-8, -15, 30)},
        {pos = Vector3.new(exteriorX, extGround + 10, exteriorZ + 1), rot = Vector3.new(12, 5, -35)},
        {pos = Vector3.new(exteriorX - 1, extGround + 4, exteriorZ - 5), rot = Vector3.new(3, 35, 50)},
    }
    for vi, vein in veinPositions do
        local veinPart = Instance.new("Part")
        veinPart.Name = "OreVein" .. vi
        veinPart.Size = Vector3.new(2.5, 0.15, 0.3)
        veinPart.Position = vein.pos
        veinPart.Orientation = vein.rot
        veinPart.Anchored = true
        veinPart.Material = Enum.Material.Neon
        veinPart.Color = Color3.fromRGB(220, 180, 40)
        veinPart.CanCollide = false
        veinPart.Parent = mineEntrance
    end

    -- Wooden scaffolding above entrance
    local scaffColor = Color3.fromRGB(70, 48, 30)
    -- Horizontal beams
    local scaffH1 = Instance.new("Part")
    scaffH1.Name = "ScaffoldH1"
    scaffH1.Size = Vector3.new(0.4, 0.4, 10)
    scaffH1.Position = Vector3.new(exteriorX + 5.5, extGround + 9, exteriorZ)
    scaffH1.Anchored = true
    scaffH1.Material = Enum.Material.Wood
    scaffH1.Color = scaffColor
    scaffH1.CanCollide = false
    scaffH1.Parent = mineEntrance

    local scaffH2 = Instance.new("Part")
    scaffH2.Name = "ScaffoldH2"
    scaffH2.Size = Vector3.new(0.4, 0.4, 10)
    scaffH2.Position = Vector3.new(exteriorX + 4, extGround + 9, exteriorZ)
    scaffH2.Anchored = true
    scaffH2.Material = Enum.Material.Wood
    scaffH2.Color = scaffColor
    scaffH2.CanCollide = false
    scaffH2.Parent = mineEntrance

    -- Vertical scaffold supports
    for _, szOff in {-4.5, 4.5} do
        local scaffV = Instance.new("Part")
        scaffV.Name = "ScaffoldV"
        scaffV.Size = Vector3.new(0.4, 3, 0.4)
        scaffV.Position = Vector3.new(exteriorX + 5.5, extGround + 7.5, exteriorZ + szOff)
        scaffV.Anchored = true
        scaffV.Material = Enum.Material.Wood
        scaffV.Color = scaffColor
        scaffV.CanCollide = false
        scaffV.Parent = mineEntrance
    end

    -- Lanterns on support beams (hung from horizontal scaffolding)
    for _, lzOff in {-3, 3} do
        local beamLantern = Instance.new("Part")
        beamLantern.Name = "BeamLantern"
        beamLantern.Size = Vector3.new(0.6, 0.8, 0.6)
        beamLantern.Position = Vector3.new(exteriorX + 5.5, extGround + 8.3, exteriorZ + lzOff)
        beamLantern.Anchored = true
        beamLantern.Material = Enum.Material.Glass
        beamLantern.Color = Color3.fromRGB(255, 210, 130)
        beamLantern.Transparency = 0.3
        beamLantern.CanCollide = false
        beamLantern.Parent = mineEntrance

        local bLight = Instance.new("PointLight")
        bLight.Color = Color3.fromRGB(255, 180, 80)
        bLight.Brightness = 1
        bLight.Range = 10
        bLight.Parent = beamLantern
    end

    -- Mine cart wheels (4 small cylinders)
    for _, wOff in {{-0.8, -1.2}, {-0.8, 1.2}, {0.8, -1.2}, {0.8, 1.2}} do
        local cartWheel = Instance.new("Part")
        cartWheel.Name = "CartWheel"
        cartWheel.Shape = Enum.PartType.Cylinder
        cartWheel.Size = Vector3.new(0.2, 0.8, 0.8)
        cartWheel.Position = Vector3.new(exteriorX + 9 + wOff[1], extGround + 0.4, exteriorZ + trackZOffset + wOff[2])
        cartWheel.Orientation = Vector3.new(0, 90, 0)
        cartWheel.Anchored = true
        cartWheel.Material = Enum.Material.Metal
        cartWheel.Color = Color3.fromRGB(70, 65, 60)
        cartWheel.CanCollide = false
        cartWheel.Parent = mineEntrance
    end

    -- Mine cart tracks off to the RIGHT side of entrance (not blocking path)
    local trackColor = Color3.fromRGB(80, 70, 60)
    local trackZOffset = 8  -- Offset tracks to the right side
    for _, zOff in ipairs({-1.2, 1.2}) do
        local rail = Instance.new("Part")
        rail.Name = "Rail"
        rail.Size = Vector3.new(8, 0.15, 0.25)
        rail.Position = Vector3.new(exteriorX + 7, extGround + 0.1, exteriorZ + trackZOffset + zOff)
        rail.Anchored = true
        rail.Material = Enum.Material.Metal
        rail.Color = trackColor
        rail.Parent = mineEntrance
    end
    -- Rail ties
    for i = 0, 3 do
        local tie = Instance.new("Part")
        tie.Name = "RailTie" .. i
        tie.Size = Vector3.new(0.6, 0.1, 3)
        tie.Position = Vector3.new(exteriorX + 4 + i * 2, extGround + 0.05, exteriorZ + trackZOffset)
        tie.Anchored = true
        tie.Material = Enum.Material.Wood
        tie.Color = Color3.fromRGB(50, 35, 20)
        tie.Parent = mineEntrance
    end

    -- Old mine cart off to the side (visual prop, not blocking entrance)
    local cartBody = Instance.new("Part")
    cartBody.Name = "MineCart"
    cartBody.Size = Vector3.new(2.5, 1.5, 3)
    cartBody.Position = Vector3.new(exteriorX + 9, extGround + 1, exteriorZ + trackZOffset)
    cartBody.Anchored = true
    cartBody.Material = Enum.Material.Metal
    cartBody.Color = Color3.fromRGB(100, 80, 60)
    cartBody.Parent = mineEntrance

    -- Gold ore spilling out of cart
    for i = 1, 3 do
        local ore = Instance.new("Part")
        ore.Name = "CartOre" .. i
        ore.Shape = Enum.PartType.Ball
        ore.Size = Vector3.new(0.6, 0.6, 0.6)
        ore.Position = Vector3.new(exteriorX + 9 + (i-2) * 0.5, extGround + 1.9, exteriorZ + trackZOffset + (i-2) * 0.4)
        ore.Anchored = true
        ore.Material = Enum.Material.Metal
        ore.Color = Color3.fromRGB(255, 200, 50) -- Gold color
        ore.Parent = mineEntrance
    end

    -- ===== LARGE SIGN WITH PRODUCTION RATE =====
    -- Sign post (support beam)
    local signPost = Instance.new("Part")
    signPost.Name = "SignPost"
    signPost.Size = Vector3.new(0.6, 8, 0.6)
    signPost.Position = Vector3.new(exteriorX + 6, extGround + 4, exteriorZ - 10)
    signPost.Anchored = true
    signPost.Material = Enum.Material.Wood
    signPost.Color = Color3.fromRGB(50, 35, 20)
    signPost.Parent = mineEntrance

    -- Large sign board (similar to Lumber Yard)
    local signBoard = Instance.new("Part")
    signBoard.Name = "Sign"
    signBoard.Size = Vector3.new(0.5, 6, 14)  -- Much larger sign
    signBoard.Position = Vector3.new(exteriorX + 6.5, extGround + 11, exteriorZ - 5)
    signBoard.Anchored = true
    signBoard.Material = Enum.Material.Wood
    signBoard.Color = Color3.fromRGB(60, 40, 25)
    signBoard.Parent = mineEntrance

    local goldMineGui = Instance.new("SurfaceGui")
    goldMineGui.Face = Enum.NormalId.Right  -- Face east toward main path
    goldMineGui.Parent = signBoard

    -- Title label (large)
    local goldMineTitleLabel = Instance.new("TextLabel")
    goldMineTitleLabel.Name = "TitleLabel"
    goldMineTitleLabel.Size = UDim2.new(1, 0, 0.6, 0)
    goldMineTitleLabel.Position = UDim2.new(0, 0, 0, 0)
    goldMineTitleLabel.BackgroundTransparency = 1
    goldMineTitleLabel.Text = "GOLD MINE"
    goldMineTitleLabel.TextColor3 = Color3.fromRGB(255, 215, 0)  -- Gold color
    goldMineTitleLabel.TextScaled = true
    goldMineTitleLabel.Font = Enum.Font.Antique
    goldMineTitleLabel.Parent = goldMineGui

    -- Production rate label (below title)
    local goldMineProductionLabel = Instance.new("TextLabel")
    goldMineProductionLabel.Name = "ProductionLabel"
    goldMineProductionLabel.Size = UDim2.new(1, 0, 0.35, 0)
    goldMineProductionLabel.Position = UDim2.new(0, 0, 0.6, 0)
    goldMineProductionLabel.BackgroundTransparency = 1
    goldMineProductionLabel.Text = "+0 gold/min"
    goldMineProductionLabel.TextColor3 = Color3.fromRGB(180, 255, 180)  -- Green for production
    goldMineProductionLabel.TextScaled = true
    goldMineProductionLabel.Font = Enum.Font.GothamBold
    goldMineProductionLabel.Parent = goldMineGui
    makeSignDoubleSided(signBoard)

    -- Function to update production rate display
    local function updateGoldMineProduction()
        -- Calculate production based on workers and upgrades
        local minerCount = #GoldMineState.miners
        local collectorCount = #GoldMineState.collectors
        local minerStats = getMinerStats(GoldMineState.equipment.minerLevel)
        local smelterStats = getSmelterStats(GoldMineState.equipment.smelterLevel)

        -- Estimate: each miner produces ~oreCapacity ore per cycle (~30 sec cycle = ~2 cycles per minute)
        -- Smelter converts ore to gold at goldPerOre rate
        -- Collectors deliver gold from smelter to chest

        local cyclesPerMinute = 2  -- Approximate miner cycles per minute
        local orePerMinute = minerCount * (minerStats.oreCapacity * cyclesPerMinute)
        local goldPerMinute = orePerMinute * smelterStats.goldPerOre

        -- Only count production if we have both miners and collectors
        local effectiveProduction = (minerCount > 0 and collectorCount > 0) and math.floor(goldPerMinute) or 0

        goldMineProductionLabel.Text = string.format("+%d gold/min", effectiveProduction)

        -- Color based on production level
        if effectiveProduction == 0 then
            goldMineProductionLabel.TextColor3 = Color3.fromRGB(150, 150, 150)  -- Gray when idle
        elseif effectiveProduction < 20 then
            goldMineProductionLabel.TextColor3 = Color3.fromRGB(180, 255, 180)  -- Light green
        else
            goldMineProductionLabel.TextColor3 = Color3.fromRGB(100, 255, 100)  -- Bright green
        end
    end

    -- Store update function for use when workers are hired or equipment upgraded
    GoldMineState.updateExteriorSign = updateGoldMineProduction

    -- Update sign periodically
    task.spawn(function()
        while true do
            updateGoldMineProduction()
            task.wait(5)  -- Update every 5 seconds
        end
    end)

    -- Walk-through entrance trigger (the black hole)
    local entranceTrigger = Instance.new("Part")
    entranceTrigger.Name = "Entrance"
    entranceTrigger.Size = Vector3.new(3, 6, 6)
    entranceTrigger.Position = Vector3.new(exteriorX + 4, extGround + 3, exteriorZ)
    entranceTrigger.Anchored = true
    entranceTrigger.Transparency = 1
    entranceTrigger.CanCollide = false
    entranceTrigger.Parent = mineEntrance

    local debounce = {}
    entranceTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if debounce[player.UserId] then return end
        debounce[player.UserId] = true
        teleportToInterior(player, "GoldMine")
        task.delay(1, function() debounce[player.UserId] = nil end)
    end)

    mineEntrance.Parent = villageFolder

    -- ========== CAVE INTERIOR ==========
    local basePos = INTERIOR_POSITIONS.GoldMine
    local mineModel = Instance.new("Model")
    mineModel.Name = "GoldMine_Interior"

    local baseX, baseZ = basePos.X, basePos.Z
    local GROUND_Y = basePos.Y -- Shadow for interior positioning

    -- Store station positions for workers
    -- REDESIGNED LAYOUT: Smelter at back wall, open floor, stations around perimeter
    -- Hire stations on LEFT and RIGHT sides of entrance portal (portal at baseZ + 28)
    GoldMineState.positions = {
        -- Back wall area (lower Z = back, higher Z = entrance)
        smelter = Vector3.new(baseX - 15, GROUND_Y, baseZ - 20),     -- Back-left: smelter
        goldChest = Vector3.new(baseX + 15, GROUND_Y, baseZ - 20),   -- Back-right: chest (near smelter)
        -- Front-left area (walls at baseX +/- 40, so positions must be inside that range)
        oreVein = Vector3.new(baseX - 33, GROUND_Y, baseZ + 10),     -- Left wall: ore vein near wall (wall at -40, 7 stud gap for miners)
        -- Front-right area (upgrades)
        upgradeKiosk = Vector3.new(baseX + 32, GROUND_Y, baseZ + 10), -- Right side: upgrade kiosk INSIDE room (walls at +40)
        -- Hire stations on SIDES of entrance portal, AGAINST entrance wall
        -- Portal frame edges are at baseX +/- 7, so position hiring stands beyond that
        hireMiner = Vector3.new(baseX - 20, GROUND_Y, baseZ + 25),   -- LEFT of portal (toward -X)
        hireCollector = Vector3.new(baseX + 20, GROUND_Y, baseZ + 25), -- RIGHT of portal (toward +X)
        -- Worker spawn in center area
        workerSpawn = Vector3.new(baseX, GROUND_Y, baseZ + 15),
    }

    -- ===== BLACK BOX ENCLOSURE (hides any cracks) =====
    local boxSize = Vector3.new(100, 40, 80)
    local boxThickness = 3

    -- Bottom (under floor)
    local boxBottom = Instance.new("Part")
    boxBottom.Name = "BoxBottom"
    boxBottom.Size = Vector3.new(boxSize.X, boxThickness, boxSize.Z)
    boxBottom.Position = Vector3.new(baseX, GROUND_Y - 5, baseZ)
    boxBottom.Anchored = true
    boxBottom.Material = Enum.Material.SmoothPlastic
    boxBottom.Color = Color3.fromRGB(0, 0, 0)
    boxBottom.CanCollide = true
    boxBottom.Parent = mineModel

    -- Top (above ceiling)
    local boxTop = Instance.new("Part")
    boxTop.Name = "BoxTop"
    boxTop.Size = Vector3.new(boxSize.X, boxThickness, boxSize.Z)
    boxTop.Position = Vector3.new(baseX, GROUND_Y + 22, baseZ)
    boxTop.Anchored = true
    boxTop.Material = Enum.Material.SmoothPlastic
    boxTop.Color = Color3.fromRGB(0, 0, 0)
    boxTop.CanCollide = false
    boxTop.Parent = mineModel

    -- Left side
    local boxLeft = Instance.new("Part")
    boxLeft.Name = "BoxLeft"
    boxLeft.Size = Vector3.new(boxThickness, boxSize.Y, boxSize.Z)
    boxLeft.Position = Vector3.new(baseX - boxSize.X/2, GROUND_Y + 8, baseZ)
    boxLeft.Anchored = true
    boxLeft.Material = Enum.Material.SmoothPlastic
    boxLeft.Color = Color3.fromRGB(0, 0, 0)
    boxLeft.CanCollide = true
    boxLeft.Parent = mineModel

    -- Right side
    local boxRight = Instance.new("Part")
    boxRight.Name = "BoxRight"
    boxRight.Size = Vector3.new(boxThickness, boxSize.Y, boxSize.Z)
    boxRight.Position = Vector3.new(baseX + boxSize.X/2, GROUND_Y + 8, baseZ)
    boxRight.Anchored = true
    boxRight.Material = Enum.Material.SmoothPlastic
    boxRight.Color = Color3.fromRGB(0, 0, 0)
    boxRight.CanCollide = true
    boxRight.Parent = mineModel

    -- Back side
    local boxBack = Instance.new("Part")
    boxBack.Name = "BoxBack"
    boxBack.Size = Vector3.new(boxSize.X, boxSize.Y, boxThickness)
    boxBack.Position = Vector3.new(baseX, GROUND_Y + 8, baseZ - boxSize.Z/2)
    boxBack.Anchored = true
    boxBack.Material = Enum.Material.SmoothPlastic
    boxBack.Color = Color3.fromRGB(0, 0, 0)
    boxBack.CanCollide = true
    boxBack.Parent = mineModel

    -- Front side (with portal opening)
    local boxFrontLeft = Instance.new("Part")
    boxFrontLeft.Name = "BoxFrontLeft"
    boxFrontLeft.Size = Vector3.new(boxSize.X/2 - 10, boxSize.Y, boxThickness)
    boxFrontLeft.Position = Vector3.new(baseX - boxSize.X/4 - 5, GROUND_Y + 8, baseZ + boxSize.Z/2)
    boxFrontLeft.Anchored = true
    boxFrontLeft.Material = Enum.Material.SmoothPlastic
    boxFrontLeft.Color = Color3.fromRGB(0, 0, 0)
    boxFrontLeft.CanCollide = true
    boxFrontLeft.Parent = mineModel

    local boxFrontRight = Instance.new("Part")
    boxFrontRight.Name = "BoxFrontRight"
    boxFrontRight.Size = Vector3.new(boxSize.X/2 - 10, boxSize.Y, boxThickness)
    boxFrontRight.Position = Vector3.new(baseX + boxSize.X/4 + 5, GROUND_Y + 8, baseZ + boxSize.Z/2)
    boxFrontRight.Anchored = true
    boxFrontRight.Material = Enum.Material.SmoothPlastic
    boxFrontRight.Color = Color3.fromRGB(0, 0, 0)
    boxFrontRight.CanCollide = true
    boxFrontRight.Parent = mineModel

    local boxFrontTop = Instance.new("Part")
    boxFrontTop.Name = "BoxFrontTop"
    boxFrontTop.Size = Vector3.new(20, boxSize.Y/2, boxThickness)
    boxFrontTop.Position = Vector3.new(baseX, GROUND_Y + 18, baseZ + boxSize.Z/2)
    boxFrontTop.Anchored = true
    boxFrontTop.Material = Enum.Material.SmoothPlastic
    boxFrontTop.Color = Color3.fromRGB(0, 0, 0)
    boxFrontTop.CanCollide = false
    boxFrontTop.Parent = mineModel

    -- ===== CAVE FLOOR (rough stone) =====
    local caveFloor = Instance.new("Part")
    caveFloor.Name = "CaveFloor"
    caveFloor.Size = Vector3.new(80, 2, 60)
    caveFloor.Position = Vector3.new(baseX, GROUND_Y - 1, baseZ)
    caveFloor.Anchored = true
    caveFloor.Material = Enum.Material.Rock
    caveFloor.Color = Color3.fromRGB(55, 50, 45)
    caveFloor.Parent = mineModel

    -- ===== CAVE WALLS (irregular rocky walls) =====
    -- Back wall
    for i = 1, 8 do
        local wallSeg = Instance.new("Part")
        wallSeg.Name = "BackWall" .. i
        local height = 12 + math.random() * 6
        local width = 10 + math.random() * 3
        wallSeg.Size = Vector3.new(width, height, 4 + math.random() * 2)
        wallSeg.Position = Vector3.new(baseX - 40 + i * 10 + (math.random() - 0.5) * 3, GROUND_Y + height/2, baseZ - 28)
        wallSeg.Anchored = true
        wallSeg.Material = Enum.Material.Rock
        wallSeg.Color = Color3.fromRGB(60 + math.random(20), 55 + math.random(15), 50 + math.random(10))
        wallSeg.Parent = mineModel
    end

    -- Side walls (full length from back to front)
    for i = 1, 7 do
        for _, side in {-1, 1} do
            local wallSeg = Instance.new("Part")
            wallSeg.Name = "SideWall" .. i .. "_" .. (side == -1 and "L" or "R")
            local height = 12 + math.random() * 5
            wallSeg.Size = Vector3.new(5, height, 10)
            wallSeg.Position = Vector3.new(baseX + side * 40, GROUND_Y + height/2, baseZ - 30 + i * 9)
            wallSeg.Anchored = true
            wallSeg.Material = Enum.Material.Rock
            wallSeg.Color = Color3.fromRGB(55 + math.random(20), 50 + math.random(15), 45 + math.random(10))
            wallSeg.Parent = mineModel
        end
    end

    -- Front wall (with portal opening in center)
    -- Left section of front wall
    local frontWallLeft = Instance.new("Part")
    frontWallLeft.Name = "FrontWallLeft"
    frontWallLeft.Size = Vector3.new(32, 16, 4)
    frontWallLeft.Position = Vector3.new(baseX - 24, GROUND_Y + 8, baseZ + 30)
    frontWallLeft.Anchored = true
    frontWallLeft.Material = Enum.Material.Rock
    frontWallLeft.Color = Color3.fromRGB(60, 55, 50)
    frontWallLeft.Parent = mineModel

    -- Right section of front wall
    local frontWallRight = Instance.new("Part")
    frontWallRight.Name = "FrontWallRight"
    frontWallRight.Size = Vector3.new(32, 16, 4)
    frontWallRight.Position = Vector3.new(baseX + 24, GROUND_Y + 8, baseZ + 30)
    frontWallRight.Anchored = true
    frontWallRight.Material = Enum.Material.Rock
    frontWallRight.Color = Color3.fromRGB(60, 55, 50)
    frontWallRight.Parent = mineModel

    -- Top section above portal
    local frontWallTop = Instance.new("Part")
    frontWallTop.Name = "FrontWallTop"
    frontWallTop.Size = Vector3.new(16, 6, 4)
    frontWallTop.Position = Vector3.new(baseX, GROUND_Y + 13, baseZ + 30)
    frontWallTop.Anchored = true
    frontWallTop.Material = Enum.Material.Rock
    frontWallTop.Color = Color3.fromRGB(60, 55, 50)
    frontWallTop.Parent = mineModel

    -- Portal frame decoration
    local portalFrameLeft = Instance.new("Part")
    portalFrameLeft.Name = "PortalFrameLeft"
    portalFrameLeft.Size = Vector3.new(1.5, 10, 1.5)
    portalFrameLeft.Position = Vector3.new(baseX - 7, GROUND_Y + 5, baseZ + 28)
    portalFrameLeft.Anchored = true
    portalFrameLeft.Material = Enum.Material.Cobblestone
    portalFrameLeft.Color = Color3.fromRGB(80, 75, 70)
    portalFrameLeft.Parent = mineModel

    local portalFrameRight = Instance.new("Part")
    portalFrameRight.Name = "PortalFrameRight"
    portalFrameRight.Size = Vector3.new(1.5, 10, 1.5)
    portalFrameRight.Position = Vector3.new(baseX + 7, GROUND_Y + 5, baseZ + 28)
    portalFrameRight.Anchored = true
    portalFrameRight.Material = Enum.Material.Cobblestone
    portalFrameRight.Color = Color3.fromRGB(80, 75, 70)
    portalFrameRight.Parent = mineModel

    local portalFrameTop = Instance.new("Part")
    portalFrameTop.Name = "PortalFrameTop"
    portalFrameTop.Size = Vector3.new(16, 1.5, 1.5)
    portalFrameTop.Position = Vector3.new(baseX, GROUND_Y + 10, baseZ + 28)
    portalFrameTop.Anchored = true
    portalFrameTop.Material = Enum.Material.Cobblestone
    portalFrameTop.Color = Color3.fromRGB(80, 75, 70)
    portalFrameTop.Parent = mineModel

    -- ===== CAVE CEILING (stalactites) =====
    local ceiling = Instance.new("Part")
    ceiling.Name = "Ceiling"
    ceiling.Size = Vector3.new(80, 3, 60)
    ceiling.Position = Vector3.new(baseX, GROUND_Y + 16, baseZ)
    ceiling.Anchored = true
    ceiling.Material = Enum.Material.Rock
    ceiling.Color = Color3.fromRGB(45, 40, 35)
    ceiling.Parent = mineModel

    -- Stalactites
    for i = 1, 20 do
        local stalactite = Instance.new("Part")
        stalactite.Name = "Stalactite" .. i
        local len = 1 + math.random() * 3
        stalactite.Size = Vector3.new(0.5 + math.random() * 0.5, len, 0.5 + math.random() * 0.5)
        stalactite.Position = Vector3.new(
            baseX - 35 + math.random() * 70,
            GROUND_Y + 14.5 - len/2,
            baseZ - 25 + math.random() * 50
        )
        stalactite.Anchored = true
        stalactite.Material = Enum.Material.Rock
        stalactite.Color = Color3.fromRGB(50, 45, 40)
        stalactite.Parent = mineModel
    end

    -- ===== SUPPORT BEAMS =====
    for i = 1, 4 do
        local xPos = baseX - 30 + i * 15
        -- Vertical beams
        for _, zOff in {-12, 12} do
            local vBeam = Instance.new("Part")
            vBeam.Size = Vector3.new(1, 14, 1)
            vBeam.Position = Vector3.new(xPos, GROUND_Y + 7, baseZ + zOff)
            vBeam.Anchored = true
            vBeam.Material = Enum.Material.Wood
            vBeam.Color = Color3.fromRGB(80, 55, 35)
            vBeam.Parent = mineModel
        end
        -- Horizontal beam
        local hBeam = Instance.new("Part")
        hBeam.Size = Vector3.new(1, 1, 26)
        hBeam.Position = Vector3.new(xPos, GROUND_Y + 13.5, baseZ)
        hBeam.Anchored = true
        hBeam.Material = Enum.Material.Wood
        hBeam.Color = Color3.fromRGB(80, 55, 35)
        hBeam.Parent = mineModel
    end

    -- ===== MINECART TRACKS REMOVED =====
    -- (Removed minecart tracks and minecart to create open floor space)
    -- Small decorative minecart placed against back wall instead
    local decorativeCart = Instance.new("Part")
    decorativeCart.Name = "DecorativeMinecart"
    decorativeCart.Size = Vector3.new(2.5, 1.5, 3)
    decorativeCart.Position = Vector3.new(baseX + 30, GROUND_Y + 0.8, baseZ - 25)
    decorativeCart.Anchored = true
    decorativeCart.Material = Enum.Material.Metal
    decorativeCart.Color = Color3.fromRGB(80, 75, 70)
    decorativeCart.Parent = mineModel

    -- ===== LIGHTING (dim cave with torch spots) =====
    for i = 1, 6 do
        local torchPos = Vector3.new(baseX - 30 + i * 12, GROUND_Y + 5, baseZ - 18)
        createTorch(mineModel, torchPos)
        createTorch(mineModel, torchPos + Vector3.new(0, 0, 36))
    end

    -- ========== STATION 1: ORE VEIN (far left of cave) ==========
    local oreVeinPos = GoldMineState.positions.oreVein

    -- Large rocky ore deposit
    local oreVeinBase = Instance.new("Part")
    oreVeinBase.Name = "OreVeinBase"
    oreVeinBase.Size = Vector3.new(10, 8, 6)
    oreVeinBase.Position = oreVeinPos + Vector3.new(0, 4, 0)
    oreVeinBase.Anchored = true
    oreVeinBase.Material = Enum.Material.Rock
    oreVeinBase.Color = Color3.fromRGB(65, 60, 55)
    oreVeinBase.Parent = mineModel

    -- Gold veins running through the rock (on +X side, facing into room)
    for i = 1, 8 do
        local goldVein = Instance.new("Part")
        goldVein.Name = "GoldVein" .. i
        goldVein.Size = Vector3.new(0.4, 0.6 + math.random() * 0.4, 1.5 + math.random())
        goldVein.Position = oreVeinPos + Vector3.new(
            5 + math.random() * 0.5,  -- On +X face (room-facing side)
            1 + math.random() * 5,
            -2 + math.random() * 4
        )
        goldVein.Anchored = true
        goldVein.Material = Enum.Material.Neon
        goldVein.Color = Color3.fromRGB(255, 200, 50)
        goldVein.Parent = mineModel
    end

    -- Glowing gold effect
    local goldGlow = Instance.new("PointLight")
    goldGlow.Color = Color3.fromRGB(255, 200, 50)
    goldGlow.Brightness = 0.8
    goldGlow.Range = 15
    goldGlow.Parent = oreVeinBase

    -- Pickaxes on rack
    local pickaxeRack = Instance.new("Part")
    pickaxeRack.Size = Vector3.new(4, 3, 0.5)
    pickaxeRack.Position = oreVeinPos + Vector3.new(7, 2, 0)
    pickaxeRack.Anchored = true
    pickaxeRack.Material = Enum.Material.Wood
    pickaxeRack.Color = Color3.fromRGB(80, 55, 35)
    pickaxeRack.Parent = mineModel

    createSign(mineModel, "ORE VEIN", oreVeinPos + Vector3.new(6, 9, 0), Vector3.new(0.3, 1.5, 5))  -- On +X side, facing into room

    -- INTERACTION: Mine Ore
    createInteraction(oreVeinBase, "Mine Ore", "Gold Vein", 1, function(player)
        local pickaxeLevel = GoldMineState.equipment.pickaxeLevel
        local stats = getPickaxeStats(pickaxeLevel)
        local currentOre = getPlayerOre(player)
        local maxOre = 10 + (pickaxeLevel * 5) -- Carry capacity also scales with pickaxe level

        if currentOre >= maxOre then
            print(string.format("[GoldMine] %s: Inventory full! Take ore to smelter. (%d/%d)", player.Name, currentOre, maxOre))
            return
        end

        -- Apply production bonuses from Town Hall (gems, building levels, research)
        local baseOre = stats.orePerSwing
        local productionMultiplier = 1.0
        if TownHallState and calculateTotalBonuses then
            local bonuses = calculateTotalBonuses()
            productionMultiplier = bonuses.production.goldMine or 1.0
        end
        local oreGained = math.floor(baseOre * productionMultiplier)
        local newOre = math.min(currentOre + oreGained, maxOre)
        setPlayerOre(player, newOre)
        addMineXP(5)

        local bonusText = productionMultiplier > 1.0 and string.format(" (%.0f%% bonus!)", (productionMultiplier - 1) * 100) or ""
        print(string.format("[GoldMine] %s mined %d ore! (Lv%d Pickaxe)%s Carrying: %d/%d",
            player.Name, newOre - currentOre, pickaxeLevel, bonusText, newOre, maxOre))

        -- Mining sparkle effect
        local sparkle = Instance.new("ParticleEmitter")
        sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
        sparkle.Size = NumberSequence.new(0.4)
        sparkle.Lifetime = NumberRange.new(0.3, 0.6)
        sparkle.Rate = 40
        sparkle.Speed = NumberRange.new(4, 8)
        sparkle.Parent = oreVeinBase
        task.delay(0.5, function() sparkle:Destroy() end)
    end, true) -- allowVisitors: visitors can mine ore for the owner

    -- ========== STATION 2: SMELTER (center of cave) ==========
    local smelterPos = GoldMineState.positions.smelter

    -- Smelter base platform
    local smelterBase = Instance.new("Part")
    smelterBase.Name = "SmelterBase"
    smelterBase.Size = Vector3.new(10, 2, 8)
    smelterBase.Position = smelterPos + Vector3.new(0, 1, 0)
    smelterBase.Anchored = true
    smelterBase.Material = Enum.Material.Cobblestone
    smelterBase.Color = Color3.fromRGB(70, 65, 60)
    smelterBase.Parent = mineModel

    -- Main smelter furnace
    local smelterFurnace = Instance.new("Part")
    smelterFurnace.Name = "SmelterFurnace"
    smelterFurnace.Size = Vector3.new(6, 6, 5)
    smelterFurnace.Position = smelterPos + Vector3.new(0, 5, 0)
    smelterFurnace.Anchored = true
    smelterFurnace.Material = Enum.Material.Brick
    smelterFurnace.Color = Color3.fromRGB(140, 80, 55)
    smelterFurnace.Parent = mineModel

    -- Ore input hopper
    local inputHopper = Instance.new("Part")
    inputHopper.Name = "InputHopper"
    inputHopper.Size = Vector3.new(3, 2, 3)
    inputHopper.Position = smelterPos + Vector3.new(-5, 4, 0)
    inputHopper.Anchored = true
    inputHopper.Material = Enum.Material.Metal
    inputHopper.Color = Color3.fromRGB(90, 85, 80)
    inputHopper.Parent = mineModel

    -- Fire opening (now faces forward, toward player area at +Z)
    local fireOpening = Instance.new("Part")
    fireOpening.Name = "FireOpening"
    fireOpening.Size = Vector3.new(2, 2.5, 1)
    fireOpening.Position = smelterPos + Vector3.new(0, 3.5, 3)  -- Front of smelter
    fireOpening.Anchored = true
    fireOpening.Material = Enum.Material.Neon
    fireOpening.Color = Color3.fromRGB(255, 100, 20)
    fireOpening.Parent = mineModel

    local fire = Instance.new("Fire")
    fire.Size = 4
    fire.Heat = 8
    fire.Parent = fireOpening

    -- Chimney with smoke (against back wall)
    local chimney = Instance.new("Part")
    chimney.Name = "Chimney"
    chimney.Size = Vector3.new(2, 5, 2)
    chimney.Position = smelterPos + Vector3.new(0, 10.5, -2)  -- Back of smelter
    chimney.Anchored = true
    chimney.Material = Enum.Material.Brick
    chimney.Color = Color3.fromRGB(110, 65, 45)
    chimney.Parent = mineModel

    local smoke = Instance.new("Smoke")
    smoke.Size = 4
    smoke.Opacity = 0.4
    smoke.RiseVelocity = 6
    smoke.Parent = chimney

    -- Gold output tray (positioned to right side, toward gold chest)
    local outputTray = Instance.new("Part")
    outputTray.Name = "OutputTray"
    outputTray.Size = Vector3.new(3, 1, 2)
    outputTray.Position = smelterPos + Vector3.new(6, 2.5, 0)  -- Right side toward chest
    outputTray.Anchored = true
    outputTray.Material = Enum.Material.Metal
    outputTray.Color = Color3.fromRGB(180, 160, 50)
    outputTray.Parent = mineModel

    -- ===== VISUAL GOLD BAR SYSTEM =====
    -- Create container for visual gold bars
    local goldBarContainer = Instance.new("Folder")
    goldBarContainer.Name = "GoldBars"
    goldBarContainer.Parent = mineModel

    -- Store the gold bar parts for easy access
    local visualGoldBars = {}
    local MAX_VISIBLE_BARS = 25  -- Show up to 25 individual gold bars

    -- Function to update visual gold bars based on smelterGold amount (1 bar = 1 gold)
    local function updateGoldBarVisuals()
        local barsToShow = math.min(GoldMineState.smelterGold, MAX_VISIBLE_BARS)

        -- Create or show bars as needed
        for i = 1, MAX_VISIBLE_BARS do
            if not visualGoldBars[i] then
                -- Create new gold bar
                local bar = Instance.new("Part")
                bar.Name = "GoldBar" .. i
                bar.Size = Vector3.new(0.6, 0.3, 0.4)
                -- Stack bars in a neat grid (5 columns, 5 rows)
                local row = math.floor((i - 1) / 5)
                local col = (i - 1) % 5
                bar.Position = smelterPos + Vector3.new(4 + col * 0.45, 3.2 + row * 0.35, -0.8 + (i % 2) * 0.25)
                bar.Anchored = true
                bar.Material = Enum.Material.Metal
                bar.Color = Color3.fromRGB(255, 200, 50)
                bar.CanCollide = false
                bar.Parent = goldBarContainer
                visualGoldBars[i] = bar

                -- Add gold shine effect
                local shine = Instance.new("SurfaceLight")
                shine.Face = Enum.NormalId.Top
                shine.Brightness = 0.5
                shine.Color = Color3.fromRGB(255, 220, 100)
                shine.Parent = bar
            end

            -- Show or hide based on count (1 bar = 1 gold)
            visualGoldBars[i].Transparency = (i <= barsToShow) and 0 or 1
        end
    end

    -- Store the update function in state for access from worker loops
    GoldMineState.updateGoldBarVisuals = updateGoldBarVisuals

    -- ===== SMELTER PROGRESS BAR UI =====
    local smelterBillboard = Instance.new("BillboardGui")
    smelterBillboard.Name = "SmelterStatus"
    smelterBillboard.Size = UDim2.new(8, 0, 2, 0)
    smelterBillboard.StudsOffset = Vector3.new(0, 6, 3)
    smelterBillboard.AlwaysOnTop = true
    smelterBillboard.Parent = smelterFurnace

    local smelterTitle = Instance.new("TextLabel")
    smelterTitle.Name = "Title"
    smelterTitle.Size = UDim2.new(1, 0, 0.4, 0)
    smelterTitle.Position = UDim2.new(0, 0, 0, 0)
    smelterTitle.BackgroundTransparency = 1
    smelterTitle.Text = "SMELTER"
    smelterTitle.TextColor3 = Color3.fromRGB(255, 200, 100)
    smelterTitle.TextStrokeTransparency = 0.3
    smelterTitle.TextScaled = true
    smelterTitle.Font = Enum.Font.GothamBold
    smelterTitle.Parent = smelterBillboard

    local progressFrame = Instance.new("Frame")
    progressFrame.Name = "ProgressFrame"
    progressFrame.Size = UDim2.new(0.8, 0, 0.2, 0)
    progressFrame.Position = UDim2.new(0.1, 0, 0.4, 0)
    progressFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    progressFrame.BorderSizePixel = 2
    progressFrame.BorderColor3 = Color3.fromRGB(100, 100, 100)
    progressFrame.Parent = smelterBillboard

    local progressBar = Instance.new("Frame")
    progressBar.Name = "ProgressBar"
    progressBar.Size = UDim2.new(0, 0, 1, 0)
    progressBar.Position = UDim2.new(0, 0, 0, 0)
    progressBar.BackgroundColor3 = Color3.fromRGB(255, 150, 50)
    progressBar.BorderSizePixel = 0
    progressBar.Parent = progressFrame

    local statusText = Instance.new("TextLabel")
    statusText.Name = "StatusText"
    statusText.Size = UDim2.new(1, 0, 0.35, 0)
    statusText.Position = UDim2.new(0, 0, 0.65, 0)
    statusText.BackgroundTransparency = 1
    statusText.Text = "Idle - Waiting for ore"
    statusText.TextColor3 = Color3.fromRGB(200, 200, 200)
    statusText.TextStrokeTransparency = 0.5
    statusText.TextScaled = true
    statusText.Font = Enum.Font.Gotham
    statusText.Parent = smelterBillboard

    -- Function to update smelter UI
    local function updateSmelterUI(status, progress)
        statusText.Text = status
        progressBar.Size = UDim2.new(progress, 0, 1, 0)
        if progress > 0 then
            progressBar.BackgroundColor3 = Color3.fromRGB(255, 150, 50)
        end
    end

    -- Store for access from worker loops
    GoldMineState.updateSmelterUI = updateSmelterUI

    -- ===== INDEPENDENT SMELTER PROCESSING LOOP =====
    -- Runs continuously, processes ore queue one at a time
    -- Progress bar fills 0→100% for EACH ore
    task.spawn(function()
        while true do
            if GoldMineState.smelterOre > 0 then
                -- Get current smelter stats (rechecks each ore for live upgrades)
                local smelterStats = getSmelterStats(GoldMineState.equipment.smelterLevel)
                local baseGoldPerOre = smelterStats.goldPerOre
                local baseSmeltTime = smelterStats.smeltTime

                -- Apply production and speed bonuses from Town Hall
                local productionMultiplier = 1.0
                local speedMultiplier = 1.0
                if TownHallState and calculateTotalBonuses then
                    local bonuses = calculateTotalBonuses()
                    productionMultiplier = bonuses.production.smelter or 1.0
                    speedMultiplier = bonuses.speed.smelter or 1.0
                end
                local goldPerOre = math.floor(baseGoldPerOre * productionMultiplier)
                local smeltTime = baseSmeltTime / speedMultiplier -- faster = divide time

                -- Process one ore at a time
                while GoldMineState.smelterOre > 0 do
                    -- Recheck stats each ore (in case player upgrades mid-batch)
                    smelterStats = getSmelterStats(GoldMineState.equipment.smelterLevel)
                    baseGoldPerOre = smelterStats.goldPerOre
                    baseSmeltTime = smelterStats.smeltTime

                    -- Re-apply bonuses
                    if TownHallState and calculateTotalBonuses then
                        local bonuses = calculateTotalBonuses()
                        productionMultiplier = bonuses.production.smelter or 1.0
                        speedMultiplier = bonuses.speed.smelter or 1.0
                    end
                    goldPerOre = math.floor(baseGoldPerOre * productionMultiplier)
                    smeltTime = baseSmeltTime / speedMultiplier

                    local oreRemaining = GoldMineState.smelterOre

                    -- Animate progress bar from 0 to 100% for this single ore
                    local steps = 20  -- Number of progress updates
                    local stepTime = smeltTime / steps

                    for step = 1, steps do
                        local progress = step / steps
                        updateSmelterUI(
                            string.format("Smelting... %d ore queued | Lv%d: %dg/ore",
                                oreRemaining, GoldMineState.equipment.smelterLevel, goldPerOre),
                            progress
                        )
                        task.wait(stepTime)
                    end

                    -- Convert one ore to gold
                    GoldMineState.smelterOre = GoldMineState.smelterOre - 1
                    GoldMineState.smelterGold = GoldMineState.smelterGold + goldPerOre

                    -- Update gold bar visuals immediately
                    updateGoldBarVisuals()

                    -- Brief flash at 100% before resetting for next ore
                    updateSmelterUI(
                        string.format("+%d gold! (%d ore left)", goldPerOre, GoldMineState.smelterOre),
                        1
                    )
                    task.wait(0.2)

                    print(string.format("[Smelter Lv%d] 1 ore → +%d gold (Queue: %d, Ready: %d)",
                        GoldMineState.equipment.smelterLevel, goldPerOre, GoldMineState.smelterOre, GoldMineState.smelterGold))
                end

                -- Done processing batch
                updateSmelterUI(
                    string.format("Ready: %d gold | Idle", GoldMineState.smelterGold),
                    0
                )
            else
                -- Idle state
                local smelterStats = getSmelterStats(GoldMineState.equipment.smelterLevel)
                if GoldMineState.smelterGold > 0 then
                    updateSmelterUI(
                        string.format("Ready: %d gold | Lv%d Smelter", GoldMineState.smelterGold, GoldMineState.equipment.smelterLevel),
                        0
                    )
                else
                    updateSmelterUI(string.format("Idle | Lv%d: %dg/ore, %.1fs",
                        GoldMineState.equipment.smelterLevel, smelterStats.goldPerOre, smelterStats.smeltTime), 0)
                end
                task.wait(1) -- Check for ore every second
            end
        end
    end)

    createSign(mineModel, "SMELTER", smelterPos + Vector3.new(0, 9, 4), Vector3.new(5, 1.5, 0.3))

    -- WALK-THROUGH: Deposit Ore (front of smelter - player approach side)
    local smelterInputTrigger = Instance.new("Part")
    smelterInputTrigger.Name = "SmelterInputTrigger"
    smelterInputTrigger.Size = Vector3.new(8, 6, 8)
    smelterInputTrigger.Position = smelterPos + Vector3.new(0, 3, 5)  -- Front of smelter
    smelterInputTrigger.Anchored = true
    smelterInputTrigger.Transparency = 1
    smelterInputTrigger.CanCollide = false
    smelterInputTrigger.Parent = mineModel

    local inputDebounce = {}
    smelterInputTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if inputDebounce[player.UserId] then return end

        local currentOre = getPlayerOre(player)
        if currentOre > 0 then
            inputDebounce[player.UserId] = true

            -- Remove ore from player
            setPlayerOre(player, 0)
            updatePlayerOreVisual(player, 0) -- Remove visual

            -- Add to smelter queue (independent smelter loop will process it)
            GoldMineState.smelterOre = GoldMineState.smelterOre + currentOre
            addMineXP(currentOre * 2)
            print(string.format("[GoldMine] %s dropped %d ore into smelter (Queue: %d)",
                player.Name, currentOre, GoldMineState.smelterOre))

            -- Fire burst effect
            local burst = Instance.new("ParticleEmitter")
            burst.Color = ColorSequence.new(Color3.fromRGB(255, 150, 50))
            burst.Size = NumberSequence.new(0.8)
            burst.Lifetime = NumberRange.new(0.5, 1)
            burst.Rate = 50
            burst.Speed = NumberRange.new(5, 10)
            burst.Parent = fireOpening
            task.delay(0.8, function() burst:Destroy() end)

            task.delay(1.5, function() inputDebounce[player.UserId] = nil end)
        end
    end)

    -- WALK-THROUGH: Pick up Gold Bars (right side of smelter, toward chest)
    local smelterOutputTrigger = Instance.new("Part")
    smelterOutputTrigger.Name = "SmelterOutputTrigger"
    smelterOutputTrigger.Size = Vector3.new(8, 6, 8)
    smelterOutputTrigger.Position = smelterPos + Vector3.new(7, 3, 0)  -- Right side toward chest
    smelterOutputTrigger.Anchored = true
    smelterOutputTrigger.Transparency = 1
    smelterOutputTrigger.CanCollide = false
    smelterOutputTrigger.Parent = mineModel

    local outputDebounce = {}
    smelterOutputTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if outputDebounce[player.UserId] then return end

        -- Check if player is carrying gold (limit: 10 per trip)
        local currentPlayerGold = GoldMineState.playerGold and GoldMineState.playerGold[player.UserId] or 0
        local maxCarry = 10  -- Player can carry 10 gold per trip

        if GoldMineState.smelterGold > 0 and currentPlayerGold < maxCarry then
            outputDebounce[player.UserId] = true

            -- Pick up gold (up to carry limit)
            local canPickUp = math.min(GoldMineState.smelterGold, maxCarry - currentPlayerGold)
            GoldMineState.smelterGold = GoldMineState.smelterGold - canPickUp

            -- Track player's carried gold
            GoldMineState.playerGold = GoldMineState.playerGold or {}
            GoldMineState.playerGold[player.UserId] = currentPlayerGold + canPickUp

            -- Update smelter UI
            if GoldMineState.updateSmelterUI then
                if GoldMineState.smelterGold > 0 then
                    GoldMineState.updateSmelterUI(
                        string.format("Ready: %d gold | Waiting for ore", GoldMineState.smelterGold),
                        0
                    )
                else
                    GoldMineState.updateSmelterUI("Idle - Waiting for ore", 0)
                end
            end

            -- Add visual gold bars on player's back
            setNPCCarrying(character, "gold", math.min(5, canPickUp))

            -- Update visual gold bars at smelter
            if GoldMineState.updateGoldBarVisuals then
                GoldMineState.updateGoldBarVisuals()
            end

            print(string.format("[GoldMine] %s picked up %d gold! (Carrying: %d/%d)",
                player.Name, canPickUp, GoldMineState.playerGold[player.UserId], maxCarry))

            task.delay(1, function() outputDebounce[player.UserId] = nil end)
        end
    end)

    -- ========== STATION 3: GOLD CHEST (far right of cave) ==========
    -- Chest faces toward room center (-Z direction) so players can see it from the entrance
    local chestPos = GoldMineState.positions.goldChest

    local goldChest = Instance.new("Part")
    goldChest.Name = "GoldChest"
    goldChest.Size = Vector3.new(5, 3, 3)
    goldChest.Anchored = true
    goldChest.Material = Enum.Material.Wood
    goldChest.Color = Color3.fromRGB(100, 70, 45)
    -- Face toward room center (-Z direction, rotated 180 degrees from original)
    local chestCenterPos = chestPos + Vector3.new(0, 1.5, 0)
    goldChest.CFrame = CFrame.lookAt(chestCenterPos, chestCenterPos + Vector3.new(0, 0, -10))
    goldChest.Parent = mineModel

    local chestLid = Instance.new("Part")
    chestLid.Size = Vector3.new(5.2, 0.8, 3.2)
    chestLid.Anchored = true
    chestLid.Material = Enum.Material.Wood
    chestLid.Color = Color3.fromRGB(90, 60, 40)
    chestLid.CFrame = goldChest.CFrame * CFrame.new(0, 1.9, 0)
    chestLid.Parent = mineModel

    -- Gold trim and lock (on front of chest, facing -Z toward room center)
    local goldTrim = Instance.new("Part")
    goldTrim.Size = Vector3.new(5.5, 0.4, 0.4)
    goldTrim.Anchored = true
    goldTrim.Material = Enum.Material.Metal
    goldTrim.Color = Color3.fromRGB(220, 180, 50)
    goldTrim.CFrame = goldChest.CFrame * CFrame.new(0, 0, -1.6)
    goldTrim.Parent = mineModel

    -- Visible gold inside (decorative)
    -- ===== VISUAL GOLD COINS IN CHEST =====
    local chestGoldContainer = Instance.new("Folder")
    chestGoldContainer.Name = "ChestGoldVisuals"
    chestGoldContainer.Parent = mineModel

    local visualChestGold = {}
    local MAX_CHEST_GOLD_VISUALS = 15

    -- Function to update visual gold in chest
    local function updateChestGoldVisuals()
        local goldToShow = math.min(math.floor(GoldMineState.chestGold / 10), MAX_CHEST_GOLD_VISUALS)

        for i = 1, MAX_CHEST_GOLD_VISUALS do
            if not visualChestGold[i] then
                -- Create gold coin/bar
                local coin = Instance.new("Part")
                coin.Name = "ChestGold" .. i
                coin.Shape = (i % 3 == 0) and Enum.PartType.Cylinder or Enum.PartType.Block
                coin.Size = (i % 3 == 0) and Vector3.new(0.2, 0.6, 0.6) or Vector3.new(0.7, 0.35, 0.35)
                local row = math.floor((i - 1) / 5)
                local col = (i - 1) % 5
                coin.Position = chestPos + Vector3.new(-1.5 + col * 0.7, 1.8 + row * 0.4, -0.5 + (i % 2) * 0.4)
                if i % 3 == 0 then
                    coin.Orientation = Vector3.new(0, 0, 90)
                end
                coin.Anchored = true
                coin.CanCollide = false
                coin.Material = Enum.Material.Metal
                coin.Color = Color3.fromRGB(255, 200, 50)
                coin.Parent = chestGoldContainer
                visualChestGold[i] = coin
            end

            visualChestGold[i].Transparency = (i <= goldToShow) and 0 or 1
        end
    end

    -- Store function in state
    GoldMineState.updateChestGoldVisuals = updateChestGoldVisuals

    -- Sign above chest - faces forward toward entrance (+Z)
    local chestSignPos = chestPos + Vector3.new(0, 5, 2)
    local chestSign = Instance.new("Part")
    chestSign.Name = "GoldChestSign"
    chestSign.Size = Vector3.new(5, 1.5, 0.3)
    chestSign.Anchored = true
    chestSign.Material = Enum.Material.Wood
    chestSign.Color = Color3.fromRGB(139, 90, 43)
    chestSign.CFrame = CFrame.lookAt(chestSignPos, chestSignPos + Vector3.new(0, 0, 10))
    chestSign.Parent = mineModel

    local chestSignGui = Instance.new("SurfaceGui")
    chestSignGui.Face = Enum.NormalId.Back -- Text on front face (facing forward)
    chestSignGui.Parent = chestSign

    local chestSignLabel = Instance.new("TextLabel")
    chestSignLabel.Size = UDim2.new(1, 0, 1, 0)
    chestSignLabel.BackgroundTransparency = 1
    chestSignLabel.Text = "GOLD CHEST"
    chestSignLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    chestSignLabel.TextScaled = true
    chestSignLabel.Font = Enum.Font.GothamBold
    chestSignLabel.Parent = chestSignGui
    makeSignDoubleSided(chestSign)

    -- Gold glow (brightness based on amount)
    local chestGlow = Instance.new("PointLight")
    chestGlow.Color = Color3.fromRGB(255, 200, 50)
    chestGlow.Brightness = 1
    chestGlow.Range = 12
    chestGlow.Parent = goldChest

    -- WALK-THROUGH: Deposit & Collect Gold (just walk by)
    local chestTrigger = Instance.new("Part")
    chestTrigger.Name = "ChestTrigger"
    chestTrigger.Size = Vector3.new(8, 5, 8)
    chestTrigger.Position = chestPos + Vector3.new(0, 2.5, 0)
    chestTrigger.Anchored = true
    chestTrigger.Transparency = 1
    chestTrigger.CanCollide = false
    chestTrigger.Parent = mineModel

    local chestDebounce = {}
    chestTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if chestDebounce[player.UserId] then return end

        -- Check if player is carrying gold bars
        GoldMineState.playerGold = GoldMineState.playerGold or {}
        local playerCarriedGold = GoldMineState.playerGold[player.UserId] or 0

        if playerCarriedGold > 0 then
            -- DEPOSIT: Player is carrying gold, drop it in chest
            chestDebounce[player.UserId] = true

            local goldToDeposit = playerCarriedGold
            GoldMineState.playerGold[player.UserId] = 0

            -- Remove visual gold from player
            local existingBackpack = character:FindFirstChild("CarriedItem")
            if existingBackpack then existingBackpack:Destroy() end

            -- Reward player immediately for depositing
            rewardPlayer(player, "gold", goldToDeposit, "GoldMine")
            addMineXP(goldToDeposit)
            print(string.format("[GoldMine] %s deposited %d gold bars → Rewarded!", player.Name, goldToDeposit))

            -- Update chest visuals (show gold briefly before being claimed)
            GoldMineState.chestGold = GoldMineState.chestGold + goldToDeposit
            updateChestGoldVisuals()

            -- Gold deposit sparkle
            local sparkle = Instance.new("ParticleEmitter")
            sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
            sparkle.Size = NumberSequence.new(0.5)
            sparkle.Lifetime = NumberRange.new(0.5, 1)
            sparkle.Rate = 40
            sparkle.Speed = NumberRange.new(3, 6)
            sparkle.SpreadAngle = Vector2.new(60, 60)
            sparkle.Parent = goldChest
            task.delay(0.8, function() sparkle:Destroy() end)

            -- Clear the chest visually after a moment (gold was claimed)
            task.delay(0.5, function()
                GoldMineState.chestGold = 0
                updateChestGoldVisuals()
            end)

            task.delay(1, function() chestDebounce[player.UserId] = nil end)

        elseif GoldMineState.chestGold > 0 then
            -- COLLECT: Chest has gold from NPC collectors, give to player
            chestDebounce[player.UserId] = true

            local gold = GoldMineState.chestGold
            GoldMineState.chestGold = 0
            rewardPlayer(player, "gold", gold, "GoldMine")
            addMineXP(10)
            print(string.format("[GoldMine] %s collected %d gold from chest!", player.Name, gold))

            -- Update visuals
            updateChestGoldVisuals()

            -- Gold sparkle
            local sparkle = Instance.new("ParticleEmitter")
            sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
            sparkle.Size = NumberSequence.new(0.5)
            sparkle.Lifetime = NumberRange.new(0.5, 1)
            sparkle.Rate = 30
            sparkle.Speed = NumberRange.new(3, 6)
            sparkle.Parent = goldChest
            task.delay(0.6, function() sparkle:Destroy() end)

            task.delay(2, function() chestDebounce[player.UserId] = nil end)
        end
    end)

    -- ========== HIRE MINERS STATION (LEFT side of entrance portal) ==========
    -- FLOOR LAYOUT: Sign against entrance wall (+Z), workers in front of sign, table at front
    -- Player approaches from inside room (from -Z) and sees sign on the wall
    local hireMinerPos = GoldMineState.positions.hireMiner

    -- Hiring stand is centered at hireMinerPos.X (left of portal)
    -- Layout: Sign AGAINST entrance wall (high Z), workers in front of sign, table in front of workers
    local minerStandX = hireMinerPos.X  -- X = -20 (left of portal center)

    -- Wall sign (AGAINST entrance wall at baseZ + 28, facing -Z into room)
    local minerWallSign = Instance.new("Part")
    minerWallSign.Name = "MinerWallSign"
    minerWallSign.Size = Vector3.new(8, 3, 0.5)  -- 8 wide (X), 3 tall (Y), 0.5 thin (Z)
    minerWallSign.Anchored = true
    minerWallSign.Material = Enum.Material.Wood
    minerWallSign.Color = Color3.fromRGB(139, 90, 43)
    -- Position against entrance wall (baseZ + 28 minus half thickness)
    minerWallSign.Position = Vector3.new(minerStandX, GROUND_Y + 6, baseZ + 27.75)
    minerWallSign.Parent = mineModel

    local minerSignGui = Instance.new("SurfaceGui")
    minerSignGui.Face = Enum.NormalId.Front  -- Front face points toward -Z (into room)
    minerSignGui.Parent = minerWallSign

    local minerSignLabel = Instance.new("TextLabel")
    minerSignLabel.Size = UDim2.new(1, 0, 1, 0)
    minerSignLabel.BackgroundTransparency = 1
    minerSignLabel.Text = "HIRE MINERS"
    minerSignLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    minerSignLabel.TextScaled = true
    minerSignLabel.Font = Enum.Font.GothamBold
    minerSignLabel.Parent = minerSignGui

    -- Store reference for updating later
    GoldMineState.minerSign = minerSignLabel
    makeSignDoubleSided(minerWallSign)

    -- Table/counter in front of workers (player approaches from -Z)
    local minerTable = Instance.new("Part")
    minerTable.Name = "MinerHiringTable"
    minerTable.Size = Vector3.new(8, 1, 2)  -- 8 wide (X), 1 tall (Y), 2 deep (Z)
    minerTable.Anchored = true
    minerTable.Material = Enum.Material.Wood
    minerTable.Color = Color3.fromRGB(90, 65, 45)
    -- Table is in front of workers (lower Z = toward room interior)
    minerTable.Position = Vector3.new(minerStandX, GROUND_Y + 1.5, baseZ + 21)
    minerTable.Parent = mineModel

    -- Table legs
    for i = -1, 1, 2 do  -- Left/right of table (X direction)
        for j = -1, 1, 2 do  -- Front/back of table (Z direction)
            local leg = Instance.new("Part")
            leg.Name = "TableLeg"
            leg.Size = Vector3.new(0.3, 1, 0.3)
            leg.Anchored = true
            leg.Material = Enum.Material.Wood
            leg.Color = Color3.fromRGB(70, 50, 35)
            leg.Position = Vector3.new(minerStandX + i * 3.5, GROUND_Y + 0.5, baseZ + 21 + j * 0.7)
            leg.Parent = mineModel
        end
    end

    -- 3 Waiting workers standing between sign and table (spread along X axis)
    GoldMineState.waitingMiners = {}
    for i = 1, 3 do
        -- Workers in front of sign, behind table (at baseZ + 24)
        -- Spread workers along X axis: -3, 0, +3 from minerStandX
        local waitingMinerPos = Vector3.new(minerStandX + (i - 2) * 3, GROUND_Y, baseZ + 24)
        local waitingMiner = createWorkerNPC(
            "WaitingMiner" .. i,
            waitingMinerPos,
            Color3.fromRGB(100, 80, 60),
            "Miner"
        )
        setNPCStatus(waitingMiner, "For hire!")
        waitingMiner.Parent = mineModel
        table.insert(GoldMineState.waitingMiners, waitingMiner)
    end

    -- INTERACTION: Hire Miner (on the table)
    local minerHirePrompt = createInteraction(minerTable, "Hire Miner (1,500g + 300f)", "Hiring Table", 1, function(player)
        -- Check if any waiting workers left at the stand
        if #GoldMineState.waitingMiners == 0 then
            print(string.format("[GoldMine] %s: No workers available to hire!", player.Name))
            notifyPlayer(player, "HireWorker", false, "No miners available to hire!")
            return
        end

        local minerCount = #GoldMineState.miners
        local maxMiners = 3

        if minerCount >= maxMiners then
            print(string.format("[GoldMine] %s: Max miners (3) reached!", player.Name))
            notifyPlayer(player, "HireWorker", false, "Max miners (3) already hired!")
            return
        end

        local cost = MinerCosts[minerCount + 1]
        if not deductPlayerResources(player, {gold = cost.gold, food = cost.food}, "GoldMine") then
            notifyPlayer(player, "HireWorker", false, string.format("Need %dg + %df to hire!", cost.gold, cost.food))
            return
        end
        notifyPlayer(player, "HireWorker", true, "Miner hired!")
        local minerId = minerCount + 1

        -- Remove one waiting worker from the stand (they walk away to work)
        local waitingWorker = table.remove(GoldMineState.waitingMiners, 1)
        if waitingWorker then
            -- Make the waiting worker walk away before destroying
            local workerRoot = waitingWorker:FindFirstChild("HumanoidRootPart") or waitingWorker:FindFirstChild("Torso")
            if workerRoot then
                local walkAwayPos = GoldMineState.positions.workerSpawn + Vector3.new(minerCount * 3, 0, 0)
                walkNPCTo(waitingWorker, walkAwayPos, 6, function()
                    _npcAnimTracks[waitingWorker] = nil
                    waitingWorker:Destroy()
                end)
            else
                _npcAnimTracks[waitingWorker] = nil
                waitingWorker:Destroy()
            end
        end

        -- Update sign if no more waiting workers
        if #GoldMineState.waitingMiners == 0 then
            if GoldMineState.minerSign then
                GoldMineState.minerSign.Text = "FULLY STAFFED"
                GoldMineState.minerSign.TextColor3 = Color3.fromRGB(150, 150, 150)
            end
        end

        -- Create visible miner NPC (spawn at hiring booth so player sees them walk to work)
        local spawnPos = GoldMineState.positions.hireMiner
        local miner = createWorkerNPC(
            "Miner " .. minerId,
            spawnPos,
            Color3.fromRGB(139, 90, 43), -- Brown work clothes
            "Miner"
        )
        miner.Parent = mineModel

        -- Create pickaxe for legacy (box-part) miners only
        -- R15 miners get their pickaxe from addWorkerAccessories (welded to hand)
        local pickaxe, pickaxeHead
        local isR15Miner = miner:FindFirstChild("HumanoidRootPart") ~= nil
        if not isR15Miner then
            pickaxe = Instance.new("Part")
            pickaxe.Name = "Pickaxe"
            pickaxe.Size = Vector3.new(0.2, 2, 0.2)
            pickaxe.Anchored = true
            pickaxe.CanCollide = false
            pickaxe.Material = Enum.Material.Wood
            pickaxe.Color = Color3.fromRGB(100, 70, 45)
            pickaxe.Parent = miner

            pickaxeHead = Instance.new("Part")
            pickaxeHead.Name = "PickaxeHead"
            pickaxeHead.Size = Vector3.new(0.8, 0.3, 0.2)
            pickaxeHead.Anchored = true
            pickaxeHead.CanCollide = false
            pickaxeHead.Material = Enum.Material.Metal
            pickaxeHead.Color = Color3.fromRGB(140, 140, 150)
            pickaxeHead.Parent = miner
        end

        local minerData = {
            npc = miner,
            state = "idle",
            carrying = 0,
            pickaxe = pickaxe,
            pickaxeHead = pickaxeHead,
        }
        table.insert(GoldMineState.miners, minerData)

        -- Function to update pickaxe position relative to miner (legacy only, R15 uses weld)
        local function updatePickaxePosition()
            if isR15Miner then return end -- R15 pickaxe is welded, no manual update needed
            local torso = miner:FindFirstChild("Torso")
            if torso then
                pickaxe.Position = torso.Position + Vector3.new(1, 0.5, 0)
                pickaxeHead.Position = pickaxe.Position + Vector3.new(0.5, 0.8, 0)
            end
        end

        -- Start miner AI loop
        task.spawn(function()
            while minerData.npc and minerData.npc.Parent do
                local cycleComplete = false

                -- Get current miner stats (updates each cycle based on upgrades)
                local minerStats = getMinerStats(GoldMineState.equipment.minerLevel)
                local oreCapacity = minerStats.oreCapacity
                local walkSpeed = minerStats.walkSpeed
                local miningTime = minerStats.miningTime

                -- Walk to ore vein
                minerData.state = "walking_to_ore"
                setNPCStatus(miner, "Walking to ore...")
                local orePos = GoldMineState.positions.oreVein + Vector3.new(math.random(2, 5), 0, math.random(-2, 2))
                walkNPCTo(miner, orePos, walkSpeed, function()
                    -- Mining with visual swing animation
                    minerData.state = "mining"
                    updatePickaxePosition()

                    -- Mine ore with progress display
                    local oreMined = 0
                    for swing = 1, oreCapacity do
                        oreMined = swing
                        setNPCStatus(miner, string.format("Mining %d/%d", oreMined, oreCapacity))

                        -- Rock particle effect
                        local torso = miner:FindFirstChild("UpperTorso") or miner:FindFirstChild("Torso")
                        if torso then
                            local rockParticles = Instance.new("ParticleEmitter")
                            rockParticles.Color = ColorSequence.new(Color3.fromRGB(120, 100, 80))
                            rockParticles.Size = NumberSequence.new(0.3)
                            rockParticles.Lifetime = NumberRange.new(0.3, 0.5)
                            rockParticles.Rate = 20
                            rockParticles.Speed = NumberRange.new(3, 6)
                            rockParticles.SpreadAngle = Vector2.new(30, 30)
                            rockParticles.Parent = torso
                            task.delay(0.4, function() rockParticles:Destroy() end)
                        end
                        task.wait(miningTime)
                    end

                    -- Pick up ore
                    minerData.carrying = oreCapacity
                    setNPCCarrying(miner, "ore", math.min(5, math.ceil(oreCapacity / 5)))
                    setNPCStatus(miner, string.format("Carrying %d ore", oreCapacity))
                    print(string.format("[Miner #%d] Mined %d ore", minerId, oreCapacity))

                    -- Walk to smelter
                    minerData.state = "walking_to_smelter"
                    setNPCStatus(miner, "Delivering ore...")
                    walkNPCTo(miner, GoldMineState.positions.smelter + Vector3.new(-4, 0, 0), walkSpeed, function()
                        -- Deposit ore into smelter queue (don't wait for smelting!)
                        minerData.state = "depositing"
                        setNPCStatus(miner, "Depositing ore...")
                        task.wait(0.5)

                        -- Add ore to smelter queue
                        local oreDeposited = minerData.carrying
                        GoldMineState.smelterOre = GoldMineState.smelterOre + oreDeposited
                        minerData.carrying = 0
                        setNPCCarrying(miner, nil, 0)

                        print(string.format("[Miner #%d] Deposited %d ore (Queue: %d)",
                            minerId, oreDeposited, GoldMineState.smelterOre))

                        -- Immediately go back to mining (don't wait for smelting)
                        minerData.state = "idle"
                        setNPCStatus(miner, "Returning...")
                        cycleComplete = true
                    end)
                end)

                -- Wait for cycle to complete before starting next one
                while not cycleComplete and minerData.npc and minerData.npc.Parent do
                    task.wait(0.5)
                end

                task.wait(1) -- Brief pause between cycles
            end
        end)

        print(string.format("[GoldMine] %s hired Miner #%d for %d gold + %d food!",
            player.Name, minerId, cost.gold, cost.food))
        print(string.format("[GoldMine] Miner #%d will mine ore → deliver to smelter → repeat!", minerId))

        -- Update exterior sign to reflect new production rate
        if GoldMineState.updateExteriorSign then
            GoldMineState.updateExteriorSign()
        end
    end)

    -- Store reference for prompt (needed for disabling when fully staffed)
    GoldMineState.minerPrompt = minerHirePrompt

    -- ========== HIRE COLLECTORS STATION (RIGHT side of entrance portal) ==========
    -- FLOOR LAYOUT: Sign against entrance wall (+Z), workers in front of sign, table at front
    -- Player approaches from inside room (from -Z) and sees sign on the wall
    local hireCollectorPos = GoldMineState.positions.hireCollector

    -- Hiring stand is centered at hireCollectorPos.X (right of portal)
    -- Layout: Sign AGAINST entrance wall (high Z), workers in front of sign, table in front of workers
    local collectorStandX = hireCollectorPos.X  -- X = +20 (right of portal center)

    -- Wall sign (AGAINST entrance wall at baseZ + 28, facing -Z into room)
    local collectorWallSign = Instance.new("Part")
    collectorWallSign.Name = "CollectorWallSign"
    collectorWallSign.Size = Vector3.new(8, 3, 0.5)  -- 8 wide (X), 3 tall (Y), 0.5 thin (Z)
    collectorWallSign.Anchored = true
    collectorWallSign.Material = Enum.Material.Wood
    collectorWallSign.Color = Color3.fromRGB(60, 100, 60)
    -- Position against entrance wall (baseZ + 28 minus half thickness)
    collectorWallSign.Position = Vector3.new(collectorStandX, GROUND_Y + 6, baseZ + 27.75)
    collectorWallSign.Parent = mineModel

    local collectorSignGui = Instance.new("SurfaceGui")
    collectorSignGui.Face = Enum.NormalId.Front  -- Front face points toward -Z (into room)
    collectorSignGui.Parent = collectorWallSign

    local collectorSignLabel = Instance.new("TextLabel")
    collectorSignLabel.Size = UDim2.new(1, 0, 1, 0)
    collectorSignLabel.BackgroundTransparency = 1
    collectorSignLabel.Text = "HIRE COLLECTORS"
    collectorSignLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    collectorSignLabel.TextScaled = true
    collectorSignLabel.Font = Enum.Font.GothamBold
    collectorSignLabel.Parent = collectorSignGui

    -- Store reference for updating later
    GoldMineState.collectorSign = collectorSignLabel
    makeSignDoubleSided(collectorWallSign)

    -- Table/counter in front of workers (player approaches from -Z)
    local collectorTable = Instance.new("Part")
    collectorTable.Name = "CollectorHiringTable"
    collectorTable.Size = Vector3.new(8, 1, 2)  -- 8 wide (X), 1 tall (Y), 2 deep (Z)
    collectorTable.Anchored = true
    collectorTable.Material = Enum.Material.Wood
    collectorTable.Color = Color3.fromRGB(60, 90, 60)
    -- Table is in front of workers (lower Z = toward room interior)
    collectorTable.Position = Vector3.new(collectorStandX, GROUND_Y + 1.5, baseZ + 21)
    collectorTable.Parent = mineModel

    -- Table legs
    for i = -1, 1, 2 do  -- Left/right of table (X direction)
        for j = -1, 1, 2 do  -- Front/back of table (Z direction)
            local leg = Instance.new("Part")
            leg.Name = "TableLeg"
            leg.Size = Vector3.new(0.3, 1, 0.3)
            leg.Anchored = true
            leg.Material = Enum.Material.Wood
            leg.Color = Color3.fromRGB(45, 65, 45)
            leg.Position = Vector3.new(collectorStandX + i * 3.5, GROUND_Y + 0.5, baseZ + 21 + j * 0.7)
            leg.Parent = mineModel
        end
    end

    -- 3 Waiting workers standing between sign and table (spread along X axis)
    GoldMineState.waitingCollectors = {}
    for i = 1, 3 do
        -- Workers in front of sign, behind table (at baseZ + 24)
        -- Spread workers along X axis: -3, 0, +3 from collectorStandX
        local waitingCollectorPos = Vector3.new(collectorStandX + (i - 2) * 3, GROUND_Y, baseZ + 24)
        local waitingCollector = createWorkerNPC(
            "WaitingCollector" .. i,
            waitingCollectorPos,
            Color3.fromRGB(60, 100, 60), -- Green work clothes
            "Collector"
        )
        setNPCStatus(waitingCollector, "For hire!")
        waitingCollector.Parent = mineModel
        table.insert(GoldMineState.waitingCollectors, waitingCollector)
    end

    -- INTERACTION: Hire Collector (on the table)
    local collectorHirePrompt = createInteraction(collectorTable, "Hire Collector (900g + 150f)", "Hiring Table", 1, function(player)
        -- Check if any waiting workers left at the stand
        if #GoldMineState.waitingCollectors == 0 then
            print(string.format("[GoldMine] %s: No collectors available to hire!", player.Name))
            notifyPlayer(player, "HireWorker", false, "No collectors available to hire!")
            return
        end

        local collectorCount = #GoldMineState.collectors
        local maxCollectors = 3

        if collectorCount >= maxCollectors then
            print(string.format("[GoldMine] %s: Max collectors (3) reached!", player.Name))
            notifyPlayer(player, "HireWorker", false, "Max collectors (3) already hired!")
            return
        end

        local cost = CollectorCosts[collectorCount + 1]
        if not deductPlayerResources(player, {gold = cost.gold, food = cost.food}, "GoldMine") then
            notifyPlayer(player, "HireWorker", false, string.format("Need %dg + %df to hire!", cost.gold, cost.food))
            return
        end
        notifyPlayer(player, "HireWorker", true, "Collector hired!")
        local collectorId = collectorCount + 1

        -- Remove one waiting worker from the stand (they walk away to work)
        local waitingWorker = table.remove(GoldMineState.waitingCollectors, 1)
        if waitingWorker then
            -- Make the waiting worker walk away before destroying
            local workerRoot = waitingWorker:FindFirstChild("HumanoidRootPart") or waitingWorker:FindFirstChild("Torso")
            if workerRoot then
                local walkAwayPos = GoldMineState.positions.workerSpawn + Vector3.new(collectorCount * 3 + 10, 0, 0)
                walkNPCTo(waitingWorker, walkAwayPos, 6, function()
                    _npcAnimTracks[waitingWorker] = nil
                    waitingWorker:Destroy()
                end)
            else
                _npcAnimTracks[waitingWorker] = nil
                waitingWorker:Destroy()
            end
        end

        -- Update sign if no more waiting workers
        if #GoldMineState.waitingCollectors == 0 then
            if GoldMineState.collectorSign then
                GoldMineState.collectorSign.Text = "FULLY STAFFED"
                GoldMineState.collectorSign.TextColor3 = Color3.fromRGB(150, 150, 150)
            end
        end

        -- Create visible collector NPC (spawn at hiring booth so player sees them walk to work)
        local spawnPos = GoldMineState.positions.hireCollector
        local collector = createWorkerNPC(
            "Collector " .. collectorId,
            spawnPos,
            Color3.fromRGB(60, 100, 60), -- Green work clothes
            "Collector"
        )
        collector.Parent = mineModel

        -- Store the hiring player for rewards
        local hiringPlayer = player

        local collectorData = {
            npc = collector,
            state = "idle",
            carrying = 0,
            owner = player.UserId,
        }
        table.insert(GoldMineState.collectors, collectorData)

        -- Start collector AI loop
        task.spawn(function()
            setNPCStatus(collector, "Waiting for gold...")

            while collectorData.npc and collectorData.npc.Parent do
                -- Get current collector stats (updates each cycle based on upgrades)
                local collectorStats = getCollectorStats(GoldMineState.equipment.collectorLevel)
                local goldCapacity = collectorStats.goldCapacity
                local walkSpeed = collectorStats.walkSpeed

                -- Check if there's gold ready at the smelter
                if GoldMineState.smelterGold >= 1 then
                    local cycleComplete = false

                    -- Walk to smelter output
                    collectorData.state = "walking_to_smelter"
                    setNPCStatus(collector, "Going to smelter...")
                    walkNPCTo(collector, GoldMineState.positions.smelter + Vector3.new(6, 0, 0), walkSpeed, function()
                        -- Pick up gold from smelter output
                        collectorData.state = "picking_up"
                        setNPCStatus(collector, "Picking up gold...")
                        task.wait(1)

                        local goldToCollect = math.min(GoldMineState.smelterGold, goldCapacity)
                        GoldMineState.smelterGold = GoldMineState.smelterGold - goldToCollect
                        collectorData.carrying = goldToCollect

                        -- Show gold being carried (1 visual bar per gold, up to 5)
                        setNPCCarrying(collector, "gold", math.min(5, goldToCollect))
                        setNPCStatus(collector, string.format("Carrying %d gold", goldToCollect))

                        -- Update visual gold bars (remove some)
                        if GoldMineState.updateGoldBarVisuals then
                            GoldMineState.updateGoldBarVisuals()
                        end

                        -- Update smelter UI
                        if GoldMineState.updateSmelterUI then
                            if GoldMineState.smelterGold > 0 then
                                GoldMineState.updateSmelterUI(
                                    string.format("Ready: %d gold bars", GoldMineState.smelterGold),
                                    0
                                )
                            else
                                GoldMineState.updateSmelterUI("Idle - Waiting for ore", 0)
                            end
                        end

                        print(string.format("[Collector #%d] Picked up %d gold from smelter", collectorId, goldToCollect))

                        -- Walk to chest
                        collectorData.state = "walking_to_chest"
                        setNPCStatus(collector, "Delivering to chest...")
                        walkNPCTo(collector, GoldMineState.positions.goldChest + Vector3.new(-4, 0, 0), walkSpeed, function()
                            -- Deposit gold into chest
                            collectorData.state = "depositing"
                            setNPCStatus(collector, "Depositing gold...")
                            task.wait(1.5)

                            local goldDelivered = collectorData.carrying
                            GoldMineState.chestGold = GoldMineState.chestGold + goldDelivered

                            -- Update chest gold visual
                            if GoldMineState.updateChestGoldVisuals then
                                GoldMineState.updateChestGoldVisuals()
                            end

                            -- REWARD THE PLAYER who hired the collector
                            -- Find the player (they might have disconnected)
                            local ownerPlayer = nil
                            for _, p in Players:GetPlayers() do
                                if p.UserId == collectorData.owner then
                                    ownerPlayer = p
                                    break
                                end
                            end

                            if ownerPlayer then
                                rewardPlayer(ownerPlayer, "gold", goldDelivered, "GoldMine")
                                print(string.format("[Collector #%d] Delivered %d gold to %s's chest!",
                                    collectorId, goldDelivered, ownerPlayer.Name))
                            else
                                -- If owner disconnected, reward all players in the mine
                                print(string.format("[Collector #%d] Delivered %d gold to chest (owner offline)",
                                    collectorId, goldDelivered))
                            end

                            -- Gold sparkle effect at chest
                            local torso = collector:FindFirstChild("UpperTorso") or collector:FindFirstChild("Torso")
                            if torso then
                                local sparkle = Instance.new("ParticleEmitter")
                                sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
                                sparkle.Size = NumberSequence.new(0.5)
                                sparkle.Lifetime = NumberRange.new(0.5, 1)
                                sparkle.Rate = 30
                                sparkle.Speed = NumberRange.new(2, 5)
                                sparkle.SpreadAngle = Vector2.new(60, 60)
                                sparkle.Parent = torso
                                task.delay(0.8, function() sparkle:Destroy() end)
                            end

                            collectorData.carrying = 0
                            setNPCCarrying(collector, nil, 0)
                            collectorData.state = "idle"
                            setNPCStatus(collector, "Waiting for gold...")
                            cycleComplete = true
                        end)
                    end)

                    -- Wait for cycle to complete before checking for more gold
                    while not cycleComplete and collectorData.npc and collectorData.npc.Parent do
                        task.wait(0.5)
                    end

                    task.wait(1) -- Brief pause between cycles
                else
                    setNPCStatus(collector, "Waiting for gold...")
                    task.wait(2) -- Check for gold every 2 seconds when idle
                end
            end
        end)

        print(string.format("[GoldMine] %s hired Collector #%d for %d gold + %d food!",
            player.Name, collectorId, cost.gold, cost.food))
        print(string.format("[GoldMine] Collector #%d will take gold from smelter → deliver to YOUR chest!", collectorId))

        -- Update exterior sign to reflect new production rate
        if GoldMineState.updateExteriorSign then
            GoldMineState.updateExteriorSign()
        end
    end)

    -- Store reference for prompt (needed for disabling when fully staffed)
    GoldMineState.collectorPrompt = collectorHirePrompt

    -- ========== SINGLE UPGRADE KIOSK (front-right area) ==========
    -- Replaces the 4 separate pedestals with ONE kiosk that opens a menu GUI
    local upgradeKioskPos = GoldMineState.positions.upgradeKiosk

    -- Kiosk pedestal/terminal - faces toward center (left/toward baseX)
    local upgradeKiosk = Instance.new("Part")
    upgradeKiosk.Name = "UpgradeKiosk"
    upgradeKiosk.Size = Vector3.new(3, 4, 2)
    upgradeKiosk.Anchored = true
    upgradeKiosk.Material = Enum.Material.Metal
    upgradeKiosk.Color = Color3.fromRGB(70, 70, 80)
    -- Position and rotate to face center (toward baseX, i.e. left)
    local kioskCenterPos = upgradeKioskPos + Vector3.new(0, 2, 0)
    local kioskLookAt = Vector3.new(baseX, kioskCenterPos.Y, kioskCenterPos.Z)
    upgradeKiosk.CFrame = CFrame.lookAt(kioskCenterPos, kioskLookAt)
    upgradeKiosk.Parent = mineModel

    -- Kiosk screen (decorative) - positioned on the front face of kiosk (facing center)
    local kioskScreen = Instance.new("Part")
    kioskScreen.Name = "KioskScreen"
    kioskScreen.Size = Vector3.new(2.5, 2, 0.2)
    kioskScreen.Anchored = true
    kioskScreen.Material = Enum.Material.Neon
    kioskScreen.Color = Color3.fromRGB(50, 150, 255)
    -- Screen is on the front of kiosk, which now faces center
    local screenCFrame = upgradeKiosk.CFrame * CFrame.new(0, 1, -1.1)
    kioskScreen.CFrame = screenCFrame
    kioskScreen.Parent = mineModel

    -- Glow effect
    local kioskGlow = Instance.new("PointLight")
    kioskGlow.Color = Color3.fromRGB(100, 200, 255)
    kioskGlow.Brightness = 1.5
    kioskGlow.Range = 8
    kioskGlow.Parent = kioskScreen

    -- Sign above kiosk - faces toward center
    local kioskSignPos = upgradeKioskPos + Vector3.new(0, 5, 0)
    local kioskSign = Instance.new("Part")
    kioskSign.Name = "UpgradeKioskSign"
    kioskSign.Size = Vector3.new(6, 1.2, 0.3)
    kioskSign.Anchored = true
    kioskSign.Material = Enum.Material.Wood
    kioskSign.Color = Color3.fromRGB(139, 90, 43)
    kioskSign.CFrame = CFrame.lookAt(kioskSignPos, Vector3.new(baseX, kioskSignPos.Y, kioskSignPos.Z))
    kioskSign.Parent = mineModel

    local kioskSignGui = Instance.new("SurfaceGui")
    kioskSignGui.Face = Enum.NormalId.Back -- Text on front face (facing center)
    kioskSignGui.Parent = kioskSign

    local kioskSignLabel = Instance.new("TextLabel")
    kioskSignLabel.Size = UDim2.new(1, 0, 1, 0)
    kioskSignLabel.BackgroundTransparency = 1
    kioskSignLabel.Text = "UPGRADE KIOSK"
    kioskSignLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    kioskSignLabel.TextScaled = true
    kioskSignLabel.Font = Enum.Font.GothamBold
    kioskSignLabel.Parent = kioskSignGui
    makeSignDoubleSided(kioskSign)

    -- Small billboard showing quick stats
    local kioskBillboard = Instance.new("BillboardGui")
    kioskBillboard.Name = "KioskPreview"
    kioskBillboard.Size = UDim2.new(6, 0, 2, 0)
    kioskBillboard.StudsOffset = Vector3.new(0, 3, 2)
    kioskBillboard.AlwaysOnTop = true
    kioskBillboard.Parent = upgradeKiosk

    local previewLabel = Instance.new("TextLabel")
    previewLabel.Size = UDim2.new(1, 0, 1, 0)
    previewLabel.BackgroundTransparency = 1
    previewLabel.Text = "Press E to Open Upgrades"
    previewLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    previewLabel.TextStrokeTransparency = 0.3
    previewLabel.TextScaled = true
    previewLabel.Font = Enum.Font.Gotham
    previewLabel.Parent = kioskBillboard

    -- Track active upgrade GUIs per player
    local activeUpgradeGuis = {}

    -- Function to create the upgrade GUI for a player
    local function createUpgradeGui(player)
        -- Remove existing GUI if any
        if activeUpgradeGuis[player.UserId] then
            activeUpgradeGuis[player.UserId]:Destroy()
            activeUpgradeGuis[player.UserId] = nil
        end

        local playerGui = player:FindFirstChild("PlayerGui")
        if not playerGui then return end

        -- Create ScreenGui
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "GoldMineUpgradeMenu"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = playerGui
        activeUpgradeGuis[player.UserId] = screenGui

        -- Main frame
        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = UDim2.new(0, 450, 0, 550)
        mainFrame.Position = UDim2.new(0.5, -225, 0.5, -275)
        mainFrame.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
        mainFrame.BorderSizePixel = 3
        mainFrame.BorderColor3 = Color3.fromRGB(255, 200, 50)
        mainFrame.Parent = screenGui

        -- Title
        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 50)
        title.Position = UDim2.new(0, 0, 0, 0)
        title.BackgroundColor3 = Color3.fromRGB(50, 40, 30)
        title.BorderSizePixel = 0
        title.Text = "GOLD MINE UPGRADES"
        title.TextColor3 = Color3.fromRGB(255, 215, 0)
        title.TextScaled = true
        title.Font = Enum.Font.GothamBold
        title.Parent = mainFrame

        -- Function to create an upgrade card
        local function createUpgradeCard(yOffset, upgradeType, getStats, currentLevel, color)
            local stats = getStats(currentLevel)
            local nextStats = getStats(currentLevel + 1)

            local card = Instance.new("Frame")
            card.Name = upgradeType .. "Card"
            card.Size = UDim2.new(0.95, 0, 0, 100)
            card.Position = UDim2.new(0.025, 0, 0, yOffset)
            card.BackgroundColor3 = Color3.fromRGB(45, 40, 35)
            card.BorderSizePixel = 2
            card.BorderColor3 = color
            card.Parent = mainFrame

            local cardTitle = Instance.new("TextLabel")
            cardTitle.Size = UDim2.new(0.6, 0, 0, 30)
            cardTitle.Position = UDim2.new(0.02, 0, 0, 5)
            cardTitle.BackgroundTransparency = 1
            cardTitle.Text = string.format("%s  Lv.%d", upgradeType:upper(), currentLevel)
            cardTitle.TextColor3 = color
            cardTitle.TextXAlignment = Enum.TextXAlignment.Left
            cardTitle.TextScaled = true
            cardTitle.Font = Enum.Font.GothamBold
            cardTitle.Parent = card

            local statsText = ""
            if upgradeType == "Pickaxe" then
                statsText = string.format("Ore/Swing: %d -> %d", stats.orePerSwing, nextStats.orePerSwing)
            elseif upgradeType == "Smelter" then
                statsText = string.format("Gold/Ore: %d -> %d | Speed: %.2fs", stats.goldPerOre, nextStats.goldPerOre, nextStats.smeltTime)
            elseif upgradeType == "Miners" then
                statsText = string.format("Capacity: %d -> %d ore | Speed: %d -> %d", stats.oreCapacity, nextStats.oreCapacity, stats.walkSpeed, nextStats.walkSpeed)
            elseif upgradeType == "Collectors" then
                statsText = string.format("Capacity: %d -> %d gold | Speed: %d -> %d", stats.goldCapacity, nextStats.goldCapacity, stats.walkSpeed, nextStats.walkSpeed)
            end

            local statsLabel = Instance.new("TextLabel")
            statsLabel.Size = UDim2.new(0.96, 0, 0, 25)
            statsLabel.Position = UDim2.new(0.02, 0, 0, 35)
            statsLabel.BackgroundTransparency = 1
            statsLabel.Text = statsText
            statsLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
            statsLabel.TextXAlignment = Enum.TextXAlignment.Left
            statsLabel.TextScaled = true
            statsLabel.Font = Enum.Font.Gotham
            statsLabel.Parent = card

            local upgradeButton = Instance.new("TextButton")
            upgradeButton.Name = "UpgradeButton"
            upgradeButton.Size = UDim2.new(0.96, 0, 0, 30)
            upgradeButton.Position = UDim2.new(0.02, 0, 0, 65)
            upgradeButton.BackgroundColor3 = Color3.fromRGB(80, 150, 80)
            upgradeButton.BorderSizePixel = 0
            upgradeButton.Text = string.format("UPGRADE - %d gold", nextStats.upgradeCost)
            upgradeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            upgradeButton.TextScaled = true
            upgradeButton.Font = Enum.Font.GothamBold
            upgradeButton.Parent = card

            return upgradeButton
        end

        -- Create cards for each upgrade type
        local pickaxeBtn = createUpgradeCard(60, "Pickaxe", getPickaxeStats, GoldMineState.equipment.pickaxeLevel, Color3.fromRGB(139, 90, 43))
        local smelterBtn = createUpgradeCard(170, "Smelter", getSmelterStats, GoldMineState.equipment.smelterLevel, Color3.fromRGB(255, 100, 50))
        local minersBtn = createUpgradeCard(280, "Miners", getMinerStats, GoldMineState.equipment.minerLevel, Color3.fromRGB(100, 80, 60))
        local collectorsBtn = createUpgradeCard(390, "Collectors", getCollectorStats, GoldMineState.equipment.collectorLevel, Color3.fromRGB(60, 100, 60))

        -- Close button
        local closeButton = Instance.new("TextButton")
        closeButton.Name = "CloseButton"
        closeButton.Size = UDim2.new(0.5, 0, 0, 40)
        closeButton.Position = UDim2.new(0.25, 0, 0, 500)
        closeButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        closeButton.BorderSizePixel = 0
        closeButton.Text = "CLOSE"
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeButton.TextScaled = true
        closeButton.Font = Enum.Font.GothamBold
        closeButton.Parent = mainFrame

        -- Button handlers
        pickaxeBtn.MouseButton1Click:Connect(function()
            local currentLevel = GoldMineState.equipment.pickaxeLevel
            local nextStats = getPickaxeStats(currentLevel + 1)
            if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "GoldMine") then return end
            GoldMineState.equipment.pickaxeLevel = currentLevel + 1
            addMineXP(50)
            print(string.format("[Upgrade] %s upgraded Pickaxe to Lv%d! Now %d ore/swing (-%d gold)",
                player.Name, currentLevel + 1, nextStats.orePerSwing, nextStats.upgradeCost))
            -- Refresh GUI
            createUpgradeGui(player)
        end)

        smelterBtn.MouseButton1Click:Connect(function()
            local currentLevel = GoldMineState.equipment.smelterLevel
            local nextStats = getSmelterStats(currentLevel + 1)
            if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "GoldMine") then return end
            GoldMineState.equipment.smelterLevel = currentLevel + 1
            addMineXP(50)
            print(string.format("[Upgrade] %s upgraded Smelter to Lv%d! Now %d gold/ore, %.1fs (-%d gold)",
                player.Name, currentLevel + 1, nextStats.goldPerOre, nextStats.smeltTime, nextStats.upgradeCost))
            createUpgradeGui(player)
            -- Update exterior sign to reflect new production rate
            if GoldMineState.updateExteriorSign then
                GoldMineState.updateExteriorSign()
            end
        end)

        minersBtn.MouseButton1Click:Connect(function()
            local currentLevel = GoldMineState.equipment.minerLevel
            local nextStats = getMinerStats(currentLevel + 1)
            if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "GoldMine") then return end
            GoldMineState.equipment.minerLevel = currentLevel + 1
            addMineXP(50)
            print(string.format("[Upgrade] %s upgraded Miners to Lv%d! Now %d ore capacity (-%d gold)",
                player.Name, currentLevel + 1, nextStats.oreCapacity, nextStats.upgradeCost))
            createUpgradeGui(player)
            -- Update exterior sign to reflect new production rate
            if GoldMineState.updateExteriorSign then
                GoldMineState.updateExteriorSign()
            end
        end)

        collectorsBtn.MouseButton1Click:Connect(function()
            local currentLevel = GoldMineState.equipment.collectorLevel
            local nextStats = getCollectorStats(currentLevel + 1)
            if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "GoldMine") then return end
            GoldMineState.equipment.collectorLevel = currentLevel + 1
            addMineXP(50)
            print(string.format("[Upgrade] %s upgraded Collectors to Lv%d! Now %d gold capacity (-%d gold)",
                player.Name, currentLevel + 1, nextStats.goldCapacity, nextStats.upgradeCost))
            createUpgradeGui(player)
            -- Update exterior sign to reflect new production rate (collectors affect effective production)
            if GoldMineState.updateExteriorSign then
                GoldMineState.updateExteriorSign()
            end
        end)

        closeButton.MouseButton1Click:Connect(function()
            screenGui:Destroy()
            activeUpgradeGuis[player.UserId] = nil
        end)
    end

    -- Cleanup GUI when player leaves
    Players.PlayerRemoving:Connect(function(player)
        if activeUpgradeGuis[player.UserId] then
            activeUpgradeGuis[player.UserId]:Destroy()
            activeUpgradeGuis[player.UserId] = nil
        end
    end)

    -- INTERACTION: Open Upgrade Menu (single kiosk)
    createInteraction(upgradeKiosk, "Open Upgrades", "Upgrade Kiosk", 2, function(player)
        createUpgradeGui(player)
        print(string.format("[GoldMine] %s opened Upgrade Menu", player.Name))
    end)

    -- ========== GEM PROSPECTING STATION (near upgrade kiosk) ==========
    local prospectingPos = GoldMineState.positions.upgradeKiosk + Vector3.new(-8, 0, 0) -- Left of upgrade kiosk

    -- Prospecting table
    local prospectingTable = Instance.new("Part")
    prospectingTable.Name = "ProspectingTable"
    prospectingTable.Size = Vector3.new(4, 2.5, 3)
    prospectingTable.Position = prospectingPos + Vector3.new(0, 1.25, 0)
    prospectingTable.Anchored = true
    prospectingTable.Material = Enum.Material.Wood
    prospectingTable.Color = Color3.fromRGB(90, 60, 40)
    prospectingTable.Parent = mineModel

    -- Mining tools on table
    local pickaxeTool = Instance.new("Part")
    pickaxeTool.Name = "ProspectingPickaxe"
    pickaxeTool.Size = Vector3.new(0.2, 1.5, 0.2)
    pickaxeTool.Position = prospectingPos + Vector3.new(1, 2.8, 0.5)
    pickaxeTool.Orientation = Vector3.new(0, 0, 45)
    pickaxeTool.Anchored = true
    pickaxeTool.Material = Enum.Material.Metal
    pickaxeTool.Color = Color3.fromRGB(100, 100, 110)
    pickaxeTool.Parent = mineModel

    -- Magnifying glass
    local magnifyGlass = Instance.new("Part")
    magnifyGlass.Name = "MagnifyingGlass"
    magnifyGlass.Shape = Enum.PartType.Cylinder
    magnifyGlass.Size = Vector3.new(0.1, 1, 1)
    magnifyGlass.Position = prospectingPos + Vector3.new(-1, 2.7, 0)
    magnifyGlass.Orientation = Vector3.new(0, 0, 90)
    magnifyGlass.Anchored = true
    magnifyGlass.Material = Enum.Material.Glass
    magnifyGlass.Color = Color3.fromRGB(200, 220, 255)
    magnifyGlass.Transparency = 0.5
    magnifyGlass.Parent = mineModel

    -- Gem display case (shows result)
    local gemCase = Instance.new("Part")
    gemCase.Name = "GemDisplayCase"
    gemCase.Size = Vector3.new(1.5, 1, 1.5)
    gemCase.Position = prospectingPos + Vector3.new(0, 3, -0.5)
    gemCase.Anchored = true
    gemCase.Material = Enum.Material.Glass
    gemCase.Color = Color3.fromRGB(200, 220, 255)
    gemCase.Transparency = 0.7
    gemCase.Parent = mineModel

    -- Result gem (hidden by default)
    local resultGem = Instance.new("Part")
    resultGem.Name = "ResultGem"
    resultGem.Shape = Enum.PartType.Ball
    resultGem.Size = Vector3.new(0.8, 0.8, 0.8)
    resultGem.Position = prospectingPos + Vector3.new(0, 3.2, -0.5)
    resultGem.Anchored = true
    resultGem.Material = Enum.Material.Neon
    resultGem.Color = Color3.fromRGB(255, 255, 255)
    resultGem.Transparency = 1 -- Hidden until gem found
    resultGem.Parent = mineModel

    -- Timer billboard
    local timerBillboard = Instance.new("BillboardGui")
    timerBillboard.Name = "ProspectingTimer"
    timerBillboard.Size = UDim2.new(0, 150, 0, 50)
    timerBillboard.StudsOffset = Vector3.new(0, 2.5, 0)
    timerBillboard.AlwaysOnTop = false
    timerBillboard.Parent = prospectingTable

    local timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "TimerText"
    timerLabel.Size = UDim2.new(1, 0, 1, 0)
    timerLabel.BackgroundTransparency = 0.5
    timerLabel.BackgroundColor3 = Color3.fromRGB(40, 30, 20)
    timerLabel.Text = "GEM PROSPECTING"
    timerLabel.TextScaled = true
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    timerLabel.Parent = timerBillboard

    -- Sign
    createSign(mineModel, "GEM PROSPECTING", prospectingPos + Vector3.new(0, 4.5, 0), Vector3.new(6, 0.8, 0.3))

    -- Track active prospecting GUIs per player
    local activeProspectingGuis = {}

    -- Function to format gold with commas
    local function formatGold(amount)
        local formatted = tostring(amount)
        local k
        while true do
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then break end
        end
        return formatted
    end

    -- Function to create the prospecting investment GUI
    local function createProspectingGui(player)
        -- Remove existing GUI if any
        if activeProspectingGuis[player.UserId] then
            activeProspectingGuis[player.UserId]:Destroy()
            activeProspectingGuis[player.UserId] = nil
        end

        local playerGui = player:FindFirstChild("PlayerGui")
        if not playerGui then return end

        -- Create ScreenGui
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "ProspectingInvestmentMenu"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = playerGui
        activeProspectingGuis[player.UserId] = screenGui

        -- Main frame
        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = UDim2.new(0, 500, 0, 580)
        mainFrame.Position = UDim2.new(0.5, -250, 0.5, -290)
        mainFrame.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
        mainFrame.BorderSizePixel = 3
        mainFrame.BorderColor3 = Color3.fromRGB(180, 100, 255)
        mainFrame.Parent = screenGui

        -- Add corner rounding
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = mainFrame

        -- Title
        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 50)
        title.Position = UDim2.new(0, 0, 0, 0)
        title.BackgroundColor3 = Color3.fromRGB(40, 30, 55)
        title.BorderSizePixel = 0
        title.Text = "PROSPECT FOR GEMS"
        title.TextColor3 = Color3.fromRGB(180, 100, 255)
        title.TextScaled = true
        title.Font = Enum.Font.GothamBold
        title.Parent = mainFrame

        local titleCorner = Instance.new("UICorner")
        titleCorner.CornerRadius = UDim.new(0, 10)
        titleCorner.Parent = title

        -- Subtitle
        local subtitle = Instance.new("TextLabel")
        subtitle.Name = "Subtitle"
        subtitle.Size = UDim2.new(1, 0, 0, 25)
        subtitle.Position = UDim2.new(0, 0, 0, 50)
        subtitle.BackgroundTransparency = 1
        subtitle.Text = "Choose your investment level:"
        subtitle.TextColor3 = Color3.fromRGB(200, 200, 200)
        subtitle.TextScaled = true
        subtitle.Font = Enum.Font.Gotham
        subtitle.Parent = mainFrame

        -- Function to create an investment tier card
        local function createTierCard(yOffset, tierIndex)
            local tierData = ProspectingTiers[tierIndex]
            local tierColors = {
                [1] = Color3.fromRGB(150, 150, 150),  -- Basic - gray
                [2] = Color3.fromRGB(50, 180, 50),    -- Advanced - green
                [3] = Color3.fromRGB(50, 100, 220),   -- Expert - blue
                [4] = Color3.fromRGB(220, 150, 30),   -- Master - gold
            }
            local tierColor = tierColors[tierIndex] or Color3.fromRGB(150, 150, 150)

            local card = Instance.new("Frame")
            card.Name = tierData.name .. "Card"
            card.Size = UDim2.new(0.94, 0, 0, 105)
            card.Position = UDim2.new(0.03, 0, 0, yOffset)
            card.BackgroundColor3 = Color3.fromRGB(35, 30, 45)
            card.BorderSizePixel = 2
            card.BorderColor3 = tierColor
            card.Parent = mainFrame

            local cardCorner = Instance.new("UICorner")
            cardCorner.CornerRadius = UDim.new(0, 8)
            cardCorner.Parent = card

            -- Tier name and cost
            local tierName = Instance.new("TextLabel")
            tierName.Size = UDim2.new(0.6, 0, 0, 28)
            tierName.Position = UDim2.new(0.02, 0, 0, 5)
            tierName.BackgroundTransparency = 1
            tierName.Text = string.format("%s PROSPECT - %s gold", tierData.name:upper(), formatGold(tierData.cost))
            tierName.TextColor3 = tierColor
            tierName.TextXAlignment = Enum.TextXAlignment.Left
            tierName.TextScaled = true
            tierName.Font = Enum.Font.GothamBold
            tierName.Parent = card

            -- Description
            local description = Instance.new("TextLabel")
            description.Size = UDim2.new(0.96, 0, 0, 20)
            description.Position = UDim2.new(0.02, 0, 0, 33)
            description.BackgroundTransparency = 1
            description.Text = tierData.description
            description.TextColor3 = Color3.fromRGB(180, 180, 180)
            description.TextXAlignment = Enum.TextXAlignment.Left
            description.TextScaled = true
            description.Font = Enum.Font.Gotham
            description.Parent = card

            -- Find chance
            local findChance = Instance.new("TextLabel")
            findChance.Size = UDim2.new(0.96, 0, 0, 20)
            findChance.Position = UDim2.new(0.02, 0, 0, 53)
            findChance.BackgroundTransparency = 1
            findChance.Text = string.format("%.0f%% chance of finding something", tierData.findChance * 100)
            findChance.TextColor3 = Color3.fromRGB(100, 200, 100)
            findChance.TextXAlignment = Enum.TextXAlignment.Left
            findChance.TextScaled = true
            findChance.Font = Enum.Font.Gotham
            findChance.Parent = card

            -- Prospect button
            local prospectButton = Instance.new("TextButton")
            prospectButton.Name = "ProspectButton"
            prospectButton.Size = UDim2.new(0.3, 0, 0, 28)
            prospectButton.Position = UDim2.new(0.68, 0, 0, 70)
            prospectButton.BackgroundColor3 = tierColor
            prospectButton.BorderSizePixel = 0
            prospectButton.Text = "PROSPECT"
            prospectButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            prospectButton.TextScaled = true
            prospectButton.Font = Enum.Font.GothamBold
            prospectButton.Parent = card

            local buttonCorner = Instance.new("UICorner")
            buttonCorner.CornerRadius = UDim.new(0, 6)
            buttonCorner.Parent = prospectButton

            return prospectButton, tierData
        end

        -- Create cards for each tier
        local basicBtn, basicData = createTierCard(85, 1)
        local advancedBtn, advancedData = createTierCard(200, 2)
        local expertBtn, expertData = createTierCard(315, 3)
        local masterBtn, masterData = createTierCard(430, 4)

        -- Close button
        local closeButton = Instance.new("TextButton")
        closeButton.Name = "CloseButton"
        closeButton.Size = UDim2.new(0.4, 0, 0, 35)
        closeButton.Position = UDim2.new(0.3, 0, 0, 540)
        closeButton.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
        closeButton.BorderSizePixel = 0
        closeButton.Text = "CLOSE"
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeButton.TextScaled = true
        closeButton.Font = Enum.Font.GothamBold
        closeButton.Parent = mainFrame

        local closeCorner = Instance.new("UICorner")
        closeCorner.CornerRadius = UDim.new(0, 6)
        closeCorner.Parent = closeButton

        -- Function to start prospecting at a specific tier
        local function startProspecting(tierIndex)
            local tierData = ProspectingTiers[tierIndex]

            -- Check and deduct gold via DataService
            if DataService then
                local playerData = DataService:GetPlayerData(player)
                if playerData then
                    if playerData.resources.gold < tierData.cost then
                        print(string.format("[GoldMine] %s: Not enough gold! Need %s, have %s.",
                            player.Name, formatGold(tierData.cost), formatGold(playerData.resources.gold)))
                        return
                    end

                    -- Deduct gold
                    local success = DataService:DeductResources(player, { gold = tierData.cost })
                    if not success then
                        print(string.format("[GoldMine] %s: Failed to deduct gold!", player.Name))
                        return
                    end

                    -- Sync HUD
                    local Events = ReplicatedStorage:FindFirstChild("Events")
                    if Events then
                        local SyncPlayerData = Events:FindFirstChild("SyncPlayerData")
                        if SyncPlayerData then
                            SyncPlayerData:FireClient(player, playerData)
                        end
                    end
                else
                    print(string.format("[GoldMine] %s: No player data found!", player.Name))
                    return
                end
            else
                print("[GoldMine] DataService not available - using demo mode (no gold deducted)")
            end

            -- Roll for gem immediately (instant result)
            local success = math.random() < tierData.findChance

            if success then
                local gem = rollGem(tierIndex)
                GoldMineState.playerHeldGem[player.UserId] = gem

                -- Show gem visual
                resultGem.Color = gem.color
                resultGem.Transparency = 0

                -- Size based on gem size
                local sizeMap = { Chip = 0.5, Stone = 0.7, Gem = 0.9, Jewel = 1.2 }
                local visualSize = sizeMap[gem.size] or 0.8
                resultGem.Size = Vector3.new(visualSize, visualSize, visualSize)

                -- Get rarity color for display
                local rarityColor = RarityColors[gem.rarity] or Color3.fromRGB(255, 255, 255)

                print(string.format("[GoldMine] %s found a %s %s %s!",
                    player.Name, gem.rarity, gem.size, gem.type))
                print(string.format("  Value: %s gold | Bonus: +%.0f%% %s",
                    formatGold(gem.value), (gem.multiplier - 1) * 100, gem.boost))
                print("  Take it to the Town Hall Trophy Case to display!")

                -- Award gem value to player
                if DataService then
                    local playerData = DataService:GetPlayerData(player)
                    if playerData then
                        DataService:UpdateResources(player, { gold = gem.value })
                        print(string.format("[GoldMine] %s received %s gold for the gem!", player.Name, formatGold(gem.value)))

                        -- Sync HUD
                        local Events = ReplicatedStorage:FindFirstChild("Events")
                        if Events then
                            local SyncPlayerData = Events:FindFirstChild("SyncPlayerData")
                            if SyncPlayerData then
                                SyncPlayerData:FireClient(player, playerData)
                            end
                        end
                    end
                end

                -- Sparkle effect
                local sparkle = Instance.new("ParticleEmitter")
                sparkle.Color = ColorSequence.new(gem.color)
                sparkle.Size = NumberSequence.new(0.3, 0)
                sparkle.Lifetime = NumberRange.new(0.5, 1)
                sparkle.Rate = 50
                sparkle.Speed = NumberRange.new(2, 4)
                sparkle.SpreadAngle = Vector2.new(180, 180)
                sparkle.Parent = resultGem
                task.delay(2, function() sparkle:Destroy() end)

                -- Update timer display
                timerLabel.Text = string.format("FOUND: %s %s!", gem.rarity:upper(), gem.type)
                timerLabel.TextColor3 = rarityColor
                task.delay(3, function()
                    timerLabel.Text = "GEM PROSPECTING"
                    timerLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
                    resultGem.Transparency = 1
                end)
            else
                print(string.format("[GoldMine] %s: No gems found this time. Better luck next prospect!", player.Name))

                -- Update timer display
                timerLabel.Text = "Nothing found..."
                timerLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
                task.delay(2, function()
                    timerLabel.Text = "GEM PROSPECTING"
                    timerLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
                end)
            end

            -- Close the GUI
            screenGui:Destroy()
            activeProspectingGuis[player.UserId] = nil
        end

        -- Button handlers
        basicBtn.MouseButton1Click:Connect(function()
            startProspecting(1)
        end)

        advancedBtn.MouseButton1Click:Connect(function()
            startProspecting(2)
        end)

        expertBtn.MouseButton1Click:Connect(function()
            startProspecting(3)
        end)

        masterBtn.MouseButton1Click:Connect(function()
            startProspecting(4)
        end)

        closeButton.MouseButton1Click:Connect(function()
            screenGui:Destroy()
            activeProspectingGuis[player.UserId] = nil
        end)
    end

    -- Start prospecting interaction
    local startProspectPrompt = Instance.new("ProximityPrompt")
    startProspectPrompt.Name = "StartProspectPrompt"
    startProspectPrompt.ObjectText = "Gem Prospecting"
    startProspectPrompt.ActionText = "Open Prospecting"
    startProspectPrompt.HoldDuration = 0.3
    startProspectPrompt.MaxActivationDistance = 8
    startProspectPrompt.Parent = prospectingTable

    startProspectPrompt.Triggered:Connect(function(player)
        -- Visitor guard
        if not isVillageOwner(player) then return end

        -- Check if GUI already open
        if activeProspectingGuis[player.UserId] then
            activeProspectingGuis[player.UserId]:Destroy()
            activeProspectingGuis[player.UserId] = nil
            return
        end

        -- Show the investment selection GUI
        createProspectingGui(player)
    end)

    -- ========== EXIT PORTAL ==========
    createExitPortal(mineModel, Vector3.new(baseX, GROUND_Y + 4, baseZ + 28))

    -- ===== DECORATIVE ENHANCEMENTS =====
    -- Glowing crystal clusters on walls
    local crystalColors = {
        {color = Color3.fromRGB(80, 120, 255), light = Color3.fromRGB(100, 150, 255)},
        {color = Color3.fromRGB(150, 60, 200), light = Color3.fromRGB(180, 100, 255)},
        {color = Color3.fromRGB(60, 200, 120), light = Color3.fromRGB(80, 255, 150)},
    }
    local crystalPositions = {
        Vector3.new(baseX - 38, GROUND_Y + 3, baseZ - 15),
        Vector3.new(baseX - 38, GROUND_Y + 5, baseZ + 5),
        Vector3.new(baseX + 38, GROUND_Y + 4, baseZ - 10),
        Vector3.new(baseX + 38, GROUND_Y + 3, baseZ + 10),
        Vector3.new(baseX - 20, GROUND_Y + 13, baseZ - 5),
        Vector3.new(baseX + 10, GROUND_Y + 13, baseZ + 8),
    }
    for ci, cpos in crystalPositions do
        local cData = crystalColors[(ci % #crystalColors) + 1]
        for cs = 1, 3 do
            local crystal = Instance.new("Part")
            crystal.Name = "Crystal" .. ci .. "_" .. cs
            crystal.Size = Vector3.new(0.3 + cs * 0.15, 0.8 + cs * 0.4, 0.3 + cs * 0.1)
            crystal.Position = cpos + Vector3.new((cs - 2) * 0.4, cs * 0.3, 0)
            crystal.Orientation = Vector3.new(math.random(-15, 15), math.random(0, 360), math.random(-20, 20))
            crystal.Anchored = true
            crystal.Material = Enum.Material.Neon
            crystal.Color = cData.color
            crystal.CanCollide = false
            crystal.Parent = mineModel
        end
        local crystalLight = Instance.new("PointLight")
        crystalLight.Color = cData.light
        crystalLight.Brightness = 0.8
        crystalLight.Range = 10
        local lightHost = Instance.new("Part")
        lightHost.Name = "CrystalGlow" .. ci
        lightHost.Size = Vector3.new(0.2, 0.2, 0.2)
        lightHost.Position = cpos
        lightHost.Anchored = true
        lightHost.Transparency = 1
        lightHost.CanCollide = false
        lightHost.Parent = mineModel
        crystalLight.Parent = lightHost
    end

    -- Rock debris scattered on floor
    for rd = 1, 12 do
        local rockDebris = Instance.new("Part")
        rockDebris.Name = "FloorDebris" .. rd
        rockDebris.Size = Vector3.new(0.4 + math.random() * 0.6, 0.3 + math.random() * 0.3, 0.4 + math.random() * 0.6)
        rockDebris.Position = Vector3.new(
            baseX - 30 + math.random() * 60,
            GROUND_Y + 0.2,
            baseZ - 20 + math.random() * 40
        )
        rockDebris.Orientation = Vector3.new(math.random() * 20, math.random() * 360, math.random() * 20)
        rockDebris.Anchored = true
        rockDebris.Material = Enum.Material.Rock
        rockDebris.Color = Color3.fromRGB(50 + math.random(20), 45 + math.random(15), 40 + math.random(10))
        rockDebris.CanCollide = false
        rockDebris.Parent = mineModel
    end

    -- Cart rail tracks on cave floor
    for _, trackZ in {baseZ - 15, baseZ + 5} do
        for _, rOff in {-0.8, 0.8} do
            local rail = Instance.new("Part")
            rail.Name = "CaveRail"
            rail.Size = Vector3.new(40, 0.1, 0.2)
            rail.Position = Vector3.new(baseX, GROUND_Y + 0.05, trackZ + rOff)
            rail.Anchored = true
            rail.Material = Enum.Material.Metal
            rail.Color = Color3.fromRGB(70, 65, 55)
            rail.CanCollide = false
            rail.Parent = mineModel
        end
        -- Rail ties
        for ti = 0, 9 do
            local tie = Instance.new("Part")
            tie.Name = "CaveRailTie"
            tie.Size = Vector3.new(0.5, 0.08, 2)
            tie.Position = Vector3.new(baseX - 18 + ti * 4, GROUND_Y + 0.03, trackZ)
            tie.Anchored = true
            tie.Material = Enum.Material.Wood
            tie.Color = Color3.fromRGB(50, 35, 22)
            tie.CanCollide = false
            tie.Parent = mineModel
        end
    end

    -- Lanterns on support beams
    for bi = 1, 4 do
        local bx = baseX - 30 + bi * 15
        for _, bz in {baseZ - 12, baseZ + 12} do
            local beamLantern = Instance.new("Part")
            beamLantern.Name = "BeamLantern"
            beamLantern.Size = Vector3.new(0.5, 0.7, 0.5)
            beamLantern.Position = Vector3.new(bx, GROUND_Y + 12, bz)
            beamLantern.Anchored = true
            beamLantern.Material = Enum.Material.Glass
            beamLantern.Color = Color3.fromRGB(255, 210, 130)
            beamLantern.Transparency = 0.3
            beamLantern.CanCollide = false
            beamLantern.Parent = mineModel

            local bLanternLight = Instance.new("PointLight")
            bLanternLight.Color = Color3.fromRGB(255, 180, 80)
            bLanternLight.Brightness = 0.6
            bLanternLight.Range = 8
            bLanternLight.Parent = beamLantern
        end
    end

    -- Parent the mine interior
    mineModel.Parent = interiorsFolder
    GoldMineState.model = mineModel

    print("  ✓ Gold Mine created (REDESIGNED SPACIOUS LAYOUT):")
    print("    BACK WALL: Smelter (left) + Gold Chest (right)")
    print("    FRONT LEFT: Ore Vein (mine here)")
    print("    FRONT RIGHT: Upgrade Kiosk + Gem Prospecting Station")
    print("    ENTRANCE AREA: Hire Miners (LEFT of door) + Hire Collectors (RIGHT of door)")
    print("    HIRING STANDS: Wall sign + table + 3 workers waiting to be hired")
    print("    Workers visually leave stand when hired, sign shows 'FULLY STAFFED' when all hired")
    print("    FLOW: Ore Vein → Smelter → Gold Chest → Profit!")
    print("    NEW: Gem Prospecting - Invest gold to find gems for Town Hall bonuses!")
end

-- ============================================================================
-- LUMBER MILL - Full progression loop prototype
-- Chop trees → Carry logs → Process at sawmill → Collect → Hire workers → Upgrade
-- ============================================================================

-- Lumber Mill state
local LumberMillState = {
    level = 1,
    xp = 0,
    loggers = {},           -- NPC loggers (trees → sawmill)
    haulers = {},           -- NPC haulers (sawmill → storage)
    waitingLoggers = {},    -- Array of waiting logger NPCs at hiring booth
    waitingHaulers = {},    -- Array of waiting hauler NPCs at hiring booth
    equipment = {
        axeLevel = 1,       -- Logs per swing, chop speed
        sawmillLevel = 1,   -- Planks per log, speed at milestones
        loggerLevel = 1,    -- Log capacity, walk speed
        haulerLevel = 1,    -- Plank capacity, walk speed
    },
    playerLogs = {},        -- [playerId] = logs being carried
    playerPlanks = {},      -- [playerId] = planks being carried
    treeStage = {},         -- [treeId] = 1-4 (stage) or 0 (respawning)
    treeRespawn = {},       -- [treeId] = os.time() when tree respawns
    treeModels = {},        -- [treeId] = Model reference
    sawmillLogs = 0,        -- Logs queued in sawmill
    woodStorage = 0,        -- Planks ready to collect
    positions = {},
    treePositions = {},     -- Store tree positions for respawn
    millModel = nil,        -- Reference to the mill model for tree creation
    -- Visual update functions (set during creation)
    updatePlankPileVisuals = nil,
    updateTreeVisual = nil, -- Function to update tree stage visuals
    updateSawmillUI = nil,  -- Function to update sawmill progress bar
}

-- Equipment stats - LEVEL BASED (scales infinitely)
-- Returns stats for a given level, with scaling costs

local function getAxeStats(level)
    return {
        logsPerChop = level,                           -- Level 1 = 1 log, Level 5 = 5 logs
        speed = 1.0 + (level - 1) * 0.2,               -- Gets faster
        upgradeCost = math.floor(100 * (level ^ 1.8)), -- Exponential cost: 100, 348, 728, 1234...
    }
end

local function getSawmillStats(level)
    -- Speed only increases at milestone levels: 10, 20, 50, 100, 200, 500, 1000
    local speedBoosts = 0
    if level >= 10 then speedBoosts = speedBoosts + 1 end
    if level >= 20 then speedBoosts = speedBoosts + 1 end
    if level >= 50 then speedBoosts = speedBoosts + 1 end
    if level >= 100 then speedBoosts = speedBoosts + 1 end
    if level >= 200 then speedBoosts = speedBoosts + 1 end
    if level >= 500 then speedBoosts = speedBoosts + 1 end
    if level >= 1000 then speedBoosts = speedBoosts + 1 end

    local processTime = math.max(0.2, 2.0 - (speedBoosts * 0.25)) -- 2.0s → 1.75s → 1.5s → 1.25s → 1.0s → 0.75s → 0.5s → 0.25s

    return {
        planksPerLog = level,                          -- Level 1 = 1 plank/log, increases every level
        processTime = processTime,                     -- Only faster at milestones
        speedBoosts = speedBoosts,                     -- For display purposes
        upgradeCost = math.floor(200 * (level ^ 1.8)), -- 200, 696, 1456, 2468...
    }
end

local function getLoggerStats(level)
    return {
        logCapacity = 5 + (level * 5),                 -- 10, 15, 20, 25...
        walkSpeed = 4 + level,                         -- 5, 6, 7, 8...
        choppingTime = math.max(0.2, 0.5 - (level - 1) * 0.05), -- Faster chopping per log
        upgradeCost = math.floor(150 * (level ^ 1.8)), -- 150, 522, 1092, 1851...
    }
end

local function getHaulerStats(level)
    return {
        plankCapacity = 10 + (level * 5),              -- 15, 20, 25, 30...
        walkSpeed = 4 + level,                         -- 5, 6, 7, 8...
        upgradeCost = math.floor(100 * (level ^ 1.8)), -- 100, 348, 728, 1234...
    }
end

local LoggerCosts = {
    [1] = { gold = 1200, food = 240 },
    [2] = { gold = 3600, food = 750 },
    [3] = { gold = 12000, food = 2400 },
}

local HaulerCosts = {
    [1] = { gold = 900, food = 180 },
    [2] = { gold = 2700, food = 540 },
    [3] = { gold = 8100, food = 1620 },
}

local function getPlayerLogs(player)
    return LumberMillState.playerLogs[player.UserId] or 0
end

local function setPlayerLogs(player, amount)
    LumberMillState.playerLogs[player.UserId] = math.max(0, math.min(amount, 8)) -- Max 8 logs carried
end

local function getPlayerPlanks(player)
    return LumberMillState.playerPlanks[player.UserId] or 0
end

local function setPlayerPlanks(player, amount)
    LumberMillState.playerPlanks[player.UserId] = math.max(0, math.min(amount, 30)) -- Max 30 planks carried
end

local function addLumberXP(amount)
    LumberMillState.xp = LumberMillState.xp + amount
    local requiredXP = LumberMillState.level * 100
    if LumberMillState.xp >= requiredXP then
        LumberMillState.level = LumberMillState.level + 1
        LumberMillState.xp = LumberMillState.xp - requiredXP
        print(string.format("[LumberMill] LEVEL UP! Now level %d", LumberMillState.level))
    end
end

-- Update visual logs on player's back
local function updatePlayerLogVisual(player, amount)
    local character = player.Character
    if not character then return end

    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    if not torso then return end

    -- Remove existing log backpack
    local existingBackpack = character:FindFirstChild("LogBackpack")
    if existingBackpack then
        existingBackpack:Destroy()
    end

    if amount <= 0 then return end

    -- Create log bundle on back
    local backpack = Instance.new("Model")
    backpack.Name = "LogBackpack"
    backpack.Parent = character

    -- Base bundle
    local bundle = Instance.new("Part")
    bundle.Name = "LogBundle"
    bundle.Size = Vector3.new(1, 0.8 + (amount * 0.15), 2)
    bundle.Anchored = false
    bundle.CanCollide = false
    bundle.Material = Enum.Material.Wood
    bundle.Color = Color3.fromRGB(100, 70, 45)
    bundle.Parent = backpack

    -- Weld to torso
    local weld = Instance.new("Weld")
    weld.Part0 = torso
    weld.Part1 = bundle
    weld.C0 = CFrame.new(0, 0.3, 0.8)
    weld.Parent = bundle

    -- Individual log visuals
    local logCount = math.min(amount, 4)
    for i = 1, logCount do
        local log = Instance.new("Part")
        log.Name = "Log" .. i
        log.Shape = Enum.PartType.Cylinder
        log.Size = Vector3.new(1.8, 0.4, 0.4)
        log.Anchored = false
        log.CanCollide = false
        log.Material = Enum.Material.Wood
        log.Color = Color3.fromRGB(90 + math.random(20), 60 + math.random(10), 40)
        log.Parent = backpack

        local logWeld = Instance.new("Weld")
        logWeld.Part0 = bundle
        logWeld.Part1 = log
        logWeld.C0 = CFrame.new(0, 0.3 + (i-1) * 0.25, 0) * CFrame.Angles(0, math.rad(90), 0)
        logWeld.Parent = log
    end
end

-- Update visual planks on player's back
local function updatePlayerPlankVisual(player, amount)
    local character = player.Character
    if not character then return end

    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    if not torso then return end

    -- Remove existing plank backpack
    local existingBackpack = character:FindFirstChild("PlankBackpack")
    if existingBackpack then
        existingBackpack:Destroy()
    end

    if amount <= 0 then return end

    -- Create plank stack on back
    local backpack = Instance.new("Model")
    backpack.Name = "PlankBackpack"
    backpack.Parent = character

    local plankCount = math.min(math.ceil(amount / 5), 6)
    for i = 1, plankCount do
        local plank = Instance.new("Part")
        plank.Name = "Plank" .. i
        plank.Size = Vector3.new(1.5, 0.15, 0.8)
        plank.Anchored = false
        plank.CanCollide = false
        plank.Material = Enum.Material.Wood
        plank.Color = Color3.fromRGB(200, 170, 120)
        plank.Parent = backpack

        local plankWeld = Instance.new("Weld")
        plankWeld.Part0 = torso
        plankWeld.Part1 = plank
        plankWeld.C0 = CFrame.new(0, 0.2 + (i-1) * 0.18, 0.7)
        plankWeld.Parent = plank
    end
end

local function createLumberMill()
    print("[4/8] Creating Lumber Mill with FOREST interior...")

    -- ========== EXTERIOR IN VILLAGE (LUMBER YARD) ==========
    -- Right side of path, entrance facing WEST (toward main path at X=60)
    local exteriorX, exteriorZ = 95, 50
    local extGround = GROUND_Y
    local yardWidth, yardDepth = 30, 25  -- Size of the lumber yard

    local lumberYard = Instance.new("Model")
    lumberYard.Name = "LumberMill_Exterior"

    -- ===== GROUND: Dirt/sawdust floor =====
    local yardFloor = Instance.new("Part")
    yardFloor.Name = "YardFloor"
    yardFloor.Size = Vector3.new(yardWidth, 0.5, yardDepth)
    yardFloor.Position = Vector3.new(exteriorX + yardWidth/2 - 5, extGround - 0.25, exteriorZ)
    yardFloor.Anchored = true
    yardFloor.Material = Enum.Material.Sand  -- Sawdust look
    yardFloor.Color = Color3.fromRGB(160, 130, 90)
    yardFloor.Parent = lumberYard

    -- ===== WOODEN FENCE PERIMETER =====
    local fenceHeight = 4
    local fenceColor = Color3.fromRGB(100, 70, 45)

    -- Back fence (east side)
    local backFence = Instance.new("Part")
    backFence.Size = Vector3.new(1, fenceHeight, yardDepth)
    backFence.Position = Vector3.new(exteriorX + yardWidth - 5, extGround + fenceHeight/2, exteriorZ)
    backFence.Anchored = true
    backFence.Material = Enum.Material.Wood
    backFence.Color = fenceColor
    backFence.Parent = lumberYard

    -- North fence
    local northFence = Instance.new("Part")
    northFence.Size = Vector3.new(yardWidth, fenceHeight, 1)
    northFence.Position = Vector3.new(exteriorX + yardWidth/2 - 5, extGround + fenceHeight/2, exteriorZ + yardDepth/2)
    northFence.Anchored = true
    northFence.Material = Enum.Material.Wood
    northFence.Color = fenceColor
    northFence.Parent = lumberYard

    -- South fence
    local southFence = Instance.new("Part")
    southFence.Size = Vector3.new(yardWidth, fenceHeight, 1)
    southFence.Position = Vector3.new(exteriorX + yardWidth/2 - 5, extGround + fenceHeight/2, exteriorZ - yardDepth/2)
    southFence.Anchored = true
    southFence.Material = Enum.Material.Wood
    southFence.Color = fenceColor
    southFence.Parent = lumberYard

    -- Fence posts (vertical supports)
    for _, pos in ipairs({
        Vector3.new(exteriorX - 5, extGround, exteriorZ - yardDepth/2),
        Vector3.new(exteriorX - 5, extGround, exteriorZ + yardDepth/2),
        Vector3.new(exteriorX + yardWidth - 5, extGround, exteriorZ - yardDepth/2),
        Vector3.new(exteriorX + yardWidth - 5, extGround, exteriorZ + yardDepth/2),
    }) do
        local post = Instance.new("Part")
        post.Size = Vector3.new(1.2, fenceHeight + 2, 1.2)
        post.Position = pos + Vector3.new(0, (fenceHeight + 2)/2, 0)
        post.Anchored = true
        post.Material = Enum.Material.Wood
        post.Color = Color3.fromRGB(80, 55, 35)
        post.Parent = lumberYard
    end

    -- Front fence (west side) - with gap for entrance (entrance is 6 studs wide at center)
    local gateGap = 4  -- Half the gate width (total gap = 8 studs)

    -- Front fence - SOUTH section (from south corner to gate)
    local frontFenceSouth = Instance.new("Part")
    local southSectionLength = (yardDepth/2) - gateGap
    frontFenceSouth.Size = Vector3.new(1, fenceHeight, southSectionLength)
    frontFenceSouth.Position = Vector3.new(exteriorX - 5, extGround + fenceHeight/2, exteriorZ - gateGap - southSectionLength/2)
    frontFenceSouth.Anchored = true
    frontFenceSouth.Material = Enum.Material.Wood
    frontFenceSouth.Color = fenceColor
    frontFenceSouth.Parent = lumberYard

    -- Front fence - NORTH section (from gate to north corner)
    local frontFenceNorth = Instance.new("Part")
    local northSectionLength = (yardDepth/2) - gateGap
    frontFenceNorth.Size = Vector3.new(1, fenceHeight, northSectionLength)
    frontFenceNorth.Position = Vector3.new(exteriorX - 5, extGround + fenceHeight/2, exteriorZ + gateGap + northSectionLength/2)
    frontFenceNorth.Anchored = true
    frontFenceNorth.Material = Enum.Material.Wood
    frontFenceNorth.Color = fenceColor
    frontFenceNorth.Parent = lumberYard

    -- ===== SAWMILL SHED (back right corner) =====
    local shedX, shedZ = exteriorX + 15, exteriorZ - 6
    local shedWidth, shedDepth, shedHeight = 10, 8, 6

    -- Shed base/floor
    local shedFloor = Instance.new("Part")
    shedFloor.Size = Vector3.new(shedWidth, 0.5, shedDepth)
    shedFloor.Position = Vector3.new(shedX, extGround + 0.25, shedZ)
    shedFloor.Anchored = true
    shedFloor.Material = Enum.Material.WoodPlanks
    shedFloor.Color = Color3.fromRGB(90, 65, 40)
    shedFloor.Parent = lumberYard

    -- Shed walls (3 walls, open front facing west)
    local shedBack = Instance.new("Part")
    shedBack.Size = Vector3.new(0.5, shedHeight, shedDepth)
    shedBack.Position = Vector3.new(shedX + shedWidth/2, extGround + shedHeight/2, shedZ)
    shedBack.Anchored = true
    shedBack.Material = Enum.Material.Wood
    shedBack.Color = Color3.fromRGB(85, 60, 38)
    shedBack.Parent = lumberYard

    for _, zOff in ipairs({-shedDepth/2, shedDepth/2}) do
        local sideWall = Instance.new("Part")
        sideWall.Size = Vector3.new(shedWidth, shedHeight, 0.5)
        sideWall.Position = Vector3.new(shedX, extGround + shedHeight/2, shedZ + zOff)
        sideWall.Anchored = true
        sideWall.Material = Enum.Material.Wood
        sideWall.Color = Color3.fromRGB(85, 60, 38)
        sideWall.Parent = lumberYard
    end

    -- Shed roof (slanted)
    local shedRoof = Instance.new("Part")
    shedRoof.Size = Vector3.new(shedWidth + 2, 0.5, shedDepth + 2)
    shedRoof.Position = Vector3.new(shedX, extGround + shedHeight + 0.25, shedZ)
    shedRoof.Orientation = Vector3.new(0, 0, -10)  -- Slight slant
    shedRoof.Anchored = true
    shedRoof.Material = Enum.Material.Wood
    shedRoof.Color = Color3.fromRGB(70, 50, 30)
    shedRoof.Parent = lumberYard

    -- Sawmill blade (circular saw in shed)
    local sawBlade = Instance.new("Part")
    sawBlade.Shape = Enum.PartType.Cylinder
    sawBlade.Size = Vector3.new(0.3, 4, 4)
    sawBlade.Position = Vector3.new(shedX - 2, extGround + 2.5, shedZ)
    sawBlade.Orientation = Vector3.new(0, 90, 0)
    sawBlade.Anchored = true
    sawBlade.Material = Enum.Material.Metal
    sawBlade.Color = Color3.fromRGB(150, 150, 160)
    sawBlade.Parent = lumberYard

    -- ===== LOG PILES (raw logs waiting to be processed) =====
    local logPileX, logPileZ = exteriorX + 5, exteriorZ + 6
    for row = 1, 3 do
        for col = 1, 4 do
            local log = Instance.new("Part")
            log.Shape = Enum.PartType.Cylinder
            log.Size = Vector3.new(6, 1.2, 1.2)
            log.Position = Vector3.new(logPileX + (col-1) * 1.5, extGround + 0.6 + (row-1) * 1.1, logPileZ)
            log.Orientation = Vector3.new(0, 0, 90)
            log.Anchored = true
            log.Material = Enum.Material.Wood
            log.Color = Color3.fromRGB(90 + math.random(20), 60 + math.random(15), 35 + math.random(10))
            log.Parent = lumberYard
        end
    end

    -- ===== PLANK STACKS (finished lumber) =====
    local plankX, plankZ = exteriorX + 18, exteriorZ + 8
    for layer = 1, 4 do
        for i = 1, 5 do
            local plank = Instance.new("Part")
            plank.Size = Vector3.new(6, 0.3, 1)
            plank.Position = Vector3.new(plankX, extGround + 0.15 + (layer-1) * 0.35, plankZ - 2 + i * 1.1)
            plank.Anchored = true
            plank.Material = Enum.Material.Wood
            plank.Color = Color3.fromRGB(200, 170, 120)
            plank.Parent = lumberYard
        end
    end

    -- ===== CHOPPING BLOCK with axe =====
    local blockX, blockZ = exteriorX + 2, exteriorZ - 4
    local choppingBlock = Instance.new("Part")
    choppingBlock.Size = Vector3.new(2, 1.5, 2)
    choppingBlock.Position = Vector3.new(blockX, extGround + 0.75, blockZ)
    choppingBlock.Anchored = true
    choppingBlock.Material = Enum.Material.Wood
    choppingBlock.Color = Color3.fromRGB(100, 70, 45)
    choppingBlock.Parent = lumberYard

    -- Axe stuck in block
    local axeHandle = Instance.new("Part")
    axeHandle.Size = Vector3.new(0.3, 2, 0.3)
    axeHandle.Position = Vector3.new(blockX, extGround + 2.5, blockZ)
    axeHandle.Orientation = Vector3.new(0, 0, 15)
    axeHandle.Anchored = true
    axeHandle.Material = Enum.Material.Wood
    axeHandle.Color = Color3.fromRGB(120, 80, 50)
    axeHandle.Parent = lumberYard

    local axeHead = Instance.new("Part")
    axeHead.Size = Vector3.new(0.8, 0.3, 1.2)
    axeHead.Position = Vector3.new(blockX - 0.3, extGround + 1.8, blockZ)
    axeHead.Orientation = Vector3.new(0, 0, 15)
    axeHead.Anchored = true
    axeHead.Material = Enum.Material.Metal
    axeHead.Color = Color3.fromRGB(100, 100, 110)
    axeHead.Parent = lumberYard

    -- ===== TREE STUMPS (decoration) =====
    for _, pos in ipairs({
        Vector3.new(exteriorX + 8, extGround, exteriorZ - 8),
        Vector3.new(exteriorX + 22, extGround, exteriorZ + 5),
    }) do
        local stump = Instance.new("Part")
        stump.Shape = Enum.PartType.Cylinder
        stump.Size = Vector3.new(1.5, 2.5, 2.5)
        stump.Position = pos + Vector3.new(0, 0.75, 0)
        stump.Anchored = true
        stump.Material = Enum.Material.Wood
        stump.Color = Color3.fromRGB(90, 65, 40)
        stump.Parent = lumberYard
    end

    -- ===== ENTRANCE GATE (west side, facing path) =====
    -- Gate posts
    for _, zOff in ipairs({-3, 3}) do
        local gatePost = Instance.new("Part")
        gatePost.Size = Vector3.new(1.5, 8, 1.5)
        gatePost.Position = Vector3.new(exteriorX - 5, extGround + 4, exteriorZ + zOff)
        gatePost.Anchored = true
        gatePost.Material = Enum.Material.Wood
        gatePost.Color = Color3.fromRGB(80, 55, 35)
        gatePost.Parent = lumberYard
    end

    -- Gate crossbeam
    local gateCross = Instance.new("Part")
    gateCross.Size = Vector3.new(1, 1.5, 8)
    gateCross.Position = Vector3.new(exteriorX - 5, extGround + 8, exteriorZ)
    gateCross.Anchored = true
    gateCross.Material = Enum.Material.Wood
    gateCross.Color = Color3.fromRGB(80, 55, 35)
    gateCross.Parent = lumberYard

    -- ===== LARGE SIGN WITH PRODUCTION RATE =====
    local signBoard = Instance.new("Part")
    signBoard.Name = "Sign"
    signBoard.Size = Vector3.new(0.5, 6, 14)  -- Much larger sign
    signBoard.Position = Vector3.new(exteriorX - 5.5, extGround + 11, exteriorZ)
    signBoard.Anchored = true
    signBoard.Material = Enum.Material.Wood
    signBoard.Color = Color3.fromRGB(60, 40, 25)
    signBoard.Parent = lumberYard

    local gui = Instance.new("SurfaceGui")
    gui.Face = Enum.NormalId.Left  -- Face west toward path
    gui.Parent = signBoard

    -- Title label (large)
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(1, 0, 0.6, 0)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "LUMBER YARD"
    titleLabel.TextColor3 = Color3.fromRGB(255, 230, 180)
    titleLabel.TextScaled = true
    titleLabel.Font = Enum.Font.Antique
    titleLabel.Parent = gui

    -- Production rate label (below title)
    local productionLabel = Instance.new("TextLabel")
    productionLabel.Name = "ProductionLabel"
    productionLabel.Size = UDim2.new(1, 0, 0.35, 0)
    productionLabel.Position = UDim2.new(0, 0, 0.6, 0)
    productionLabel.BackgroundTransparency = 1
    productionLabel.Text = "+0 wood/min"
    productionLabel.TextColor3 = Color3.fromRGB(180, 255, 180)  -- Green for production
    productionLabel.TextScaled = true
    productionLabel.Font = Enum.Font.GothamBold
    productionLabel.Parent = gui
    makeSignDoubleSided(signBoard)

    -- Function to update production rate display
    local function updateLumberYardProduction()
        -- Calculate production based on workers and upgrades
        local loggerCount = #LumberMillState.loggers
        local haulerCount = #LumberMillState.haulers
        local sawmillStats = getSawmillStats(LumberMillState.equipment.sawmillLevel)
        local loggerStats = getLoggerStats(LumberMillState.equipment.loggerLevel)

        -- Estimate: each logger produces ~logCapacity logs per cycle (~30 sec cycle)
        -- Sawmill converts logs to planks at planksPerLog rate
        -- Haulers deliver planks to storage

        local logsPerMinute = loggerCount * (loggerStats.logCapacity * 2)  -- ~2 cycles per minute
        local planksPerMinute = math.min(logsPerMinute, haulerCount * 10) * sawmillStats.planksPerLog

        -- Only count production if we have both loggers and haulers
        local effectiveProduction = (loggerCount > 0 and haulerCount > 0) and planksPerMinute or 0

        productionLabel.Text = string.format("+%d wood/min", effectiveProduction)

        -- Color based on production level
        if effectiveProduction == 0 then
            productionLabel.TextColor3 = Color3.fromRGB(150, 150, 150)  -- Gray when idle
        elseif effectiveProduction < 10 then
            productionLabel.TextColor3 = Color3.fromRGB(180, 255, 180)  -- Light green
        else
            productionLabel.TextColor3 = Color3.fromRGB(100, 255, 100)  -- Bright green
        end
    end

    -- Store update function for use when workers are hired
    LumberMillState.updateExteriorSign = updateLumberYardProduction

    -- Update sign periodically
    task.spawn(function()
        while true do
            updateLumberYardProduction()
            task.wait(5)  -- Update every 5 seconds
        end
    end)

    -- Torches at entrance
    createTorch(lumberYard, Vector3.new(exteriorX - 5, extGround + 6, exteriorZ - 4))
    createTorch(lumberYard, Vector3.new(exteriorX - 5, extGround + 6, exteriorZ + 4))

    -- ===== WALK-THROUGH ENTRANCE TRIGGER =====
    local entranceTrigger = Instance.new("Part")
    entranceTrigger.Name = "Entrance"
    entranceTrigger.Size = Vector3.new(2, 8, 6)
    entranceTrigger.Position = Vector3.new(exteriorX - 6, extGround + 4, exteriorZ)
    entranceTrigger.Anchored = true
    entranceTrigger.Transparency = 1
    entranceTrigger.CanCollide = false
    entranceTrigger.Parent = lumberYard

    local debounce = {}
    entranceTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if debounce[player.UserId] then return end
        debounce[player.UserId] = true
        teleportToInterior(player, "LumberMill")
        task.delay(1, function() debounce[player.UserId] = nil end)
    end)

    -- Lumber Mill visual details
    -- Sawdust pile near shed
    local sawdustPile = Instance.new("Part")
    sawdustPile.Name = "SawdustPile"
    sawdustPile.Shape = Enum.PartType.Ball
    sawdustPile.Size = Vector3.new(3, 1.5, 3)
    sawdustPile.Position = Vector3.new(exteriorX + 8, extGround + 0.5, exteriorZ + 5)
    sawdustPile.Anchored = true
    sawdustPile.Material = Enum.Material.Sand
    sawdustPile.Color = Color3.fromRGB(200, 175, 130)
    sawdustPile.CanCollide = false
    sawdustPile.Parent = lumberYard

    -- Wood shavings scattered on ground
    for ws = 1, 6 do
        local shaving = Instance.new("Part")
        shaving.Name = "WoodShaving" .. ws
        shaving.Size = Vector3.new(0.8 + math.random() * 0.5, 0.08, 0.3 + math.random() * 0.3)
        shaving.Position = Vector3.new(
            exteriorX + 3 + math.random() * 10,
            extGround + 0.05,
            exteriorZ - 3 + math.random() * 10
        )
        shaving.Orientation = Vector3.new(0, math.random() * 360, 0)
        shaving.Anchored = true
        shaving.Material = Enum.Material.Wood
        shaving.Color = Color3.fromRGB(190, 165, 120)
        shaving.CanCollide = false
        shaving.Parent = lumberYard
    end

    -- Chopping block with embedded axe
    local choppingBlock = Instance.new("Part")
    choppingBlock.Name = "ChoppingBlock"
    choppingBlock.Shape = Enum.PartType.Cylinder
    choppingBlock.Size = Vector3.new(1.5, 2, 2)
    choppingBlock.Position = Vector3.new(exteriorX + 12, extGround + 0.75, exteriorZ - 6)
    choppingBlock.Anchored = true
    choppingBlock.Material = Enum.Material.Wood
    choppingBlock.Color = Color3.fromRGB(85, 60, 35)
    choppingBlock.CanCollide = false
    choppingBlock.Parent = lumberYard

    -- Axe in chopping block
    local axeHandle = Instance.new("Part")
    axeHandle.Name = "AxeHandle"
    axeHandle.Size = Vector3.new(0.2, 2, 0.2)
    axeHandle.Position = Vector3.new(exteriorX + 12, extGround + 2.5, exteriorZ - 6)
    axeHandle.Orientation = Vector3.new(0, 0, 15)
    axeHandle.Anchored = true
    axeHandle.Material = Enum.Material.Wood
    axeHandle.Color = Color3.fromRGB(100, 70, 45)
    axeHandle.CanCollide = false
    axeHandle.Parent = lumberYard

    local axeHead = Instance.new("Part")
    axeHead.Name = "AxeHead"
    axeHead.Size = Vector3.new(0.8, 0.3, 0.15)
    axeHead.Position = Vector3.new(exteriorX + 12.2, extGround + 3.3, exteriorZ - 6)
    axeHead.Orientation = Vector3.new(0, 0, 15)
    axeHead.Anchored = true
    axeHead.Material = Enum.Material.Metal
    axeHead.Color = Color3.fromRGB(140, 140, 150)
    axeHead.CanCollide = false
    axeHead.Parent = lumberYard

    -- Stacked plank pallets
    for sp = 1, 3 do
        local plankStack = Instance.new("Part")
        plankStack.Name = "PlankPallet" .. sp
        plankStack.Size = Vector3.new(3, 0.8 + sp * 0.3, 1.5)
        plankStack.Position = Vector3.new(exteriorX - 6, extGround + (0.8 + sp * 0.3)/2, exteriorZ + 6 + (sp - 1) * 2)
        plankStack.Anchored = true
        plankStack.Material = Enum.Material.WoodPlanks
        plankStack.Color = Color3.fromRGB(190, 160, 110)
        plankStack.CanCollide = false
        plankStack.Parent = lumberYard
    end

    lumberYard.Parent = villageFolder

    -- ========== FOREST INTERIOR ==========
    local basePos = INTERIOR_POSITIONS.LumberMill
    local millModel = Instance.new("Model")
    millModel.Name = "LumberMill_Interior"

    local baseX, baseZ = basePos.X, basePos.Z
    local GROUND_Y = basePos.Y

    -- Store positions for workers (matching gold mine pattern: ±20 X, +25 Z near portal)
    LumberMillState.positions = {
        treesLeft = Vector3.new(baseX - 26, GROUND_Y, baseZ),       -- Left tree grove
        treesRight = Vector3.new(baseX + 26, GROUND_Y, baseZ),      -- Right tree grove
        sawmill = Vector3.new(baseX, GROUND_Y, baseZ - 18),         -- Sawmill in BACK center
        woodStorage = Vector3.new(baseX - 12, GROUND_Y, baseZ - 18),-- Output pile (left of sawmill)
        storageChest = Vector3.new(baseX + 12, GROUND_Y, baseZ - 18),-- Storage chest (right of sawmill)
        hireLogger = Vector3.new(baseX - 20, GROUND_Y, baseZ + 25), -- LEFT of portal (like gold mine)
        hireHauler = Vector3.new(baseX + 20, GROUND_Y, baseZ + 25), -- RIGHT of portal (like gold mine)
        upgradeKiosk = Vector3.new(baseX + 40, GROUND_Y, baseZ + 28), -- Front-right: near wall, out of the way
        workerSpawn = Vector3.new(baseX, GROUND_Y, baseZ - 10),     -- Near sawmill
    }

    -- ===== FOREST FLOOR (grass and dirt) =====
    local forestFloor = Instance.new("Part")
    forestFloor.Name = "ForestFloor"
    forestFloor.Size = Vector3.new(120, 2, 80)
    forestFloor.Position = Vector3.new(baseX, GROUND_Y - 1, baseZ)
    forestFloor.Anchored = true
    forestFloor.Material = Enum.Material.Grass
    forestFloor.Color = Color3.fromRGB(60, 90, 45)
    forestFloor.Parent = millModel

    -- Dirt path between stations
    local dirtPath = Instance.new("Part")
    dirtPath.Size = Vector3.new(100, 0.2, 8)
    dirtPath.Position = Vector3.new(baseX, GROUND_Y + 0.2, baseZ)
    dirtPath.Anchored = true
    dirtPath.Material = Enum.Material.Ground
    dirtPath.Color = Color3.fromRGB(90, 70, 50)
    dirtPath.Parent = millModel

    -- ===== FOREST BOUNDARY (trees around edge) =====
    for i = 1, 12 do
        local angle = (i / 12) * math.pi * 2
        local radius = 50
        local treeX = baseX + math.cos(angle) * radius
        local treeZ = baseZ + math.sin(angle) * radius

        local trunk = Instance.new("Part")
        trunk.Shape = Enum.PartType.Cylinder
        trunk.Size = Vector3.new(18 + math.random() * 8, 2 + math.random(), 2 + math.random())
        trunk.Position = Vector3.new(treeX, GROUND_Y + 9, treeZ)
        trunk.Orientation = Vector3.new(0, 0, 90)
        trunk.Anchored = true
        trunk.Material = Enum.Material.Wood
        trunk.Color = Color3.fromRGB(70 + math.random(20), 50 + math.random(15), 30 + math.random(10))
        trunk.Parent = millModel

        local leaves = Instance.new("Part")
        leaves.Shape = Enum.PartType.Ball
        leaves.Size = Vector3.new(10 + math.random() * 5, 12 + math.random() * 6, 10 + math.random() * 5)
        leaves.Position = Vector3.new(treeX, GROUND_Y + 20, treeZ)
        leaves.Anchored = true
        leaves.Material = Enum.Material.Grass
        leaves.Color = Color3.fromRGB(40 + math.random(30), 90 + math.random(30), 35 + math.random(20))
        leaves.Parent = millModel
    end

    -- ===== PERIMETER FENCE (prevents walking/jumping out) =====
    local fenceHeight = 4
    local fenceThickness = 0.5
    local zoneHalfX = 55  -- Half of forest floor width (120/2 - buffer)
    local zoneHalfZ = 35  -- Half of forest floor depth (80/2 - buffer)

    local fenceWalls = {
        -- North wall
        {pos = Vector3.new(baseX, GROUND_Y + fenceHeight/2, baseZ + zoneHalfZ), size = Vector3.new(zoneHalfX * 2, fenceHeight, fenceThickness)},
        -- South wall
        {pos = Vector3.new(baseX, GROUND_Y + fenceHeight/2, baseZ - zoneHalfZ), size = Vector3.new(zoneHalfX * 2, fenceHeight, fenceThickness)},
        -- East wall
        {pos = Vector3.new(baseX + zoneHalfX, GROUND_Y + fenceHeight/2, baseZ), size = Vector3.new(fenceThickness, fenceHeight, zoneHalfZ * 2)},
        -- West wall
        {pos = Vector3.new(baseX - zoneHalfX, GROUND_Y + fenceHeight/2, baseZ), size = Vector3.new(fenceThickness, fenceHeight, zoneHalfZ * 2)},
    }

    for _, fence in ipairs(fenceWalls) do
        local fencePart = Instance.new("Part")
        fencePart.Name = "PerimeterFence"
        fencePart.Size = fence.size
        fencePart.Position = fence.pos
        fencePart.Anchored = true
        fencePart.CanCollide = true
        fencePart.Material = Enum.Material.Wood
        fencePart.Color = Color3.fromRGB(100, 70, 45)
        fencePart.Parent = millModel
    end

    -- Invisible ceiling (prevents jumping over fence)
    local invisibleCeiling = Instance.new("Part")
    invisibleCeiling.Name = "InvisibleCeiling"
    invisibleCeiling.Size = Vector3.new(zoneHalfX * 2, 1, zoneHalfZ * 2)
    invisibleCeiling.Position = Vector3.new(baseX, GROUND_Y + 20, baseZ)
    invisibleCeiling.Anchored = true
    invisibleCeiling.CanCollide = true
    invisibleCeiling.Transparency = 1
    invisibleCeiling.Parent = millModel

    -- Open sky effect (bright ceiling)
    local sky = Instance.new("Part")
    sky.Size = Vector3.new(120, 1, 80)
    sky.Position = Vector3.new(baseX, GROUND_Y + 35, baseZ)
    sky.Anchored = true
    sky.Material = Enum.Material.SmoothPlastic
    sky.Color = Color3.fromRGB(135, 180, 220)
    sky.Transparency = 0.3
    sky.Parent = millModel

    -- Sunlight
    local sunlight = Instance.new("Part")
    sunlight.Size = Vector3.new(20, 1, 20)
    sunlight.Position = Vector3.new(baseX, GROUND_Y + 34, baseZ)
    sunlight.Anchored = true
    sunlight.Material = Enum.Material.Neon
    sunlight.Color = Color3.fromRGB(255, 250, 200)
    sunlight.Transparency = 0.7
    sunlight.Parent = millModel

    local sun = Instance.new("PointLight")
    sun.Brightness = 2
    sun.Range = 60
    sun.Color = Color3.fromRGB(255, 250, 220)
    sun.Parent = sunlight

    -- ========== STEP 1: TREE GROVES (BOTH SIDES) ==========
    -- Left tree grove ground
    local leftTreeGrove = Instance.new("Part")
    leftTreeGrove.Name = "LeftTreeGroveGround"
    leftTreeGrove.Size = Vector3.new(20, 0.2, 40)
    leftTreeGrove.Position = Vector3.new(baseX - 25, GROUND_Y + 0.2, baseZ)
    leftTreeGrove.Anchored = true
    leftTreeGrove.Material = Enum.Material.Grass
    leftTreeGrove.Color = Color3.fromRGB(60, 100, 45)
    leftTreeGrove.Parent = millModel

    -- Right tree grove ground
    local rightTreeGrove = Instance.new("Part")
    rightTreeGrove.Name = "RightTreeGroveGround"
    rightTreeGrove.Size = Vector3.new(20, 0.2, 40)
    rightTreeGrove.Position = Vector3.new(baseX + 25, GROUND_Y + 0.2, baseZ)
    rightTreeGrove.Anchored = true
    rightTreeGrove.Material = Enum.Material.Grass
    rightTreeGrove.Color = Color3.fromRGB(60, 100, 45)
    rightTreeGrove.Parent = millModel

    -- Store reference to millModel for tree respawn
    LumberMillState.millModel = millModel

    -- Trees on BOTH SIDES (7 trees per side = 14 total)
    local treePositions = {
        -- LEFT SIDE TREES (7 trees)
        {x = baseX - 30, z = baseZ - 12},
        {x = baseX - 22, z = baseZ - 12},
        {x = baseX - 30, z = baseZ - 4},
        {x = baseX - 22, z = baseZ - 4},
        {x = baseX - 30, z = baseZ + 4},
        {x = baseX - 22, z = baseZ + 4},
        {x = baseX - 26, z = baseZ + 12},
        -- RIGHT SIDE TREES (7 trees)
        {x = baseX + 30, z = baseZ - 12},
        {x = baseX + 22, z = baseZ - 12},
        {x = baseX + 30, z = baseZ - 4},
        {x = baseX + 22, z = baseZ - 4},
        {x = baseX + 30, z = baseZ + 4},
        {x = baseX + 22, z = baseZ + 4},
        {x = baseX + 26, z = baseZ + 12},
    }

    -- Store positions for respawn system
    LumberMillState.treePositions = treePositions

    -- Wood reward per stage (more wood for later stages)
    local woodPerStage = { [1] = 1, [2] = 2, [3] = 3, [4] = 5 }

    -- Function to create a tree model for a specific stage
    local function createChoppableTree(id, pos, stage)
        local treeModel = Instance.new("Model")
        treeModel.Name = "ChoppableTree" .. id

        if stage == 0 then
            -- Tree is gone (respawning) - just create empty model
            treeModel.Parent = millModel
            return treeModel
        end

        -- Trunk height varies by stage
        local trunkHeights = { [1] = 8, [2] = 8, [3] = 8, [4] = 2 }
        local trunkHeight = trunkHeights[stage]

        local trunk = Instance.new("Part")
        trunk.Name = "Trunk"
        trunk.Size = Vector3.new(2, trunkHeight, 2)
        trunk.Position = Vector3.new(pos.x, GROUND_Y + trunkHeight/2, pos.z)
        trunk.Anchored = true
        trunk.Material = Enum.Material.Wood
        trunk.Color = Color3.fromRGB(90, 60, 40)
        trunk.Parent = treeModel

        -- Foliage only for stages 1-2
        if stage == 1 then
            -- 3 layers of foliage (full bushy tree)
            for layer = 1, 3 do
                local size = 7 - (layer - 1) * 1.5
                local foliage = Instance.new("Part")
                foliage.Name = "Leaves" .. layer
                foliage.Shape = Enum.PartType.Ball
                foliage.Size = Vector3.new(size, size * 0.8, size)
                foliage.Position = Vector3.new(pos.x, GROUND_Y + 8 + layer * 2, pos.z)
                foliage.Anchored = true
                foliage.Material = Enum.Material.Grass
                foliage.Color = Color3.fromRGB(50, 110, 40)
                foliage.Parent = treeModel
            end
        elseif stage == 2 then
            -- 2 smaller layers (less bushy)
            for layer = 1, 2 do
                local size = 5 - (layer - 1) * 1.2
                local foliage = Instance.new("Part")
                foliage.Name = "Leaves" .. layer
                foliage.Shape = Enum.PartType.Ball
                foliage.Size = Vector3.new(size, size * 0.7, size)
                foliage.Position = Vector3.new(pos.x, GROUND_Y + 8 + layer * 2, pos.z)
                foliage.Anchored = true
                foliage.Material = Enum.Material.Grass
                foliage.Color = Color3.fromRGB(55, 100, 45)
                foliage.Parent = treeModel
            end
        end
        -- Stages 3-4: no foliage (trunk only / stump)

        treeModel.Parent = millModel
        return treeModel
    end

    -- Function to spawn wood chip particles
    local function spawnWoodChips(pos)
        local chipPart = Instance.new("Part")
        chipPart.Name = "ChipEmitter"
        chipPart.Size = Vector3.new(1, 1, 1)
        chipPart.Position = Vector3.new(pos.x, GROUND_Y + 3, pos.z)
        chipPart.Anchored = true
        chipPart.Transparency = 1
        chipPart.CanCollide = false
        chipPart.Parent = millModel

        local chips = Instance.new("ParticleEmitter")
        chips.Color = ColorSequence.new(Color3.fromRGB(180, 140, 90))
        chips.Size = NumberSequence.new(0.3)
        chips.Lifetime = NumberRange.new(0.3, 0.6)
        chips.Rate = 30
        chips.Speed = NumberRange.new(4, 8)
        chips.SpreadAngle = Vector2.new(45, 45)
        chips.Parent = chipPart

        task.delay(0.5, function()
            chipPart:Destroy()
        end)
    end

    -- Function to update tree visual (destroy old, create new)
    local function updateTreeVisual(id, stage)
        local pos = LumberMillState.treePositions[id]
        if not pos then return end

        -- Remove old model
        if LumberMillState.treeModels[id] then
            LumberMillState.treeModels[id]:Destroy()
        end

        -- Create new model for stage
        LumberMillState.treeModels[id] = createChoppableTree(id, pos, stage)

        -- Re-add interaction if tree is choppable (stage 1-4)
        if stage >= 1 and stage <= 4 then
            local treeModel = LumberMillState.treeModels[id]
            local trunk = treeModel:FindFirstChild("Trunk")
            if trunk then
                createInteraction(trunk, "Chop Tree", "Tree #" .. id, 1.0, function(player)
                    local currentStage = LumberMillState.treeStage[id]
                    if not currentStage or currentStage == 0 then
                        return -- Tree is gone/respawning
                    end

                    local currentLogs = getPlayerLogs(player)
                    if currentLogs >= 8 then
                        print(string.format("[LumberMill] %s: Carrying max logs! Take them to the sawmill.", player.Name))
                        return
                    end

                    -- Award wood based on current stage
                    local woodGained = woodPerStage[currentStage] or 1
                    local axeLevel = LumberMillState.equipment.axeLevel
                    local stats = getAxeStats(axeLevel)
                    woodGained = woodGained * stats.logsPerChop
                    setPlayerLogs(player, currentLogs + woodGained)
                    updatePlayerLogVisual(player, getPlayerLogs(player))
                    addLumberXP(5 + currentStage * 2)

                    -- Progress to next stage
                    local newStage = currentStage + 1
                    local stageNames = { [1] = "full", [2] = "thinned", [3] = "trunk only", [4] = "stump", [0] = "gone" }

                    if newStage > 4 then
                        newStage = 0 -- Gone (respawning)
                        LumberMillState.treeRespawn[id] = os.time() + 15
                        print(string.format("[LumberMill] %s felled tree #%d completely! +%d logs (Carrying: %d/8). Respawns in 15s.",
                            player.Name, id, woodGained, getPlayerLogs(player)))
                    else
                        print(string.format("[LumberMill] %s chopped tree #%d (now %s). +%d logs (Carrying: %d/8)",
                            player.Name, id, stageNames[newStage], woodGained, getPlayerLogs(player)))
                    end

                    LumberMillState.treeStage[id] = newStage

                    -- Update visual
                    updateTreeVisual(id, newStage)

                    -- Wood chip particles
                    spawnWoodChips(pos)
                end, true) -- allowVisitors: visitors can chop trees for the owner
            end
        end
    end

    -- Store the update function in state
    LumberMillState.updateTreeVisual = updateTreeVisual

    -- Initialize all trees at stage 1 (full)
    for i, pos in ipairs(treePositions) do
        LumberMillState.treeStage[i] = 1
        LumberMillState.treeModels[i] = createChoppableTree(i, pos, 1)

        -- Add initial interaction
        local trunk = LumberMillState.treeModels[i]:FindFirstChild("Trunk")
        if trunk then
            local treeId = i  -- Capture in closure
            createInteraction(trunk, "Chop Tree", "Tree #" .. treeId, 1.0, function(player)
                local currentStage = LumberMillState.treeStage[treeId]
                if not currentStage or currentStage == 0 then
                    return -- Tree is gone/respawning
                end

                local currentLogs = getPlayerLogs(player)
                if currentLogs >= 8 then
                    print(string.format("[LumberMill] %s: Carrying max logs! Take them to the sawmill.", player.Name))
                    return
                end

                -- Award wood based on current stage
                local woodGained = woodPerStage[currentStage] or 1
                local axeLevel = LumberMillState.equipment.axeLevel
                local stats = getAxeStats(axeLevel)
                woodGained = woodGained * stats.logsPerChop
                setPlayerLogs(player, currentLogs + woodGained)
                updatePlayerLogVisual(player, getPlayerLogs(player))
                addLumberXP(5 + currentStage * 2)

                -- Progress to next stage
                local newStage = currentStage + 1
                local stageNames = { [1] = "full", [2] = "thinned", [3] = "trunk only", [4] = "stump", [0] = "gone" }
                local treePos = LumberMillState.treePositions[treeId]

                if newStage > 4 then
                    newStage = 0 -- Gone (respawning)
                    LumberMillState.treeRespawn[treeId] = os.time() + 15
                    print(string.format("[LumberMill] %s felled tree #%d completely! +%d logs (Carrying: %d/8). Respawns in 15s.",
                        player.Name, treeId, woodGained, getPlayerLogs(player)))
                else
                    print(string.format("[LumberMill] %s chopped tree #%d (now %s). +%d logs (Carrying: %d/8)",
                        player.Name, treeId, stageNames[newStage], woodGained, getPlayerLogs(player)))
                end

                LumberMillState.treeStage[treeId] = newStage

                -- Update visual
                updateTreeVisual(treeId, newStage)

                -- Wood chip particles
                spawnWoodChips(treePos)
            end, true) -- allowVisitors: visitors can chop trees for the owner
        end
    end

    -- Tree respawn loop (check every second)
    task.spawn(function()
        while true do
            task.wait(1)
            local now = os.time()
            for id, respawnTime in pairs(LumberMillState.treeRespawn) do
                if now >= respawnTime then
                    LumberMillState.treeStage[id] = 1
                    LumberMillState.treeRespawn[id] = nil
                    updateTreeVisual(id, 1)
                    print(string.format("[LumberMill] Tree #%d has regrown!", id))
                end
            end
        end
    end)

    -- Axe display near trees
    local axeDisplay = Instance.new("Part")
    axeDisplay.Name = "AxeDisplay"
    axeDisplay.Size = Vector3.new(0.3, 3.5, 0.3)
    axeDisplay.Position = Vector3.new(baseX - 12, GROUND_Y + 1.8, baseZ + 8)
    axeDisplay.Orientation = Vector3.new(0, 0, -30)
    axeDisplay.Anchored = true
    axeDisplay.Material = Enum.Material.Wood
    axeDisplay.Color = Color3.fromRGB(100, 70, 45)
    axeDisplay.Parent = millModel

    -- Axe head
    local axeHead = Instance.new("Part")
    axeHead.Name = "AxeHead"
    axeHead.Size = Vector3.new(0.3, 1.2, 1.8)
    axeHead.Position = Vector3.new(baseX - 13, GROUND_Y + 3.8, baseZ + 8)
    axeHead.Orientation = Vector3.new(0, 0, -30)
    axeHead.Anchored = true
    axeHead.Material = Enum.Material.Metal
    axeHead.Color = Color3.fromRGB(140, 140, 145)
    axeHead.Parent = millModel

    -- Chopping stump
    local stump = Instance.new("Part")
    stump.Name = "ChoppingStump"
    stump.Shape = Enum.PartType.Cylinder
    stump.Size = Vector3.new(1.5, 3, 3)
    stump.Position = Vector3.new(baseX - 12, GROUND_Y + 0.75, baseZ + 8)
    stump.Anchored = true
    stump.Material = Enum.Material.Wood
    stump.Color = Color3.fromRGB(80, 55, 35)
    stump.Parent = millModel

    -- Signs for both tree groves
    createSign(millModel, "TREES", Vector3.new(baseX - 26, GROUND_Y + 4, baseZ + 16), Vector3.new(4, 1.2, 0.3))
    createSign(millModel, "TREES", Vector3.new(baseX + 26, GROUND_Y + 4, baseZ + 16), Vector3.new(4, 1.2, 0.3))

    -- ========== STEP 2: SAWMILL STATION (IN BACK) ==========
    local sawmillZ = baseZ - 18  -- Back of the lumber yard

    -- Sawmill table
    local sawmillTable = Instance.new("Part")
    sawmillTable.Name = "SawmillTable"
    sawmillTable.Size = Vector3.new(8, 3, 4)
    sawmillTable.Position = Vector3.new(baseX, GROUND_Y + 1.5, sawmillZ)
    sawmillTable.Anchored = true
    sawmillTable.Material = Enum.Material.Wood
    sawmillTable.Color = Color3.fromRGB(80, 55, 35)
    sawmillTable.Parent = millModel

    -- Saw blade (large circular)
    local sawBlade = Instance.new("Part")
    sawBlade.Name = "SawBlade"
    sawBlade.Shape = Enum.PartType.Cylinder
    sawBlade.Size = Vector3.new(0.5, 5, 5)
    sawBlade.Position = Vector3.new(baseX + 4, GROUND_Y + 4, sawmillZ)
    sawBlade.Orientation = Vector3.new(0, 0, 90)
    sawBlade.Anchored = true
    sawBlade.Material = Enum.Material.Metal
    sawBlade.Color = Color3.fromRGB(160, 160, 165)
    sawBlade.Parent = millModel

    -- Saw blade teeth marks
    local sawTeeth = Instance.new("Part")
    sawTeeth.Name = "SawTeeth"
    sawTeeth.Shape = Enum.PartType.Cylinder
    sawTeeth.Size = Vector3.new(0.3, 5.5, 5.5)
    sawTeeth.Position = Vector3.new(baseX + 4.1, GROUND_Y + 4, sawmillZ)
    sawTeeth.Orientation = Vector3.new(0, 0, 90)
    sawTeeth.Anchored = true
    sawTeeth.Material = Enum.Material.DiamondPlate
    sawTeeth.Color = Color3.fromRGB(120, 120, 125)
    sawTeeth.Parent = millModel

    -- Log being cut (on table)
    local cuttingLog = Instance.new("Part")
    cuttingLog.Name = "CuttingLog"
    cuttingLog.Shape = Enum.PartType.Cylinder
    cuttingLog.Size = Vector3.new(6, 1.8, 1.8)
    cuttingLog.Position = Vector3.new(baseX, GROUND_Y + 3.5, sawmillZ)
    cuttingLog.Orientation = Vector3.new(0, 90, 0)
    cuttingLog.Anchored = true
    cuttingLog.Material = Enum.Material.Wood
    cuttingLog.Color = Color3.fromRGB(100, 70, 50)
    cuttingLog.Parent = millModel

    -- Sawdust pile
    local sawdust = Instance.new("Part")
    sawdust.Name = "Sawdust"
    sawdust.Size = Vector3.new(5, 1.5, 5)
    sawdust.Position = Vector3.new(baseX, GROUND_Y + 0.75, sawmillZ + 5)
    sawdust.Anchored = true
    sawdust.Material = Enum.Material.Sand
    sawdust.Color = Color3.fromRGB(210, 190, 150)
    sawdust.Parent = millModel

    createSign(millModel, "SAWMILL", Vector3.new(baseX, GROUND_Y + 6, sawmillZ + 3), Vector3.new(4, 1.5, 0.3))

    -- ===== SAWMILL PROGRESS BAR UI =====
    local sawmillBillboard = Instance.new("BillboardGui")
    sawmillBillboard.Name = "SawmillStatus"
    sawmillBillboard.Size = UDim2.new(8, 0, 2, 0)
    sawmillBillboard.StudsOffset = Vector3.new(0, 5, 3)
    sawmillBillboard.AlwaysOnTop = true
    sawmillBillboard.Parent = sawmillTable

    local sawmillTitle = Instance.new("TextLabel")
    sawmillTitle.Name = "Title"
    sawmillTitle.Size = UDim2.new(1, 0, 0.4, 0)
    sawmillTitle.Position = UDim2.new(0, 0, 0, 0)
    sawmillTitle.BackgroundTransparency = 1
    sawmillTitle.Text = "SAWMILL"
    sawmillTitle.TextColor3 = Color3.fromRGB(180, 140, 90)
    sawmillTitle.TextStrokeTransparency = 0.3
    sawmillTitle.TextScaled = true
    sawmillTitle.Font = Enum.Font.GothamBold
    sawmillTitle.Parent = sawmillBillboard

    local sawmillProgressFrame = Instance.new("Frame")
    sawmillProgressFrame.Name = "ProgressFrame"
    sawmillProgressFrame.Size = UDim2.new(0.8, 0, 0.2, 0)
    sawmillProgressFrame.Position = UDim2.new(0.1, 0, 0.4, 0)
    sawmillProgressFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    sawmillProgressFrame.BorderSizePixel = 2
    sawmillProgressFrame.BorderColor3 = Color3.fromRGB(100, 100, 100)
    sawmillProgressFrame.Parent = sawmillBillboard

    local sawmillProgressBar = Instance.new("Frame")
    sawmillProgressBar.Name = "ProgressBar"
    sawmillProgressBar.Size = UDim2.new(0, 0, 1, 0)
    sawmillProgressBar.Position = UDim2.new(0, 0, 0, 0)
    sawmillProgressBar.BackgroundColor3 = Color3.fromRGB(180, 140, 90)
    sawmillProgressBar.BorderSizePixel = 0
    sawmillProgressBar.Parent = sawmillProgressFrame

    local sawmillStatusText = Instance.new("TextLabel")
    sawmillStatusText.Name = "StatusText"
    sawmillStatusText.Size = UDim2.new(1, 0, 0.35, 0)
    sawmillStatusText.Position = UDim2.new(0, 0, 0.65, 0)
    sawmillStatusText.BackgroundTransparency = 1
    sawmillStatusText.Text = "Idle - Waiting for logs"
    sawmillStatusText.TextColor3 = Color3.fromRGB(200, 200, 200)
    sawmillStatusText.TextStrokeTransparency = 0.5
    sawmillStatusText.TextScaled = true
    sawmillStatusText.Font = Enum.Font.Gotham
    sawmillStatusText.Parent = sawmillBillboard

    -- Function to update sawmill UI
    local function updateSawmillUI(status, progress)
        sawmillStatusText.Text = status
        sawmillProgressBar.Size = UDim2.new(progress, 0, 1, 0)
        if progress > 0 then
            sawmillProgressBar.BackgroundColor3 = Color3.fromRGB(180, 140, 90)
        end
    end

    -- Store for access from worker loops
    LumberMillState.updateSawmillUI = updateSawmillUI

    -- ===== INDEPENDENT SAWMILL PROCESSING LOOP =====
    -- Runs continuously, processes log queue one at a time
    -- Progress bar fills 0→100% for EACH log
    task.spawn(function()
        while true do
            if LumberMillState.sawmillLogs > 0 then
                -- Get current sawmill stats (rechecks each log for live upgrades)
                local sawmillStats = getSawmillStats(LumberMillState.equipment.sawmillLevel)
                local basePlanksPerLog = sawmillStats.planksPerLog
                local baseProcessTime = sawmillStats.processTime

                -- Apply production and speed bonuses from Town Hall
                local productionMultiplier = 1.0
                local speedMultiplier = 1.0
                if TownHallState and calculateTotalBonuses then
                    local bonuses = calculateTotalBonuses()
                    productionMultiplier = bonuses.production.sawmill or 1.0
                    speedMultiplier = bonuses.speed.sawmill or 1.0
                end
                local planksPerLog = math.floor(basePlanksPerLog * productionMultiplier)
                local processTime = baseProcessTime / speedMultiplier -- faster = divide time

                -- Process one log at a time
                while LumberMillState.sawmillLogs > 0 do
                    -- Recheck stats each log (in case player upgrades mid-batch)
                    sawmillStats = getSawmillStats(LumberMillState.equipment.sawmillLevel)
                    basePlanksPerLog = sawmillStats.planksPerLog
                    baseProcessTime = sawmillStats.processTime

                    -- Re-apply bonuses
                    if TownHallState and calculateTotalBonuses then
                        local bonuses = calculateTotalBonuses()
                        productionMultiplier = bonuses.production.sawmill or 1.0
                        speedMultiplier = bonuses.speed.sawmill or 1.0
                    end
                    planksPerLog = math.floor(basePlanksPerLog * productionMultiplier)
                    processTime = baseProcessTime / speedMultiplier

                    local logsRemaining = LumberMillState.sawmillLogs

                    -- Animate progress bar from 0 to 100% for this single log
                    local steps = 20  -- Number of progress updates
                    local stepTime = processTime / steps

                    for step = 1, steps do
                        local progress = step / steps
                        updateSawmillUI(
                            string.format("Sawing... %d logs queued | Lv%d: %dp/log",
                                logsRemaining, LumberMillState.equipment.sawmillLevel, planksPerLog),
                            progress
                        )
                        task.wait(stepTime)
                    end

                    -- Convert one log to planks
                    LumberMillState.sawmillLogs = LumberMillState.sawmillLogs - 1
                    LumberMillState.woodStorage = LumberMillState.woodStorage + planksPerLog
                    addLumberXP(10)

                    -- Update plank pile visuals immediately
                    if LumberMillState.updatePlankPileVisuals then
                        LumberMillState.updatePlankPileVisuals()
                    end

                    -- Brief flash at 100% before resetting for next log
                    updateSawmillUI(
                        string.format("+%d planks! (%d logs left)", planksPerLog, LumberMillState.sawmillLogs),
                        1
                    )
                    task.wait(0.2)

                    print(string.format("[Sawmill Lv%d] 1 log → +%d planks (Queue: %d, Ready: %d)",
                        LumberMillState.equipment.sawmillLevel, planksPerLog, LumberMillState.sawmillLogs, LumberMillState.woodStorage))
                end

                -- Done processing batch
                updateSawmillUI(
                    string.format("Ready: %d planks | Idle", LumberMillState.woodStorage),
                    0
                )
            else
                -- Idle state
                local sawmillStats = getSawmillStats(LumberMillState.equipment.sawmillLevel)
                if LumberMillState.woodStorage > 0 then
                    updateSawmillUI(
                        string.format("Ready: %d planks | Lv%d Sawmill", LumberMillState.woodStorage, LumberMillState.equipment.sawmillLevel),
                        0
                    )
                else
                    updateSawmillUI(string.format("Idle | Lv%d: %dp/log, %.1fs",
                        LumberMillState.equipment.sawmillLevel, sawmillStats.planksPerLog, sawmillStats.processTime), 0)
                end
                task.wait(1) -- Check for logs every second
            end
        end
    end)

    -- ===== SAWMILL WALK-THROUGH SYSTEM =====
    -- Input side: Drop off logs for processing (now just adds to queue)
    local sawmillInputTrigger = Instance.new("Part")
    sawmillInputTrigger.Name = "SawmillInputTrigger"
    sawmillInputTrigger.Size = Vector3.new(10, 5, 8)
    sawmillInputTrigger.Position = Vector3.new(baseX, GROUND_Y + 2.5, sawmillZ)
    sawmillInputTrigger.Anchored = true
    sawmillInputTrigger.Transparency = 1
    sawmillInputTrigger.CanCollide = false
    sawmillInputTrigger.Parent = millModel

    local sawmillInputDebounce = {}
    sawmillInputTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if sawmillInputDebounce[player.UserId] then return end

        local currentLogs = getPlayerLogs(player)
        if currentLogs > 0 then
            sawmillInputDebounce[player.UserId] = true

            -- Deposit logs to sawmill queue (independent sawmill loop will process it)
            LumberMillState.sawmillLogs = LumberMillState.sawmillLogs + currentLogs
            setPlayerLogs(player, 0)

            -- Remove visual from player
            local backpack = character:FindFirstChild("LogBackpack")
            if backpack then backpack:Destroy() end

            print(string.format("[LumberMill] %s loaded %d logs into sawmill! (Queue: %d)",
                player.Name, currentLogs, LumberMillState.sawmillLogs))

            -- Sawdust particles
            local dust = Instance.new("ParticleEmitter")
            dust.Color = ColorSequence.new(Color3.fromRGB(220, 200, 160))
            dust.Size = NumberSequence.new(0.4)
            dust.Lifetime = NumberRange.new(0.5, 1)
            dust.Rate = 30
            dust.Speed = NumberRange.new(2, 5)
            dust.SpreadAngle = Vector2.new(30, 30)
            dust.Parent = sawBlade
            task.delay(0.8, function() dust:Destroy() end)

            task.delay(1.5, function() sawmillInputDebounce[player.UserId] = nil end)
        end
    end)

    -- ========== STEP 3: OUTPUT PILE (COLLECT PLANKS) - Left of sawmill ==========
    local outputPilePos = Vector3.new(baseX - 12, GROUND_Y, sawmillZ)

    local outputPile = Instance.new("Part")
    outputPile.Name = "OutputPileBase"
    outputPile.Size = Vector3.new(8, 0.4, 6)
    outputPile.Position = outputPilePos + Vector3.new(0, 0.2, 0)
    outputPile.Anchored = true
    outputPile.Material = Enum.Material.Concrete
    outputPile.Color = Color3.fromRGB(110, 105, 100)
    outputPile.Parent = millModel

    -- ===== VISUAL PLANK PILE SYSTEM =====
    local plankPileContainer = Instance.new("Folder")
    plankPileContainer.Name = "PlankPileVisuals"
    plankPileContainer.Parent = millModel

    local visualPlanks = {}
    local MAX_VISIBLE_PLANKS = 30  -- 1:1 ratio with planks (up to 30 shown)

    -- Function to update visual planks based on woodStorage count (1 visual per plank)
    local function updatePlankPileVisuals()
        local planksToShow = math.min(LumberMillState.woodStorage, MAX_VISIBLE_PLANKS)

        for i = 1, MAX_VISIBLE_PLANKS do
            if not visualPlanks[i] then
                -- Create plank - stacked in neat rows
                local plank = Instance.new("Part")
                plank.Name = "StoragePlank" .. i
                plank.Size = Vector3.new(3, 0.2, 0.6)  -- Smaller, neater planks
                local layer = math.floor((i - 1) / 10)  -- 10 planks per layer
                local row = math.floor(((i - 1) % 10) / 5)  -- 5 planks per row
                local col = (i - 1) % 5
                plank.Position = outputPilePos + Vector3.new(
                    -1.2 + col * 0.65,           -- X: spread across
                    0.5 + layer * 0.25,          -- Y: stack up
                    -0.8 + row * 0.7             -- Z: front/back rows
                )
                plank.Orientation = Vector3.new(0, 90, 0)  -- All aligned
                plank.Anchored = true
                plank.CanCollide = false
                plank.Material = Enum.Material.Wood
                plank.Color = Color3.fromRGB(200, 170, 120)
                plank.Parent = plankPileContainer
                visualPlanks[i] = plank
            end

            visualPlanks[i].Transparency = (i <= planksToShow) and 0 or 1
        end
    end

    -- Store function in state
    LumberMillState.updatePlankPileVisuals = updatePlankPileVisuals

    createSign(millModel, "PLANKS", outputPilePos + Vector3.new(0, 4, 3), Vector3.new(3, 1, 0.3))

    -- WALK-THROUGH: Collect Planks (pick up planks when walking by)
    local plankPickupTrigger = Instance.new("Part")
    plankPickupTrigger.Name = "PlankPickupTrigger"
    plankPickupTrigger.Size = Vector3.new(10, 5, 8)
    plankPickupTrigger.Position = outputPilePos + Vector3.new(0, 2.5, 0)
    plankPickupTrigger.Anchored = true
    plankPickupTrigger.Transparency = 1
    plankPickupTrigger.CanCollide = false
    plankPickupTrigger.Parent = millModel

    local plankPickupDebounce = {}
    plankPickupTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if plankPickupDebounce[player.UserId] then return end

        local currentPlanks = getPlayerPlanks(player)
        local maxCarry = 30

        if LumberMillState.woodStorage > 0 and currentPlanks < maxCarry then
            plankPickupDebounce[player.UserId] = true

            -- Pick up planks
            local planksToTake = math.min(LumberMillState.woodStorage, maxCarry - currentPlanks)
            LumberMillState.woodStorage = LumberMillState.woodStorage - planksToTake
            setPlayerPlanks(player, currentPlanks + planksToTake)

            -- Add visual to player
            updatePlayerPlankVisual(player, currentPlanks + planksToTake)

            -- Update pile visuals
            updatePlankPileVisuals()

            print(string.format("[LumberMill] %s picked up %d planks! (Carrying: %d/%d)",
                player.Name, planksToTake, getPlayerPlanks(player), maxCarry))

            -- Wood pickup sound effect
            local pickup = Instance.new("ParticleEmitter")
            pickup.Color = ColorSequence.new(Color3.fromRGB(200, 170, 120))
            pickup.Size = NumberSequence.new(0.2)
            pickup.Lifetime = NumberRange.new(0.2, 0.4)
            pickup.Rate = 15
            pickup.Speed = NumberRange.new(3, 6)
            pickup.Parent = outputPile
            task.delay(0.4, function() pickup:Destroy() end)

            task.delay(1, function() plankPickupDebounce[player.UserId] = nil end)
        end
    end)

    -- ========== STEP 4: STORAGE CHEST (Right of sawmill in back) ==========
    local storageChestPos = Vector3.new(baseX + 12, GROUND_Y, sawmillZ)

    local storageChest = Instance.new("Part")
    storageChest.Name = "StorageChest"
    storageChest.Size = Vector3.new(4, 3, 3)
    storageChest.Position = storageChestPos + Vector3.new(0, 1.5, 0)
    storageChest.Anchored = true
    storageChest.Material = Enum.Material.Wood
    storageChest.Color = Color3.fromRGB(100, 70, 45)
    storageChest.Parent = millModel

    -- Chest lid
    local chestLid = Instance.new("Part")
    chestLid.Name = "ChestLid"
    chestLid.Size = Vector3.new(4.2, 0.4, 3.2)
    chestLid.Position = storageChestPos + Vector3.new(0, 3.2, 0)
    chestLid.Anchored = true
    chestLid.Material = Enum.Material.Wood
    chestLid.Color = Color3.fromRGB(80, 55, 35)
    chestLid.Parent = millModel

    -- Metal bands on chest
    for i = 1, 2 do
        local band = Instance.new("Part")
        band.Size = Vector3.new(4.4, 0.2, 0.2)
        band.Position = storageChestPos + Vector3.new(0, 1 + i * 0.8, 1.5)
        band.Anchored = true
        band.Material = Enum.Material.Metal
        band.Color = Color3.fromRGB(60, 55, 50)
        band.Parent = millModel
    end

    createSign(millModel, "STORAGE", storageChestPos + Vector3.new(0, 5, 2), Vector3.new(4, 1, 0.3))

    local storageChestTrigger = Instance.new("Part")
    storageChestTrigger.Name = "StorageChestTrigger"
    storageChestTrigger.Size = Vector3.new(6, 5, 5)
    storageChestTrigger.Position = storageChestPos + Vector3.new(0, 2.5, 0)
    storageChestTrigger.Anchored = true
    storageChestTrigger.Transparency = 1
    storageChestTrigger.CanCollide = false
    storageChestTrigger.Parent = millModel

    local storageChestDebounce = {}
    storageChestTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if storageChestDebounce[player.UserId] then return end

        local playerCarriedPlanks = getPlayerPlanks(player)
        if playerCarriedPlanks > 0 then
            storageChestDebounce[player.UserId] = true

            -- DEPOSIT: Player carrying planks
            local planksToDeposit = playerCarriedPlanks
            setPlayerPlanks(player, 0)

            -- Remove visual from player
            local backpack = character:FindFirstChild("PlankBackpack")
            if backpack then backpack:Destroy() end

            -- REWARD the player!
            rewardPlayer(player, "wood", planksToDeposit, "LumberMill")

            print(string.format("[LumberMill] %s stored %d planks! (+%d wood)",
                player.Name, planksToDeposit, planksToDeposit))

            -- Storage sparkle effect
            local sparkle = Instance.new("ParticleEmitter")
            sparkle.Color = ColorSequence.new(Color3.fromRGB(200, 180, 140))
            sparkle.Size = NumberSequence.new(0.3, 0)
            sparkle.Lifetime = NumberRange.new(0.4, 0.8)
            sparkle.Rate = 30
            sparkle.Speed = NumberRange.new(3, 6)
            sparkle.SpreadAngle = Vector2.new(60, 60)
            sparkle.Parent = storageChest
            task.delay(0.6, function() sparkle:Destroy() end)

            task.delay(1, function() storageChestDebounce[player.UserId] = nil end)
        end
    end)

    -- ========== STEP 5: HIRE LOGGERS (LEFT of portal, like gold mine) ==========
    local hiringArea = LumberMillState.positions.hireLogger

    local loggerBoard = Instance.new("Part")
    loggerBoard.Name = "LoggerHiringBoard"
    loggerBoard.Size = Vector3.new(5, 4, 0.5)
    loggerBoard.Position = hiringArea + Vector3.new(0, 2.5, 0)
    loggerBoard.Anchored = true
    loggerBoard.Material = Enum.Material.Wood
    loggerBoard.Color = Color3.fromRGB(100, 70, 50)
    loggerBoard.Parent = millModel

    createSign(millModel, "HIRE LOGGERS", hiringArea + Vector3.new(0, 5, 0), Vector3.new(6, 1.2, 0.3))

    -- Waiting logger NPCs (stored in array like gold mine)
    LumberMillState.waitingLoggers = {}
    for i = 1, 3 do
        local waitingLoggerPos = Vector3.new(hiringArea.X + (i - 2) * 3, GROUND_Y, hiringArea.Z - 2)
        local waitingLogger = createWorkerNPC(
            "Logger " .. i,
            waitingLoggerPos,
            Color3.fromRGB(180, 50, 50), -- Red plaid
            "Logger"
        )
        setNPCStatus(waitingLogger, "For hire!")
        waitingLogger.Parent = millModel
        table.insert(LumberMillState.waitingLoggers, waitingLogger)
    end

    -- INTERACTION: Hire Logger
    createInteraction(loggerBoard, "Hire Logger (1,200g + 240f)", "Hiring Board", 1, function(player)
        local loggerCount = #LumberMillState.loggers
        local maxLoggers = 3

        if loggerCount >= maxLoggers then
            print(string.format("[LumberMill] %s: Max loggers (3) reached!", player.Name))
            notifyPlayer(player, "HireWorker", false, "Max loggers (3) already hired!")
            return
        end

        -- Check if there are waiting workers
        if #LumberMillState.waitingLoggers == 0 then
            print(string.format("[LumberMill] %s: No loggers available to hire!", player.Name))
            notifyPlayer(player, "HireWorker", false, "No loggers available to hire!")
            return
        end

        local cost = LoggerCosts[loggerCount + 1]
        if not deductPlayerResources(player, {gold = cost.gold, food = cost.food}, "LumberMill") then
            notifyPlayer(player, "HireWorker", false, string.format("Need %dg + %df to hire!", cost.gold, cost.food))
            return
        end
        notifyPlayer(player, "HireWorker", true, "Logger hired!")
        local loggerId = loggerCount + 1

        -- Remove one waiting worker from the stand (they walk away to work)
        local waitingWorker = table.remove(LumberMillState.waitingLoggers, 1)
        if waitingWorker then
            -- Make the waiting worker walk away before destroying
            setNPCStatus(waitingWorker, "Hired!")
            task.spawn(function()
                local walkAwayPos = LumberMillState.positions.workerSpawn + Vector3.new(loggerCount * 3, 0, 0)
                walkNPCTo(waitingWorker, walkAwayPos, 6, function()
                    _npcAnimTracks[waitingWorker] = nil
                    waitingWorker:Destroy()
                end)
            end)
        end

        -- Check if booth is now empty
        if #LumberMillState.waitingLoggers == 0 then
            print("[LumberMill] Logger booth is now empty!")
        end

        -- Create visible logger NPC at hiring booth (walks to work from there)
        local spawnPos = LumberMillState.positions.hireLogger
        local logger = createWorkerNPC(
            "Logger " .. loggerId,
            spawnPos,
            Color3.fromRGB(180, 50, 50), -- Red plaid work clothes
            "Logger"
        )
        logger.Parent = millModel

        local loggerData = {
            npc = logger,
            state = "idle",
            carrying = 0,
        }
        table.insert(LumberMillState.loggers, loggerData)

        -- Start logger AI loop with async completion-flag pattern
        task.spawn(function()
            while loggerData.npc and loggerData.npc.Parent do
                local cycleComplete = false

                -- Get current logger stats (updates each cycle based on upgrades)
                local loggerStats = getLoggerStats(LumberMillState.equipment.loggerLevel)
                local logCapacity = loggerStats.logCapacity
                local walkSpeed = loggerStats.walkSpeed
                local choppingTime = loggerStats.choppingTime

                -- Find an available tree (stage 1-4)
                local targetTreeId = nil
                local targetTreePos = nil
                for treeId, stage in pairs(LumberMillState.treeStage) do
                    if stage and stage >= 1 and stage <= 4 then
                        targetTreeId = treeId
                        targetTreePos = LumberMillState.treePositions[treeId]
                        break
                    end
                end

                if targetTreeId and targetTreePos then
                    -- Walk to the actual tree
                    loggerData.state = "walking_to_trees"
                    setNPCStatus(logger, string.format("Going to tree #%d...", targetTreeId))
                    local treePos = Vector3.new(targetTreePos.x, GROUND_Y, targetTreePos.z)
                    walkNPCTo(logger, treePos + Vector3.new(2, 0, 0), walkSpeed, function()
                        -- Chop the actual tree through its stages
                        loggerData.state = "chopping"
                        local logsCollected = 0
                        local woodPerStage = { 1, 2, 3, 5 }  -- Same as player chopping

                        -- Chop until we have enough logs or tree is gone
                        while logsCollected < logCapacity do
                            local currentStage = LumberMillState.treeStage[targetTreeId]
                            if not currentStage or currentStage == 0 then
                                break -- Tree is gone
                            end

                            setNPCStatus(logger, string.format("Chopping tree #%d (%d logs)", targetTreeId, logsCollected))

                            -- Wood chip particle effect
                            local torso = logger:FindFirstChild("UpperTorso") or logger:FindFirstChild("Torso")
                            if torso then
                                local chips = Instance.new("ParticleEmitter")
                                chips.Color = ColorSequence.new(Color3.fromRGB(180, 140, 90))
                                chips.Size = NumberSequence.new(0.3)
                                chips.Lifetime = NumberRange.new(0.3, 0.5)
                                chips.Rate = 20
                                chips.Speed = NumberRange.new(3, 6)
                                chips.SpreadAngle = Vector2.new(30, 30)
                                chips.Parent = torso
                                task.delay(0.4, function() chips:Destroy() end)
                            end

                            task.wait(choppingTime)

                            -- Progress tree to next stage
                            local newStage = currentStage + 1
                            local logsFromChop = woodPerStage[currentStage] or 1
                            logsCollected = logsCollected + logsFromChop

                            if newStage > 4 then
                                newStage = 0
                                LumberMillState.treeRespawn[targetTreeId] = os.time() + 15
                                print(string.format("[Logger #%d] Felled tree #%d! +%d logs", loggerId, targetTreeId, logsFromChop))
                            end

                            LumberMillState.treeStage[targetTreeId] = newStage
                            if LumberMillState.updateTreeVisual then
                                LumberMillState.updateTreeVisual(targetTreeId, newStage)
                            end
                        end

                        -- Pick up collected logs
                        loggerData.carrying = logsCollected
                        setNPCCarrying(logger, "logs", math.min(5, math.ceil(logsCollected / 3)))
                        setNPCStatus(logger, string.format("Carrying %d logs", logsCollected))
                        print(string.format("[Logger #%d] Collected %d logs from tree #%d", loggerId, logsCollected, targetTreeId))

                        -- Walk to sawmill input
                        loggerData.state = "walking_to_sawmill"
                        setNPCStatus(logger, "Delivering logs...")
                        walkNPCTo(logger, LumberMillState.positions.sawmill + Vector3.new(-4, 0, 0), walkSpeed, function()
                            -- Deposit logs into sawmill queue
                            loggerData.state = "depositing"
                            setNPCStatus(logger, "Depositing logs...")
                            task.wait(0.5)

                            -- Add logs to sawmill queue
                            local logsDeposited = loggerData.carrying
                            LumberMillState.sawmillLogs = LumberMillState.sawmillLogs + logsDeposited
                            loggerData.carrying = 0
                            setNPCCarrying(logger, nil, 0)

                            print(string.format("[Logger #%d] Deposited %d logs (Queue: %d)",
                                loggerId, logsDeposited, LumberMillState.sawmillLogs))

                            -- Immediately go back (don't wait for processing)
                            loggerData.state = "idle"
                            setNPCStatus(logger, "Returning...")
                            cycleComplete = true
                        end)
                    end)
                else
                    -- No trees available, wait for respawn
                    setNPCStatus(logger, "Waiting for trees...")
                    task.wait(3)
                    cycleComplete = true
                end

                -- Wait for cycle to complete before starting next one
                while not cycleComplete and loggerData.npc and loggerData.npc.Parent do
                    task.wait(0.5)
                end

                task.wait(1) -- Brief pause between cycles
            end
        end)

        print(string.format("[LumberMill] %s hired Logger #%d for %d gold + %d food!",
            player.Name, loggerId, cost.gold, cost.food))
        print(string.format("[LumberMill] Logger #%d will chop trees → deliver to sawmill → repeat!", loggerId))
    end)

    -- ========== HIRE HAULERS STATION (RIGHT of portal, like gold mine) ==========
    local haulerArea = LumberMillState.positions.hireHauler

    local haulerBoard = Instance.new("Part")
    haulerBoard.Name = "HaulerHiringBoard"
    haulerBoard.Size = Vector3.new(5, 4, 0.5)
    haulerBoard.Position = haulerArea + Vector3.new(0, 2.5, 0)
    haulerBoard.Anchored = true
    haulerBoard.Material = Enum.Material.Wood
    haulerBoard.Color = Color3.fromRGB(60, 90, 60) -- Green-ish
    haulerBoard.Parent = millModel

    createSign(millModel, "HIRE HAULERS", haulerArea + Vector3.new(0, 5, 0), Vector3.new(6, 1.5, 0.3))

    -- Waiting hauler NPCs (stored in array like gold mine)
    LumberMillState.waitingHaulers = {}
    for i = 1, 3 do
        local waitingHaulerPos = Vector3.new(haulerArea.X + (i - 2) * 3, GROUND_Y, haulerArea.Z - 2)
        local waitingHauler = createWorkerNPC(
            "Hauler " .. i,
            waitingHaulerPos,
            Color3.fromRGB(60, 100, 60), -- Green work clothes
            "Hauler"
        )
        setNPCStatus(waitingHauler, "For hire!")
        waitingHauler.Parent = millModel
        table.insert(LumberMillState.waitingHaulers, waitingHauler)
    end

    -- INTERACTION: Hire Hauler
    createInteraction(haulerBoard, "Hire Hauler (900g + 180f)", "Hiring Board", 1, function(player)
        local haulerCount = #LumberMillState.haulers
        local maxHaulers = 3

        if haulerCount >= maxHaulers then
            print(string.format("[LumberMill] %s: Max haulers (3) reached!", player.Name))
            return
        end

        -- Check if there are waiting workers
        if #LumberMillState.waitingHaulers == 0 then
            print(string.format("[LumberMill] %s: No haulers available to hire!", player.Name))
            return
        end

        local cost = HaulerCosts[haulerCount + 1]
        if not deductPlayerResources(player, {gold = cost.gold, food = cost.food}, "LumberMill") then return end
        local haulerId = haulerCount + 1

        -- Remove one waiting worker from the stand (they walk away to work)
        local waitingWorker = table.remove(LumberMillState.waitingHaulers, 1)
        if waitingWorker then
            -- Make the waiting worker walk away before destroying
            setNPCStatus(waitingWorker, "Hired!")
            task.spawn(function()
                local walkAwayPos = LumberMillState.positions.workerSpawn + Vector3.new(haulerCount * 3 + 10, 0, 0)
                walkNPCTo(waitingWorker, walkAwayPos, 6, function()
                    _npcAnimTracks[waitingWorker] = nil
                    waitingWorker:Destroy()
                end)
            end)
        end

        -- Check if booth is now empty
        if #LumberMillState.waitingHaulers == 0 then
            print("[LumberMill] Hauler booth is now empty!")
        end

        -- Create visible hauler NPC at hiring booth (walks to work from there)
        local spawnPos = LumberMillState.positions.hireHauler
        local hauler = createWorkerNPC(
            "Hauler " .. haulerId,
            spawnPos,
            Color3.fromRGB(60, 100, 60), -- Green work clothes
            "Hauler"
        )
        hauler.Parent = millModel

        -- Store the hiring player for rewards
        local hiringPlayer = player

        local haulerData = {
            npc = hauler,
            state = "idle",
            carrying = 0,
            owner = player.UserId,
        }
        table.insert(LumberMillState.haulers, haulerData)

        -- Start hauler AI loop with async completion-flag pattern
        task.spawn(function()
            setNPCStatus(hauler, "Waiting for planks...")

            while haulerData.npc and haulerData.npc.Parent do
                -- Get current hauler stats (updates each cycle based on upgrades)
                local haulerStats = getHaulerStats(LumberMillState.equipment.haulerLevel)
                local plankCapacity = haulerStats.plankCapacity
                local walkSpeed = haulerStats.walkSpeed

                -- Check if there are planks ready at output pile
                if LumberMillState.woodStorage >= 1 then
                    local cycleComplete = false

                    -- RESERVE planks immediately to prevent race condition with player pickup
                    local planksToCollect = math.min(LumberMillState.woodStorage, plankCapacity)
                    LumberMillState.woodStorage = LumberMillState.woodStorage - planksToCollect
                    haulerData.carrying = planksToCollect

                    -- Update visuals immediately (planks are now "reserved")
                    if LumberMillState.updatePlankPileVisuals then
                        LumberMillState.updatePlankPileVisuals()
                    end

                    print(string.format("[Hauler #%d] Reserved %d planks for pickup", haulerId, planksToCollect))

                    -- Walk to output pile
                    haulerData.state = "walking_to_output"
                    setNPCStatus(hauler, string.format("Going for %d planks...", planksToCollect))
                    walkNPCTo(hauler, LumberMillState.positions.woodStorage + Vector3.new(0, 0, 3), walkSpeed, function()
                        -- Pick up planks (already reserved in haulerData.carrying)
                        haulerData.state = "picking_up"
                        setNPCStatus(hauler, "Picking up planks...")
                        task.wait(1)

                        -- Show planks being carried (use already reserved amount)
                        local reservedPlanks = haulerData.carrying
                        setNPCCarrying(hauler, "planks", math.min(5, math.ceil(reservedPlanks / 5)))
                        setNPCStatus(hauler, string.format("Carrying %d planks", reservedPlanks))

                        print(string.format("[Hauler #%d] Picked up %d planks", haulerId, reservedPlanks))

                        -- Walk to storage chest
                        haulerData.state = "walking_to_storage"
                        setNPCStatus(hauler, "Delivering to storage...")
                        walkNPCTo(hauler, LumberMillState.positions.storageChest + Vector3.new(0, 0, 3), walkSpeed, function()
                            -- Deposit planks and reward owner
                            haulerData.state = "depositing"
                            setNPCStatus(hauler, "Depositing planks...")
                            task.wait(1.5)

                            local planksDelivered = haulerData.carrying

                            -- REWARD THE PLAYER who hired the hauler
                            local ownerPlayer = nil
                            for _, p in Players:GetPlayers() do
                                if p.UserId == haulerData.owner then
                                    ownerPlayer = p
                                    break
                                end
                            end

                            if ownerPlayer then
                                rewardPlayer(ownerPlayer, "wood", planksDelivered, "LumberMill")
                                print(string.format("[Hauler #%d] Delivered %d planks to %s's storage!",
                                    haulerId, planksDelivered, ownerPlayer.Name))
                            else
                                print(string.format("[Hauler #%d] Delivered %d planks to storage (owner offline)",
                                    haulerId, planksDelivered))
                            end

                            -- Sparkle effect
                            local torso = hauler:FindFirstChild("UpperTorso") or hauler:FindFirstChild("Torso")
                            if torso then
                                local sparkle = Instance.new("ParticleEmitter")
                                sparkle.Color = ColorSequence.new(Color3.fromRGB(200, 180, 140))
                                sparkle.Size = NumberSequence.new(0.5)
                                sparkle.Lifetime = NumberRange.new(0.5, 1)
                                sparkle.Rate = 30
                                sparkle.Speed = NumberRange.new(2, 5)
                                sparkle.SpreadAngle = Vector2.new(60, 60)
                                sparkle.Parent = torso
                                task.delay(0.8, function() sparkle:Destroy() end)
                            end

                            haulerData.carrying = 0
                            setNPCCarrying(hauler, nil, 0)
                            haulerData.state = "idle"
                            setNPCStatus(hauler, "Waiting for planks...")
                            cycleComplete = true
                        end)
                    end)

                    -- Wait for cycle to complete
                    while not cycleComplete and haulerData.npc and haulerData.npc.Parent do
                        task.wait(0.5)
                    end

                    task.wait(1)
                else
                    setNPCStatus(hauler, "Waiting for planks...")
                    task.wait(2) -- Check for planks every 2 seconds
                end
            end
        end)

        print(string.format("[LumberMill] %s hired Hauler #%d for %d gold + %d food!",
            player.Name, haulerId, cost.gold, cost.food))
        print(string.format("[LumberMill] Hauler #%d will take planks from output → deliver to YOUR storage!", haulerId))
    end)

    -- ========== STEP 6: SINGLE UPGRADE KIOSK (like Gold Mine) ==========
    local upgradeKioskPos = LumberMillState.positions.upgradeKiosk

    -- Kiosk pedestal/terminal
    local upgradeKiosk = Instance.new("Part")
    upgradeKiosk.Name = "UpgradeKiosk"
    upgradeKiosk.Size = Vector3.new(3, 4, 2)
    upgradeKiosk.Anchored = true
    upgradeKiosk.Material = Enum.Material.Metal
    upgradeKiosk.Color = Color3.fromRGB(70, 80, 70)  -- Greenish metal for lumber theme
    local kioskCenterPos = upgradeKioskPos + Vector3.new(0, 2, 0)
    upgradeKiosk.Position = kioskCenterPos
    upgradeKiosk.Parent = millModel

    -- Kiosk screen (decorative)
    local kioskScreen = Instance.new("Part")
    kioskScreen.Name = "KioskScreen"
    kioskScreen.Size = Vector3.new(2.5, 2, 0.2)
    kioskScreen.Anchored = true
    kioskScreen.Material = Enum.Material.Neon
    kioskScreen.Color = Color3.fromRGB(100, 200, 100)  -- Green glow for lumber
    kioskScreen.Position = kioskCenterPos + Vector3.new(0, 1, -1.1)
    kioskScreen.Parent = millModel

    -- Glow effect
    local kioskGlow = Instance.new("PointLight")
    kioskGlow.Color = Color3.fromRGB(100, 200, 100)
    kioskGlow.Brightness = 1.5
    kioskGlow.Range = 8
    kioskGlow.Parent = kioskScreen

    -- Sign above kiosk
    local kioskSign = Instance.new("Part")
    kioskSign.Name = "UpgradeKioskSign"
    kioskSign.Size = Vector3.new(6, 1.2, 0.3)
    kioskSign.Position = upgradeKioskPos + Vector3.new(0, 5, 0)
    kioskSign.Anchored = true
    kioskSign.Material = Enum.Material.Wood
    kioskSign.Color = Color3.fromRGB(100, 70, 45)
    kioskSign.Parent = millModel

    local kioskSignGui = Instance.new("SurfaceGui")
    kioskSignGui.Face = Enum.NormalId.Front
    kioskSignGui.Parent = kioskSign

    local kioskSignLabel = Instance.new("TextLabel")
    kioskSignLabel.Size = UDim2.new(1, 0, 1, 0)
    kioskSignLabel.BackgroundTransparency = 1
    kioskSignLabel.Text = "UPGRADE KIOSK"
    kioskSignLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    kioskSignLabel.TextScaled = true
    kioskSignLabel.Font = Enum.Font.GothamBold
    kioskSignLabel.Parent = kioskSignGui
    makeSignDoubleSided(kioskSign)

    -- Billboard showing "Press E to Open Upgrades"
    local kioskBillboard = Instance.new("BillboardGui")
    kioskBillboard.Name = "KioskPreview"
    kioskBillboard.Size = UDim2.new(6, 0, 2, 0)
    kioskBillboard.StudsOffset = Vector3.new(0, 3, 0)
    kioskBillboard.AlwaysOnTop = true
    kioskBillboard.Parent = upgradeKiosk

    local previewLabel = Instance.new("TextLabel")
    previewLabel.Size = UDim2.new(1, 0, 1, 0)
    previewLabel.BackgroundTransparency = 1
    previewLabel.Text = "Press E to Open Upgrades"
    previewLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    previewLabel.TextStrokeTransparency = 0.3
    previewLabel.TextScaled = true
    previewLabel.Font = Enum.Font.Gotham
    previewLabel.Parent = kioskBillboard

    -- Track active upgrade GUIs per player
    local activeLumberUpgradeGuis = {}

    -- Function to create the upgrade GUI for a player
    local function createLumberUpgradeGui(player)
        -- Remove existing GUI if any
        if activeLumberUpgradeGuis[player.UserId] then
            activeLumberUpgradeGuis[player.UserId]:Destroy()
            activeLumberUpgradeGuis[player.UserId] = nil
        end

        local playerGui = player:FindFirstChild("PlayerGui")
        if not playerGui then return end

        -- Create ScreenGui
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "LumberMillUpgradeMenu"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = playerGui
        activeLumberUpgradeGuis[player.UserId] = screenGui

        -- Main frame
        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = UDim2.new(0, 450, 0, 550)
        mainFrame.Position = UDim2.new(0.5, -225, 0.5, -275)
        mainFrame.BackgroundColor3 = Color3.fromRGB(30, 35, 25)  -- Dark green tint
        mainFrame.BorderSizePixel = 3
        mainFrame.BorderColor3 = Color3.fromRGB(100, 200, 100)
        mainFrame.Parent = screenGui

        -- Title
        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 50)
        title.Position = UDim2.new(0, 0, 0, 0)
        title.BackgroundColor3 = Color3.fromRGB(40, 50, 30)
        title.BorderSizePixel = 0
        title.Text = "LUMBER YARD UPGRADES"
        title.TextColor3 = Color3.fromRGB(150, 255, 150)
        title.TextScaled = true
        title.Font = Enum.Font.GothamBold
        title.Parent = mainFrame

        -- Close button
        local closeButton = Instance.new("TextButton")
        closeButton.Name = "CloseButton"
        closeButton.Size = UDim2.new(0, 40, 0, 40)
        closeButton.Position = UDim2.new(1, -45, 0, 5)
        closeButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        closeButton.BorderSizePixel = 0
        closeButton.Text = "X"
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeButton.TextScaled = true
        closeButton.Font = Enum.Font.GothamBold
        closeButton.Parent = mainFrame
        closeButton.MouseButton1Click:Connect(function()
            screenGui:Destroy()
            activeLumberUpgradeGuis[player.UserId] = nil
        end)

        -- Function to create an upgrade card
        local function createUpgradeCard(yOffset, upgradeType, getStats, currentLevel, color, onUpgrade)
            local stats = getStats(currentLevel)
            local nextStats = getStats(currentLevel + 1)

            local card = Instance.new("Frame")
            card.Name = upgradeType .. "Card"
            card.Size = UDim2.new(0.95, 0, 0, 100)
            card.Position = UDim2.new(0.025, 0, 0, yOffset)
            card.BackgroundColor3 = Color3.fromRGB(45, 50, 40)
            card.BorderSizePixel = 2
            card.BorderColor3 = color
            card.Parent = mainFrame

            local cardTitle = Instance.new("TextLabel")
            cardTitle.Size = UDim2.new(0.6, 0, 0, 30)
            cardTitle.Position = UDim2.new(0.02, 0, 0, 5)
            cardTitle.BackgroundTransparency = 1
            cardTitle.Text = string.format("%s  Lv.%d", upgradeType:upper(), currentLevel)
            cardTitle.TextColor3 = color
            cardTitle.TextXAlignment = Enum.TextXAlignment.Left
            cardTitle.TextScaled = true
            cardTitle.Font = Enum.Font.GothamBold
            cardTitle.Parent = card

            local statsLabel = Instance.new("TextLabel")
            statsLabel.Size = UDim2.new(0.96, 0, 0, 35)
            statsLabel.Position = UDim2.new(0.02, 0, 0, 35)
            statsLabel.BackgroundTransparency = 1
            statsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
            statsLabel.TextXAlignment = Enum.TextXAlignment.Left
            statsLabel.TextScaled = true
            statsLabel.Font = Enum.Font.Gotham
            statsLabel.Parent = card

            -- Set stats text based on upgrade type
            if upgradeType == "Axe" then
                statsLabel.Text = string.format("Current: %d logs/chop → Next: %d logs/chop", stats.logsPerChop, nextStats.logsPerChop)
            elseif upgradeType == "Sawmill" then
                statsLabel.Text = string.format("Current: %d planks/log, %.1fs → Next: %d planks/log, %.1fs",
                    stats.planksPerLog, stats.processTime, nextStats.planksPerLog, nextStats.processTime)
            elseif upgradeType == "Logger" then
                statsLabel.Text = string.format("Current: %d log capacity → Next: %d log capacity", stats.logCapacity, nextStats.logCapacity)
            elseif upgradeType == "Hauler" then
                statsLabel.Text = string.format("Current: %d plank capacity → Next: %d plank capacity", stats.plankCapacity, nextStats.plankCapacity)
            end

            local upgradeButton = Instance.new("TextButton")
            upgradeButton.Name = "UpgradeButton"
            upgradeButton.Size = UDim2.new(0.4, 0, 0, 28)
            upgradeButton.Position = UDim2.new(0.55, 0, 0, 68)
            upgradeButton.BackgroundColor3 = Color3.fromRGB(80, 150, 80)
            upgradeButton.BorderSizePixel = 0
            upgradeButton.Text = string.format("UPGRADE - %d gold", nextStats.upgradeCost)
            upgradeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            upgradeButton.TextScaled = true
            upgradeButton.Font = Enum.Font.GothamBold
            upgradeButton.Parent = card

            upgradeButton.MouseButton1Click:Connect(function()
                onUpgrade()
                -- Refresh the GUI
                createLumberUpgradeGui(player)
            end)

            return card
        end

        -- Create upgrade cards
        local yOffset = 60

        -- 1. Axe Upgrade
        createUpgradeCard(yOffset, "Axe", getAxeStats, LumberMillState.equipment.axeLevel,
            Color3.fromRGB(139, 90, 43), function()
                local nextLevel = LumberMillState.equipment.axeLevel + 1
                local nextStats = getAxeStats(nextLevel)
                if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "LumberMill") then return end
                LumberMillState.equipment.axeLevel = nextLevel
                addLumberXP(50)
                print(string.format("[Upgrade] %s upgraded Axe to Lv%d! Now %d logs/chop", player.Name, nextLevel, nextStats.logsPerChop))
            end)
        yOffset = yOffset + 110

        -- 2. Sawmill Upgrade
        createUpgradeCard(yOffset, "Sawmill", getSawmillStats, LumberMillState.equipment.sawmillLevel,
            Color3.fromRGB(180, 140, 90), function()
                local nextLevel = LumberMillState.equipment.sawmillLevel + 1
                local nextStats = getSawmillStats(nextLevel)
                if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "LumberMill") then return end
                LumberMillState.equipment.sawmillLevel = nextLevel
                addLumberXP(50)
                print(string.format("[Upgrade] %s upgraded Sawmill to Lv%d!", player.Name, nextLevel))
            end)
        yOffset = yOffset + 110

        -- 3. Logger Upgrade
        createUpgradeCard(yOffset, "Logger", getLoggerStats, LumberMillState.equipment.loggerLevel,
            Color3.fromRGB(180, 50, 50), function()
                local nextLevel = LumberMillState.equipment.loggerLevel + 1
                local nextStats = getLoggerStats(nextLevel)
                if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "LumberMill") then return end
                LumberMillState.equipment.loggerLevel = nextLevel
                addLumberXP(50)
                print(string.format("[Upgrade] %s upgraded Loggers to Lv%d!", player.Name, nextLevel))
            end)
        yOffset = yOffset + 110

        -- 4. Hauler Upgrade
        createUpgradeCard(yOffset, "Hauler", getHaulerStats, LumberMillState.equipment.haulerLevel,
            Color3.fromRGB(60, 150, 60), function()
                local nextLevel = LumberMillState.equipment.haulerLevel + 1
                local nextStats = getHaulerStats(nextLevel)
                if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "LumberMill") then return end
                LumberMillState.equipment.haulerLevel = nextLevel
                addLumberXP(50)
                print(string.format("[Upgrade] %s upgraded Haulers to Lv%d!", player.Name, nextLevel))
            end)
    end

    -- Cleanup GUI when player leaves
    Players.PlayerRemoving:Connect(function(player)
        if activeLumberUpgradeGuis[player.UserId] then
            activeLumberUpgradeGuis[player.UserId]:Destroy()
            activeLumberUpgradeGuis[player.UserId] = nil
        end
    end)

    -- INTERACTION: Open Upgrade Menu (single kiosk)
    createInteraction(upgradeKiosk, "Open Upgrades", "Upgrade Kiosk", 2, function(player)
        createLumberUpgradeGui(player)
        print(string.format("[LumberMill] %s opened Upgrade Menu", player.Name))
    end)

    -- ========== EXIT PORTAL ==========
    createExitPortal(millModel, Vector3.new(baseX, GROUND_Y + 4, baseZ + 28))

    -- ===== FOREST DECORATIVE ENHANCEMENTS =====
    -- Fallen log on ground
    local fallenLog = Instance.new("Part")
    fallenLog.Name = "FallenLog"
    fallenLog.Shape = Enum.PartType.Cylinder
    fallenLog.Size = Vector3.new(8, 2, 2)
    fallenLog.Position = Vector3.new(baseX - 10, GROUND_Y + 1, baseZ - 15)
    fallenLog.Orientation = Vector3.new(0, 30, 90)
    fallenLog.Anchored = true
    fallenLog.Material = Enum.Material.Wood
    fallenLog.Color = Color3.fromRGB(70, 50, 30)
    fallenLog.CanCollide = false
    fallenLog.Parent = millModel

    -- Mushroom props near trees
    local mushroomPositions = {
        Vector3.new(baseX - 28, GROUND_Y, baseZ - 10),
        Vector3.new(baseX - 24, GROUND_Y, baseZ + 6),
        Vector3.new(baseX + 28, GROUND_Y, baseZ - 8),
        Vector3.new(baseX + 24, GROUND_Y, baseZ + 8),
        Vector3.new(baseX - 32, GROUND_Y, baseZ + 2),
    }
    for mi, mpos in mushroomPositions do
        -- Stem
        local stem = Instance.new("Part")
        stem.Name = "MushroomStem" .. mi
        stem.Shape = Enum.PartType.Cylinder
        stem.Size = Vector3.new(0.5, 0.4, 0.4)
        stem.Position = mpos + Vector3.new(0, 0.25, 0)
        stem.Anchored = true
        stem.Material = Enum.Material.SmoothPlastic
        stem.Color = Color3.fromRGB(230, 220, 200)
        stem.CanCollide = false
        stem.Parent = millModel

        -- Cap
        local cap = Instance.new("Part")
        cap.Name = "MushroomCap" .. mi
        cap.Shape = Enum.PartType.Cylinder
        cap.Size = Vector3.new(0.3, 0.8, 0.8)
        cap.Position = mpos + Vector3.new(0, 0.55, 0)
        cap.Anchored = true
        cap.Material = Enum.Material.SmoothPlastic
        cap.Color = Color3.fromRGB(180, 50 + mi * 20, 40)
        cap.CanCollide = false
        cap.Parent = millModel
    end

    -- Stone path through forest to logging areas
    for sp = 0, 8 do
        local stone = Instance.new("Part")
        stone.Name = "ForestPathStone" .. sp
        stone.Size = Vector3.new(2.5, 0.15, 2)
        stone.Position = Vector3.new(baseX, GROUND_Y + 0.1, baseZ - 18 + sp * 5)
        stone.Anchored = true
        stone.Material = Enum.Material.Cobblestone
        stone.Color = Color3.fromRGB(90, 85, 78)
        stone.CanCollide = false
        stone.Parent = millModel
    end

    -- Leaf particle emitter on sky part (falling leaves effect)
    local leafEmitter = Instance.new("ParticleEmitter")
    leafEmitter.Name = "FallingLeaves"
    leafEmitter.Color = ColorSequence.new(Color3.fromRGB(60, 120, 40))
    leafEmitter.Size = NumberSequence.new(0.3, 0.5)
    leafEmitter.Lifetime = NumberRange.new(4, 8)
    leafEmitter.Rate = 3
    leafEmitter.Speed = NumberRange.new(1, 3)
    leafEmitter.SpreadAngle = Vector2.new(180, 0)
    leafEmitter.Rotation = NumberRange.new(0, 360)
    leafEmitter.RotSpeed = NumberRange.new(20, 60)
    leafEmitter.Parent = sky

    -- Bird nest props in tree areas
    for _, nestPos in {
        Vector3.new(baseX - 28, GROUND_Y + 10, baseZ - 8),
        Vector3.new(baseX + 26, GROUND_Y + 9, baseZ + 6),
    } do
        local nest = Instance.new("Part")
        nest.Name = "BirdNest"
        nest.Shape = Enum.PartType.Cylinder
        nest.Size = Vector3.new(0.4, 1, 1)
        nest.Position = nestPos
        nest.Anchored = true
        nest.Material = Enum.Material.Fabric
        nest.Color = Color3.fromRGB(110, 85, 50)
        nest.CanCollide = false
        nest.Parent = millModel
    end

    -- Parent the lumber mill interior
    millModel.Parent = interiorsFolder

    print("  ✓ Lumber Mill created (FOREST interior):")
    print("    - Enter building in village to teleport inside")
    print("    - Fenced perimeter prevents escaping")
    print("    - 14 trees with 4-stage progressive chopping:")
    print("      Stage 1: Full tree (3 foliage layers) → 1 wood")
    print("      Stage 2: Thinned (2 foliage layers) → 2 wood")
    print("      Stage 3: Trunk only → 3 wood")
    print("      Stage 4: Stump → 5 wood (bonus!)")
    print("      Then: Gone → 15 second respawn")
    print("    1. CHOP TREES: 4 chops to fell completely")
    print("    2. CARRY LOGS: Transport up to 8 logs")
    print("    3. SAWMILL: Walk through to load logs (progress bar shows processing)")
    print("    4. COLLECT: Grab planks from output pile")
    print("    5. STORE: Deposit planks in chest for wood!")
    print("    6. HIRE LOGGERS: Automate tree chopping")
    print("    7. UPGRADE: Better axe + sawmill = more wood")
end

-- ============================================================================
-- FARM - Full progression loop prototype
-- Plant seeds → Water crops → Tend/Wait → Harvest → Process → Collect → Hire → Upgrade
-- ============================================================================

-- Farm states for multiple farms (Farm 1-6)
-- Each farm has its own independent state
local FarmStates = {} -- [farmNumber] = farmState

-- Factory function to create a new farm state
local function createFarmState(farmNumber)
    return {
        farmNumber = farmNumber,
        level = 1,
        xp = 0,
        farmers = {},       -- NPC farmers (plant, harvest, deliver to windmill)
        carriers = {},      -- NPC carriers (windmill → barn/storage)
        equipment = {
            hoeLevel = 1,           -- Crops per action
            wateringCanLevel = 1,   -- Plots per water, speed
            windmillLevel = 1,      -- Grain per crop, speed at milestones
            farmerLevel = 1,        -- Crop capacity, walk speed
            carrierLevel = 1,       -- Grain capacity, walk speed
        },
        -- Crop plot states
        plots = {}, -- [plotId] = { crop = "wheat", stage = 0-3, watered = false }
        -- Player inventory (shared across farms for simplicity)
        playerCrops = {},   -- [playerId] = crops being carried
        playerFood = {},    -- [playerId] = food being carried
        -- Storage piles
        harvestPile = 0,    -- Crops at harvest basket (ready for windmill)
        windmillCrops = 0,  -- Crops being processed
        foodStorage = 0,    -- Food ready to collect at silo
        positions = {},
        -- Visual update functions (set during creation)
        updateHarvestPileVisuals = nil,
        updateFoodStorageVisuals = nil,
        updateWindmillUI = nil, -- Function to update windmill progress bar
        updateExteriorStats = nil, -- Function to update exterior sign stats
        -- Hiring station tracking (like Gold Mine pattern)
        waitingFarmers = {},  -- NPCs waiting at hire station
        waitingCarriers = {}, -- NPCs waiting at carrier station
        farmerSign = nil,     -- TextLabel reference for "HIRE FARMERS" / "FULLY STAFFED"
        carrierSign = nil,    -- TextLabel reference for "HIRE CARRIERS" / "FULLY STAFFED"
    }
end

-- Get or create farm state for a given farm number
local function getFarmState(farmNumber)
    if not FarmStates[farmNumber] then
        FarmStates[farmNumber] = createFarmState(farmNumber)
    end
    return FarmStates[farmNumber]
end

-- Legacy alias for Farm 1 (for backward compatibility with existing code)
local FarmState = getFarmState(1)

-- Equipment stats - LEVEL BASED (scales infinitely)
-- Returns stats for a given level, with scaling costs

local function getHoeStats(level)
    return {
        cropsPerAction = level,                        -- Level 1 = 1 crop, Level 5 = 5 crops
        speed = 1.0 + (level - 1) * 0.2,               -- Gets faster
        upgradeCost = math.floor(100 * (level ^ 1.8)), -- Exponential cost: 100, 348, 728, 1234...
    }
end

local function getWateringCanStats(level)
    return {
        plotsPerWater = 1 + level,                     -- Level 1 = 2 plots, Level 5 = 6 plots
        speed = 1.0 + (level - 1) * 0.2,               -- Gets faster
        upgradeCost = math.floor(80 * (level ^ 1.8)),  -- Exponential cost: 80, 278, 582, 987...
    }
end

local function getWindmillStatsFunc(level)
    -- Speed only increases at milestone levels: 10, 20, 50, 100, 200, 500, 1000
    local speedBoosts = 0
    if level >= 10 then speedBoosts = speedBoosts + 1 end
    if level >= 20 then speedBoosts = speedBoosts + 1 end
    if level >= 50 then speedBoosts = speedBoosts + 1 end
    if level >= 100 then speedBoosts = speedBoosts + 1 end
    if level >= 200 then speedBoosts = speedBoosts + 1 end
    if level >= 500 then speedBoosts = speedBoosts + 1 end
    if level >= 1000 then speedBoosts = speedBoosts + 1 end

    local processTime = math.max(0.2, 1.5 - (speedBoosts * 0.2)) -- 1.5s → 1.3s → 1.1s → 0.9s → 0.7s → 0.5s → 0.3s → 0.2s

    return {
        grainPerCrop = level,                          -- Level 1 = 1 grain/crop, increases every level
        processTime = processTime,                     -- Only faster at milestones
        speedBoosts = speedBoosts,                     -- For display purposes
        upgradeCost = math.floor(200 * (level ^ 1.8)), -- 200, 696, 1456, 2468...
    }
end

local function getFarmerStats(level)
    return {
        cropCapacity = 5 + (level * 5),                -- 10, 15, 20, 25...
        walkSpeed = 4 + level,                         -- 5, 6, 7, 8...
        harvestTime = math.max(0.2, 0.5 - (level - 1) * 0.05), -- Faster harvesting per crop
        upgradeCost = math.floor(150 * (level ^ 1.8)), -- 150, 522, 1092, 1851...
    }
end

local function getCarrierStats(level)
    return {
        grainCapacity = 10 + (level * 5),              -- 15, 20, 25, 30...
        walkSpeed = 4 + level,                         -- 5, 6, 7, 8...
        upgradeCost = math.floor(100 * (level ^ 1.8)), -- 100, 348, 728, 1234...
    }
end

local FarmerCosts = {
    [1] = { gold = 1200, food = 240 },
    [2] = { gold = 3600, food = 750 },
    [3] = { gold = 12000, food = 2400 },
}

local CarrierCosts = {
    [1] = { gold = 900, food = 180 },
    [2] = { gold = 2700, food = 540 },
    [3] = { gold = 8100, food = 1620 },
}

-- Crop types and their properties
local CropTypes = {
    Wheat = { growTime = 10, foodValue = 5, color = Color3.fromRGB(220, 200, 100), unlockLevel = 1 },
    Corn = { growTime = 15, foodValue = 8, color = Color3.fromRGB(240, 220, 80), unlockLevel = 3 },
    Carrots = { growTime = 8, foodValue = 4, color = Color3.fromRGB(240, 140, 50), unlockLevel = 5 },
    Pumpkins = { growTime = 20, foodValue = 12, color = Color3.fromRGB(230, 130, 50), unlockLevel = 7 },
}

local function getPlayerCrops(player)
    return FarmState.playerCrops[player.UserId] or 0
end

local function setPlayerCrops(player, amount)
    FarmState.playerCrops[player.UserId] = math.max(0, math.min(amount, 20)) -- Max 20 crops carried
end

local function getPlayerFood(player)
    return FarmState.playerFood[player.UserId] or 0
end

local function setPlayerFood(player, amount)
    FarmState.playerFood[player.UserId] = math.max(0, math.min(amount, 50)) -- Max 50 food carried
end

-- Update visual crops on player's back (wheat bundle)
local function updatePlayerCropVisual(player, amount)
    local character = player.Character
    if not character then return end

    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    if not torso then return end

    -- Remove existing crop bundle
    local existingBundle = character:FindFirstChild("CropBundle")
    if existingBundle then
        existingBundle:Destroy()
    end

    if amount <= 0 then return end

    -- Create wheat bundle on back
    local bundle = Instance.new("Model")
    bundle.Name = "CropBundle"
    bundle.Parent = character

    -- Base bundle
    local base = Instance.new("Part")
    base.Name = "BundleBase"
    base.Size = Vector3.new(1.2, 0.6 + (amount * 0.05), 1.5)
    base.Anchored = false
    base.CanCollide = false
    base.Material = Enum.Material.Grass
    base.Color = Color3.fromRGB(220, 200, 100) -- Wheat color
    base.Parent = bundle

    -- Weld to torso
    local weld = Instance.new("Weld")
    weld.Part0 = torso
    weld.Part1 = base
    weld.C0 = CFrame.new(0, 0.2, 0.7)
    weld.Parent = base

    -- Add wheat stalks
    local stalkCount = math.min(math.ceil(amount / 3), 5)
    for i = 1, stalkCount do
        local stalk = Instance.new("Part")
        stalk.Name = "Stalk" .. i
        stalk.Size = Vector3.new(0.15, 1.2 + math.random() * 0.3, 0.15)
        stalk.Anchored = false
        stalk.CanCollide = false
        stalk.Material = Enum.Material.Grass
        stalk.Color = Color3.fromRGB(200 + math.random(30), 180 + math.random(30), 80 + math.random(30))
        stalk.Parent = bundle

        local stalkWeld = Instance.new("Weld")
        stalkWeld.Part0 = base
        stalkWeld.Part1 = stalk
        stalkWeld.C0 = CFrame.new(-0.3 + i * 0.15, 0.7, 0)
        stalkWeld.Parent = stalk
    end
end

-- Update visual food sacks on player's back
local function updatePlayerFoodVisual(player, amount)
    local character = player.Character
    if not character then return end

    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    if not torso then return end

    -- Remove existing food sack
    local existingSack = character:FindFirstChild("FoodSack")
    if existingSack then
        existingSack:Destroy()
    end

    if amount <= 0 then return end

    -- Create flour/food sack on back
    local sack = Instance.new("Model")
    sack.Name = "FoodSack"
    sack.Parent = character

    local sackCount = math.min(math.ceil(amount / 15), 3)
    for i = 1, sackCount do
        local bag = Instance.new("Part")
        bag.Name = "Bag" .. i
        bag.Size = Vector3.new(0.8, 1.0, 0.6)
        bag.Anchored = false
        bag.CanCollide = false
        bag.Material = Enum.Material.Fabric
        bag.Color = Color3.fromRGB(200, 180, 140) -- Burlap color
        bag.Parent = sack

        local bagWeld = Instance.new("Weld")
        bagWeld.Part0 = torso
        bagWeld.Part1 = bag
        bagWeld.C0 = CFrame.new(0, 0.1 + (i-1) * 0.4, 0.6)
        bagWeld.Parent = bag
    end
end

local function addFarmXP(amount, farmNumber)
    farmNumber = farmNumber or 1
    local farmState = getFarmState(farmNumber)
    farmState.xp = farmState.xp + amount
    local requiredXP = farmState.level * 100
    if farmState.xp >= requiredXP then
        farmState.level = farmState.level + 1
        farmState.xp = farmState.xp - requiredXP
        print(string.format("[Farm %d] LEVEL UP! Now level %d", farmNumber, farmState.level))

        -- Update exterior stats billboard
        if farmState.updateExteriorStats then
            farmState.updateExteriorStats()
        end
    end
end

local function createFarm(farmNumber)
    farmNumber = farmNumber or 1
    local farmName = "Farm " .. farmNumber
    local farmKey = "Farm" .. farmNumber

    print(string.format("[Creating %s] Full Progression Loop...", farmName))

    -- Get farm state for this specific farm
    local currentFarmState = getFarmState(farmNumber)

    -- Shadow the global FarmState with this farm's state
    -- This makes all existing code in this function use the correct farm
    local FarmState = currentFarmState

    -- ========== EXTERIOR IN VILLAGE (RED BARN) ==========
    local exteriorData = FARM_EXTERIOR_POSITIONS[farmNumber]
    local exteriorX, exteriorZ = exteriorData.x, exteriorData.z
    local facingDirection = exteriorData.facing

    -- Use the barn exterior for farms (red barn with gambrel roof)
    local exterior = createBarnExterior(
        farmName:upper(),
        Vector3.new(exteriorX, GROUND_Y, exteriorZ),
        Vector3.new(18, 10, 15), -- Slightly taller for barn proportions
        farmKey,
        facingDirection
    )

    -- ========== PRODUCTION STATS BILLBOARD ==========
    -- Create a billboard on the exterior showing production stats
    local statsBoard = Instance.new("Part")
    statsBoard.Name = "StatsBoard"
    statsBoard.Size = Vector3.new(6, 3, 0.3)
    statsBoard.Position = Vector3.new(exteriorX, GROUND_Y + 5, exteriorZ + 8) -- Above entrance
    statsBoard.Anchored = true
    statsBoard.Material = Enum.Material.Wood
    statsBoard.Color = Color3.fromRGB(80, 60, 40)
    statsBoard.Parent = exterior

    local statsBillboard = Instance.new("BillboardGui")
    statsBillboard.Name = "StatsBillboard"
    statsBillboard.Size = UDim2.new(8, 0, 4, 0)
    statsBillboard.StudsOffset = Vector3.new(0, 2, 0)
    statsBillboard.AlwaysOnTop = false
    statsBillboard.Parent = statsBoard

    local statsFrame = Instance.new("Frame")
    statsFrame.Name = "StatsFrame"
    statsFrame.Size = UDim2.new(1, 0, 1, 0)
    statsFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 20)
    statsFrame.BackgroundTransparency = 0.3
    statsFrame.BorderSizePixel = 0
    statsFrame.Parent = statsBillboard

    local statsCorner = Instance.new("UICorner")
    statsCorner.CornerRadius = UDim.new(0.1, 0)
    statsCorner.Parent = statsFrame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(1, 0, 0.3, 0)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = farmName
    titleLabel.TextColor3 = Color3.fromRGB(255, 230, 150)
    titleLabel.TextScaled = true
    titleLabel.Font = Enum.Font.Antique
    titleLabel.Parent = statsFrame

    local foodLabel = Instance.new("TextLabel")
    foodLabel.Name = "FoodLabel"
    foodLabel.Size = UDim2.new(1, 0, 0.35, 0)
    foodLabel.Position = UDim2.new(0, 0, 0.3, 0)
    foodLabel.BackgroundTransparency = 1
    foodLabel.Text = "🌾 Food: 0"
    foodLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
    foodLabel.TextScaled = true
    foodLabel.Font = Enum.Font.GothamMedium
    foodLabel.Parent = statsFrame

    local cropsLabel = Instance.new("TextLabel")
    cropsLabel.Name = "CropsLabel"
    cropsLabel.Size = UDim2.new(1, 0, 0.25, 0)
    cropsLabel.Position = UDim2.new(0, 0, 0.55, 0)
    cropsLabel.BackgroundTransparency = 1
    cropsLabel.Text = "🌱 Crops: 0 | Level 1"
    cropsLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
    cropsLabel.TextScaled = true
    cropsLabel.Font = Enum.Font.GothamMedium
    cropsLabel.Parent = statsFrame

    -- Production rate label (like Gold Mine pattern)
    local productionLabel = Instance.new("TextLabel")
    productionLabel.Name = "ProductionLabel"
    productionLabel.Size = UDim2.new(1, 0, 0.2, 0)
    productionLabel.Position = UDim2.new(0, 0, 0.8, 0)
    productionLabel.BackgroundTransparency = 1
    productionLabel.Text = "+0 gold/min"
    productionLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    productionLabel.TextScaled = true
    productionLabel.Font = Enum.Font.GothamBold
    productionLabel.Parent = statsFrame

    -- Function to update production rate based on workers
    local function updateFarmProduction()
        -- Calculate production based on farmers and carriers
        local farmerCount = #currentFarmState.farmers
        local carrierCount = #currentFarmState.carriers
        local farmerStats = getFarmerStats(currentFarmState.equipment.farmerLevel)
        local carrierStats = getCarrierStats(currentFarmState.equipment.carrierLevel)
        local windmillStats = getWindmillStatsFunc(currentFarmState.equipment.windmillLevel)

        -- Estimate production chain:
        -- Farmer: harvests cropCapacity crops, delivers to windmill (~30 sec cycle = ~2 cycles/min)
        -- Windmill: converts crops to food at grainPerCrop rate
        -- Carrier: delivers food to storage chest

        local cyclesPerMinute = 2  -- Approximate cycles per minute
        local cropsPerMinute = farmerCount * (farmerStats.cropCapacity * cyclesPerMinute)
        local foodPerMinute = cropsPerMinute * windmillStats.grainPerCrop
        -- Carriers limit how fast food can be delivered
        local deliveredFoodPerMinute = math.min(foodPerMinute, carrierCount * carrierStats.grainCapacity * cyclesPerMinute)

        -- Only count production if we have both farmers and carriers
        local effectiveProduction = (farmerCount > 0 and carrierCount > 0) and math.floor(deliveredFoodPerMinute) or 0

        productionLabel.Text = string.format("+%d food/min", effectiveProduction)

        -- Color based on production level
        if effectiveProduction == 0 then
            productionLabel.TextColor3 = Color3.fromRGB(150, 150, 150)  -- Gray when idle
        elseif effectiveProduction < 50 then
            productionLabel.TextColor3 = Color3.fromRGB(180, 255, 180)  -- Light green
        else
            productionLabel.TextColor3 = Color3.fromRGB(100, 255, 100)  -- Bright green
        end
    end

    -- Store update function for use when workers are hired
    currentFarmState.updateFarmProduction = updateFarmProduction

    -- Function to update exterior stats
    currentFarmState.updateExteriorStats = function()
        local totalCrops = currentFarmState.harvestPile + currentFarmState.windmillCrops
        foodLabel.Text = string.format("🌾 Food: %d", currentFarmState.foodStorage)
        cropsLabel.Text = string.format("🌱 Crops: %d | Level %d", totalCrops, currentFarmState.level)
        updateFarmProduction()  -- Also update production rate
    end

    -- Update production periodically (like Gold Mine)
    task.spawn(function()
        while true do
            updateFarmProduction()
            task.wait(5)  -- Update every 5 seconds
        end
    end)

    -- ========== OPEN FARMLAND INTERIOR ==========
    local basePos = INTERIOR_POSITIONS[farmKey]
    local farmModel = Instance.new("Model")
    farmModel.Name = farmKey .. "_Interior"

    local baseX, baseZ = basePos.X, basePos.Z
    local GROUND_Y = basePos.Y

    -- Store positions for workers
    -- REDESIGNED LAYOUT: Windmill/storage at back, crop fields on BOTH sides, single upgrade kiosk
    currentFarmState.positions = {
        -- Back wall area (lower Z = back, entrance is at higher Z)
        windmill = Vector3.new(baseX - 20, GROUND_Y, baseZ - 25),        -- Back-left: windmill (processing)
        storageShed = Vector3.new(baseX + 20, GROUND_Y, baseZ - 25),     -- Back-right: storage shed (collect)
        -- Middle area - crop fields on BOTH sides with walking path in center
        cropFieldLeft = Vector3.new(baseX - 25, GROUND_Y, baseZ),        -- Left side: 3x4 = 12 plots
        cropFieldRight = Vector3.new(baseX + 25, GROUND_Y, baseZ),       -- Right side: 3x4 = 12 plots
        -- Front area (entrance side)
        seedShed = Vector3.new(baseX - 25, GROUND_Y, baseZ + 20),        -- Front-left: seed shed
        upgradeKiosk = Vector3.new(baseX + 25, GROUND_Y, baseZ + 20),    -- Front-right: single upgrade kiosk
        hireFarmer = Vector3.new(baseX - 15, GROUND_Y, baseZ + 30),      -- Front area: hire farmers
        hireCarrier = Vector3.new(baseX + 15, GROUND_Y, baseZ + 30),     -- Front area: hire carriers
        -- Worker spawn near center
        workerSpawn = Vector3.new(baseX, GROUND_Y, baseZ + 25),
        -- Processing positions (for NPC routes)
        windmillInput = Vector3.new(baseX - 20, GROUND_Y, baseZ - 20),   -- Near windmill for drop-off
        foodStorage = Vector3.new(baseX + 20, GROUND_Y, baseZ - 20),     -- Near storage for pickup
    }

    -- ===== GRASS FIELD FLOOR =====
    local farmFloor = Instance.new("Part")
    farmFloor.Name = "FarmlandFloor"
    farmFloor.Size = Vector3.new(140, 2, 100)
    farmFloor.Position = Vector3.new(baseX, GROUND_Y - 1, baseZ)
    farmFloor.Anchored = true
    farmFloor.Material = Enum.Material.Grass
    farmFloor.Color = Color3.fromRGB(80, 120, 50)
    farmFloor.Parent = farmModel

    -- Dirt paths between areas
    local mainPath = Instance.new("Part")
    mainPath.Size = Vector3.new(80, 0.2, 6)
    mainPath.Position = Vector3.new(baseX, GROUND_Y + 0.2, baseZ)
    mainPath.Anchored = true
    mainPath.Material = Enum.Material.Ground
    mainPath.Color = Color3.fromRGB(100, 80, 55)
    mainPath.Parent = farmModel

    -- ===== WOODEN FENCE BOUNDARY =====
    local fenceHeight = 3
    local fenceColor = Color3.fromRGB(110, 80, 50)
    local fencePositions = {
        { pos = Vector3.new(baseX, GROUND_Y + fenceHeight/2, baseZ - 48), size = Vector3.new(138, fenceHeight, 1) }, -- Back
        { pos = Vector3.new(baseX, GROUND_Y + fenceHeight/2, baseZ + 48), size = Vector3.new(138, fenceHeight, 1) }, -- Front (with gap)
        { pos = Vector3.new(baseX - 68, GROUND_Y + fenceHeight/2, baseZ), size = Vector3.new(1, fenceHeight, 96) }, -- Left
        { pos = Vector3.new(baseX + 68, GROUND_Y + fenceHeight/2, baseZ), size = Vector3.new(1, fenceHeight, 96) }, -- Right
    }
    for i, f in ipairs(fencePositions) do
        local fence = Instance.new("Part")
        fence.Name = "Fence" .. i
        fence.Size = f.size
        fence.Position = f.pos
        fence.Anchored = true
        fence.Material = Enum.Material.Wood
        fence.Color = fenceColor
        fence.Parent = farmModel
    end

    -- Fence posts
    for i = -5, 5 do
        for _, zOff in {-48, 48} do
            local post = Instance.new("Part")
            post.Size = Vector3.new(1.2, 5, 1.2)
            post.Position = Vector3.new(baseX + i * 12, GROUND_Y + 2.5, baseZ + zOff)
            post.Anchored = true
            post.Material = Enum.Material.Wood
            post.Color = Color3.fromRGB(90, 65, 40)
            post.Parent = farmModel
        end
    end

    -- ===== OPEN SKY CEILING =====
    local sky = Instance.new("Part")
    sky.Name = "Sky"
    sky.Size = Vector3.new(150, 1, 110)
    sky.Position = Vector3.new(baseX, GROUND_Y + 40, baseZ)
    sky.Anchored = true
    sky.Material = Enum.Material.SmoothPlastic
    sky.Color = Color3.fromRGB(140, 190, 240)
    sky.Transparency = 0.3
    sky.Parent = farmModel

    -- Clouds
    for i = 1, 6 do
        local cloud = Instance.new("Part")
        cloud.Shape = Enum.PartType.Ball
        cloud.Size = Vector3.new(15 + math.random() * 10, 5, 10 + math.random() * 8)
        cloud.Position = Vector3.new(baseX - 50 + math.random() * 100, GROUND_Y + 35, baseZ - 30 + math.random() * 60)
        cloud.Anchored = true
        cloud.Material = Enum.Material.SmoothPlastic
        cloud.Color = Color3.fromRGB(255, 255, 255)
        cloud.Transparency = 0.4
        cloud.Parent = farmModel
    end

    -- Sunlight
    local sun = Instance.new("Part")
    sun.Shape = Enum.PartType.Ball
    sun.Size = Vector3.new(12, 12, 12)
    sun.Position = Vector3.new(baseX + 40, GROUND_Y + 38, baseZ - 30)
    sun.Anchored = true
    sun.Material = Enum.Material.Neon
    sun.Color = Color3.fromRGB(255, 250, 180)
    sun.Parent = farmModel

    local sunlight = Instance.new("PointLight")
    sunlight.Brightness = 2
    sunlight.Range = 80
    sunlight.Color = Color3.fromRGB(255, 250, 220)
    sunlight.Parent = sun

    -- ===== DECORATIVE TREES AROUND EDGE =====
    local treePositions = {
        Vector3.new(baseX - 55, GROUND_Y, baseZ - 35),
        Vector3.new(baseX - 60, GROUND_Y, baseZ + 20),
        Vector3.new(baseX + 55, GROUND_Y, baseZ - 40),
        Vector3.new(baseX + 60, GROUND_Y, baseZ + 30),
    }
    for _, tPos in ipairs(treePositions) do
        local trunk = Instance.new("Part")
        trunk.Shape = Enum.PartType.Cylinder
        trunk.Size = Vector3.new(15, 2, 2)
        trunk.Position = tPos + Vector3.new(0, 7.5, 0)
        trunk.Orientation = Vector3.new(0, 0, 90)
        trunk.Anchored = true
        trunk.Material = Enum.Material.Wood
        trunk.Color = Color3.fromRGB(80, 60, 40)
        trunk.Parent = farmModel

        local leaves = Instance.new("Part")
        leaves.Shape = Enum.PartType.Ball
        leaves.Size = Vector3.new(10, 12, 10)
        leaves.Position = tPos + Vector3.new(0, 18, 0)
        leaves.Anchored = true
        leaves.Material = Enum.Material.Grass
        leaves.Color = Color3.fromRGB(60, 110, 45)
        leaves.Parent = farmModel
    end

    -- ===== EXIT PORTAL =====
    createExitPortal(farmModel, Vector3.new(baseX, GROUND_Y + 4, baseZ + 45))

    -- ========== STEP 1: SEED SHED (GET SEEDS) ==========
    -- REDESIGNED POSITION: Front-left area near entrance - faces toward center (right/toward baseX)
    local seedShedPos = FarmState.positions.seedShed

    local seedShed = Instance.new("Part")
    seedShed.Name = "SeedShed"
    seedShed.Size = Vector3.new(5, 4, 4)
    seedShed.Anchored = true
    seedShed.Material = Enum.Material.Wood
    seedShed.Color = Color3.fromRGB(110, 80, 55)
    -- Face toward center (toward baseX, i.e. right from this position)
    local seedShedCenterPos = seedShedPos + Vector3.new(0, 2, 0)
    seedShed.CFrame = CFrame.lookAt(seedShedCenterPos, Vector3.new(baseX, seedShedCenterPos.Y, seedShedCenterPos.Z))
    seedShed.Parent = farmModel

    -- Shed roof - oriented to match shed facing
    local shedRoof = Instance.new("Part")
    shedRoof.Name = "ShedRoof"
    shedRoof.Size = Vector3.new(6, 0.5, 5)
    shedRoof.Anchored = true
    shedRoof.Material = Enum.Material.Wood
    shedRoof.Color = Color3.fromRGB(80, 55, 35)
    shedRoof.CFrame = seedShed.CFrame * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(10))
    shedRoof.Parent = farmModel

    -- Seed bags - positioned in front of shed (toward center)
    for i = 1, 3 do
        local seedBag = Instance.new("Part")
        seedBag.Name = "SeedBag" .. i
        seedBag.Size = Vector3.new(1.2, 1.5, 0.8)
        seedBag.Anchored = true
        seedBag.Material = Enum.Material.Fabric
        seedBag.Color = Color3.fromRGB(180, 160, 120)
        -- Position bags in front of the shed (toward center)
        seedBag.CFrame = seedShed.CFrame * CFrame.new(-1.5 + i * 1.5, -1.25, -2.5)
        seedBag.Parent = farmModel
    end

    -- Sign above shed - faces toward center
    local seedSignPos = seedShedPos + Vector3.new(0, 5.5, 0)
    local seedSign = Instance.new("Part")
    seedSign.Name = "SeedsSign"
    seedSign.Size = Vector3.new(3, 1, 0.3)
    seedSign.Anchored = true
    seedSign.Material = Enum.Material.Wood
    seedSign.Color = Color3.fromRGB(110, 80, 55)
    seedSign.CFrame = CFrame.lookAt(seedSignPos, Vector3.new(baseX, seedSignPos.Y, seedSignPos.Z))
    seedSign.Parent = farmModel

    local seedSignGui = Instance.new("SurfaceGui")
    seedSignGui.Face = Enum.NormalId.Back -- Text on front face (facing center)
    seedSignGui.Parent = seedSign

    local seedSignLabel = Instance.new("TextLabel")
    seedSignLabel.Size = UDim2.new(1, 0, 1, 0)
    seedSignLabel.BackgroundTransparency = 1
    seedSignLabel.Text = "SEEDS"
    seedSignLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    seedSignLabel.TextScaled = true
    seedSignLabel.Font = Enum.Font.GothamBold
    seedSignLabel.Parent = seedSignGui
    makeSignDoubleSided(seedSign)

    -- INTERACTION: Get Seeds
    createInteraction(seedShed, "Get Seeds", "Seed Shed", 0.5, function(player)
        print(string.format("[Farm] %s grabbed wheat seeds! Go plant them in the field.", player.Name))
        addFarmXP(2)
    end, true) -- allowVisitors: visitors can get seeds for the owner

    -- ========== STEP 2: CROP FIELDS (LEFT AND RIGHT SIDES) ==========
    -- REDESIGNED: Crop plots on BOTH sides with walking path in center
    -- Each side has a 3x4 grid = 12 plots per side = 24 total plots

    local plotParts = {}
    local cropParts = {}

    -- Helper function to create a crop field on one side
    local function createCropFieldSide(sideName, centerX, centerZ, plotIdOffset)
        -- Dirt field base for this side
        local field = Instance.new("Part")
        field.Name = "CropField_" .. sideName
        field.Size = Vector3.new(14, 0.3, 18)
        field.Position = Vector3.new(centerX, GROUND_Y + 0.15, centerZ)
        field.Anchored = true
        field.Material = Enum.Material.Ground
        field.Color = Color3.fromRGB(80, 60, 40)
        field.Parent = farmModel

        -- Create 3x4 grid of plots (3 columns, 4 rows)
        for row = 1, 4 do
            for col = 1, 3 do
                local plotId = plotIdOffset + (row - 1) * 3 + col

                -- Calculate plot position (centered on the field)
                local plotX = centerX - 5 + (col - 1) * 4.5
                local plotZ = centerZ - 6 + (row - 1) * 4

                -- Dirt plot
                local plot = Instance.new("Part")
                plot.Name = "Plot_" .. sideName .. "_" .. row .. "_" .. col
                plot.Size = Vector3.new(3.5, 0.4, 3)
                plot.Position = Vector3.new(plotX, GROUND_Y + 0.2, plotZ)
                plot.Anchored = true
                plot.Material = Enum.Material.Ground
                plot.Color = Color3.fromRGB(70, 50, 35)
                plot.Parent = farmModel
                plotParts[plotId] = plot

                -- Initialize plot state
                FarmState.plots[plotId] = { crop = nil, stage = 0, watered = false }

                -- Crop visual (starts invisible)
                local crop = Instance.new("Part")
                crop.Name = "Crop_" .. sideName .. "_" .. row .. "_" .. col
                crop.Size = Vector3.new(2.5, 0.5, 2.5)
                crop.Position = Vector3.new(plotX, GROUND_Y + 0.7, plotZ)
                crop.Anchored = true
                crop.Material = Enum.Material.Grass
                crop.Color = Color3.fromRGB(220, 200, 100) -- Wheat color
                crop.Transparency = 1 -- Hidden until planted
                crop.Parent = farmModel
                cropParts[plotId] = crop

                -- Store positions for crop visual updates
                local storedPlotX = plotX
                local storedPlotZ = plotZ

                -- INTERACTION: Plant/Harvest at plot
                createInteraction(plot, "Plant Seeds", sideName .. " Plot #" .. ((row-1)*3 + col), 0.8, function(player)
                    local plotState = FarmState.plots[plotId]

                    if plotState.crop == nil then
                        -- Plant new crop
                        plotState.crop = "Wheat"
                        plotState.stage = 1
                        plotState.watered = false

                        crop.Transparency = 0.6
                        crop.Size = Vector3.new(2.5, 0.8, 2.5)
                        crop.Position = Vector3.new(storedPlotX, GROUND_Y + 0.6, storedPlotZ)

                        addFarmXP(3)
                        print(string.format("[Farm] %s planted wheat in %s plot #%d! Water it to speed growth.",
                            player.Name, sideName, plotId))

                        -- Auto-grow after delay
                        task.delay(10, function()
                            if FarmState.plots[plotId].crop and FarmState.plots[plotId].stage < 3 then
                                FarmState.plots[plotId].stage = 3
                                crop.Transparency = 0
                                crop.Size = Vector3.new(2.5, 2.5, 2.5)
                                crop.Position = Vector3.new(storedPlotX, GROUND_Y + 1.5, storedPlotZ)
                                print(string.format("[Farm] Crop in %s plot #%d is ready to harvest!", sideName, plotId))
                            end
                        end)

                    elseif plotState.stage >= 3 then
                        -- Harvest ready crop
                        local hoeLevel = FarmState.equipment.hoeLevel
                        local hoeStats = getHoeStats(hoeLevel)
                        local cropsHarvested = hoeStats.cropsPerAction

                        local currentCrops = getPlayerCrops(player)
                        local newCropCount = currentCrops + cropsHarvested
                        setPlayerCrops(player, newCropCount)

                        -- Add visual crops to player
                        updatePlayerCropVisual(player, newCropCount)

                        -- Reset plot
                        plotState.crop = nil
                        plotState.stage = 0
                        plotState.watered = false
                        crop.Transparency = 1

                        addFarmXP(8)
                        print(string.format("[Farm] %s harvested %d crops from %s plot #%d! (Carrying: %d/20)",
                            player.Name, cropsHarvested, sideName, plotId, getPlayerCrops(player)))

                        -- Harvest particles
                        local leaves = Instance.new("ParticleEmitter")
                        leaves.Color = ColorSequence.new(Color3.fromRGB(220, 200, 100))
                        leaves.Size = NumberSequence.new(0.4)
                        leaves.Lifetime = NumberRange.new(0.5, 1)
                        leaves.Rate = 20
                        leaves.Speed = NumberRange.new(3, 6)
                        leaves.Parent = crop
                        task.delay(0.5, function() leaves:Destroy() end)
                    else
                        -- Still growing
                        print(string.format("[Farm] %s: Crop in %s plot #%d is still growing (stage %d/3). Water it!",
                            player.Name, sideName, plotId, plotState.stage))
                    end
                end, true) -- allowVisitors: visitors can plant seeds for the owner
            end
        end

        -- Add field sign
        createSign(farmModel, sideName:upper() .. " FIELD", Vector3.new(centerX, GROUND_Y + 4, centerZ + 10), Vector3.new(5, 1, 0.3))
    end

    -- Create LEFT crop field (plots 1-12)
    createCropFieldSide("Left", baseX - 25, baseZ, 0)

    -- Create RIGHT crop field (plots 13-24)
    createCropFieldSide("Right", baseX + 25, baseZ, 12)

    -- Central walking path (dirt path between the two fields)
    local centralPath = Instance.new("Part")
    centralPath.Name = "CentralPath"
    centralPath.Size = Vector3.new(10, 0.2, 60)
    centralPath.Position = Vector3.new(baseX, GROUND_Y + 0.2, baseZ)
    centralPath.Anchored = true
    centralPath.Material = Enum.Material.Ground
    centralPath.Color = Color3.fromRGB(100, 80, 55)
    centralPath.Parent = farmModel

    -- Scarecrow in center (between the two fields)
    local scarecrowPost = Instance.new("Part")
    scarecrowPost.Name = "ScarecrowPost"
    scarecrowPost.Size = Vector3.new(0.5, 6, 0.5)
    scarecrowPost.Position = Vector3.new(baseX, GROUND_Y + 3, baseZ)
    scarecrowPost.Anchored = true
    scarecrowPost.Material = Enum.Material.Wood
    scarecrowPost.Color = Color3.fromRGB(90, 65, 45)
    scarecrowPost.Parent = farmModel

    local scarecrowArms = Instance.new("Part")
    scarecrowArms.Name = "ScarecrowArms"
    scarecrowArms.Size = Vector3.new(4, 0.4, 0.4)
    scarecrowArms.Position = Vector3.new(baseX, GROUND_Y + 5, baseZ)
    scarecrowArms.Anchored = true
    scarecrowArms.Material = Enum.Material.Wood
    scarecrowArms.Color = Color3.fromRGB(90, 65, 45)
    scarecrowArms.Parent = farmModel

    local scarecrowHead = Instance.new("Part")
    scarecrowHead.Name = "ScarecrowHead"
    scarecrowHead.Shape = Enum.PartType.Ball
    scarecrowHead.Size = Vector3.new(1.5, 1.5, 1.5)
    scarecrowHead.Position = Vector3.new(baseX, GROUND_Y + 6.5, baseZ)
    scarecrowHead.Anchored = true
    scarecrowHead.Material = Enum.Material.Fabric
    scarecrowHead.Color = Color3.fromRGB(200, 180, 140)
    scarecrowHead.Parent = farmModel

    -- Hat on scarecrow
    local scarecrowHat = Instance.new("Part")
    scarecrowHat.Name = "ScarecrowHat"
    scarecrowHat.Shape = Enum.PartType.Cylinder
    scarecrowHat.Size = Vector3.new(0.5, 2, 2)
    scarecrowHat.Position = Vector3.new(baseX, GROUND_Y + 7.5, baseZ)
    scarecrowHat.Anchored = true
    scarecrowHat.Material = Enum.Material.Fabric
    scarecrowHat.Color = Color3.fromRGB(100, 80, 60)
    scarecrowHat.Parent = farmModel

    -- ========== STEP 3: WELL (WATER CROPS) ==========
    -- Positioned in the center, accessible from both crop fields
    local wellPos = Vector3.new(baseX, GROUND_Y, baseZ + 12)

    local wellBase = Instance.new("Part")
    wellBase.Name = "WellBase"
    wellBase.Shape = Enum.PartType.Cylinder
    wellBase.Size = Vector3.new(2.5, 5, 5)
    wellBase.Position = wellPos + Vector3.new(0, 1.25, 0)
    wellBase.Anchored = true
    wellBase.Material = Enum.Material.Cobblestone
    wellBase.Color = Color3.fromRGB(100, 95, 90)
    wellBase.Parent = farmModel

    -- Well roof
    local wellRoof = Instance.new("Part")
    wellRoof.Name = "WellRoof"
    wellRoof.Size = Vector3.new(6, 0.5, 6)
    wellRoof.Position = wellPos + Vector3.new(0, 6, 0)
    wellRoof.Anchored = true
    wellRoof.Material = Enum.Material.Wood
    wellRoof.Color = Color3.fromRGB(80, 55, 35)
    wellRoof.Parent = farmModel

    -- Well posts
    for _, offset in {{-2.5, -2.5}, {-2.5, 2.5}, {2.5, -2.5}, {2.5, 2.5}} do
        local post = Instance.new("Part")
        post.Name = "WellPost"
        post.Size = Vector3.new(0.4, 4, 0.4)
        post.Position = wellPos + Vector3.new(offset[1], 4, offset[2])
        post.Anchored = true
        post.Material = Enum.Material.Wood
        post.Color = Color3.fromRGB(90, 65, 45)
        post.Parent = farmModel
    end

    -- Well bucket
    local bucket = Instance.new("Part")
    bucket.Name = "Bucket"
    bucket.Shape = Enum.PartType.Cylinder
    bucket.Size = Vector3.new(1, 1.5, 1.5)
    bucket.Position = wellPos + Vector3.new(0, 4, 0)
    bucket.Anchored = true
    bucket.Material = Enum.Material.Wood
    bucket.Color = Color3.fromRGB(100, 70, 50)
    bucket.Parent = farmModel

    -- Water in well
    local wellWater = Instance.new("Part")
    wellWater.Name = "WellWater"
    wellWater.Shape = Enum.PartType.Cylinder
    wellWater.Size = Vector3.new(0.3, 4, 4)
    wellWater.Position = wellPos + Vector3.new(0, 1, 0)
    wellWater.Anchored = true
    wellWater.Material = Enum.Material.Glass
    wellWater.Color = Color3.fromRGB(70, 130, 180)
    wellWater.Transparency = 0.4
    wellWater.Parent = farmModel

    createSign(farmModel, "WELL", wellPos + Vector3.new(0, 7, 3), Vector3.new(3, 1, 0.3))

    -- INTERACTION: Draw Water (speeds up crop growth in BOTH fields)
    createInteraction(wellBase, "Draw Water", "Well", 1, function(player)
        local wateringCanLevel = FarmState.equipment.wateringCanLevel
        local stats = getWateringCanStats(wateringCanLevel)
        local plotsWatered = stats.plotsPerWater

        -- Water random plots that need it (works across both left and right fields)
        local watered = 0
        for plotId, plotState in pairs(FarmState.plots) do
            if plotState.crop and not plotState.watered and watered < plotsWatered then
                plotState.watered = true
                plotState.stage = math.min(plotState.stage + 1, 3)

                -- Update visual - the crop part already knows its position
                local crop = cropParts[plotId]
                if crop and plotState.stage >= 3 then
                    crop.Transparency = 0
                    crop.Size = Vector3.new(2.5, 2.5, 2.5)
                    -- Adjust Y position for full-grown crop (move up by 1 stud)
                    local currentPos = crop.Position
                    crop.Position = Vector3.new(currentPos.X, GROUND_Y + 1.5, currentPos.Z)
                end

                watered = watered + 1
            end
        end

        addFarmXP(5)
        if watered > 0 then
            print(string.format("[Farm] %s watered %d plot(s)! Crops grow faster.", player.Name, watered))
        else
            print(string.format("[Farm] %s: No crops need watering right now.", player.Name))
        end

        -- Water splash effect
        local splash = Instance.new("ParticleEmitter")
        splash.Color = ColorSequence.new(Color3.fromRGB(100, 180, 255))
        splash.Size = NumberSequence.new(0.3)
        splash.Lifetime = NumberRange.new(0.3, 0.6)
        splash.Rate = 25
        splash.Speed = NumberRange.new(2, 5)
        splash.Parent = bucket
        task.delay(0.4, function() splash:Destroy() end)
    end, true) -- allowVisitors: visitors can draw water for the owner

    -- ========== STEP 4: HARVEST BASKET (LOAD CROPS) ==========
    -- REDESIGNED POSITION: Near windmill for easy crop drop-off before processing
    local basketPos = FarmState.positions.windmill + Vector3.new(0, 0, 8)  -- In front of windmill

    local harvestBasket = Instance.new("Part")
    harvestBasket.Name = "HarvestBasket"
    harvestBasket.Size = Vector3.new(5, 2.5, 4)
    harvestBasket.Position = basketPos + Vector3.new(0, 1.25, 0)
    harvestBasket.Anchored = true
    harvestBasket.Material = Enum.Material.WoodPlanks
    harvestBasket.Color = Color3.fromRGB(160, 130, 90)
    harvestBasket.Parent = farmModel

    -- ===== VISUAL HARVEST PILE SYSTEM =====
    local harvestPileContainer = Instance.new("Folder")
    harvestPileContainer.Name = "HarvestPileVisuals"
    harvestPileContainer.Parent = farmModel

    local visualCrops = {}
    local MAX_VISIBLE_CROPS = 12

    local function updateHarvestPileVisuals()
        local cropsToShow = math.min(math.floor(FarmState.harvestPile / 2), MAX_VISIBLE_CROPS)

        for i = 1, MAX_VISIBLE_CROPS do
            if not visualCrops[i] then
                -- Create crop bundle
                local crop = Instance.new("Part")
                crop.Name = "HarvestCrop" .. i
                crop.Size = Vector3.new(0.8 + math.random() * 0.3, 0.6 + math.random() * 0.2, 0.6 + math.random() * 0.2)
                local row = math.floor((i - 1) / 4)
                local col = (i - 1) % 4
                crop.Position = basketPos + Vector3.new(-1.2 + col * 0.8, 2.8 + row * 0.5, -0.8 + (i % 2) * 0.6)
                crop.Orientation = Vector3.new(0, math.random(360), 0)
                crop.Anchored = true
                crop.CanCollide = false
                crop.Material = Enum.Material.Grass
                crop.Color = Color3.fromRGB(220 + math.random(20), 200 + math.random(15), 80 + math.random(30))
                crop.Parent = harvestPileContainer
                visualCrops[i] = crop
            end

            visualCrops[i].Transparency = (i <= cropsToShow) and 0 or 1
        end
    end

    FarmState.updateHarvestPileVisuals = updateHarvestPileVisuals

    createSign(farmModel, "HARVEST", basketPos + Vector3.new(0, 5, 2), Vector3.new(4, 1, 0.3))

    -- WALK-THROUGH: Deposit Crops (walk by with crops to drop them off)
    local basketDepositTrigger = Instance.new("Part")
    basketDepositTrigger.Name = "BasketDepositTrigger"
    basketDepositTrigger.Size = Vector3.new(7, 5, 6)
    basketDepositTrigger.Position = basketPos + Vector3.new(0, 2.5, 0)
    basketDepositTrigger.Anchored = true
    basketDepositTrigger.Transparency = 1
    basketDepositTrigger.CanCollide = false
    basketDepositTrigger.Parent = farmModel

    local basketDebounce = {}
    basketDepositTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if basketDebounce[player.UserId] then return end

        local currentCrops = getPlayerCrops(player)
        if currentCrops > 0 then
            basketDebounce[player.UserId] = true

            -- Deposit crops to basket
            FarmState.harvestPile = FarmState.harvestPile + currentCrops
            setPlayerCrops(player, 0)

            -- Remove visual from player
            local bundle = character:FindFirstChild("CropBundle")
            if bundle then bundle:Destroy() end

            -- Update pile visuals
            updateHarvestPileVisuals()

            -- Update exterior stats billboard
            if FarmState.updateExteriorStats then
                FarmState.updateExteriorStats()
            end

            print(string.format("[Farm] %s deposited %d crops! (Harvest pile: %d)",
                player.Name, currentCrops, FarmState.harvestPile))

            -- Crop deposit particles
            local leaves = Instance.new("ParticleEmitter")
            leaves.Color = ColorSequence.new(Color3.fromRGB(220, 200, 100))
            leaves.Size = NumberSequence.new(0.3)
            leaves.Lifetime = NumberRange.new(0.3, 0.6)
            leaves.Rate = 20
            leaves.Speed = NumberRange.new(2, 4)
            leaves.Parent = harvestBasket
            task.delay(0.5, function() leaves:Destroy() end)

            task.delay(1, function() basketDebounce[player.UserId] = nil end)
        end
    end)

    -- ========== STEP 5: WINDMILL (PROCESS CROPS INTO FOOD) ==========
    -- REDESIGNED POSITION: Back-left wall for processing
    local windmillPos = FarmState.positions.windmill

    -- Windmill base
    local windmillBase = Instance.new("Part")
    windmillBase.Name = "WindmillBase"
    windmillBase.Size = Vector3.new(8, 12, 8)
    windmillBase.Position = windmillPos + Vector3.new(0, 6, 0)
    windmillBase.Anchored = true
    windmillBase.Material = Enum.Material.Cobblestone
    windmillBase.Color = Color3.fromRGB(180, 170, 160)
    windmillBase.Parent = farmModel

    -- Windmill top (cone-ish)
    local windmillTop = Instance.new("Part")
    windmillTop.Name = "WindmillTop"
    windmillTop.Size = Vector3.new(6, 4, 6)
    windmillTop.Position = windmillPos + Vector3.new(0, 14, 0)
    windmillTop.Anchored = true
    windmillTop.Material = Enum.Material.Wood
    windmillTop.Color = Color3.fromRGB(120, 90, 60)
    windmillTop.Parent = farmModel

    -- Windmill blades hub
    local bladeHub = Instance.new("Part")
    bladeHub.Name = "BladeHub"
    bladeHub.Shape = Enum.PartType.Cylinder
    bladeHub.Size = Vector3.new(2, 2, 2)
    bladeHub.Position = windmillPos + Vector3.new(0, 10, 4)
    bladeHub.Orientation = Vector3.new(90, 0, 0)
    bladeHub.Anchored = true
    bladeHub.Material = Enum.Material.Wood
    bladeHub.Color = Color3.fromRGB(100, 70, 50)
    bladeHub.Parent = farmModel

    -- Windmill blades
    for i = 1, 4 do
        local blade = Instance.new("Part")
        blade.Name = "Blade" .. i
        blade.Size = Vector3.new(1, 8, 0.3)
        blade.Position = windmillPos + Vector3.new(0, 10, 4.5)
        blade.Orientation = Vector3.new(0, 0, (i - 1) * 90 + 45)
        blade.Anchored = true
        blade.Material = Enum.Material.Wood
        blade.Color = Color3.fromRGB(140, 110, 80)
        blade.Parent = farmModel
    end

    -- Windmill door
    local windmillDoor = Instance.new("Part")
    windmillDoor.Name = "WindmillDoor"
    windmillDoor.Size = Vector3.new(3, 5, 0.5)
    windmillDoor.Position = windmillPos + Vector3.new(0, 2.5, 4)
    windmillDoor.Anchored = true
    windmillDoor.Material = Enum.Material.Wood
    windmillDoor.Color = Color3.fromRGB(80, 55, 35)
    windmillDoor.Parent = farmModel

    -- Crop hopper at windmill entrance
    local hopper = Instance.new("Part")
    hopper.Name = "CropHopper"
    hopper.Size = Vector3.new(4, 2, 3)
    hopper.Position = windmillPos + Vector3.new(-5, 1, 4)
    hopper.Anchored = true
    hopper.Material = Enum.Material.Wood
    hopper.Color = Color3.fromRGB(120, 90, 60)
    hopper.Parent = farmModel

    -- Sign on windmill - faces forward toward entrance (+Z)
    local windmillSignPos = windmillPos + Vector3.new(0, 13, 5)
    local windmillSign = Instance.new("Part")
    windmillSign.Name = "WindmillSign"
    windmillSign.Size = Vector3.new(5, 1.5, 0.3)
    windmillSign.Anchored = true
    windmillSign.Material = Enum.Material.Wood
    windmillSign.Color = Color3.fromRGB(110, 80, 55)
    windmillSign.CFrame = CFrame.lookAt(windmillSignPos, windmillSignPos + Vector3.new(0, 0, 10))
    windmillSign.Parent = farmModel

    local windmillSignGui = Instance.new("SurfaceGui")
    windmillSignGui.Face = Enum.NormalId.Back -- Text on front face (facing forward)
    windmillSignGui.Parent = windmillSign

    local windmillSignLabel = Instance.new("TextLabel")
    windmillSignLabel.Size = UDim2.new(1, 0, 1, 0)
    windmillSignLabel.BackgroundTransparency = 1
    windmillSignLabel.Text = "WINDMILL"
    windmillSignLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    windmillSignLabel.TextScaled = true
    windmillSignLabel.Font = Enum.Font.GothamBold
    windmillSignLabel.Parent = windmillSignGui
    makeSignDoubleSided(windmillSign)

    -- ===== WINDMILL PROGRESS BAR UI =====
    local windmillBillboard = Instance.new("BillboardGui")
    windmillBillboard.Name = "WindmillStatus"
    windmillBillboard.Size = UDim2.new(8, 0, 2, 0)
    windmillBillboard.StudsOffset = Vector3.new(0, 17, 3)
    windmillBillboard.AlwaysOnTop = true
    windmillBillboard.Parent = windmillBase

    local windmillTitle = Instance.new("TextLabel")
    windmillTitle.Name = "Title"
    windmillTitle.Size = UDim2.new(1, 0, 0.4, 0)
    windmillTitle.Position = UDim2.new(0, 0, 0, 0)
    windmillTitle.BackgroundTransparency = 1
    windmillTitle.Text = "WINDMILL"
    windmillTitle.TextColor3 = Color3.fromRGB(220, 200, 100)
    windmillTitle.TextStrokeTransparency = 0.3
    windmillTitle.TextScaled = true
    windmillTitle.Font = Enum.Font.GothamBold
    windmillTitle.Parent = windmillBillboard

    local windmillProgressFrame = Instance.new("Frame")
    windmillProgressFrame.Name = "ProgressFrame"
    windmillProgressFrame.Size = UDim2.new(0.8, 0, 0.2, 0)
    windmillProgressFrame.Position = UDim2.new(0.1, 0, 0.4, 0)
    windmillProgressFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    windmillProgressFrame.BorderSizePixel = 2
    windmillProgressFrame.BorderColor3 = Color3.fromRGB(100, 100, 100)
    windmillProgressFrame.Parent = windmillBillboard

    local windmillProgressBar = Instance.new("Frame")
    windmillProgressBar.Name = "ProgressBar"
    windmillProgressBar.Size = UDim2.new(0, 0, 1, 0)
    windmillProgressBar.Position = UDim2.new(0, 0, 0, 0)
    windmillProgressBar.BackgroundColor3 = Color3.fromRGB(220, 200, 100)
    windmillProgressBar.BorderSizePixel = 0
    windmillProgressBar.Parent = windmillProgressFrame

    local windmillStatusText = Instance.new("TextLabel")
    windmillStatusText.Name = "StatusText"
    windmillStatusText.Size = UDim2.new(1, 0, 0.35, 0)
    windmillStatusText.Position = UDim2.new(0, 0, 0.65, 0)
    windmillStatusText.BackgroundTransparency = 1
    windmillStatusText.Text = "Idle - Waiting for crops"
    windmillStatusText.TextColor3 = Color3.fromRGB(200, 200, 200)
    windmillStatusText.TextStrokeTransparency = 0.5
    windmillStatusText.TextScaled = true
    windmillStatusText.Font = Enum.Font.Gotham
    windmillStatusText.Parent = windmillBillboard

    -- Function to update windmill UI
    local function updateWindmillUI(status, progress)
        windmillStatusText.Text = status
        windmillProgressBar.Size = UDim2.new(progress, 0, 1, 0)
        if progress > 0 then
            windmillProgressBar.BackgroundColor3 = Color3.fromRGB(220, 200, 100)
        end
    end

    -- Store for access from worker loops
    FarmState.updateWindmillUI = updateWindmillUI

    -- ===== INDEPENDENT WINDMILL PROCESSING LOOP =====
    -- Runs continuously, processes crop queue one at a time
    -- Progress bar fills 0->100% for EACH crop
    task.spawn(function()
        while true do
            if FarmState.windmillCrops > 0 then
                -- Get current windmill stats (rechecks each crop for live upgrades)
                local windmillStats = getWindmillStatsFunc(FarmState.equipment.windmillLevel)
                local baseGrainPerCrop = windmillStats.grainPerCrop
                local baseProcessTime = windmillStats.processTime

                -- Apply production and speed bonuses from Town Hall
                local productionMultiplier = 1.0
                local speedMultiplier = 1.0
                if TownHallState and calculateTotalBonuses then
                    local bonuses = calculateTotalBonuses()
                    productionMultiplier = bonuses.production.windmill or 1.0
                    speedMultiplier = bonuses.speed.windmill or 1.0
                end
                local grainPerCrop = math.floor(baseGrainPerCrop * productionMultiplier)
                local processTime = baseProcessTime / speedMultiplier -- faster = divide time

                -- Process one crop at a time
                while FarmState.windmillCrops > 0 do
                    -- Recheck stats each crop (in case player upgrades mid-batch)
                    windmillStats = getWindmillStatsFunc(FarmState.equipment.windmillLevel)
                    baseGrainPerCrop = windmillStats.grainPerCrop
                    baseProcessTime = windmillStats.processTime

                    -- Re-apply bonuses
                    if TownHallState and calculateTotalBonuses then
                        local bonuses = calculateTotalBonuses()
                        productionMultiplier = bonuses.production.windmill or 1.0
                        speedMultiplier = bonuses.speed.windmill or 1.0
                    end
                    grainPerCrop = math.floor(baseGrainPerCrop * productionMultiplier)
                    processTime = baseProcessTime / speedMultiplier

                    local cropsRemaining = FarmState.windmillCrops

                    -- Animate progress bar from 0 to 100% for this single crop
                    local steps = 20  -- Number of progress updates
                    local stepTime = processTime / steps

                    for step = 1, steps do
                        local progress = step / steps
                        updateWindmillUI(
                            string.format("Grinding... %d crops queued | Lv%d: %dg/crop",
                                cropsRemaining, FarmState.equipment.windmillLevel, grainPerCrop),
                            progress
                        )
                        task.wait(stepTime)
                    end

                    -- Convert one crop to food
                    FarmState.windmillCrops = FarmState.windmillCrops - 1
                    FarmState.foodStorage = FarmState.foodStorage + grainPerCrop
                    addFarmXP(10)

                    -- Update food storage visuals immediately
                    if FarmState.updateFoodStorageVisuals then
                        FarmState.updateFoodStorageVisuals()
                    end

                    -- Update exterior stats billboard
                    if FarmState.updateExteriorStats then
                        FarmState.updateExteriorStats()
                    end

                    -- Brief flash at 100% before resetting for next crop
                    updateWindmillUI(
                        string.format("+%d food! (%d crops left)", grainPerCrop, FarmState.windmillCrops),
                        1
                    )
                    task.wait(0.2)

                    print(string.format("[Windmill Lv%d] 1 crop -> +%d food (Queue: %d, Storage: %d)",
                        FarmState.equipment.windmillLevel, grainPerCrop, FarmState.windmillCrops, FarmState.foodStorage))
                end

                -- Done processing batch
                updateWindmillUI(
                    string.format("Ready: %d food | Idle", FarmState.foodStorage),
                    0
                )
            else
                -- Idle state
                local windmillStats = getWindmillStatsFunc(FarmState.equipment.windmillLevel)
                if FarmState.foodStorage > 0 then
                    updateWindmillUI(
                        string.format("Ready: %d food | Lv%d Windmill", FarmState.foodStorage, FarmState.equipment.windmillLevel),
                        0
                    )
                else
                    updateWindmillUI(string.format("Idle | Lv%d: %dg/crop, %.1fs",
                        FarmState.equipment.windmillLevel, windmillStats.grainPerCrop, windmillStats.processTime), 0)
                end
                task.wait(1) -- Check for crops every second
            end
        end
    end)

    -- ===== WINDMILL WALK-THROUGH SYSTEM =====
    -- Input side: Drop off crops for processing (now just adds to queue)
    local windmillInputTrigger = Instance.new("Part")
    windmillInputTrigger.Name = "WindmillInputTrigger"
    windmillInputTrigger.Size = Vector3.new(8, 5, 6)
    windmillInputTrigger.Position = windmillPos + Vector3.new(-3, 2.5, 4)
    windmillInputTrigger.Anchored = true
    windmillInputTrigger.Transparency = 1
    windmillInputTrigger.CanCollide = false
    windmillInputTrigger.Parent = farmModel

    local windmillInputDebounce = {}
    windmillInputTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if windmillInputDebounce[player.UserId] then return end

        -- Check if player is carrying crops OR if harvest pile has crops
        local currentCrops = getPlayerCrops(player)
        local cropsToProcess = 0

        if currentCrops > 0 then
            -- Use player's carried crops
            cropsToProcess = currentCrops
            setPlayerCrops(player, 0)

            -- Remove visual from player
            local bundle = character:FindFirstChild("CropBundle")
            if bundle then bundle:Destroy() end
        elseif FarmState.harvestPile > 0 then
            -- Use crops from harvest basket
            cropsToProcess = math.min(FarmState.harvestPile, 10)
            FarmState.harvestPile = FarmState.harvestPile - cropsToProcess
            updateHarvestPileVisuals()

            -- Update exterior stats billboard
            if FarmState.updateExteriorStats then
                FarmState.updateExteriorStats()
            end
        end

        if cropsToProcess > 0 then
            windmillInputDebounce[player.UserId] = true

            -- Add to windmill queue (the independent loop will process)
            FarmState.windmillCrops = FarmState.windmillCrops + cropsToProcess

            -- Update exterior stats billboard
            if FarmState.updateExteriorStats then
                FarmState.updateExteriorStats()
            end

            print(string.format("[Farm] %s loaded %d crops into windmill! (Queue: %d)",
                player.Name, cropsToProcess, FarmState.windmillCrops))

            -- Grain particles
            local grain = Instance.new("ParticleEmitter")
            grain.Color = ColorSequence.new(Color3.fromRGB(240, 220, 150))
            grain.Size = NumberSequence.new(0.3)
            grain.Lifetime = NumberRange.new(0.5, 1)
            grain.Rate = 20
            grain.Speed = NumberRange.new(1, 3)
            grain.Parent = hopper
            task.delay(0.8, function() grain:Destroy() end)

            task.delay(1.5, function() windmillInputDebounce[player.UserId] = nil end)
        end
    end)

    -- ========== STEP 6: OUTPUT SILO (COLLECT FOOD) ==========
    -- REDESIGNED POSITION: Near windmill (back-left area) for easy pickup
    local siloPos = FarmState.positions.windmill + Vector3.new(10, 0, 0)  -- Right of windmill

    local silo = Instance.new("Part")
    silo.Name = "Silo"
    silo.Shape = Enum.PartType.Cylinder
    silo.Size = Vector3.new(8, 6, 6)
    silo.Position = siloPos + Vector3.new(0, 4, 0)
    silo.Anchored = true
    silo.Material = Enum.Material.Metal
    silo.Color = Color3.fromRGB(180, 170, 160)
    silo.Parent = farmModel

    -- Silo roof
    local siloRoof = Instance.new("Part")
    siloRoof.Name = "SiloRoof"
    siloRoof.Shape = Enum.PartType.Ball
    siloRoof.Size = Vector3.new(6, 3, 6)
    siloRoof.Position = siloPos + Vector3.new(0, 8.5, 0)
    siloRoof.Anchored = true
    siloRoof.Material = Enum.Material.Metal
    siloRoof.Color = Color3.fromRGB(150, 50, 50)
    siloRoof.Parent = farmModel

    -- ===== VISUAL FOOD STORAGE SYSTEM =====
    local foodStorageContainer = Instance.new("Folder")
    foodStorageContainer.Name = "FoodStorageVisuals"
    foodStorageContainer.Parent = farmModel

    local visualFoodSacks = {}
    local MAX_VISIBLE_SACKS = 10

    local function updateFoodStorageVisuals()
        local sacksToShow = math.min(math.floor(FarmState.foodStorage / 10), MAX_VISIBLE_SACKS)

        for i = 1, MAX_VISIBLE_SACKS do
            if not visualFoodSacks[i] then
                -- Create flour/food sack
                local sack = Instance.new("Part")
                sack.Name = "FoodSack" .. i
                sack.Size = Vector3.new(1.2, 1.5, 1)
                local angle = (i / MAX_VISIBLE_SACKS) * math.pi * 2
                local radius = 4
                sack.Position = siloPos + Vector3.new(math.cos(angle) * radius, 0.75 + math.floor((i-1) / 5) * 1.3, math.sin(angle) * radius)
                sack.Orientation = Vector3.new(0, angle * 180 / math.pi + math.random(30), 0)
                sack.Anchored = true
                sack.CanCollide = false
                sack.Material = Enum.Material.Fabric
                sack.Color = Color3.fromRGB(200 + math.random(20), 180 + math.random(15), 140 + math.random(20))
                sack.Parent = foodStorageContainer
                visualFoodSacks[i] = sack
            end

            visualFoodSacks[i].Transparency = (i <= sacksToShow) and 0 or 1
        end
    end

    FarmState.updateFoodStorageVisuals = updateFoodStorageVisuals

    createSign(farmModel, "SILO", siloPos + Vector3.new(0, 10, 3), Vector3.new(3, 1, 0.3))

    -- WALK-THROUGH: Pick up Food from Silo
    local siloPickupTrigger = Instance.new("Part")
    siloPickupTrigger.Name = "SiloPickupTrigger"
    siloPickupTrigger.Size = Vector3.new(10, 5, 10)
    siloPickupTrigger.Position = siloPos + Vector3.new(0, 2.5, 0)
    siloPickupTrigger.Anchored = true
    siloPickupTrigger.Transparency = 1
    siloPickupTrigger.CanCollide = false
    siloPickupTrigger.Parent = farmModel

    local siloPickupDebounce = {}
    siloPickupTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if siloPickupDebounce[player.UserId] then return end

        local currentFood = getPlayerFood(player)
        local maxCarry = 50

        if FarmState.foodStorage > 0 and currentFood < maxCarry then
            siloPickupDebounce[player.UserId] = true

            -- Pick up food
            local foodToTake = math.min(FarmState.foodStorage, maxCarry - currentFood)
            FarmState.foodStorage = FarmState.foodStorage - foodToTake
            setPlayerFood(player, currentFood + foodToTake)

            -- Add visual to player
            updatePlayerFoodVisual(player, currentFood + foodToTake)

            -- Update silo visuals
            updateFoodStorageVisuals()

            -- Update exterior stats billboard
            if FarmState.updateExteriorStats then
                FarmState.updateExteriorStats()
            end

            print(string.format("[Farm] %s picked up %d food! (Carrying: %d/%d)",
                player.Name, foodToTake, getPlayerFood(player), maxCarry))

            -- Pickup particles
            local pickup = Instance.new("ParticleEmitter")
            pickup.Color = ColorSequence.new(Color3.fromRGB(240, 220, 150))
            pickup.Size = NumberSequence.new(0.2)
            pickup.Lifetime = NumberRange.new(0.2, 0.4)
            pickup.Rate = 15
            pickup.Speed = NumberRange.new(2, 4)
            pickup.Parent = silo
            task.delay(0.4, function() pickup:Destroy() end)

            task.delay(1, function() siloPickupDebounce[player.UserId] = nil end)
        end
    end)

    -- ========== STEP 6.5: STORAGE SHED (DEPOSIT FOOD FOR REWARD) ==========
    -- REDESIGNED POSITION: Back-right wall (collection point) - faces forward toward entrance (+Z)
    local storageShedPos = FarmState.positions.storageShed

    local storageShed = Instance.new("Part")
    storageShed.Name = "StorageShed"
    storageShed.Size = Vector3.new(6, 5, 5)
    storageShed.Anchored = true
    storageShed.Material = Enum.Material.Wood
    storageShed.Color = Color3.fromRGB(120, 90, 60)
    -- Face forward toward entrance (+Z direction)
    local storageShedCenterPos = storageShedPos + Vector3.new(0, 2.5, 0)
    storageShed.CFrame = CFrame.lookAt(storageShedCenterPos, storageShedCenterPos + Vector3.new(0, 0, 10))
    storageShed.Parent = farmModel

    -- Shed roof - oriented to match shed facing
    local storageShedRoof = Instance.new("Part")
    storageShedRoof.Name = "StorageShedRoof"
    storageShedRoof.Size = Vector3.new(7, 0.5, 6)
    storageShedRoof.Anchored = true
    storageShedRoof.Material = Enum.Material.Wood
    storageShedRoof.Color = Color3.fromRGB(90, 65, 45)
    storageShedRoof.CFrame = storageShed.CFrame * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(8))
    storageShedRoof.Parent = farmModel

    -- Sign above shed - faces forward toward entrance (+Z)
    local storageSignPos = storageShedPos + Vector3.new(0, 6.5, 3)
    local storageSign = Instance.new("Part")
    storageSign.Name = "StorageSign"
    storageSign.Size = Vector3.new(4, 1, 0.3)
    storageSign.Anchored = true
    storageSign.Material = Enum.Material.Wood
    storageSign.Color = Color3.fromRGB(110, 80, 55)
    storageSign.CFrame = CFrame.lookAt(storageSignPos, storageSignPos + Vector3.new(0, 0, 10))
    storageSign.Parent = farmModel

    local storageSignGui = Instance.new("SurfaceGui")
    storageSignGui.Face = Enum.NormalId.Back -- Text on front face (facing forward)
    storageSignGui.Parent = storageSign

    local storageSignLabel = Instance.new("TextLabel")
    storageSignLabel.Size = UDim2.new(1, 0, 1, 0)
    storageSignLabel.BackgroundTransparency = 1
    storageSignLabel.Text = "STORAGE"
    storageSignLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    storageSignLabel.TextScaled = true
    storageSignLabel.Font = Enum.Font.GothamBold
    storageSignLabel.Parent = storageSignGui
    makeSignDoubleSided(storageSign)

    -- WALK-THROUGH: Deposit Food for Reward
    local storageShedTrigger = Instance.new("Part")
    storageShedTrigger.Name = "StorageShedTrigger"
    storageShedTrigger.Size = Vector3.new(8, 5, 7)
    storageShedTrigger.Position = storageShedPos + Vector3.new(0, 2.5, 0)
    storageShedTrigger.Anchored = true
    storageShedTrigger.Transparency = 1
    storageShedTrigger.CanCollide = false
    storageShedTrigger.Parent = farmModel

    local storageShedDebounce = {}
    storageShedTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if storageShedDebounce[player.UserId] then return end

        local playerCarriedFood = getPlayerFood(player)
        if playerCarriedFood > 0 then
            storageShedDebounce[player.UserId] = true

            -- DEPOSIT: Player carrying food
            local foodToDeposit = playerCarriedFood
            setPlayerFood(player, 0)

            -- Remove visual from player
            local sack = character:FindFirstChild("FoodSack")
            if sack then sack:Destroy() end

            -- REWARD the player!
            rewardPlayer(player, "food", foodToDeposit, "Farm")

            print(string.format("[Farm] %s stored %d food! (+%d food)",
                player.Name, foodToDeposit, foodToDeposit))

            -- Storage sparkle effect
            local sparkle = Instance.new("ParticleEmitter")
            sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150))
            sparkle.Size = NumberSequence.new(0.3, 0)
            sparkle.Lifetime = NumberRange.new(0.4, 0.8)
            sparkle.Rate = 30
            sparkle.Speed = NumberRange.new(3, 6)
            sparkle.SpreadAngle = Vector2.new(60, 60)
            sparkle.Parent = storageShed
            task.delay(0.6, function() sparkle:Destroy() end)

            task.delay(1, function() storageShedDebounce[player.UserId] = nil end)
        end
    end)

    -- ========== STEP 7: HIRE FARMERS STATION ==========
    -- REDESIGNED POSITION: Front area, left side - faces toward center (right/toward baseX)
    local hireFarmerPos = FarmState.positions.hireFarmer

    local barn = Instance.new("Part")
    barn.Name = "HireFarmerStation"
    barn.Size = Vector3.new(8, 6, 6)
    barn.Anchored = true
    barn.Material = Enum.Material.Wood
    barn.Color = Color3.fromRGB(160, 60, 60) -- Red barn
    -- Face toward center (toward baseX, i.e. right from this position)
    local barnCenterPos = hireFarmerPos + Vector3.new(0, 3, 0)
    barn.CFrame = CFrame.lookAt(barnCenterPos, Vector3.new(baseX, barnCenterPos.Y, barnCenterPos.Z))
    barn.Parent = farmModel

    -- Barn roof - oriented to match barn facing
    local barnRoof = Instance.new("WedgePart")
    barnRoof.Name = "BarnRoof"
    barnRoof.Size = Vector3.new(8, 3, 4)
    barnRoof.Anchored = true
    barnRoof.Material = Enum.Material.Wood
    barnRoof.Color = Color3.fromRGB(130, 50, 50)
    barnRoof.CFrame = barn.CFrame * CFrame.new(0, 4.5, 1) * CFrame.Angles(0, math.rad(180), 0)
    barnRoof.Parent = farmModel

    local barnRoof2 = Instance.new("WedgePart")
    barnRoof2.Name = "BarnRoof2"
    barnRoof2.Size = Vector3.new(8, 3, 4)
    barnRoof2.Anchored = true
    barnRoof2.Material = Enum.Material.Wood
    barnRoof2.Color = Color3.fromRGB(130, 50, 50)
    barnRoof2.CFrame = barn.CFrame * CFrame.new(0, 4.5, -2)
    barnRoof2.Parent = farmModel

    -- Farmhand figure (NPC standing in front of barn, toward center)
    local farmhandBody = Instance.new("Part")
    farmhandBody.Name = "FarmhandBody"
    farmhandBody.Size = Vector3.new(1.5, 2.8, 1)
    farmhandBody.Anchored = true
    farmhandBody.Material = Enum.Material.SmoothPlastic
    farmhandBody.Color = Color3.fromRGB(100, 80, 60)
    -- Position in front of barn (toward center)
    farmhandBody.CFrame = barn.CFrame * CFrame.new(0, -1.6, -4)
    farmhandBody.Parent = farmModel

    -- Farmhand head
    local farmhandHead = Instance.new("Part")
    farmhandHead.Name = "FarmhandHead"
    farmhandHead.Shape = Enum.PartType.Ball
    farmhandHead.Size = Vector3.new(1.2, 1.2, 1.2)
    farmhandHead.Anchored = true
    farmhandHead.Material = Enum.Material.SmoothPlastic
    farmhandHead.Color = Color3.fromRGB(210, 180, 140)
    farmhandHead.CFrame = barn.CFrame * CFrame.new(0, 0.4, -4)
    farmhandHead.Parent = farmModel

    -- Straw hat
    local strawHat = Instance.new("Part")
    strawHat.Name = "StrawHat"
    strawHat.Shape = Enum.PartType.Cylinder
    strawHat.Size = Vector3.new(0.3, 2, 2)
    strawHat.Anchored = true
    strawHat.Material = Enum.Material.Fabric
    strawHat.Color = Color3.fromRGB(220, 200, 120)
    strawHat.CFrame = barn.CFrame * CFrame.new(0, 1.1, -4) * CFrame.Angles(0, 0, math.rad(90))
    strawHat.Parent = farmModel

    -- Sign above barn - faces toward center
    local farmSignPos = hireFarmerPos + Vector3.new(0, 7, 0)
    local farmHireSign = Instance.new("Part")
    farmHireSign.Name = "HireFarmersSign"
    farmHireSign.Size = Vector3.new(6, 1.5, 0.3)
    farmHireSign.Anchored = true
    farmHireSign.Material = Enum.Material.Wood
    farmHireSign.Color = Color3.fromRGB(110, 80, 55)
    farmHireSign.CFrame = CFrame.lookAt(farmSignPos, Vector3.new(baseX, farmSignPos.Y, farmSignPos.Z))
    farmHireSign.Parent = farmModel

    local farmHireSignGui = Instance.new("SurfaceGui")
    farmHireSignGui.Face = Enum.NormalId.Back -- Text on front face (facing center)
    farmHireSignGui.Parent = farmHireSign

    local farmHireSignLabel = Instance.new("TextLabel")
    farmHireSignLabel.Size = UDim2.new(1, 0, 1, 0)
    farmHireSignLabel.BackgroundTransparency = 1
    farmHireSignLabel.Text = "HIRE FARMERS"
    farmHireSignLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    farmHireSignLabel.TextScaled = true
    farmHireSignLabel.Font = Enum.Font.GothamBold
    farmHireSignLabel.Parent = farmHireSignGui

    -- Store reference for updating later (like Gold Mine pattern)
    FarmState.farmerSign = farmHireSignLabel
    makeSignDoubleSided(farmHireSign)

    -- Table/counter in front of workers (player approaches from center)
    local farmerTable = Instance.new("Part")
    farmerTable.Name = "FarmerHiringTable"
    farmerTable.Size = Vector3.new(8, 1, 2)
    farmerTable.Anchored = true
    farmerTable.Material = Enum.Material.Wood
    farmerTable.Color = Color3.fromRGB(90, 65, 45)
    -- Table is in front of barn (toward center)
    farmerTable.CFrame = barn.CFrame * CFrame.new(0, -2, -6)
    farmerTable.Parent = farmModel

    -- Table legs
    for i = -1, 1, 2 do
        for j = -1, 1, 2 do
            local leg = Instance.new("Part")
            leg.Name = "TableLeg"
            leg.Size = Vector3.new(0.3, 1, 0.3)
            leg.Anchored = true
            leg.Material = Enum.Material.Wood
            leg.Color = Color3.fromRGB(70, 50, 35)
            leg.CFrame = farmerTable.CFrame * CFrame.new(i * 3.5, -0.5, j * 0.7)
            leg.Parent = farmModel
        end
    end

    -- 3 Waiting farmer NPCs standing behind table (like Gold Mine pattern)
    FarmState.waitingFarmers = {}
    for i = 1, 3 do
        -- Workers behind table, spread along X axis: -3, 0, +3
        local waitingFarmerPos = hireFarmerPos + Vector3.new((i - 2) * 3, 0, 0)
        local waitingFarmer = createWorkerNPC(
            "WaitingFarmer" .. i,
            waitingFarmerPos,
            Color3.fromRGB(100, 140, 100), -- Green overalls
            "Farmer"
        )
        setNPCStatus(waitingFarmer, "For hire!")
        waitingFarmer.Parent = farmModel
        table.insert(FarmState.waitingFarmers, waitingFarmer)
    end

    -- INTERACTION: Hire Farmer NPC (on the table, like Gold Mine)
    createInteraction(farmerTable, "Hire Farmer (1,200g + 240f)", "Hiring Table", 1, function(player)
        -- Check if any waiting workers left at the stand
        if #FarmState.waitingFarmers == 0 then
            print(string.format("[Farm] %s: No workers available to hire!", player.Name))
            notifyPlayer(player, "HireWorker", false, "No farmers available to hire!")
            return
        end

        local farmerCount = #FarmState.farmers
        local maxFarmers = 3

        if farmerCount >= maxFarmers then
            print(string.format("[Farm] %s: Max farmers (3) reached!", player.Name))
            notifyPlayer(player, "HireWorker", false, "Max farmers (3) already hired!")
            return
        end

        local cost = FarmerCosts[farmerCount + 1]
        if not deductPlayerResources(player, {gold = cost.gold, food = cost.food}, "Farm") then
            notifyPlayer(player, "HireWorker", false, string.format("Need %dg + %df to hire!", cost.gold, cost.food))
            return
        end
        notifyPlayer(player, "HireWorker", true, "Farmer hired!")
        local farmerId = farmerCount + 1

        -- Remove one waiting worker from the stand (they walk away to work)
        local waitingWorker = table.remove(FarmState.waitingFarmers, 1)
        if waitingWorker then
            -- Make the waiting worker walk away before destroying
            local workerRoot = waitingWorker:FindFirstChild("HumanoidRootPart") or waitingWorker:FindFirstChild("Torso")
            if workerRoot then
                local walkAwayPos = FarmState.positions.workerSpawn + Vector3.new(farmerCount * 3, 0, 0)
                walkNPCTo(waitingWorker, walkAwayPos, 6, function()
                    _npcAnimTracks[waitingWorker] = nil
                    waitingWorker:Destroy()
                end)
            else
                _npcAnimTracks[waitingWorker] = nil
                waitingWorker:Destroy()
            end
        end

        -- Update sign if no more waiting workers
        if #FarmState.waitingFarmers == 0 then
            if FarmState.farmerSign then
                FarmState.farmerSign.Text = "FULLY STAFFED"
                FarmState.farmerSign.TextColor3 = Color3.fromRGB(150, 150, 150)
            end
        end

        -- Create visible farmer NPC at hiring booth (walks to work from there)
        local spawnPos = FarmState.positions.hireFarmer
        local farmer = createWorkerNPC(
            "Farmer " .. farmerId,
            spawnPos,
            Color3.fromRGB(100, 140, 100), -- Green overalls
            "Farmer"
        )
        farmer.Parent = farmModel

        local farmerData = {
            npc = farmer,
            state = "idle",
            carrying = 0,
        }
        table.insert(FarmState.farmers, farmerData)

        -- Start farmer AI loop with async completion-flag pattern
        task.spawn(function()
            while farmerData.npc and farmerData.npc.Parent do
                local cycleComplete = false

                -- Get current farmer stats (updates each cycle based on upgrades)
                local farmerStats = getFarmerStats(FarmState.equipment.farmerLevel)
                local cropCapacity = farmerStats.cropCapacity
                local walkSpeed = farmerStats.walkSpeed
                local harvestTime = farmerStats.harvestTime

                -- Walk to crop field (randomly choose left or right field)
                farmerData.state = "walking_to_field"
                setNPCStatus(farmer, "Walking to field...")
                local fieldBase = math.random() < 0.5 and FarmState.positions.cropFieldLeft or FarmState.positions.cropFieldRight
                local fieldPos = fieldBase + Vector3.new(math.random(-5, 5), 0, math.random(-6, 6))
                walkNPCTo(farmer, fieldPos, walkSpeed, function()
                    -- Harvest crops with visual status display
                    farmerData.state = "harvesting"

                    -- Harvest with progress display
                    local cropsHarvested = 0
                    for harvest = 1, cropCapacity do
                        cropsHarvested = harvest
                        setNPCStatus(farmer, string.format("Harvesting %d/%d", cropsHarvested, cropCapacity))

                        -- Harvest particle effect
                        local torso = farmer:FindFirstChild("UpperTorso") or farmer:FindFirstChild("Torso")
                        if torso then
                            local leaves = Instance.new("ParticleEmitter")
                            leaves.Color = ColorSequence.new(Color3.fromRGB(220, 200, 100))
                            leaves.Size = NumberSequence.new(0.3)
                            leaves.Lifetime = NumberRange.new(0.3, 0.5)
                            leaves.Rate = 15
                            leaves.Speed = NumberRange.new(2, 4)
                            leaves.SpreadAngle = Vector2.new(30, 30)
                            leaves.Parent = torso
                            task.delay(0.4, function() leaves:Destroy() end)
                        end
                        task.wait(harvestTime)
                    end

                    -- Pick up crops
                    farmerData.carrying = cropCapacity
                    setNPCCarrying(farmer, "crops", math.min(5, math.ceil(cropCapacity / 3)))
                    setNPCStatus(farmer, string.format("Carrying %d crops", cropCapacity))
                    print(string.format("[Farmer #%d] Harvested %d crops", farmerId, cropCapacity))

                    -- Walk to windmill input
                    farmerData.state = "walking_to_windmill"
                    setNPCStatus(farmer, "Delivering crops...")
                    walkNPCTo(farmer, FarmState.positions.windmillInput, walkSpeed, function()
                        -- Deposit crops into windmill queue
                        farmerData.state = "depositing"
                        setNPCStatus(farmer, "Loading windmill...")
                        task.wait(0.5)

                        -- Add crops to windmill queue
                        local cropsDeposited = farmerData.carrying
                        FarmState.windmillCrops = FarmState.windmillCrops + cropsDeposited
                        farmerData.carrying = 0
                        setNPCCarrying(farmer, nil, 0)

                        -- Update exterior stats billboard
                        if FarmState.updateExteriorStats then
                            FarmState.updateExteriorStats()
                        end

                        print(string.format("[Farmer #%d] Deposited %d crops (Queue: %d)",
                            farmerId, cropsDeposited, FarmState.windmillCrops))

                        -- Immediately go back (don't wait for processing)
                        farmerData.state = "idle"
                        setNPCStatus(farmer, "Returning...")
                        cycleComplete = true
                    end)
                end)

                -- Wait for cycle to complete before starting next one
                while not cycleComplete and farmerData.npc and farmerData.npc.Parent do
                    task.wait(0.5)
                end

                task.wait(1) -- Brief pause between cycles
            end
        end)

        print(string.format("[Farm] %s hired Farmer #%d for %d gold + %d food!",
            player.Name, farmerId, cost.gold, cost.food))
        print(string.format("[Farm] Farmer #%d will harvest crops -> deliver to windmill -> repeat!", farmerId))

        -- Update production display (like Gold Mine pattern)
        if FarmState.updateFarmProduction then
            FarmState.updateFarmProduction()
        end
    end)

    -- ========== HIRE CARRIERS STATION ==========
    -- REDESIGNED POSITION: Front area, right side - faces toward center (left/toward baseX)
    local hireCarrierPos = FarmState.positions.hireCarrier

    local carrierBoard = Instance.new("Part")
    carrierBoard.Name = "CarrierHiringStation"
    carrierBoard.Size = Vector3.new(6, 5, 5)
    carrierBoard.Anchored = true
    carrierBoard.Material = Enum.Material.Wood
    carrierBoard.Color = Color3.fromRGB(60, 90, 60) -- Green-ish
    -- Face toward center (toward baseX, i.e. left from this position since it's at baseX+15)
    local carrierBoardCenterPos = hireCarrierPos + Vector3.new(0, 2.5, 0)
    carrierBoard.CFrame = CFrame.lookAt(carrierBoardCenterPos, Vector3.new(baseX, carrierBoardCenterPos.Y, carrierBoardCenterPos.Z))
    carrierBoard.Parent = farmModel

    -- Carrier station roof - oriented to match station facing
    local carrierRoof = Instance.new("Part")
    carrierRoof.Name = "CarrierStationRoof"
    carrierRoof.Size = Vector3.new(7, 0.5, 6)
    carrierRoof.Anchored = true
    carrierRoof.Material = Enum.Material.Wood
    carrierRoof.Color = Color3.fromRGB(50, 70, 50)
    carrierRoof.CFrame = carrierBoard.CFrame * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(8))
    carrierRoof.Parent = farmModel

    -- Sign above station - faces toward center
    local carrierSignPos = hireCarrierPos + Vector3.new(0, 7, 0)
    local carrierHireSign = Instance.new("Part")
    carrierHireSign.Name = "HireCarriersSign"
    carrierHireSign.Size = Vector3.new(6, 1.5, 0.3)
    carrierHireSign.Anchored = true
    carrierHireSign.Material = Enum.Material.Wood
    carrierHireSign.Color = Color3.fromRGB(110, 80, 55)
    carrierHireSign.CFrame = CFrame.lookAt(carrierSignPos, Vector3.new(baseX, carrierSignPos.Y, carrierSignPos.Z))
    carrierHireSign.Parent = farmModel

    local carrierHireSignGui = Instance.new("SurfaceGui")
    carrierHireSignGui.Face = Enum.NormalId.Back -- Text on front face (facing center)
    carrierHireSignGui.Parent = carrierHireSign

    local carrierHireSignLabel = Instance.new("TextLabel")
    carrierHireSignLabel.Size = UDim2.new(1, 0, 1, 0)
    carrierHireSignLabel.BackgroundTransparency = 1
    carrierHireSignLabel.Text = "HIRE CARRIERS"
    carrierHireSignLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    carrierHireSignLabel.TextScaled = true
    carrierHireSignLabel.Font = Enum.Font.GothamBold
    carrierHireSignLabel.Parent = carrierHireSignGui

    -- Store reference for updating later (like Gold Mine pattern)
    FarmState.carrierSign = carrierHireSignLabel
    makeSignDoubleSided(carrierHireSign)

    -- Table/counter in front of workers (player approaches from center)
    local carrierTable = Instance.new("Part")
    carrierTable.Name = "CarrierHiringTable"
    carrierTable.Size = Vector3.new(8, 1, 2)
    carrierTable.Anchored = true
    carrierTable.Material = Enum.Material.Wood
    carrierTable.Color = Color3.fromRGB(90, 65, 45)
    -- Table is in front of station (toward center)
    carrierTable.CFrame = carrierBoard.CFrame * CFrame.new(0, -1.5, -4)
    carrierTable.Parent = farmModel

    -- Table legs
    for i = -1, 1, 2 do
        for j = -1, 1, 2 do
            local leg = Instance.new("Part")
            leg.Name = "TableLeg"
            leg.Size = Vector3.new(0.3, 1, 0.3)
            leg.Anchored = true
            leg.Material = Enum.Material.Wood
            leg.Color = Color3.fromRGB(70, 50, 35)
            leg.CFrame = carrierTable.CFrame * CFrame.new(i * 3.5, -0.5, j * 0.7)
            leg.Parent = farmModel
        end
    end

    -- 3 Waiting carrier NPCs standing behind table (like Gold Mine pattern)
    FarmState.waitingCarriers = {}
    for i = 1, 3 do
        -- Workers behind table, spread along X axis: -3, 0, +3
        local waitingCarrierPos = hireCarrierPos + Vector3.new((i - 2) * 3, 0, 0)
        local waitingCarrier = createWorkerNPC(
            "WaitingCarrier" .. i,
            waitingCarrierPos,
            Color3.fromRGB(60, 100, 60), -- Darker green work clothes
            "Carrier"
        )
        setNPCStatus(waitingCarrier, "For hire!")
        waitingCarrier.Parent = farmModel
        table.insert(FarmState.waitingCarriers, waitingCarrier)
    end

    -- INTERACTION: Hire Carrier NPC (on the table, like Gold Mine)
    createInteraction(carrierTable, "Hire Carrier (900g + 180f)", "Hiring Table", 1, function(player)
        -- Check if any waiting workers left at the stand
        if #FarmState.waitingCarriers == 0 then
            print(string.format("[Farm] %s: No carriers available to hire!", player.Name))
            notifyPlayer(player, "HireWorker", false, "No carriers available to hire!")
            return
        end

        local carrierCount = #FarmState.carriers
        local maxCarriers = 3

        if carrierCount >= maxCarriers then
            print(string.format("[Farm] %s: Max carriers (3) reached!", player.Name))
            notifyPlayer(player, "HireWorker", false, "Max carriers (3) already hired!")
            return
        end

        local cost = CarrierCosts[carrierCount + 1]
        if not deductPlayerResources(player, {gold = cost.gold, food = cost.food}, "Farm") then
            notifyPlayer(player, "HireWorker", false, string.format("Need %dg + %df to hire!", cost.gold, cost.food))
            return
        end
        notifyPlayer(player, "HireWorker", true, "Carrier hired!")

        -- Remove one waiting worker from the stand (they walk away to work)
        local waitingWorker = table.remove(FarmState.waitingCarriers, 1)
        if waitingWorker then
            -- Make the waiting worker walk away before destroying
            local workerRoot = waitingWorker:FindFirstChild("HumanoidRootPart") or waitingWorker:FindFirstChild("Torso")
            if workerRoot then
                local walkAwayPos = FarmState.positions.workerSpawn + Vector3.new(carrierCount * 3 + 10, 0, 0)
                walkNPCTo(waitingWorker, walkAwayPos, 6, function()
                    _npcAnimTracks[waitingWorker] = nil
                    waitingWorker:Destroy()
                end)
            else
                _npcAnimTracks[waitingWorker] = nil
                waitingWorker:Destroy()
            end
        end

        -- Update sign if no more waiting workers
        if #FarmState.waitingCarriers == 0 then
            if FarmState.carrierSign then
                FarmState.carrierSign.Text = "FULLY STAFFED"
                FarmState.carrierSign.TextColor3 = Color3.fromRGB(150, 150, 150)
            end
        end
        local carrierId = carrierCount + 1

        -- Create visible carrier NPC at hiring booth (walks to work from there)
        local spawnPos = FarmState.positions.hireCarrier
        local carrier = createWorkerNPC(
            "Carrier " .. carrierId,
            spawnPos,
            Color3.fromRGB(60, 100, 60), -- Darker green work clothes
            "Carrier"
        )
        carrier.Parent = farmModel

        -- Store the hiring player for rewards
        local hiringPlayer = player

        local carrierData = {
            npc = carrier,
            state = "idle",
            carrying = 0,
            owner = player.UserId,
        }
        table.insert(FarmState.carriers, carrierData)

        -- Start carrier AI loop with async completion-flag pattern
        task.spawn(function()
            setNPCStatus(carrier, "Waiting for food...")

            while carrierData.npc and carrierData.npc.Parent do
                -- Get current carrier stats (updates each cycle based on upgrades)
                local carrierStats = getCarrierStats(FarmState.equipment.carrierLevel)
                local grainCapacity = carrierStats.grainCapacity
                local walkSpeed = carrierStats.walkSpeed

                -- Check if there is food ready at silo
                if FarmState.foodStorage >= 1 then
                    local cycleComplete = false

                    -- Walk to silo
                    carrierData.state = "walking_to_silo"
                    setNPCStatus(carrier, "Going to silo...")
                    walkNPCTo(carrier, FarmState.positions.foodStorage + Vector3.new(0, 0, 3), walkSpeed, function()
                        -- Pick up food
                        carrierData.state = "picking_up"
                        setNPCStatus(carrier, "Picking up food...")
                        task.wait(1)

                        local foodToCollect = math.min(FarmState.foodStorage, grainCapacity)
                        FarmState.foodStorage = FarmState.foodStorage - foodToCollect
                        carrierData.carrying = foodToCollect

                        -- Update silo visuals
                        if FarmState.updateFoodStorageVisuals then
                            FarmState.updateFoodStorageVisuals()
                        end

                        -- Update exterior stats billboard
                        if FarmState.updateExteriorStats then
                            FarmState.updateExteriorStats()
                        end

                        -- Visual: Add food bags to NPC
                        setNPCCarrying(carrier, "food", math.min(5, math.ceil(foodToCollect / 5)))
                        setNPCStatus(carrier, string.format("Carrying %d food", foodToCollect))

                        print(string.format("[Carrier #%d] Picked up %d food (Remaining: %d)",
                            carrierId, foodToCollect, FarmState.foodStorage))

                        -- Walk to storage shed (delivery point)
                        carrierData.state = "walking_to_storage"
                        setNPCStatus(carrier, "Delivering food...")
                        walkNPCTo(carrier, FarmState.positions.storageShed, walkSpeed, function()
                            -- Deliver food to chest
                            carrierData.state = "delivering"
                            setNPCStatus(carrier, "Delivering...")
                            task.wait(1)

                            local foodDelivered = carrierData.carrying

                            carrierData.carrying = 0
                            setNPCCarrying(carrier, nil, 0)

                            -- Delivery sparkle effect (green for food)
                            local torso = carrier:FindFirstChild("UpperTorso") or carrier:FindFirstChild("Torso")
                            if torso then
                                local sparkle = Instance.new("ParticleEmitter")
                                sparkle.Color = ColorSequence.new(Color3.fromRGB(150, 255, 150))
                                sparkle.Size = NumberSequence.new(0.4)
                                sparkle.Lifetime = NumberRange.new(0.5, 1)
                                sparkle.Rate = 30
                                sparkle.Speed = NumberRange.new(3, 6)
                                sparkle.SpreadAngle = Vector2.new(60, 60)
                                sparkle.Parent = torso
                                task.delay(0.6, function() sparkle:Destroy() end)
                            end

                            print(string.format("[Carrier #%d] Delivered %d food to storage!",
                                carrierId, foodDelivered))

                            -- Reward food to the player
                            rewardPlayer(hiringPlayer, "food", foodDelivered, "Carrier")

                            addFarmXP(15)

                            -- Return to silo
                            carrierData.state = "returning"
                            setNPCStatus(carrier, "Returning...")
                            cycleComplete = true
                        end)
                    end)

                    -- Wait for cycle to complete before starting next one
                    while not cycleComplete and carrierData.npc and carrierData.npc.Parent do
                        task.wait(0.5)
                    end
                else
                    -- No food, wait and check again
                    setNPCStatus(carrier, string.format("Waiting... (%d food)", FarmState.foodStorage))
                    task.wait(2)
                end
            end
        end)

        print(string.format("[Farm] %s hired Carrier #%d for %d gold + %d food!",
            player.Name, carrierId, cost.gold, cost.food))
        print(string.format("[Farm] Carrier #%d will collect food from silo -> deliver to storage -> repeat!", carrierId))

        -- Update production display (like Gold Mine pattern)
        if FarmState.updateFarmProduction then
            FarmState.updateFarmProduction()
        end
    end)

    -- ========== STEP 8: SINGLE UPGRADE KIOSK (front-right area) ==========
    -- REDESIGNED: Replaces the multiple pedestals with ONE kiosk that opens a menu GUI
    -- Kiosk faces toward center (left/toward baseX)
    local upgradeKioskPos = FarmState.positions.upgradeKiosk

    -- Kiosk pedestal/terminal - faces toward center
    local farmUpgradeKiosk = Instance.new("Part")
    farmUpgradeKiosk.Name = "FarmUpgradeKiosk"
    farmUpgradeKiosk.Size = Vector3.new(3, 4, 2)
    farmUpgradeKiosk.Anchored = true
    farmUpgradeKiosk.Material = Enum.Material.Metal
    farmUpgradeKiosk.Color = Color3.fromRGB(80, 100, 60) -- Green-ish metal
    -- Position and rotate to face center (toward baseX, i.e. left)
    local farmKioskCenterPos = upgradeKioskPos + Vector3.new(0, 2, 0)
    local farmKioskLookAt = Vector3.new(baseX, farmKioskCenterPos.Y, farmKioskCenterPos.Z)
    farmUpgradeKiosk.CFrame = CFrame.lookAt(farmKioskCenterPos, farmKioskLookAt)
    farmUpgradeKiosk.Parent = farmModel

    -- Kiosk screen (decorative) - positioned on the front face of kiosk (facing center)
    local farmKioskScreen = Instance.new("Part")
    farmKioskScreen.Name = "KioskScreen"
    farmKioskScreen.Size = Vector3.new(2.5, 2, 0.2)
    farmKioskScreen.Anchored = true
    farmKioskScreen.Material = Enum.Material.Neon
    farmKioskScreen.Color = Color3.fromRGB(100, 200, 100) -- Green glow
    -- Screen is on the front of kiosk, which now faces center
    local farmScreenCFrame = farmUpgradeKiosk.CFrame * CFrame.new(0, 1, -1.1)
    farmKioskScreen.CFrame = farmScreenCFrame
    farmKioskScreen.Parent = farmModel

    -- Glow effect
    local farmKioskGlow = Instance.new("PointLight")
    farmKioskGlow.Color = Color3.fromRGB(150, 220, 100)
    farmKioskGlow.Brightness = 1.5
    farmKioskGlow.Range = 8
    farmKioskGlow.Parent = farmKioskScreen

    -- Sign above kiosk - faces toward center
    local farmKioskSignPos = upgradeKioskPos + Vector3.new(0, 5, 0)
    local farmKioskSign = Instance.new("Part")
    farmKioskSign.Name = "FarmUpgradeKioskSign"
    farmKioskSign.Size = Vector3.new(6, 1.2, 0.3)
    farmKioskSign.Anchored = true
    farmKioskSign.Material = Enum.Material.Wood
    farmKioskSign.Color = Color3.fromRGB(110, 80, 55)
    farmKioskSign.CFrame = CFrame.lookAt(farmKioskSignPos, Vector3.new(baseX, farmKioskSignPos.Y, farmKioskSignPos.Z))
    farmKioskSign.Parent = farmModel

    local farmKioskSignGui = Instance.new("SurfaceGui")
    farmKioskSignGui.Face = Enum.NormalId.Back -- Text on front face (facing center)
    farmKioskSignGui.Parent = farmKioskSign

    local farmKioskSignLabel = Instance.new("TextLabel")
    farmKioskSignLabel.Size = UDim2.new(1, 0, 1, 0)
    farmKioskSignLabel.BackgroundTransparency = 1
    farmKioskSignLabel.Text = "UPGRADE KIOSK"
    farmKioskSignLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    farmKioskSignLabel.TextScaled = true
    farmKioskSignLabel.Font = Enum.Font.GothamBold
    farmKioskSignLabel.Parent = farmKioskSignGui
    makeSignDoubleSided(farmKioskSign)

    -- Small billboard showing quick stats
    local farmKioskBillboard = Instance.new("BillboardGui")
    farmKioskBillboard.Name = "KioskPreview"
    farmKioskBillboard.Size = UDim2.new(6, 0, 2, 0)
    farmKioskBillboard.StudsOffset = Vector3.new(0, 3, 2)
    farmKioskBillboard.AlwaysOnTop = true
    farmKioskBillboard.Parent = farmUpgradeKiosk

    local farmPreviewLabel = Instance.new("TextLabel")
    farmPreviewLabel.Size = UDim2.new(1, 0, 1, 0)
    farmPreviewLabel.BackgroundTransparency = 1
    farmPreviewLabel.Text = "Press E to Open Upgrades"
    farmPreviewLabel.TextColor3 = Color3.fromRGB(200, 220, 150)
    farmPreviewLabel.TextStrokeTransparency = 0.3
    farmPreviewLabel.TextScaled = true
    farmPreviewLabel.Font = Enum.Font.Gotham
    farmPreviewLabel.Parent = farmKioskBillboard

    -- Track active farm upgrade GUIs per player
    local activeFarmUpgradeGuis = {}

    -- Function to create the farm upgrade GUI for a player
    local function createFarmUpgradeGui(player)
        -- Remove existing GUI if any
        if activeFarmUpgradeGuis[player.UserId] then
            activeFarmUpgradeGuis[player.UserId]:Destroy()
            activeFarmUpgradeGuis[player.UserId] = nil
        end

        local playerGui = player:FindFirstChild("PlayerGui")
        if not playerGui then return end

        -- Create ScreenGui
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "FarmUpgradeMenu"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = playerGui
        activeFarmUpgradeGuis[player.UserId] = screenGui

        -- Main frame (slightly taller for 5 upgrades)
        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = UDim2.new(0, 450, 0, 650)
        mainFrame.Position = UDim2.new(0.5, -225, 0.5, -325)
        mainFrame.BackgroundColor3 = Color3.fromRGB(30, 40, 25)
        mainFrame.BorderSizePixel = 3
        mainFrame.BorderColor3 = Color3.fromRGB(150, 200, 100)
        mainFrame.Parent = screenGui

        -- Title
        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 50)
        title.Position = UDim2.new(0, 0, 0, 0)
        title.BackgroundColor3 = Color3.fromRGB(50, 60, 40)
        title.BorderSizePixel = 0
        title.Text = "FARM UPGRADES"
        title.TextColor3 = Color3.fromRGB(200, 230, 100)
        title.TextScaled = true
        title.Font = Enum.Font.GothamBold
        title.Parent = mainFrame

        -- Function to create an upgrade card
        local function createFarmUpgradeCard(yOffset, upgradeType, getStats, currentLevel, color)
            local stats = getStats(currentLevel)
            local nextStats = getStats(currentLevel + 1)

            local card = Instance.new("Frame")
            card.Name = upgradeType .. "Card"
            card.Size = UDim2.new(0.95, 0, 0, 100)
            card.Position = UDim2.new(0.025, 0, 0, yOffset)
            card.BackgroundColor3 = Color3.fromRGB(45, 55, 40)
            card.BorderSizePixel = 2
            card.BorderColor3 = color
            card.Parent = mainFrame

            local cardTitle = Instance.new("TextLabel")
            cardTitle.Size = UDim2.new(0.6, 0, 0, 30)
            cardTitle.Position = UDim2.new(0.02, 0, 0, 5)
            cardTitle.BackgroundTransparency = 1
            cardTitle.Text = string.format("%s  Lv.%d", upgradeType:upper(), currentLevel)
            cardTitle.TextColor3 = color
            cardTitle.TextXAlignment = Enum.TextXAlignment.Left
            cardTitle.TextScaled = true
            cardTitle.Font = Enum.Font.GothamBold
            cardTitle.Parent = card

            local statsText = ""
            if upgradeType == "Hoe" then
                statsText = string.format("Crops/Harvest: %d -> %d", stats.cropsPerAction, nextStats.cropsPerAction)
            elseif upgradeType == "Watering Can" then
                statsText = string.format("Plots/Water: %d -> %d", stats.plotsPerWater, nextStats.plotsPerWater)
            elseif upgradeType == "Windmill" then
                statsText = string.format("Grain/Crop: %d -> %d | Speed: %.1fs", stats.grainPerCrop, nextStats.grainPerCrop, nextStats.processTime)
            elseif upgradeType == "Farmers" then
                statsText = string.format("Capacity: %d -> %d crops | Speed: %d -> %d", stats.cropCapacity, nextStats.cropCapacity, stats.walkSpeed, nextStats.walkSpeed)
            elseif upgradeType == "Carriers" then
                statsText = string.format("Capacity: %d -> %d food | Speed: %d -> %d", stats.grainCapacity, nextStats.grainCapacity, stats.walkSpeed, nextStats.walkSpeed)
            end

            local statsLabel = Instance.new("TextLabel")
            statsLabel.Size = UDim2.new(0.96, 0, 0, 25)
            statsLabel.Position = UDim2.new(0.02, 0, 0, 35)
            statsLabel.BackgroundTransparency = 1
            statsLabel.Text = statsText
            statsLabel.TextColor3 = Color3.fromRGB(180, 200, 160)
            statsLabel.TextXAlignment = Enum.TextXAlignment.Left
            statsLabel.TextScaled = true
            statsLabel.Font = Enum.Font.Gotham
            statsLabel.Parent = card

            local upgradeButton = Instance.new("TextButton")
            upgradeButton.Name = "UpgradeButton"
            upgradeButton.Size = UDim2.new(0.96, 0, 0, 30)
            upgradeButton.Position = UDim2.new(0.02, 0, 0, 65)
            upgradeButton.BackgroundColor3 = Color3.fromRGB(80, 150, 80)
            upgradeButton.BorderSizePixel = 0
            upgradeButton.Text = string.format("UPGRADE - %d gold", nextStats.upgradeCost)
            upgradeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            upgradeButton.TextScaled = true
            upgradeButton.Font = Enum.Font.GothamBold
            upgradeButton.Parent = card

            return upgradeButton
        end

        -- Create cards for each upgrade type (5 cards for Farm)
        local hoeBtn = createFarmUpgradeCard(60, "Hoe", getHoeStats, FarmState.equipment.hoeLevel, Color3.fromRGB(139, 90, 43))
        local waterCanBtn = createFarmUpgradeCard(170, "Watering Can", getWateringCanStats, FarmState.equipment.wateringCanLevel, Color3.fromRGB(80, 150, 200))
        local windmillBtn = createFarmUpgradeCard(280, "Windmill", getWindmillStatsFunc, FarmState.equipment.windmillLevel, Color3.fromRGB(220, 200, 100))
        local farmersBtn = createFarmUpgradeCard(390, "Farmers", getFarmerStats, FarmState.equipment.farmerLevel, Color3.fromRGB(100, 140, 100))
        local carriersBtn = createFarmUpgradeCard(500, "Carriers", getCarrierStats, FarmState.equipment.carrierLevel, Color3.fromRGB(60, 100, 60))

        -- Close button
        local closeButton = Instance.new("TextButton")
        closeButton.Name = "CloseButton"
        closeButton.Size = UDim2.new(0.5, 0, 0, 40)
        closeButton.Position = UDim2.new(0.25, 0, 0, 605)
        closeButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        closeButton.BorderSizePixel = 0
        closeButton.Text = "CLOSE"
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeButton.TextScaled = true
        closeButton.Font = Enum.Font.GothamBold
        closeButton.Parent = mainFrame

        -- Button handlers
        hoeBtn.MouseButton1Click:Connect(function()
            local currentLevel = FarmState.equipment.hoeLevel
            local nextStats = getHoeStats(currentLevel + 1)
            if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "Farm") then return end
            FarmState.equipment.hoeLevel = currentLevel + 1
            addFarmXP(50)
            print(string.format("[Upgrade] %s upgraded Hoe to Lv%d! Now %d crops/harvest (-%d gold)",
                player.Name, currentLevel + 1, nextStats.cropsPerAction, nextStats.upgradeCost))
            -- Refresh GUI
            createFarmUpgradeGui(player)
        end)

        waterCanBtn.MouseButton1Click:Connect(function()
            local currentLevel = FarmState.equipment.wateringCanLevel
            local nextStats = getWateringCanStats(currentLevel + 1)
            if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "Farm") then return end
            FarmState.equipment.wateringCanLevel = currentLevel + 1
            addFarmXP(50)
            print(string.format("[Upgrade] %s upgraded Watering Can to Lv%d! Now %d plots/water (-%d gold)",
                player.Name, currentLevel + 1, nextStats.plotsPerWater, nextStats.upgradeCost))
            createFarmUpgradeGui(player)
        end)

        windmillBtn.MouseButton1Click:Connect(function()
            local currentLevel = FarmState.equipment.windmillLevel
            local nextStats = getWindmillStatsFunc(currentLevel + 1)
            if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "Farm") then return end
            FarmState.equipment.windmillLevel = currentLevel + 1
            addFarmXP(50)
            print(string.format("[Upgrade] %s upgraded Windmill to Lv%d! Now %d grain/crop, %.1fs (-%d gold)",
                player.Name, currentLevel + 1, nextStats.grainPerCrop, nextStats.processTime, nextStats.upgradeCost))
            createFarmUpgradeGui(player)
        end)

        farmersBtn.MouseButton1Click:Connect(function()
            local currentLevel = FarmState.equipment.farmerLevel
            local nextStats = getFarmerStats(currentLevel + 1)
            if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "Farm") then return end
            FarmState.equipment.farmerLevel = currentLevel + 1
            addFarmXP(50)
            print(string.format("[Upgrade] %s upgraded Farmers to Lv%d! Now %d crop capacity (-%d gold)",
                player.Name, currentLevel + 1, nextStats.cropCapacity, nextStats.upgradeCost))
            createFarmUpgradeGui(player)
        end)

        carriersBtn.MouseButton1Click:Connect(function()
            local currentLevel = FarmState.equipment.carrierLevel
            local nextStats = getCarrierStats(currentLevel + 1)
            if not deductPlayerResources(player, {gold = nextStats.upgradeCost}, "Farm") then return end
            FarmState.equipment.carrierLevel = currentLevel + 1
            addFarmXP(50)
            print(string.format("[Upgrade] %s upgraded Carriers to Lv%d! Now %d food capacity (-%d gold)",
                player.Name, currentLevel + 1, nextStats.grainCapacity, nextStats.upgradeCost))
            createFarmUpgradeGui(player)
        end)

        closeButton.MouseButton1Click:Connect(function()
            screenGui:Destroy()
            activeFarmUpgradeGuis[player.UserId] = nil
        end)
    end

    -- Cleanup GUI when player leaves
    Players.PlayerRemoving:Connect(function(player)
        if activeFarmUpgradeGuis[player.UserId] then
            activeFarmUpgradeGuis[player.UserId]:Destroy()
            activeFarmUpgradeGuis[player.UserId] = nil
        end
    end)

    -- INTERACTION: Open Upgrade Menu (single kiosk)
    createInteraction(farmUpgradeKiosk, "Open Upgrades", "Upgrade Kiosk", 2, function(player)
        createFarmUpgradeGui(player)
        print(string.format("[Farm] %s opened Upgrade Menu", player.Name))
    end)

    -- ===== FARM DECORATIVE ENHANCEMENTS =====
    -- Scarecrow in crop field area
    local scarecrowPos = Vector3.new(baseX - 15, GROUND_Y, baseZ - 10)
    -- Post
    local scPost = Instance.new("Part")
    scPost.Name = "ScarecrowPost"
    scPost.Size = Vector3.new(0.4, 5, 0.4)
    scPost.Position = scarecrowPos + Vector3.new(0, 2.5, 0)
    scPost.Anchored = true
    scPost.Material = Enum.Material.Wood
    scPost.Color = Color3.fromRGB(80, 55, 35)
    scPost.CanCollide = false
    scPost.Parent = farmModel

    -- Crossbar (arms)
    local scArms = Instance.new("Part")
    scArms.Name = "ScarecrowArms"
    scArms.Size = Vector3.new(3, 0.3, 0.3)
    scArms.Position = scarecrowPos + Vector3.new(0, 4, 0)
    scArms.Anchored = true
    scArms.Material = Enum.Material.Wood
    scArms.Color = Color3.fromRGB(80, 55, 35)
    scArms.CanCollide = false
    scArms.Parent = farmModel

    -- Head (sack)
    local scHead = Instance.new("Part")
    scHead.Name = "ScarecrowHead"
    scHead.Shape = Enum.PartType.Ball
    scHead.Size = Vector3.new(1, 1, 1)
    scHead.Position = scarecrowPos + Vector3.new(0, 5.2, 0)
    scHead.Anchored = true
    scHead.Material = Enum.Material.Fabric
    scHead.Color = Color3.fromRGB(200, 175, 130)
    scHead.CanCollide = false
    scHead.Parent = farmModel

    -- Hat
    local scHat = Instance.new("Part")
    scHat.Name = "ScarecrowHat"
    scHat.Shape = Enum.PartType.Cylinder
    scHat.Size = Vector3.new(0.5, 1.5, 1.5)
    scHat.Position = scarecrowPos + Vector3.new(0, 5.8, 0)
    scHat.Anchored = true
    scHat.Material = Enum.Material.Fabric
    scHat.Color = Color3.fromRGB(120, 90, 50)
    scHat.CanCollide = false
    scHat.Parent = farmModel

    -- Water trough near storage
    local troughPos = Vector3.new(baseX + 20, GROUND_Y, baseZ + 15)
    local trough = Instance.new("Part")
    trough.Name = "WaterTrough"
    trough.Size = Vector3.new(4, 1, 1.5)
    trough.Position = troughPos + Vector3.new(0, 0.5, 0)
    trough.Anchored = true
    trough.Material = Enum.Material.Wood
    trough.Color = Color3.fromRGB(90, 65, 40)
    trough.CanCollide = false
    trough.Parent = farmModel

    local troughWater = Instance.new("Part")
    troughWater.Name = "TroughWater"
    troughWater.Size = Vector3.new(3.5, 0.3, 1)
    troughWater.Position = troughPos + Vector3.new(0, 0.8, 0)
    troughWater.Anchored = true
    troughWater.Material = Enum.Material.Glass
    troughWater.Color = Color3.fromRGB(70, 130, 190)
    troughWater.Transparency = 0.3
    troughWater.CanCollide = false
    troughWater.Parent = farmModel

    -- Flour sacks near mill station (round sack shapes)
    for si = 1, 3 do
        local sack = Instance.new("Part")
        sack.Name = "FlourSack" .. si
        sack.Size = Vector3.new(1, 1.2, 0.8)
        sack.Position = Vector3.new(baseX + 30 + (si - 2) * 1.5, GROUND_Y + 0.6, baseZ - 18)
        sack.Anchored = true
        sack.Material = Enum.Material.Fabric
        sack.Color = Color3.fromRGB(220, 210, 190)
        sack.CanCollide = false
        sack.Parent = farmModel

        local sackMesh = Instance.new("SpecialMesh")
        sackMesh.MeshType = Enum.MeshType.Sphere
        sackMesh.Scale = Vector3.new(1, 1.3, 0.9)
        sackMesh.Parent = sack

        -- Rope tie on top
        local ropeTie = Instance.new("Part")
        ropeTie.Name = "SackRope" .. si
        ropeTie.Size = Vector3.new(0.6, 0.15, 0.6)
        ropeTie.Position = Vector3.new(baseX + 30 + (si - 2) * 1.5, GROUND_Y + 1.3, baseZ - 18)
        ropeTie.Anchored = true
        ropeTie.Material = Enum.Material.Fabric
        ropeTie.Color = Color3.fromRGB(150, 130, 90)
        ropeTie.CanCollide = false
        ropeTie.Parent = farmModel
    end

    -- Parent the farm interior
    farmModel.Parent = interiorsFolder
    currentFarmState.model = farmModel

    print(string.format("  ✓ %s created (REDESIGNED LAYOUT):", farmName))
    print("    - Crop fields on BOTH sides (24 plots total)")
    print("    - Single upgrade kiosk with menu UI")
    print("    - Full progression: Seeds → Plant → Water → Harvest → Process → Collect")
    print("    - Production stats displayed on exterior sign")
end

-- ============================================================================
-- BARRACKS - Army Training System
-- ============================================================================
-- STATIONS:
--   1. TRAINING STATION: Queue troops for training (Soldier, Archer, Catapult)
--   2. RESEARCH STATION: Unlock new troop types (Archer, then Catapult)
--   3. QUEUE EXPANSION: Buy additional training queue slots (2 default, 5 max)
--   4. ARMY DISPLAY: View your current army composition
-- ============================================================================

-- Troop definitions for Army Training System
local BarracksTroopTypes = {
    Soldier = {
        displayName = "Soldier",
        description = "Melee fighter with heavy armor",
        costs = { gold = 150, food = 50 },
        trainTime = 30,
        foodUpkeep = 2,
        researchCost = nil,
        researchTime = 0,
        prereq = nil,
        color = Color3.fromRGB(140, 140, 150),
    },
    Archer = {
        displayName = "Archer",
        description = "Ranged unit with bows",
        costs = { gold = 50, wood = 150, food = 30 },
        trainTime = 25,
        foodUpkeep = 1,
        researchCost = { gold = 500, wood = 300 },
        researchTime = 60,
        prereq = nil,
        color = Color3.fromRGB(100, 140, 90),
    },
    Catapult = {
        displayName = "Catapult",
        description = "Siege weapon for breaking defenses",
        costs = { gold = 200, wood = 300 },
        trainTime = 120,
        foodUpkeep = 5,
        researchCost = { gold = 1000, wood = 500, food = 200 },
        researchTime = 120,
        prereq = "Archer",
        color = Color3.fromRGB(100, 70, 45),
    },
}

-- Ordered list for consistent iteration
local BarracksTroopOrder = { "Soldier", "Archer", "Catapult" }

local QueueSlotCosts = { [3] = 500, [4] = 1500, [5] = 4000 }

-- Barracks state
local BarracksState = {
    level = 1,
    xp = 0,
    xpToNextLevel = 100,
    trainingQueues = {},   -- [userId] = { {troopType, startTime, completesAt}, ... }
    queueSlots = {},       -- [userId] = number (default 2, max 5)
    researched = {},       -- [userId] = { Soldier=true, Archer=false, Catapult=false }
    activeResearch = {},   -- [userId] = { troopType, startTime, completesAt } or nil
    positions = {},
    -- Visual update callbacks (set during creation)
    updateQueueVisuals = nil,
    updateResearchVisuals = nil,
}

-- Active barracks GUIs per player
local activeBarracksGuis = {} -- [userId] = ScreenGui

-- Add XP to barracks and handle leveling
local function addBarracksXP(amount: number)
    BarracksState.xp = BarracksState.xp + amount
    while BarracksState.xp >= BarracksState.xpToNextLevel do
        BarracksState.xp = BarracksState.xp - BarracksState.xpToNextLevel
        BarracksState.level = BarracksState.level + 1
        BarracksState.xpToNextLevel = math.floor(BarracksState.xpToNextLevel * 1.5)
        print(string.format("[Barracks] LEVEL UP! Now level %d", BarracksState.level))
    end
end

-- Initialize barracks data for a player
local function initPlayerBarracksData(player: Player)
    local uid = player.UserId
    if not BarracksState.queueSlots[uid] then
        BarracksState.queueSlots[uid] = 2
    end
    if not BarracksState.trainingQueues[uid] then
        BarracksState.trainingQueues[uid] = {}
    end
    if not BarracksState.researched[uid] then
        BarracksState.researched[uid] = { Soldier = true, Archer = false, Catapult = false }
    end
end

-- Format time remaining as MM:SS
local function formatTimeRemaining(seconds: number): string
    if seconds <= 0 then return "Done!" end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    if m > 0 then
        return string.format("%dm %02ds", m, s)
    end
    return string.format("%ds", s)
end

-- Add a troop to the training queue
local function addToTrainingQueue(player: Player, troopType: string): boolean
    local uid = player.UserId
    initPlayerBarracksData(player)

    local troopDef = BarracksTroopTypes[troopType]
    if not troopDef then return false end

    -- Check troop is researched
    if not BarracksState.researched[uid][troopType] then
        notifyPlayer(player, "BarracksTrain", false, troopDef.displayName .. " not yet researched!")
        return false
    end

    -- Check queue capacity
    local queue = BarracksState.trainingQueues[uid]
    local maxSlots = BarracksState.queueSlots[uid]
    if #queue >= maxSlots then
        notifyPlayer(player, "BarracksTrain", false, "Training queue full! (" .. #queue .. "/" .. maxSlots .. ")")
        return false
    end

    -- Check food supply
    if DataService then
        local playerData = DataService:GetPlayerData(player)
        if playerData and playerData.trainingPaused then
            notifyPlayer(player, "BarracksTrain", false, "Food supply too low! Build more farms.")
            return false
        end
    end

    -- Deduct resources
    if not deductPlayerResources(player, troopDef.costs, "Barracks") then return false end

    -- Calculate start time (chains after last queue item)
    local now = os.time()
    local startTime = now
    if #queue > 0 then
        local lastItem = queue[#queue]
        startTime = math.max(now, lastItem.completesAt)
    end
    local completesAt = startTime + troopDef.trainTime

    table.insert(queue, {
        troopType = troopType,
        startTime = startTime,
        completesAt = completesAt,
    })

    notifyPlayer(player, "BarracksTrain", true,
        "Training " .. troopDef.displayName .. "! Ready in " .. formatTimeRemaining(completesAt - now))
    addBarracksXP(5)

    if BarracksState.updateQueueVisuals then
        BarracksState.updateQueueVisuals(player)
    end

    return true
end

-- Start researching a troop type
local function startResearch(player: Player, troopType: string): boolean
    local uid = player.UserId
    initPlayerBarracksData(player)

    local troopDef = BarracksTroopTypes[troopType]
    if not troopDef then return false end

    -- Check not already researched
    if BarracksState.researched[uid][troopType] then
        notifyPlayer(player, "BarracksResearch", false, troopDef.displayName .. " already researched!")
        return false
    end

    -- Check not already researching something
    if BarracksState.activeResearch[uid] then
        notifyPlayer(player, "BarracksResearch", false, "Already researching! Wait for current research to finish.")
        return false
    end

    -- Check prereq
    if troopDef.prereq and not BarracksState.researched[uid][troopDef.prereq] then
        local prereqName = BarracksTroopTypes[troopDef.prereq].displayName
        notifyPlayer(player, "BarracksResearch", false, "Research " .. prereqName .. " first!")
        return false
    end

    -- Check research cost exists
    if not troopDef.researchCost then return false end

    -- Deduct resources
    if not deductPlayerResources(player, troopDef.researchCost, "Barracks") then return false end

    local now = os.time()
    BarracksState.activeResearch[uid] = {
        troopType = troopType,
        startTime = now,
        completesAt = now + troopDef.researchTime,
    }

    notifyPlayer(player, "BarracksResearch", true,
        "Researching " .. troopDef.displayName .. "! " .. formatTimeRemaining(troopDef.researchTime))
    addBarracksXP(10)

    return true
end

-- Buy an additional queue slot
local function buyQueueSlot(player: Player): boolean
    local uid = player.UserId
    initPlayerBarracksData(player)

    local currentSlots = BarracksState.queueSlots[uid]
    if currentSlots >= 5 then
        notifyPlayer(player, "BarracksSlot", false, "Already at maximum queue slots (5)!")
        return false
    end

    local nextSlot = currentSlots + 1
    local cost = QueueSlotCosts[nextSlot]
    if not cost then return false end

    if not deductPlayerResources(player, { gold = cost }, "Barracks") then return false end

    BarracksState.queueSlots[uid] = nextSlot
    notifyPlayer(player, "BarracksSlot", true, "Queue expanded to " .. nextSlot .. " slots!")
    addBarracksXP(15)
    return true
end

local function createBarracks()
    print("[6/8] Creating Barracks with full progression loop...")

    -- ========== EXTERIOR IN VILLAGE ==========
    -- Right side of path, faces west toward main road
    local exteriorX, exteriorZ = 95, 100

    -- Create exterior building shell
    createBuildingExterior(
        "BARRACKS",
        Vector3.new(exteriorX, GROUND_Y, exteriorZ),
        Vector3.new(18, 10, 16),
        Color3.fromRGB(80, 75, 70), -- Dark stone roof
        Color3.fromRGB(100, 90, 85), -- Cobblestone walls
        "Barracks",
        "west" -- Entrance faces the main path
    )

    -- ========== MILITARY TRAINING GROUNDS INTERIOR ==========
    local basePos = INTERIOR_POSITIONS.Barracks
    local barracksModel = Instance.new("Model")
    barracksModel.Name = "Barracks_Interior"

    local baseX, baseZ = basePos.X, basePos.Z
    local GROUND_Y = basePos.Y

    -- Store positions for workers
    BarracksState.positions = {
        recruitBoard = Vector3.new(baseX - 35, GROUND_Y, baseZ - 25),
        trainingYard = Vector3.new(baseX, GROUND_Y, baseZ),
        armory = Vector3.new(baseX + 35, GROUND_Y, baseZ - 20),
        armyCamp = Vector3.new(baseX + 35, GROUND_Y, baseZ + 20),
        workerSpawn = Vector3.new(baseX - 30, GROUND_Y, baseZ + 30),
    }

    -- ===== SAND TRAINING ARENA FLOOR =====
    local arenaFloor = Instance.new("Part")
    arenaFloor.Name = "TrainingArenaFloor"
    arenaFloor.Size = Vector3.new(120, 2, 90)
    arenaFloor.Position = Vector3.new(baseX, GROUND_Y - 1, baseZ)
    arenaFloor.Anchored = true
    arenaFloor.Material = Enum.Material.Sand
    arenaFloor.Color = Color3.fromRGB(180, 160, 120)
    arenaFloor.Parent = barracksModel

    -- Central training pit (darker sand)
    local trainingPit = Instance.new("Part")
    trainingPit.Name = "TrainingPit"
    trainingPit.Size = Vector3.new(40, 0.3, 40)
    trainingPit.Position = Vector3.new(baseX, GROUND_Y + 0.2, baseZ)
    trainingPit.Anchored = true
    trainingPit.Material = Enum.Material.Sand
    trainingPit.Color = Color3.fromRGB(150, 130, 95)
    trainingPit.Parent = barracksModel

    -- ===== STONE WALLS (military fortress style) =====
    local wallHeight = 15
    local wallColor = Color3.fromRGB(90, 85, 80)
    local wallPositions = {
        { pos = Vector3.new(baseX, GROUND_Y + wallHeight/2, baseZ - 43), size = Vector3.new(118, wallHeight, 3) }, -- Back
        { pos = Vector3.new(baseX - 58, GROUND_Y + wallHeight/2, baseZ), size = Vector3.new(3, wallHeight, 86) }, -- Left
        { pos = Vector3.new(baseX + 58, GROUND_Y + wallHeight/2, baseZ), size = Vector3.new(3, wallHeight, 86) }, -- Right
    }
    for i, w in ipairs(wallPositions) do
        local wall = Instance.new("Part")
        wall.Name = "FortressWall" .. i
        wall.Size = w.size
        wall.Position = w.pos
        wall.Anchored = true
        wall.Material = Enum.Material.Cobblestone
        wall.Color = wallColor
        wall.Parent = barracksModel
    end

    -- Front wall with gate opening
    local frontWallLeft = Instance.new("Part")
    frontWallLeft.Size = Vector3.new(50, wallHeight, 3)
    frontWallLeft.Position = Vector3.new(baseX - 34, GROUND_Y + wallHeight/2, baseZ + 43)
    frontWallLeft.Anchored = true
    frontWallLeft.Material = Enum.Material.Cobblestone
    frontWallLeft.Color = wallColor
    frontWallLeft.Parent = barracksModel

    local frontWallRight = Instance.new("Part")
    frontWallRight.Size = Vector3.new(50, wallHeight, 3)
    frontWallRight.Position = Vector3.new(baseX + 34, GROUND_Y + wallHeight/2, baseZ + 43)
    frontWallRight.Anchored = true
    frontWallRight.Material = Enum.Material.Cobblestone
    frontWallRight.Color = wallColor
    frontWallRight.Parent = barracksModel

    -- Gate arch
    local gateArch = Instance.new("Part")
    gateArch.Size = Vector3.new(18, 4, 3)
    gateArch.Position = Vector3.new(baseX, GROUND_Y + wallHeight - 2, baseZ + 43)
    gateArch.Anchored = true
    gateArch.Material = Enum.Material.Cobblestone
    gateArch.Color = Color3.fromRGB(70, 65, 60)
    gateArch.Parent = barracksModel

    -- ===== MILITARY BANNERS =====
    local bannerColors = {
        Color3.fromRGB(180, 50, 50),  -- Red
        Color3.fromRGB(50, 50, 150),  -- Blue
        Color3.fromRGB(180, 150, 50), -- Gold
    }
    for i = 1, 6 do
        local banner = Instance.new("Part")
        banner.Name = "MilitaryBanner" .. i
        banner.Size = Vector3.new(0.3, 10, 5)
        banner.Position = Vector3.new(baseX - 50 + i * 16, GROUND_Y + 12, baseZ - 41)
        banner.Anchored = true
        banner.Material = Enum.Material.Fabric
        banner.Color = bannerColors[(i - 1) % 3 + 1]
        banner.Parent = barracksModel
    end

    -- ===== TORCH PILLARS =====
    local torchPositions = {
        Vector3.new(baseX - 25, GROUND_Y, baseZ - 25),
        Vector3.new(baseX + 25, GROUND_Y, baseZ - 25),
        Vector3.new(baseX - 25, GROUND_Y, baseZ + 25),
        Vector3.new(baseX + 25, GROUND_Y, baseZ + 25),
    }
    for i, tPos in ipairs(torchPositions) do
        local pillar = Instance.new("Part")
        pillar.Size = Vector3.new(2, 8, 2)
        pillar.Position = tPos + Vector3.new(0, 4, 0)
        pillar.Anchored = true
        pillar.Material = Enum.Material.Cobblestone
        pillar.Color = Color3.fromRGB(100, 95, 90)
        pillar.Parent = barracksModel

        local brazier = Instance.new("Part")
        brazier.Size = Vector3.new(3, 1.5, 3)
        brazier.Position = tPos + Vector3.new(0, 8.5, 0)
        brazier.Anchored = true
        brazier.Material = Enum.Material.Metal
        brazier.Color = Color3.fromRGB(50, 45, 40)
        brazier.Parent = barracksModel

        local fire = Instance.new("Fire")
        fire.Size = 4
        fire.Heat = 5
        fire.Parent = brazier

        local light = Instance.new("PointLight")
        light.Brightness = 1.5
        light.Range = 25
        light.Color = Color3.fromRGB(255, 180, 80)
        light.Parent = brazier
    end

    -- ===== CEILING (stone fortress roof) =====
    local ceiling = Instance.new("Part")
    ceiling.Name = "FortressCeiling"
    ceiling.Size = Vector3.new(120, 2, 90)
    ceiling.Position = Vector3.new(baseX, GROUND_Y + wallHeight + 1, baseZ)
    ceiling.Anchored = true
    ceiling.Material = Enum.Material.Slate
    ceiling.Color = Color3.fromRGB(70, 65, 60)
    ceiling.Parent = barracksModel

    -- ===== EXIT PORTAL =====
    createExitPortal(barracksModel, Vector3.new(baseX, GROUND_Y + 4, baseZ + 40))

    -- ========== DECORATIONS ==========
    -- Weapon racks on walls
    for i = 1, 3 do
        local rack = Instance.new("Part")
        rack.Name = "WeaponRack" .. i
        rack.Size = Vector3.new(6, 4, 0.5)
        rack.Position = Vector3.new(baseX + 55, GROUND_Y + 4, baseZ - 30 + i * 18)
        rack.Anchored = true
        rack.Material = Enum.Material.Wood
        rack.Color = Color3.fromRGB(90, 60, 40)
        rack.Parent = barracksModel

        -- Swords on rack
        for j = 1, 3 do
            local sword = Instance.new("Part")
            sword.Size = Vector3.new(0.2, 3, 0.4)
            sword.Position = Vector3.new(baseX + 55.5, GROUND_Y + 4, baseZ - 32 + i * 18 + j * 1.5)
            sword.Orientation = Vector3.new(0, 0, 15)
            sword.Anchored = true
            sword.Material = Enum.Material.Metal
            sword.Color = Color3.fromRGB(180, 180, 190)
            sword.Parent = barracksModel
        end
    end

    -- ========================================================================
    -- STATION 1: TRAINING STATION (center of arena)
    -- ========================================================================
    local trainingTable = Instance.new("Part")
    trainingTable.Name = "TrainingTable"
    trainingTable.Size = Vector3.new(6, 3, 4)
    trainingTable.Position = Vector3.new(baseX, GROUND_Y + 1.5, baseZ + 5)
    trainingTable.Anchored = true
    trainingTable.Material = Enum.Material.Wood
    trainingTable.Color = Color3.fromRGB(100, 70, 45)
    trainingTable.Parent = barracksModel

    -- Training board (map on table)
    local trainingBoard = Instance.new("Part")
    trainingBoard.Name = "TrainingBoard"
    trainingBoard.Size = Vector3.new(4, 3, 0.3)
    trainingBoard.Position = Vector3.new(baseX, GROUND_Y + 4.5, baseZ + 7)
    trainingBoard.Anchored = true
    trainingBoard.Material = Enum.Material.Wood
    trainingBoard.Color = Color3.fromRGB(80, 55, 35)
    trainingBoard.Parent = barracksModel

    createSign(barracksModel, "TRAINING STATION", Vector3.new(baseX, GROUND_Y + 7, baseZ + 7), Vector3.new(6, 1, 0.3))

    -- Visual queue slots (5 max, body+head pairs colored by troop type)
    local queueSlotParts = {}
    for i = 1, 5 do
        local slotBody = Instance.new("Part")
        slotBody.Name = "QueueSlot" .. i
        slotBody.Size = Vector3.new(1, 2.5, 0.8)
        slotBody.Position = Vector3.new(baseX - 6 + (i - 1) * 2.5, GROUND_Y + 1.25, baseZ + 2)
        slotBody.Anchored = true
        slotBody.Material = Enum.Material.Metal
        slotBody.Color = Color3.fromRGB(140, 140, 150)
        slotBody.Transparency = 1
        slotBody.Parent = barracksModel

        local slotHead = Instance.new("Part")
        slotHead.Name = "QueueSlotHead" .. i
        slotHead.Shape = Enum.PartType.Ball
        slotHead.Size = Vector3.new(0.8, 0.8, 0.8)
        slotHead.Position = Vector3.new(baseX - 6 + (i - 1) * 2.5, GROUND_Y + 3, baseZ + 2)
        slotHead.Anchored = true
        slotHead.Material = Enum.Material.SmoothPlastic
        slotHead.Color = Color3.fromRGB(227, 183, 151)
        slotHead.Transparency = 1
        slotHead.Parent = barracksModel

        table.insert(queueSlotParts, { body = slotBody, head = slotHead })
    end

    -- Queue visual update function
    local function updateQueueVisualsForPlayer(player)
        local uid = player.UserId
        local queue = BarracksState.trainingQueues[uid] or {}
        for i, parts in ipairs(queueSlotParts) do
            if i <= #queue then
                local troopDef = BarracksTroopTypes[queue[i].troopType]
                parts.body.Color = troopDef and troopDef.color or Color3.fromRGB(140, 140, 150)
                parts.body.Transparency = 0
                parts.head.Transparency = 0
            else
                parts.body.Transparency = 1
                parts.head.Transparency = 1
            end
        end
    end
    BarracksState.updateQueueVisuals = updateQueueVisualsForPlayer

    -- Training Menu GUI
    local function showTrainingMenu(player)
        local uid = player.UserId
        initPlayerBarracksData(player)

        if activeBarracksGuis[uid] then
            activeBarracksGuis[uid]:Destroy()
            activeBarracksGuis[uid] = nil
        end

        local playerGui = player:FindFirstChild("PlayerGui")
        if not playerGui then return end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "BarracksTrainingGui"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = playerGui
        activeBarracksGuis[uid] = screenGui

        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = UDim2.new(0, 500, 0, 450)
        mainFrame.Position = UDim2.new(0.5, -250, 0.5, -225)
        mainFrame.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
        mainFrame.BorderSizePixel = 3
        mainFrame.BorderColor3 = Color3.fromRGB(200, 50, 50)
        mainFrame.Parent = screenGui

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 45)
        title.BackgroundColor3 = Color3.fromRGB(50, 40, 30)
        title.BorderSizePixel = 0
        title.Text = "TRAINING STATION"
        title.TextColor3 = Color3.fromRGB(255, 100, 80)
        title.TextScaled = true
        title.Font = Enum.Font.GothamBold
        title.Parent = mainFrame

        -- Troop cards
        local yOffset = 55
        for _, troopName in ipairs(BarracksTroopOrder) do
            if BarracksState.researched[uid][troopName] then
                local troopDef = BarracksTroopTypes[troopName]

                local card = Instance.new("Frame")
                card.Size = UDim2.new(0.95, 0, 0, 85)
                card.Position = UDim2.new(0.025, 0, 0, yOffset)
                card.BackgroundColor3 = Color3.fromRGB(45, 40, 35)
                card.BorderSizePixel = 2
                card.BorderColor3 = troopDef.color
                card.Parent = mainFrame

                local cardTitle = Instance.new("TextLabel")
                cardTitle.Size = UDim2.new(0.5, 0, 0, 25)
                cardTitle.Position = UDim2.new(0.02, 0, 0, 5)
                cardTitle.BackgroundTransparency = 1
                cardTitle.Text = troopDef.displayName
                cardTitle.TextColor3 = troopDef.color
                cardTitle.TextXAlignment = Enum.TextXAlignment.Left
                cardTitle.TextScaled = true
                cardTitle.Font = Enum.Font.GothamBold
                cardTitle.Parent = card

                -- Cost display
                local costParts = {}
                if troopDef.costs.gold then table.insert(costParts, troopDef.costs.gold .. "g") end
                if troopDef.costs.wood then table.insert(costParts, troopDef.costs.wood .. "w") end
                if troopDef.costs.food then table.insert(costParts, troopDef.costs.food .. "f") end

                local costLabel = Instance.new("TextLabel")
                costLabel.Size = UDim2.new(0.96, 0, 0, 20)
                costLabel.Position = UDim2.new(0.02, 0, 0, 30)
                costLabel.BackgroundTransparency = 1
                costLabel.Text = "Cost: " .. table.concat(costParts, " / ") .. "  |  Time: " .. formatTimeRemaining(troopDef.trainTime)
                costLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
                costLabel.TextXAlignment = Enum.TextXAlignment.Left
                costLabel.TextScaled = true
                costLabel.Font = Enum.Font.Gotham
                costLabel.Parent = card

                local trainBtn = Instance.new("TextButton")
                trainBtn.Size = UDim2.new(0.96, 0, 0, 25)
                trainBtn.Position = UDim2.new(0.02, 0, 0, 55)
                trainBtn.BackgroundColor3 = Color3.fromRGB(80, 150, 80)
                trainBtn.BorderSizePixel = 0
                trainBtn.Text = "TRAIN " .. troopDef.displayName:upper()
                trainBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                trainBtn.TextScaled = true
                trainBtn.Font = Enum.Font.GothamBold
                trainBtn.Parent = card

                trainBtn.MouseButton1Click:Connect(function()
                    addToTrainingQueue(player, troopName)
                    -- Refresh GUI
                    showTrainingMenu(player)
                end)

                yOffset = yOffset + 90
            end
        end

        -- Queue display
        local queue = BarracksState.trainingQueues[uid] or {}
        local maxSlots = BarracksState.queueSlots[uid] or 2

        local queueTitle = Instance.new("TextLabel")
        queueTitle.Size = UDim2.new(0.95, 0, 0, 25)
        queueTitle.Position = UDim2.new(0.025, 0, 0, yOffset + 5)
        queueTitle.BackgroundTransparency = 1
        queueTitle.Text = string.format("Queue: %d/%d", #queue, maxSlots)
        queueTitle.TextColor3 = Color3.fromRGB(255, 200, 100)
        queueTitle.TextXAlignment = Enum.TextXAlignment.Left
        queueTitle.TextScaled = true
        queueTitle.Font = Enum.Font.GothamBold
        queueTitle.Parent = mainFrame

        local now = os.time()
        for i, item in ipairs(queue) do
            local remaining = item.completesAt - now
            local troopDef = BarracksTroopTypes[item.troopType]
            local queueLabel = Instance.new("TextLabel")
            queueLabel.Size = UDim2.new(0.9, 0, 0, 18)
            queueLabel.Position = UDim2.new(0.05, 0, 0, yOffset + 28 + (i - 1) * 20)
            queueLabel.BackgroundTransparency = 1
            queueLabel.Text = string.format("%d. %s - %s", i, troopDef and troopDef.displayName or item.troopType, formatTimeRemaining(remaining))
            queueLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
            queueLabel.TextXAlignment = Enum.TextXAlignment.Left
            queueLabel.TextScaled = true
            queueLabel.Font = Enum.Font.Gotham
            queueLabel.Parent = mainFrame
        end

        -- Resize frame to fit content
        local totalHeight = yOffset + 35 + #queue * 20 + 50
        mainFrame.Size = UDim2.new(0, 500, 0, math.max(350, totalHeight))
        mainFrame.Position = UDim2.new(0.5, -250, 0.5, -math.max(350, totalHeight) / 2)

        -- Close button
        local closeButton = Instance.new("TextButton")
        closeButton.Size = UDim2.new(0.5, 0, 0, 35)
        closeButton.Position = UDim2.new(0.25, 0, 1, -40)
        closeButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        closeButton.BorderSizePixel = 0
        closeButton.Text = "CLOSE"
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeButton.TextScaled = true
        closeButton.Font = Enum.Font.GothamBold
        closeButton.Parent = mainFrame

        closeButton.MouseButton1Click:Connect(function()
            screenGui:Destroy()
            activeBarracksGuis[uid] = nil
        end)
    end

    createInteraction(trainingTable, "Train Troops", "Training Station", 0, function(player)
        showTrainingMenu(player)
    end)

    -- ========================================================================
    -- STATION 2: RESEARCH STATION (left side)
    -- ========================================================================
    local researchTable = Instance.new("Part")
    researchTable.Name = "ResearchTable"
    researchTable.Size = Vector3.new(5, 3, 3)
    researchTable.Position = Vector3.new(baseX - 25, GROUND_Y + 1.5, baseZ - 5)
    researchTable.Anchored = true
    researchTable.Material = Enum.Material.Wood
    researchTable.Color = Color3.fromRGB(90, 60, 40)
    researchTable.Parent = barracksModel

    -- Scroll decoration
    local scroll = Instance.new("Part")
    scroll.Name = "ResearchScroll"
    scroll.Shape = Enum.PartType.Cylinder
    scroll.Size = Vector3.new(0.3, 2, 0.5)
    scroll.Position = Vector3.new(baseX - 25, GROUND_Y + 3.3, baseZ - 5)
    scroll.Orientation = Vector3.new(0, 0, 90)
    scroll.Anchored = true
    scroll.Material = Enum.Material.Fabric
    scroll.Color = Color3.fromRGB(230, 210, 170)
    scroll.Parent = barracksModel

    -- Glowing crystal
    local crystal = Instance.new("Part")
    crystal.Name = "ResearchCrystal"
    crystal.Size = Vector3.new(1, 2, 1)
    crystal.Position = Vector3.new(baseX - 23, GROUND_Y + 4, baseZ - 5)
    crystal.Anchored = true
    crystal.Material = Enum.Material.Neon
    crystal.Color = Color3.fromRGB(100, 150, 255)
    crystal.Parent = barracksModel

    local crystalLight = Instance.new("PointLight")
    crystalLight.Brightness = 1
    crystalLight.Range = 12
    crystalLight.Color = Color3.fromRGB(100, 150, 255)
    crystalLight.Parent = crystal

    createSign(barracksModel, "RESEARCH STATION", Vector3.new(baseX - 25, GROUND_Y + 6.5, baseZ - 3), Vector3.new(6, 1, 0.3))

    -- Research Menu GUI
    local function showResearchMenu(player)
        local uid = player.UserId
        initPlayerBarracksData(player)

        if activeBarracksGuis[uid] then
            activeBarracksGuis[uid]:Destroy()
            activeBarracksGuis[uid] = nil
        end

        local playerGui = player:FindFirstChild("PlayerGui")
        if not playerGui then return end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "BarracksResearchGui"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = playerGui
        activeBarracksGuis[uid] = screenGui

        local mainFrame = Instance.new("Frame")
        mainFrame.Size = UDim2.new(0, 450, 0, 400)
        mainFrame.Position = UDim2.new(0.5, -225, 0.5, -200)
        mainFrame.BackgroundColor3 = Color3.fromRGB(20, 25, 40)
        mainFrame.BorderSizePixel = 3
        mainFrame.BorderColor3 = Color3.fromRGB(100, 150, 255)
        mainFrame.Parent = screenGui

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 45)
        title.BackgroundColor3 = Color3.fromRGB(30, 35, 60)
        title.BorderSizePixel = 0
        title.Text = "RESEARCH STATION"
        title.TextColor3 = Color3.fromRGB(100, 180, 255)
        title.TextScaled = true
        title.Font = Enum.Font.GothamBold
        title.Parent = mainFrame

        -- Active research progress
        local yOffset = 55
        local activeRes = BarracksState.activeResearch[uid]
        if activeRes then
            local now = os.time()
            local remaining = activeRes.completesAt - now
            local troopDef = BarracksTroopTypes[activeRes.troopType]

            local activeCard = Instance.new("Frame")
            activeCard.Size = UDim2.new(0.95, 0, 0, 50)
            activeCard.Position = UDim2.new(0.025, 0, 0, yOffset)
            activeCard.BackgroundColor3 = Color3.fromRGB(40, 50, 80)
            activeCard.BorderSizePixel = 2
            activeCard.BorderColor3 = Color3.fromRGB(255, 200, 50)
            activeCard.Parent = mainFrame

            local activeLabel = Instance.new("TextLabel")
            activeLabel.Size = UDim2.new(0.96, 0, 0, 25)
            activeLabel.Position = UDim2.new(0.02, 0, 0, 5)
            activeLabel.BackgroundTransparency = 1
            activeLabel.Text = "Researching: " .. (troopDef and troopDef.displayName or activeRes.troopType)
            activeLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
            activeLabel.TextXAlignment = Enum.TextXAlignment.Left
            activeLabel.TextScaled = true
            activeLabel.Font = Enum.Font.GothamBold
            activeLabel.Parent = activeCard

            local timeLabel = Instance.new("TextLabel")
            timeLabel.Size = UDim2.new(0.96, 0, 0, 20)
            timeLabel.Position = UDim2.new(0.02, 0, 0, 28)
            timeLabel.BackgroundTransparency = 1
            timeLabel.Text = "Time remaining: " .. formatTimeRemaining(remaining)
            timeLabel.TextColor3 = Color3.fromRGB(180, 180, 220)
            timeLabel.TextXAlignment = Enum.TextXAlignment.Left
            timeLabel.TextScaled = true
            timeLabel.Font = Enum.Font.Gotham
            timeLabel.Parent = activeCard

            yOffset = yOffset + 60
        end

        -- Research cards for each troop type
        for _, troopName in ipairs(BarracksTroopOrder) do
            local troopDef = BarracksTroopTypes[troopName]
            local isResearched = BarracksState.researched[uid][troopName]

            local card = Instance.new("Frame")
            card.Size = UDim2.new(0.95, 0, 0, 70)
            card.Position = UDim2.new(0.025, 0, 0, yOffset)
            card.BackgroundColor3 = isResearched and Color3.fromRGB(30, 50, 30) or Color3.fromRGB(45, 40, 50)
            card.BorderSizePixel = 2
            card.BorderColor3 = troopDef.color
            card.Parent = mainFrame

            local cardTitle = Instance.new("TextLabel")
            cardTitle.Size = UDim2.new(0.6, 0, 0, 25)
            cardTitle.Position = UDim2.new(0.02, 0, 0, 5)
            cardTitle.BackgroundTransparency = 1
            cardTitle.Text = troopDef.displayName .. (isResearched and " (UNLOCKED)" or "")
            cardTitle.TextColor3 = isResearched and Color3.fromRGB(100, 200, 100) or troopDef.color
            cardTitle.TextXAlignment = Enum.TextXAlignment.Left
            cardTitle.TextScaled = true
            cardTitle.Font = Enum.Font.GothamBold
            cardTitle.Parent = card

            if not isResearched and troopDef.researchCost then
                -- Cost display
                local costParts = {}
                if troopDef.researchCost.gold then table.insert(costParts, troopDef.researchCost.gold .. "g") end
                if troopDef.researchCost.wood then table.insert(costParts, troopDef.researchCost.wood .. "w") end
                if troopDef.researchCost.food then table.insert(costParts, troopDef.researchCost.food .. "f") end
                local prereqText = troopDef.prereq and ("  |  Requires: " .. BarracksTroopTypes[troopDef.prereq].displayName) or ""

                local costLabel = Instance.new("TextLabel")
                costLabel.Size = UDim2.new(0.96, 0, 0, 18)
                costLabel.Position = UDim2.new(0.02, 0, 0, 28)
                costLabel.BackgroundTransparency = 1
                costLabel.Text = "Cost: " .. table.concat(costParts, " / ") .. "  |  " .. formatTimeRemaining(troopDef.researchTime) .. prereqText
                costLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
                costLabel.TextXAlignment = Enum.TextXAlignment.Left
                costLabel.TextScaled = true
                costLabel.Font = Enum.Font.Gotham
                costLabel.Parent = card

                local researchBtn = Instance.new("TextButton")
                researchBtn.Size = UDim2.new(0.4, 0, 0, 22)
                researchBtn.Position = UDim2.new(0.55, 0, 0, 44)
                researchBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 160)
                researchBtn.BorderSizePixel = 0
                researchBtn.Text = "RESEARCH"
                researchBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                researchBtn.TextScaled = true
                researchBtn.Font = Enum.Font.GothamBold
                researchBtn.Parent = card

                researchBtn.MouseButton1Click:Connect(function()
                    startResearch(player, troopName)
                    showResearchMenu(player)
                end)
            else
                local descLabel = Instance.new("TextLabel")
                descLabel.Size = UDim2.new(0.96, 0, 0, 18)
                descLabel.Position = UDim2.new(0.02, 0, 0, 30)
                descLabel.BackgroundTransparency = 1
                descLabel.Text = troopDef.description
                descLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
                descLabel.TextXAlignment = Enum.TextXAlignment.Left
                descLabel.TextScaled = true
                descLabel.Font = Enum.Font.Gotham
                descLabel.Parent = card
            end

            yOffset = yOffset + 75
        end

        -- Resize frame
        local totalHeight = yOffset + 50
        mainFrame.Size = UDim2.new(0, 450, 0, totalHeight)
        mainFrame.Position = UDim2.new(0.5, -225, 0.5, -totalHeight / 2)

        local closeButton = Instance.new("TextButton")
        closeButton.Size = UDim2.new(0.5, 0, 0, 35)
        closeButton.Position = UDim2.new(0.25, 0, 1, -40)
        closeButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        closeButton.BorderSizePixel = 0
        closeButton.Text = "CLOSE"
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeButton.TextScaled = true
        closeButton.Font = Enum.Font.GothamBold
        closeButton.Parent = mainFrame

        closeButton.MouseButton1Click:Connect(function()
            screenGui:Destroy()
            activeBarracksGuis[uid] = nil
        end)
    end

    createInteraction(researchTable, "Research Troops", "Research Station", 0, function(player)
        showResearchMenu(player)
    end)

    -- ========================================================================
    -- STATION 3: QUEUE EXPANSION (right side)
    -- ========================================================================
    local queueDesk = Instance.new("Part")
    queueDesk.Name = "QueueDesk"
    queueDesk.Size = Vector3.new(5, 3, 3)
    queueDesk.Position = Vector3.new(baseX + 25, GROUND_Y + 1.5, baseZ - 5)
    queueDesk.Anchored = true
    queueDesk.Material = Enum.Material.Wood
    queueDesk.Color = Color3.fromRGB(100, 70, 45)
    queueDesk.Parent = barracksModel

    -- Gold coin decoration
    local goldCoin = Instance.new("Part")
    goldCoin.Name = "GoldCoinDecor"
    goldCoin.Shape = Enum.PartType.Cylinder
    goldCoin.Size = Vector3.new(0.3, 1.5, 1.5)
    goldCoin.Position = Vector3.new(baseX + 25, GROUND_Y + 3.3, baseZ - 5)
    goldCoin.Orientation = Vector3.new(0, 0, 90)
    goldCoin.Anchored = true
    goldCoin.Material = Enum.Material.Neon
    goldCoin.Color = Color3.fromRGB(255, 200, 50)
    goldCoin.Parent = barracksModel

    createSign(barracksModel, "QUEUE EXPANSION", Vector3.new(baseX + 25, GROUND_Y + 6.5, baseZ - 3), Vector3.new(6, 1, 0.3))

    -- Queue Expansion Menu GUI
    local function showQueueExpansionMenu(player)
        local uid = player.UserId
        initPlayerBarracksData(player)

        if activeBarracksGuis[uid] then
            activeBarracksGuis[uid]:Destroy()
            activeBarracksGuis[uid] = nil
        end

        local playerGui = player:FindFirstChild("PlayerGui")
        if not playerGui then return end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "BarracksQueueGui"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = playerGui
        activeBarracksGuis[uid] = screenGui

        local mainFrame = Instance.new("Frame")
        mainFrame.Size = UDim2.new(0, 350, 0, 250)
        mainFrame.Position = UDim2.new(0.5, -175, 0.5, -125)
        mainFrame.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
        mainFrame.BorderSizePixel = 3
        mainFrame.BorderColor3 = Color3.fromRGB(255, 200, 50)
        mainFrame.Parent = screenGui

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 45)
        title.BackgroundColor3 = Color3.fromRGB(50, 40, 30)
        title.BorderSizePixel = 0
        title.Text = "QUEUE EXPANSION"
        title.TextColor3 = Color3.fromRGB(255, 200, 50)
        title.TextScaled = true
        title.Font = Enum.Font.GothamBold
        title.Parent = mainFrame

        local currentSlots = BarracksState.queueSlots[uid] or 2

        local slotsLabel = Instance.new("TextLabel")
        slotsLabel.Size = UDim2.new(0.9, 0, 0, 35)
        slotsLabel.Position = UDim2.new(0.05, 0, 0, 60)
        slotsLabel.BackgroundTransparency = 1
        slotsLabel.Text = string.format("Current Slots: %d / 5", currentSlots)
        slotsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        slotsLabel.TextScaled = true
        slotsLabel.Font = Enum.Font.GothamBold
        slotsLabel.Parent = mainFrame

        if currentSlots < 5 then
            local nextCost = QueueSlotCosts[currentSlots + 1]

            local costLabel = Instance.new("TextLabel")
            costLabel.Size = UDim2.new(0.9, 0, 0, 25)
            costLabel.Position = UDim2.new(0.05, 0, 0, 100)
            costLabel.BackgroundTransparency = 1
            costLabel.Text = string.format("Next slot cost: %d gold", nextCost)
            costLabel.TextColor3 = Color3.fromRGB(200, 200, 180)
            costLabel.TextScaled = true
            costLabel.Font = Enum.Font.Gotham
            costLabel.Parent = mainFrame

            local buyBtn = Instance.new("TextButton")
            buyBtn.Size = UDim2.new(0.6, 0, 0, 40)
            buyBtn.Position = UDim2.new(0.2, 0, 0, 140)
            buyBtn.BackgroundColor3 = Color3.fromRGB(80, 150, 80)
            buyBtn.BorderSizePixel = 0
            buyBtn.Text = string.format("BUY SLOT - %dg", nextCost)
            buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            buyBtn.TextScaled = true
            buyBtn.Font = Enum.Font.GothamBold
            buyBtn.Parent = mainFrame

            buyBtn.MouseButton1Click:Connect(function()
                buyQueueSlot(player)
                showQueueExpansionMenu(player)
            end)
        else
            local maxLabel = Instance.new("TextLabel")
            maxLabel.Size = UDim2.new(0.9, 0, 0, 35)
            maxLabel.Position = UDim2.new(0.05, 0, 0, 110)
            maxLabel.BackgroundTransparency = 1
            maxLabel.Text = "MAX SLOTS REACHED"
            maxLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
            maxLabel.TextScaled = true
            maxLabel.Font = Enum.Font.GothamBold
            maxLabel.Parent = mainFrame
        end

        local closeButton = Instance.new("TextButton")
        closeButton.Size = UDim2.new(0.5, 0, 0, 35)
        closeButton.Position = UDim2.new(0.25, 0, 1, -40)
        closeButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        closeButton.BorderSizePixel = 0
        closeButton.Text = "CLOSE"
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeButton.TextScaled = true
        closeButton.Font = Enum.Font.GothamBold
        closeButton.Parent = mainFrame

        closeButton.MouseButton1Click:Connect(function()
            screenGui:Destroy()
            activeBarracksGuis[uid] = nil
        end)
    end

    createInteraction(queueDesk, "Expand Queue", "Queue Expansion", 0, function(player)
        showQueueExpansionMenu(player)
    end)

    -- ========================================================================
    -- STATION 4: ARMY DISPLAY (back wall)
    -- ========================================================================
    local displayBoard = Instance.new("Part")
    displayBoard.Name = "ArmyDisplayBoard"
    displayBoard.Size = Vector3.new(20, 8, 0.5)
    displayBoard.Position = Vector3.new(baseX, GROUND_Y + 5, baseZ - 40)
    displayBoard.Anchored = true
    displayBoard.Material = Enum.Material.SmoothPlastic
    displayBoard.Color = Color3.fromRGB(25, 20, 18)
    displayBoard.Parent = barracksModel

    -- SurfaceGui for army counts
    local displayGui = Instance.new("SurfaceGui")
    displayGui.Face = Enum.NormalId.Front
    displayGui.Parent = displayBoard

    local displayTitle = Instance.new("TextLabel")
    displayTitle.Size = UDim2.new(1, 0, 0.2, 0)
    displayTitle.BackgroundTransparency = 1
    displayTitle.Text = "YOUR ARMY"
    displayTitle.TextColor3 = Color3.fromRGB(255, 200, 50)
    displayTitle.TextScaled = true
    displayTitle.Font = Enum.Font.GothamBold
    displayTitle.Parent = displayGui

    local displayContent = Instance.new("TextLabel")
    displayContent.Name = "ArmyContent"
    displayContent.Size = UDim2.new(1, 0, 0.75, 0)
    displayContent.Position = UDim2.new(0, 0, 0.22, 0)
    displayContent.BackgroundTransparency = 1
    displayContent.Text = "Enter barracks to view army"
    displayContent.TextColor3 = Color3.fromRGB(200, 200, 200)
    displayContent.TextScaled = true
    displayContent.Font = Enum.Font.Gotham
    displayContent.Parent = displayGui

    makeSignDoubleSided(displayBoard)

    createSign(barracksModel, "YOUR ARMY", Vector3.new(baseX, GROUND_Y + 10, baseZ - 40), Vector3.new(6, 1, 0.3))

    -- Troop statues on pedestals (decorative)
    local statueData = {
        { name = "Soldier", pos = Vector3.new(baseX - 6, GROUND_Y, baseZ - 37), color = Color3.fromRGB(140, 140, 150) },
        { name = "Archer", pos = Vector3.new(baseX, GROUND_Y, baseZ - 37), color = Color3.fromRGB(100, 140, 90) },
        { name = "Catapult", pos = Vector3.new(baseX + 6, GROUND_Y, baseZ - 37), color = Color3.fromRGB(100, 70, 45) },
    }
    for _, sd in ipairs(statueData) do
        -- Pedestal
        local pedestal = Instance.new("Part")
        pedestal.Name = sd.name .. "Pedestal"
        pedestal.Size = Vector3.new(2, 1, 2)
        pedestal.Position = sd.pos + Vector3.new(0, 0.5, 0)
        pedestal.Anchored = true
        pedestal.Material = Enum.Material.Cobblestone
        pedestal.Color = Color3.fromRGB(80, 75, 70)
        pedestal.Parent = barracksModel

        -- Statue body
        local statueBody = Instance.new("Part")
        statueBody.Name = sd.name .. "Statue"
        statueBody.Size = Vector3.new(1.2, 3, 0.8)
        statueBody.Position = sd.pos + Vector3.new(0, 2.5, 0)
        statueBody.Anchored = true
        statueBody.Material = Enum.Material.Metal
        statueBody.Color = sd.color
        statueBody.Parent = barracksModel

        -- Statue head
        local statueHead = Instance.new("Part")
        statueHead.Name = sd.name .. "StatueHead"
        statueHead.Shape = Enum.PartType.Ball
        statueHead.Size = Vector3.new(0.8, 0.8, 0.8)
        statueHead.Position = sd.pos + Vector3.new(0, 4.4, 0)
        statueHead.Anchored = true
        statueHead.Material = Enum.Material.Metal
        statueHead.Color = sd.color
        statueHead.Parent = barracksModel
    end

    -- Update army display when player approaches
    local displayTrigger = Instance.new("Part")
    displayTrigger.Name = "ArmyDisplayTrigger"
    displayTrigger.Size = Vector3.new(24, 8, 10)
    displayTrigger.Position = Vector3.new(baseX, GROUND_Y + 4, baseZ - 35)
    displayTrigger.Anchored = true
    displayTrigger.Transparency = 1
    displayTrigger.CanCollide = false
    displayTrigger.Parent = barracksModel

    local displayDebounce = {}
    displayTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if displayDebounce[player.UserId] then return end
        displayDebounce[player.UserId] = true

        -- Update display with troop counts
        if DataService then
            local playerData = DataService:GetPlayerData(player)
            if playerData then
                local troops = playerData.troops or {}
                local lines = {}
                for _, troopName in ipairs(BarracksTroopOrder) do
                    local count = troops[troopName] or 0
                    local troopDef = BarracksTroopTypes[troopName]
                    table.insert(lines, string.format("%s: %d", troopDef.displayName, count))
                end
                -- Also show other troops not in our list
                for troopType, count in pairs(troops) do
                    if not BarracksTroopTypes[troopType] and count > 0 then
                        table.insert(lines, string.format("%s: %d", troopType, count))
                    end
                end
                if #lines == 0 then
                    displayContent.Text = "No troops trained yet!\nVisit the Training Station"
                else
                    displayContent.Text = table.concat(lines, "\n")
                end
            end
        end

        task.delay(2, function() displayDebounce[player.UserId] = nil end)
    end)

    -- ========================================================================
    -- BACKGROUND PROCESSING: Training Queue
    -- ========================================================================
    task.spawn(function()
        while true do
            task.wait(1)
            local now = os.time()
            for _, player in ipairs(Players:GetPlayers()) do
                local uid = player.UserId
                local queue = BarracksState.trainingQueues[uid]
                if queue and #queue > 0 then
                    local firstItem = queue[1]
                    if firstItem.completesAt <= now then
                        -- Training complete! Add troop to player data
                        local troopType = firstItem.troopType
                        table.remove(queue, 1)

                        -- Shift remaining queue items forward
                        for i, item in ipairs(queue) do
                            if i == 1 then
                                item.startTime = now
                                item.completesAt = now + BarracksTroopTypes[item.troopType].trainTime
                            else
                                item.startTime = queue[i - 1].completesAt
                                item.completesAt = item.startTime + BarracksTroopTypes[item.troopType].trainTime
                            end
                        end

                        if DataService then
                            local playerData = DataService:GetPlayerData(player)
                            if playerData then
                                playerData.troops = playerData.troops or {}
                                playerData.troops[troopType] = (playerData.troops[troopType] or 0) + 1
                                DataService:UpdateFoodSupplyState(player)

                                -- Sync HUD
                                local Events = ReplicatedStorage:FindFirstChild("Events")
                                if Events then
                                    local SyncPlayerData = Events:FindFirstChild("SyncPlayerData")
                                    if SyncPlayerData then SyncPlayerData:FireClient(player, playerData) end
                                end
                            end
                        end

                        addBarracksXP(10)
                        local troopDef = BarracksTroopTypes[troopType]
                        notifyPlayer(player, "BarracksTrain", true,
                            troopDef.displayName .. " training complete! Added to your army.")
                        print(string.format("[Barracks] %s: %s training complete!", player.Name, troopType))

                        if BarracksState.updateQueueVisuals then
                            BarracksState.updateQueueVisuals(player)
                        end
                    end
                end
            end
        end
    end)

    -- ========================================================================
    -- BACKGROUND PROCESSING: Research
    -- ========================================================================
    task.spawn(function()
        while true do
            task.wait(1)
            local now = os.time()
            for _, player in ipairs(Players:GetPlayers()) do
                local uid = player.UserId
                local research = BarracksState.activeResearch[uid]
                if research and research.completesAt <= now then
                    local troopType = research.troopType
                    BarracksState.researched[uid] = BarracksState.researched[uid] or {}
                    BarracksState.researched[uid][troopType] = true
                    BarracksState.activeResearch[uid] = nil

                    addBarracksXP(20)

                    local troopDef = BarracksTroopTypes[troopType]
                    notifyPlayer(player, "BarracksResearch", true,
                        troopDef.displayName .. " research complete! You can now train them.")
                    print(string.format("[Barracks] %s: %s research complete!", player.Name, troopType))

                    -- Flash the crystal
                    task.spawn(function()
                        crystal.Color = Color3.fromRGB(255, 255, 100)
                        crystalLight.Color = Color3.fromRGB(255, 255, 100)
                        task.wait(1)
                        crystal.Color = Color3.fromRGB(100, 150, 255)
                        crystalLight.Color = Color3.fromRGB(100, 150, 255)
                    end)
                end
            end
        end
    end)

    -- ========================================================================
    -- PLAYER INIT AND CLEANUP
    -- ========================================================================
    Players.PlayerAdded:Connect(function(player)
        initPlayerBarracksData(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        local uid = player.UserId
        -- Cleanup GUI
        if activeBarracksGuis[uid] then
            activeBarracksGuis[uid]:Destroy()
            activeBarracksGuis[uid] = nil
        end
        -- Cleanup state
        BarracksState.trainingQueues[uid] = nil
        BarracksState.queueSlots[uid] = nil
        BarracksState.researched[uid] = nil
        BarracksState.activeResearch[uid] = nil
    end)

    -- Init existing players
    for _, player in ipairs(Players:GetPlayers()) do
        initPlayerBarracksData(player)
    end

    -- ===== BARRACKS DECORATIVE ENHANCEMENTS =====
    -- Training dummies in training yard
    local dummyPositions = {
        Vector3.new(baseX - 10, GROUND_Y, baseZ - 5),
        Vector3.new(baseX + 10, GROUND_Y, baseZ - 5),
        Vector3.new(baseX, GROUND_Y, baseZ + 8),
    }
    for di, dpos in dummyPositions do
        -- Post
        local dPost = Instance.new("Part")
        dPost.Name = "DummyPost" .. di
        dPost.Size = Vector3.new(0.5, 5, 0.5)
        dPost.Position = dpos + Vector3.new(0, 2.5, 0)
        dPost.Anchored = true
        dPost.Material = Enum.Material.Wood
        dPost.Color = Color3.fromRGB(80, 55, 35)
        dPost.CanCollide = false
        dPost.Parent = barracksModel

        -- Crossbar
        local dCross = Instance.new("Part")
        dCross.Name = "DummyCross" .. di
        dCross.Size = Vector3.new(2.5, 0.4, 0.4)
        dCross.Position = dpos + Vector3.new(0, 4, 0)
        dCross.Anchored = true
        dCross.Material = Enum.Material.Wood
        dCross.Color = Color3.fromRGB(80, 55, 35)
        dCross.CanCollide = false
        dCross.Parent = barracksModel

        -- Sack head
        local dHead = Instance.new("Part")
        dHead.Name = "DummyHead" .. di
        dHead.Shape = Enum.PartType.Ball
        dHead.Size = Vector3.new(1.2, 1.2, 1.2)
        dHead.Position = dpos + Vector3.new(0, 5.5, 0)
        dHead.Anchored = true
        dHead.Material = Enum.Material.Fabric
        dHead.Color = Color3.fromRGB(180, 160, 120)
        dHead.CanCollide = false
        dHead.Parent = barracksModel
    end

    -- Archery targets on back wall
    for ti = 1, 3 do
        -- Target board
        local target = Instance.new("Part")
        target.Name = "ArcheryTarget" .. ti
        target.Shape = Enum.PartType.Cylinder
        target.Size = Vector3.new(0.5, 3, 3)
        target.Position = Vector3.new(baseX - 20 + ti * 15, GROUND_Y + 4, baseZ - 41)
        target.Orientation = Vector3.new(0, 0, 90)
        target.Anchored = true
        target.Material = Enum.Material.Wood
        target.Color = Color3.fromRGB(220, 210, 180)
        target.CanCollide = false
        target.Parent = barracksModel

        -- Red ring
        local ring = Instance.new("Part")
        ring.Name = "TargetRing" .. ti
        ring.Shape = Enum.PartType.Cylinder
        ring.Size = Vector3.new(0.52, 2, 2)
        ring.Position = Vector3.new(baseX - 20 + ti * 15, GROUND_Y + 4, baseZ - 41.1)
        ring.Orientation = Vector3.new(0, 0, 90)
        ring.Anchored = true
        ring.Material = Enum.Material.SmoothPlastic
        ring.Color = Color3.fromRGB(200, 40, 40)
        ring.CanCollide = false
        ring.Parent = barracksModel

        -- Gold center
        local center = Instance.new("Part")
        center.Name = "TargetCenter" .. ti
        center.Shape = Enum.PartType.Cylinder
        center.Size = Vector3.new(0.54, 0.8, 0.8)
        center.Position = Vector3.new(baseX - 20 + ti * 15, GROUND_Y + 4, baseZ - 41.2)
        center.Orientation = Vector3.new(0, 0, 90)
        center.Anchored = true
        center.Material = Enum.Material.SmoothPlastic
        center.Color = Color3.fromRGB(255, 200, 50)
        center.CanCollide = false
        center.Parent = barracksModel
    end

    -- Weapon racks along side walls
    for _, rackX in {baseX - 55, baseX + 55} do
        -- Rack frame
        local rackFrame = Instance.new("Part")
        rackFrame.Name = "WeaponRack"
        rackFrame.Size = Vector3.new(1, 4, 6)
        rackFrame.Position = Vector3.new(rackX, GROUND_Y + 2, baseZ)
        rackFrame.Anchored = true
        rackFrame.Material = Enum.Material.Wood
        rackFrame.Color = Color3.fromRGB(80, 55, 35)
        rackFrame.CanCollide = false
        rackFrame.Parent = barracksModel

        -- Swords on rack
        for si = 1, 3 do
            local sword = Instance.new("Part")
            sword.Name = "RackSword" .. si
            sword.Size = Vector3.new(0.2, 3, 0.3)
            sword.Position = Vector3.new(rackX, GROUND_Y + 2.5, baseZ - 2 + si * 1.5)
            sword.Orientation = Vector3.new(0, 0, 10)
            sword.Anchored = true
            sword.Material = Enum.Material.Metal
            sword.Color = Color3.fromRGB(170, 170, 175)
            sword.CanCollide = false
            sword.Parent = barracksModel
        end
    end

    -- Military flag poles with banners
    for _, fpPos in {
        Vector3.new(baseX - 45, GROUND_Y, baseZ + 30),
        Vector3.new(baseX + 45, GROUND_Y, baseZ + 30),
        Vector3.new(baseX - 45, GROUND_Y, baseZ - 30),
        Vector3.new(baseX + 45, GROUND_Y, baseZ - 30),
    } do
        local fp = Instance.new("Part")
        fp.Name = "MilitaryFlagPole"
        fp.Size = Vector3.new(0.3, 10, 0.3)
        fp.Position = fpPos + Vector3.new(0, 5, 0)
        fp.Anchored = true
        fp.Material = Enum.Material.Metal
        fp.Color = Color3.fromRGB(60, 55, 50)
        fp.CanCollide = false
        fp.Parent = barracksModel

        local fb = Instance.new("Part")
        fb.Name = "MilitaryBanner"
        fb.Size = Vector3.new(0.1, 3, 2)
        fb.Position = fpPos + Vector3.new(0, 8.5, 1.5)
        fb.Anchored = true
        fb.Material = Enum.Material.Fabric
        fb.Color = Color3.fromRGB(180, 30, 30)
        fb.CanCollide = false
        fb.Parent = barracksModel
    end

    -- Sand ring for sparring (circular darker sand in center)
    local sparRing = Instance.new("Part")
    sparRing.Name = "SparringRing"
    sparRing.Shape = Enum.PartType.Cylinder
    sparRing.Size = Vector3.new(0.15, 20, 20)
    sparRing.Position = Vector3.new(baseX, GROUND_Y + 0.2, baseZ)
    sparRing.Anchored = true
    sparRing.Material = Enum.Material.Sand
    sparRing.Color = Color3.fromRGB(170, 150, 110)
    sparRing.CanCollide = false
    sparRing.Parent = barracksModel

    -- Parent the barracks interior
    barracksModel.Parent = interiorsFolder
    BarracksState.model = barracksModel

    print("  ✓ Barracks created (ARMY TRAINING SYSTEM interior):")
    print("    - Training Station: Train Soldiers, Archers, Catapults")
    print("    - Research Station: Unlock new troop types")
    print("    - Queue Expansion: Buy more training slots")
    print("    - Army Display: View your troop counts")
end

-- ============================================================================
-- TOWN HALL - City Command Center
-- ============================================================================
-- Four stations for city management:
--   1. JEWEL TROPHY CASE: Display stolen/prospected gems for city-wide bonuses
--   2. BUILDING UPGRADE CENTER: Centralized location for all building upgrades
--   3. SHIELD CONTROL CENTER: Manage city defenses
--   4. RESEARCH STATION: Unlock city improvements (future expansion)
-- ============================================================================

-- Town Hall state
local TownHallState = {
    level = 1,
    xp = 0,
    xpToNextLevel = 100,

    -- Jewel Trophy Case (3 shelves x 3 slots = 9 max)
    jewelCase = {
        slots = {},         -- [1-9] = nil or { type = "Ruby", size = "Gem", color = Color3, boost = "production", multiplier = 1.2 }
        maxSlots = 3,       -- Start with 3, can buy up to 9
    },

    -- Building Upgrades (centralized tracking)
    buildingLevels = {
        goldMine = 1,
        lumberMill = 1,
        barracks = 1,
        farm1 = 1,
        farm2 = 1,
        farm3 = 1,
        farm4 = 1,
        farm5 = 1,
        farm6 = 1,
    },

    -- Shield Control
    shields = {
        isActive = false,
        duration = 0,       -- Total shield duration in seconds
        endTime = 0,        -- When shield expires (tick value)
    },

    -- Research (future expansion)
    research = {
        completed = {},     -- Array of completed research IDs
        inProgress = nil,   -- { id = "...", startTime = 0, endTime = 0 }
    },

    -- Visual update functions (set during creation)
    updateJewelCaseVisuals = nil,
    updateShieldStatusVisuals = nil,

    population = 10, -- Base population
    positions = {},
}

-- Gem slot purchase costs (to unlock more slots beyond initial 3)
local GemSlotCosts = {
    [4] = { gold = 5000, wood = 1000 },
    [5] = { gold = 10000, wood = 2000 },
    [6] = { gold = 20000, wood = 4000 },
    [7] = { gold = 40000, wood = 8000 },
    [8] = { gold = 75000, wood = 15000 },
    [9] = { gold = 150000, wood = 30000 },
}

-- Shield durations and costs
local ShieldOptions = {
    { name = "Short Shield", duration = 3600, cost = { gold = 500 } },       -- 1 hour
    { name = "Medium Shield", duration = 14400, cost = { gold = 1500 } },    -- 4 hours
    { name = "Long Shield", duration = 43200, cost = { gold = 4000 } },      -- 12 hours
    { name = "Extended Shield", duration = 86400, cost = { gold = 10000 } }, -- 24 hours
}

-- Calculate gem bonuses from Town Hall's trophy case
-- Returns multipliers for production, speed, defense
local function calculateGemBonuses()
    local bonuses = {
        production = 1.0,  -- Multiplier for resource production
        speed = 1.0,       -- Multiplier for processing/training speed
        defense = 1.0,     -- Multiplier for defense strength
        all = 1.0,         -- Multiplier for everything (from Diamonds)
    }

    local jewelCase = TownHallState.jewelCase
    for i = 1, jewelCase.maxSlots do
        local gem = jewelCase.slots[i]
        if gem then
            local boost = gem.boost
            local multiplier = gem.multiplier

            if boost == "all" then
                -- Diamond boosts everything
                bonuses.all = bonuses.all * multiplier
            elseif boost == "production" then
                bonuses.production = bonuses.production * multiplier
            elseif boost == "speed" then
                bonuses.speed = bonuses.speed * multiplier
            elseif boost == "defense" then
                bonuses.defense = bonuses.defense * multiplier
            end
        end
    end

    -- Apply the "all" bonus to everything
    bonuses.production = bonuses.production * bonuses.all
    bonuses.speed = bonuses.speed * bonuses.all
    bonuses.defense = bonuses.defense * bonuses.all

    return bonuses
end

-- Get building level multiplier (Level 1 = 1.0x, Level 2 = 1.1x, Level 3 = 1.2x, etc.)
-- Each level adds +10% production
local function getBuildingLevelMultiplier(buildingName)
    local level = TownHallState.buildingLevels[buildingName]
    if not level then return 1.0 end
    return 1.0 + (level - 1) * 0.1
end

-- Get research bonuses from completed research
-- Returns bonuses per building and global bonuses
local function getResearchBonuses()
    local bonuses = {
        -- Per-building production bonuses
        production = {
            goldMine = 1.0,
            smelter = 1.0,
            lumberMill = 1.0,
            sawmill = 1.0,
            farm = 1.0,
            windmill = 1.0,
            barracks = 1.0,
        },
        -- Per-building speed bonuses
        speed = {
            goldMine = 1.0,
            smelter = 1.0,
            lumberMill = 1.0,
            sawmill = 1.0,
            farm = 1.0,
            windmill = 1.0,
            barracks = 1.0,
        },
        -- Global bonuses (apply to all)
        all = {
            production = 1.0,
            speed = 1.0,
        },
    }

    for _, researchId in ipairs(TownHallState.research.completed) do
        local research = ResearchTree[researchId]
        if research and research.bonus then
            local target = research.bonus.target
            local bonusType = research.bonus.type
            local value = research.bonus.value

            if target == "all" then
                -- Universal bonus applies to global all
                if bonusType == "production" then
                    bonuses.all.production = bonuses.all.production + value
                elseif bonusType == "speed" then
                    bonuses.all.speed = bonuses.all.speed + value
                end
            else
                -- Target-specific bonus
                if bonusType == "production" and bonuses.production[target] then
                    bonuses.production[target] = bonuses.production[target] + value
                elseif bonusType == "speed" and bonuses.speed[target] then
                    bonuses.speed[target] = bonuses.speed[target] + value
                end
            end
        end
    end

    return bonuses
end

-- Master bonus calculation function
-- Combines gem bonuses, building level bonuses, and research bonuses
-- Returns final multipliers for each building/system
local function calculateTotalBonuses()
    local gemBonuses = calculateGemBonuses()
    local researchBonuses = getResearchBonuses()

    local totals = {
        -- Production multipliers by building (base * gem * research_global * research_target * building_level)
        production = {
            goldMine = gemBonuses.production * researchBonuses.all.production * researchBonuses.production.goldMine * getBuildingLevelMultiplier("goldMine"),
            smelter = gemBonuses.production * researchBonuses.all.production * researchBonuses.production.smelter * getBuildingLevelMultiplier("goldMine"), -- smelter tied to goldMine level
            lumberMill = gemBonuses.production * researchBonuses.all.production * researchBonuses.production.lumberMill * getBuildingLevelMultiplier("lumberMill"),
            sawmill = gemBonuses.production * researchBonuses.all.production * researchBonuses.production.sawmill * getBuildingLevelMultiplier("lumberMill"), -- sawmill tied to lumberMill level
            farm = gemBonuses.production * researchBonuses.all.production * researchBonuses.production.farm,
            windmill = gemBonuses.production * researchBonuses.all.production * researchBonuses.production.windmill,
            barracks = gemBonuses.production * researchBonuses.all.production * researchBonuses.production.barracks * getBuildingLevelMultiplier("barracks"),
        },
        -- Speed multipliers by building
        speed = {
            goldMine = gemBonuses.speed * researchBonuses.all.speed * researchBonuses.speed.goldMine,
            smelter = gemBonuses.speed * researchBonuses.all.speed * researchBonuses.speed.smelter,
            lumberMill = gemBonuses.speed * researchBonuses.all.speed * researchBonuses.speed.lumberMill,
            sawmill = gemBonuses.speed * researchBonuses.all.speed * researchBonuses.speed.sawmill,
            farm = gemBonuses.speed * researchBonuses.all.speed * researchBonuses.speed.farm,
            windmill = gemBonuses.speed * researchBonuses.all.speed * researchBonuses.speed.windmill,
            barracks = gemBonuses.speed * researchBonuses.all.speed * researchBonuses.speed.barracks,
        },
        -- Defense bonus (gems only for now)
        defense = gemBonuses.defense,
    }

    -- Apply farm building level multipliers (each farm has its own level)
    for i = 1, 6 do
        local farmKey = "farm" .. i
        local farmLevelMultiplier = getBuildingLevelMultiplier(farmKey)
        totals.production["farm" .. i] = totals.production.farm * farmLevelMultiplier
    end

    return totals
end

-- Add XP to town hall and handle leveling
local function addTownHallXP(amount: number)
    TownHallState.xp = TownHallState.xp + amount
    while TownHallState.xp >= TownHallState.xpToNextLevel do
        TownHallState.xp = TownHallState.xp - TownHallState.xpToNextLevel
        TownHallState.level = TownHallState.level + 1
        TownHallState.xpToNextLevel = math.floor(TownHallState.xpToNextLevel * 1.5)
        TownHallState.population = TownHallState.population + 5 -- More citizens at higher levels
        print(string.format("[TownHall] LEVEL UP! Now level %d (Population: %d)", TownHallState.level, TownHallState.population))

        -- Update storage capacity in DataService for the village owner
        if DataService and _villageOwnerUserId then
            local ownerPlayer = Players:GetPlayerByUserId(_villageOwnerUserId)
            if ownerPlayer then
                local cap = DataService:GetStorageCapacityForTH(TownHallState.level)
                local playerData = DataService:GetPlayerData(ownerPlayer)
                if playerData and cap then
                    playerData.storageCapacity = { gold = cap.gold, wood = cap.wood, food = cap.food }
                    playerData.townHallLevel = TownHallState.level
                    print(string.format("[TownHall] Updated storage caps: %d gold, %d wood, %d food",
                        cap.gold, cap.wood, cap.food))
                end
            end
        end
    end
end

local function createTownHall()
    print("[7/8] Creating Town Hall with full progression loop...")

    -- ========== EXTERIOR IN VILLAGE (Grand Medieval Town Hall) ==========
    -- At the end of the main path, faces south toward incoming players
    local exteriorX, exteriorZ = 60, 155
    local extGround = GROUND_Y

    local townHallExterior = Instance.new("Model")
    townHallExterior.Name = "TownHall_Exterior"

    -- Color palette for town hall
    local stoneColor = Color3.fromRGB(180, 175, 165)      -- Light stone walls
    local darkStoneColor = Color3.fromRGB(120, 115, 105) -- Darker stone accents
    local roofColor = Color3.fromRGB(80, 60, 50)         -- Dark wood/slate roof
    local woodColor = Color3.fromRGB(90, 60, 40)         -- Wood trim
    local goldAccent = Color3.fromRGB(180, 150, 50)      -- Gold decorations

    -- ===== MAIN BUILDING BASE =====
    local mainBuilding = Instance.new("Part")
    mainBuilding.Name = "MainBuilding"
    mainBuilding.Size = Vector3.new(28, 12, 20)
    mainBuilding.Position = Vector3.new(exteriorX, extGround + 6, exteriorZ)
    mainBuilding.Anchored = true
    mainBuilding.Material = Enum.Material.Brick
    mainBuilding.Color = stoneColor
    mainBuilding.Parent = townHallExterior

    -- ===== CENTRAL CLOCK TOWER =====
    local towerBase = Instance.new("Part")
    towerBase.Name = "TowerBase"
    towerBase.Size = Vector3.new(10, 20, 10)
    towerBase.Position = Vector3.new(exteriorX, extGround + 10, exteriorZ)
    towerBase.Anchored = true
    towerBase.Material = Enum.Material.Brick
    towerBase.Color = stoneColor
    towerBase.Parent = townHallExterior

    -- Tower upper section (narrower)
    local towerUpper = Instance.new("Part")
    towerUpper.Name = "TowerUpper"
    towerUpper.Size = Vector3.new(8, 8, 8)
    towerUpper.Position = Vector3.new(exteriorX, extGround + 24, exteriorZ)
    towerUpper.Anchored = true
    towerUpper.Material = Enum.Material.Brick
    towerUpper.Color = darkStoneColor
    towerUpper.Parent = townHallExterior

    -- Tower spire/roof (pointed)
    local towerSpire = Instance.new("Part")
    towerSpire.Name = "TowerSpire"
    towerSpire.Size = Vector3.new(6, 10, 6)
    towerSpire.Position = Vector3.new(exteriorX, extGround + 33, exteriorZ)
    towerSpire.Anchored = true
    towerSpire.Material = Enum.Material.Slate
    towerSpire.Color = roofColor
    towerSpire.Parent = townHallExterior

    -- Spire top point
    local spireTop = Instance.new("Part")
    spireTop.Name = "SpireTop"
    spireTop.Size = Vector3.new(2, 6, 2)
    spireTop.Position = Vector3.new(exteriorX, extGround + 41, exteriorZ)
    spireTop.Anchored = true
    spireTop.Material = Enum.Material.Slate
    spireTop.Color = roofColor
    spireTop.Parent = townHallExterior

    -- Gold ornament on top
    local spireOrnament = Instance.new("Part")
    spireOrnament.Name = "SpireOrnament"
    spireOrnament.Shape = Enum.PartType.Ball
    spireOrnament.Size = Vector3.new(1.5, 1.5, 1.5)
    spireOrnament.Position = Vector3.new(exteriorX, extGround + 44.5, exteriorZ)
    spireOrnament.Anchored = true
    spireOrnament.Material = Enum.Material.Metal
    spireOrnament.Color = goldAccent
    spireOrnament.Parent = townHallExterior

    -- Clock face (facing south toward players)
    local clockFace = Instance.new("Part")
    clockFace.Name = "ClockFace"
    clockFace.Shape = Enum.PartType.Cylinder
    clockFace.Size = Vector3.new(0.5, 5, 5)
    clockFace.Position = Vector3.new(exteriorX, extGround + 24, exteriorZ - 4)
    clockFace.Orientation = Vector3.new(90, 0, 0)
    clockFace.Anchored = true
    clockFace.Material = Enum.Material.SmoothPlastic
    clockFace.Color = Color3.fromRGB(240, 235, 220)
    clockFace.Parent = townHallExterior

    -- Clock hands
    local hourHand = Instance.new("Part")
    hourHand.Name = "HourHand"
    hourHand.Size = Vector3.new(0.3, 1.5, 0.1)
    hourHand.Position = Vector3.new(exteriorX, extGround + 24.5, exteriorZ - 4.3)
    hourHand.Orientation = Vector3.new(0, 0, 30)
    hourHand.Anchored = true
    hourHand.Material = Enum.Material.Metal
    hourHand.Color = Color3.fromRGB(20, 20, 20)
    hourHand.Parent = townHallExterior

    local minuteHand = Instance.new("Part")
    minuteHand.Name = "MinuteHand"
    minuteHand.Size = Vector3.new(0.2, 2, 0.1)
    minuteHand.Position = Vector3.new(exteriorX + 0.3, extGround + 24.8, exteriorZ - 4.3)
    minuteHand.Orientation = Vector3.new(0, 0, -45)
    minuteHand.Anchored = true
    minuteHand.Material = Enum.Material.Metal
    minuteHand.Color = Color3.fromRGB(20, 20, 20)
    minuteHand.Parent = townHallExterior

    -- ===== MAIN ROOF (two-sided peaked) =====
    -- Left roof section
    local roofLeft = Instance.new("Part")
    roofLeft.Name = "RoofLeft"
    roofLeft.Size = Vector3.new(12, 2, 22)
    roofLeft.Position = Vector3.new(exteriorX - 8, extGround + 14, exteriorZ)
    roofLeft.Orientation = Vector3.new(0, 0, 25)
    roofLeft.Anchored = true
    roofLeft.Material = Enum.Material.Slate
    roofLeft.Color = roofColor
    roofLeft.Parent = townHallExterior

    -- Right roof section
    local roofRight = Instance.new("Part")
    roofRight.Name = "RoofRight"
    roofRight.Size = Vector3.new(12, 2, 22)
    roofRight.Position = Vector3.new(exteriorX + 8, extGround + 14, exteriorZ)
    roofRight.Orientation = Vector3.new(0, 0, -25)
    roofRight.Anchored = true
    roofRight.Material = Enum.Material.Slate
    roofRight.Color = roofColor
    roofRight.Parent = townHallExterior

    -- ===== GRAND ENTRANCE (facing south) =====
    -- Stone steps leading up to entrance
    for i = 1, 4 do
        local step = Instance.new("Part")
        step.Name = "Step" .. i
        step.Size = Vector3.new(12, 0.5, 2)
        step.Position = Vector3.new(exteriorX, extGround + (i-1) * 0.5 + 0.25, exteriorZ - 10 - (4-i) * 2)
        step.Anchored = true
        step.Material = Enum.Material.Marble
        step.Color = darkStoneColor
        step.Parent = townHallExterior
    end

    -- Entrance platform
    local entrancePlatform = Instance.new("Part")
    entrancePlatform.Name = "EntrancePlatform"
    entrancePlatform.Size = Vector3.new(14, 0.5, 6)
    entrancePlatform.Position = Vector3.new(exteriorX, extGround + 2.25, exteriorZ - 7)
    entrancePlatform.Anchored = true
    entrancePlatform.Material = Enum.Material.Marble
    entrancePlatform.Color = darkStoneColor
    entrancePlatform.Parent = townHallExterior

    -- Grand entrance columns (4 columns)
    local columnPositions = {-5, -2, 2, 5}
    for i, xOff in ipairs(columnPositions) do
        -- Column base
        local columnBase = Instance.new("Part")
        columnBase.Name = "ColumnBase" .. i
        columnBase.Size = Vector3.new(1.8, 1, 1.8)
        columnBase.Position = Vector3.new(exteriorX + xOff, extGround + 3, exteriorZ - 7)
        columnBase.Anchored = true
        columnBase.Material = Enum.Material.Marble
        columnBase.Color = Color3.fromRGB(200, 195, 185)
        columnBase.Parent = townHallExterior

        -- Column shaft
        local column = Instance.new("Part")
        column.Name = "Column" .. i
        column.Shape = Enum.PartType.Cylinder
        column.Size = Vector3.new(6, 1.2, 1.2)
        column.Position = Vector3.new(exteriorX + xOff, extGround + 6.5, exteriorZ - 7)
        column.Orientation = Vector3.new(0, 0, 90)
        column.Anchored = true
        column.Material = Enum.Material.Marble
        column.Color = Color3.fromRGB(220, 215, 205)
        column.Parent = townHallExterior

        -- Column capital (top)
        local columnTop = Instance.new("Part")
        columnTop.Name = "ColumnTop" .. i
        columnTop.Size = Vector3.new(2, 1, 2)
        columnTop.Position = Vector3.new(exteriorX + xOff, extGround + 10, exteriorZ - 7)
        columnTop.Anchored = true
        columnTop.Material = Enum.Material.Marble
        columnTop.Color = Color3.fromRGB(200, 195, 185)
        columnTop.Parent = townHallExterior
    end

    -- Entrance portico roof (above columns)
    local porticoRoof = Instance.new("Part")
    porticoRoof.Name = "PorticoRoof"
    porticoRoof.Size = Vector3.new(16, 1.5, 8)
    porticoRoof.Position = Vector3.new(exteriorX, extGround + 11.5, exteriorZ - 7)
    porticoRoof.Anchored = true
    porticoRoof.Material = Enum.Material.Marble
    porticoRoof.Color = darkStoneColor
    porticoRoof.Parent = townHallExterior

    -- Triangular pediment above entrance
    local pediment = Instance.new("Part")
    pediment.Name = "Pediment"
    pediment.Size = Vector3.new(14, 4, 1)
    pediment.Position = Vector3.new(exteriorX, extGround + 14, exteriorZ - 7)
    pediment.Anchored = true
    pediment.Material = Enum.Material.Marble
    pediment.Color = stoneColor
    pediment.Parent = townHallExterior

    -- Dark entrance doorway
    local doorway = Instance.new("Part")
    doorway.Name = "Doorway"
    doorway.Size = Vector3.new(6, 7, 2)
    doorway.Position = Vector3.new(exteriorX, extGround + 6, exteriorZ - 9.15)
    doorway.Anchored = true
    doorway.Material = Enum.Material.Slate
    doorway.Color = Color3.fromRGB(30, 25, 20)
    doorway.Parent = townHallExterior

    -- Wooden double doors (decorative)
    local leftDoor = Instance.new("Part")
    leftDoor.Name = "LeftDoor"
    leftDoor.Size = Vector3.new(2.5, 6, 0.3)
    leftDoor.Position = Vector3.new(exteriorX - 1.3, extGround + 5.5, exteriorZ - 8.65)
    leftDoor.Anchored = true
    leftDoor.Material = Enum.Material.Wood
    leftDoor.Color = woodColor
    leftDoor.Parent = townHallExterior

    local rightDoor = Instance.new("Part")
    rightDoor.Name = "RightDoor"
    rightDoor.Size = Vector3.new(2.5, 6, 0.3)
    rightDoor.Position = Vector3.new(exteriorX + 1.3, extGround + 5.5, exteriorZ - 8.65)
    rightDoor.Anchored = true
    rightDoor.Material = Enum.Material.Wood
    rightDoor.Color = woodColor
    rightDoor.Parent = townHallExterior

    -- Door handles (gold)
    for _, xOff in ipairs({-0.3, 2.9}) do
        local handle = Instance.new("Part")
        handle.Name = "DoorHandle"
        handle.Shape = Enum.PartType.Ball
        handle.Size = Vector3.new(0.4, 0.4, 0.4)
        handle.Position = Vector3.new(exteriorX + xOff - 1, extGround + 5.5, exteriorZ - 8.45)
        handle.Anchored = true
        handle.Material = Enum.Material.Metal
        handle.Color = goldAccent
        handle.Parent = townHallExterior
    end

    -- ===== WINDOWS =====
    -- Side windows on main building
    for _, side in ipairs({-1, 1}) do
        for i = 1, 2 do
            local window = Instance.new("Part")
            window.Name = "Window"
            window.Size = Vector3.new(3, 4, 0.3)
            window.Position = Vector3.new(exteriorX + side * 10, extGround + 6, exteriorZ - 5 + i * 8)
            window.Orientation = Vector3.new(0, 90, 0)
            window.Anchored = true
            window.Material = Enum.Material.Glass
            window.Color = Color3.fromRGB(150, 180, 220)
            window.Transparency = 0.3
            window.Parent = townHallExterior
        end
    end

    -- ===== DECORATIVE ELEMENTS =====
    -- Royal banners on either side of entrance
    for _, xOff in ipairs({-7, 7}) do
        local bannerPole = Instance.new("Part")
        bannerPole.Name = "BannerPole"
        bannerPole.Size = Vector3.new(0.3, 8, 0.3)
        bannerPole.Position = Vector3.new(exteriorX + xOff, extGround + 8, exteriorZ - 6)
        bannerPole.Orientation = Vector3.new(0, 0, 20 * (xOff > 0 and -1 or 1))
        bannerPole.Anchored = true
        bannerPole.Material = Enum.Material.Metal
        bannerPole.Color = goldAccent
        bannerPole.Parent = townHallExterior

        local banner = Instance.new("Part")
        banner.Name = "Banner"
        banner.Size = Vector3.new(0.1, 5, 3)
        banner.Position = Vector3.new(exteriorX + xOff + (xOff > 0 and 1 or -1), extGround + 9, exteriorZ - 6)
        banner.Anchored = true
        banner.Material = Enum.Material.Fabric
        banner.Color = Color3.fromRGB(150, 50, 50) -- Royal red
        banner.Parent = townHallExterior
    end

    -- Torches at entrance
    createTorch(townHallExterior, Vector3.new(exteriorX - 6.5, extGround + 6, exteriorZ - 8))
    createTorch(townHallExterior, Vector3.new(exteriorX + 6.5, extGround + 6, exteriorZ - 8))

    -- "TOWN HALL" sign above entrance
    local signBoard = Instance.new("Part")
    signBoard.Name = "TownHallSign"
    signBoard.Size = Vector3.new(10, 2, 0.3)
    signBoard.Position = Vector3.new(exteriorX, extGround + 17, exteriorZ - 5)
    signBoard.Anchored = true
    signBoard.Material = Enum.Material.Wood
    signBoard.Color = woodColor
    signBoard.Parent = townHallExterior

    local signGui = Instance.new("SurfaceGui")
    signGui.Face = Enum.NormalId.Front
    signGui.Parent = signBoard

    local signLabel = Instance.new("TextLabel")
    signLabel.Size = UDim2.new(1, 0, 1, 0)
    signLabel.BackgroundTransparency = 1
    signLabel.Text = "TOWN HALL"
    signLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    signLabel.TextScaled = true
    signLabel.Font = Enum.Font.Antique
    signLabel.Parent = signGui
    makeSignDoubleSided(signBoard)

    -- ===== ENTRANCE TRIGGER =====
    local entranceTrigger = Instance.new("Part")
    entranceTrigger.Name = "Entrance"
    entranceTrigger.Size = Vector3.new(5, 6, 3)
    entranceTrigger.Position = Vector3.new(exteriorX, extGround + 5.5, exteriorZ - 9)
    entranceTrigger.Anchored = true
    entranceTrigger.Transparency = 1
    entranceTrigger.CanCollide = false
    entranceTrigger.Parent = townHallExterior

    local debounce = {}
    entranceTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if debounce[player.UserId] then return end
        debounce[player.UserId] = true
        teleportToInterior(player, "TownHall")
        task.delay(1, function() debounce[player.UserId] = nil end)
    end)

    -- Stained glass windows
    local stainedGlassColors = {
        Color3.fromRGB(180, 40, 40),
        Color3.fromRGB(40, 80, 180),
        Color3.fromRGB(200, 170, 40),
    }
    for gi, glassColor in stainedGlassColors do
        local stainedGlass = Instance.new("Part")
        stainedGlass.Name = "StainedGlass" .. gi
        stainedGlass.Size = Vector3.new(0.3, 3.5, 2)
        stainedGlass.Position = Vector3.new(exteriorX + (gi - 2) * 6, extGround + 6, exteriorZ - 10.2)
        stainedGlass.Anchored = true
        stainedGlass.Material = Enum.Material.Glass
        stainedGlass.Color = glassColor
        stainedGlass.Transparency = 0.3
        stainedGlass.CanCollide = false
        stainedGlass.Parent = townHallExterior
    end

    -- Stone steps leading to entrance
    for si = 1, 3 do
        local step = Instance.new("Part")
        step.Name = "Step" .. si
        step.Size = Vector3.new(6 + si * 2, 0.5, 1.5)
        step.Position = Vector3.new(exteriorX, extGround + (si - 1) * 0.5, exteriorZ - 10 - si * 1.5)
        step.Anchored = true
        step.Material = Enum.Material.Cobblestone
        step.Color = Color3.fromRGB(160, 155, 145)
        step.Parent = townHallExterior
    end

    -- Flag on spire
    local spireFlagPole = Instance.new("Part")
    spireFlagPole.Name = "SpireFlagPole"
    spireFlagPole.Size = Vector3.new(0.2, 5, 0.2)
    spireFlagPole.Position = Vector3.new(exteriorX, extGround + 46, exteriorZ)
    spireFlagPole.Anchored = true
    spireFlagPole.Material = Enum.Material.Metal
    spireFlagPole.Color = Color3.fromRGB(60, 55, 50)
    spireFlagPole.CanCollide = false
    spireFlagPole.Parent = townHallExterior

    local spireFlag = Instance.new("Part")
    spireFlag.Name = "SpireFlag"
    spireFlag.Size = Vector3.new(0.1, 3, 2)
    spireFlag.Position = Vector3.new(exteriorX, extGround + 47, exteriorZ + 1.5)
    spireFlag.Anchored = true
    spireFlag.Material = Enum.Material.Fabric
    spireFlag.Color = Color3.fromRGB(180, 150, 50)
    spireFlag.CanCollide = false
    spireFlag.Parent = townHallExterior

    -- Buttress supports on side walls
    for _, bside in {-1, 1} do
        for bi = 1, 2 do
            local buttress = Instance.new("Part")
            buttress.Name = "Buttress"
            buttress.Size = Vector3.new(1.5, 8, 2)
            buttress.Position = Vector3.new(exteriorX + bside * 14.5, extGround + 4, exteriorZ - 5 + bi * 10)
            buttress.Anchored = true
            buttress.Material = Enum.Material.Brick
            buttress.Color = darkStoneColor
            buttress.CanCollide = false
            buttress.Parent = townHallExterior
        end
    end

    -- Royal banner above entrance
    local royalBanner = Instance.new("Part")
    royalBanner.Name = "RoyalBanner"
    royalBanner.Size = Vector3.new(0.15, 4, 3)
    royalBanner.Position = Vector3.new(exteriorX, extGround + 10, exteriorZ - 10.3)
    royalBanner.Anchored = true
    royalBanner.Material = Enum.Material.Fabric
    royalBanner.Color = Color3.fromRGB(100, 20, 20)
    royalBanner.CanCollide = false
    royalBanner.Parent = townHallExterior

    -- Banner gold trim
    local bannerTrim = Instance.new("Part")
    bannerTrim.Name = "BannerTrim"
    bannerTrim.Size = Vector3.new(0.16, 0.3, 3)
    bannerTrim.Position = Vector3.new(exteriorX, extGround + 8, exteriorZ - 10.3)
    bannerTrim.Anchored = true
    bannerTrim.Material = Enum.Material.Metal
    bannerTrim.Color = Color3.fromRGB(200, 170, 50)
    bannerTrim.CanCollide = false
    bannerTrim.Parent = townHallExterior

    -- Garden near entrance
    local gardenBed = Instance.new("Part")
    gardenBed.Name = "Garden"
    gardenBed.Size = Vector3.new(8, 0.3, 3)
    gardenBed.Position = Vector3.new(exteriorX + 10, extGround + 0.15, exteriorZ - 12)
    gardenBed.Anchored = true
    gardenBed.Material = Enum.Material.Ground
    gardenBed.Color = Color3.fromRGB(70, 50, 30)
    gardenBed.CanCollide = false
    gardenBed.Parent = townHallExterior

    for gf = 1, 5 do
        local gardenFlower = Instance.new("Part")
        gardenFlower.Name = "GardenFlower" .. gf
        gardenFlower.Shape = Enum.PartType.Ball
        gardenFlower.Size = Vector3.new(0.6, 0.6, 0.6)
        gardenFlower.Position = Vector3.new(exteriorX + 7 + gf * 1.2, extGround + 0.6, exteriorZ - 12)
        gardenFlower.Anchored = true
        gardenFlower.Material = Enum.Material.Grass
        gardenFlower.Color = stainedGlassColors[(gf % 3) + 1]
        gardenFlower.CanCollide = false
        gardenFlower.Parent = townHallExterior
    end

    -- Golden window glow
    for _, wPos in {
        Vector3.new(exteriorX - 14.5, extGround + 5, exteriorZ),
        Vector3.new(exteriorX + 14.5, extGround + 5, exteriorZ),
        Vector3.new(exteriorX, extGround + 5, exteriorZ - 10.5),
    } do
        local windowGlow = Instance.new("PointLight")
        windowGlow.Name = "WindowGlow"
        windowGlow.Color = Color3.fromRGB(255, 220, 120)
        windowGlow.Brightness = 1.2
        windowGlow.Range = 15
        local glowPart = Instance.new("Part")
        glowPart.Name = "WindowGlowSource"
        glowPart.Size = Vector3.new(0.5, 0.5, 0.5)
        glowPart.Position = wPos
        glowPart.Anchored = true
        glowPart.Transparency = 1
        glowPart.CanCollide = false
        glowPart.Parent = townHallExterior
        windowGlow.Parent = glowPart
    end

    townHallExterior.Parent = villageFolder

    -- ========== GRAND HALL INTERIOR ==========
    local basePos = INTERIOR_POSITIONS.TownHall
    local townHallModel = Instance.new("Model")
    townHallModel.Name = "TownHall_Interior"

    local baseX, baseZ = basePos.X, basePos.Z
    local GROUND_Y = basePos.Y

    -- Store positions for workers
    TownHallState.positions = {
        taxOffice = Vector3.new(baseX - 40, GROUND_Y, baseZ - 30),
        census = Vector3.new(baseX - 40, GROUND_Y, baseZ + 10),
        library = Vector3.new(baseX + 40, GROUND_Y, baseZ - 30),
        treasury = Vector3.new(baseX + 40, GROUND_Y, baseZ + 10),
        throne = Vector3.new(baseX, GROUND_Y, baseZ - 45),
        workerSpawn = Vector3.new(baseX - 30, GROUND_Y, baseZ + 40),
    }

    -- ===== POLISHED MARBLE FLOOR =====
    local hallFloor = Instance.new("Part")
    hallFloor.Name = "GrandHallFloor"
    hallFloor.Size = Vector3.new(130, 2, 110)
    hallFloor.Position = Vector3.new(baseX, GROUND_Y - 1, baseZ)
    hallFloor.Anchored = true
    hallFloor.Material = Enum.Material.Marble
    hallFloor.Color = Color3.fromRGB(220, 215, 205)
    hallFloor.Parent = townHallModel

    -- Decorative floor pattern (darker marble inlay)
    local floorPattern = Instance.new("Part")
    floorPattern.Size = Vector3.new(100, 0.1, 80)
    floorPattern.Position = Vector3.new(baseX, GROUND_Y + 0.15, baseZ)
    floorPattern.Anchored = true
    floorPattern.Material = Enum.Material.Marble
    floorPattern.Color = Color3.fromRGB(180, 175, 165)
    floorPattern.Parent = townHallModel

    -- ===== GRAND STONE WALLS =====
    local wallHeight = 22
    local wallColor = Color3.fromRGB(170, 165, 155)
    local wallPositions = {
        { pos = Vector3.new(baseX, GROUND_Y + wallHeight/2, baseZ - 53), size = Vector3.new(128, wallHeight, 3) }, -- Back
        { pos = Vector3.new(baseX - 63, GROUND_Y + wallHeight/2, baseZ), size = Vector3.new(3, wallHeight, 106) }, -- Left
        { pos = Vector3.new(baseX + 63, GROUND_Y + wallHeight/2, baseZ), size = Vector3.new(3, wallHeight, 106) }, -- Right
    }
    for i, w in ipairs(wallPositions) do
        local wall = Instance.new("Part")
        wall.Name = "GrandWall" .. i
        wall.Size = w.size
        wall.Position = w.pos
        wall.Anchored = true
        wall.Material = Enum.Material.Marble
        wall.Color = wallColor
        wall.Parent = townHallModel
    end

    -- Front wall with grand entrance
    local frontWallLeft = Instance.new("Part")
    frontWallLeft.Size = Vector3.new(55, wallHeight, 3)
    frontWallLeft.Position = Vector3.new(baseX - 36, GROUND_Y + wallHeight/2, baseZ + 53)
    frontWallLeft.Anchored = true
    frontWallLeft.Material = Enum.Material.Marble
    frontWallLeft.Color = wallColor
    frontWallLeft.Parent = townHallModel

    local frontWallRight = Instance.new("Part")
    frontWallRight.Size = Vector3.new(55, wallHeight, 3)
    frontWallRight.Position = Vector3.new(baseX + 36, GROUND_Y + wallHeight/2, baseZ + 53)
    frontWallRight.Anchored = true
    frontWallRight.Material = Enum.Material.Marble
    frontWallRight.Color = wallColor
    frontWallRight.Parent = townHallModel

    -- Grand entrance arch
    local entranceArch = Instance.new("Part")
    entranceArch.Size = Vector3.new(18, 6, 3)
    entranceArch.Position = Vector3.new(baseX, GROUND_Y + wallHeight - 3, baseZ + 53)
    entranceArch.Anchored = true
    entranceArch.Material = Enum.Material.Marble
    entranceArch.Color = Color3.fromRGB(200, 195, 185)
    entranceArch.Parent = townHallModel

    -- ===== VAULTED CEILING =====
    local ceiling = Instance.new("Part")
    ceiling.Name = "VaultedCeiling"
    ceiling.Size = Vector3.new(130, 3, 110)
    ceiling.Position = Vector3.new(baseX, GROUND_Y + wallHeight + 1, baseZ)
    ceiling.Anchored = true
    ceiling.Material = Enum.Material.Marble
    ceiling.Color = Color3.fromRGB(200, 195, 185)
    ceiling.Parent = townHallModel

    -- Ceiling decorative beams
    for i = 1, 5 do
        local beam = Instance.new("Part")
        beam.Size = Vector3.new(126, 2, 3)
        beam.Position = Vector3.new(baseX, GROUND_Y + wallHeight - 1, baseZ - 40 + i * 18)
        beam.Anchored = true
        beam.Material = Enum.Material.Wood
        beam.Color = Color3.fromRGB(80, 55, 35)
        beam.Parent = townHallModel
    end

    -- ===== EXIT PORTAL =====
    createExitPortal(townHallModel, Vector3.new(baseX, GROUND_Y + 5, baseZ + 50))

    -- ========== INTERIOR DECORATIONS ==========
    -- Grand royal carpet down the center
    local carpet = Instance.new("Part")
    carpet.Name = "RoyalCarpet"
    carpet.Size = Vector3.new(6, 0.1, 60)
    carpet.Position = Vector3.new(baseX, GROUND_Y + 0.25, baseZ)
    carpet.Anchored = true
    carpet.Material = Enum.Material.Fabric
    carpet.Color = Color3.fromRGB(150, 50, 50)
    carpet.Parent = townHallModel

    -- Marble columns along the hall
    for i = 1, 6 do
        for _, xOffset in {-20, 20} do
            local column = Instance.new("Part")
            column.Name = "Column"
            column.Shape = Enum.PartType.Cylinder
            column.Size = Vector3.new(18, 2.5, 2.5)
            column.Position = Vector3.new(baseX + xOffset, GROUND_Y + 9, baseZ - 40 + i * 14)
            column.Orientation = Vector3.new(0, 0, 90)
            column.Anchored = true
            column.Material = Enum.Material.Marble
            column.Color = Color3.fromRGB(220, 215, 210)
            column.Parent = townHallModel
        end
    end

    -- Royal banners on walls
    for i = 1, 4 do
        local banner = Instance.new("Part")
        banner.Name = "RoyalBanner" .. i
        banner.Size = Vector3.new(0.1, 10, 6)
        banner.Position = Vector3.new(baseX - 55, GROUND_Y + 10, baseZ - 35 + i * 20)
        banner.Anchored = true
        banner.Material = Enum.Material.Fabric
        banner.Color = i % 2 == 0 and Color3.fromRGB(50, 50, 150) or Color3.fromRGB(150, 50, 50)
        banner.Parent = townHallModel
    end

    -- Chandeliers
    for i = 1, 3 do
        local chandelier = Instance.new("Part")
        chandelier.Name = "Chandelier" .. i
        chandelier.Size = Vector3.new(5, 3, 5)
        chandelier.Position = Vector3.new(baseX, GROUND_Y + 17, baseZ - 30 + i * 25)
        chandelier.Anchored = true
        chandelier.Material = Enum.Material.Metal
        chandelier.Color = Color3.fromRGB(180, 160, 50)
        chandelier.Parent = townHallModel

        -- Chandelier lights
        local light = Instance.new("PointLight")
        light.Brightness = 1.5
        light.Range = 30
        light.Color = Color3.fromRGB(255, 240, 200)
        light.Parent = chandelier
    end

    -- Throne at the back
    local throne = Instance.new("Part")
    throne.Name = "Throne"
    throne.Size = Vector3.new(4, 6, 3)
    throne.Position = Vector3.new(baseX, GROUND_Y + 3, baseZ - 45)
    throne.Anchored = true
    throne.Material = Enum.Material.Marble
    throne.Color = Color3.fromRGB(180, 160, 50)
    throne.Parent = townHallModel

    -- ========================================================================
    -- NEW STATION 1: JEWEL TROPHY CASE (Display gems for city-wide bonuses)
    -- ========================================================================

    -- Trophy case back panel (against back wall)
    local trophyCaseBack = Instance.new("Part")
    trophyCaseBack.Name = "TrophyCaseBack"
    trophyCaseBack.Size = Vector3.new(18, 12, 1)
    trophyCaseBack.Position = Vector3.new(baseX, GROUND_Y + 6, baseZ - 48)
    trophyCaseBack.Anchored = true
    trophyCaseBack.Material = Enum.Material.Wood
    trophyCaseBack.Color = Color3.fromRGB(80, 55, 35)
    trophyCaseBack.Parent = townHallModel

    -- Trophy case glass front
    local trophyCaseGlass = Instance.new("Part")
    trophyCaseGlass.Name = "TrophyCaseGlass"
    trophyCaseGlass.Size = Vector3.new(18, 12, 0.3)
    trophyCaseGlass.Position = Vector3.new(baseX, GROUND_Y + 6, baseZ - 46)
    trophyCaseGlass.Anchored = true
    trophyCaseGlass.Material = Enum.Material.Glass
    trophyCaseGlass.Color = Color3.fromRGB(200, 220, 255)
    trophyCaseGlass.Transparency = 0.7
    trophyCaseGlass.Parent = townHallModel

    -- Create 3 shelves with 3 gem pedestals each (9 total slots)
    local gemPedestals = {}
    local gemVisuals = {}

    for shelf = 1, 3 do
        -- Shelf surface
        local shelfPart = Instance.new("Part")
        shelfPart.Name = "Shelf" .. shelf
        shelfPart.Size = Vector3.new(16, 0.3, 2)
        shelfPart.Position = Vector3.new(baseX, GROUND_Y + 2 + (shelf * 3), baseZ - 47)
        shelfPart.Anchored = true
        shelfPart.Material = Enum.Material.Wood
        shelfPart.Color = Color3.fromRGB(100, 70, 45)
        shelfPart.Parent = townHallModel

        -- Create 3 pedestals per shelf
        for slot = 1, 3 do
            local slotNum = (shelf - 1) * 3 + slot
            local xOffset = -5 + (slot - 1) * 5

            -- Pedestal base
            local pedestal = Instance.new("Part")
            pedestal.Name = "Pedestal_" .. slotNum
            pedestal.Size = Vector3.new(2, 0.8, 1.5)
            pedestal.Position = Vector3.new(baseX + xOffset, shelfPart.Position.Y + 0.55, baseZ - 47)
            pedestal.Anchored = true
            pedestal.Material = Enum.Material.Marble
            pedestal.Color = Color3.fromRGB(220, 215, 210)
            pedestal.Parent = townHallModel
            gemPedestals[slotNum] = pedestal

            -- Gem visual placeholder (starts invisible)
            local gemVisual = Instance.new("Part")
            gemVisual.Name = "GemVisual_" .. slotNum
            gemVisual.Shape = Enum.PartType.Ball
            gemVisual.Size = Vector3.new(1, 1, 1)
            gemVisual.Position = pedestal.Position + Vector3.new(0, 0.8, 0)
            gemVisual.Anchored = true
            gemVisual.Material = Enum.Material.Neon
            gemVisual.Color = Color3.fromRGB(255, 255, 255)
            gemVisual.Transparency = 1 -- Hidden by default
            gemVisual.Parent = townHallModel
            gemVisuals[slotNum] = gemVisual

            -- Check if slot is active or locked
            if slotNum <= TownHallState.jewelCase.maxSlots then
                -- Active slot - interaction prompt
                local prompt = Instance.new("ProximityPrompt")
                prompt.Name = "GemSlotPrompt_" .. slotNum
                prompt.ObjectText = "Gem Slot " .. slotNum
                prompt.ActionText = "Place Gem"
                prompt.HoldDuration = 0.5
                prompt.MaxActivationDistance = 8
                prompt.Parent = pedestal

                prompt.Triggered:Connect(function(player)
                    if not isVillageOwner(player) then return end
                    -- Check if player has a held gem
                    local heldGem = GoldMineState.playerHeldGem[player.UserId]
                    if heldGem then
                        -- Check if slot is empty
                        if not TownHallState.jewelCase.slots[slotNum] then
                            -- Place gem
                            TownHallState.jewelCase.slots[slotNum] = heldGem
                            GoldMineState.playerHeldGem[player.UserId] = nil

                            -- Update visual
                            gemVisual.Color = heldGem.color
                            gemVisual.Transparency = 0

                            -- Size based on gem size
                            local sizeMap = { Chip = 0.6, Stone = 0.8, Gem = 1.0, Jewel = 1.4 }
                            local visualSize = sizeMap[heldGem.size] or 1.0
                            gemVisual.Size = Vector3.new(visualSize, visualSize, visualSize)

                            print(string.format("[TownHall] %s placed a %s %s in slot %d!",
                                player.Name, heldGem.size, heldGem.type, slotNum))
                            print(string.format("  Bonus: +%.0f%% %s", (heldGem.multiplier - 1) * 100, heldGem.boost))

                            -- Update bonuses display
                            local bonuses = calculateGemBonuses()
                            print(string.format("[TownHall] Current bonuses: Production %.2fx, Speed %.2fx, Defense %.2fx",
                                bonuses.production, bonuses.speed, bonuses.defense))
                        else
                            print(string.format("[TownHall] Slot %d already has a gem!", slotNum))
                        end
                    else
                        print(string.format("[TownHall] %s: No gem to place! Prospect gems at the Gold Mine.", player.Name))
                    end
                end)
            else
                -- Locked slot - show padlock
                local lockBillboard = Instance.new("BillboardGui")
                lockBillboard.Name = "LockIndicator"
                lockBillboard.Size = UDim2.new(0, 50, 0, 50)
                lockBillboard.StudsOffset = Vector3.new(0, 1, 0)
                lockBillboard.Parent = pedestal

                local lockLabel = Instance.new("TextLabel")
                lockLabel.Name = "LockIcon"
                lockLabel.Size = UDim2.new(1, 0, 1, 0)
                lockLabel.BackgroundTransparency = 1
                lockLabel.Text = "🔒"
                lockLabel.TextScaled = true
                lockLabel.Font = Enum.Font.GothamBold
                lockLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
                lockLabel.Parent = lockBillboard

                -- Locked slot purchase prompt
                local cost = GemSlotCosts[slotNum]
                if cost then
                    local unlockPrompt = Instance.new("ProximityPrompt")
                    unlockPrompt.Name = "UnlockSlotPrompt_" .. slotNum
                    unlockPrompt.ObjectText = "Locked Slot"
                    unlockPrompt.ActionText = string.format("Unlock (%d Gold)", cost.gold)
                    unlockPrompt.HoldDuration = 1.0
                    unlockPrompt.MaxActivationDistance = 6
                    unlockPrompt.Parent = pedestal

                    unlockPrompt.Triggered:Connect(function(player)
                        if not isVillageOwner(player) then return end
                        -- Check if previous slots are unlocked
                        if TownHallState.jewelCase.maxSlots < slotNum - 1 then
                            print(string.format("[TownHall] Must unlock slot %d first!", slotNum - 1))
                            return
                        end

                        if not deductPlayerResources(player, {gold = cost.gold}, "TownHall") then return end
                        print(string.format("[TownHall] %s unlocked gem slot %d for %d gold!",
                            player.Name, slotNum, cost.gold))
                        TownHallState.jewelCase.maxSlots = slotNum

                        -- Update visuals - remove lock, add interaction
                        lockBillboard:Destroy()
                        unlockPrompt:Destroy()

                        -- Add new interaction prompt
                        local newPrompt = Instance.new("ProximityPrompt")
                        newPrompt.Name = "GemSlotPrompt_" .. slotNum
                        newPrompt.ObjectText = "Gem Slot " .. slotNum
                        newPrompt.ActionText = "Place Gem"
                        newPrompt.HoldDuration = 0.5
                        newPrompt.Parent = pedestal
                    end)
                end
            end
        end
    end

    -- Trophy case label
    local trophyLabel = Instance.new("Part")
    trophyLabel.Name = "TrophyCaseLabel"
    trophyLabel.Size = Vector3.new(10, 1.5, 0.2)
    trophyLabel.Position = Vector3.new(baseX, GROUND_Y + 13, baseZ - 48)
    trophyLabel.Anchored = true
    trophyLabel.Material = Enum.Material.SmoothPlastic
    trophyLabel.Color = Color3.fromRGB(180, 160, 50)
    trophyLabel.Parent = townHallModel

    local trophyLabelGui = Instance.new("SurfaceGui")
    trophyLabelGui.Face = Enum.NormalId.Front
    trophyLabelGui.Parent = trophyLabel

    local trophyLabelText = Instance.new("TextLabel")
    trophyLabelText.Size = UDim2.new(1, 0, 1, 0)
    trophyLabelText.BackgroundTransparency = 1
    trophyLabelText.Text = "JEWEL TROPHY CASE"
    trophyLabelText.TextScaled = true
    trophyLabelText.Font = Enum.Font.GothamBold
    trophyLabelText.TextColor3 = Color3.fromRGB(255, 255, 255)
    trophyLabelText.Parent = trophyLabelGui
    makeSignDoubleSided(trophyLabel)

    -- ========================================================================
    -- NEW STATION 2: BUILDING UPGRADE CENTER
    -- ========================================================================

    -- Upgrade center desk (left side of hall)
    local upgradeDesk = Instance.new("Part")
    upgradeDesk.Name = "UpgradeDesk"
    upgradeDesk.Size = Vector3.new(8, 3, 5)
    upgradeDesk.Position = Vector3.new(baseX - 25, GROUND_Y + 1.5, baseZ + 10)
    upgradeDesk.Anchored = true
    upgradeDesk.Material = Enum.Material.Wood
    upgradeDesk.Color = Color3.fromRGB(90, 65, 45)
    upgradeDesk.Parent = townHallModel

    -- Blueprint rolls on desk
    for i = 1, 3 do
        local blueprint = Instance.new("Part")
        blueprint.Name = "Blueprint" .. i
        blueprint.Shape = Enum.PartType.Cylinder
        blueprint.Size = Vector3.new(0.4, 2 + i * 0.3, 0.4)
        blueprint.Position = Vector3.new(baseX - 27 + i * 1.5, GROUND_Y + 3.2, baseZ + 10)
        blueprint.Orientation = Vector3.new(0, 0, 90)
        blueprint.Anchored = true
        blueprint.Material = Enum.Material.SmoothPlastic
        blueprint.Color = Color3.fromRGB(240, 230, 200)
        blueprint.Parent = townHallModel
    end

    -- Sign
    createSign(townHallModel, "BUILDING UPGRADES", Vector3.new(baseX - 25, GROUND_Y + 5.5, baseZ + 10), Vector3.new(8, 1, 0.3))

    -- Upgrade center interaction
    local upgradePrompt = Instance.new("ProximityPrompt")
    upgradePrompt.Name = "UpgradeCenterPrompt"
    upgradePrompt.ObjectText = "Upgrade Center"
    upgradePrompt.ActionText = "View Upgrades"
    upgradePrompt.HoldDuration = 0.3
    upgradePrompt.MaxActivationDistance = 10
    upgradePrompt.Parent = upgradeDesk

    -- Building display names for upgrade center GUI
    local buildingDisplayNames = {
        goldMine = "Gold Mine",
        lumberMill = "Lumber Mill",
        barracks = "Barracks",
        farm1 = "Farm 1",
        farm2 = "Farm 2",
        farm3 = "Farm 3",
        farm4 = "Farm 4",
        farm5 = "Farm 5",
        farm6 = "Farm 6",
    }

    local buildingOrder = { "goldMine", "lumberMill", "barracks", "farm1", "farm2", "farm3", "farm4", "farm5", "farm6" }

    -- Active upgrade center GUIs per player
    local activeUpgradeCenterGuis = {} -- [userId] = ScreenGui

    -- Number formatting with commas
    local function formatNumber(n)
        local formatted = tostring(math.floor(n))
        local k
        while true do
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
            if k == 0 then break end
        end
        return formatted
    end

    -- Create the upgrade center GUI for a player
    local function createUpgradeCenterGui(player)
        -- Destroy existing GUI if open
        if activeUpgradeCenterGuis[player.UserId] then
            activeUpgradeCenterGuis[player.UserId]:Destroy()
            activeUpgradeCenterGuis[player.UserId] = nil
        end

        local playerGui = player:FindFirstChild("PlayerGui")
        if not playerGui then return end

        -- Create ScreenGui
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "UpgradeCenterMenu"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = playerGui
        activeUpgradeCenterGuis[player.UserId] = screenGui

        -- Main frame
        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = UDim2.new(0, 480, 0, 600)
        mainFrame.Position = UDim2.new(0.5, -240, 0.5, -300)
        mainFrame.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
        mainFrame.BorderSizePixel = 3
        mainFrame.BorderColor3 = Color3.fromRGB(255, 200, 50)
        mainFrame.Parent = screenGui

        -- Title bar
        local titleBar = Instance.new("Frame")
        titleBar.Name = "TitleBar"
        titleBar.Size = UDim2.new(1, 0, 0, 50)
        titleBar.Position = UDim2.new(0, 0, 0, 0)
        titleBar.BackgroundColor3 = Color3.fromRGB(50, 40, 30)
        titleBar.BorderSizePixel = 0
        titleBar.Parent = mainFrame

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(0.85, 0, 1, 0)
        title.Position = UDim2.new(0, 0, 0, 0)
        title.BackgroundTransparency = 1
        title.Text = "UPGRADE CENTER"
        title.TextColor3 = Color3.fromRGB(255, 215, 0)
        title.TextScaled = true
        title.Font = Enum.Font.GothamBold
        title.Parent = titleBar

        -- X close button in title bar
        local xButton = Instance.new("TextButton")
        xButton.Name = "XClose"
        xButton.Size = UDim2.new(0, 40, 0, 40)
        xButton.Position = UDim2.new(1, -45, 0, 5)
        xButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        xButton.BorderSizePixel = 0
        xButton.Text = "X"
        xButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        xButton.TextScaled = true
        xButton.Font = Enum.Font.GothamBold
        xButton.Parent = titleBar

        -- Scrolling frame for content
        local scrollFrame = Instance.new("ScrollingFrame")
        scrollFrame.Name = "Content"
        scrollFrame.Size = UDim2.new(1, -10, 1, -110) -- Leave room for title and bottom close
        scrollFrame.Position = UDim2.new(0, 5, 0, 55)
        scrollFrame.BackgroundTransparency = 1
        scrollFrame.BorderSizePixel = 0
        scrollFrame.ScrollBarThickness = 8
        scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(255, 200, 50)
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0) -- Will be set after adding content
        scrollFrame.Parent = mainFrame

        local yOffset = 5

        -- ======== TOWN HALL UPGRADE CARD ========
        local thCard = Instance.new("Frame")
        thCard.Name = "TownHallCard"
        thCard.Size = UDim2.new(0.97, 0, 0, 130)
        thCard.Position = UDim2.new(0.015, 0, 0, yOffset)
        thCard.BackgroundColor3 = Color3.fromRGB(50, 40, 30)
        thCard.BorderSizePixel = 2
        thCard.BorderColor3 = Color3.fromRGB(255, 215, 0)
        thCard.Parent = scrollFrame

        local thTitle = Instance.new("TextLabel")
        thTitle.Size = UDim2.new(0.75, 0, 0, 30)
        thTitle.Position = UDim2.new(0.02, 0, 0, 5)
        thTitle.BackgroundTransparency = 1
        thTitle.Text = string.format("TOWN HALL  Level %d", TownHallState.level)
        thTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
        thTitle.TextXAlignment = Enum.TextXAlignment.Left
        thTitle.TextScaled = true
        thTitle.Font = Enum.Font.GothamBold
        thTitle.Parent = thCard

        -- Crown icon label
        local crownLabel = Instance.new("TextLabel")
        crownLabel.Size = UDim2.new(0, 30, 0, 30)
        crownLabel.Position = UDim2.new(1, -35, 0, 5)
        crownLabel.BackgroundTransparency = 1
        crownLabel.Text = "♛"
        crownLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
        crownLabel.TextScaled = true
        crownLabel.Font = Enum.Font.GothamBold
        crownLabel.Parent = thCard

        -- Current storage display
        local currentCap = DataService and DataService:GetStorageCapacityForTH(TownHallState.level)
        local capText = currentCap
            and string.format("Storage: %sg / %sw / %sf",
                formatNumber(currentCap.gold), formatNumber(currentCap.wood), formatNumber(currentCap.food))
            or "Storage: --"

        local thStorageLabel = Instance.new("TextLabel")
        thStorageLabel.Size = UDim2.new(0.96, 0, 0, 22)
        thStorageLabel.Position = UDim2.new(0.02, 0, 0, 35)
        thStorageLabel.BackgroundTransparency = 1
        thStorageLabel.Text = capText
        thStorageLabel.TextColor3 = Color3.fromRGB(200, 200, 180)
        thStorageLabel.TextXAlignment = Enum.TextXAlignment.Left
        thStorageLabel.TextScaled = true
        thStorageLabel.Font = Enum.Font.Gotham
        thStorageLabel.Parent = thCard

        -- Next level storage
        local nextCap = DataService and DataService:GetStorageCapacityForTH(TownHallState.level + 1)
        if TownHallState.level < 10 and nextCap then
            local nextCapLabel = Instance.new("TextLabel")
            nextCapLabel.Size = UDim2.new(0.96, 0, 0, 22)
            nextCapLabel.Position = UDim2.new(0.02, 0, 0, 57)
            nextCapLabel.BackgroundTransparency = 1
            nextCapLabel.Text = string.format("Next: %sg / %sw / %sf",
                formatNumber(nextCap.gold), formatNumber(nextCap.wood), formatNumber(nextCap.food))
            nextCapLabel.TextColor3 = Color3.fromRGB(150, 200, 150)
            nextCapLabel.TextXAlignment = Enum.TextXAlignment.Left
            nextCapLabel.TextScaled = true
            nextCapLabel.Font = Enum.Font.Gotham
            nextCapLabel.Parent = thCard
        end

        -- TH upgrade button or MAX label
        if TownHallState.level >= 10 then
            local maxLabel = Instance.new("TextLabel")
            maxLabel.Size = UDim2.new(0.96, 0, 0, 32)
            maxLabel.Position = UDim2.new(0.02, 0, 0, 88)
            maxLabel.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
            maxLabel.BorderSizePixel = 0
            maxLabel.Text = "MAX LEVEL"
            maxLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
            maxLabel.TextScaled = true
            maxLabel.Font = Enum.Font.GothamBold
            maxLabel.Parent = thCard
        else
            local thCost = TownHallUpgradeCosts[TownHallState.level]
            local thUpgradeBtn = Instance.new("TextButton")
            thUpgradeBtn.Name = "THUpgradeButton"
            thUpgradeBtn.Size = UDim2.new(0.96, 0, 0, 32)
            thUpgradeBtn.Position = UDim2.new(0.02, 0, 0, 88)
            thUpgradeBtn.BackgroundColor3 = Color3.fromRGB(80, 150, 80)
            thUpgradeBtn.BorderSizePixel = 0
            thUpgradeBtn.Text = thCost
                and string.format("UPGRADE TO LEVEL %d - %s gold", TownHallState.level + 1, formatNumber(thCost.gold))
                or "UPGRADE"
            thUpgradeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            thUpgradeBtn.TextScaled = true
            thUpgradeBtn.Font = Enum.Font.GothamBold
            thUpgradeBtn.Parent = thCard

            thUpgradeBtn.MouseButton1Click:Connect(function()
                if TownHallState.level >= 10 then return end
                local cost = TownHallUpgradeCosts[TownHallState.level]
                if not cost then return end
                if not deductPlayerResources(player, cost, "TownHallUpgrade") then return end

                TownHallState.level = TownHallState.level + 1
                TownHallState.xpToNextLevel = math.floor(TownHallState.xpToNextLevel * 1.5)
                TownHallState.population = TownHallState.population + 5
                print(string.format("[TownHall] %s upgraded Town Hall to level %d!", player.Name, TownHallState.level))

                -- Sync to DataService
                if DataService and _villageOwnerUserId then
                    local ownerPlayer = Players:GetPlayerByUserId(_villageOwnerUserId)
                    if ownerPlayer then
                        local playerData = DataService:GetPlayerData(ownerPlayer)
                        if playerData then
                            playerData.townHallLevel = TownHallState.level
                            local cap = DataService:GetStorageCapacityForTH(TownHallState.level)
                            if cap then
                                playerData.storageCapacity = { gold = cap.gold, wood = cap.wood, food = cap.food }
                            end
                            -- Sync HUD
                            local Events = ReplicatedStorage:FindFirstChild("Events")
                            if Events then
                                local SyncPlayerData = Events:FindFirstChild("SyncPlayerData")
                                if SyncPlayerData then SyncPlayerData:FireClient(player, playerData) end
                            end
                        end
                    end
                end

                -- Refresh GUI
                createUpgradeCenterGui(player)
            end)
        end

        yOffset = yOffset + 140

        -- ======== BUILDING UPGRADES SEPARATOR ========
        local separator = Instance.new("TextLabel")
        separator.Size = UDim2.new(0.97, 0, 0, 25)
        separator.Position = UDim2.new(0.015, 0, 0, yOffset)
        separator.BackgroundTransparency = 1
        separator.Text = "--- BUILDING UPGRADES ---"
        separator.TextColor3 = Color3.fromRGB(180, 160, 120)
        separator.TextScaled = true
        separator.Font = Enum.Font.GothamBold
        separator.Parent = scrollFrame

        yOffset = yOffset + 30

        -- ======== BUILDING UPGRADE CARDS ========
        for _, buildingName in ipairs(buildingOrder) do
            local displayName = buildingDisplayNames[buildingName]
            local config = BuildingUpgradeCosts[buildingName]
            if not config then continue end

            local level = TownHallState.buildingLevels[buildingName] or 1
            local maxLevel = config.maxLevel
            local bonus = (level - 1) * 10

            local card = Instance.new("Frame")
            card.Name = buildingName .. "Card"
            card.Size = UDim2.new(0.97, 0, 0, 90)
            card.Position = UDim2.new(0.015, 0, 0, yOffset)
            card.BackgroundColor3 = Color3.fromRGB(45, 40, 35)
            card.BorderSizePixel = 2
            card.BorderColor3 = Color3.fromRGB(180, 160, 120)
            card.Parent = scrollFrame

            -- Building name + level
            local cardTitle = Instance.new("TextLabel")
            cardTitle.Size = UDim2.new(0.55, 0, 0, 25)
            cardTitle.Position = UDim2.new(0.02, 0, 0, 5)
            cardTitle.BackgroundTransparency = 1
            cardTitle.Text = string.format("%s  Lv.%d/%d", displayName, level, maxLevel)
            cardTitle.TextColor3 = Color3.fromRGB(255, 200, 50)
            cardTitle.TextXAlignment = Enum.TextXAlignment.Left
            cardTitle.TextScaled = true
            cardTitle.Font = Enum.Font.GothamBold
            cardTitle.Parent = card

            -- Bonus display
            local bonusLabel = Instance.new("TextLabel")
            bonusLabel.Size = UDim2.new(0.4, 0, 0, 25)
            bonusLabel.Position = UDim2.new(0.58, 0, 0, 5)
            bonusLabel.BackgroundTransparency = 1
            bonusLabel.Text = string.format("+%d%% bonus", bonus)
            bonusLabel.TextColor3 = Color3.fromRGB(150, 200, 150)
            bonusLabel.TextXAlignment = Enum.TextXAlignment.Right
            bonusLabel.TextScaled = true
            bonusLabel.Font = Enum.Font.Gotham
            bonusLabel.Parent = card

            if level >= maxLevel then
                -- MAX LEVEL label
                local maxLabel = Instance.new("TextLabel")
                maxLabel.Size = UDim2.new(0.96, 0, 0, 28)
                maxLabel.Position = UDim2.new(0.02, 0, 0, 32)
                maxLabel.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
                maxLabel.BorderSizePixel = 0
                maxLabel.Text = "MAX LEVEL"
                maxLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
                maxLabel.TextScaled = true
                maxLabel.Font = Enum.Font.GothamBold
                maxLabel.Parent = card

                card.Size = UDim2.new(0.97, 0, 0, 70)
            else
                local cost = getUpgradeCost(buildingName, level)
                -- Cost display
                local costParts = {}
                if cost then
                    if cost.gold then table.insert(costParts, formatNumber(cost.gold) .. "g") end
                    if cost.wood then table.insert(costParts, formatNumber(cost.wood) .. "w") end
                    if cost.food then table.insert(costParts, formatNumber(cost.food) .. "f") end
                end

                local costLabel = Instance.new("TextLabel")
                costLabel.Size = UDim2.new(0.96, 0, 0, 22)
                costLabel.Position = UDim2.new(0.02, 0, 0, 32)
                costLabel.BackgroundTransparency = 1
                costLabel.Text = "Cost: " .. table.concat(costParts, ", ")
                costLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
                costLabel.TextXAlignment = Enum.TextXAlignment.Left
                costLabel.TextScaled = true
                costLabel.Font = Enum.Font.Gotham
                costLabel.Parent = card

                -- Upgrade button
                local upgradeBtn = Instance.new("TextButton")
                upgradeBtn.Name = "UpgradeButton"
                upgradeBtn.Size = UDim2.new(0.96, 0, 0, 28)
                upgradeBtn.Position = UDim2.new(0.02, 0, 0, 56)
                upgradeBtn.BackgroundColor3 = Color3.fromRGB(80, 150, 80)
                upgradeBtn.BorderSizePixel = 0
                upgradeBtn.Text = "UPGRADE"
                upgradeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                upgradeBtn.TextScaled = true
                upgradeBtn.Font = Enum.Font.GothamBold
                upgradeBtn.Parent = card

                -- Capture buildingName in closure
                local bName = buildingName
                upgradeBtn.MouseButton1Click:Connect(function()
                    local curLevel = TownHallState.buildingLevels[bName] or 1
                    local upgCost = getUpgradeCost(bName, curLevel)
                    if not upgCost then return end
                    if not deductPlayerResources(player, upgCost, "BuildingUpgrade") then return end

                    TownHallState.buildingLevels[bName] = curLevel + 1
                    local newLevel = TownHallState.buildingLevels[bName]
                    print(string.format("[TownHall] %s upgraded %s to Level %d! (+%d%% bonus)",
                        player.Name, buildingDisplayNames[bName], newLevel, (newLevel - 1) * 10))

                    addTownHallXP(50 * newLevel)

                    -- Refresh GUI
                    createUpgradeCenterGui(player)
                end)
            end

            yOffset = yOffset + (level >= maxLevel and 75 or 95)
        end

        -- Update canvas size to fit all content
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, yOffset + 10)

        -- Bottom close button
        local closeButton = Instance.new("TextButton")
        closeButton.Name = "CloseButton"
        closeButton.Size = UDim2.new(0.5, 0, 0, 40)
        closeButton.Position = UDim2.new(0.25, 0, 1, -50)
        closeButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        closeButton.BorderSizePixel = 0
        closeButton.Text = "CLOSE"
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeButton.TextScaled = true
        closeButton.Font = Enum.Font.GothamBold
        closeButton.Parent = mainFrame

        -- Close handlers
        local function closeGui()
            screenGui:Destroy()
            activeUpgradeCenterGuis[player.UserId] = nil
        end

        closeButton.MouseButton1Click:Connect(closeGui)
        xButton.MouseButton1Click:Connect(closeGui)
    end

    -- Cleanup GUI when player leaves
    Players.PlayerRemoving:Connect(function(leavingPlayer)
        if activeUpgradeCenterGuis[leavingPlayer.UserId] then
            activeUpgradeCenterGuis[leavingPlayer.UserId]:Destroy()
            activeUpgradeCenterGuis[leavingPlayer.UserId] = nil
        end
    end)

    upgradePrompt.Triggered:Connect(function(player)
        if not isVillageOwner(player) then return end
        createUpgradeCenterGui(player)
        print(string.format("[TownHall] %s opened Upgrade Center", player.Name))
    end)

    -- ========================================================================
    -- NEW STATION 3: SHIELD CONTROL CENTER
    -- ========================================================================

    -- Shield control panel (right side of hall)
    local shieldPanel = Instance.new("Part")
    shieldPanel.Name = "ShieldControlPanel"
    shieldPanel.Size = Vector3.new(6, 6, 2)
    shieldPanel.Position = Vector3.new(baseX + 25, GROUND_Y + 3, baseZ + 10)
    shieldPanel.Anchored = true
    shieldPanel.Material = Enum.Material.Metal
    shieldPanel.Color = Color3.fromRGB(60, 60, 70)
    shieldPanel.Parent = townHallModel

    -- Shield status display
    local shieldStatusGui = Instance.new("SurfaceGui")
    shieldStatusGui.Name = "ShieldStatusGui"
    shieldStatusGui.Face = Enum.NormalId.Front
    shieldStatusGui.Parent = shieldPanel

    local shieldStatusFrame = Instance.new("Frame")
    shieldStatusFrame.Size = UDim2.new(1, 0, 1, 0)
    shieldStatusFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    shieldStatusFrame.Parent = shieldStatusGui

    local shieldStatusLabel = Instance.new("TextLabel")
    shieldStatusLabel.Name = "StatusLabel"
    shieldStatusLabel.Size = UDim2.new(1, 0, 0.4, 0)
    shieldStatusLabel.Position = UDim2.new(0, 0, 0.1, 0)
    shieldStatusLabel.BackgroundTransparency = 1
    shieldStatusLabel.Text = "SHIELDS: OFFLINE"
    shieldStatusLabel.TextScaled = true
    shieldStatusLabel.Font = Enum.Font.Code
    shieldStatusLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
    shieldStatusLabel.Parent = shieldStatusFrame

    local shieldTimeLabel = Instance.new("TextLabel")
    shieldTimeLabel.Name = "TimeLabel"
    shieldTimeLabel.Size = UDim2.new(1, 0, 0.3, 0)
    shieldTimeLabel.Position = UDim2.new(0, 0, 0.55, 0)
    shieldTimeLabel.BackgroundTransparency = 1
    shieldTimeLabel.Text = ""
    shieldTimeLabel.TextScaled = true
    shieldTimeLabel.Font = Enum.Font.Code
    shieldTimeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    shieldTimeLabel.Parent = shieldStatusFrame
    makeSignDoubleSided(shieldPanel)

    -- Update shield status visuals
    local function updateShieldStatusVisuals()
        if TownHallState.shields.isActive then
            local remaining = TownHallState.shields.endTime - tick()
            if remaining > 0 then
                shieldStatusLabel.Text = "SHIELDS: ONLINE"
                shieldStatusLabel.TextColor3 = Color3.fromRGB(50, 255, 50)
                local hours = math.floor(remaining / 3600)
                local minutes = math.floor((remaining % 3600) / 60)
                shieldTimeLabel.Text = string.format("Time: %dh %dm", hours, minutes)
            else
                TownHallState.shields.isActive = false
                shieldStatusLabel.Text = "SHIELDS: OFFLINE"
                shieldStatusLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
                shieldTimeLabel.Text = ""
            end
        else
            shieldStatusLabel.Text = "SHIELDS: OFFLINE"
            shieldStatusLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
            shieldTimeLabel.Text = ""
        end
    end
    TownHallState.updateShieldStatusVisuals = updateShieldStatusVisuals

    -- Sign
    createSign(townHallModel, "SHIELD CONTROL", Vector3.new(baseX + 25, GROUND_Y + 7, baseZ + 10), Vector3.new(7, 1, 0.3))

    -- Shield activation prompt
    local shieldPrompt = Instance.new("ProximityPrompt")
    shieldPrompt.Name = "ShieldControlPrompt"
    shieldPrompt.ObjectText = "Shield Control"
    shieldPrompt.ActionText = "Manage Shields"
    shieldPrompt.HoldDuration = 0.3
    shieldPrompt.MaxActivationDistance = 10
    shieldPrompt.Parent = shieldPanel

    shieldPrompt.Triggered:Connect(function(player)
        if not isVillageOwner(player) then return end
        print("[TownHall] === SHIELD CONTROL CENTER ===")
        if TownHallState.shields.isActive then
            local remaining = TownHallState.shields.endTime - tick()
            local hours = math.floor(remaining / 3600)
            local minutes = math.floor((remaining % 3600) / 60)
            print(string.format("  Shield ACTIVE: %dh %dm remaining", hours, minutes))
        else
            print("  Shield OFFLINE")
            print("")
            print("  Available Shield Options:")
            for i, option in ipairs(ShieldOptions) do
                print(string.format("    %d. %s (%d hours) - %d Gold",
                    i, option.name, option.duration / 3600, option.cost.gold))
            end
            print("")
            print("  [Shield activation coming soon - use interaction for demo]")

            -- Demo: Activate 1-hour shield
            TownHallState.shields.isActive = true
            TownHallState.shields.duration = 3600
            TownHallState.shields.endTime = tick() + 3600
            updateShieldStatusVisuals()
            print("  [DEMO] 1-hour shield activated!")
        end
    end)

    -- Shield status update loop
    task.spawn(function()
        while true do
            task.wait(60) -- Update every minute
            if TownHallState.updateShieldStatusVisuals then
                TownHallState.updateShieldStatusVisuals()
            end
        end
    end)

    -- ========================================================================
    -- NEW STATION 4: RESEARCH STATION (Future expansion placeholder)
    -- ========================================================================

    -- Research desk (near throne)
    local researchDesk = Instance.new("Part")
    researchDesk.Name = "ResearchDesk"
    researchDesk.Size = Vector3.new(5, 3, 3)
    researchDesk.Position = Vector3.new(baseX - 10, GROUND_Y + 1.5, baseZ - 30)
    researchDesk.Anchored = true
    researchDesk.Material = Enum.Material.Wood
    researchDesk.Color = Color3.fromRGB(70, 50, 35)
    researchDesk.Parent = townHallModel

    -- Ancient books
    for i = 1, 4 do
        local book = Instance.new("Part")
        book.Name = "ResearchBook" .. i
        book.Size = Vector3.new(0.8, 0.2, 0.6)
        book.Position = Vector3.new(baseX - 11 + i * 0.9, GROUND_Y + 3.15, baseZ - 30)
        book.Anchored = true
        book.Material = Enum.Material.Fabric
        book.Color = Color3.fromRGB(60 + i * 20, 40 + i * 10, 30)
        book.Parent = townHallModel
    end

    -- Sign
    createSign(townHallModel, "RESEARCH", Vector3.new(baseX - 10, GROUND_Y + 5, baseZ - 30), Vector3.new(5, 0.8, 0.3))

    local researchPrompt = Instance.new("ProximityPrompt")
    researchPrompt.Name = "ResearchPrompt"
    researchPrompt.ObjectText = "Research Station"
    researchPrompt.ActionText = "View Research"
    researchPrompt.HoldDuration = 0.3
    researchPrompt.MaxActivationDistance = 8
    researchPrompt.Parent = researchDesk

    -- Track selected research for each player
    local selectedResearch = {}  -- [playerId] = researchId
    local lastResearchInteraction = {}  -- [playerId] = tick()

    -- Check if research prerequisites are met
    local function hasPrerequisites(researchId)
        local research = ResearchTree[researchId]
        if not research then return false end

        for _, prereqId in ipairs(research.prerequisites) do
            local found = false
            for _, completedId in ipairs(TownHallState.research.completed) do
                if completedId == prereqId then
                    found = true
                    break
                end
            end
            if not found then return false end
        end
        return true
    end

    -- Check if research is already completed
    local function isResearchCompleted(researchId)
        for _, completedId in ipairs(TownHallState.research.completed) do
            if completedId == researchId then
                return true
            end
        end
        return false
    end

    -- Get available research (prerequisites met, not completed, TH level met)
    local function getAvailableResearch()
        local available = {}
        for researchId, research in pairs(ResearchTree) do
            if not isResearchCompleted(researchId)
               and hasPrerequisites(researchId)
               and TownHallState.level >= research.thRequired then
                table.insert(available, researchId)
            end
        end
        -- Sort by category for consistent display
        table.sort(available, function(a, b)
            return ResearchTree[a].category < ResearchTree[b].category
        end)
        return available
    end

    -- Start research
    local function startResearch(player, researchId)
        local research = ResearchTree[researchId]
        if not research then
            print(string.format("[Research] %s: Invalid research ID", player.Name))
            return false
        end

        if TownHallState.research.inProgress then
            print(string.format("[Research] %s: Research already in progress!", player.Name))
            return false
        end

        if isResearchCompleted(researchId) then
            print(string.format("[Research] %s: %s already completed!", player.Name, research.name))
            return false
        end

        if not hasPrerequisites(researchId) then
            print(string.format("[Research] %s: Prerequisites not met for %s", player.Name, research.name))
            return false
        end

        if TownHallState.level < research.thRequired then
            print(string.format("[Research] %s: Town Hall level %d required (you have %d)",
                player.Name, research.thRequired, TownHallState.level))
            return false
        end

        -- Check resources
        local cost = research.cost
        local hasGold = not cost.gold or GoldMineState.chestGold >= cost.gold
        local hasWood = not cost.wood or LumberMillState.woodStorage >= cost.wood
        local hasFood = not cost.food or FarmState.foodStorage >= cost.food

        if not hasGold or not hasWood or not hasFood then
            print(string.format("[Research] %s: Insufficient resources for %s!", player.Name, research.name))
            local needParts = {}
            if cost.gold then table.insert(needParts, string.format("%d Gold", cost.gold)) end
            if cost.wood then table.insert(needParts, string.format("%d Wood", cost.wood)) end
            if cost.food then table.insert(needParts, string.format("%d Food", cost.food)) end
            print(string.format("  Need: %s", table.concat(needParts, ", ")))
            return false
        end

        -- Deduct resources
        if cost.gold then GoldMineState.chestGold = GoldMineState.chestGold - cost.gold end
        if cost.wood then LumberMillState.woodStorage = LumberMillState.woodStorage - cost.wood end
        if cost.food then FarmState.foodStorage = FarmState.foodStorage - cost.food end

        -- Start research
        local now = tick()
        TownHallState.research.inProgress = {
            id = researchId,
            startTime = now,
            endTime = now + research.duration,
        }

        local minutes = math.floor(research.duration / 60)
        local seconds = research.duration % 60
        print("[Research] ========== RESEARCH STARTED! ==========")
        print(string.format("  Researching: %s", research.name))
        print(string.format("  Time: %dm %ds", minutes, seconds))
        print(string.format("  Bonus: %s", research.description))
        print("=================================================")

        return true
    end

    -- Complete research (called by timer)
    local function completeResearch()
        if not TownHallState.research.inProgress then return end

        local researchId = TownHallState.research.inProgress.id
        local research = ResearchTree[researchId]

        if research then
            table.insert(TownHallState.research.completed, researchId)
            print("[Research] ========== RESEARCH COMPLETE! ==========")
            print(string.format("  Completed: %s", research.name))
            print(string.format("  UNLOCKED: %s", research.description))
            print("===================================================")

            -- Add Town Hall XP
            addTownHallXP(100)

            -- Notify all connected players about research completion
            local Events = ReplicatedStorage:FindFirstChild("Events")
            if Events then
                local researchUpdateEvent = Events:FindFirstChild("ResearchUpdate")
                if researchUpdateEvent then
                    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
                        researchUpdateEvent:FireClient(p, {
                            action = "completed",
                            researchId = researchId,
                            name = research.name,
                            description = research.description,
                        })
                    end
                end
            end
        end

        TownHallState.research.inProgress = nil
    end

    -- Research timer loop
    task.spawn(function()
        while true do
            task.wait(1) -- Check every second
            if TownHallState.research.inProgress then
                local now = tick()
                if now >= TownHallState.research.inProgress.endTime then
                    completeResearch()
                end
            end
        end
    end)

    -- Get research RemoteEvents from Events folder
    local ResearchEvents = {}
    task.defer(function()
        local Events = ReplicatedStorage:FindFirstChild("Events")
        if Events then
            ResearchEvents.OpenResearchUI = Events:FindFirstChild("OpenResearchUI")
            ResearchEvents.StartResearchRequest = Events:FindFirstChild("StartResearchRequest")
            ResearchEvents.ResearchUpdate = Events:FindFirstChild("ResearchUpdate")
        end
    end)

    researchPrompt.Triggered:Connect(function(player)
        if not isVillageOwner(player) then return end
        -- Gather research data to send to client
        local researchData = {
            townHallLevel = TownHallState.level,
            completed = TownHallState.research.completed,
            inProgress = nil,
            available = {},
            allResearch = {},
            resources = {
                gold = GoldMineState.chestGold,
                wood = LumberMillState.woodStorage,
                food = FarmState.foodStorage,
            },
        }

        -- In-progress research
        if TownHallState.research.inProgress then
            local inProgress = TownHallState.research.inProgress
            local research = ResearchTree[inProgress.id]
            local remaining = math.max(0, inProgress.endTime - tick())
            researchData.inProgress = {
                id = inProgress.id,
                name = research and research.name or "Unknown",
                description = research and research.description or "",
                category = research and research.category or "",
                remaining = remaining,
                duration = research and research.duration or 0,
            }
        end

        -- Available research
        local available = getAvailableResearch()
        for _, researchId in ipairs(available) do
            local research = ResearchTree[researchId]
            if research then
                table.insert(researchData.available, {
                    id = researchId,
                    name = research.name,
                    description = research.description,
                    category = research.category,
                    cost = research.cost,
                    duration = research.duration,
                    thRequired = research.thRequired,
                    prerequisites = research.prerequisites,
                })
            end
        end

        -- All research (for tree visualization)
        for researchId, research in pairs(ResearchTree) do
            researchData.allResearch[researchId] = {
                id = researchId,
                name = research.name,
                description = research.description,
                category = research.category,
                cost = research.cost,
                duration = research.duration,
                thRequired = research.thRequired,
                prerequisites = research.prerequisites,
                completed = isResearchCompleted(researchId),
                available = false, -- will be set below
            }
        end
        -- Mark available ones
        for _, avail in ipairs(researchData.available) do
            if researchData.allResearch[avail.id] then
                researchData.allResearch[avail.id].available = true
            end
        end

        -- Fire to client to open UI
        if ResearchEvents.OpenResearchUI then
            ResearchEvents.OpenResearchUI:FireClient(player, researchData)
        end
    end)

    -- Handle research start request from client UI
    if ResearchEvents.StartResearchRequest then
        ResearchEvents.StartResearchRequest.OnServerEvent:Connect(function(player, researchId)
            if not isVillageOwner(player) then return end
            if typeof(researchId) ~= "string" then return end

            local success = startResearch(player, researchId)

            -- Send updated research state back to client
            if success then
                local remaining = 0
                if TownHallState.research.inProgress then
                    remaining = math.max(0, TownHallState.research.inProgress.endTime - tick())
                end
                if ResearchEvents.ResearchUpdate then
                    ResearchEvents.ResearchUpdate:FireClient(player, {
                        action = "started",
                        researchId = researchId,
                        remaining = remaining,
                        resources = {
                            gold = GoldMineState.chestGold,
                            wood = LumberMillState.woodStorage,
                            food = FarmState.foodStorage,
                        },
                    })
                end
            else
                if ResearchEvents.ResearchUpdate then
                    ResearchEvents.ResearchUpdate:FireClient(player, {
                        action = "failed",
                        researchId = researchId,
                        error = "Could not start research. Check resources and prerequisites.",
                    })
                end
            end
        end)
    else
        -- Deferred setup for StartResearchRequest handler (events may not be ready yet)
        task.defer(function()
            local Events = ReplicatedStorage:FindFirstChild("Events")
            if not Events then
                task.wait(2)
                Events = ReplicatedStorage:FindFirstChild("Events")
            end
            if Events then
                local startEvent = Events:FindFirstChild("StartResearchRequest")
                if startEvent then
                    startEvent.OnServerEvent:Connect(function(player, researchId)
                        if not isVillageOwner(player) then return end
                        if typeof(researchId) ~= "string" then return end

                        local success = startResearch(player, researchId)

                        local updateEvent = Events:FindFirstChild("ResearchUpdate")
                        if success then
                            local remaining = 0
                            if TownHallState.research.inProgress then
                                remaining = math.max(0, TownHallState.research.inProgress.endTime - tick())
                            end
                            if updateEvent then
                                updateEvent:FireClient(player, {
                                    action = "started",
                                    researchId = researchId,
                                    remaining = remaining,
                                    resources = {
                                        gold = GoldMineState.chestGold,
                                        wood = LumberMillState.woodStorage,
                                        food = FarmState.foodStorage,
                                    },
                                })
                            end
                        else
                            if updateEvent then
                                updateEvent:FireClient(player, {
                                    action = "failed",
                                    researchId = researchId,
                                    error = "Could not start research. Check resources and prerequisites.",
                                })
                            end
                        end
                    end)
                end
            end
        end)
    end

    -- ========================================================================
    -- ADDITIONAL HELPER: Update positions for new layout
    -- ========================================================================
    TownHallState.positions = {
        jewelCase = Vector3.new(baseX, GROUND_Y + 6, baseZ - 47),
        upgradeCenter = Vector3.new(baseX - 25, GROUND_Y + 1.5, baseZ + 10),
        shieldControl = Vector3.new(baseX + 25, GROUND_Y + 3, baseZ + 10),
        research = Vector3.new(baseX - 10, GROUND_Y + 1.5, baseZ - 30),
        throne = Vector3.new(baseX, GROUND_Y, baseZ - 45),
    }

    -- (Old stations removed: Tax Office, Census Desk, Research Library,
    -- Treasury Vault, Advisor Quarters, Royal Archives)
    -- See commit history for original implementation
    -- ===== TOWN HALL DECORATIVE ENHANCEMENTS =====
    -- Tapestry/banners on walls
    local tapestryColors = {
        Color3.fromRGB(120, 20, 20),
        Color3.fromRGB(20, 50, 120),
        Color3.fromRGB(100, 80, 20),
    }
    for ti, tColor in tapestryColors do
        local tapestry = Instance.new("Part")
        tapestry.Name = "Tapestry" .. ti
        tapestry.Size = Vector3.new(0.15, 6, 3)
        tapestry.Position = Vector3.new(baseX - 20 + ti * 12, GROUND_Y + 6, baseZ - 28)
        tapestry.Anchored = true
        tapestry.Material = Enum.Material.Fabric
        tapestry.Color = tColor
        tapestry.CanCollide = false
        tapestry.Parent = townHallModel

        -- Gold trim at bottom
        local trimPart = Instance.new("Part")
        trimPart.Name = "TapestryTrim" .. ti
        trimPart.Size = Vector3.new(0.16, 0.3, 3)
        trimPart.Position = Vector3.new(baseX - 20 + ti * 12, GROUND_Y + 3, baseZ - 28)
        trimPart.Anchored = true
        trimPart.Material = Enum.Material.Metal
        trimPart.Color = Color3.fromRGB(200, 170, 50)
        trimPart.CanCollide = false
        trimPart.Parent = townHallModel
    end

    -- Book shelves along walls
    for _, shelfPos in {
        Vector3.new(baseX - 28, GROUND_Y, baseZ - 10),
        Vector3.new(baseX - 28, GROUND_Y, baseZ + 10),
        Vector3.new(baseX + 28, GROUND_Y, baseZ - 10),
        Vector3.new(baseX + 28, GROUND_Y, baseZ + 10),
    } do
        -- Shelf frame
        local shelf = Instance.new("Part")
        shelf.Name = "BookShelf"
        shelf.Size = Vector3.new(1.5, 6, 4)
        shelf.Position = shelfPos + Vector3.new(0, 3, 0)
        shelf.Anchored = true
        shelf.Material = Enum.Material.Wood
        shelf.Color = Color3.fromRGB(70, 48, 30)
        shelf.CanCollide = false
        shelf.Parent = townHallModel

        -- Books on shelves (colored blocks)
        local bookColors = {
            Color3.fromRGB(150, 30, 30),
            Color3.fromRGB(30, 80, 30),
            Color3.fromRGB(30, 30, 120),
            Color3.fromRGB(120, 100, 30),
        }
        for bi = 1, 4 do
            local book = Instance.new("Part")
            book.Name = "Book" .. bi
            book.Size = Vector3.new(0.8, 0.8, 0.4)
            book.Position = shelfPos + Vector3.new(0.3, 1 + bi * 1.2, (bi - 2.5) * 0.8)
            book.Anchored = true
            book.Material = Enum.Material.SmoothPlastic
            book.Color = bookColors[bi]
            book.CanCollide = false
            book.Parent = townHallModel
        end
    end

    -- Candelabra props
    for _, candlePos in {
        Vector3.new(baseX - 10, GROUND_Y + 3.5, baseZ - 15),
        Vector3.new(baseX + 10, GROUND_Y + 3.5, baseZ - 15),
    } do
        -- Base
        local candleBase = Instance.new("Part")
        candleBase.Name = "CandelabraBase"
        candleBase.Shape = Enum.PartType.Cylinder
        candleBase.Size = Vector3.new(0.3, 0.8, 0.8)
        candleBase.Position = candlePos
        candleBase.Anchored = true
        candleBase.Material = Enum.Material.Metal
        candleBase.Color = Color3.fromRGB(180, 150, 50)
        candleBase.CanCollide = false
        candleBase.Parent = townHallModel

        -- Arms and candles
        for ci = -1, 1 do
            local candle = Instance.new("Part")
            candle.Name = "Candle"
            candle.Size = Vector3.new(0.15, 0.8, 0.15)
            candle.Position = candlePos + Vector3.new(ci * 0.3, 0.6, 0)
            candle.Anchored = true
            candle.Material = Enum.Material.SmoothPlastic
            candle.Color = Color3.fromRGB(240, 230, 200)
            candle.CanCollide = false
            candle.Parent = townHallModel

            local flame = Instance.new("Fire")
            flame.Size = 1
            flame.Heat = 1
            flame.Parent = candle
        end
    end

    -- Parent the town hall interior
    townHallModel.Parent = interiorsFolder
    TownHallState.model = townHallModel

    print("  ✓ Town Hall created (CITY COMMAND CENTER):")
    print("    - Enter building in village to teleport inside")
    print("    - Jewel Trophy Case: Display gems for city-wide bonuses")
    print("    - Building Upgrade Center: Upgrade all buildings")
    print("    - Shield Control: Manage city defenses")
end

-- ============================================================================
-- DECORATIONS
-- ============================================================================

local function createDecorations()
    print("[8/8] Adding decorations...")

    -- Trees around the village
    local treePositions = {
        Vector3.new(15, GROUND_Y, 30),
        Vector3.new(105, GROUND_Y, 30),
        Vector3.new(10, GROUND_Y, 130),
        Vector3.new(110, GROUND_Y, 130),
        Vector3.new(5, GROUND_Y, 80),
        Vector3.new(115, GROUND_Y, 80),
    }

    for i, pos in treePositions do
        local tree = Instance.new("Model")
        tree.Name = "Tree" .. i

        -- Varied tree height
        local trunkHeight = 7 + (i % 3)
        local trunk = Instance.new("Part")
        trunk.Name = "Trunk"
        trunk.Size = Vector3.new(2.5, trunkHeight, 2.5)
        trunk.Position = pos + Vector3.new(0, trunkHeight/2, 0)
        trunk.Anchored = true
        trunk.Material = Enum.Material.Wood
        trunk.Color = Color3.fromRGB(75 + (i * 5) % 15, 50 + (i * 3) % 10, 30 + (i * 7) % 10)
        trunk.Parent = tree

        -- Main canopy (large)
        local greenShade = 100 + (i * 17) % 40
        local leaves = Instance.new("Part")
        leaves.Name = "Leaves"
        leaves.Shape = Enum.PartType.Ball
        leaves.Size = Vector3.new(9, 8, 9)
        leaves.Position = pos + Vector3.new(0, trunkHeight + 2, 0)
        leaves.Anchored = true
        leaves.Material = Enum.Material.Grass
        leaves.Color = Color3.fromRGB(45 + (i * 7) % 20, greenShade, 40 + (i * 11) % 20)
        leaves.CanCollide = false
        leaves.Parent = tree

        -- Secondary canopy (smaller, offset for organic shape)
        local leaves2 = Instance.new("Part")
        leaves2.Name = "Leaves2"
        leaves2.Shape = Enum.PartType.Ball
        leaves2.Size = Vector3.new(6, 5, 6)
        leaves2.Position = pos + Vector3.new(2 * ((i % 2 == 0) and 1 or -1), trunkHeight + 1, 1.5 * ((i % 3 == 0) and 1 or -1))
        leaves2.Anchored = true
        leaves2.Material = Enum.Material.Grass
        leaves2.Color = Color3.fromRGB(50 + (i * 9) % 20, greenShade - 10, 45 + (i * 5) % 15)
        leaves2.CanCollide = false
        leaves2.Parent = tree

        -- Root bumps at base
        for r = 1, 3 do
            local root = Instance.new("Part")
            root.Name = "Root" .. r
            root.Size = Vector3.new(1.2, 0.6, 0.5)
            local angle = math.rad((r - 1) * 120 + i * 30)
            root.Position = pos + Vector3.new(math.cos(angle) * 1.3, 0.3, math.sin(angle) * 1.3)
            root.Orientation = Vector3.new(0, math.deg(angle), 15)
            root.Anchored = true
            root.Material = Enum.Material.Wood
            root.Color = Color3.fromRGB(70, 48, 30)
            root.CanCollide = false
            root.Parent = tree
        end

        tree.Parent = decorFolder
    end

    -- Street lamps along the main path
    local lampPositions = {
        Vector3.new(55, GROUND_Y, 35),
        Vector3.new(65, GROUND_Y, 35),
        Vector3.new(55, GROUND_Y, 55),
        Vector3.new(65, GROUND_Y, 55),
        Vector3.new(55, GROUND_Y, 85),
        Vector3.new(65, GROUND_Y, 85),
        Vector3.new(55, GROUND_Y, 105),
        Vector3.new(65, GROUND_Y, 105),
    }

    for i, pos in lampPositions do
        local lamp = Instance.new("Model")
        lamp.Name = "StreetLamp" .. i

        local pole = Instance.new("Part")
        pole.Name = "Pole"
        pole.Size = Vector3.new(0.5, 8, 0.5)
        pole.Position = pos + Vector3.new(0, 4, 0)
        pole.Anchored = true
        pole.Material = Enum.Material.Metal
        pole.Color = Color3.fromRGB(50, 50, 55)
        pole.Parent = lamp

        -- Hanging bracket (L-shaped arm)
        local bracket = Instance.new("Part")
        bracket.Name = "Bracket"
        bracket.Size = Vector3.new(0.3, 0.3, 1.5)
        bracket.Position = pos + Vector3.new(0, 8, 0.75)
        bracket.Anchored = true
        bracket.Material = Enum.Material.Metal
        bracket.Color = Color3.fromRGB(45, 45, 50)
        bracket.CanCollide = false
        bracket.Parent = lamp

        -- Lantern hung from bracket end
        local lantern = Instance.new("Part")
        lantern.Name = "Lantern"
        lantern.Size = Vector3.new(1.2, 1.8, 1.2)
        lantern.Position = pos + Vector3.new(0, 7, 1.5)
        lantern.Anchored = true
        lantern.Material = Enum.Material.Glass
        lantern.Color = Color3.fromRGB(255, 220, 150)
        lantern.Transparency = 0.3
        lantern.CanCollide = false
        lantern.Parent = lamp

        -- Lantern cage bars (4 vertical bars around glass)
        for b = 0, 3 do
            local bar = Instance.new("Part")
            bar.Name = "CageBar" .. b
            bar.Size = Vector3.new(0.1, 1.8, 0.1)
            local bAngle = math.rad(b * 90)
            bar.Position = pos + Vector3.new(math.cos(bAngle) * 0.7, 7, 1.5 + math.sin(bAngle) * 0.7)
            bar.Anchored = true
            bar.Material = Enum.Material.Metal
            bar.Color = Color3.fromRGB(45, 45, 50)
            bar.CanCollide = false
            bar.Parent = lamp
        end

        -- Lantern top cap
        local cap = Instance.new("Part")
        cap.Name = "LanternCap"
        cap.Size = Vector3.new(1.4, 0.2, 1.4)
        cap.Position = pos + Vector3.new(0, 7.9, 1.5)
        cap.Anchored = true
        cap.Material = Enum.Material.Metal
        cap.Color = Color3.fromRGB(45, 45, 50)
        cap.CanCollide = false
        cap.Parent = lamp

        local light = Instance.new("PointLight")
        light.Color = Color3.fromRGB(255, 200, 120)
        light.Brightness = 1.5
        light.Range = 25
        light.Parent = lantern

        lamp.Parent = decorFolder
    end

    -- Benches near buildings
    local benchPositions = {
        {pos = Vector3.new(40, GROUND_Y, 70), rot = 0},
        {pos = Vector3.new(80, GROUND_Y, 70), rot = 0},
        {pos = Vector3.new(60, GROUND_Y, 45), rot = 90},
        {pos = Vector3.new(60, GROUND_Y, 95), rot = 90},
    }

    for i, data in benchPositions do
        local bench = Instance.new("Model")
        bench.Name = "Bench" .. i

        -- Seat plank
        local seat = Instance.new("Part")
        seat.Name = "Seat"
        seat.Size = Vector3.new(4, 0.3, 1.5)
        seat.Position = data.pos + Vector3.new(0, 1.2, 0)
        seat.Orientation = Vector3.new(0, data.rot, 0)
        seat.Anchored = true
        seat.Material = Enum.Material.Wood
        seat.Color = Color3.fromRGB(90, 65, 45)
        seat.Parent = bench

        -- Backrest
        local backrest = Instance.new("Part")
        backrest.Name = "Backrest"
        backrest.Size = Vector3.new(4, 1.2, 0.2)
        backrest.Position = data.pos + Vector3.new(0, 1.9, -0.65)
        backrest.Orientation = Vector3.new(-10, data.rot, 0)
        backrest.Anchored = true
        backrest.Material = Enum.Material.Wood
        backrest.Color = Color3.fromRGB(85, 60, 40)
        backrest.Parent = bench

        -- Legs (2)
        local rad = math.rad(data.rot)
        for _, side in {-1.5, 1.5} do
            local leg = Instance.new("Part")
            leg.Name = "Leg"
            leg.Size = Vector3.new(0.4, 1.2, 1.2)
            local legOffset = Vector3.new(side, 0.6, 0)
            local rotX = legOffset.X * math.cos(rad) - legOffset.Z * math.sin(rad)
            local rotZ = legOffset.X * math.sin(rad) + legOffset.Z * math.cos(rad)
            leg.Position = data.pos + Vector3.new(rotX, legOffset.Y, rotZ)
            leg.Orientation = Vector3.new(0, data.rot, 0)
            leg.Anchored = true
            leg.Material = Enum.Material.Wood
            leg.Color = Color3.fromRGB(75, 55, 35)
            leg.Parent = bench
        end

        bench.Parent = decorFolder
    end

    -- Central well with roof structure
    local well = Instance.new("Model")
    well.Name = "CentralWell"

    -- Taller stone rim
    local wellBase = Instance.new("Part")
    wellBase.Name = "Base"
    wellBase.Shape = Enum.PartType.Cylinder
    wellBase.Size = Vector3.new(3, 7, 7)
    wellBase.Position = Vector3.new(60, GROUND_Y + 1.5, 45)
    wellBase.Anchored = true
    wellBase.Material = Enum.Material.Cobblestone
    wellBase.Color = Color3.fromRGB(110, 105, 100)
    wellBase.Parent = well

    -- Water with shimmer
    local wellWater = Instance.new("Part")
    wellWater.Name = "Water"
    wellWater.Shape = Enum.PartType.Cylinder
    wellWater.Size = Vector3.new(0.5, 5, 5)
    wellWater.Position = Vector3.new(60, GROUND_Y + 1, 45)
    wellWater.Anchored = true
    wellWater.Material = Enum.Material.Glass
    wellWater.Color = Color3.fromRGB(70, 130, 190)
    wellWater.Transparency = 0.35
    wellWater.Parent = well

    -- Roof support posts (4 posts)
    for p = 0, 3 do
        local post = Instance.new("Part")
        post.Name = "WellPost" .. p
        post.Size = Vector3.new(0.5, 5, 0.5)
        local pAngle = math.rad(p * 90 + 45)
        post.Position = Vector3.new(60 + math.cos(pAngle) * 3, GROUND_Y + 5.5, 45 + math.sin(pAngle) * 3)
        post.Anchored = true
        post.Material = Enum.Material.Wood
        post.Color = Color3.fromRGB(70, 48, 30)
        post.Parent = well
    end

    -- Roof (peaked, two sloped Parts)
    local roofLeft = Instance.new("Part")
    roofLeft.Name = "WellRoofLeft"
    roofLeft.Size = Vector3.new(5, 0.3, 7)
    roofLeft.Position = Vector3.new(58.8, GROUND_Y + 8.5, 45)
    roofLeft.Orientation = Vector3.new(0, 0, 25)
    roofLeft.Anchored = true
    roofLeft.Material = Enum.Material.Wood
    roofLeft.Color = Color3.fromRGB(80, 55, 35)
    roofLeft.CanCollide = false
    roofLeft.Parent = well

    local roofRight = Instance.new("Part")
    roofRight.Name = "WellRoofRight"
    roofRight.Size = Vector3.new(5, 0.3, 7)
    roofRight.Position = Vector3.new(61.2, GROUND_Y + 8.5, 45)
    roofRight.Orientation = Vector3.new(0, 0, -25)
    roofRight.Anchored = true
    roofRight.Material = Enum.Material.Wood
    roofRight.Color = Color3.fromRGB(80, 55, 35)
    roofRight.CanCollide = false
    roofRight.Parent = well

    -- Roof beam (horizontal, holds rope)
    local roofBeam = Instance.new("Part")
    roofBeam.Name = "RoofBeam"
    roofBeam.Size = Vector3.new(0.4, 0.4, 7)
    roofBeam.Position = Vector3.new(60, GROUND_Y + 9.2, 45)
    roofBeam.Anchored = true
    roofBeam.Material = Enum.Material.Wood
    roofBeam.Color = Color3.fromRGB(70, 48, 30)
    roofBeam.CanCollide = false
    roofBeam.Parent = well

    -- Rope from beam
    local rope = Instance.new("Part")
    rope.Name = "Rope"
    rope.Size = Vector3.new(0.15, 4, 0.15)
    rope.Position = Vector3.new(60, GROUND_Y + 7, 45)
    rope.Anchored = true
    rope.Material = Enum.Material.Fabric
    rope.Color = Color3.fromRGB(160, 140, 100)
    rope.CanCollide = false
    rope.Parent = well

    -- Bucket at rope end
    local bucket = Instance.new("Part")
    bucket.Name = "Bucket"
    bucket.Shape = Enum.PartType.Cylinder
    bucket.Size = Vector3.new(1, 1, 1)
    bucket.Position = Vector3.new(60, GROUND_Y + 4.8, 45)
    bucket.Orientation = Vector3.new(0, 0, 0)
    bucket.Anchored = true
    bucket.Material = Enum.Material.Wood
    bucket.Color = Color3.fromRGB(90, 65, 40)
    bucket.CanCollide = false
    bucket.Parent = well

    well.Parent = decorFolder


    -- Barrel clusters near buildings
    local barrelPositions = {
        Vector3.new(35, GROUND_Y, 35),
        Vector3.new(85, GROUND_Y, 35),
        Vector3.new(35, GROUND_Y, 115),
        Vector3.new(85, GROUND_Y, 115),
    }
    for i, bpos in barrelPositions do
        for j = 1, 3 do
            local barrel = Instance.new("Part")
            barrel.Name = "Barrel" .. i .. "_" .. j
            barrel.Shape = Enum.PartType.Cylinder
            barrel.Size = Vector3.new(2, 1.5, 1.5)
            barrel.Position = bpos + Vector3.new((j - 2) * 1.8, 1, (j % 2) * 0.5)
            barrel.Anchored = true
            barrel.Material = Enum.Material.WoodPlanks
            barrel.Color = Color3.fromRGB(100 + j * 10, 70 + j * 5, 40 + j * 5)
            barrel.CanCollide = false
            barrel.Parent = decorFolder
        end
    end

    -- Crate stacks near paths
    local cratePositions = {
        Vector3.new(50, GROUND_Y, 40),
        Vector3.new(70, GROUND_Y, 40),
        Vector3.new(50, GROUND_Y, 80),
        Vector3.new(70, GROUND_Y, 80),
    }
    for i, cpos in cratePositions do
        local crate = Instance.new("Part")
        crate.Name = "Crate" .. i
        crate.Size = Vector3.new(1.5, 1.5, 1.5)
        crate.Position = cpos + Vector3.new(0, 0.75, 0)
        crate.Anchored = true
        crate.Material = Enum.Material.WoodPlanks
        crate.Color = Color3.fromRGB(150, 120, 80)
        crate.CanCollide = false
        crate.Parent = decorFolder

        -- Stacked crate on top (slightly rotated)
        if i % 2 == 0 then
            local crate2 = Instance.new("Part")
            crate2.Name = "Crate" .. i .. "_top"
            crate2.Size = Vector3.new(1.3, 1.3, 1.3)
            crate2.Position = cpos + Vector3.new(0.2, 2.1, 0.1)
            crate2.Orientation = Vector3.new(0, 15, 0)
            crate2.Anchored = true
            crate2.Material = Enum.Material.WoodPlanks
            crate2.Color = Color3.fromRGB(140, 115, 75)
            crate2.CanCollide = false
            crate2.Parent = decorFolder
        end
    end

    -- Flower beds along paths
    local flowerPositions = {
        Vector3.new(53, GROUND_Y, 60),
        Vector3.new(67, GROUND_Y, 60),
        Vector3.new(53, GROUND_Y, 110),
        Vector3.new(67, GROUND_Y, 110),
    }
    local flowerColors = {
        Color3.fromRGB(220, 60, 60),
        Color3.fromRGB(255, 200, 60),
        Color3.fromRGB(200, 80, 200),
        Color3.fromRGB(255, 150, 50),
    }
    for i, fpos in flowerPositions do
        -- Soil bed
        local bed = Instance.new("Part")
        bed.Name = "FlowerBed" .. i
        bed.Size = Vector3.new(3, 0.3, 1.5)
        bed.Position = fpos + Vector3.new(0, 0.15, 0)
        bed.Anchored = true
        bed.Material = Enum.Material.Ground
        bed.Color = Color3.fromRGB(80, 55, 35)
        bed.CanCollide = false
        bed.Parent = decorFolder

        -- Flowers
        for f = 1, 4 do
            local flower = Instance.new("Part")
            flower.Name = "Flower" .. f
            flower.Shape = Enum.PartType.Ball
            flower.Size = Vector3.new(0.5, 0.5, 0.5)
            flower.Position = fpos + Vector3.new((f - 2.5) * 0.6, 0.5, 0)
            flower.Anchored = true
            flower.Material = Enum.Material.Grass
            flower.Color = flowerColors[(f + i) % #flowerColors + 1]
            flower.CanCollide = false
            flower.Parent = decorFolder
        end
    end

    -- Market stall near center
    local stallPos = Vector3.new(45, GROUND_Y, 75)
    local stallModel = Instance.new("Model")
    stallModel.Name = "MarketStall"

    -- Counter
    local counter = Instance.new("Part")
    counter.Name = "Counter"
    counter.Size = Vector3.new(6, 3, 2)
    counter.Position = stallPos + Vector3.new(0, 1.5, 0)
    counter.Anchored = true
    counter.Material = Enum.Material.Wood
    counter.Color = Color3.fromRGB(100, 70, 45)
    counter.Parent = stallModel

    -- Support posts for canopy
    for _, sx in {-2.8, 2.8} do
        local spost = Instance.new("Part")
        spost.Name = "StallPost"
        spost.Size = Vector3.new(0.4, 5, 0.4)
        spost.Position = stallPos + Vector3.new(sx, 2.5, 1)
        spost.Anchored = true
        spost.Material = Enum.Material.Wood
        spost.Color = Color3.fromRGB(80, 55, 35)
        spost.Parent = stallModel
    end

    -- Fabric canopy
    local canopy = Instance.new("Part")
    canopy.Name = "Canopy"
    canopy.Size = Vector3.new(7, 0.2, 3.5)
    canopy.Position = stallPos + Vector3.new(0, 5.2, 0.5)
    canopy.Orientation = Vector3.new(8, 0, 0)
    canopy.Anchored = true
    canopy.Material = Enum.Material.Fabric
    canopy.Color = Color3.fromRGB(160, 40, 40)
    canopy.CanCollide = false
    canopy.Parent = stallModel

    stallModel.Parent = decorFolder

    -- Notice board near entrance
    local noticeBoard = Instance.new("Part")
    noticeBoard.Name = "NoticeBoard"
    noticeBoard.Size = Vector3.new(3, 2.5, 0.3)
    noticeBoard.Position = Vector3.new(78, GROUND_Y + 3, 14)
    noticeBoard.Anchored = true
    noticeBoard.Material = Enum.Material.Wood
    noticeBoard.Color = Color3.fromRGB(90, 65, 40)
    noticeBoard.CanCollide = false
    noticeBoard.Parent = decorFolder

    local noticeBoardPost = Instance.new("Part")
    noticeBoardPost.Name = "NoticeBoardPost"
    noticeBoardPost.Size = Vector3.new(0.4, 4, 0.4)
    noticeBoardPost.Position = Vector3.new(78, GROUND_Y + 2, 14)
    noticeBoardPost.Anchored = true
    noticeBoardPost.Material = Enum.Material.Wood
    noticeBoardPost.Color = Color3.fromRGB(70, 48, 30)
    noticeBoardPost.Parent = decorFolder

    -- Notice board text
    local noticeGui = Instance.new("SurfaceGui")
    noticeGui.Face = Enum.NormalId.Front
    noticeGui.Parent = noticeBoard
    local noticeLabel = Instance.new("TextLabel")
    noticeLabel.Size = UDim2.new(1, 0, 1, 0)
    noticeLabel.BackgroundTransparency = 1
    noticeLabel.Text = "VILLAGE\nNOTICES"
    noticeLabel.TextColor3 = Color3.fromRGB(40, 30, 20)
    noticeLabel.TextScaled = true
    noticeLabel.Font = Enum.Font.Antique
    noticeLabel.Parent = noticeGui

    -- Hay cart near farm area
    local cartBase = Instance.new("Part")
    cartBase.Name = "HayCartBase"
    cartBase.Size = Vector3.new(4, 1, 2.5)
    cartBase.Position = Vector3.new(85, GROUND_Y + 1, 95)
    cartBase.Anchored = true
    cartBase.Material = Enum.Material.Wood
    cartBase.Color = Color3.fromRGB(100, 70, 45)
    cartBase.CanCollide = false
    cartBase.Parent = decorFolder

    local hayPile = Instance.new("Part")
    hayPile.Name = "HayPile"
    hayPile.Size = Vector3.new(3.5, 1.5, 2)
    hayPile.Position = Vector3.new(85, GROUND_Y + 2.2, 95)
    hayPile.Anchored = true
    hayPile.Material = Enum.Material.Fabric
    hayPile.Color = Color3.fromRGB(210, 185, 120)
    hayPile.CanCollide = false
    hayPile.Parent = decorFolder

    -- Cart wheels
    for _, wOff in {{-2.2, -1.3}, {-2.2, 1.3}, {2.2, -1.3}, {2.2, 1.3}} do
        local wheel = Instance.new("Part")
        wheel.Name = "CartWheel"
        wheel.Shape = Enum.PartType.Cylinder
        wheel.Size = Vector3.new(0.3, 1.5, 1.5)
        wheel.Position = Vector3.new(85 + wOff[1], GROUND_Y + 0.75, 95 + wOff[2])
        wheel.Orientation = Vector3.new(0, 90, 0)
        wheel.Anchored = true
        wheel.Material = Enum.Material.Wood
        wheel.Color = Color3.fromRGB(70, 48, 30)
        wheel.CanCollide = false
        wheel.Parent = decorFolder
    end

    print("  ✓ Decorations added")
end

-- ============================================================================
-- WORKER SPAWN FUNCTIONS (extracted for reconstruction from saved state)
-- These create the NPC + start AI loop, without deducting cost.
-- ============================================================================

-- Spawn a miner NPC and start its AI loop (no cost deduction)
local function spawnMinerWorker(ownerUserId)
    local model = GoldMineState.model
    if not model then return end

    local minerCount = #GoldMineState.miners
    local minerId = minerCount + 1

    local spawnPos = GoldMineState.positions.workerSpawn + Vector3.new(minerCount * 3, 0, 0)
    local miner = createWorkerNPC(
        "Miner " .. minerId,
        spawnPos,
        Color3.fromRGB(139, 90, 43),
        "Miner"
    )
    miner.Parent = model

    local isR15Miner = miner:FindFirstChild("HumanoidRootPart") ~= nil
    local pickaxe, pickaxeHead
    if not isR15Miner then
        pickaxe = Instance.new("Part")
        pickaxe.Name = "Pickaxe"
        pickaxe.Size = Vector3.new(0.2, 2, 0.2)
        pickaxe.Anchored = true
        pickaxe.CanCollide = false
        pickaxe.Material = Enum.Material.Wood
        pickaxe.Color = Color3.fromRGB(100, 70, 45)
        pickaxe.Parent = miner

        pickaxeHead = Instance.new("Part")
        pickaxeHead.Name = "PickaxeHead"
        pickaxeHead.Size = Vector3.new(0.8, 0.3, 0.2)
        pickaxeHead.Anchored = true
        pickaxeHead.CanCollide = false
        pickaxeHead.Material = Enum.Material.Metal
        pickaxeHead.Color = Color3.fromRGB(140, 140, 150)
        pickaxeHead.Parent = miner
    end

    local minerData = {
        npc = miner,
        state = "idle",
        carrying = 0,
        pickaxe = pickaxe,
        pickaxeHead = pickaxeHead,
    }
    table.insert(GoldMineState.miners, minerData)

    local function updatePickaxePosition()
        if isR15Miner then return end
        local torso = miner:FindFirstChild("Torso")
        if torso then
            pickaxe.Position = torso.Position + Vector3.new(1, 0.5, 0)
            pickaxeHead.Position = pickaxe.Position + Vector3.new(0.5, 0.8, 0)
        end
    end

    task.spawn(function()
        while minerData.npc and minerData.npc.Parent do
            local cycleComplete = false
            local minerStats = getMinerStats(GoldMineState.equipment.minerLevel)
            local oreCapacity = minerStats.oreCapacity
            local walkSpeed = minerStats.walkSpeed
            local miningTime = minerStats.miningTime

            minerData.state = "walking_to_ore"
            setNPCStatus(miner, "Walking to ore...")
            local orePos = GoldMineState.positions.oreVein + Vector3.new(math.random(-3, 3), 0, math.random(-2, 2))
            walkNPCTo(miner, orePos, walkSpeed, function()
                minerData.state = "mining"
                updatePickaxePosition()
                local oreMined = 0
                for swing = 1, oreCapacity do
                    oreMined = swing
                    setNPCStatus(miner, string.format("Mining %d/%d", oreMined, oreCapacity))
                    local torso = miner:FindFirstChild("UpperTorso") or miner:FindFirstChild("Torso")
                    if torso then
                        local rockParticles = Instance.new("ParticleEmitter")
                        rockParticles.Color = ColorSequence.new(Color3.fromRGB(120, 100, 80))
                        rockParticles.Size = NumberSequence.new(0.3)
                        rockParticles.Lifetime = NumberRange.new(0.3, 0.5)
                        rockParticles.Rate = 20
                        rockParticles.Speed = NumberRange.new(3, 6)
                        rockParticles.SpreadAngle = Vector2.new(30, 30)
                        rockParticles.Parent = torso
                        task.delay(0.4, function() rockParticles:Destroy() end)
                    end
                    task.wait(miningTime)
                end
                minerData.carrying = oreCapacity
                setNPCCarrying(miner, "ore", math.min(5, math.ceil(oreCapacity / 5)))
                setNPCStatus(miner, string.format("Carrying %d ore", oreCapacity))

                minerData.state = "walking_to_smelter"
                setNPCStatus(miner, "Delivering ore...")
                walkNPCTo(miner, GoldMineState.positions.smelter + Vector3.new(-4, 0, 0), walkSpeed, function()
                    minerData.state = "depositing"
                    setNPCStatus(miner, "Depositing ore...")
                    task.wait(0.5)
                    local oreDeposited = minerData.carrying
                    GoldMineState.smelterOre = GoldMineState.smelterOre + oreDeposited
                    minerData.carrying = 0
                    setNPCCarrying(miner, nil, 0)
                    minerData.state = "idle"
                    setNPCStatus(miner, "Returning...")
                    cycleComplete = true
                end)
            end)

            while not cycleComplete and minerData.npc and minerData.npc.Parent do
                task.wait(0.5)
            end
            task.wait(1)
        end
    end)

    print(string.format("[Reconstruct] Spawned Miner #%d", minerId))
end

-- Spawn a collector NPC and start its AI loop (no cost deduction)
local function spawnCollectorWorker(ownerUserId)
    local model = GoldMineState.model
    if not model then return end

    local collectorCount = #GoldMineState.collectors
    local collectorId = collectorCount + 1

    local spawnPos = GoldMineState.positions.workerSpawn + Vector3.new(collectorCount * 3 + 10, 0, 0)
    local collector = createWorkerNPC(
        "Collector " .. collectorId,
        spawnPos,
        Color3.fromRGB(60, 100, 60),
        "Collector"
    )
    collector.Parent = model

    local collectorData = {
        npc = collector,
        state = "idle",
        carrying = 0,
        owner = ownerUserId,
    }
    table.insert(GoldMineState.collectors, collectorData)

    task.spawn(function()
        setNPCStatus(collector, "Waiting for gold...")
        while collectorData.npc and collectorData.npc.Parent do
            local collectorStats = getCollectorStats(GoldMineState.equipment.collectorLevel)
            local goldCapacity = collectorStats.goldCapacity
            local walkSpeed = collectorStats.walkSpeed

            if GoldMineState.smelterGold >= 1 then
                local cycleComplete = false
                collectorData.state = "walking_to_smelter"
                setNPCStatus(collector, "Going to smelter...")
                walkNPCTo(collector, GoldMineState.positions.smelter + Vector3.new(6, 0, 0), walkSpeed, function()
                    collectorData.state = "picking_up"
                    setNPCStatus(collector, "Picking up gold...")
                    task.wait(1)
                    local goldToCollect = math.min(GoldMineState.smelterGold, goldCapacity)
                    GoldMineState.smelterGold = GoldMineState.smelterGold - goldToCollect
                    collectorData.carrying = goldToCollect
                    setNPCCarrying(collector, "gold", math.min(5, goldToCollect))
                    setNPCStatus(collector, string.format("Carrying %d gold", goldToCollect))
                    if GoldMineState.updateGoldBarVisuals then GoldMineState.updateGoldBarVisuals() end

                    collectorData.state = "walking_to_chest"
                    setNPCStatus(collector, "Delivering to chest...")
                    walkNPCTo(collector, GoldMineState.positions.goldChest + Vector3.new(-4, 0, 0), walkSpeed, function()
                        collectorData.state = "depositing"
                        setNPCStatus(collector, "Depositing gold...")
                        task.wait(1.5)
                        local goldDelivered = collectorData.carrying
                        GoldMineState.chestGold = GoldMineState.chestGold + goldDelivered
                        if GoldMineState.updateChestGoldVisuals then GoldMineState.updateChestGoldVisuals() end

                        local ownerPlayer = nil
                        for _, p in Players:GetPlayers() do
                            if p.UserId == collectorData.owner then
                                ownerPlayer = p
                                break
                            end
                        end
                        if ownerPlayer then
                            rewardPlayer(ownerPlayer, "gold", goldDelivered, "GoldMine")
                        end

                        collectorData.carrying = 0
                        setNPCCarrying(collector, nil, 0)
                        collectorData.state = "idle"
                        setNPCStatus(collector, "Waiting for gold...")
                        cycleComplete = true
                    end)
                end)
                while not cycleComplete and collectorData.npc and collectorData.npc.Parent do
                    task.wait(0.5)
                end
                task.wait(1)
            else
                setNPCStatus(collector, "Waiting for gold...")
                task.wait(2)
            end
        end
    end)

    print(string.format("[Reconstruct] Spawned Collector #%d", collectorId))
end

-- Spawn a logger NPC and start its AI loop (no cost deduction)
local function spawnLoggerWorker()
    local model = LumberMillState.millModel
    if not model then return end

    local loggerCount = #LumberMillState.loggers
    local loggerId = loggerCount + 1

    local spawnPos = LumberMillState.positions.workerSpawn + Vector3.new(loggerCount * 3, 0, 0)
    local logger = createWorkerNPC(
        "Logger " .. loggerId,
        spawnPos,
        Color3.fromRGB(180, 50, 50),
        "Logger"
    )
    logger.Parent = model

    local loggerData = {
        npc = logger,
        state = "idle",
        carrying = 0,
    }
    table.insert(LumberMillState.loggers, loggerData)

    task.spawn(function()
        while loggerData.npc and loggerData.npc.Parent do
            local cycleComplete = false
            local loggerStats = getLoggerStats(LumberMillState.equipment.loggerLevel)
            local logCapacity = loggerStats.logCapacity
            local walkSpeed = loggerStats.walkSpeed
            local choppingTime = loggerStats.choppingTime

            local targetTreeId = nil
            local targetTreePos = nil
            for treeId, stage in pairs(LumberMillState.treeStage) do
                if stage and stage >= 1 and stage <= 4 then
                    targetTreeId = treeId
                    targetTreePos = LumberMillState.treePositions[treeId]
                    break
                end
            end

            if targetTreeId and targetTreePos then
                loggerData.state = "walking_to_trees"
                setNPCStatus(logger, string.format("Going to tree #%d...", targetTreeId))
                local treePos = Vector3.new(targetTreePos.x, GROUND_Y, targetTreePos.z)
                walkNPCTo(logger, treePos + Vector3.new(2, 0, 0), walkSpeed, function()
                    loggerData.state = "chopping"
                    local logsCollected = 0
                    local woodPerStage = { 1, 2, 3, 5 }
                    while logsCollected < logCapacity do
                        local currentStage = LumberMillState.treeStage[targetTreeId]
                        if not currentStage or currentStage == 0 then break end
                        setNPCStatus(logger, string.format("Chopping tree #%d (%d logs)", targetTreeId, logsCollected))
                        local torso = logger:FindFirstChild("UpperTorso") or logger:FindFirstChild("Torso")
                        if torso then
                            local chips = Instance.new("ParticleEmitter")
                            chips.Color = ColorSequence.new(Color3.fromRGB(180, 140, 90))
                            chips.Size = NumberSequence.new(0.3)
                            chips.Lifetime = NumberRange.new(0.3, 0.5)
                            chips.Rate = 20
                            chips.Speed = NumberRange.new(3, 6)
                            chips.SpreadAngle = Vector2.new(30, 30)
                            chips.Parent = torso
                            task.delay(0.4, function() chips:Destroy() end)
                        end
                        task.wait(choppingTime)
                        local newStage = currentStage + 1
                        local logsFromChop = woodPerStage[currentStage] or 1
                        logsCollected = logsCollected + logsFromChop
                        if newStage > 4 then
                            newStage = 0
                            LumberMillState.treeRespawn[targetTreeId] = os.time() + 15
                        end
                        LumberMillState.treeStage[targetTreeId] = newStage
                        if LumberMillState.updateTreeVisual then
                            LumberMillState.updateTreeVisual(targetTreeId, newStage)
                        end
                    end
                    loggerData.carrying = logsCollected
                    setNPCCarrying(logger, "logs", math.min(5, math.ceil(logsCollected / 3)))
                    setNPCStatus(logger, string.format("Carrying %d logs", logsCollected))

                    loggerData.state = "walking_to_sawmill"
                    setNPCStatus(logger, "Delivering logs...")
                    walkNPCTo(logger, LumberMillState.positions.sawmill + Vector3.new(-4, 0, 0), walkSpeed, function()
                        loggerData.state = "depositing"
                        setNPCStatus(logger, "Depositing logs...")
                        task.wait(0.5)
                        LumberMillState.sawmillLogs = LumberMillState.sawmillLogs + loggerData.carrying
                        loggerData.carrying = 0
                        setNPCCarrying(logger, nil, 0)
                        loggerData.state = "idle"
                        setNPCStatus(logger, "Returning...")
                        cycleComplete = true
                    end)
                end)
                while not cycleComplete and loggerData.npc and loggerData.npc.Parent do
                    task.wait(0.5)
                end
                task.wait(1)
            else
                setNPCStatus(logger, "No trees available...")
                task.wait(3)
            end
        end
    end)

    print(string.format("[Reconstruct] Spawned Logger #%d", loggerId))
end

-- Spawn a hauler NPC and start its AI loop (no cost deduction)
local function spawnHaulerWorker(ownerUserId)
    local model = LumberMillState.millModel
    if not model then return end

    local haulerCount = #LumberMillState.haulers
    local haulerId = haulerCount + 1

    local spawnPos = LumberMillState.positions.workerSpawn + Vector3.new(haulerCount * 3 + 10, 0, 0)
    local hauler = createWorkerNPC(
        "Hauler " .. haulerId,
        spawnPos,
        Color3.fromRGB(50, 80, 140),
        "Hauler"
    )
    hauler.Parent = model

    local haulerData = {
        npc = hauler,
        state = "idle",
        carrying = 0,
        owner = ownerUserId,
    }
    table.insert(LumberMillState.haulers, haulerData)

    task.spawn(function()
        setNPCStatus(hauler, "Waiting for planks...")
        while haulerData.npc and haulerData.npc.Parent do
            local haulerStats = getHaulerStats(LumberMillState.equipment.haulerLevel)
            local plankCapacity = haulerStats.plankCapacity
            local walkSpeed = haulerStats.walkSpeed

            if LumberMillState.woodStorage >= 1 then
                local cycleComplete = false
                haulerData.state = "walking_to_sawmill"
                setNPCStatus(hauler, "Going to sawmill...")
                walkNPCTo(hauler, LumberMillState.positions.sawmill + Vector3.new(6, 0, 0), walkSpeed, function()
                    haulerData.state = "picking_up"
                    setNPCStatus(hauler, "Picking up planks...")
                    task.wait(1)
                    local planksToCollect = math.min(LumberMillState.woodStorage, plankCapacity)
                    LumberMillState.woodStorage = LumberMillState.woodStorage - planksToCollect
                    haulerData.carrying = planksToCollect
                    setNPCCarrying(hauler, "planks", math.min(5, math.ceil(planksToCollect / 5)))
                    setNPCStatus(hauler, string.format("Carrying %d planks", planksToCollect))
                    if LumberMillState.updatePlankPileVisuals then LumberMillState.updatePlankPileVisuals() end

                    haulerData.state = "walking_to_storage"
                    setNPCStatus(hauler, "Delivering planks...")
                    walkNPCTo(hauler, LumberMillState.positions.storage + Vector3.new(-4, 0, 0), walkSpeed, function()
                        haulerData.state = "depositing"
                        setNPCStatus(hauler, "Depositing planks...")
                        task.wait(1.5)
                        local planksDelivered = haulerData.carrying

                        local ownerPlayer = nil
                        for _, p in Players:GetPlayers() do
                            if p.UserId == haulerData.owner then
                                ownerPlayer = p
                                break
                            end
                        end
                        if ownerPlayer then
                            rewardPlayer(ownerPlayer, "wood", planksDelivered, "LumberMill")
                        end

                        haulerData.carrying = 0
                        setNPCCarrying(hauler, nil, 0)
                        haulerData.state = "idle"
                        setNPCStatus(hauler, "Waiting for planks...")
                        cycleComplete = true
                    end)
                end)
                while not cycleComplete and haulerData.npc and haulerData.npc.Parent do
                    task.wait(0.5)
                end
                task.wait(1)
            else
                setNPCStatus(hauler, "Waiting for planks...")
                task.wait(2)
            end
        end
    end)

    print(string.format("[Reconstruct] Spawned Hauler #%d", haulerId))
end

-- Spawn a farmer NPC and start its AI loop (no cost deduction)
local function spawnFarmerWorker(farmNumber)
    local farmState = FarmStates[farmNumber]
    if not farmState or not farmState.model then return end

    local farmerCount = #farmState.farmers
    local farmerId = farmerCount + 1

    local spawnPos = farmState.positions.workerSpawn + Vector3.new(farmerCount * 3, 0, 0)
    local farmer = createWorkerNPC(
        "Farmer " .. farmerId,
        spawnPos,
        Color3.fromRGB(180, 160, 50),
        "Farmer"
    )
    farmer.Parent = farmState.model

    local farmerData = {
        npc = farmer,
        state = "idle",
        carrying = 0,
    }
    table.insert(farmState.farmers, farmerData)

    task.spawn(function()
        while farmerData.npc and farmerData.npc.Parent do
            local cycleComplete = false
            local farmerStats = getFarmerStats(farmState.equipment.farmerLevel)
            local cropCapacity = farmerStats.cropCapacity
            local walkSpeed = farmerStats.walkSpeed
            local harvestTime = farmerStats.harvestTime

            -- Find harvestable plots
            local readyPlots = {}
            for plotId, plotData in farmState.plots do
                if plotData.stage and plotData.stage >= 3 then
                    table.insert(readyPlots, plotId)
                end
            end

            if #readyPlots > 0 then
                farmerData.state = "walking_to_field"
                setNPCStatus(farmer, "Going to harvest...")
                local fieldPos = farmState.positions.cropField or farmState.positions.workerSpawn
                walkNPCTo(farmer, fieldPos + Vector3.new(math.random(-3, 3), 0, math.random(-2, 2)), walkSpeed, function()
                    farmerData.state = "harvesting"
                    local cropsHarvested = 0
                    for _, plotId in readyPlots do
                        if cropsHarvested >= cropCapacity then break end
                        setNPCStatus(farmer, string.format("Harvesting %d/%d", cropsHarvested, cropCapacity))
                        task.wait(harvestTime)
                        cropsHarvested = cropsHarvested + 1
                        farmState.plots[plotId].stage = 0
                    end

                    farmerData.carrying = cropsHarvested
                    setNPCCarrying(farmer, "crops", math.min(5, math.ceil(cropsHarvested / 3)))
                    setNPCStatus(farmer, string.format("Carrying %d crops", cropsHarvested))

                    farmerData.state = "walking_to_basket"
                    setNPCStatus(farmer, "Delivering crops...")
                    local basketPos = farmState.positions.harvestBasket or farmState.positions.workerSpawn
                    walkNPCTo(farmer, basketPos + Vector3.new(-2, 0, 0), walkSpeed, function()
                        farmerData.state = "depositing"
                        setNPCStatus(farmer, "Depositing crops...")
                        task.wait(0.5)
                        farmState.harvestPile = farmState.harvestPile + farmerData.carrying
                        farmerData.carrying = 0
                        setNPCCarrying(farmer, nil, 0)
                        if farmState.updateHarvestPileVisuals then farmState.updateHarvestPileVisuals() end
                        farmerData.state = "idle"
                        setNPCStatus(farmer, "Returning...")
                        cycleComplete = true
                    end)
                end)
                while not cycleComplete and farmerData.npc and farmerData.npc.Parent do
                    task.wait(0.5)
                end
                task.wait(1)
            else
                setNPCStatus(farmer, "Waiting for crops...")
                task.wait(3)
            end
        end
    end)

    print(string.format("[Reconstruct] Spawned Farmer #%d for Farm %d", farmerId, farmNumber))
end

-- Spawn a carrier NPC and start its AI loop (no cost deduction)
local function spawnCarrierWorker(farmNumber, ownerUserId)
    local farmState = FarmStates[farmNumber]
    if not farmState or not farmState.model then return end

    local carrierCount = #farmState.carriers
    local carrierId = carrierCount + 1

    local spawnPos = farmState.positions.workerSpawn + Vector3.new(carrierCount * 3 + 10, 0, 0)
    local carrier = createWorkerNPC(
        "Carrier " .. carrierId,
        spawnPos,
        Color3.fromRGB(100, 140, 60),
        "Carrier"
    )
    carrier.Parent = farmState.model

    local carrierData = {
        npc = carrier,
        state = "idle",
        carrying = 0,
        owner = ownerUserId,
    }
    table.insert(farmState.carriers, carrierData)

    task.spawn(function()
        setNPCStatus(carrier, "Waiting for food...")
        while carrierData.npc and carrierData.npc.Parent do
            local carrierStats = getCarrierStats(farmState.equipment.carrierLevel)
            local grainCapacity = carrierStats.grainCapacity
            local walkSpeed = carrierStats.walkSpeed

            if farmState.foodStorage >= 1 then
                local cycleComplete = false
                carrierData.state = "walking_to_silo"
                setNPCStatus(carrier, "Going to silo...")
                local siloPos = farmState.positions.foodSilo or farmState.positions.workerSpawn
                walkNPCTo(carrier, siloPos + Vector3.new(2, 0, 0), walkSpeed, function()
                    carrierData.state = "picking_up"
                    setNPCStatus(carrier, "Picking up food...")
                    task.wait(1)
                    local foodToCollect = math.min(farmState.foodStorage, grainCapacity)
                    farmState.foodStorage = farmState.foodStorage - foodToCollect
                    carrierData.carrying = foodToCollect
                    setNPCCarrying(carrier, "food", math.min(5, math.ceil(foodToCollect / 5)))
                    setNPCStatus(carrier, string.format("Carrying %d food", foodToCollect))
                    if farmState.updateFoodStorageVisuals then farmState.updateFoodStorageVisuals() end

                    carrierData.state = "walking_to_barn"
                    setNPCStatus(carrier, "Delivering food...")
                    local barnPos = farmState.positions.barn or farmState.positions.workerSpawn
                    walkNPCTo(carrier, barnPos + Vector3.new(-2, 0, 0), walkSpeed, function()
                        carrierData.state = "depositing"
                        setNPCStatus(carrier, "Depositing food...")
                        task.wait(1.5)
                        local foodDelivered = carrierData.carrying

                        local ownerPlayer = nil
                        for _, p in Players:GetPlayers() do
                            if p.UserId == carrierData.owner then
                                ownerPlayer = p
                                break
                            end
                        end
                        if ownerPlayer then
                            rewardPlayer(ownerPlayer, "food", foodDelivered, "Farm")
                        end

                        carrierData.carrying = 0
                        setNPCCarrying(carrier, nil, 0)
                        carrierData.state = "idle"
                        setNPCStatus(carrier, "Waiting for food...")
                        cycleComplete = true
                    end)
                end)
                while not cycleComplete and carrierData.npc and carrierData.npc.Parent do
                    task.wait(0.5)
                end
                task.wait(1)
            else
                setNPCStatus(carrier, "Waiting for food...")
                task.wait(2)
            end
        end
    end)

    print(string.format("[Reconstruct] Spawned Carrier #%d for Farm %d", carrierId, farmNumber))
end

-- (Drill sergeant spawning removed - replaced by Army Training System)

-- ============================================================================
-- VILLAGE STATE OVERRIDE (apply saved state before building creation reads it)
-- ============================================================================

local function applyLoadedState(savedState)
    if not savedState then return end
    print("[SimpleTest] Applying saved village state...")

    -- Gold Mine
    if savedState.goldMine then
        local gm = savedState.goldMine
        GoldMineState.level = gm.level or 1
        GoldMineState.xp = gm.xp or 0
        GoldMineState.equipment.pickaxeLevel = gm.equipment and gm.equipment.pickaxeLevel or 1
        GoldMineState.equipment.smelterLevel = gm.equipment and gm.equipment.smelterLevel or 1
        GoldMineState.equipment.minerLevel = gm.equipment and gm.equipment.minerLevel or 1
        GoldMineState.equipment.collectorLevel = gm.equipment and gm.equipment.collectorLevel or 1
        GoldMineState.smelterOre = gm.smelterOre or 0
        GoldMineState.smelterGold = gm.smelterGold or 0
        GoldMineState.chestGold = gm.chestGold or 0
        if gm.prospecting then
            GoldMineState.prospecting.isActive = gm.prospecting.isActive or false
            GoldMineState.prospecting.tier = gm.prospecting.tier
            GoldMineState.prospecting.startTime = gm.prospecting.startTime or 0
            GoldMineState.prospecting.endTime = gm.prospecting.endTime or 0
            -- Time reconciliation: if prospecting completed while offline
            if GoldMineState.prospecting.isActive and GoldMineState.prospecting.endTime > 0 then
                if os.time() >= GoldMineState.prospecting.endTime then
                    GoldMineState.prospecting.isActive = false
                    print("[Reconstruct] Prospecting completed while offline")
                end
            end
        end
    end

    -- Lumber Mill
    if savedState.lumberMill then
        local lm = savedState.lumberMill
        LumberMillState.level = lm.level or 1
        LumberMillState.xp = lm.xp or 0
        LumberMillState.equipment.axeLevel = lm.equipment and lm.equipment.axeLevel or 1
        LumberMillState.equipment.sawmillLevel = lm.equipment and lm.equipment.sawmillLevel or 1
        LumberMillState.equipment.loggerLevel = lm.equipment and lm.equipment.loggerLevel or 1
        LumberMillState.equipment.haulerLevel = lm.equipment and lm.equipment.haulerLevel or 1
        LumberMillState.sawmillLogs = lm.sawmillLogs or 0
        LumberMillState.woodStorage = lm.woodStorage or 0
        -- Restore tree stages
        if lm.treeStages then
            for treeIdStr, stage in lm.treeStages do
                local treeId = tonumber(treeIdStr) or treeIdStr
                LumberMillState.treeStage[treeId] = stage
            end
        end
        -- Time reconciliation: respawn trees that should have regrown
        if lm.treeRespawnTimes then
            local now = os.time()
            for treeIdStr, respawnTime in lm.treeRespawnTimes do
                local treeId = tonumber(treeIdStr) or treeIdStr
                if now >= respawnTime then
                    LumberMillState.treeStage[treeId] = 1
                    print(string.format("[Reconstruct] Tree #%s regrew while offline", tostring(treeId)))
                else
                    LumberMillState.treeRespawn[treeId] = respawnTime
                end
            end
        end
    end

    -- Farms
    if savedState.farms then
        for farmNumStr, farmData in savedState.farms do
            local farmNumber = tonumber(farmNumStr)
            if farmNumber then
                local farmState = getFarmState(farmNumber)
                farmState.level = farmData.level or 1
                farmState.xp = farmData.xp or 0
                if farmData.equipment then
                    farmState.equipment.hoeLevel = farmData.equipment.hoeLevel or 1
                    farmState.equipment.wateringCanLevel = farmData.equipment.wateringCanLevel or 1
                    farmState.equipment.windmillLevel = farmData.equipment.windmillLevel or 1
                    farmState.equipment.farmerLevel = farmData.equipment.farmerLevel or 1
                    farmState.equipment.carrierLevel = farmData.equipment.carrierLevel or 1
                end
                farmState.harvestPile = farmData.harvestPile or 0
                farmState.windmillCrops = farmData.windmillCrops or 0
                farmState.foodStorage = farmData.foodStorage or 0
                -- Restore plots with time reconciliation
                if farmData.plots then
                    for plotIdStr, plotInfo in farmData.plots do
                        local plotId = tonumber(plotIdStr) or plotIdStr
                        farmState.plots[plotId] = {
                            crop = plotInfo.crop,
                            stage = plotInfo.stage or 0,
                            watered = plotInfo.watered or false,
                            plantedAt = plotInfo.plantedAt,
                        }
                        -- Time reconciliation: advance crop stage if enough time passed
                        if plotInfo.plantedAt and plotInfo.stage and plotInfo.stage < 3 then
                            local elapsed = os.time() - plotInfo.plantedAt
                            local growthPerStage = 60 -- 60 seconds per stage
                            local stagesGrown = math.floor(elapsed / growthPerStage)
                            if stagesGrown > 0 then
                                farmState.plots[plotId].stage = math.min(3, plotInfo.stage + stagesGrown)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Barracks
    if savedState.barracks then
        local br = savedState.barracks
        BarracksState.level = br.level or 1
        BarracksState.xp = br.xp or 0
        BarracksState.xpToNextLevel = br.xpToNextLevel or 100
    end

    -- Town Hall
    if savedState.townHall then
        local th = savedState.townHall
        TownHallState.level = th.level or 1
        TownHallState.xp = th.xp or 0
        TownHallState.xpToNextLevel = th.xpToNextLevel or 100
        TownHallState.population = th.population or 10

        -- Sync TH level to DataService
        if DataService and _villageOwnerUserId then
            local ownerPlayer = Players:GetPlayerByUserId(_villageOwnerUserId)
            if ownerPlayer then
                local playerData = DataService:GetPlayerData(ownerPlayer)
                if playerData then
                    playerData.townHallLevel = TownHallState.level
                end
            end
        end
        if th.jewelCase then
            TownHallState.jewelCase.maxSlots = th.jewelCase.maxSlots or 3
            if th.jewelCase.slots then
                for slotIdStr, slotData in th.jewelCase.slots do
                    local slotIdx = tonumber(slotIdStr) or slotIdStr
                    TownHallState.jewelCase.slots[slotIdx] = {
                        type = slotData.type,
                        size = slotData.size,
                        boost = slotData.boost,
                        multiplier = slotData.multiplier,
                        color = slotData.color and Color3.fromRGB(
                            slotData.color.r or 255,
                            slotData.color.g or 255,
                            slotData.color.b or 255
                        ) or nil,
                    }
                end
            end
        end
        if th.buildingLevels then
            for k, v in th.buildingLevels do
                TownHallState.buildingLevels[k] = v
            end
        end
        if th.shields then
            TownHallState.shields.isActive = th.shields.isActive or false
            TownHallState.shields.duration = th.shields.duration or 0
            TownHallState.shields.endTime = th.shields.endTime or 0
            -- Time reconciliation: expire shields that ended while offline
            if TownHallState.shields.isActive and TownHallState.shields.endTime > 0 then
                if os.time() >= TownHallState.shields.endTime then
                    TownHallState.shields.isActive = false
                    TownHallState.shields.duration = 0
                    TownHallState.shields.endTime = 0
                    print("[Reconstruct] Shield expired while offline")
                end
            end
        end
        if th.research then
            TownHallState.research.completed = th.research.completed or {}
            -- Convert saved research time back to tick()-based for the running timer
            if th.research.inProgress and th.research.inProgress.id then
                local ip = th.research.inProgress
                local elapsed = os.time() - (ip.savedAt or os.time())
                local remaining = math.max(0, (ip.remainingTime or 0) - elapsed)
                if remaining > 0 then
                    local now = tick()
                    TownHallState.research.inProgress = {
                        id = ip.id,
                        startTime = now,
                        endTime = now + remaining,
                    }
                    print(string.format("[Reconstruct] Research '%s' resuming with %.0fs remaining", ip.id, remaining))
                else
                    -- Research completed while offline — will be completed by the timer loop
                    local now = tick()
                    TownHallState.research.inProgress = {
                        id = ip.id,
                        startTime = now - 1,
                        endTime = now - 1, -- Already expired, timer will call completeResearch()
                    }
                    print(string.format("[Reconstruct] Research '%s' completed while offline", ip.id))
                end
            else
                TownHallState.research.inProgress = nil
            end
        end
    end

    -- Farm Data (plot purchases)
    if savedState.farmData then
        if _villageOwnerUserId then
            PlayerFarmData[_villageOwnerUserId] = {
                farmPlots = savedState.farmData.farmPlots or 1,
                builtFarms = {},
            }
            if savedState.farmData.builtFarms then
                for k, v in savedState.farmData.builtFarms do
                    local num = tonumber(k)
                    if num then
                        PlayerFarmData[_villageOwnerUserId].builtFarms[num] = v
                    end
                end
            end
        end
    end

    print("[SimpleTest] Saved state applied successfully")
end

-- Reconstruct workers from saved counts (call AFTER buildings are created)
local function reconstructWorkers(savedState, ownerUserId)
    if not savedState then return end
    print("[SimpleTest] Reconstructing workers from saved state...")

    -- Clear waiting NPCs at hiring stands (they represent unfilled slots)
    -- We'll remove as many waiting workers as we have saved workers

    -- Gold Mine miners
    local minerCount = savedState.goldMine and savedState.goldMine.minerCount or 0
    for i = 1, minerCount do
        -- Remove a waiting miner (visual at hiring stand)
        if #GoldMineState.waitingMiners > 0 then
            local waitingWorker = table.remove(GoldMineState.waitingMiners, 1)
            _npcAnimTracks[waitingWorker] = nil
            waitingWorker:Destroy()
        end
        spawnMinerWorker(ownerUserId)
    end
    -- Update hiring sign if all slots filled
    if #GoldMineState.waitingMiners == 0 and GoldMineState.minerSign then
        GoldMineState.minerSign.Text = "FULLY STAFFED"
        GoldMineState.minerSign.TextColor3 = Color3.fromRGB(150, 150, 150)
    end

    -- Gold Mine collectors
    local collectorCount = savedState.goldMine and savedState.goldMine.collectorCount or 0
    for i = 1, collectorCount do
        if #GoldMineState.waitingCollectors > 0 then
            local waitingWorker = table.remove(GoldMineState.waitingCollectors, 1)
            _npcAnimTracks[waitingWorker] = nil
            waitingWorker:Destroy()
        end
        spawnCollectorWorker(ownerUserId)
    end
    if #GoldMineState.waitingCollectors == 0 and GoldMineState.collectorSign then
        GoldMineState.collectorSign.Text = "FULLY STAFFED"
        GoldMineState.collectorSign.TextColor3 = Color3.fromRGB(150, 150, 150)
    end

    -- Loggers
    local loggerCount = savedState.lumberMill and savedState.lumberMill.loggerCount or 0
    for i = 1, loggerCount do
        if #LumberMillState.waitingLoggers > 0 then
            local waitingWorker = table.remove(LumberMillState.waitingLoggers, 1)
            _npcAnimTracks[waitingWorker] = nil
            waitingWorker:Destroy()
        end
        spawnLoggerWorker()
    end

    -- Haulers
    local haulerCount = savedState.lumberMill and savedState.lumberMill.haulerCount or 0
    for i = 1, haulerCount do
        if #LumberMillState.waitingHaulers > 0 then
            local waitingWorker = table.remove(LumberMillState.waitingHaulers, 1)
            _npcAnimTracks[waitingWorker] = nil
            waitingWorker:Destroy()
        end
        spawnHaulerWorker(ownerUserId)
    end

    -- Farmers and Carriers (per farm)
    if savedState.farms then
        for farmNumStr, farmData in savedState.farms do
            local farmNumber = tonumber(farmNumStr)
            if farmNumber and FarmStates[farmNumber] then
                local farmerCount = farmData.farmerCount or 0
                for i = 1, farmerCount do
                    local fs = FarmStates[farmNumber]
                    if fs.waitingFarmers and #fs.waitingFarmers > 0 then
                        local waitingWorker = table.remove(fs.waitingFarmers, 1)
                        _npcAnimTracks[waitingWorker] = nil
                        waitingWorker:Destroy()
                    end
                    spawnFarmerWorker(farmNumber)
                end
                if FarmStates[farmNumber].waitingFarmers and #FarmStates[farmNumber].waitingFarmers == 0 and FarmStates[farmNumber].farmerSign then
                    FarmStates[farmNumber].farmerSign.Text = "FULLY STAFFED"
                    FarmStates[farmNumber].farmerSign.TextColor3 = Color3.fromRGB(150, 150, 150)
                end

                local carrierCount = farmData.carrierCount or 0
                for i = 1, carrierCount do
                    local fs = FarmStates[farmNumber]
                    if fs.waitingCarriers and #fs.waitingCarriers > 0 then
                        local waitingWorker = table.remove(fs.waitingCarriers, 1)
                        _npcAnimTracks[waitingWorker] = nil
                        waitingWorker:Destroy()
                    end
                    spawnCarrierWorker(farmNumber, ownerUserId)
                end
                if FarmStates[farmNumber].waitingCarriers and #FarmStates[farmNumber].waitingCarriers == 0 and FarmStates[farmNumber].carrierSign then
                    FarmStates[farmNumber].carrierSign.Text = "FULLY STAFFED"
                    FarmStates[farmNumber].carrierSign.TextColor3 = Color3.fromRGB(150, 150, 150)
                end
            end
        end
    end

    print(string.format("[SimpleTest] Worker reconstruction complete: %d miners, %d collectors, %d loggers, %d haulers",
        minerCount, collectorCount, loggerCount, haulerCount))
end

-- ============================================================================
-- MAIN EXECUTION
-- ============================================================================

-- In reserved server mode, Main.server.lua blocks at PlayerAdded:Wait() before
-- calling VillageStateService:Init(). We must wait for that initialization to
-- complete so GetLoadedState() returns saved data instead of nil.
local _isReservedServer = (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)

if _isReservedServer and VillageStateService then
    print("[SimpleTest] Reserved server detected, waiting for VillageStateService init...")
    local waitStart = os.clock()
    while not VillageStateService:GetOwnerUserId() do
        if os.clock() - waitStart > 30 then
            warn("[SimpleTest] Timed out waiting for VillageStateService init (30s), proceeding with defaults")
            break
        end
        task.wait(0.1)
    end
    local ownerId = VillageStateService:GetOwnerUserId()
    if ownerId then
        _villageOwnerUserId = ownerId
        print(string.format("[SimpleTest] VillageStateService ready, owner: %d", ownerId))
    end
end

-- Load saved state BEFORE building creation (so state tables have correct values)
local savedState = nil
if VillageStateService then
    savedState = VillageStateService:GetLoadedState()
    if savedState then
        print("[SimpleTest] Applying saved village state...")
        applyLoadedState(savedState)
    else
        print("[SimpleTest] No saved state found, building with defaults")
    end
end

local success, errorMsg = pcall(function()
    createGround()
    createEntranceGate()
    createResourceBoard()
    createGoldMine()
    createLumberMill()

    -- Build farms: Farm 1 always, additional farms from saved state
    createFarm(1)
    if savedState and savedState.farmData and savedState.farmData.builtFarms then
        for farmNumStr, built in savedState.farmData.builtFarms do
            local farmNum = tonumber(farmNumStr)
            if farmNum and farmNum > 1 and built then
                createFarm(farmNum)
            end
        end
    end

    createBarracks()
    createTownHall()
    createDecorations()

    -- ========== KILL ZONES (respawn players who fall out of bounds) ==========
    local function createKillZone(name, pos, sz)
        local zone = Instance.new("Part")
        zone.Name = name
        zone.Size = sz
        zone.Position = pos
        zone.Anchored = true
        zone.Transparency = 1
        zone.CanCollide = false
        zone.Parent = workspace
        zone.Touched:Connect(function(hit)
            local character = hit.Parent
            local humanoid = character and character:FindFirstChild("Humanoid")
            if not humanoid then return end
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(60, GROUND_Y + 5, 18)
            end
        end)
    end
    -- Main village kill zone
    createKillZone("VillageKillZone", Vector3.new(60, -50, 90), Vector3.new(500, 5, 500))
    -- Interior kill zones (below each interior Y level)
    createKillZone("GoldMineKillZone", Vector3.new(0, 440, 0), Vector3.new(500, 5, 500))
    createKillZone("LumberMillKillZone", Vector3.new(0, 540, 0), Vector3.new(500, 5, 500))
    createKillZone("FarmKillZone", Vector3.new(0, 640, 0), Vector3.new(500, 5, 500))
    createKillZone("BarracksKillZone", Vector3.new(0, 790, 0), Vector3.new(500, 5, 500))
    createKillZone("TownHallKillZone", Vector3.new(0, 890, 0), Vector3.new(500, 5, 500))
end)

if success then
    -- Reconstruct workers AFTER buildings are created (need model references + positions)
    if savedState and _villageOwnerUserId then
        pcall(function()
            reconstructWorkers(savedState, _villageOwnerUserId)
        end)
    end

    -- Expose state tables for VillageStateService serialization
    if VillageStateService then
        VillageStateService:SetStateTables({
            GoldMineState = GoldMineState,
            LumberMillState = LumberMillState,
            FarmStates = FarmStates,
            BarracksState = BarracksState,
            TownHallState = TownHallState,
            PlayerFarmData = PlayerFarmData,
        })
        VillageStateService:StartAutoSave()
    end

    print("========================================")
    print("GAMEPLAY VILLAGE BUILT SUCCESSFULLY!")
    print("========================================")
else
    warn("========================================")
    warn("VILLAGE BUILD FAILED!")
    warn("Error: " .. tostring(errorMsg))
    warn("========================================")
end

-- ============================================================================
-- PLAYER ROLE MANAGEMENT & SAVE TRIGGERS
-- ============================================================================

-- Detect player roles on join (owner vs visitor)
Players.PlayerAdded:Connect(function(player)
    local joinData = player:GetJoinData()
    local teleportData = joinData and joinData.TeleportData

    if teleportData and teleportData.isOwner then
        _playerRoles[player.UserId] = "owner"
        _villageOwnerUserId = player.UserId
        print(string.format("[Village] %s joined as OWNER", player.Name))

        -- Safety net: if saved state wasn't applied during main execution (e.g.
        -- VillageStateService init timed out), apply it now
        if VillageStateService and VillageStateService:GetOwnerUserId() then
            local lateState = VillageStateService:GetLoadedState()
            if lateState and not savedState then
                print("[Village] Applying saved state on owner join (late recovery)")
                applyLoadedState(lateState)
                pcall(function()
                    reconstructWorkers(lateState, player.UserId)
                end)
            end
        end

        -- Sync owner's HUD with their resources (wait for DataService to load)
        if DataService then
            task.defer(function()
                -- Wait for DataService to load player data (may take a moment after join)
                local waitStart2 = os.clock()
                local playerData = DataService:GetPlayerData(player)
                while not playerData and os.clock() - waitStart2 < 10 do
                    task.wait(0.5)
                    playerData = DataService:GetPlayerData(player)
                end
                if playerData and player.Parent then
                    local Events = ReplicatedStorage:FindFirstChild("Events")
                    if Events then
                        local SyncPlayerData = Events:FindFirstChild("SyncPlayerData")
                        if SyncPlayerData then
                            SyncPlayerData:FireClient(player, playerData)
                        end
                    end
                end
            end)
        end
    elseif teleportData and teleportData.ownerUserId then
        _playerRoles[player.UserId] = "visitor"
        print(string.format("[Village] %s joined as VISITOR", player.Name))
    else
        -- No teleport data (Studio/direct join): first player is owner
        if not _villageOwnerUserId then
            _villageOwnerUserId = player.UserId
            _playerRoles[player.UserId] = "owner"
            print(string.format("[Village] %s is OWNER (first player, no teleport data)", player.Name))

            -- If VillageStateService exists but wasn't initialized (Studio mode),
            -- initialize it now with the first player as owner
            if VillageStateService and not VillageStateService:GetOwnerUserId() then
                pcall(function()
                    VillageStateService:Init(player.UserId)
                    local savedState2 = VillageStateService:GetLoadedState()
                    if savedState2 then
                        applyLoadedState(savedState2)
                        reconstructWorkers(savedState2, player.UserId)
                    end
                    VillageStateService:SetStateTables({
                        GoldMineState = GoldMineState,
                        LumberMillState = LumberMillState,
                        FarmStates = FarmStates,
                        BarracksState = BarracksState,
                        TownHallState = TownHallState,
                        PlayerFarmData = PlayerFarmData,
                    })
                    VillageStateService:StartAutoSave()
                end)
            end
        else
            _playerRoles[player.UserId] = "visitor"
            print(string.format("[Village] %s is VISITOR (no teleport data, owner already set)", player.Name))
        end
    end
end)

-- Catch up: process players who joined before the PlayerAdded handler was connected
-- (This is a standard Roblox pattern - PlayerAdded can fire before the handler is registered
--  if the script yields during init, e.g. waiting for VillageStateService)
for _, player in Players:GetPlayers() do
    if not _playerRoles[player.UserId] then
        local joinData = player:GetJoinData()
        local teleportData = joinData and joinData.TeleportData

        if teleportData and teleportData.isOwner then
            _playerRoles[player.UserId] = "owner"
            _villageOwnerUserId = player.UserId
            print(string.format("[Village] %s retroactively set as OWNER (joined before handler)", player.Name))
        elseif teleportData and teleportData.ownerUserId then
            _playerRoles[player.UserId] = "visitor"
            print(string.format("[Village] %s retroactively set as VISITOR (joined before handler)", player.Name))
        else
            -- No teleport data (Studio/direct join): first player is owner
            if not _villageOwnerUserId then
                _villageOwnerUserId = player.UserId
                _playerRoles[player.UserId] = "owner"
                print(string.format("[Village] %s retroactively set as OWNER (first player, joined before handler)", player.Name))

                -- Initialize VillageStateService for Studio mode if needed
                if VillageStateService and not VillageStateService:GetOwnerUserId() then
                    pcall(function()
                        VillageStateService:Init(player.UserId)
                        local savedState2 = VillageStateService:GetLoadedState()
                        if savedState2 then
                            applyLoadedState(savedState2)
                            reconstructWorkers(savedState2, player.UserId)
                        end
                        VillageStateService:SetStateTables({
                            GoldMineState = GoldMineState,
                            LumberMillState = LumberMillState,
                            FarmStates = FarmStates,
                            BarracksState = BarracksState,
                            TownHallState = TownHallState,
                            PlayerFarmData = PlayerFarmData,
                        })
                        VillageStateService:StartAutoSave()
                    end)
                end
            else
                _playerRoles[player.UserId] = "visitor"
                print(string.format("[Village] %s retroactively set as VISITOR (joined before handler)", player.Name))
            end
        end

        -- Sync HUD for the owner
        if _playerRoles[player.UserId] == "owner" and DataService then
            task.defer(function()
                local waitStart2 = os.clock()
                local playerData = DataService:GetPlayerData(player)
                while not playerData and os.clock() - waitStart2 < 10 do
                    task.wait(0.5)
                    playerData = DataService:GetPlayerData(player)
                end
                if playerData and player.Parent then
                    local Events = ReplicatedStorage:FindFirstChild("Events")
                    if Events then
                        local SyncPlayerData = Events:FindFirstChild("SyncPlayerData")
                        if SyncPlayerData then
                            SyncPlayerData:FireClient(player, playerData)
                        end
                    end
                end
            end)
        end
    end
end

-- Save village state when owner leaves
Players.PlayerRemoving:Connect(function(player)
    if player.UserId == _villageOwnerUserId then
        print(string.format("[Village] Owner %s leaving, saving and releasing lock...", player.Name))
        if VillageStateService then
            pcall(function()
                VillageStateService:Shutdown()
            end)
        end
    end
    _playerRoles[player.UserId] = nil
    -- Clean up per-player transient state
    PlayerReturnPositions[player.UserId] = nil
    PlayerCurrentBuilding[player.UserId] = nil
    TeleportCooldown[player.UserId] = nil
    PlayerFarmData[player.UserId] = nil
end)

-- Serialize village state on server shutdown (DataService handles actual persistence)
game:BindToClose(function()
    if VillageStateService then
        print("[Village] Server shutting down, serializing village state into playerData...")
        pcall(function()
            VillageStateService:SaveState()
        end)
    end
end)
