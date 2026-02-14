--!strict
--[[
    MiniBaseBuilder.lua

    Creates simplified castle models representing player bases on the overworld map.
    Each mini-base shows the player's Town Hall level, name, and trophies.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)

local MiniBaseBuilder = {}

-- ============================================================================
-- MATERIALS & COLORS
-- ============================================================================

local Materials = {
    Stone = Enum.Material.Rock,
    Brick = Enum.Material.Brick,
    Wood = Enum.Material.WoodPlanks,
    Metal = Enum.Material.DiamondPlate,
    Fabric = Enum.Material.Fabric,
}

local Colors = {
    WallStone = Color3.fromRGB(130, 125, 120),
    WallDark = Color3.fromRGB(100, 95, 90),
    KeepBase = Color3.fromRGB(150, 140, 130),
    KeepRoof = Color3.fromRGB(80, 65, 60),
    GateDoor = Color3.fromRGB(80, 55, 35),
    GateIron = Color3.fromRGB(60, 60, 65),
    BannerPole = Color3.fromRGB(90, 65, 45),
    Ground = Color3.fromRGB(95, 85, 65),
}

-- ============================================================================
-- BASE FOLDER REFERENCE
-- ============================================================================

local _basesFolder: Folder?

--[[
    Gets or creates the bases folder in workspace.
]]
local function getBasesFolder(): Folder
    if _basesFolder and _basesFolder.Parent then
        return _basesFolder
    end

    local overworld = workspace:FindFirstChild("Overworld")
    if not overworld then
        overworld = Instance.new("Folder")
        overworld.Name = "Overworld"
        overworld.Parent = workspace
    end

    _basesFolder = overworld:FindFirstChild("Bases") :: Folder?
    if not _basesFolder then
        _basesFolder = Instance.new("Folder")
        _basesFolder.Name = "Bases"
        _basesFolder.Parent = overworld
    end

    return _basesFolder :: Folder
end

-- ============================================================================
-- MINI-BASE COMPONENTS
-- ============================================================================

--[[
    Creates the central keep (castle tower) scaled by TH level.
]]
local function createKeep(thLevel: number, color: Color3): Model
    local keep = Instance.new("Model")
    keep.Name = "Keep"

    local baseConfig = OverworldConfig.Base
    local keepHeight = OverworldConfig.GetKeepHeight(thLevel)
    local keepWidth = 6 + thLevel * 0.5 -- Slightly wider at higher levels

    -- Keep base (foundation)
    local foundation = Instance.new("Part")
    foundation.Name = "Foundation"
    foundation.Size = Vector3.new(keepWidth + 2, 0.5, keepWidth + 2)
    foundation.Position = Vector3.new(0, 0.25, 0)
    foundation.Anchored = true
    foundation.Material = Materials.Stone
    foundation.Color = Colors.WallDark
    foundation.Parent = keep

    -- Main keep body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(keepWidth, keepHeight, keepWidth)
    body.Position = Vector3.new(0, keepHeight / 2 + 0.5, 0)
    body.Anchored = true
    body.Material = Materials.Brick
    body.Color = Colors.KeepBase
    body.Parent = keep

    -- Battlements on top
    local battlementCount = 4
    local battlementSize = keepWidth / 4

    for i = 0, battlementCount - 1 do
        local angle = (i / battlementCount) * math.pi * 2
        local offsetX = math.cos(angle) * (keepWidth / 2 - battlementSize / 2)
        local offsetZ = math.sin(angle) * (keepWidth / 2 - battlementSize / 2)

        local battlement = Instance.new("Part")
        battlement.Name = "Battlement"
        battlement.Size = Vector3.new(battlementSize, 1.5, battlementSize)
        battlement.Position = Vector3.new(offsetX, keepHeight + 1.25, offsetZ)
        battlement.Anchored = true
        battlement.Material = Materials.Stone
        battlement.Color = Colors.WallStone
        battlement.Parent = keep
    end

    -- Roof (pointed top for higher TH levels)
    if thLevel >= 5 then
        local roofHeight = 3 + (thLevel - 5) * 0.5
        local roof = Instance.new("Part")
        roof.Name = "Roof"
        roof.Size = Vector3.new(keepWidth - 1, roofHeight, keepWidth - 1)
        roof.Position = Vector3.new(0, keepHeight + 2 + roofHeight / 2, 0)
        roof.Anchored = true
        roof.Material = Materials.Brick
        roof.Color = Colors.KeepRoof
        roof.Parent = keep

        -- Roof point (using wedge)
        local roofPoint = Instance.new("Part")
        roofPoint.Name = "RoofPoint"
        roofPoint.Size = Vector3.new(2, 2, 2)
        roofPoint.Position = Vector3.new(0, keepHeight + 2 + roofHeight + 1, 0)
        roofPoint.Anchored = true
        roofPoint.Material = Materials.Stone
        roofPoint.Color = Colors.WallDark
        roofPoint.Shape = Enum.PartType.Ball
        roofPoint.Parent = keep
    end

    -- Color accent stripe based on difficulty
    local accent = Instance.new("Part")
    accent.Name = "ColorAccent"
    accent.Size = Vector3.new(keepWidth + 0.1, 1, keepWidth + 0.1)
    accent.Position = Vector3.new(0, keepHeight * 0.3, 0)
    accent.Anchored = true
    accent.Material = Materials.Fabric
    accent.Color = color
    accent.Parent = keep

    keep.PrimaryPart = body
    return keep
end

--[[
    Creates the wall ring around the base.
]]
local function createWalls(color: Color3): Model
    local walls = Instance.new("Model")
    walls.Name = "Walls"

    local baseConfig = OverworldConfig.Base
    local wallRadius = baseConfig.WallRadius
    local wallHeight = baseConfig.WallHeight
    local wallThickness = baseConfig.WallThickness

    -- Four wall segments (square layout)
    local wallSegments = {
        {pos = Vector3.new(0, 0, wallRadius), size = Vector3.new(wallRadius * 2, wallHeight, wallThickness)},
        {pos = Vector3.new(0, 0, -wallRadius), size = Vector3.new(wallRadius * 2, wallHeight, wallThickness)},
        {pos = Vector3.new(wallRadius, 0, 0), size = Vector3.new(wallThickness, wallHeight, wallRadius * 2 - wallThickness)},
        {pos = Vector3.new(-wallRadius, 0, 0), size = Vector3.new(wallThickness, wallHeight, wallRadius * 2 - wallThickness)},
    }

    for i, segment in wallSegments do
        local wall = Instance.new("Part")
        wall.Name = "Wall" .. i
        wall.Size = segment.size
        wall.Position = segment.pos + Vector3.new(0, wallHeight / 2, 0)
        wall.Anchored = true
        wall.Material = Materials.Stone
        wall.Color = Colors.WallStone
        wall.Parent = walls
    end

    -- Corner towers
    local towerPositions = {
        Vector3.new(wallRadius, 0, wallRadius),
        Vector3.new(-wallRadius, 0, wallRadius),
        Vector3.new(wallRadius, 0, -wallRadius),
        Vector3.new(-wallRadius, 0, -wallRadius),
    }

    for i, pos in towerPositions do
        local tower = Instance.new("Part")
        tower.Name = "CornerTower" .. i
        tower.Size = Vector3.new(2.5, wallHeight + 2, 2.5)
        tower.Position = pos + Vector3.new(0, (wallHeight + 2) / 2, 0)
        tower.Anchored = true
        tower.Material = Materials.Stone
        tower.Color = Colors.WallDark
        tower.Shape = Enum.PartType.Cylinder
        tower.Parent = walls

        -- Tower cap
        local cap = Instance.new("Part")
        cap.Name = "TowerCap" .. i
        cap.Size = Vector3.new(3, 0.5, 3)
        cap.Position = pos + Vector3.new(0, wallHeight + 2.25, 0)
        cap.Anchored = true
        cap.Material = Materials.Stone
        cap.Color = Colors.WallStone
        cap.Parent = walls
    end

    -- Color the tops of walls with difficulty color
    local wallTop = Instance.new("Part")
    wallTop.Name = "WallColorRing"
    wallTop.Size = Vector3.new(wallRadius * 2 + 2, 0.5, wallRadius * 2 + 2)
    wallTop.Position = Vector3.new(0, wallHeight + 0.25, 0)
    wallTop.Anchored = true
    wallTop.Material = Materials.Fabric
    wallTop.Color = color
    wallTop.Transparency = 0.5
    wallTop.CanCollide = false
    wallTop.Parent = walls

    return walls
end

--[[
    Creates the gate (entry point) for the base.
]]
local function createGate(): Model
    local gate = Instance.new("Model")
    gate.Name = "Gate"

    local baseConfig = OverworldConfig.Base
    local wallRadius = baseConfig.WallRadius
    local gateWidth = 4
    local gateHeight = 4

    -- Gate frame (towers on sides)
    for side = -1, 1, 2 do
        local tower = Instance.new("Part")
        tower.Name = "GateTower"
        tower.Size = Vector3.new(2, gateHeight + 2, 2)
        tower.Position = Vector3.new(side * (gateWidth / 2 + 1), (gateHeight + 2) / 2, -wallRadius)
        tower.Anchored = true
        tower.Material = Materials.Stone
        tower.Color = Colors.WallDark
        tower.Parent = gate
    end

    -- Gate arch
    local arch = Instance.new("Part")
    arch.Name = "Arch"
    arch.Size = Vector3.new(gateWidth, 1, 1.5)
    arch.Position = Vector3.new(0, gateHeight + 0.5, -wallRadius)
    arch.Anchored = true
    arch.Material = Materials.Stone
    arch.Color = Colors.WallStone
    arch.Parent = gate

    -- Gate doors (wooden)
    local door = Instance.new("Part")
    door.Name = "GateDoor"
    door.Size = Vector3.new(gateWidth - 0.5, gateHeight - 0.5, 0.4)
    door.Position = Vector3.new(0, gateHeight / 2, -wallRadius + 0.5)
    door.Anchored = true
    door.Material = Materials.Wood
    door.Color = Colors.GateDoor
    door.Parent = gate

    -- Iron bands on door
    for j = 1, 3 do
        local band = Instance.new("Part")
        band.Name = "IronBand"
        band.Size = Vector3.new(gateWidth - 0.7, 0.2, 0.5)
        band.Position = Vector3.new(0, j * (gateHeight / 4), -wallRadius + 0.4)
        band.Anchored = true
        band.Material = Materials.Metal
        band.Color = Colors.GateIron
        band.Parent = gate
    end

    -- Gate trigger zone (invisible, for interaction)
    local trigger = Instance.new("Part")
    trigger.Name = "GateTrigger"
    trigger.Size = Vector3.new(gateWidth + 4, 8, 8)
    trigger.Position = Vector3.new(0, 4, -wallRadius - 4)
    trigger.Anchored = true
    trigger.Transparency = 1
    trigger.CanCollide = false
    trigger.Parent = gate

    return gate
end

--[[
    Creates the banner with player info.
]]
local function createBanner(username: string, trophies: number, thLevel: number, isOnline: boolean): BillboardGui
    local keepHeight = OverworldConfig.GetKeepHeight(thLevel)

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Banner"
    billboard.Size = UDim2.new(0, 200, 0, 100)
    billboard.StudsOffset = Vector3.new(0, keepHeight + 5, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 150

    -- Main frame
    local frame = Instance.new("Frame")
    frame.Name = "BannerFrame"
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(40, 35, 30)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Parent = billboard

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.1, 0)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(120, 100, 60)
    stroke.Thickness = 2
    stroke.Parent = frame

    -- Username
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "Username"
    nameLabel.Size = UDim2.new(1, 0, 0.4, 0)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = username
    nameLabel.TextColor3 = isOnline and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(220, 210, 180)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = frame

    -- TH Level and Trophies row
    local statsFrame = Instance.new("Frame")
    statsFrame.Name = "Stats"
    statsFrame.Size = UDim2.new(1, 0, 0.35, 0)
    statsFrame.Position = UDim2.new(0, 0, 0.4, 0)
    statsFrame.BackgroundTransparency = 1
    statsFrame.Parent = frame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0.05, 0)
    layout.Parent = statsFrame

    -- TH Label
    local thLabel = Instance.new("TextLabel")
    thLabel.Name = "TH"
    thLabel.Size = UDim2.new(0.4, 0, 1, 0)
    thLabel.BackgroundTransparency = 1
    thLabel.Text = "TH " .. thLevel
    thLabel.TextColor3 = Color3.fromRGB(180, 160, 120)
    thLabel.TextScaled = true
    thLabel.Font = Enum.Font.Gotham
    thLabel.Parent = statsFrame

    -- Trophy Label
    local trophyLabel = Instance.new("TextLabel")
    trophyLabel.Name = "Trophies"
    trophyLabel.Size = UDim2.new(0.5, 0, 1, 0)
    trophyLabel.BackgroundTransparency = 1
    trophyLabel.Text = trophies .. " Trophies"
    trophyLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
    trophyLabel.TextScaled = true
    trophyLabel.Font = Enum.Font.Gotham
    trophyLabel.Parent = statsFrame

    -- Online indicator dot
    if isOnline then
        local onlineDot = Instance.new("Frame")
        onlineDot.Name = "OnlineDot"
        onlineDot.Size = UDim2.new(0.1, 0, 0.1, 0)
        onlineDot.Position = UDim2.new(0.85, 0, 0.05, 0)
        onlineDot.BackgroundColor3 = Color3.fromRGB(50, 255, 50)
        onlineDot.Parent = frame

        local dotCorner = Instance.new("UICorner")
        dotCorner.CornerRadius = UDim.new(1, 0)
        dotCorner.Parent = onlineDot
    end

    return billboard
end

--[[
    Creates a shield visual effect around the base.
]]
local function createShieldEffect(baseSize: number): Part
    local shield = Instance.new("Part")
    shield.Name = "ShieldEffect"
    shield.Size = Vector3.new(baseSize + 5, baseSize / 2, baseSize + 5)
    shield.Position = Vector3.new(0, baseSize / 4, 0)
    shield.Anchored = true
    shield.Material = Enum.Material.ForceField
    shield.Color = OverworldConfig.Visuals.ShieldColor
    shield.Transparency = OverworldConfig.Visuals.ShieldTransparency
    shield.CanCollide = false
    shield.Shape = Enum.PartType.Ball

    return shield
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

export type MiniBaseData = {
    userId: number,
    username: string,
    townHallLevel: number,
    trophies: number,
    position: Vector3,
    isOnline: boolean,
    isFriend: boolean,
    isOwnBase: boolean,
    hasShield: boolean,
}

--[[
    Creates a complete mini-base model for a player.

    @param data MiniBaseData - Player and base information
    @return Model - The created mini-base model
]]
function MiniBaseBuilder.Create(data: MiniBaseData): Model
    local base = Instance.new("Model")
    base.Name = "Base_" .. data.userId

    -- Determine color based on ownership/relationship
    local color: Color3
    if data.isOwnBase then
        color = OverworldConfig.Visuals.OwnBaseColor
    elseif data.isFriend then
        color = OverworldConfig.Visuals.FriendColor
    else
        -- Difficulty color would need attacker's TH level
        -- For now, use medium color
        color = OverworldConfig.Visuals.DifficultyColors.Medium
    end

    -- Create components
    local keep = createKeep(data.townHallLevel, color)
    keep.Parent = base

    local walls = createWalls(color)
    walls.Parent = base

    local gate = createGate()
    gate.Parent = base

    -- Set up banner on keep
    local keepBody = keep:FindFirstChild("Body") :: Part
    if keepBody then
        local banner = createBanner(data.username, data.trophies, data.townHallLevel, data.isOnline)
        banner.Adornee = keepBody
        banner.Parent = keepBody
    end

    -- Add shield effect if shielded
    if data.hasShield then
        local shield = createShieldEffect(OverworldConfig.Base.WallRadius * 2)
        shield.Parent = base
    end

    -- Ground under base
    local ground = Instance.new("Part")
    ground.Name = "BaseGround"
    ground.Size = Vector3.new(OverworldConfig.Base.Size + 4, 0.2, OverworldConfig.Base.Size + 4)
    ground.Position = Vector3.new(0, 0.1, 0)
    ground.Anchored = true
    ground.Material = Enum.Material.Cobblestone
    ground.Color = Colors.Ground
    ground.Parent = base

    -- Set PrimaryPart before positioning
    base.PrimaryPart = ground

    -- Position the base
    base:SetPrimaryPartCFrame(CFrame.new(data.position))

    -- Store data as attribute for reference
    base:SetAttribute("UserId", data.userId)
    base:SetAttribute("Username", data.username)
    base:SetAttribute("TownHallLevel", data.townHallLevel)
    base:SetAttribute("Trophies", data.trophies)
    base:SetAttribute("IsOwnBase", data.isOwnBase)
    base:SetAttribute("IsFriend", data.isFriend)
    base:SetAttribute("HasShield", data.hasShield)

    -- Parent to bases folder
    base.Parent = getBasesFolder()

    return base
end

--[[
    Updates an existing mini-base with new data.

    @param model Model - The existing mini-base model
    @param data MiniBaseData - Updated player and base information
]]
function MiniBaseBuilder.Update(model: Model, data: MiniBaseData)
    -- Update banner
    local keep = model:FindFirstChild("Keep") :: Model?
    if keep then
        local keepBody = keep:FindFirstChild("Body") :: Part?
        if keepBody then
            local oldBanner = keepBody:FindFirstChild("Banner") :: BillboardGui?
            if oldBanner then
                oldBanner:Destroy()
            end

            local newBanner = createBanner(data.username, data.trophies, data.townHallLevel, data.isOnline)
            newBanner.Adornee = keepBody
            newBanner.Parent = keepBody
        end
    end

    -- Update shield
    local existingShield = model:FindFirstChild("ShieldEffect")
    if data.hasShield and not existingShield then
        local shield = createShieldEffect(OverworldConfig.Base.WallRadius * 2)
        shield.Parent = model
    elseif not data.hasShield and existingShield then
        existingShield:Destroy()
    end

    -- Update attributes
    model:SetAttribute("Trophies", data.trophies)
    model:SetAttribute("HasShield", data.hasShield)
end

--[[
    Removes a mini-base model.

    @param userId number - The user ID of the base owner
    @return boolean - True if base was found and removed
]]
function MiniBaseBuilder.Remove(userId: number): boolean
    local basesFolder = getBasesFolder()
    local base = basesFolder:FindFirstChild("Base_" .. userId)

    if base then
        base:Destroy()
        return true
    end

    return false
end

--[[
    Gets a mini-base model by user ID.

    @param userId number - The user ID of the base owner
    @return Model? - The mini-base model, or nil if not found
]]
function MiniBaseBuilder.GetBase(userId: number): Model?
    local basesFolder = getBasesFolder()
    return basesFolder:FindFirstChild("Base_" .. userId) :: Model?
end

--[[
    Updates the difficulty color of a base based on attacker's TH level.

    @param model Model - The mini-base model
    @param attackerTH number - The attacker's Town Hall level
]]
function MiniBaseBuilder.UpdateDifficultyColor(model: Model, attackerTH: number)
    local defenderTH = model:GetAttribute("TownHallLevel") :: number?
    if not defenderTH then return end

    local thDiff = defenderTH - attackerTH
    local color = OverworldConfig.GetDifficultyColor(thDiff)

    -- Update color accent on keep
    local keep = model:FindFirstChild("Keep") :: Model?
    if keep then
        local accent = keep:FindFirstChild("ColorAccent") :: Part?
        if accent then
            accent.Color = color
        end
    end

    -- Update wall color ring
    local walls = model:FindFirstChild("Walls") :: Model?
    if walls then
        local ring = walls:FindFirstChild("WallColorRing") :: Part?
        if ring then
            ring.Color = color
        end
    end
end

--[[
    Gets all mini-base models currently in the world.

    @return {Model} - Array of mini-base models
]]
function MiniBaseBuilder.GetAllBases(): {Model}
    local basesFolder = getBasesFolder()
    local bases = {}

    for _, child in basesFolder:GetChildren() do
        if child:IsA("Model") and child.Name:match("^Base_") then
            table.insert(bases, child)
        end
    end

    return bases
end

--[[
    Highlights a base for interaction.

    @param model Model - The mini-base model
    @param highlighted boolean - Whether to highlight
]]
function MiniBaseBuilder.SetHighlight(model: Model, highlighted: boolean)
    local highlight = model:FindFirstChild("SelectionHighlight") :: Highlight?

    if highlighted and not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "SelectionHighlight"
        highlight.FillColor = Color3.fromRGB(255, 255, 100)
        highlight.FillTransparency = 0.7
        highlight.OutlineColor = Color3.fromRGB(255, 200, 50)
        highlight.OutlineTransparency = 0
        highlight.Parent = model
    elseif not highlighted and highlight then
        highlight:Destroy()
    end
end

return MiniBaseBuilder
