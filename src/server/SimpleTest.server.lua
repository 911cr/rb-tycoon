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
    Farm1 = { exitPos = Vector3.new(30, 3, 100), buildingPos = Vector3.new(25, 0, 100) },        -- Exit east of building
    Farm2 = { exitPos = Vector3.new(30, 3, 130), buildingPos = Vector3.new(25, 0, 130) },
    Farm3 = { exitPos = Vector3.new(90, 3, 130), buildingPos = Vector3.new(95, 0, 130) },
    Farm4 = { exitPos = Vector3.new(15, 3, 115), buildingPos = Vector3.new(10, 0, 115) },
    Farm5 = { exitPos = Vector3.new(105, 3, 115), buildingPos = Vector3.new(110, 0, 115) },
    Farm6 = { exitPos = Vector3.new(60, 3, 135), buildingPos = Vector3.new(60, 0, 140) },
    Barracks = { exitPos = Vector3.new(90, 3, 100), buildingPos = Vector3.new(95, 0, 100) },     -- Exit west of building
    TownHall = { exitPos = Vector3.new(60, 3, 150), buildingPos = Vector3.new(60, 0, 155) },     -- Exit south of building
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

    local gui = Instance.new("SurfaceGui")
    gui.Face = Enum.NormalId.Front
    gui.Parent = signBoard

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 230, 180)
    label.TextScaled = true
    label.Font = Enum.Font.Antique
    label.Parent = gui
    return signBoard
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

local function createInteraction(part, actionText, objectText, holdDuration, callback)
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = actionText or "Interact"
    prompt.ObjectText = objectText or ""
    prompt.HoldDuration = holdDuration or 0.5
    prompt.MaxActivationDistance = 8
    prompt.RequiresLineOfSight = false
    prompt.Parent = part

    if callback then
        prompt.Triggered:Connect(callback)
    end

    return prompt
end

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

    -- Gambrel roof (classic barn roof - 4 panels)
    -- Using simple angled triangular roof instead of complex gambrel for reliability
    local roofOverhang = 1.5
    local roofPeakHeight = 5 -- Height of roof peak above walls

    -- Left roof slope (from wall top to center peak)
    local roofLeft = Instance.new("Part")
    roofLeft.Name = "RoofLeft"
    -- Width needs to span from left edge to center, accounting for slope
    local roofSlopeWidth = math.sqrt((size.X/2)^2 + roofPeakHeight^2) + 0.5
    roofLeft.Size = Vector3.new(roofSlopeWidth, 0.5, size.Z + roofOverhang * 2)
    -- Position at midpoint between wall top-left and peak
    local roofLeftPos = position + rotateOffset(Vector3.new(-size.X/4, wallHeight + roofPeakHeight/2, 0))
    -- Calculate slope angle
    local slopeAngle = math.deg(math.atan2(roofPeakHeight, size.X/2))
    roofLeft.Position = roofLeftPos
    roofLeft.Orientation = Vector3.new(0, rotation, slopeAngle)
    roofLeft.Anchored = true
    roofLeft.Material = Enum.Material.Metal
    roofLeft.Color = roofGray
    roofLeft.Parent = exterior

    -- Right roof slope (from wall top to center peak)
    local roofRight = Instance.new("Part")
    roofRight.Name = "RoofRight"
    roofRight.Size = Vector3.new(roofSlopeWidth, 0.5, size.Z + roofOverhang * 2)
    local roofRightPos = position + rotateOffset(Vector3.new(size.X/4, wallHeight + roofPeakHeight/2, 0))
    roofRight.Position = roofRightPos
    roofRight.Orientation = Vector3.new(0, rotation, -slopeAngle)
    roofRight.Anchored = true
    roofRight.Material = Enum.Material.Metal
    roofRight.Color = roofGray
    roofRight.Parent = exterior

    -- Roof ridge cap (peak)
    local roofRidge = Instance.new("Part")
    roofRidge.Name = "RoofRidge"
    roofRidge.Size = Vector3.new(1, 0.6, size.Z + roofOverhang * 2)
    roofRidge.Position = position + Vector3.new(0, wallHeight + roofPeakHeight, 0)
    roofRidge.Orientation = Vector3.new(0, rotation, 0)
    roofRidge.Anchored = true
    roofRidge.Material = Enum.Material.Metal
    roofRidge.Color = Color3.fromRGB(60, 60, 65)
    roofRidge.Parent = exterior

    -- Front gable (triangular wall piece under roof at front)
    local frontGable = Instance.new("WedgePart")
    frontGable.Name = "FrontGable"
    frontGable.Size = Vector3.new(roofPeakHeight, size.X, 0.5)
    local gableFrontPos = position + rotateOffset(Vector3.new(0, wallHeight + roofPeakHeight/2, size.Z/2 + 0.25))
    frontGable.CFrame = CFrame.new(gableFrontPos) * CFrame.Angles(0, math.rad(rotation), math.rad(-90))
    frontGable.Anchored = true
    frontGable.Material = Enum.Material.Wood
    frontGable.Color = barnRed
    frontGable.Parent = exterior

    -- Back gable (triangular wall piece under roof at back)
    local backGable = Instance.new("WedgePart")
    backGable.Name = "BackGable"
    backGable.Size = Vector3.new(roofPeakHeight, size.X, 0.5)
    local gableBackPos = position + rotateOffset(Vector3.new(0, wallHeight + roofPeakHeight/2, -size.Z/2 - 0.25))
    backGable.CFrame = CFrame.new(gableBackPos) * CFrame.Angles(0, math.rad(rotation + 180), math.rad(-90))
    backGable.Anchored = true
    backGable.Material = Enum.Material.Wood
    backGable.Color = barnRed
    backGable.Parent = exterior

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
    createSign(exterior, name, position + rotateOffset(Vector3.new(0, wallHeight + roofHeight + 1.5, size.Z/2 + 1)), Vector3.new(8, 2.5, 0.3))

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

    -- Roof
    local roof = Instance.new("Part")
    roof.Name = "Roof"
    roof.Size = Vector3.new(size.X + 2, 1, size.Z + 2)
    roof.Position = position + Vector3.new(0, wallHeight + 0.5, 0)
    roof.Orientation = Vector3.new(0, rotation, 0)
    roof.Anchored = true
    roof.Material = Enum.Material.Slate
    roof.Color = roofColor
    roof.Parent = exterior

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
    -- Add resources to player's local storage (for mini-game tracking)
    local resources = getPlayerResources(player)
    if resources[resourceType] then
        resources[resourceType] = resources[resourceType] + amount
        print(string.format("[REWARD] %s gained +%d %s! (Local total: %d)",
            player.Name, amount, resourceType, resources[resourceType]))
    else
        warn("[REWARD] Unknown resource type:", resourceType)
    end

    -- UPDATE DATASERVICE (this is what the HUD reads from!)
    if DataService then
        local playerData = DataService:GetPlayerData(player)
        if playerData then
            -- Build resource change table based on type
            local changes = {}
            changes[resourceType] = amount

            -- Update resources in DataService
            local success = DataService:UpdateResources(player, changes)
            if success then
                print(string.format("[REWARD] Updated DataService: %s +%d %s (DataService total: %d)",
                    player.Name, amount, resourceType, playerData.resources[resourceType] or 0))

                -- Fire SyncPlayerData to update the HUD
                local Events = ReplicatedStorage:FindFirstChild("Events")
                if Events then
                    local SyncPlayerData = Events:FindFirstChild("SyncPlayerData")
                    if SyncPlayerData then
                        SyncPlayerData:FireClient(player, playerData)
                        print(string.format("[REWARD] Synced HUD for %s", player.Name))
                    end
                end
            else
                warn("[REWARD] Failed to update DataService for", player.Name)
            end
        else
            warn("[REWARD] No player data found for", player.Name)
        end
    else
        warn("[REWARD] DataService not available yet")
    end

    -- Fire event to client to show reward notification
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if Events then
        local ServerResponse = Events:FindFirstChild("ServerResponse")
        if ServerResponse then
            ServerResponse:FireClient(player, "MiniGameReward", {
                success = true,
                resourceType = resourceType,
                amount = amount,
                building = buildingName,
                newTotal = resources[resourceType]
            })
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
    ground.Material = Enum.Material.Grass
    ground.Color = Color3.fromRGB(80, 130, 60)
    ground.Parent = villageFolder

    -- Main cobblestone path (runs from entrance to Town Hall at the end)
    local mainPath = Instance.new("Part")
    mainPath.Name = "MainPath"
    mainPath.Size = Vector3.new(12, 0.1, 150)  -- Wider, longer path
    mainPath.Position = Vector3.new(60, GROUND_Y + 0.05, 90)
    mainPath.Anchored = true
    mainPath.Material = Enum.Material.Cobblestone
    mainPath.Color = Color3.fromRGB(100, 95, 90)
    mainPath.Parent = villageFolder

    -- Cross path at first row of buildings (Gold Mine / Lumber Mill)
    local crossPath1 = Instance.new("Part")
    crossPath1.Name = "CrossPath1"
    crossPath1.Size = Vector3.new(90, 0.1, 8)
    crossPath1.Position = Vector3.new(60, GROUND_Y + 0.05, 50)
    crossPath1.Anchored = true
    crossPath1.Material = Enum.Material.Cobblestone
    crossPath1.Color = Color3.fromRGB(100, 95, 90)
    crossPath1.Parent = villageFolder

    -- Cross path at second row of buildings (Farm / Barracks)
    local crossPath2 = Instance.new("Part")
    crossPath2.Name = "CrossPath2"
    crossPath2.Size = Vector3.new(90, 0.1, 8)
    crossPath2.Position = Vector3.new(60, GROUND_Y + 0.05, 100)
    crossPath2.Anchored = true
    crossPath2.Material = Enum.Material.Cobblestone
    crossPath2.Color = Color3.fromRGB(100, 95, 90)
    crossPath2.Parent = villageFolder

    -- Town Hall plaza at the end
    local plaza = Instance.new("Part")
    plaza.Name = "TownHallPlaza"
    plaza.Size = Vector3.new(40, 0.1, 30)
    plaza.Position = Vector3.new(60, GROUND_Y + 0.05, 155)
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

    -- Tower tops (conical/pyramid)
    for _, tower in {leftTower, rightTower} do
        local top = Instance.new("Part")
        top.Size = Vector3.new(10, 4, 10)
        top.Position = tower.Position + Vector3.new(0, 12, 0)
        top.Anchored = true
        top.Material = Enum.Material.Slate
        top.Color = Color3.fromRGB(60, 55, 50)
        top.Parent = gateModel
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

    gateModel.Parent = villageFolder
    print("  ✓ Entrance gate created")
end

-- ============================================================================
-- NPC WORKER SYSTEM
-- Creates visible animated workers that walk between stations
-- ============================================================================

-- Create a simple NPC worker model
local function createWorkerNPC(name, position, color)
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
    local torso = npc:FindFirstChild("Torso")
    if not torso then return end

    local offset = newPosition - (torso.Position - Vector3.new(0, 3, 0))

    -- Move all parts recursively (including those in child models like CarriedItem)
    local function moveParts(parent)
        for _, child in parent:GetChildren() do
            if child:IsA("BasePart") then
                child.Position = child.Position + offset
            elseif child:IsA("Model") then
                moveParts(child)  -- Recursively move parts in child models
            end
        end
    end

    moveParts(npc)
end

-- Animate NPC walking to a destination
local function walkNPCTo(npc, destination, speed, callback)
    local torso = npc:FindFirstChild("Torso")
    if not torso then return end

    local startPos = torso.Position - Vector3.new(0, 3, 0)
    local endPos = Vector3.new(destination.X, startPos.Y, destination.Z)
    local distance = (endPos - startPos).Magnitude
    local duration = distance / (speed or 8)

    -- Face destination
    local direction = (endPos - startPos).Unit
    local lookAt = CFrame.lookAt(startPos, endPos)

    local elapsed = 0
    local walkConnection
    local legPhase = 0

    walkConnection = RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        local alpha = math.min(elapsed / duration, 1)

        -- Lerp position
        local currentPos = startPos:Lerp(endPos, alpha)
        moveNPC(npc, currentPos)

        -- Animate legs
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
            -- Reset leg positions
            if leftLeg then leftLeg.Position = currentPos + Vector3.new(-0.4, 1, 0) end
            if rightLeg then rightLeg.Position = currentPos + Vector3.new(0.4, 1, 0) end
            if leftArm then leftArm.Position = currentPos + Vector3.new(-1, 3, 0) end
            if rightArm then rightArm.Position = currentPos + Vector3.new(1, 3, 0) end
            if callback then callback() end
        end
    end)

    return walkConnection
end

-- Add carried item visual to NPC (uses welds so items follow NPC movement)
local function setNPCCarrying(npc, itemType, amount)
    -- Remove existing carried item
    local existingItem = npc:FindFirstChild("CarriedItem")
    if existingItem then existingItem:Destroy() end

    if not itemType or amount <= 0 then return end

    local torso = npc:FindFirstChild("Torso")
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

        -- Ore chunks on top of sack (brown/gray rock chunks)
        for i = 1, math.min(amount, 3) do
            createWeldedPart({
                name = "Ore" .. i,
                size = Vector3.new(0.3, 0.3, 0.3),
                material = Enum.Material.Slate,
                color = Color3.fromRGB(100, 85, 70) -- Brown/gray ore color
            }, CFrame.new((i-2) * 0.25, 0.5 + sackHeight/2 + 0.15, 0.8))
        end
    elseif itemType == "gold" then
        -- Gold bars/ingots stacked on back
        for i = 1, math.min(amount, 3) do
            createWeldedPart({
                name = "GoldBar" .. i,
                size = Vector3.new(0.6, 0.3, 0.3),
                material = Enum.Material.Metal,
                color = Color3.fromRGB(255, 200, 50) -- Gold color
            }, CFrame.new((i-2) * 0.3, 0.5 + (i-1) * 0.35, 0.7))
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

        -- Individual log visuals
        for i = 1, math.min(amount, 4) do
            createWeldedPart({
                name = "Log" .. i,
                size = Vector3.new(1.6, 0.35, 0.35),
                shape = Enum.PartType.Cylinder,
                material = Enum.Material.Wood,
                color = Color3.fromRGB(90 + math.random(20), 60 + math.random(10), 40)
            }, CFrame.new(0, 0.3 + bundleHeight/2 + (i-1) * 0.2, 0.8) * CFrame.Angles(0, math.rad(90), 0))
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

        -- Crop visuals on top
        for i = 1, math.min(amount, 3) do
            createWeldedPart({
                name = "Crop" .. i,
                size = Vector3.new(0.4, 0.4, 0.4),
                material = Enum.Material.Grass,
                color = Color3.fromRGB(230, 200, 80) -- Wheat/grain color
            }, CFrame.new((i-2) * 0.3, 0.5 + basketHeight/2 + 0.2, 0.8))
        end
    elseif itemType == "grain" then
        -- Grain sacks
        for i = 1, math.min(amount, 3) do
            createWeldedPart({
                name = "GrainSack" .. i,
                size = Vector3.new(0.6, 0.8, 0.5),
                material = Enum.Material.Fabric,
                color = Color3.fromRGB(210, 190, 150)
            }, CFrame.new((i-2) * 0.35, 0.4 + (i-1) * 0.2, 0.7))
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

        -- Food items on top
        for i = 1, math.min(amount, 3) do
            createWeldedPart({
                name = "Food" .. i,
                size = Vector3.new(0.35, 0.35, 0.35),
                material = Enum.Material.SmoothPlastic,
                color = Color3.fromRGB(255, 220, 150) -- Bread/food color
            }, CFrame.new((i-2) * 0.3, 0.5 + crateHeight/2 + 0.2, 0.8))
        end
    end
end

-- ============================================================================
-- GEM SYSTEM - Prospecting and Trophy Case
-- Gems provide city-wide production bonuses when displayed in Town Hall
-- ============================================================================

-- Gem type definitions with colors and boost types
local GemTypes = {
    Ruby = { color = Color3.fromRGB(220, 20, 60), boost = "production" },
    Emerald = { color = Color3.fromRGB(0, 201, 87), boost = "speed" },
    Sapphire = { color = Color3.fromRGB(15, 82, 186), boost = "defense" },
    Diamond = { color = Color3.fromRGB(185, 242, 255), boost = "all" },
}

-- Gem size multipliers and rarity (probability of getting each size on success)
local GemSizes = {
    Chip = { multiplier = 1.05, rarity = 0.50 },   -- 50% of successful prospects
    Stone = { multiplier = 1.10, rarity = 0.30 },  -- 30% of successful prospects
    Gem = { multiplier = 1.20, rarity = 0.15 },    -- 15% of successful prospects
    Jewel = { multiplier = 1.35, rarity = 0.05 },  -- 5% of successful prospects
}

-- Gem rarity by prospecting tier (chance to get each gem type)
local GemRarityByTier = {
    [1] = { Ruby = 0.50, Emerald = 0.35, Sapphire = 0.14, Diamond = 0.01 }, -- Basic
    [2] = { Ruby = 0.35, Emerald = 0.35, Sapphire = 0.25, Diamond = 0.05 }, -- Advanced
    [3] = { Ruby = 0.25, Emerald = 0.30, Sapphire = 0.30, Diamond = 0.15 }, -- Premium
}

-- Prospecting tier costs and duration
local ProspectingTiers = {
    [1] = { name = "Basic", cost = 500, duration = 300 },    -- 5 minutes, 500 gold
    [2] = { name = "Advanced", cost = 2000, duration = 300 }, -- 5 minutes, 2000 gold
    [3] = { name = "Premium", cost = 5000, duration = 300 },  -- 5 minutes, 5000 gold
}

-- Roll a gem based on prospecting tier (returns gem data or nil)
local function rollGem(tier)
    -- Determine gem type based on tier-specific rarity
    local rarityTable = GemRarityByTier[tier] or GemRarityByTier[1]
    local roll = math.random()
    local cumulative = 0
    local gemType = "Ruby" -- Default fallback

    for gType, chance in pairs(rarityTable) do
        cumulative = cumulative + chance
        if roll <= cumulative then
            gemType = gType
            break
        end
    end

    -- Determine gem size
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

    return {
        type = gemType,
        size = gemSize,
        color = GemTypes[gemType].color,
        boost = GemTypes[gemType].boost,
        multiplier = GemSizes[gemSize].multiplier,
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
    [1] = { gold = 500, food = 100 },
    [2] = { gold = 1500, food = 300 },
    [3] = { gold = 5000, food = 1000 },
}

local CollectorCosts = {
    [1] = { gold = 300, food = 50 },
    [2] = { gold = 1000, food = 200 },
    [3] = { gold = 3000, food = 600 },
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

    -- Hanging sign off to the LEFT side (not blocking approach path)
    local signPost = Instance.new("Part")
    signPost.Name = "SignPost"
    signPost.Size = Vector3.new(0.4, 5, 0.4)
    signPost.Position = Vector3.new(exteriorX + 6, extGround + 2.5, exteriorZ - 10)
    signPost.Anchored = true
    signPost.Material = Enum.Material.Wood
    signPost.Color = Color3.fromRGB(50, 35, 20)
    signPost.Parent = mineEntrance

    local signBoard = Instance.new("Part")
    signBoard.Name = "Sign"
    signBoard.Size = Vector3.new(0.3, 1.8, 5)
    signBoard.Position = Vector3.new(exteriorX + 6.2, extGround + 5.5, exteriorZ - 10)
    signBoard.Orientation = Vector3.new(0, 90, -5)
    signBoard.Anchored = true
    signBoard.Material = Enum.Material.Wood
    signBoard.Color = Color3.fromRGB(70, 50, 30)
    signBoard.Parent = mineEntrance

    local gui = Instance.new("SurfaceGui")
    gui.Face = Enum.NormalId.Front
    gui.Parent = signBoard

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "GOLD MINE"
    label.TextColor3 = Color3.fromRGB(255, 215, 0)
    label.TextScaled = true
    label.Font = Enum.Font.Antique
    label.Parent = gui

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
        oreVein = Vector3.new(baseX - 37, GROUND_Y, baseZ + 10),     -- Left wall: ore vein embedded in wall (wall at -40)
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

        local oreGained = stats.orePerSwing
        local newOre = math.min(currentOre + oreGained, maxOre)
        setPlayerOre(player, newOre)
        addMineXP(5)

        print(string.format("[GoldMine] %s mined %d ore! (Lv%d Pickaxe) Carrying: %d/%d",
            player.Name, newOre - currentOre, pickaxeLevel, newOre, maxOre))

        -- Mining sparkle effect
        local sparkle = Instance.new("ParticleEmitter")
        sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
        sparkle.Size = NumberSequence.new(0.4)
        sparkle.Lifetime = NumberRange.new(0.3, 0.6)
        sparkle.Rate = 40
        sparkle.Speed = NumberRange.new(4, 8)
        sparkle.Parent = oreVeinBase
        task.delay(0.5, function() sparkle:Destroy() end)
    end)

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
                local goldPerOre = smelterStats.goldPerOre
                local smeltTime = smelterStats.smeltTime

                -- Process one ore at a time
                while GoldMineState.smelterOre > 0 do
                    -- Recheck stats each ore (in case player upgrades mid-batch)
                    smelterStats = getSmelterStats(GoldMineState.equipment.smelterLevel)
                    goldPerOre = smelterStats.goldPerOre
                    smeltTime = smelterStats.smeltTime

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
            Color3.fromRGB(100, 80, 60)
        )
        setNPCStatus(waitingMiner, "For hire!")
        waitingMiner.Parent = mineModel
        table.insert(GoldMineState.waitingMiners, waitingMiner)
    end

    -- INTERACTION: Hire Miner (on the table)
    local minerHirePrompt = createInteraction(minerTable, "Hire Miner (500 gold)", "Hiring Table", 1, function(player)
        -- Check if any waiting workers left at the stand
        if #GoldMineState.waitingMiners == 0 then
            print(string.format("[GoldMine] %s: No workers available to hire!", player.Name))
            return
        end

        local minerCount = #GoldMineState.miners
        local maxMiners = 3

        if minerCount >= maxMiners then
            print(string.format("[GoldMine] %s: Max miners (3) reached!", player.Name))
            return
        end

        local cost = MinerCosts[minerCount + 1]
        local minerId = minerCount + 1

        -- Remove one waiting worker from the stand (they walk away to work)
        local waitingWorker = table.remove(GoldMineState.waitingMiners, 1)
        if waitingWorker then
            -- Make the waiting worker walk away before destroying
            local workerTorso = waitingWorker:FindFirstChild("Torso")
            if workerTorso then
                local walkAwayPos = GoldMineState.positions.workerSpawn + Vector3.new(minerCount * 3, 0, 0)
                walkNPCTo(waitingWorker, walkAwayPos, 6, function()
                    waitingWorker:Destroy()
                end)
            else
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

        -- Create visible miner NPC
        local spawnPos = GoldMineState.positions.workerSpawn + Vector3.new(minerCount * 3, 0, 0)
        local miner = createWorkerNPC(
            "Miner " .. minerId,
            spawnPos,
            Color3.fromRGB(139, 90, 43) -- Brown work clothes
        )
        miner.Parent = mineModel

        -- Create pickaxe for the miner
        local pickaxe = Instance.new("Part")
        pickaxe.Name = "Pickaxe"
        pickaxe.Size = Vector3.new(0.2, 2, 0.2)
        pickaxe.Anchored = true
        pickaxe.CanCollide = false
        pickaxe.Material = Enum.Material.Wood
        pickaxe.Color = Color3.fromRGB(100, 70, 45)
        pickaxe.Parent = miner

        local pickaxeHead = Instance.new("Part")
        pickaxeHead.Name = "PickaxeHead"
        pickaxeHead.Size = Vector3.new(0.8, 0.3, 0.2)
        pickaxeHead.Anchored = true
        pickaxeHead.CanCollide = false
        pickaxeHead.Material = Enum.Material.Metal
        pickaxeHead.Color = Color3.fromRGB(140, 140, 150)
        pickaxeHead.Parent = miner

        local minerData = {
            npc = miner,
            state = "idle",
            carrying = 0,
            pickaxe = pickaxe,
            pickaxeHead = pickaxeHead,
        }
        table.insert(GoldMineState.miners, minerData)

        -- Function to update pickaxe position relative to miner
        local function updatePickaxePosition()
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
                local orePos = GoldMineState.positions.oreVein + Vector3.new(math.random(-3, 3), 0, math.random(-2, 2))
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
                        local torso = miner:FindFirstChild("Torso")
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
            Color3.fromRGB(60, 100, 60) -- Green work clothes
        )
        setNPCStatus(waitingCollector, "For hire!")
        waitingCollector.Parent = mineModel
        table.insert(GoldMineState.waitingCollectors, waitingCollector)
    end

    -- INTERACTION: Hire Collector (on the table)
    local collectorHirePrompt = createInteraction(collectorTable, "Hire Collector (300 gold)", "Hiring Table", 1, function(player)
        -- Check if any waiting workers left at the stand
        if #GoldMineState.waitingCollectors == 0 then
            print(string.format("[GoldMine] %s: No collectors available to hire!", player.Name))
            return
        end

        local collectorCount = #GoldMineState.collectors
        local maxCollectors = 3

        if collectorCount >= maxCollectors then
            print(string.format("[GoldMine] %s: Max collectors (3) reached!", player.Name))
            return
        end

        local cost = CollectorCosts[collectorCount + 1]
        local collectorId = collectorCount + 1

        -- Remove one waiting worker from the stand (they walk away to work)
        local waitingWorker = table.remove(GoldMineState.waitingCollectors, 1)
        if waitingWorker then
            -- Make the waiting worker walk away before destroying
            local workerTorso = waitingWorker:FindFirstChild("Torso")
            if workerTorso then
                local walkAwayPos = GoldMineState.positions.workerSpawn + Vector3.new(collectorCount * 3 + 10, 0, 0)
                walkNPCTo(waitingWorker, walkAwayPos, 6, function()
                    waitingWorker:Destroy()
                end)
            else
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

        -- Create visible collector NPC
        local spawnPos = GoldMineState.positions.workerSpawn + Vector3.new(collectorCount * 3 + 10, 0, 0)
        local collector = createWorkerNPC(
            "Collector " .. collectorId,
            spawnPos,
            Color3.fromRGB(60, 100, 60) -- Green work clothes
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
                            local torso = collector:FindFirstChild("Torso")
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
            -- TODO: Check gold and deduct
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
            GoldMineState.equipment.smelterLevel = currentLevel + 1
            addMineXP(50)
            print(string.format("[Upgrade] %s upgraded Smelter to Lv%d! Now %d gold/ore, %.1fs (-%d gold)",
                player.Name, currentLevel + 1, nextStats.goldPerOre, nextStats.smeltTime, nextStats.upgradeCost))
            createUpgradeGui(player)
        end)

        minersBtn.MouseButton1Click:Connect(function()
            local currentLevel = GoldMineState.equipment.minerLevel
            local nextStats = getMinerStats(currentLevel + 1)
            GoldMineState.equipment.minerLevel = currentLevel + 1
            addMineXP(50)
            print(string.format("[Upgrade] %s upgraded Miners to Lv%d! Now %d ore capacity (-%d gold)",
                player.Name, currentLevel + 1, nextStats.oreCapacity, nextStats.upgradeCost))
            createUpgradeGui(player)
        end)

        collectorsBtn.MouseButton1Click:Connect(function()
            local currentLevel = GoldMineState.equipment.collectorLevel
            local nextStats = getCollectorStats(currentLevel + 1)
            GoldMineState.equipment.collectorLevel = currentLevel + 1
            addMineXP(50)
            print(string.format("[Upgrade] %s upgraded Collectors to Lv%d! Now %d gold capacity (-%d gold)",
                player.Name, currentLevel + 1, nextStats.goldCapacity, nextStats.upgradeCost))
            createUpgradeGui(player)
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

    -- Prospecting state display function
    local function updateProspectingDisplay()
        local state = GoldMineState.prospecting
        if state.isActive then
            local remaining = state.endTime - tick()
            if remaining > 0 then
                local minutes = math.floor(remaining / 60)
                local seconds = math.floor(remaining % 60)
                timerLabel.Text = string.format("Prospecting: %d:%02d", minutes, seconds)
                timerLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
                resultGem.Transparency = 1 -- Hide while prospecting
            else
                timerLabel.Text = "READY TO COLLECT!"
                timerLabel.TextColor3 = Color3.fromRGB(50, 255, 50)
                resultGem.Transparency = 0 -- Show mystery gem
                resultGem.Color = Color3.fromRGB(200, 180, 100) -- Mystery color
            end
        else
            timerLabel.Text = "GEM PROSPECTING"
            timerLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
            resultGem.Transparency = 1
        end
    end

    -- Start prospecting interaction
    local startProspectPrompt = Instance.new("ProximityPrompt")
    startProspectPrompt.Name = "StartProspectPrompt"
    startProspectPrompt.ObjectText = "Gem Prospecting"
    startProspectPrompt.ActionText = "Invest Gold"
    startProspectPrompt.HoldDuration = 0.5
    startProspectPrompt.MaxActivationDistance = 8
    startProspectPrompt.Parent = prospectingTable

    startProspectPrompt.Triggered:Connect(function(player)
        local state = GoldMineState.prospecting

        -- Check if already prospecting
        if state.isActive then
            local remaining = state.endTime - tick()
            if remaining > 0 then
                local minutes = math.floor(remaining / 60)
                local seconds = math.floor(remaining % 60)
                print(string.format("[GoldMine] Prospecting in progress... %d:%02d remaining", minutes, seconds))
                return
            else
                -- Ready to collect!
                local success = math.random() < 0.5 -- 50% success rate

                if success then
                    local gem = rollGem(state.tier)
                    GoldMineState.playerHeldGem[player.UserId] = gem

                    -- Show gem visual
                    resultGem.Color = gem.color
                    resultGem.Transparency = 0

                    -- Size based on gem size
                    local sizeMap = { Chip = 0.5, Stone = 0.7, Gem = 0.9, Jewel = 1.2 }
                    local visualSize = sizeMap[gem.size] or 0.8
                    resultGem.Size = Vector3.new(visualSize, visualSize, visualSize)

                    print(string.format("[GoldMine] %s found a %s %s!",
                        player.Name, gem.size, gem.type))
                    print(string.format("  Bonus: +%.0f%% %s", (gem.multiplier - 1) * 100, gem.boost))
                    print("  Take it to the Town Hall Trophy Case to display!")

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
                else
                    print(string.format("[GoldMine] %s: No gems found this time. Better luck next prospect!", player.Name))
                end

                -- Reset state
                state.isActive = false
                state.tier = nil
                task.delay(1, updateProspectingDisplay)
                return
            end
        end

        -- Show tier options
        print("[GoldMine] === GEM PROSPECTING ===")
        print("  Select investment tier (higher = better gems):")
        for i, tier in ipairs(ProspectingTiers) do
            local rarityTable = GemRarityByTier[i]
            print(string.format("    %d. %s (%d gold) - Diamond chance: %.0f%%",
                i, tier.name, tier.cost, (rarityTable.Diamond or 0) * 100))
        end
        print("")
        print("  [Demo: Starting Basic prospecting]")

        -- Start basic prospecting for demo
        local tier = 1
        local tierData = ProspectingTiers[tier]

        -- TODO: Check and deduct gold
        print(string.format("[GoldMine] %s started %s prospecting! (%d gold)",
            player.Name, tierData.name, tierData.cost))

        state.isActive = true
        state.tier = tier
        state.startTime = tick()
        state.endTime = tick() + tierData.duration

        updateProspectingDisplay()
    end)

    -- Update timer every second
    task.spawn(function()
        while true do
            task.wait(1)
            if GoldMineState.prospecting.isActive then
                updateProspectingDisplay()
            end
        end
    end)

    -- ========== EXIT PORTAL ==========
    createExitPortal(mineModel, Vector3.new(baseX, GROUND_Y + 4, baseZ + 28))

    -- Parent the mine interior
    mineModel.Parent = interiorsFolder

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
    [1] = { gold = 400, food = 80 },
    [2] = { gold = 1200, food = 250 },
    [3] = { gold = 4000, food = 800 },
}

local HaulerCosts = {
    [1] = { gold = 300, food = 60 },
    [2] = { gold = 900, food = 180 },
    [3] = { gold = 2700, food = 540 },
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

    -- ===== SIGN =====
    local signBoard = Instance.new("Part")
    signBoard.Name = "Sign"
    signBoard.Size = Vector3.new(0.5, 2.5, 10)
    signBoard.Position = Vector3.new(exteriorX - 5.5, extGround + 10, exteriorZ)
    signBoard.Anchored = true
    signBoard.Material = Enum.Material.Wood
    signBoard.Color = Color3.fromRGB(60, 40, 25)
    signBoard.Parent = lumberYard

    local gui = Instance.new("SurfaceGui")
    gui.Face = Enum.NormalId.Left  -- Face west toward path
    gui.Parent = signBoard

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "LUMBER YARD"
    label.TextColor3 = Color3.fromRGB(255, 230, 180)
    label.TextScaled = true
    label.Font = Enum.Font.Antique
    label.Parent = gui

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
        upgradeKiosk = Vector3.new(baseX, GROUND_Y, baseZ + 10),    -- Center, behind spawn
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
    dirtPath.Position = Vector3.new(baseX, GROUND_Y + 0.1, baseZ)
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
    leftTreeGrove.Position = Vector3.new(baseX - 25, GROUND_Y + 0.1, baseZ)
    leftTreeGrove.Anchored = true
    leftTreeGrove.Material = Enum.Material.Grass
    leftTreeGrove.Color = Color3.fromRGB(60, 100, 45)
    leftTreeGrove.Parent = millModel

    -- Right tree grove ground
    local rightTreeGrove = Instance.new("Part")
    rightTreeGrove.Name = "RightTreeGroveGround"
    rightTreeGrove.Size = Vector3.new(20, 0.2, 40)
    rightTreeGrove.Position = Vector3.new(baseX + 25, GROUND_Y + 0.1, baseZ)
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
                end)
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
            end)
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
                local planksPerLog = sawmillStats.planksPerLog
                local processTime = sawmillStats.processTime

                -- Process one log at a time
                while LumberMillState.sawmillLogs > 0 do
                    -- Recheck stats each log (in case player upgrades mid-batch)
                    sawmillStats = getSawmillStats(LumberMillState.equipment.sawmillLevel)
                    planksPerLog = sawmillStats.planksPerLog
                    processTime = sawmillStats.processTime

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
            Color3.fromRGB(180, 50, 50) -- Red plaid
        )
        setNPCStatus(waitingLogger, "For hire!")
        waitingLogger.Parent = millModel
        table.insert(LumberMillState.waitingLoggers, waitingLogger)
    end

    -- INTERACTION: Hire Logger
    createInteraction(loggerBoard, "Hire Logger", "Hiring Board", 1, function(player)
        local loggerCount = #LumberMillState.loggers
        local maxLoggers = 3

        if loggerCount >= maxLoggers then
            print(string.format("[LumberMill] %s: Max loggers (3) reached!", player.Name))
            return
        end

        -- Check if there are waiting workers
        if #LumberMillState.waitingLoggers == 0 then
            print(string.format("[LumberMill] %s: No loggers available to hire!", player.Name))
            return
        end

        local cost = LoggerCosts[loggerCount + 1]
        local loggerId = loggerCount + 1

        -- Remove one waiting worker from the stand (they walk away to work)
        local waitingWorker = table.remove(LumberMillState.waitingLoggers, 1)
        if waitingWorker then
            -- Make the waiting worker walk away before destroying
            setNPCStatus(waitingWorker, "Hired!")
            task.spawn(function()
                local walkAwayPos = LumberMillState.positions.workerSpawn + Vector3.new(loggerCount * 3, 0, 0)
                walkNPCTo(waitingWorker, walkAwayPos, 6, function()
                    waitingWorker:Destroy()
                end)
            end)
        end

        -- Check if booth is now empty
        if #LumberMillState.waitingLoggers == 0 then
            print("[LumberMill] Logger booth is now empty!")
        end

        -- Create visible logger NPC at spawn position
        local spawnPos = LumberMillState.positions.workerSpawn + Vector3.new(loggerCount * 3, 0, 0)
        local logger = createWorkerNPC(
            "Logger " .. loggerId,
            spawnPos,
            Color3.fromRGB(180, 50, 50) -- Red plaid work clothes
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
                            local torso = logger:FindFirstChild("Torso")
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
            Color3.fromRGB(60, 100, 60) -- Green work clothes
        )
        setNPCStatus(waitingHauler, "For hire!")
        waitingHauler.Parent = millModel
        table.insert(LumberMillState.waitingHaulers, waitingHauler)
    end

    -- INTERACTION: Hire Hauler
    createInteraction(haulerBoard, "Hire Hauler", "Hiring Board", 1, function(player)
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
        local haulerId = haulerCount + 1

        -- Remove one waiting worker from the stand (they walk away to work)
        local waitingWorker = table.remove(LumberMillState.waitingHaulers, 1)
        if waitingWorker then
            -- Make the waiting worker walk away before destroying
            setNPCStatus(waitingWorker, "Hired!")
            task.spawn(function()
                local walkAwayPos = LumberMillState.positions.workerSpawn + Vector3.new(haulerCount * 3 + 10, 0, 0)
                walkNPCTo(waitingWorker, walkAwayPos, 6, function()
                    waitingWorker:Destroy()
                end)
            end)
        end

        -- Check if booth is now empty
        if #LumberMillState.waitingHaulers == 0 then
            print("[LumberMill] Hauler booth is now empty!")
        end

        -- Create visible hauler NPC at spawn position
        local spawnPos = LumberMillState.positions.workerSpawn + Vector3.new(haulerCount * 3 + 10, 0, 0)
        local hauler = createWorkerNPC(
            "Hauler " .. haulerId,
            spawnPos,
            Color3.fromRGB(60, 100, 60) -- Green work clothes
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
                            local torso = hauler:FindFirstChild("Torso")
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

    -- ========== STEP 6: UPGRADE KIOSK (RIGHT SIDE - not blocking entrance) ==========
    local upgradeArea = LumberMillState.positions.upgradeKiosk

    -- Main upgrade station structure
    local upgradeBench = Instance.new("Part")
    upgradeBench.Name = "UpgradeBench"
    upgradeBench.Size = Vector3.new(12, 3, 6)
    upgradeBench.Position = upgradeArea + Vector3.new(0, 1.5, 0)
    upgradeBench.Anchored = true
    upgradeBench.Material = Enum.Material.Wood
    upgradeBench.Color = Color3.fromRGB(85, 60, 40)
    upgradeBench.Parent = millModel

    local grindWheel = Instance.new("Part")
    grindWheel.Name = "GrindingWheel"
    grindWheel.Shape = Enum.PartType.Cylinder
    grindWheel.Size = Vector3.new(1, 3, 3)
    grindWheel.Position = upgradeArea + Vector3.new(-4, 3.5, 0)
    grindWheel.Orientation = Vector3.new(0, 0, 90)
    grindWheel.Anchored = true
    grindWheel.Material = Enum.Material.Cobblestone
    grindWheel.Color = Color3.fromRGB(130, 125, 120)
    grindWheel.Parent = millModel

    local toolRack = Instance.new("Part")
    toolRack.Name = "ToolRack"
    toolRack.Size = Vector3.new(4, 4, 0.5)
    toolRack.Position = upgradeArea + Vector3.new(4, 3.5, -2)
    toolRack.Anchored = true
    toolRack.Material = Enum.Material.Wood
    toolRack.Color = Color3.fromRGB(90, 65, 45)
    toolRack.Parent = millModel

    createSign(millModel, "UPGRADE SHOP", upgradeArea + Vector3.new(0, 6, 3), Vector3.new(8, 1.5, 0.3))

    -- Upgrade status billboard
    local upgradeBillboard = Instance.new("BillboardGui")
    upgradeBillboard.Name = "UpgradeStatus"
    upgradeBillboard.Size = UDim2.new(14, 0, 8, 0)
    upgradeBillboard.StudsOffset = Vector3.new(0, 8, 0)
    upgradeBillboard.AlwaysOnTop = true
    upgradeBillboard.Parent = upgradeBench

    local upgradeFrame = Instance.new("Frame")
    upgradeFrame.Size = UDim2.new(1, 0, 1, 0)
    upgradeFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 20)
    upgradeFrame.BackgroundTransparency = 0.2
    upgradeFrame.BorderSizePixel = 0
    upgradeFrame.Parent = upgradeBillboard

    local upgradeTitle = Instance.new("TextLabel")
    upgradeTitle.Size = UDim2.new(1, 0, 0.15, 0)
    upgradeTitle.Position = UDim2.new(0, 0, 0, 0)
    upgradeTitle.BackgroundTransparency = 1
    upgradeTitle.Text = "UPGRADE SHOP"
    upgradeTitle.TextColor3 = Color3.fromRGB(180, 140, 90)
    upgradeTitle.TextScaled = true
    upgradeTitle.Font = Enum.Font.GothamBold
    upgradeTitle.Parent = upgradeFrame

    -- Function to update the upgrade display (LEVEL-BASED, UNLIMITED)
    local function updateLumberUpgradeDisplay()
        -- Clear existing upgrade labels (except title)
        for _, child in upgradeFrame:GetChildren() do
            if child.Name:match("^Upgrade") then
                child:Destroy()
            end
        end

        local yPos = 0.18

        -- 1. Axe upgrade
        local axeLevel = LumberMillState.equipment.axeLevel
        local axeStats = getAxeStats(axeLevel)
        local axeNextStats = getAxeStats(axeLevel + 1)
        local axeLabel = Instance.new("TextLabel")
        axeLabel.Name = "Upgrade1"
        axeLabel.Size = UDim2.new(1, 0, 0.18, 0)
        axeLabel.Position = UDim2.new(0, 0, yPos, 0)
        axeLabel.BackgroundTransparency = 1
        axeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        axeLabel.TextScaled = true
        axeLabel.Font = Enum.Font.Gotham
        axeLabel.Text = string.format("1. AXE Lv%d→%d | %d→%d logs | Cost: %d",
            axeLevel, axeLevel + 1, axeStats.logsPerChop, axeNextStats.logsPerChop, axeNextStats.upgradeCost)
        axeLabel.Parent = upgradeFrame
        yPos = yPos + 0.19

        -- 2. Sawmill upgrade
        local sawmillLevel = LumberMillState.equipment.sawmillLevel
        local sawmillStats = getSawmillStats(sawmillLevel)
        local sawmillNextStats = getSawmillStats(sawmillLevel + 1)
        local sawmillLabel = Instance.new("TextLabel")
        sawmillLabel.Name = "Upgrade2"
        sawmillLabel.Size = UDim2.new(1, 0, 0.18, 0)
        sawmillLabel.Position = UDim2.new(0, 0, yPos, 0)
        sawmillLabel.BackgroundTransparency = 1
        sawmillLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        sawmillLabel.TextScaled = true
        sawmillLabel.Font = Enum.Font.Gotham
        sawmillLabel.Text = string.format("2. SAWMILL Lv%d→%d | %dp/log, %.1fs | Cost: %d",
            sawmillLevel, sawmillLevel + 1, sawmillNextStats.planksPerLog, sawmillNextStats.processTime, sawmillNextStats.upgradeCost)
        sawmillLabel.Parent = upgradeFrame
        yPos = yPos + 0.19

        -- 3. Logger upgrade
        local loggerLevel = LumberMillState.equipment.loggerLevel
        local loggerStats = getLoggerStats(loggerLevel)
        local loggerNextStats = getLoggerStats(loggerLevel + 1)
        local loggerLabel = Instance.new("TextLabel")
        loggerLabel.Name = "Upgrade3"
        loggerLabel.Size = UDim2.new(1, 0, 0.18, 0)
        loggerLabel.Position = UDim2.new(0, 0, yPos, 0)
        loggerLabel.BackgroundTransparency = 1
        loggerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        loggerLabel.TextScaled = true
        loggerLabel.Font = Enum.Font.Gotham
        loggerLabel.Text = string.format("3. LOGGERS Lv%d→%d | %d→%d log cap | Cost: %d",
            loggerLevel, loggerLevel + 1, loggerStats.logCapacity, loggerNextStats.logCapacity, loggerNextStats.upgradeCost)
        loggerLabel.Parent = upgradeFrame
        yPos = yPos + 0.19

        -- 4. Hauler upgrade
        local haulerLevel = LumberMillState.equipment.haulerLevel
        local haulerStats = getHaulerStats(haulerLevel)
        local haulerNextStats = getHaulerStats(haulerLevel + 1)
        local haulerLabel = Instance.new("TextLabel")
        haulerLabel.Name = "Upgrade4"
        haulerLabel.Size = UDim2.new(1, 0, 0.18, 0)
        haulerLabel.Position = UDim2.new(0, 0, yPos, 0)
        haulerLabel.BackgroundTransparency = 1
        haulerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        haulerLabel.TextScaled = true
        haulerLabel.Font = Enum.Font.Gotham
        haulerLabel.Text = string.format("4. HAULERS Lv%d→%d | %d→%d plank cap | Cost: %d",
            haulerLevel, haulerLevel + 1, haulerStats.plankCapacity, haulerNextStats.plankCapacity, haulerNextStats.upgradeCost)
        haulerLabel.Parent = upgradeFrame
    end

    -- Initial display
    updateLumberUpgradeDisplay()

    -- Create 4 interaction parts for each upgrade (pedestals)
    local lumberUpgradePositions = {
        { name = "Axe", offset = Vector3.new(-4.5, 0, 3), color = Color3.fromRGB(139, 90, 43) },
        { name = "Sawmill", offset = Vector3.new(-1.5, 0, 3), color = Color3.fromRGB(180, 140, 90) },
        { name = "LoggerGear", offset = Vector3.new(1.5, 0, 3), color = Color3.fromRGB(180, 50, 50) },
        { name = "HaulerGear", offset = Vector3.new(4.5, 0, 3), color = Color3.fromRGB(60, 100, 60) },
    }

    local lumberPedestals = {}
    for i, upgradeInfo in lumberUpgradePositions do
        local pedestal = Instance.new("Part")
        pedestal.Name = upgradeInfo.name .. "Pedestal"
        pedestal.Size = Vector3.new(2, 1, 2)
        pedestal.Position = upgradeArea + upgradeInfo.offset + Vector3.new(0, 0.5, 0)
        pedestal.Anchored = true
        pedestal.Material = Enum.Material.Cobblestone
        pedestal.Color = upgradeInfo.color
        pedestal.Parent = millModel
        lumberPedestals[i] = pedestal

        local numberSign = Instance.new("TextLabel")
        local signBillboard = Instance.new("BillboardGui")
        signBillboard.Size = UDim2.new(2, 0, 1, 0)
        signBillboard.StudsOffset = Vector3.new(0, 1.5, 0)
        signBillboard.AlwaysOnTop = true
        signBillboard.Parent = pedestal
        numberSign.Size = UDim2.new(1, 0, 1, 0)
        numberSign.BackgroundTransparency = 1
        numberSign.Text = tostring(i)
        numberSign.TextColor3 = Color3.fromRGB(255, 255, 255)
        numberSign.TextStrokeTransparency = 0
        numberSign.TextScaled = true
        numberSign.Font = Enum.Font.GothamBold
        numberSign.Parent = signBillboard
    end

    -- INTERACTION: Upgrade Axe (pedestal 1) - UNLIMITED LEVELS
    createInteraction(lumberPedestals[1], "Buy Axe Upgrade", "Pedestal 1", 1.5, function(player)
        local currentLevel = LumberMillState.equipment.axeLevel
        local nextLevel = currentLevel + 1
        local nextStats = getAxeStats(nextLevel)
        local cost = nextStats.upgradeCost

        -- TODO: Check if player has enough gold and deduct
        LumberMillState.equipment.axeLevel = nextLevel
        addLumberXP(50)
        updateLumberUpgradeDisplay()
        print(string.format("[Upgrade] %s upgraded Axe to Lv%d! Now %d logs/chop (-%d gold)",
            player.Name, nextLevel, nextStats.logsPerChop, cost))
    end)

    -- INTERACTION: Upgrade Sawmill (pedestal 2) - UNLIMITED LEVELS
    createInteraction(lumberPedestals[2], "Buy Sawmill Upgrade", "Pedestal 2", 1.5, function(player)
        local currentLevel = LumberMillState.equipment.sawmillLevel
        local nextLevel = currentLevel + 1
        local nextStats = getSawmillStats(nextLevel)
        local cost = nextStats.upgradeCost

        LumberMillState.equipment.sawmillLevel = nextLevel
        addLumberXP(50)
        updateLumberUpgradeDisplay()
        print(string.format("[Upgrade] %s upgraded Sawmill to Lv%d! Now %d planks/log, %.1fs (-%d gold)",
            player.Name, nextLevel, nextStats.planksPerLog, nextStats.processTime, cost))
    end)

    -- INTERACTION: Upgrade Logger Gear (pedestal 3) - UNLIMITED LEVELS
    createInteraction(lumberPedestals[3], "Buy Logger Upgrade", "Pedestal 3", 1.5, function(player)
        local currentLevel = LumberMillState.equipment.loggerLevel
        local nextLevel = currentLevel + 1
        local nextStats = getLoggerStats(nextLevel)
        local cost = nextStats.upgradeCost

        LumberMillState.equipment.loggerLevel = nextLevel
        addLumberXP(50)
        updateLumberUpgradeDisplay()
        print(string.format("[Upgrade] %s upgraded Loggers to Lv%d! Now %d log capacity (-%d gold)",
            player.Name, nextLevel, nextStats.logCapacity, cost))
    end)

    -- INTERACTION: Upgrade Hauler Gear (pedestal 4) - UNLIMITED LEVELS
    createInteraction(lumberPedestals[4], "Buy Hauler Upgrade", "Pedestal 4", 1.5, function(player)
        local currentLevel = LumberMillState.equipment.haulerLevel
        local nextLevel = currentLevel + 1
        local nextStats = getHaulerStats(nextLevel)
        local cost = nextStats.upgradeCost

        LumberMillState.equipment.haulerLevel = nextLevel
        addLumberXP(50)
        updateLumberUpgradeDisplay()
        print(string.format("[Upgrade] %s upgraded Haulers to Lv%d! Now %d plank capacity (-%d gold)",
            player.Name, nextLevel, nextStats.plankCapacity, cost))
    end)

    -- ========== EXIT PORTAL ==========
    createExitPortal(millModel, Vector3.new(baseX, GROUND_Y + 4, baseZ + 28))

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
    [1] = { gold = 400, food = 80 },
    [2] = { gold = 1200, food = 250 },
    [3] = { gold = 4000, food = 800 },
}

local CarrierCosts = {
    [1] = { gold = 300, food = 60 },
    [2] = { gold = 900, food = 180 },
    [3] = { gold = 2700, food = 540 },
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
    cropsLabel.Size = UDim2.new(1, 0, 0.35, 0)
    cropsLabel.Position = UDim2.new(0, 0, 0.65, 0)
    cropsLabel.BackgroundTransparency = 1
    cropsLabel.Text = "🌱 Crops: 0 | Level 1"
    cropsLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
    cropsLabel.TextScaled = true
    cropsLabel.Font = Enum.Font.GothamMedium
    cropsLabel.Parent = statsFrame

    -- Function to update exterior stats
    currentFarmState.updateExteriorStats = function()
        local totalCrops = currentFarmState.harvestPile + currentFarmState.windmillCrops
        foodLabel.Text = string.format("🌾 Food: %d", currentFarmState.foodStorage)
        cropsLabel.Text = string.format("🌱 Crops: %d | Level %d", totalCrops, currentFarmState.level)
    end

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
    mainPath.Position = Vector3.new(baseX, GROUND_Y + 0.1, baseZ)
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

    -- INTERACTION: Get Seeds
    createInteraction(seedShed, "Get Seeds", "Seed Shed", 0.5, function(player)
        print(string.format("[Farm] %s grabbed wheat seeds! Go plant them in the field.", player.Name))
        addFarmXP(2)
    end)

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
                end)
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
    centralPath.Position = Vector3.new(baseX, GROUND_Y + 0.1, baseZ)
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
    end)

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
                local grainPerCrop = windmillStats.grainPerCrop
                local processTime = windmillStats.processTime

                -- Process one crop at a time
                while FarmState.windmillCrops > 0 do
                    -- Recheck stats each crop (in case player upgrades mid-batch)
                    windmillStats = getWindmillStatsFunc(FarmState.equipment.windmillLevel)
                    grainPerCrop = windmillStats.grainPerCrop
                    processTime = windmillStats.processTime

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

    -- Waiting farmer NPCs (for visual) - positioned in front of barn toward center
    for i = 1, 2 do
        local waitingFarmerPos = hireFarmerPos + Vector3.new(3 + i * 2, 0, 0) -- Offset toward center (right)
        local waitingFarmer = createWorkerNPC(
            "Farmer " .. i,
            waitingFarmerPos,
            Color3.fromRGB(100, 140, 100) -- Green overalls
        )
        setNPCStatus(waitingFarmer, "For hire!")
        waitingFarmer.Parent = farmModel
    end

    -- INTERACTION: Hire Farmer NPC
    createInteraction(barn, "Hire Farmer", "Barn", 1, function(player)
        local farmerCount = #FarmState.farmers
        local maxFarmers = 3

        if farmerCount >= maxFarmers then
            print(string.format("[Farm] %s: Max farmers (3) reached!", player.Name))
            return
        end

        local cost = FarmerCosts[farmerCount + 1]
        local farmerId = farmerCount + 1

        -- Create visible farmer NPC
        local spawnPos = FarmState.positions.workerSpawn + Vector3.new(farmerCount * 3, 0, 0)
        local farmer = createWorkerNPC(
            "Farmer " .. farmerId,
            spawnPos,
            Color3.fromRGB(100, 140, 100) -- Green overalls
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
                        local torso = farmer:FindFirstChild("Torso")
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

    -- Waiting carrier NPCs - positioned in front of station toward center
    for i = 1, 2 do
        local waitingCarrierPos = hireCarrierPos + Vector3.new(-3 - i * 2, 0, 0) -- Offset toward center (left)
        local waitingCarrier = createWorkerNPC(
            "Carrier " .. i,
            waitingCarrierPos,
            Color3.fromRGB(60, 100, 60) -- Darker green work clothes
        )
        setNPCStatus(waitingCarrier, "For hire!")
        waitingCarrier.Parent = farmModel
    end

    -- INTERACTION: Hire Carrier NPC
    createInteraction(carrierBoard, "Hire Carrier", "Hiring Board", 1, function(player)
        local carrierCount = #FarmState.carriers
        local maxCarriers = 3

        if carrierCount >= maxCarriers then
            print(string.format("[Farm] %s: Max carriers (3) reached!", player.Name))
            return
        end

        local cost = CarrierCosts[carrierCount + 1]
        local carrierId = carrierCount + 1

        -- Create visible carrier NPC
        local spawnPos = FarmState.positions.workerSpawn + Vector3.new(carrierCount * 3 + 10, 0, 0)
        local carrier = createWorkerNPC(
            "Carrier " .. carrierId,
            spawnPos,
            Color3.fromRGB(60, 100, 60) -- Darker green work clothes
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
                            -- Deliver food for gold
                            carrierData.state = "delivering"
                            setNPCStatus(carrier, "Delivering...")
                            task.wait(1)

                            local foodDelivered = carrierData.carrying
                            local goldEarned = foodDelivered * 10 -- 10 gold per food

                            carrierData.carrying = 0
                            setNPCCarrying(carrier, nil, 0)

                            -- Delivery sparkle effect
                            local torso = carrier:FindFirstChild("Torso")
                            if torso then
                                local sparkle = Instance.new("ParticleEmitter")
                                sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
                                sparkle.Size = NumberSequence.new(0.4)
                                sparkle.Lifetime = NumberRange.new(0.5, 1)
                                sparkle.Rate = 30
                                sparkle.Speed = NumberRange.new(3, 6)
                                sparkle.SpreadAngle = Vector2.new(60, 60)
                                sparkle.Parent = torso
                                task.delay(0.6, function() sparkle:Destroy() end)
                            end

                            print(string.format("[Carrier #%d] Delivered %d food -> +%d gold!",
                                carrierId, foodDelivered, goldEarned))

                            -- ACTUALLY REWARD THE PLAYER (this was missing!)
                            rewardPlayer(hiringPlayer, "gold", goldEarned, "Carrier")

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
            -- TODO: Check gold and deduct
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
            FarmState.equipment.wateringCanLevel = currentLevel + 1
            addFarmXP(50)
            print(string.format("[Upgrade] %s upgraded Watering Can to Lv%d! Now %d plots/water (-%d gold)",
                player.Name, currentLevel + 1, nextStats.plotsPerWater, nextStats.upgradeCost))
            createFarmUpgradeGui(player)
        end)

        windmillBtn.MouseButton1Click:Connect(function()
            local currentLevel = FarmState.equipment.windmillLevel
            local nextStats = getWindmillStatsFunc(currentLevel + 1)
            FarmState.equipment.windmillLevel = currentLevel + 1
            addFarmXP(50)
            print(string.format("[Upgrade] %s upgraded Windmill to Lv%d! Now %d grain/crop, %.1fs (-%d gold)",
                player.Name, currentLevel + 1, nextStats.grainPerCrop, nextStats.processTime, nextStats.upgradeCost))
            createFarmUpgradeGui(player)
        end)

        farmersBtn.MouseButton1Click:Connect(function()
            local currentLevel = FarmState.equipment.farmerLevel
            local nextStats = getFarmerStats(currentLevel + 1)
            FarmState.equipment.farmerLevel = currentLevel + 1
            addFarmXP(50)
            print(string.format("[Upgrade] %s upgraded Farmers to Lv%d! Now %d crop capacity (-%d gold)",
                player.Name, currentLevel + 1, nextStats.cropCapacity, nextStats.upgradeCost))
            createFarmUpgradeGui(player)
        end)

        carriersBtn.MouseButton1Click:Connect(function()
            local currentLevel = FarmState.equipment.carrierLevel
            local nextStats = getCarrierStats(currentLevel + 1)
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

    -- Parent the farm interior
    farmModel.Parent = interiorsFolder

    print(string.format("  ✓ %s created (REDESIGNED LAYOUT):", farmName))
    print("    - Crop fields on BOTH sides (24 plots total)")
    print("    - Single upgrade kiosk with menu UI")
    print("    - Full progression: Seeds → Plant → Water → Harvest → Process → Collect")
    print("    - Production stats displayed on exterior sign")
end

-- ============================================================================
-- BARRACKS - Military training building with full progression loop
-- ============================================================================
-- PROGRESSION LOOP:
--   1. RECRUIT: Get trainee from Recruitment Board (costs food)
--   2. TRAIN: Take trainee to Training Yard (practice at dummies)
--   3. EQUIP: Take trained recruit to Armory (weapon + armor)
--   4. DEPLOY: Take soldier to Army Camp (joins your army)
--   5. HIRE: Unlock Drill Sergeants at Level 3 (automation)
--   6. UPGRADE: Improve training dummies, weapons, armor at Forge
-- ============================================================================

-- Barracks state
local BarracksState = {
    level = 1,
    xp = 0,
    xpToNextLevel = 100,
    drillSergeants = {},  -- NPC drill sergeants (train recruits)
    equipment = {
        dummies = "Basic",     -- Training dummy quality
        weapons = "Basic",     -- Weapon quality
        armor = "Basic",       -- Armor quality
    },
    playerInventory = {}, -- Per-player: { trainees = 0, trainedRecruits = 0, equippedSoldiers = 0, deployedTroops = 0 }
    -- Player carrying state (for walk-through system)
    playerTrainees = {},     -- [playerId] = trainees being carried
    playerRecruits = {},     -- [playerId] = trained recruits being carried
    playerSoldiers = {},     -- [playerId] = equipped soldiers being carried
    -- Visual update functions (set during creation)
    updateTraineeQueueVisuals = nil,
    updateRecruitQueueVisuals = nil,
    updateSoldierQueueVisuals = nil,
    totalTroopsTrained = 0,
    positions = {},
}

-- Equipment upgrade tiers for Barracks
local DummyStats = {
    Basic = { trainSpeed = 1.0, xpBonus = 1, cost = 0 },
    Reinforced = { trainSpeed = 1.5, xpBonus = 2, cost = 500 },
    Steel = { trainSpeed = 2.0, xpBonus = 3, cost = 2500 },
    Enchanted = { trainSpeed = 3.0, xpBonus = 5, cost = 12000 },
}

local WeaponStats = {
    Basic = { damage = 10, cost = 0 },
    Iron = { damage = 18, cost = 800 },
    Steel = { damage = 28, cost = 4000 },
    Mithril = { damage = 45, cost = 20000 },
}

local ArmorStats = {
    Basic = { defense = 5, cost = 0 },
    Iron = { defense = 12, cost = 600 },
    Steel = { defense = 22, cost = 3000 },
    Mithril = { defense = 40, cost = 15000 },
}

-- Worker (Drill Sergeant) costs
local DrillSergeantCosts = {
    { gold = 300, food = 150 },  -- First sergeant
    { gold = 800, food = 400 },  -- Second
    { gold = 2000, food = 1000 }, -- Third
    { gold = 5000, food = 2500 }, -- Fourth (max)
}

-- Get or initialize player barracks inventory
local function getBarracksInventory(player: Player)
    local id = tostring(player.UserId)
    if not BarracksState.playerInventory[id] then
        BarracksState.playerInventory[id] = {
            trainees = 0,
            trainedRecruits = 0,
            equippedSoldiers = 0,
            deployedTroops = 0,
        }
    end
    return BarracksState.playerInventory[id]
end

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

-- Player carrying helper functions for walk-through system
local function getPlayerTrainees(player: Player): number
    return BarracksState.playerTrainees[player.UserId] or 0
end

local function setPlayerTrainees(player: Player, amount: number)
    BarracksState.playerTrainees[player.UserId] = math.max(0, math.min(amount, 10))
end

local function getPlayerRecruits(player: Player): number
    return BarracksState.playerRecruits[player.UserId] or 0
end

local function setPlayerRecruits(player: Player, amount: number)
    BarracksState.playerRecruits[player.UserId] = math.max(0, math.min(amount, 10))
end

local function getPlayerSoldiers(player: Player): number
    return BarracksState.playerSoldiers[player.UserId] or 0
end

local function setPlayerSoldiers(player: Player, amount: number)
    BarracksState.playerSoldiers[player.UserId] = math.max(0, math.min(amount, 10))
end

--[[
    Updates the visual representation of trainees following the player.
    Shows peasant figures following behind the player.
]]
local function updatePlayerTraineeVisual(player: Player, count: number)
    local character = player.Character
    if not character then return end
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    -- Remove old trainee visuals
    for _, child in character:GetChildren() do
        if child.Name == "TraineeFollower" then
            child:Destroy()
        end
    end

    if count <= 0 then return end

    -- Create trainee figures on player's back (max 3 visible)
    local visibleCount = math.min(count, 3)
    for i = 1, visibleCount do
        local traineeModel = Instance.new("Model")
        traineeModel.Name = "TraineeFollower"

        -- Peasant body (brown tunic)
        local body = Instance.new("Part")
        body.Name = "TraineeBody"
        body.Size = Vector3.new(0.6, 1.2, 0.4)
        body.Position = humanoidRootPart.Position + Vector3.new(-0.8 - (i-1)*0.5, 0.3 + (i-1)*0.4, -0.5)
        body.Anchored = false
        body.CanCollide = false
        body.Material = Enum.Material.Fabric
        body.Color = Color3.fromRGB(139, 119, 101)
        body.Parent = traineeModel

        -- Weld to player
        local bodyWeld = Instance.new("WeldConstraint")
        bodyWeld.Part0 = humanoidRootPart
        bodyWeld.Part1 = body
        bodyWeld.Parent = body

        -- Peasant head
        local head = Instance.new("Part")
        head.Name = "TraineeHead"
        head.Shape = Enum.PartType.Ball
        head.Size = Vector3.new(0.4, 0.4, 0.4)
        head.Position = body.Position + Vector3.new(0, 0.8, 0)
        head.Anchored = false
        head.CanCollide = false
        head.Material = Enum.Material.SmoothPlastic
        head.Color = Color3.fromRGB(227, 183, 151)
        head.Parent = traineeModel

        local headWeld = Instance.new("WeldConstraint")
        headWeld.Part0 = body
        headWeld.Part1 = head
        headWeld.Parent = head

        traineeModel.PrimaryPart = body
        traineeModel.Parent = character
    end

    -- Add count indicator if more than visible
    if count > 3 then
        local countPart = Instance.new("Part")
        countPart.Name = "TraineeFollower"
        countPart.Shape = Enum.PartType.Ball
        countPart.Size = Vector3.new(0.5, 0.5, 0.5)
        countPart.Position = humanoidRootPart.Position + Vector3.new(-2.5, 1.5, -0.5)
        countPart.Anchored = false
        countPart.CanCollide = false
        countPart.Material = Enum.Material.Neon
        countPart.Color = Color3.fromRGB(255, 220, 100)
        countPart.Parent = character

        local countWeld = Instance.new("WeldConstraint")
        countWeld.Part0 = humanoidRootPart
        countWeld.Part1 = countPart
        countWeld.Parent = countPart

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 30, 0, 30)
        billboard.StudsOffset = Vector3.new(0, 0.5, 0)
        billboard.Parent = countPart

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = "x" .. tostring(count)
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard
    end
end

--[[
    Updates the visual representation of trained recruits on the player.
    Shows soldiers with basic armor behind the player.
]]
local function updatePlayerRecruitVisual(player: Player, count: number)
    local character = player.Character
    if not character then return end
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    -- Remove old recruit visuals
    for _, child in character:GetChildren() do
        if child.Name == "RecruitFollower" then
            child:Destroy()
        end
    end

    if count <= 0 then return end

    -- Create recruit figures on player's back (max 3 visible)
    local visibleCount = math.min(count, 3)
    for i = 1, visibleCount do
        local recruitModel = Instance.new("Model")
        recruitModel.Name = "RecruitFollower"

        -- Recruit body (leather armor)
        local body = Instance.new("Part")
        body.Name = "RecruitBody"
        body.Size = Vector3.new(0.7, 1.3, 0.5)
        body.Position = humanoidRootPart.Position + Vector3.new(-0.8 - (i-1)*0.5, 0.3 + (i-1)*0.4, -0.5)
        body.Anchored = false
        body.CanCollide = false
        body.Material = Enum.Material.Leather
        body.Color = Color3.fromRGB(110, 85, 60)
        body.Parent = recruitModel

        -- Weld to player
        local bodyWeld = Instance.new("WeldConstraint")
        bodyWeld.Part0 = humanoidRootPart
        bodyWeld.Part1 = body
        bodyWeld.Parent = body

        -- Recruit head with helmet
        local head = Instance.new("Part")
        head.Name = "RecruitHead"
        head.Shape = Enum.PartType.Ball
        head.Size = Vector3.new(0.45, 0.45, 0.45)
        head.Position = body.Position + Vector3.new(0, 0.85, 0)
        head.Anchored = false
        head.CanCollide = false
        head.Material = Enum.Material.Metal
        head.Color = Color3.fromRGB(100, 95, 90)
        head.Parent = recruitModel

        local headWeld = Instance.new("WeldConstraint")
        headWeld.Part0 = body
        headWeld.Part1 = head
        headWeld.Parent = head

        recruitModel.PrimaryPart = body
        recruitModel.Parent = character
    end

    -- Add count indicator if more than visible
    if count > 3 then
        local countPart = Instance.new("Part")
        countPart.Name = "RecruitFollower"
        countPart.Shape = Enum.PartType.Ball
        countPart.Size = Vector3.new(0.5, 0.5, 0.5)
        countPart.Position = humanoidRootPart.Position + Vector3.new(-2.5, 1.5, -0.5)
        countPart.Anchored = false
        countPart.CanCollide = false
        countPart.Material = Enum.Material.Neon
        countPart.Color = Color3.fromRGB(100, 180, 255)
        countPart.Parent = character

        local countWeld = Instance.new("WeldConstraint")
        countWeld.Part0 = humanoidRootPart
        countWeld.Part1 = countPart
        countWeld.Parent = countPart

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 30, 0, 30)
        billboard.StudsOffset = Vector3.new(0, 0.5, 0)
        billboard.Parent = countPart

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = "x" .. tostring(count)
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard
    end
end

--[[
    Updates the visual representation of equipped soldiers on the player.
    Shows fully armored soldiers with swords behind the player.
]]
local function updatePlayerSoldierVisual(player: Player, count: number)
    local character = player.Character
    if not character then return end
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    -- Remove old soldier visuals
    for _, child in character:GetChildren() do
        if child.Name == "SoldierFollower" then
            child:Destroy()
        end
    end

    if count <= 0 then return end

    -- Create soldier figures on player's back (max 3 visible)
    local visibleCount = math.min(count, 3)
    for i = 1, visibleCount do
        local soldierModel = Instance.new("Model")
        soldierModel.Name = "SoldierFollower"

        -- Soldier body (metal armor)
        local body = Instance.new("Part")
        body.Name = "SoldierBody"
        body.Size = Vector3.new(0.8, 1.4, 0.5)
        body.Position = humanoidRootPart.Position + Vector3.new(-0.8 - (i-1)*0.5, 0.3 + (i-1)*0.4, -0.5)
        body.Anchored = false
        body.CanCollide = false
        body.Material = Enum.Material.Metal
        body.Color = Color3.fromRGB(140, 140, 150)
        body.Parent = soldierModel

        -- Weld to player
        local bodyWeld = Instance.new("WeldConstraint")
        bodyWeld.Part0 = humanoidRootPart
        bodyWeld.Part1 = body
        bodyWeld.Parent = body

        -- Soldier head with full helm
        local head = Instance.new("Part")
        head.Name = "SoldierHead"
        head.Size = Vector3.new(0.5, 0.5, 0.5)
        head.Position = body.Position + Vector3.new(0, 0.95, 0)
        head.Anchored = false
        head.CanCollide = false
        head.Material = Enum.Material.Metal
        head.Color = Color3.fromRGB(100, 100, 110)
        head.Parent = soldierModel

        local headWeld = Instance.new("WeldConstraint")
        headWeld.Part0 = body
        headWeld.Part1 = head
        headWeld.Parent = head

        -- Sword on back
        local sword = Instance.new("Part")
        sword.Name = "SoldierSword"
        sword.Size = Vector3.new(0.1, 1.0, 0.2)
        sword.Position = body.Position + Vector3.new(0.3, 0.2, -0.2)
        sword.Orientation = Vector3.new(0, 0, -25)
        sword.Anchored = false
        sword.CanCollide = false
        sword.Material = Enum.Material.Metal
        sword.Color = Color3.fromRGB(180, 180, 190)
        sword.Parent = soldierModel

        local swordWeld = Instance.new("WeldConstraint")
        swordWeld.Part0 = body
        swordWeld.Part1 = sword
        swordWeld.Parent = sword

        soldierModel.PrimaryPart = body
        soldierModel.Parent = character
    end

    -- Add count indicator if more than visible
    if count > 3 then
        local countPart = Instance.new("Part")
        countPart.Name = "SoldierFollower"
        countPart.Shape = Enum.PartType.Ball
        countPart.Size = Vector3.new(0.5, 0.5, 0.5)
        countPart.Position = humanoidRootPart.Position + Vector3.new(-2.5, 1.5, -0.5)
        countPart.Anchored = false
        countPart.CanCollide = false
        countPart.Material = Enum.Material.Neon
        countPart.Color = Color3.fromRGB(255, 150, 50)
        countPart.Parent = character

        local countWeld = Instance.new("WeldConstraint")
        countWeld.Part0 = humanoidRootPart
        countWeld.Part1 = countPart
        countWeld.Parent = countPart

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 30, 0, 30)
        billboard.StudsOffset = Vector3.new(0, 0.5, 0)
        billboard.Parent = countPart

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = "x" .. tostring(count)
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard
    end
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
    trainingPit.Position = Vector3.new(baseX, GROUND_Y + 0.1, baseZ)
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
    -- STATION 1: RECRUITMENT BOARD (Get trainees - costs food)
    -- ========================================================================
    local recruitBoard = Instance.new("Part")
    recruitBoard.Name = "RecruitmentBoard"
    recruitBoard.Size = Vector3.new(4, 5, 0.5)
    recruitBoard.Position = Vector3.new(baseX - 12, GROUND_Y + 2.5, baseZ)
    recruitBoard.Anchored = true
    recruitBoard.Material = Enum.Material.Wood
    recruitBoard.Color = Color3.fromRGB(100, 70, 45)
    recruitBoard.Parent = barracksModel

    -- Board header
    local boardHeader = Instance.new("Part")
    boardHeader.Name = "BoardHeader"
    boardHeader.Size = Vector3.new(4.5, 1, 0.3)
    boardHeader.Position = Vector3.new(baseX - 12, GROUND_Y + 5.5, baseZ)
    boardHeader.Anchored = true
    boardHeader.Material = Enum.Material.Wood
    boardHeader.Color = Color3.fromRGB(80, 55, 35)
    boardHeader.Parent = barracksModel

    -- Recruitment posters
    for i = 1, 3 do
        local poster = Instance.new("Part")
        poster.Name = "Poster" .. i
        poster.Size = Vector3.new(1, 1.5, 0.1)
        poster.Position = Vector3.new(baseX - 13 + i * 1.2, GROUND_Y + 3, baseZ + 0.3)
        poster.Anchored = true
        poster.Material = Enum.Material.SmoothPlastic
        poster.Color = Color3.fromRGB(240, 230, 200)
        poster.Parent = barracksModel
    end

    -- Waiting peasants (visual - these show the queue of available trainees)
    local traineeQueueParts = {}
    for i = 1, 5 do
        local peasant = Instance.new("Part")
        peasant.Name = "WaitingPeasant" .. i
        peasant.Size = Vector3.new(1, 3, 1)
        peasant.Position = Vector3.new(baseX - 14, GROUND_Y + 1.5, baseZ - 3 + i * 1.5)
        peasant.Anchored = true
        peasant.Material = Enum.Material.Fabric
        peasant.Color = Color3.fromRGB(139, 119, 101)
        peasant.Transparency = i > 2 and 1 or 0 -- Only show first 2 initially
        peasant.Parent = barracksModel

        local peasantHead = Instance.new("Part")
        peasantHead.Name = "PeasantHead" .. i
        peasantHead.Shape = Enum.PartType.Ball
        peasantHead.Size = Vector3.new(1, 1, 1)
        peasantHead.Position = Vector3.new(baseX - 14, GROUND_Y + 3.5, baseZ - 3 + i * 1.5)
        peasantHead.Anchored = true
        peasantHead.Material = Enum.Material.SmoothPlastic
        peasantHead.Color = Color3.fromRGB(227, 183, 151)
        peasantHead.Transparency = i > 2 and 1 or 0
        peasantHead.Parent = barracksModel

        table.insert(traineeQueueParts, { body = peasant, head = peasantHead })
    end

    -- Trainee queue visual update function
    local traineeQueueCount = 5 -- Available trainees waiting
    local function updateTraineeQueueVisuals()
        for i, parts in ipairs(traineeQueueParts) do
            local visible = i <= traineeQueueCount
            parts.body.Transparency = visible and 0 or 1
            parts.head.Transparency = visible and 0 or 1
        end
    end
    BarracksState.updateTraineeQueueVisuals = updateTraineeQueueVisuals

    -- Sign showing action
    createSign(barracksModel, "WALK TO RECRUIT", Vector3.new(baseX - 12, GROUND_Y + 6.5, baseZ + 2), Vector3.new(5, 0.8, 0.3))

    -- WALK-THROUGH TRIGGER: Recruit trainees (walk near the board)
    local recruitTrigger = Instance.new("Part")
    recruitTrigger.Name = "RecruitTrigger"
    recruitTrigger.Size = Vector3.new(8, 5, 6)
    recruitTrigger.Position = Vector3.new(baseX - 13, GROUND_Y + 2.5, baseZ)
    recruitTrigger.Anchored = true
    recruitTrigger.Transparency = 1
    recruitTrigger.CanCollide = false
    recruitTrigger.Parent = barracksModel

    local recruitDebounce = {}
    recruitTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if recruitDebounce[player.UserId] then return end
        recruitDebounce[player.UserId] = true

        -- Check if trainees available in queue
        if traineeQueueCount > 0 then
            -- Pick up a trainee
            local currentTrainees = getPlayerTrainees(player)
            if currentTrainees < 10 then
                traineeQueueCount = traineeQueueCount - 1
                setPlayerTrainees(player, currentTrainees + 1)
                updatePlayerTraineeVisual(player, currentTrainees + 1)
                updateTraineeQueueVisuals()
                addBarracksXP(5)
                print(string.format("[Barracks] %s recruited a trainee! (Cost: 10 Food)", player.Name))
                print(string.format("  Carrying %d trainee(s). Take to TRAINING YARD!", currentTrainees + 1))
            else
                print(string.format("[Barracks] %s: Already carrying maximum trainees (10)!", player.Name))
            end
        else
            print(string.format("[Barracks] %s: No more trainees available! Wait for more peasants.", player.Name))
        end

        task.delay(1, function() recruitDebounce[player.UserId] = nil end)
    end)

    -- Slowly regenerate trainees over time
    task.spawn(function()
        while true do
            task.wait(10) -- Every 10 seconds
            if traineeQueueCount < 5 then
                traineeQueueCount = traineeQueueCount + 1
                updateTraineeQueueVisuals()
                print("[Barracks] A new peasant arrived for recruitment!")
            end
        end
    end)

    -- ========================================================================
    -- STATION 2: TRAINING YARD (Train at dummies)
    -- ========================================================================
    local trainingYard = Instance.new("Part")
    trainingYard.Name = "TrainingYard"
    trainingYard.Size = Vector3.new(16, 0.2, 14)
    trainingYard.Position = Vector3.new(baseX, GROUND_Y + 0.1, baseZ + 16)
    trainingYard.Anchored = true
    trainingYard.Material = Enum.Material.Ground
    trainingYard.Color = Color3.fromRGB(120, 100, 80)
    trainingYard.Parent = barracksModel

    -- Training dummies (3 of them)
    local dummies = {}
    for i = 1, 3 do
        local dummyPost = Instance.new("Part")
        dummyPost.Name = "DummyPost" .. i
        dummyPost.Size = Vector3.new(0.5, 5, 0.5)
        dummyPost.Position = Vector3.new(baseX - 5 + (i - 1) * 5, GROUND_Y + 2.5, baseZ + 16)
        dummyPost.Anchored = true
        dummyPost.Material = Enum.Material.Wood
        dummyPost.Color = Color3.fromRGB(90, 65, 45)
        dummyPost.Parent = barracksModel

        local dummyBody = Instance.new("Part")
        dummyBody.Name = "DummyBody" .. i
        dummyBody.Size = Vector3.new(2, 3, 1)
        dummyBody.Position = Vector3.new(baseX - 5 + (i - 1) * 5, GROUND_Y + 4.5, baseZ + 16)
        dummyBody.Anchored = true
        dummyBody.Material = Enum.Material.Fabric
        dummyBody.Color = Color3.fromRGB(180, 160, 120)
        dummyBody.Parent = barracksModel

        local dummyHead = Instance.new("Part")
        dummyHead.Name = "DummyHead" .. i
        dummyHead.Shape = Enum.PartType.Ball
        dummyHead.Size = Vector3.new(1.2, 1.2, 1.2)
        dummyHead.Position = Vector3.new(baseX - 5 + (i - 1) * 5, GROUND_Y + 6.5, baseZ + 16)
        dummyHead.Anchored = true
        dummyHead.Material = Enum.Material.Fabric
        dummyHead.Color = Color3.fromRGB(180, 160, 120)
        dummyHead.Parent = barracksModel

        table.insert(dummies, { post = dummyPost, body = dummyBody, head = dummyHead })
    end

    -- Training queue visuals (trainees waiting to train at each dummy)
    local trainingQueueParts = {}
    for i = 1, 6 do
        local trainee = Instance.new("Part")
        trainee.Name = "TrainingQueueTrainee" .. i
        trainee.Size = Vector3.new(0.8, 2.5, 0.6)
        trainee.Position = Vector3.new(baseX - 8 + (i-1) * 2.5, GROUND_Y + 1.25, baseZ + 20)
        trainee.Anchored = true
        trainee.Material = Enum.Material.Fabric
        trainee.Color = Color3.fromRGB(139, 119, 101)
        trainee.Transparency = 1 -- Hidden initially
        trainee.Parent = barracksModel

        local traineeHead = Instance.new("Part")
        traineeHead.Name = "TrainingQueueHead" .. i
        traineeHead.Shape = Enum.PartType.Ball
        traineeHead.Size = Vector3.new(0.7, 0.7, 0.7)
        traineeHead.Position = Vector3.new(baseX - 8 + (i-1) * 2.5, GROUND_Y + 3, baseZ + 20)
        traineeHead.Anchored = true
        traineeHead.Material = Enum.Material.SmoothPlastic
        traineeHead.Color = Color3.fromRGB(227, 183, 151)
        traineeHead.Transparency = 1
        traineeHead.Parent = barracksModel

        table.insert(trainingQueueParts, { body = trainee, head = traineeHead })
    end

    -- Trained recruit waiting area (after training)
    local recruitReadyParts = {}
    for i = 1, 6 do
        local recruit = Instance.new("Part")
        recruit.Name = "TrainedRecruit" .. i
        recruit.Size = Vector3.new(0.8, 2.5, 0.6)
        recruit.Position = Vector3.new(baseX - 8 + (i-1) * 2.5, GROUND_Y + 1.25, baseZ + 12)
        recruit.Anchored = true
        recruit.Material = Enum.Material.Leather
        recruit.Color = Color3.fromRGB(110, 85, 60)
        recruit.Transparency = 1
        recruit.Parent = barracksModel

        local recruitHead = Instance.new("Part")
        recruitHead.Name = "TrainedRecruitHead" .. i
        recruitHead.Shape = Enum.PartType.Ball
        recruitHead.Size = Vector3.new(0.75, 0.75, 0.75)
        recruitHead.Position = Vector3.new(baseX - 8 + (i-1) * 2.5, GROUND_Y + 3, baseZ + 12)
        recruitHead.Anchored = true
        recruitHead.Material = Enum.Material.Metal
        recruitHead.Color = Color3.fromRGB(100, 95, 90)
        recruitHead.Transparency = 1
        recruitHead.Parent = barracksModel

        table.insert(recruitReadyParts, { body = recruit, head = recruitHead })
    end

    -- Training state
    local traineesInTraining = 0
    local traineesReady = 0

    local function updateTrainingVisuals()
        -- Update trainees in queue
        for i, parts in ipairs(trainingQueueParts) do
            local visible = i <= traineesInTraining
            parts.body.Transparency = visible and 0 or 1
            parts.head.Transparency = visible and 0 or 1
        end
        -- Update trained recruits ready
        for i, parts in ipairs(recruitReadyParts) do
            local visible = i <= traineesReady
            parts.body.Transparency = visible and 0 or 1
            parts.head.Transparency = visible and 0 or 1
        end
    end
    BarracksState.updateRecruitQueueVisuals = updateTrainingVisuals

    -- Signs
    createSign(barracksModel, "DROP TRAINEES", Vector3.new(baseX, GROUND_Y + 8.5, baseZ + 20), Vector3.new(5, 0.8, 0.3))
    createSign(barracksModel, "PICK UP RECRUITS", Vector3.new(baseX, GROUND_Y + 8.5, baseZ + 12), Vector3.new(6, 0.8, 0.3))

    -- WALK-THROUGH TRIGGER: Drop trainees for training
    local trainingInputTrigger = Instance.new("Part")
    trainingInputTrigger.Name = "TrainingInputTrigger"
    trainingInputTrigger.Size = Vector3.new(18, 5, 6)
    trainingInputTrigger.Position = Vector3.new(baseX, GROUND_Y + 2.5, baseZ + 20)
    trainingInputTrigger.Anchored = true
    trainingInputTrigger.Transparency = 1
    trainingInputTrigger.CanCollide = false
    trainingInputTrigger.Parent = barracksModel

    local trainingInputDebounce = {}
    trainingInputTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if trainingInputDebounce[player.UserId] then return end
        trainingInputDebounce[player.UserId] = true

        local playerTrainees = getPlayerTrainees(player)
        if playerTrainees > 0 and traineesInTraining < 6 then
            local toDeposit = math.min(playerTrainees, 6 - traineesInTraining)
            setPlayerTrainees(player, playerTrainees - toDeposit)
            updatePlayerTraineeVisual(player, playerTrainees - toDeposit)
            traineesInTraining = traineesInTraining + toDeposit
            updateTrainingVisuals()
            print(string.format("[Barracks] %s dropped %d trainee(s) for training!", player.Name, toDeposit))
            print(string.format("  Trainees in training: %d", traineesInTraining))

            -- Wobble a dummy for visual feedback
            local dummyBody = dummies[2].body
            local originalPos = dummyBody.Position
            task.spawn(function()
                dummyBody.Position = originalPos + Vector3.new(0.3, 0, 0)
                task.wait(0.1)
                dummyBody.Position = originalPos - Vector3.new(0.3, 0, 0)
                task.wait(0.1)
                dummyBody.Position = originalPos
            end)
        elseif playerTrainees == 0 then
            print(string.format("[Barracks] %s: Not carrying any trainees! Recruit some first.", player.Name))
        else
            print(string.format("[Barracks] %s: Training yard is full! Wait for training to finish.", player.Name))
        end

        task.delay(1.5, function() trainingInputDebounce[player.UserId] = nil end)
    end)

    -- WALK-THROUGH TRIGGER: Pick up trained recruits
    local trainingOutputTrigger = Instance.new("Part")
    trainingOutputTrigger.Name = "TrainingOutputTrigger"
    trainingOutputTrigger.Size = Vector3.new(18, 5, 6)
    trainingOutputTrigger.Position = Vector3.new(baseX, GROUND_Y + 2.5, baseZ + 12)
    trainingOutputTrigger.Anchored = true
    trainingOutputTrigger.Transparency = 1
    trainingOutputTrigger.CanCollide = false
    trainingOutputTrigger.Parent = barracksModel

    local trainingOutputDebounce = {}
    trainingOutputTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if trainingOutputDebounce[player.UserId] then return end
        trainingOutputDebounce[player.UserId] = true

        local playerRecruits = getPlayerRecruits(player)
        if traineesReady > 0 and playerRecruits < 10 then
            local toPickup = math.min(traineesReady, 10 - playerRecruits)
            traineesReady = traineesReady - toPickup
            setPlayerRecruits(player, playerRecruits + toPickup)
            updatePlayerRecruitVisual(player, playerRecruits + toPickup)
            updateTrainingVisuals()
            print(string.format("[Barracks] %s picked up %d trained recruit(s)!", player.Name, toPickup))
            print(string.format("  Carrying %d recruit(s). Take to ARMORY!", playerRecruits + toPickup))
        elseif traineesReady == 0 then
            print(string.format("[Barracks] %s: No trained recruits ready. Training in progress...", player.Name))
        else
            print(string.format("[Barracks] %s: Already carrying maximum recruits!", player.Name))
        end

        task.delay(1, function() trainingOutputDebounce[player.UserId] = nil end)
    end)

    -- Training processing loop (trainees → trained recruits over time)
    task.spawn(function()
        while true do
            task.wait(3) -- Process every 3 seconds
            if traineesInTraining > 0 and traineesReady < 6 then
                local dummyStats = DummyStats[BarracksState.equipment.dummies]
                traineesInTraining = traineesInTraining - 1
                traineesReady = traineesReady + 1
                updateTrainingVisuals()

                local xpGain = 15 * dummyStats.xpBonus
                addBarracksXP(xpGain)
                print(string.format("[Barracks] Training complete! (+%d XP) Recruits ready: %d", xpGain, traineesReady))

                -- Sparks on dummy for visual effect
                local sparks = Instance.new("ParticleEmitter")
                sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 100))
                sparks.Size = NumberSequence.new(0.3, 0)
                sparks.Lifetime = NumberRange.new(0.2, 0.4)
                sparks.Rate = 50
                sparks.Speed = NumberRange.new(5, 10)
                sparks.SpreadAngle = Vector2.new(180, 180)
                sparks.Parent = dummies[2].body
                task.delay(0.5, function() sparks:Destroy() end)
            end
        end
    end)

    -- ========================================================================
    -- STATION 3: ARMORY (Equip soldiers with weapons and armor)
    -- ========================================================================
    local armory = Instance.new("Part")
    armory.Name = "Armory"
    armory.Size = Vector3.new(8, 6, 6)
    armory.Position = Vector3.new(baseX + 12, GROUND_Y + 3, baseZ + 10)
    armory.Anchored = true
    armory.Material = Enum.Material.Cobblestone
    armory.Color = Color3.fromRGB(90, 85, 80)
    armory.Parent = barracksModel

    -- Armory roof
    local armoryRoof = Instance.new("Part")
    armoryRoof.Name = "ArmoryRoof"
    armoryRoof.Size = Vector3.new(9, 1, 7)
    armoryRoof.Position = Vector3.new(baseX + 12, GROUND_Y + 6.5, baseZ + 10)
    armoryRoof.Anchored = true
    armoryRoof.Material = Enum.Material.Slate
    armoryRoof.Color = Color3.fromRGB(70, 65, 60)
    armoryRoof.Parent = barracksModel

    -- Weapon racks inside
    local weaponRack = Instance.new("Part")
    weaponRack.Name = "WeaponRack"
    weaponRack.Size = Vector3.new(6, 4, 0.5)
    weaponRack.Position = Vector3.new(baseX + 12, GROUND_Y + 2, baseZ + 13)
    weaponRack.Anchored = true
    weaponRack.Material = Enum.Material.Wood
    weaponRack.Color = Color3.fromRGB(80, 55, 35)
    weaponRack.Parent = barracksModel

    -- Swords on rack
    for i = 1, 4 do
        local sword = Instance.new("Part")
        sword.Name = "Sword" .. i
        sword.Size = Vector3.new(0.2, 2.5, 0.4)
        sword.Position = Vector3.new(baseX + 10 + i * 1.2, GROUND_Y + 2.5, baseZ + 13.3)
        sword.Anchored = true
        sword.Material = Enum.Material.Metal
        sword.Color = Color3.fromRGB(180, 180, 185)
        sword.Parent = barracksModel
    end

    -- Armor stand
    local armorStand = Instance.new("Part")
    armorStand.Name = "ArmorStand"
    armorStand.Size = Vector3.new(2, 4, 1)
    armorStand.Position = Vector3.new(baseX + 14, GROUND_Y + 2, baseZ + 8)
    armorStand.Anchored = true
    armorStand.Material = Enum.Material.Metal
    armorStand.Color = Color3.fromRGB(140, 140, 150)
    armorStand.Parent = barracksModel

    -- Recruits waiting to be equipped (visual queue)
    local armoryQueueParts = {}
    for i = 1, 4 do
        local recruit = Instance.new("Part")
        recruit.Name = "ArmoryQueueRecruit" .. i
        recruit.Size = Vector3.new(0.8, 2.5, 0.6)
        recruit.Position = Vector3.new(baseX + 8, GROUND_Y + 1.25, baseZ + 7 + i * 1.5)
        recruit.Anchored = true
        recruit.Material = Enum.Material.Leather
        recruit.Color = Color3.fromRGB(110, 85, 60)
        recruit.Transparency = 1
        recruit.Parent = barracksModel

        local recruitHead = Instance.new("Part")
        recruitHead.Name = "ArmoryQueueHead" .. i
        recruitHead.Shape = Enum.PartType.Ball
        recruitHead.Size = Vector3.new(0.7, 0.7, 0.7)
        recruitHead.Position = Vector3.new(baseX + 8, GROUND_Y + 3, baseZ + 7 + i * 1.5)
        recruitHead.Anchored = true
        recruitHead.Material = Enum.Material.Metal
        recruitHead.Color = Color3.fromRGB(100, 95, 90)
        recruitHead.Transparency = 1
        recruitHead.Parent = barracksModel

        table.insert(armoryQueueParts, { body = recruit, head = recruitHead })
    end

    -- Equipped soldiers ready for pickup (visual queue)
    local soldierReadyParts = {}
    for i = 1, 4 do
        local soldier = Instance.new("Part")
        soldier.Name = "EquippedSoldier" .. i
        soldier.Size = Vector3.new(0.9, 2.6, 0.6)
        soldier.Position = Vector3.new(baseX + 16, GROUND_Y + 1.3, baseZ + 7 + i * 1.5)
        soldier.Anchored = true
        soldier.Material = Enum.Material.Metal
        soldier.Color = Color3.fromRGB(140, 140, 150)
        soldier.Transparency = 1
        soldier.Parent = barracksModel

        local soldierHead = Instance.new("Part")
        soldierHead.Name = "EquippedSoldierHead" .. i
        soldierHead.Size = Vector3.new(0.7, 0.7, 0.7)
        soldierHead.Position = Vector3.new(baseX + 16, GROUND_Y + 3.1, baseZ + 7 + i * 1.5)
        soldierHead.Anchored = true
        soldierHead.Material = Enum.Material.Metal
        soldierHead.Color = Color3.fromRGB(100, 100, 110)
        soldierHead.Transparency = 1
        soldierHead.Parent = barracksModel

        -- Sword on back
        local sword = Instance.new("Part")
        sword.Name = "SoldierSword" .. i
        sword.Size = Vector3.new(0.1, 1.2, 0.2)
        sword.Position = Vector3.new(baseX + 16.3, GROUND_Y + 1.8, baseZ + 7 + i * 1.5)
        sword.Orientation = Vector3.new(0, 0, -20)
        sword.Anchored = true
        sword.Material = Enum.Material.Metal
        sword.Color = Color3.fromRGB(180, 180, 190)
        sword.Transparency = 1
        sword.Parent = barracksModel

        table.insert(soldierReadyParts, { body = soldier, head = soldierHead, sword = sword })
    end

    -- Armory state
    local recruitsEquipping = 0
    local soldiersReady = 0

    local function updateArmoryVisuals()
        -- Update recruits in queue
        for i, parts in ipairs(armoryQueueParts) do
            local visible = i <= recruitsEquipping
            parts.body.Transparency = visible and 0 or 1
            parts.head.Transparency = visible and 0 or 1
        end
        -- Update equipped soldiers ready
        for i, parts in ipairs(soldierReadyParts) do
            local visible = i <= soldiersReady
            parts.body.Transparency = visible and 0 or 1
            parts.head.Transparency = visible and 0 or 1
            parts.sword.Transparency = visible and 0 or 1
        end
    end
    BarracksState.updateSoldierQueueVisuals = updateArmoryVisuals

    -- Signs
    createSign(barracksModel, "DROP RECRUITS", Vector3.new(baseX + 8, GROUND_Y + 7, baseZ + 10), Vector3.new(5, 0.8, 0.3))
    createSign(barracksModel, "PICK UP SOLDIERS", Vector3.new(baseX + 16, GROUND_Y + 7, baseZ + 10), Vector3.new(6, 0.8, 0.3))

    -- WALK-THROUGH TRIGGER: Drop recruits for equipping
    local armoryInputTrigger = Instance.new("Part")
    armoryInputTrigger.Name = "ArmoryInputTrigger"
    armoryInputTrigger.Size = Vector3.new(6, 5, 10)
    armoryInputTrigger.Position = Vector3.new(baseX + 8, GROUND_Y + 2.5, baseZ + 10)
    armoryInputTrigger.Anchored = true
    armoryInputTrigger.Transparency = 1
    armoryInputTrigger.CanCollide = false
    armoryInputTrigger.Parent = barracksModel

    local armoryInputDebounce = {}
    armoryInputTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if armoryInputDebounce[player.UserId] then return end
        armoryInputDebounce[player.UserId] = true

        local playerRecruits = getPlayerRecruits(player)
        if playerRecruits > 0 and recruitsEquipping < 4 then
            local toDeposit = math.min(playerRecruits, 4 - recruitsEquipping)
            setPlayerRecruits(player, playerRecruits - toDeposit)
            updatePlayerRecruitVisual(player, playerRecruits - toDeposit)
            recruitsEquipping = recruitsEquipping + toDeposit
            updateArmoryVisuals()
            print(string.format("[Barracks] %s dropped %d recruit(s) for equipping!", player.Name, toDeposit))
            print(string.format("  Recruits being equipped: %d", recruitsEquipping))
        elseif playerRecruits == 0 then
            print(string.format("[Barracks] %s: Not carrying any recruits! Train some first.", player.Name))
        else
            print(string.format("[Barracks] %s: Armory is full! Wait for equipping to finish.", player.Name))
        end

        task.delay(1.5, function() armoryInputDebounce[player.UserId] = nil end)
    end)

    -- WALK-THROUGH TRIGGER: Pick up equipped soldiers
    local armoryOutputTrigger = Instance.new("Part")
    armoryOutputTrigger.Name = "ArmoryOutputTrigger"
    armoryOutputTrigger.Size = Vector3.new(6, 5, 10)
    armoryOutputTrigger.Position = Vector3.new(baseX + 16, GROUND_Y + 2.5, baseZ + 10)
    armoryOutputTrigger.Anchored = true
    armoryOutputTrigger.Transparency = 1
    armoryOutputTrigger.CanCollide = false
    armoryOutputTrigger.Parent = barracksModel

    local armoryOutputDebounce = {}
    armoryOutputTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if armoryOutputDebounce[player.UserId] then return end
        armoryOutputDebounce[player.UserId] = true

        local playerSoldiers = getPlayerSoldiers(player)
        if soldiersReady > 0 and playerSoldiers < 10 then
            local toPickup = math.min(soldiersReady, 10 - playerSoldiers)
            soldiersReady = soldiersReady - toPickup
            setPlayerSoldiers(player, playerSoldiers + toPickup)
            updatePlayerSoldierVisual(player, playerSoldiers + toPickup)
            updateArmoryVisuals()

            local weaponStats = WeaponStats[BarracksState.equipment.weapons]
            local armorStats = ArmorStats[BarracksState.equipment.armor]
            print(string.format("[Barracks] %s picked up %d equipped soldier(s)!", player.Name, toPickup))
            print(string.format("  Weapon: %s (Damage: %d)", BarracksState.equipment.weapons, weaponStats.damage))
            print(string.format("  Armor: %s (Defense: %d)", BarracksState.equipment.armor, armorStats.defense))
            print(string.format("  Carrying %d soldier(s). Take to ARMY CAMP to deploy!", playerSoldiers + toPickup))
        elseif soldiersReady == 0 then
            print(string.format("[Barracks] %s: No equipped soldiers ready. Equipping in progress...", player.Name))
        else
            print(string.format("[Barracks] %s: Already carrying maximum soldiers!", player.Name))
        end

        task.delay(1, function() armoryOutputDebounce[player.UserId] = nil end)
    end)

    -- Equipping processing loop (recruits → equipped soldiers over time)
    task.spawn(function()
        while true do
            task.wait(4) -- Process every 4 seconds (slower than training)
            if recruitsEquipping > 0 and soldiersReady < 4 then
                recruitsEquipping = recruitsEquipping - 1
                soldiersReady = soldiersReady + 1
                updateArmoryVisuals()

                addBarracksXP(20)
                print(string.format("[Barracks] Soldier equipped! (+20 XP) Soldiers ready: %d", soldiersReady))

                -- Metal sparks effect
                local metalSparks = Instance.new("ParticleEmitter")
                metalSparks.Color = ColorSequence.new(Color3.fromRGB(200, 200, 220))
                metalSparks.Size = NumberSequence.new(0.2, 0)
                metalSparks.Lifetime = NumberRange.new(0.3, 0.5)
                metalSparks.Rate = 30
                metalSparks.Speed = NumberRange.new(3, 6)
                metalSparks.Parent = armory
                task.delay(0.5, function() metalSparks:Destroy() end)
            end
        end
    end)

    -- ========================================================================
    -- STATION 4: ARMY CAMP (Deploy troops to your army)
    -- ========================================================================
    local armyCamp = Instance.new("Part")
    armyCamp.Name = "ArmyCamp"
    armyCamp.Size = Vector3.new(12, 0.2, 10)
    armyCamp.Position = Vector3.new(baseX + 15, GROUND_Y + 0.1, baseZ - 5)
    armyCamp.Anchored = true
    armyCamp.Material = Enum.Material.Grass
    armyCamp.Color = Color3.fromRGB(80, 120, 60)
    armyCamp.Parent = barracksModel

    -- Tents
    for i = 1, 2 do
        local tent = Instance.new("Part")
        tent.Name = "Tent" .. i
        tent.Size = Vector3.new(4, 3, 5)
        tent.Position = Vector3.new(baseX + 12 + (i - 1) * 6, GROUND_Y + 1.5, baseZ - 5)
        tent.Anchored = true
        tent.Material = Enum.Material.Fabric
        tent.Color = Color3.fromRGB(180, 160, 130)
        tent.Parent = barracksModel

        -- Tent peak
        local tentPeak = Instance.new("Part")
        tentPeak.Name = "TentPeak" .. i
        tentPeak.Size = Vector3.new(4, 2, 5)
        tentPeak.Position = Vector3.new(baseX + 12 + (i - 1) * 6, GROUND_Y + 4, baseZ - 5)
        tentPeak.Anchored = true
        tentPeak.Material = Enum.Material.Fabric
        tentPeak.Color = Color3.fromRGB(160, 140, 110)
        tentPeak.Parent = barracksModel
    end

    -- Campfire
    local campfire = Instance.new("Part")
    campfire.Name = "Campfire"
    campfire.Shape = Enum.PartType.Cylinder
    campfire.Size = Vector3.new(0.5, 2, 2)
    campfire.Position = Vector3.new(baseX + 15, GROUND_Y + 0.25, baseZ - 8)
    campfire.Orientation = Vector3.new(0, 0, 90)
    campfire.Anchored = true
    campfire.Material = Enum.Material.Rock
    campfire.Color = Color3.fromRGB(60, 50, 40)
    campfire.Parent = barracksModel

    -- Campfire flames
    local campfireFire = Instance.new("Fire")
    campfireFire.Size = 3
    campfireFire.Heat = 5
    campfireFire.Color = Color3.fromRGB(255, 150, 50)
    campfireFire.SecondaryColor = Color3.fromRGB(255, 80, 20)
    campfireFire.Parent = campfire

    -- Deploy marker (flag)
    local deployFlag = Instance.new("Part")
    deployFlag.Name = "DeployFlag"
    deployFlag.Size = Vector3.new(0.3, 6, 0.3)
    deployFlag.Position = Vector3.new(baseX + 20, GROUND_Y + 3, baseZ - 3)
    deployFlag.Anchored = true
    deployFlag.Material = Enum.Material.Metal
    deployFlag.Color = Color3.fromRGB(70, 70, 75)
    deployFlag.Parent = barracksModel

    local deployBanner = Instance.new("Part")
    deployBanner.Name = "DeployBanner"
    deployBanner.Size = Vector3.new(0.1, 2.5, 2)
    deployBanner.Position = Vector3.new(baseX + 20.5, GROUND_Y + 5, baseZ - 3)
    deployBanner.Anchored = true
    deployBanner.Material = Enum.Material.Fabric
    deployBanner.Color = Color3.fromRGB(50, 120, 180) -- Blue deployment flag
    deployBanner.Parent = barracksModel

    -- Deployed army visual (soldiers standing in formation)
    local deployedArmyParts = {}
    for i = 1, 8 do
        local row = math.floor((i-1) / 4)
        local col = (i-1) % 4
        local soldier = Instance.new("Part")
        soldier.Name = "DeployedSoldier" .. i
        soldier.Size = Vector3.new(0.9, 2.6, 0.6)
        soldier.Position = Vector3.new(baseX + 10 + col * 2, GROUND_Y + 1.3, baseZ - 3 - row * 2)
        soldier.Anchored = true
        soldier.Material = Enum.Material.Metal
        soldier.Color = Color3.fromRGB(140, 140, 150)
        soldier.Transparency = 1
        soldier.Parent = barracksModel

        local soldierHead = Instance.new("Part")
        soldierHead.Name = "DeployedSoldierHead" .. i
        soldierHead.Size = Vector3.new(0.6, 0.6, 0.6)
        soldierHead.Position = Vector3.new(baseX + 10 + col * 2, GROUND_Y + 3.1, baseZ - 3 - row * 2)
        soldierHead.Anchored = true
        soldierHead.Material = Enum.Material.Metal
        soldierHead.Color = Color3.fromRGB(100, 100, 110)
        soldierHead.Transparency = 1
        soldierHead.Parent = barracksModel

        table.insert(deployedArmyParts, { body = soldier, head = soldierHead })
    end

    local totalDeployedThisSession = 0

    local function updateDeployedArmyVisuals()
        for i, parts in ipairs(deployedArmyParts) do
            local visible = i <= totalDeployedThisSession
            parts.body.Transparency = visible and 0 or 1
            parts.head.Transparency = visible and 0 or 1
        end
    end

    -- Sign
    createSign(barracksModel, "DEPLOY SOLDIERS", Vector3.new(baseX + 15, GROUND_Y + 7, baseZ - 3), Vector3.new(6, 0.8, 0.3))

    -- WALK-THROUGH TRIGGER: Deploy soldiers to army (final reward station)
    local deployTrigger = Instance.new("Part")
    deployTrigger.Name = "DeployTrigger"
    deployTrigger.Size = Vector3.new(14, 5, 12)
    deployTrigger.Position = Vector3.new(baseX + 15, GROUND_Y + 2.5, baseZ - 5)
    deployTrigger.Anchored = true
    deployTrigger.Transparency = 1
    deployTrigger.CanCollide = false
    deployTrigger.Parent = barracksModel

    local deployDebounce = {}
    deployTrigger.Touched:Connect(function(hit)
        local character = hit.Parent
        local humanoid = character and character:FindFirstChild("Humanoid")
        if not humanoid then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if deployDebounce[player.UserId] then return end
        deployDebounce[player.UserId] = true

        local playerSoldiers = getPlayerSoldiers(player)
        if playerSoldiers > 0 then
            local inv = getBarracksInventory(player)
            local goldReward = playerSoldiers * 30

            -- Deploy all soldiers at once
            inv.deployedTroops = inv.deployedTroops + playerSoldiers
            BarracksState.totalTroopsTrained = BarracksState.totalTroopsTrained + playerSoldiers
            totalDeployedThisSession = math.min(totalDeployedThisSession + playerSoldiers, 8)

            setPlayerSoldiers(player, 0)
            updatePlayerSoldierVisual(player, 0)
            updateDeployedArmyVisuals()

            addBarracksXP(25 * playerSoldiers)
            rewardPlayer(player, "gold", goldReward, "Barracks")

            -- Glory particles
            local glory = Instance.new("ParticleEmitter")
            glory.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
            glory.Size = NumberSequence.new(0.5, 0)
            glory.Lifetime = NumberRange.new(1, 2)
            glory.Rate = 40
            glory.Speed = NumberRange.new(3, 5)
            glory.SpreadAngle = Vector2.new(30, 30)
            glory.Parent = deployFlag
            task.delay(1.5, function() glory:Destroy() end)

            print(string.format("[Barracks] %s deployed %d soldier(s) to their army!", player.Name, playerSoldiers))
            print(string.format("  +%d Gold reward!", goldReward))
            print(string.format("  Total army size: %d troops", inv.deployedTroops))
            print(string.format("  Barracks total trained: %d", BarracksState.totalTroopsTrained))
        else
            print(string.format("[Barracks] %s: Not carrying any soldiers! Complete the training loop first.", player.Name))
            print("  Recruit → Train → Equip → Deploy")
        end

        task.delay(1.5, function() deployDebounce[player.UserId] = nil end)
    end)

    -- ========================================================================
    -- STATION 5: SERGEANT HUT (Hire drill sergeants - Level 3+)
    -- ========================================================================
    local sergeantHut = Instance.new("Part")
    sergeantHut.Name = "SergeantHut"
    sergeantHut.Size = Vector3.new(6, 5, 5)
    sergeantHut.Position = Vector3.new(baseX - 10, GROUND_Y + 2.5, baseZ + 10)
    sergeantHut.Anchored = true
    sergeantHut.Material = Enum.Material.Wood
    sergeantHut.Color = Color3.fromRGB(100, 75, 50)
    sergeantHut.Parent = barracksModel

    -- Sergeant hut roof
    local hutRoof = Instance.new("Part")
    hutRoof.Name = "HutRoof"
    hutRoof.Size = Vector3.new(7, 1, 6)
    hutRoof.Position = Vector3.new(baseX - 10, GROUND_Y + 5.5, baseZ + 10)
    hutRoof.Anchored = true
    hutRoof.Material = Enum.Material.Slate
    hutRoof.Color = Color3.fromRGB(60, 55, 50)
    hutRoof.Parent = barracksModel

    -- Sergeant sign
    local sergeantSign = Instance.new("Part")
    sergeantSign.Name = "SergeantSign"
    sergeantSign.Size = Vector3.new(3, 1, 0.2)
    sergeantSign.Position = Vector3.new(baseX - 10, GROUND_Y + 4, baseZ + 12.6)
    sergeantSign.Anchored = true
    sergeantSign.Material = Enum.Material.Wood
    sergeantSign.Color = Color3.fromRGB(80, 55, 35)
    sergeantSign.Parent = barracksModel

    createInteraction(sergeantHut, "Hire Drill Sergeant", "Sergeant Hut", 2, function(player)
        if BarracksState.level < 3 then
            print(string.format("[Barracks] Need Level 3 to hire sergeants! (Currently Level %d)", BarracksState.level))
            return
        end

        local numSergeants = #BarracksState.drillSergeants
        if numSergeants >= 4 then
            print("[Barracks] Maximum sergeants hired (4)")
            return
        end

        local cost = DrillSergeantCosts[numSergeants + 1]
        print(string.format("[Barracks] Hiring Drill Sergeant #%d (Cost: %d Gold, %d Food)",
            numSergeants + 1, cost.gold, cost.food))

        table.insert(BarracksState.drillSergeants, {
            id = numSergeants + 1,
            efficiency = 1.0 + numSergeants * 0.1,
            hiredAt = tick(),
        })

        addBarracksXP(50)
        print(string.format("  Drill sergeants: %d/4", #BarracksState.drillSergeants))
        print("  Sergeants will automatically train recruits!")

        -- Spawn sergeant visual
        local sergeantVisual = Instance.new("Part")
        sergeantVisual.Name = "Sergeant" .. numSergeants + 1
        sergeantVisual.Size = Vector3.new(1.5, 4, 1.5)
        sergeantVisual.Position = Vector3.new(baseX - 8 + numSergeants * 2, GROUND_Y + 2, baseZ + 8)
        sergeantVisual.Anchored = true
        sergeantVisual.Material = Enum.Material.SmoothPlastic
        sergeantVisual.Color = Color3.fromRGB(70, 70, 90) -- Dark military uniform
        sergeantVisual.Parent = barracksModel

        local sergeantHead = Instance.new("Part")
        sergeantHead.Name = "SergeantHead" .. numSergeants + 1
        sergeantHead.Shape = Enum.PartType.Ball
        sergeantHead.Size = Vector3.new(1.2, 1.2, 1.2)
        sergeantHead.Position = Vector3.new(baseX - 8 + numSergeants * 2, GROUND_Y + 4.6, baseZ + 8)
        sergeantHead.Anchored = true
        sergeantHead.Material = Enum.Material.SmoothPlastic
        sergeantHead.Color = Color3.fromRGB(227, 183, 151)
        sergeantHead.Parent = barracksModel
    end)

    -- ========================================================================
    -- STATION 6: FORGE (Upgrade dummies, weapons, armor)
    -- ========================================================================
    local forge = Instance.new("Part")
    forge.Name = "Forge"
    forge.Size = Vector3.new(7, 5, 6)
    forge.Position = Vector3.new(baseX + 12, GROUND_Y + 2.5, baseZ - 12)
    forge.Anchored = true
    forge.Material = Enum.Material.Cobblestone
    forge.Color = Color3.fromRGB(80, 70, 65)
    forge.Parent = barracksModel

    -- Forge chimney
    local forgeChimney = Instance.new("Part")
    forgeChimney.Name = "ForgeChimney"
    forgeChimney.Size = Vector3.new(2, 4, 2)
    forgeChimney.Position = Vector3.new(baseX + 14, GROUND_Y + 7, baseZ - 13)
    forgeChimney.Anchored = true
    forgeChimney.Material = Enum.Material.Brick
    forgeChimney.Color = Color3.fromRGB(100, 60, 50)
    forgeChimney.Parent = barracksModel

    -- Forge smoke
    local forgeSmoke = Instance.new("Smoke")
    forgeSmoke.Size = 3
    forgeSmoke.Opacity = 0.3
    forgeSmoke.RiseVelocity = 4
    forgeSmoke.Color = Color3.fromRGB(60, 60, 60)
    forgeSmoke.Parent = forgeChimney

    -- Anvil
    local anvil = Instance.new("Part")
    anvil.Name = "Anvil"
    anvil.Size = Vector3.new(2, 1.5, 1)
    anvil.Position = Vector3.new(baseX + 10, GROUND_Y + 0.75, baseZ - 10)
    anvil.Anchored = true
    anvil.Material = Enum.Material.Metal
    anvil.Color = Color3.fromRGB(50, 50, 55)
    anvil.Parent = barracksModel

    -- Forge fire
    local forgeFire = Instance.new("Part")
    forgeFire.Name = "ForgeFire"
    forgeFire.Size = Vector3.new(3, 2, 2)
    forgeFire.Position = Vector3.new(baseX + 12, GROUND_Y + 1, baseZ - 14)
    forgeFire.Anchored = true
    forgeFire.Material = Enum.Material.Neon
    forgeFire.Color = Color3.fromRGB(255, 100, 30)
    forgeFire.Parent = barracksModel

    local forgeFlames = Instance.new("Fire")
    forgeFlames.Size = 5
    forgeFlames.Heat = 10
    forgeFlames.Parent = forgeFire

    createInteraction(forge, "Upgrade Equipment", "Military Forge", 2.5, function(player)
        print("[Barracks] === FORGE UPGRADES ===")
        print(string.format("  Current Dummies: %s", BarracksState.equipment.dummies))
        print(string.format("  Current Weapons: %s", BarracksState.equipment.weapons))
        print(string.format("  Current Armor: %s", BarracksState.equipment.armor))

        -- Auto-upgrade to next tier (simplified)
        local tiers = {"Basic", "Iron", "Steel", "Mithril"}
        local dummyTiers = {"Basic", "Reinforced", "Steel", "Enchanted"}

        -- Find current tier and upgrade weapons
        for i, tier in ipairs(tiers) do
            if BarracksState.equipment.weapons == tier and i < #tiers then
                local nextTier = tiers[i + 1]
                local cost = WeaponStats[nextTier].cost
                print(string.format("[Barracks] Upgrading weapons to %s (Cost: %d Gold)", nextTier, cost))
                BarracksState.equipment.weapons = nextTier
                addBarracksXP(40)

                -- Forge sparks
                local sparks = Instance.new("ParticleEmitter")
                sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 100))
                sparks.Size = NumberSequence.new(0.4, 0)
                sparks.Lifetime = NumberRange.new(0.3, 0.6)
                sparks.Rate = 60
                sparks.Speed = NumberRange.new(5, 10)
                sparks.SpreadAngle = Vector2.new(60, 60)
                sparks.Parent = anvil
                task.delay(1, function() sparks:Destroy() end)
                return
            end
        end

        -- If weapons maxed, upgrade armor
        for i, tier in ipairs(tiers) do
            if BarracksState.equipment.armor == tier and i < #tiers then
                local nextTier = tiers[i + 1]
                local cost = ArmorStats[nextTier].cost
                print(string.format("[Barracks] Upgrading armor to %s (Cost: %d Gold)", nextTier, cost))
                BarracksState.equipment.armor = nextTier
                addBarracksXP(40)
                return
            end
        end

        -- If armor maxed, upgrade dummies
        for i, tier in ipairs(dummyTiers) do
            if BarracksState.equipment.dummies == tier and i < #dummyTiers then
                local nextTier = dummyTiers[i + 1]
                local cost = DummyStats[nextTier].cost
                print(string.format("[Barracks] Upgrading training dummies to %s (Cost: %d Gold)", nextTier, cost))
                BarracksState.equipment.dummies = nextTier
                addBarracksXP(40)
                return
            end
        end

        print("[Barracks] All equipment at maximum level!")
    end)

    -- Parent the barracks interior
    barracksModel.Parent = interiorsFolder

    print("  ✓ Barracks created (MILITARY TRAINING GROUNDS interior):")
    print("    - Enter building in village to teleport inside")
    print("    - Full progression: Recruit → Train → Equip → Deploy")
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

-- Add XP to town hall and handle leveling
local function addTownHallXP(amount: number)
    TownHallState.xp = TownHallState.xp + amount
    while TownHallState.xp >= TownHallState.xpToNextLevel do
        TownHallState.xp = TownHallState.xp - TownHallState.xpToNextLevel
        TownHallState.level = TownHallState.level + 1
        TownHallState.xpToNextLevel = math.floor(TownHallState.xpToNextLevel * 1.5)
        TownHallState.population = TownHallState.population + 5 -- More citizens at higher levels
        print(string.format("[TownHall] LEVEL UP! Now level %d (Population: %d)", TownHallState.level, TownHallState.population))
    end
end

local function createTownHall()
    print("[7/8] Creating Town Hall with full progression loop...")

    -- ========== EXTERIOR IN VILLAGE ==========
    -- At the end of the main path, faces south toward incoming players
    local exteriorX, exteriorZ = 60, 155

    -- Create exterior building shell
    createBuildingExterior(
        "TOWN HALL",
        Vector3.new(exteriorX, GROUND_Y, exteriorZ),
        Vector3.new(20, 14, 18),
        Color3.fromRGB(110, 100, 95), -- Elegant stone roof
        Color3.fromRGB(130, 120, 110), -- Grand cobblestone walls
        "TownHall",
        "south" -- Entrance faces the main path (toward gate)
    )

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
    floorPattern.Position = Vector3.new(baseX, GROUND_Y + 0.05, baseZ)
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
    carpet.Position = Vector3.new(baseX, GROUND_Y + 0.05, baseZ)
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
                        -- Check if previous slots are unlocked
                        if TownHallState.jewelCase.maxSlots < slotNum - 1 then
                            print(string.format("[TownHall] Must unlock slot %d first!", slotNum - 1))
                            return
                        end

                        -- TODO: Check and deduct resources
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

    upgradePrompt.Triggered:Connect(function(player)
        print("[TownHall] === BUILDING UPGRADE CENTER ===")
        print(string.format("  Gold Mine: Level %d", TownHallState.buildingLevels.goldMine))
        print(string.format("  Lumber Mill: Level %d", TownHallState.buildingLevels.lumberMill))
        print(string.format("  Barracks: Level %d", TownHallState.buildingLevels.barracks))
        for i = 1, 6 do
            local farmKey = "farm" .. i
            print(string.format("  Farm %d: Level %d", i, TownHallState.buildingLevels[farmKey]))
        end
        print("")
        print("  [Upgrade costs scale with level]")
        print("  Use the upgrade kiosk in each building to upgrade")
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

    researchPrompt.Triggered:Connect(function(player)
        print("[TownHall] === RESEARCH STATION ===")
        print("  Coming in future update!")
        print("  Unlock city-wide improvements through research")
    end)

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
    -- Parent the town hall interior
    townHallModel.Parent = interiorsFolder

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

        local trunk = Instance.new("Part")
        trunk.Name = "Trunk"
        trunk.Size = Vector3.new(2, 8, 2)
        trunk.Position = pos + Vector3.new(0, 4, 0)
        trunk.Anchored = true
        trunk.Material = Enum.Material.Wood
        trunk.Color = Color3.fromRGB(80, 55, 35)
        trunk.Parent = tree

        local leaves = Instance.new("Part")
        leaves.Name = "Leaves"
        leaves.Shape = Enum.PartType.Ball
        leaves.Size = Vector3.new(8, 7, 8)
        leaves.Position = pos + Vector3.new(0, 10, 0)
        leaves.Anchored = true
        leaves.Material = Enum.Material.Grass
        leaves.Color = Color3.fromRGB(60, 120, 50)
        leaves.Parent = tree

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

        local lantern = Instance.new("Part")
        lantern.Name = "Lantern"
        lantern.Size = Vector3.new(1.5, 2, 1.5)
        lantern.Position = pos + Vector3.new(0, 9, 0)
        lantern.Anchored = true
        lantern.Material = Enum.Material.Glass
        lantern.Color = Color3.fromRGB(255, 220, 150)
        lantern.Transparency = 0.3
        lantern.Parent = lamp

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
        local bench = Instance.new("Part")
        bench.Name = "Bench" .. i
        bench.Size = Vector3.new(4, 1.5, 1.5)
        bench.Position = data.pos + Vector3.new(0, 0.75, 0)
        bench.Orientation = Vector3.new(0, data.rot, 0)
        bench.Anchored = true
        bench.Material = Enum.Material.Wood
        bench.Color = Color3.fromRGB(90, 65, 45)
        bench.Parent = decorFolder
    end

    -- Central well/fountain
    local well = Instance.new("Model")
    well.Name = "CentralWell"

    local wellBase = Instance.new("Part")
    wellBase.Name = "Base"
    wellBase.Shape = Enum.PartType.Cylinder
    wellBase.Size = Vector3.new(2, 6, 6)
    wellBase.Position = Vector3.new(60, GROUND_Y + 1, 45)
    wellBase.Anchored = true
    wellBase.Material = Enum.Material.Cobblestone
    wellBase.Color = Color3.fromRGB(110, 105, 100)
    wellBase.Parent = well

    local wellWater = Instance.new("Part")
    wellWater.Name = "Water"
    wellWater.Shape = Enum.PartType.Cylinder
    wellWater.Size = Vector3.new(0.5, 4, 4)
    wellWater.Position = Vector3.new(60, GROUND_Y + 1.5, 45)
    wellWater.Anchored = true
    wellWater.Material = Enum.Material.Glass
    wellWater.Color = Color3.fromRGB(80, 140, 200)
    wellWater.Transparency = 0.4
    wellWater.Parent = well

    well.Parent = decorFolder

    print("  ✓ Decorations added")
end

-- ============================================================================
-- MAIN EXECUTION
-- ============================================================================

local success, errorMsg = pcall(function()
    createGround()
    createEntranceGate()
    createGoldMine()
    createLumberMill()
    createFarm(1) -- Farm 1 is created by default (additional farms purchased in shop)
    createBarracks()
    createTownHall()
    createDecorations()
end)

if success then
    print("========================================")
    print("GAMEPLAY VILLAGE BUILT SUCCESSFULLY!")
    print("========================================")
    print("")
    print("=== GOLD MINE (FULL PROTOTYPE) ===")
    print("  1. MINE ORE - Click vein, carry up to 10")
    print("  2. LOAD REFINER - Dump ore into hopper")
    print("  3. SMELT GOLD - Work furnace to create gold")
    print("  4. COLLECT - Grab gold from output chest")
    print("  5. HIRE WORKERS - Automate (Level 3+)")
    print("  6. UPGRADE - Better tools = more output")
    print("")
    print("")
    print("=== LUMBER MILL (FULL PROTOTYPE) ===")
    print("  1. CHOP TREES - 4 stages per tree (more wood each stage)")
    print("  2. CARRY LOGS - Transport up to 8 logs")
    print("  3. SAWMILL - Walk through to load (progress bar)")
    print("  4. COLLECT - Grab planks from output")
    print("  5. STORE - Deposit in chest for wood!")
    print("  6. HIRE LOGGERS - Automate tree chopping")
    print("  7. UPGRADE - Better axe/sawmill = more wood")
    print("")
    print("=== FARM (FULL PROTOTYPE) ===")
    print("  1. GET SEEDS - Grab from seed shed")
    print("  2. PLANT - Click empty plots")
    print("  3. WATER - Draw water, speeds growth")
    print("  4. HARVEST - Click grown crops")
    print("  5. LOAD - Dump in harvest basket")
    print("  6. PROCESS - Grind at windmill")
    print("  7. COLLECT - Grab food from silo")
    print("  8. HIRE WORKERS - Automate (Level 3+)")
    print("  9. UPGRADE - Hoe, watering can, windmill")
    print("")
    print("=== BARRACKS (FULL PROTOTYPE) ===")
    print("  1. RECRUIT - Get trainees (costs food)")
    print("  2. TRAIN - Practice at combat dummies")
    print("  3. EQUIP - Weapon + armor at armory")
    print("  4. DEPLOY - Send to army camp")
    print("  5. HIRE SERGEANTS - Automate (Level 3+)")
    print("  6. UPGRADE - Better dummies, weapons, armor")
    print("")
    print("=== TOWN HALL (FULL PROTOTYPE) ===")
    print("  1. COLLECT TAXES - Get gold from citizens")
    print("  2. REGISTER CITIZENS - Grow population")
    print("  3. STUDY SCROLLS - Earn research points")
    print("  4. DEPOSIT GOLD - Store in treasury vault")
    print("  5. HIRE ADVISORS - Automate (Level 3+)")
    print("  6. UPGRADE - Better ledgers, scrolls, vault")
    print("")
    print("Walk around and find [E] prompts to play!")
    print("Mini-games give resources and level up buildings!")
    print("========================================")
else
    warn("========================================")
    warn("VILLAGE BUILD FAILED!")
    warn("Error: " .. tostring(errorMsg))
    warn("========================================")
end
