--!strict
--[[
    TreasureChestService.lua

    Manages treasure chest spawning and collection in the overworld.
    Follows ResourceNodeService pattern: per-player cooldowns, distance validation.

    ~20 chests scattered across wilderness and forbidden zones.
    Visual Part-based chest models grounded on terrain via raycast.
    Loot goes to carried loot (not directly to resources).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local TreasureChestData = require(ReplicatedStorage.Shared.Constants.TreasureChestData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local TreasureChestService = {}
TreasureChestService.__index = TreasureChestService

-- ============================================================================
-- SIGNALS
-- ============================================================================

TreasureChestService.ChestCollected = Signal.new() -- (player, chestId, loot)

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

-- Per-player cooldowns: _cooldowns[userId][chestId] = expiresAt timestamp
local _cooldowns: {[number]: {[string]: number}} = {}

-- Chest models in world
local _chestModels: {[string]: Model} = {}

local _initialized = false

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

local function getTerrainY(x: number, z: number): number
    return OverworldConfig.GetTerrainHeight(x, z)
end

--[[
    Creates a visual chest model on the terrain.
]]
local function createChestModel(chest: any): Model
    local x, z = chest.x, chest.z
    local y = getTerrainY(x, z)
    local typeConfig = TreasureChestData.Types[chest.zone]

    local model = Instance.new("Model")
    model.Name = "Chest_" .. chest.id

    -- Chest body
    local body = Instance.new("Part")
    body.Name = "ChestBody"
    body.Size = Vector3.new(2.5, 1.8, 1.8)
    body.Anchored = true
    body.CanCollide = false
    body.Material = Enum.Material.WoodPlanks
    body.Color = typeConfig.color
    body.CFrame = CFrame.new(x, y + 0.6, z) -- Partially embedded
    body.Parent = model

    -- Lid (gold/purple accent)
    local lid = Instance.new("Part")
    lid.Name = "Lid"
    lid.Size = Vector3.new(2.5, 0.4, 1.8)
    lid.Anchored = true
    lid.CanCollide = false
    lid.Material = Enum.Material.Metal
    lid.Color = typeConfig.accentColor
    lid.CFrame = CFrame.new(x, y + 1.7, z)
    lid.Parent = model

    -- Sparkles
    local sparkles = Instance.new("Sparkles")
    sparkles.SparkleColor = typeConfig.accentColor
    sparkles.Parent = lid

    -- Billboard label
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 100, 0, 25)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 30
    billboard.Parent = body

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = typeConfig.displayName
    label.TextColor3 = typeConfig.accentColor
    label.TextStrokeTransparency = 0.3
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    model.PrimaryPart = body

    -- Place in Overworld folder
    local owFolder = workspace:FindFirstChild("Overworld")
    if not owFolder then
        owFolder = Instance.new("Folder")
        owFolder.Name = "Overworld"
        owFolder.Parent = workspace
    end
    local chestFolder = owFolder:FindFirstChild("TreasureChests")
    if not chestFolder then
        chestFolder = Instance.new("Folder")
        chestFolder.Name = "TreasureChests"
        chestFolder.Parent = owFolder
    end

    model.Parent = chestFolder
    return model
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function TreasureChestService:Init()
    if _initialized then return end
    _initialized = true

    -- Create all chest models
    for _, chest in TreasureChestData.GetAllChests() do
        task.defer(function()
            _chestModels[chest.id] = createChestModel(chest)
        end)
    end

    print(string.format("[TreasureChestService] Initialized %d chests", #TreasureChestData.GetAllChests()))
end

--[[
    Attempts to collect a chest. Validates proximity, cooldown, and rolls loot.

    @param player Player
    @param chestId string
    @return boolean, table?, string? - (success, loot, errorReason)
]]
function TreasureChestService:CollectChest(player: Player, chestId: string): (boolean, any?, string?)
    local chest = TreasureChestData.GetChestById(chestId)
    if not chest then
        return false, nil, "CHEST_NOT_FOUND"
    end

    -- Check per-player cooldown
    local userId = player.UserId
    _cooldowns[userId] = _cooldowns[userId] or {}
    local cooldownEnd = _cooldowns[userId][chestId] or 0
    if os.time() < cooldownEnd then
        return false, nil, "ON_COOLDOWN"
    end

    -- Check proximity
    local character = player.Character
    if not character then
        return false, nil, "NO_CHARACTER"
    end
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then
        return false, nil, "NO_CHARACTER"
    end

    local chestY = getTerrainY(chest.x, chest.z)
    local chestPos = Vector3.new(chest.x, chestY, chest.z)
    local dist = (root.Position - chestPos).Magnitude
    if dist > TreasureChestData.CollectRange then
        return false, nil, "TOO_FAR"
    end

    -- Roll loot
    local loot = TreasureChestData.RollLoot(chestId)
    if not loot then
        return false, nil, "ROLL_FAILED"
    end

    -- Set cooldown
    _cooldowns[userId][chestId] = os.time() + TreasureChestData.RollCooldown()

    self.ChestCollected:Fire(player, chestId, loot)

    return true, loot, nil
end

--[[
    Gets chests available to a player (not on cooldown).
    @param player Player
    @return {table}
]]
function TreasureChestService:GetAvailableChests(player: Player): {any}
    local userId = player.UserId
    local playerCooldowns = _cooldowns[userId] or {}
    local now = os.time()
    local available = {}

    for _, chest in TreasureChestData.GetAllChests() do
        local cooldownEnd = playerCooldowns[chest.id] or 0
        local isAvailable = now >= cooldownEnd
        table.insert(available, {
            id = chest.id,
            zone = chest.zone,
            x = chest.x,
            z = chest.z,
            available = isAvailable,
            cooldownRemaining = if isAvailable then 0 else cooldownEnd - now,
        })
    end

    return available
end

--[[
    Cleans up player cooldown data.
]]
function TreasureChestService:CleanupPlayer(userId: number)
    _cooldowns[userId] = nil
end

return TreasureChestService
