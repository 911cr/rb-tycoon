--!strict
--[[
    BattleArenaService.lua

    Manages in-place instanced battle arenas for Battle Tycoon: Conquest.
    Replaces the TeleportService-based cross-place battle system with
    server-local arena instances that spawn a copy of the defender's base
    at a remote position in the current server.

    SECURITY:
    - All arena operations are server-authoritative
    - Client only receives visual state updates via RemoteEvents
    - Player position and visibility are controlled server-side
    - Rate limited to 1 concurrent battle per player

    Dependencies:
    - DataService (for player/defender data)
    - CombatService (for battle simulation)
    - TroopService (for troop availability)
    - BuildingData (for visual properties)

    Events:
    - ArenaCreated(battleId, attackerUserId, arenaFolder)
    - ArenaDestroyed(battleId)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BuildingData = require(ReplicatedStorage.Shared.Constants.BuildingData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declarations for services (resolved in Init)
local DataService
local CombatService
local TroopService

local BattleArenaService = {}
BattleArenaService.__index = BattleArenaService

-- Events
BattleArenaService.ArenaCreated = Signal.new()
BattleArenaService.ArenaDestroyed = Signal.new()

-- Private state
local _activeArenas: {[string]: ArenaState} = {}
local _playerBattleMap: {[number]: string} = {} -- [userId] = battleId (1 battle per player)
local _arenaIndex: number = 0 -- Incrementing counter for arena Y offsets
local _initialized = false

-- RemoteEvent references (created in Init)
local _requestBattleEvent: RemoteEvent
local _battleArenaReadyEvent: RemoteEvent
local _battleStateUpdateEvent: RemoteEvent
local _battleCompleteEvent: RemoteEvent
local _returnToOverworldEvent: RemoteEvent

-- Constants
local ARENA_BASE_HEIGHT = 500 -- Y offset for first arena
local ARENA_SPACING = 200 -- Y gap between concurrent arenas
local ARENA_SIZE = 40 -- Grid units (40x40)
local STUD_SIZE = 4 -- Studs per grid unit
local POST_BATTLE_DELAY = 5 -- Seconds before cleanup after battle ends

-- Building visual definitions: {sizeX, sizeY, sizeZ, color, material}
type BuildingVisual = {
    size: Vector3,
    color: Color3,
    material: Enum.Material,
}

local BUILDING_VISUALS: {[string]: BuildingVisual} = {
    TownHall = {
        size = Vector3.new(6, 8, 6),
        color = Color3.fromRGB(80, 80, 80),
        material = Enum.Material.Brick,
    },
    GoldMine = {
        size = Vector3.new(4, 4, 4),
        color = Color3.fromRGB(230, 200, 50),
        material = Enum.Material.SmoothPlastic,
    },
    LumberMill = {
        size = Vector3.new(4, 4, 4),
        color = Color3.fromRGB(60, 140, 40),
        material = Enum.Material.WoodPlanks,
    },
    Farm = {
        size = Vector3.new(4, 4, 4),
        color = Color3.fromRGB(160, 110, 50),
        material = Enum.Material.Grass,
    },
    GoldStorage = {
        size = Vector3.new(4, 5, 4),
        color = Color3.fromRGB(210, 180, 50),
        material = Enum.Material.SmoothPlastic,
    },
    Barracks = {
        size = Vector3.new(5, 4, 5),
        color = Color3.fromRGB(180, 50, 50),
        material = Enum.Material.SmoothPlastic,
    },
    ArmyCamp = {
        size = Vector3.new(5, 4, 5),
        color = Color3.fromRGB(160, 60, 60),
        material = Enum.Material.Fabric,
    },
    SpellFactory = {
        size = Vector3.new(4, 5, 4),
        color = Color3.fromRGB(130, 50, 180),
        material = Enum.Material.Neon,
    },
    Cannon = {
        size = Vector3.new(3, 3, 3),
        color = Color3.fromRGB(40, 40, 100),
        material = Enum.Material.Metal,
    },
    ArcherTower = {
        size = Vector3.new(3, 6, 3),
        color = Color3.fromRGB(50, 50, 120),
        material = Enum.Material.Brick,
    },
    Mortar = {
        size = Vector3.new(3, 2, 3),
        color = Color3.fromRGB(60, 60, 110),
        material = Enum.Material.Metal,
    },
    AirDefense = {
        size = Vector3.new(3, 5, 3),
        color = Color3.fromRGB(50, 50, 130),
        material = Enum.Material.Metal,
    },
    WizardTower = {
        size = Vector3.new(3, 7, 3),
        color = Color3.fromRGB(70, 40, 140),
        material = Enum.Material.Neon,
    },
    Wall = {
        size = Vector3.new(4, 3, 4),
        color = Color3.fromRGB(140, 140, 140),
        material = Enum.Material.Slate,
    },
}

-- Internal types
type ArenaState = {
    battleId: string,
    arenaId: string,
    attackerUserId: number,
    defenderUserId: number,
    arenaFolder: Folder,
    arenaCenter: Vector3,
    arenaYOffset: number,
    buildingParts: {[string]: Part}, -- [buildingId] = Part
    savedPlayerState: SavedPlayerState?,
    createdAt: number,
    isCleaningUp: boolean,
}

type SavedPlayerState = {
    position: CFrame,
    transparencyMap: {[BasePart]: number}, -- original transparency values
    autoRotate: boolean,
}

type ArenaBuildingInfo = {
    buildingId: string,
    buildingType: string,
    level: number,
    gridX: number,
    gridZ: number,
    maxHp: number,
    category: string,
}

type CreateArenaResult = {
    success: boolean,
    battleId: string?,
    error: string?,
}

--[[
    Creates a RemoteEvent under ReplicatedStorage.Events.
    If it already exists, returns the existing one.
]]
local function getOrCreateRemoteEvent(name: string): RemoteEvent
    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    if not eventsFolder then
        eventsFolder = Instance.new("Folder")
        eventsFolder.Name = "Events"
        eventsFolder.Parent = ReplicatedStorage
    end

    local existing = eventsFolder:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then
        return existing
    end

    local event = Instance.new("RemoteEvent")
    event.Name = name
    event.Parent = eventsFolder
    return event
end

--[[
    Ensures the workspace.BattleArenas folder exists.
]]
local function getArenasFolder(): Folder
    local folder = workspace:FindFirstChild("BattleArenas")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "BattleArenas"
        folder.Parent = workspace
    end
    return folder :: Folder
end

--[[
    Allocates a unique Y offset for the next arena.
    Uses an incrementing counter so arenas never overlap.
]]
local function allocateArenaYOffset(): number
    _arenaIndex += 1
    return ARENA_BASE_HEIGHT + (_arenaIndex * ARENA_SPACING)
end

--[[
    Converts a grid position (0-based, in grid units) to a world position
    relative to the arena center.

    Grid is ARENA_SIZE x ARENA_SIZE (40x40 units), centered on arena center.
    Each grid unit is STUD_SIZE studs (4).
]]
local function gridToWorldPosition(gridX: number, gridZ: number, arenaCenter: Vector3, buildingSize: Vector3): Vector3
    local halfGrid = ARENA_SIZE / 2
    local offsetX = (gridX - halfGrid) * STUD_SIZE
    local offsetZ = (gridZ - halfGrid) * STUD_SIZE
    -- Y is half the building height so the bottom sits on the arena floor
    return Vector3.new(
        arenaCenter.X + offsetX,
        arenaCenter.Y + (buildingSize.Y / 2),
        arenaCenter.Z + offsetZ
    )
end

--[[
    Gets the visual definition for a building type.
    Falls back to a default gray block if type is unknown.
]]
local function getBuildingVisual(buildingType: string): BuildingVisual
    local visual = BUILDING_VISUALS[buildingType]
    if visual then
        return visual
    end
    -- Fallback for unknown building types
    return {
        size = Vector3.new(4, 4, 4),
        color = Color3.fromRGB(128, 128, 128),
        material = Enum.Material.SmoothPlastic,
    }
end

--[[
    Creates a floor part for the arena so the buildings have visible ground.
]]
local function createArenaFloor(arenaFolder: Folder, arenaCenter: Vector3)
    local floorSize = ARENA_SIZE * STUD_SIZE
    local floor = Instance.new("Part")
    floor.Name = "ArenaFloor"
    floor.Size = Vector3.new(floorSize, 1, floorSize)
    floor.Position = Vector3.new(arenaCenter.X, arenaCenter.Y - 0.5, arenaCenter.Z)
    floor.Anchored = true
    floor.CanCollide = true
    floor.Material = Enum.Material.Grass
    floor.Color = Color3.fromRGB(80, 120, 40)
    floor.Parent = arenaFolder
end

--[[
    Creates a 3D Part representing a building in the arena.
    Tags it with attributes for identification and combat tracking.
]]
local function createBuildingPart(
    arenaFolder: Folder,
    buildingInfo: ArenaBuildingInfo,
    arenaCenter: Vector3
): Part
    local visual = getBuildingVisual(buildingInfo.buildingType)
    local worldPos = gridToWorldPosition(
        buildingInfo.gridX,
        buildingInfo.gridZ,
        arenaCenter,
        visual.size
    )

    local part = Instance.new("Part")
    part.Name = buildingInfo.buildingType .. "_" .. buildingInfo.buildingId
    part.Size = visual.size
    part.Position = worldPos
    part.Anchored = true
    part.CanCollide = true
    part.Material = visual.material
    part.Color = visual.color

    -- Tag with combat attributes
    part:SetAttribute("BuildingId", buildingInfo.buildingId)
    part:SetAttribute("BuildingType", buildingInfo.buildingType)
    part:SetAttribute("MaxHp", buildingInfo.maxHp)
    part:SetAttribute("CurrentHp", buildingInfo.maxHp)
    part:SetAttribute("Category", buildingInfo.category)
    part:SetAttribute("Level", buildingInfo.level)

    -- Add BillboardGui with building name
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Label"
    billboard.Size = UDim2.new(0, 100, 0, 30)
    billboard.StudsOffset = Vector3.new(0, visual.size.Y / 2 + 1, 0)
    billboard.AlwaysOnTop = false
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Name = "NameLabel"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = buildingInfo.buildingType .. " Lv." .. tostring(buildingInfo.level)
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.5
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    -- Add HP bar billboard
    local hpBillboard = Instance.new("BillboardGui")
    hpBillboard.Name = "HpBar"
    hpBillboard.Size = UDim2.new(0, 80, 0, 10)
    hpBillboard.StudsOffset = Vector3.new(0, visual.size.Y / 2 + 0.5, 0)
    hpBillboard.AlwaysOnTop = false
    hpBillboard.Parent = part

    local hpBackground = Instance.new("Frame")
    hpBackground.Name = "Background"
    hpBackground.Size = UDim2.new(1, 0, 1, 0)
    hpBackground.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    hpBackground.BorderSizePixel = 0
    hpBackground.Parent = hpBillboard

    local hpFill = Instance.new("Frame")
    hpFill.Name = "Fill"
    hpFill.Size = UDim2.new(1, 0, 1, 0) -- starts at 100%
    hpFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
    hpFill.BorderSizePixel = 0
    hpFill.Parent = hpBackground

    part.Parent = arenaFolder

    return part
end

--[[
    Extracts building info from defender data and converts to ArenaBuildingInfo list.
    Uses building.position if available (as grid coords), otherwise distributes
    buildings in a grid pattern around the center.
]]
local function extractBuildingLayout(defenderData: any): {ArenaBuildingInfo}
    local buildings: {ArenaBuildingInfo} = {}
    local fallbackIndex = 0

    for id, building in defenderData.buildings do
        local buildingDef = BuildingData.GetByType(building.type)
        if not buildingDef then continue end

        local levelData = BuildingData.GetLevelData(building.type, building.level or 1)
        local maxHp = if levelData and levelData.hp then levelData.hp else 100

        -- Determine grid position
        local gridX: number
        local gridZ: number

        if building.position and typeof(building.position) == "Vector3" then
            -- Use stored position (as grid coordinates)
            gridX = math.clamp(math.floor(building.position.X), 0, ARENA_SIZE - 1)
            gridZ = math.clamp(math.floor(building.position.Z), 0, ARENA_SIZE - 1)
        else
            -- Fallback: distribute buildings in a spiral-like grid pattern
            local cols = math.ceil(math.sqrt(ARENA_SIZE))
            local row = math.floor(fallbackIndex / cols)
            local col = fallbackIndex % cols
            gridX = math.clamp(10 + col * 3, 0, ARENA_SIZE - 1)
            gridZ = math.clamp(10 + row * 3, 0, ARENA_SIZE - 1)
            fallbackIndex += 1
        end

        table.insert(buildings, {
            buildingId = id,
            buildingType = building.type,
            level = building.level or 1,
            gridX = gridX,
            gridZ = gridZ,
            maxHp = maxHp,
            category = buildingDef.category or "other",
        })
    end

    return buildings
end

--[[
    Hides the player's overworld character by setting all BaseParts to transparent
    and disabling HumanoidAutoRotate. Stores original state for restoration.
]]
local function hidePlayerCharacter(player: Player): SavedPlayerState?
    local character = player.Character
    if not character then return nil end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoidRootPart then return nil end

    local savedState: SavedPlayerState = {
        position = humanoidRootPart.CFrame,
        transparencyMap = {},
        autoRotate = if humanoid then humanoid.AutoRotate else true,
    }

    -- Store and set transparency for all BaseParts
    for _, descendant in character:GetDescendants() do
        if descendant:IsA("BasePart") then
            savedState.transparencyMap[descendant] = descendant.Transparency
            descendant.Transparency = 1
        end
    end

    -- Disable auto-rotate so invisible character does not react to input
    if humanoid then
        humanoid.AutoRotate = false
    end

    -- Anchor the humanoid root part so character does not fall
    humanoidRootPart.Anchored = true

    return savedState
end

--[[
    Restores the player's overworld character from saved state.
    Re-shows all parts and re-enables HumanoidAutoRotate.
]]
local function restorePlayerCharacter(player: Player, savedState: SavedPlayerState?)
    if not savedState then return end

    local character = player.Character
    if not character then return end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    -- Restore transparency for all saved parts
    for part, originalTransparency in savedState.transparencyMap do
        if part and part.Parent then
            part.Transparency = originalTransparency
        end
    end

    -- Restore auto-rotate
    if humanoid then
        humanoid.AutoRotate = savedState.autoRotate
    end

    -- Unanchor and restore position
    if humanoidRootPart then
        humanoidRootPart.Anchored = false
        humanoidRootPart.CFrame = savedState.position
    end
end

--[[
    Serializes the building layout for transmission to the client.
    Returns a list of tables with only serializable data (no Part references).
]]
local function serializeBuildingLayout(arena: ArenaState): {any}
    local layout = {}
    for buildingId, part in arena.buildingParts do
        table.insert(layout, {
            buildingId = buildingId,
            buildingType = part:GetAttribute("BuildingType"),
            level = part:GetAttribute("Level"),
            maxHp = part:GetAttribute("MaxHp"),
            currentHp = part:GetAttribute("CurrentHp"),
            category = part:GetAttribute("Category"),
            position = part.Position,
            size = part.Size,
        })
    end
    return layout
end

--[[
    Updates the visual HP bar on a building part based on currentHp / maxHp ratio.
]]
local function updateBuildingHpVisual(part: Part, currentHp: number, maxHp: number)
    local ratio = math.clamp(currentHp / math.max(maxHp, 1), 0, 1)

    -- Update the attribute
    part:SetAttribute("CurrentHp", currentHp)

    -- Update HP bar fill
    local hpBar = part:FindFirstChild("HpBar") :: BillboardGui?
    if hpBar then
        local background = hpBar:FindFirstChild("Background") :: Frame?
        if background then
            local fill = background:FindFirstChild("Fill") :: Frame?
            if fill then
                fill.Size = UDim2.new(ratio, 0, 1, 0)
                -- Color gradient: green -> yellow -> red
                if ratio > 0.6 then
                    fill.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
                elseif ratio > 0.3 then
                    fill.BackgroundColor3 = Color3.fromRGB(220, 200, 30)
                else
                    fill.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
                end
            end
        end
    end

    -- If destroyed, make part translucent and dark
    if currentHp <= 0 then
        part.Transparency = 0.6
        part.Color = Color3.fromRGB(60, 60, 60)
    end
end

--[[
    Creates a battle arena: loads defender data, spawns buildings,
    hides attacker, starts combat simulation.

    @param attacker Player - The attacking player
    @param defenderUserId number - The defender's UserId (may be offline)
    @param options table? - Optional battle options (passed through to CombatService):
        - isRevenge: boolean - If true, skip shield check and grant revenge loot bonus
    @return CreateArenaResult - Success/failure with battleId or error
]]
function BattleArenaService:CreateArena(attacker: Player, defenderUserId: number, options: {isRevenge: boolean?}?): CreateArenaResult
    -- 1. VALIDATE ATTACKER
    if not attacker or not attacker:IsA("Player") then
        return { success = false, battleId = nil, error = "INVALID_ATTACKER" }
    end

    -- 2. VALIDATE ATTACKER IS NOT ALREADY IN BATTLE
    if _playerBattleMap[attacker.UserId] then
        return { success = false, battleId = nil, error = "ALREADY_IN_BATTLE" }
    end

    -- 3. VALIDATE DEFENDER
    if typeof(defenderUserId) ~= "number" then
        return { success = false, battleId = nil, error = "INVALID_DEFENDER" }
    end

    -- Prevent self-attack
    if defenderUserId == attacker.UserId then
        return { success = false, battleId = nil, error = "CANNOT_ATTACK_SELF" }
    end

    -- 4. LOAD DEFENDER DATA
    local defenderData
    local defenderPlayer = Players:GetPlayerByUserId(defenderUserId)
    if defenderPlayer then
        defenderData = DataService:GetPlayerData(defenderPlayer)
    end
    if not defenderData then
        defenderData = DataService:GetPlayerDataById(defenderUserId)
    end
    if not defenderData then
        return { success = false, battleId = nil, error = "DEFENDER_NOT_FOUND" }
    end

    -- 5. VERIFY DEFENDER HAS BUILDINGS
    local hasBuildingsToClone = false
    for _ in defenderData.buildings do
        hasBuildingsToClone = true
        break
    end
    if not hasBuildingsToClone then
        return { success = false, battleId = nil, error = "DEFENDER_NO_BUILDINGS" }
    end

    -- 6. START COMBAT (via CombatService -- validates troops, shield, etc.)
    local combatResult = CombatService:StartBattle(attacker, defenderUserId, options)
    if not combatResult.success then
        return { success = false, battleId = nil, error = combatResult.error }
    end

    local battleId = combatResult.battleId :: string

    -- 7. ALLOCATE ARENA SPACE
    local arenaYOffset = allocateArenaYOffset()
    local arenaCenter = Vector3.new(0, arenaYOffset, 0)
    local arenaId = "Arena_" .. battleId

    -- 8. CREATE ARENA FOLDER
    local arenasFolder = getArenasFolder()
    local arenaFolder = Instance.new("Folder")
    arenaFolder.Name = arenaId
    arenaFolder.Parent = arenasFolder

    -- 9. CREATE ARENA FLOOR
    createArenaFloor(arenaFolder, arenaCenter)

    -- 10. CLONE DEFENDER BUILDINGS INTO ARENA
    local buildingLayout = extractBuildingLayout(defenderData)
    local buildingParts: {[string]: Part} = {}

    for _, buildingInfo in buildingLayout do
        local part = createBuildingPart(arenaFolder, buildingInfo, arenaCenter)
        buildingParts[buildingInfo.buildingId] = part
    end

    -- 11. HIDE ATTACKER IN OVERWORLD
    local savedState = hidePlayerCharacter(attacker)

    -- 12. STORE ARENA STATE
    local arenaState: ArenaState = {
        battleId = battleId,
        arenaId = arenaId,
        attackerUserId = attacker.UserId,
        defenderUserId = defenderUserId,
        arenaFolder = arenaFolder,
        arenaCenter = arenaCenter,
        arenaYOffset = arenaYOffset,
        buildingParts = buildingParts,
        savedPlayerState = savedState,
        createdAt = os.time(),
        isCleaningUp = false,
    }

    _activeArenas[battleId] = arenaState
    _playerBattleMap[attacker.UserId] = battleId

    -- 13. NOTIFY CLIENT: Arena is ready
    local serializedLayout = serializeBuildingLayout(arenaState)
    _battleArenaReadyEvent:FireClient(attacker, {
        battleId = battleId,
        arenaCenter = arenaCenter,
        arenaSize = ARENA_SIZE * STUD_SIZE,
        buildings = serializedLayout,
        defenderName = defenderData.username or ("Player " .. tostring(defenderUserId)),
        defenderTownHallLevel = defenderData.townHallLevel or 1,
        isRevenge = options and options.isRevenge or false,
    })

    -- 14. FIRE INTERNAL EVENT
    BattleArenaService.ArenaCreated:Fire(battleId, attacker.UserId, arenaFolder)

    print(string.format(
        "[BattleArenaService] Arena created: battleId=%s, attacker=%s, defender=%d, Y=%d",
        battleId, attacker.Name, defenderUserId, arenaYOffset
    ))

    return { success = true, battleId = battleId, error = nil }
end

--[[
    Destroys a battle arena: removes all parts, restores player character,
    cleans up state tracking.

    @param battleId string - The battle ID whose arena to destroy
]]
function BattleArenaService:DestroyArena(battleId: string)
    local arena = _activeArenas[battleId]
    if not arena then
        warn("[BattleArenaService] DestroyArena called for unknown battleId:", battleId)
        return
    end

    -- Prevent double cleanup
    if arena.isCleaningUp then return end
    arena.isCleaningUp = true

    -- 1. RESTORE ATTACKER CHARACTER
    local attacker = Players:GetPlayerByUserId(arena.attackerUserId)
    if attacker then
        restorePlayerCharacter(attacker, arena.savedPlayerState)
    end

    -- 2. DESTROY ALL ARENA PARTS
    if arena.arenaFolder and arena.arenaFolder.Parent then
        arena.arenaFolder:Destroy()
    end

    -- 3. CLEAN UP STATE
    _playerBattleMap[arena.attackerUserId] = nil
    _activeArenas[battleId] = nil

    -- 4. FIRE INTERNAL EVENT
    BattleArenaService.ArenaDestroyed:Fire(battleId)

    print(string.format(
        "[BattleArenaService] Arena destroyed: battleId=%s",
        battleId
    ))
end

--[[
    Gets the arena state for a given battle.
]]
function BattleArenaService:GetArena(battleId: string): ArenaState?
    return _activeArenas[battleId]
end

--[[
    Gets the active battle ID for a player, if any.
]]
function BattleArenaService:GetPlayerBattleId(player: Player): string?
    return _playerBattleMap[player.UserId]
end

--[[
    Checks if a player is currently in a battle.
]]
function BattleArenaService:IsPlayerInBattle(player: Player): boolean
    return _playerBattleMap[player.UserId] ~= nil
end

--[[
    Handles per-tick visual updates from CombatService.
    Updates building HP visuals and sends state to the client.
]]
local function onBattleTick(battleId: string, battleState: any)
    local arena = _activeArenas[battleId]
    if not arena then return end

    -- Retrieve the internal building targets from CombatService
    -- CombatService stores them at battleId .. "_targets"
    local targets = CombatService:GetBattleState(battleId)
    if not targets then return end

    -- Build a serializable state update for the client
    local buildingUpdates = {}
    local troopPositions = {}

    -- Update building HP visuals from combat targets
    -- CombatService stores targets in _activeBattles[battleId .. "_targets"]
    -- We read the attributes on our Parts which we update below
    for buildingId, part in arena.buildingParts do
        local currentHp = part:GetAttribute("CurrentHp") or 0
        local maxHp = part:GetAttribute("MaxHp") or 1
        table.insert(buildingUpdates, {
            buildingId = buildingId,
            currentHp = currentHp,
            maxHp = maxHp,
        })
    end

    -- Serialize troop positions from battle state
    if battleState and battleState.troops then
        for _, troop in battleState.troops do
            if troop.state ~= "dead" then
                table.insert(troopPositions, {
                    id = troop.id,
                    type = troop.type,
                    position = troop.position,
                    state = troop.state,
                    currentHp = troop.currentHp,
                    maxHp = troop.maxHp,
                    targetId = troop.targetId,
                })
            end
        end
    end

    -- Fire state update to attacker
    local attacker = Players:GetPlayerByUserId(arena.attackerUserId)
    if attacker then
        _battleStateUpdateEvent:FireClient(attacker, {
            battleId = battleId,
            destruction = if battleState then battleState.destruction else 0,
            starsEarned = if battleState then battleState.starsEarned else 0,
            phase = if battleState then battleState.phase else "battle",
            timeRemaining = if battleState then math.max(0, battleState.endsAt - os.time()) else 0,
            buildings = buildingUpdates,
            troops = troopPositions,
        })
    end
end

--[[
    Synchronizes CombatService building target HP with arena building Parts.
    Called each tick to keep visuals in sync with the server simulation.
]]
local function syncBuildingHpFromCombat(battleId: string)
    local arena = _activeArenas[battleId]
    if not arena then return end

    -- CombatService stores targets at _activeBattles[battleId .. "_targets"]
    -- We access them via GetBattleState to check if battle exists, then read
    -- the internal target data. Since CombatService stores building targets
    -- in its own internal state, we use a polling approach: compare building IDs
    -- and update our Part attributes accordingly.
    --
    -- The CombatService target data is not directly exposed via API, so we
    -- read the battle state and use the building HP data from its internal
    -- metadata. We access it through the battle state's building data
    -- via the module-level reference to CombatService internals.
    --
    -- For now, we rely on the BattleTick signal to pass us the full state,
    -- and we sync during the onBattleTick callback.
    -- This function is kept as a named reference for the tick connection.
end

--[[
    Handles the BattleTick signal from CombatService.
    Updates arena building visuals to match simulation state.
]]
local function handleBattleTick(battleId: string, battleState: any)
    local arena = _activeArenas[battleId]
    if not arena then return end

    -- CombatService fires BattleTick with the full BattleState.
    -- The building targets are stored internally in CombatService.
    -- We need to update our arena Parts' HP attributes based on the
    -- combat simulation. Since CombatService does not expose target HP
    -- directly via BattleState, we compute building HP from destruction %.
    --
    -- However, the CombatService stores targets at battleId.."_targets" in
    -- its internal _activeBattles table. We can read building HP changes
    -- by comparing our Part attributes with the combat state.
    --
    -- Strategy: CombatService's getDefenderBuildings() creates targets with
    -- building IDs matching the defender's data keys. Our arena parts use
    -- the same keys. We track destruction via the overall destruction percentage
    -- and distribute damage proportionally, or we implement a direct bridge.
    --
    -- For the most accurate approach: we expose a method on CombatService to
    -- get building target states. Since we cannot modify CombatService here,
    -- we use the destruction percentage to estimate individual building damage.
    -- This is an approximation -- future integration should add a
    -- CombatService:GetBuildingTargets(battleId) method for exact HP sync.

    if not battleState then return end

    -- Approximate building HP from overall destruction and per-building tracking
    -- We apply proportional damage based on destruction increase
    local destruction = battleState.destruction or 0

    -- Update building parts: mark destroyed buildings based on which targets
    -- CombatService has flagged. We iterate all parts and check if the combat
    -- system has marked them as destroyed by checking if destruction is >= 100
    -- for all, or individually mark based on the destruction progression.
    --
    -- Simple approach: scale all non-TH building HP by (100 - destruction) / 100
    -- and mark the TH as destroyed if townHallDestroyed is true.
    for buildingId, part in arena.buildingParts do
        local maxHp = part:GetAttribute("MaxHp") or 100
        local buildingType = part:GetAttribute("BuildingType") or ""

        local newHp: number

        if buildingType == "TownHall" and battleState.townHallDestroyed then
            newHp = 0
        elseif destruction >= 100 then
            newHp = 0
        else
            -- Scale HP proportionally to destruction
            -- This is an approximation; actual per-building HP tracking
            -- requires CombatService to expose target data
            newHp = math.floor(maxHp * (1 - destruction / 100))
        end

        local currentHp = part:GetAttribute("CurrentHp") or maxHp
        -- Only decrease HP (buildings do not heal mid-battle)
        if newHp < currentHp then
            updateBuildingHpVisual(part, newHp, maxHp)
        end
    end

    -- Forward the tick update to the client
    onBattleTick(battleId, battleState)
end

--[[
    Handles the BattleEnded signal from CombatService.
    Sends results to client and schedules arena cleanup.
]]
local function handleBattleEnded(battleId: string, result: any)
    local arena = _activeArenas[battleId]
    if not arena then return end

    -- Send battle result to attacker client
    local attacker = Players:GetPlayerByUserId(arena.attackerUserId)
    if attacker then
        _battleCompleteEvent:FireClient(attacker, {
            battleId = battleId,
            victory = result.victory,
            destruction = result.destruction,
            stars = result.stars,
            isConquest = result.isConquest,
            loot = result.loot,
            trophiesGained = result.trophiesGained,
            xpGained = result.xpGained,
            duration = result.duration,
            troopsLost = result.troopsLost,
            buildingsDestroyed = result.buildingsDestroyed,
        })
    end

    -- Schedule cleanup after post-battle delay
    -- The client shows the results screen for POST_BATTLE_DELAY seconds,
    -- then the player can click "Return" or we auto-cleanup
    task.delay(POST_BATTLE_DELAY, function()
        -- If player has not manually returned yet, clean up
        if _activeArenas[battleId] and not _activeArenas[battleId].isCleaningUp then
            BattleArenaService:DestroyArena(battleId)
            -- Notify client to return camera to overworld
            if attacker and attacker.Parent then
                _returnToOverworldEvent:FireClient(attacker, {
                    battleId = battleId,
                })
            end
        end
    end)

    print(string.format(
        "[BattleArenaService] Battle ended: battleId=%s, destruction=%d%%, stars=%d",
        battleId, result.destruction, result.stars
    ))
end

--[[
    Handles the RequestBattle RemoteEvent from client.
    Validates and initiates a battle arena.

    SECURITY:
    - Rate limited: 1 battle per player at a time
    - Type validation on all parameters
    - Player existence validated
]]
local function handleRequestBattle(player: Player, defenderUserId: any)
    -- Type validation
    if typeof(defenderUserId) ~= "number" then return end

    -- Integer validation
    if defenderUserId ~= math.floor(defenderUserId) then return end

    -- Range validation (valid Roblox UserIds are positive)
    if defenderUserId <= 0 then return end

    -- Rate limit: 1 battle at a time
    if _playerBattleMap[player.UserId] then
        warn("[BattleArenaService] Player already in battle:", player.Name)
        return
    end

    -- Create the arena
    local result = BattleArenaService:CreateArena(player, defenderUserId)

    if not result.success then
        -- Notify client of failure
        _battleArenaReadyEvent:FireClient(player, {
            battleId = nil,
            error = result.error,
        })
    end
end

--[[
    Handles the ReturnToOverworld RemoteEvent from client.
    Player clicked "Return" after viewing battle results.
    Triggers arena cleanup if not already cleaning up.
]]
local function handleReturnToOverworld(player: Player, data: any)
    local battleId = _playerBattleMap[player.UserId]
    if not battleId then return end

    local arena = _activeArenas[battleId]
    if not arena then return end

    -- Verify this is the correct player
    if arena.attackerUserId ~= player.UserId then return end

    -- Destroy the arena (restores player)
    BattleArenaService:DestroyArena(battleId)
end

--[[
    Handles player disconnect during battle.
    Cleans up the arena immediately to prevent orphaned state.
]]
local function handlePlayerRemoving(player: Player)
    local battleId = _playerBattleMap[player.UserId]
    if not battleId then return end

    local arena = _activeArenas[battleId]
    if not arena then
        _playerBattleMap[player.UserId] = nil
        return
    end

    -- End the battle in CombatService if still active
    local battleState = CombatService:GetBattleState(battleId)
    if battleState and battleState.phase ~= "ended" then
        CombatService:EndBattle(battleId)
    end

    -- Clean up arena (do not try to restore character since player is leaving)
    arena.savedPlayerState = nil
    BattleArenaService:DestroyArena(battleId)
end

--[[
    Initializes the BattleArenaService.
    Creates RemoteEvents and connects to CombatService signals.
]]
function BattleArenaService:Init()
    if _initialized then
        warn("BattleArenaService already initialized")
        return
    end

    -- Resolve service references
    DataService = require(ServerScriptService.Services.DataService)
    CombatService = require(ServerScriptService.Services.CombatService)
    TroopService = require(ServerScriptService.Services.TroopService)

    -- Create RemoteEvents
    _requestBattleEvent = getOrCreateRemoteEvent("RequestBattle")
    _battleArenaReadyEvent = getOrCreateRemoteEvent("BattleArenaReady")
    _battleStateUpdateEvent = getOrCreateRemoteEvent("BattleStateUpdate")
    _battleCompleteEvent = getOrCreateRemoteEvent("BattleComplete")
    _returnToOverworldEvent = getOrCreateRemoteEvent("ReturnToOverworld")

    -- Connect client -> server events
    _requestBattleEvent.OnServerEvent:Connect(handleRequestBattle)
    _returnToOverworldEvent.OnServerEvent:Connect(handleReturnToOverworld)

    -- Connect to CombatService signals
    CombatService.BattleTick:Connect(handleBattleTick)
    CombatService.BattleEnded:Connect(handleBattleEnded)

    -- Handle player disconnect during battle
    Players.PlayerRemoving:Connect(handlePlayerRemoving)

    -- Periodic cleanup: destroy orphaned arenas (safety net)
    task.spawn(function()
        while true do
            task.wait(60) -- Check every minute
            local now = os.time()
            for battleId, arena in _activeArenas do
                -- If arena has existed for more than 10 minutes, force cleanup
                -- (battles max out at 3 minutes + 30s scout + 5s post-battle)
                local maxArenaLifetime = 600 -- 10 minutes
                if now - arena.createdAt > maxArenaLifetime and not arena.isCleaningUp then
                    warn(string.format(
                        "[BattleArenaService] Force-cleaning orphaned arena: battleId=%s, age=%ds",
                        battleId, now - arena.createdAt
                    ))
                    BattleArenaService:DestroyArena(battleId)
                end
            end
        end
    end)

    _initialized = true
    print("BattleArenaService initialized")
end

return BattleArenaService
