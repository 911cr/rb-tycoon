--!strict
--[[
    LootCarryService.lua

    Manages the loot carrying system for overworld gameplay.

    After ANY overworld combat (bandits, PvP, bosses, chests), loot is NOT
    instantly added to resources. Players carry it physically and must return
    to their base gate to "bank" it.

    Features:
    - Session-only carried loot (NOT persisted to DataStore)
    - Visual cart model attached to player (size scales with loot value)
    - Auto-banking when player walks within 12 studs of own base gate
    - Teleport blocking while carrying loot
    - Loot drops on disconnect (collectible by others for 5 minutes)

    Loot is stored server-side in _carriedLoot table.
    Other players can see the cart but NOT the exact value.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local LootCarryService = {}
LootCarryService.__index = LootCarryService

-- ============================================================================
-- SIGNALS
-- ============================================================================

LootCarryService.LootAdded = Signal.new()      -- (player, lootTable)
LootCarryService.LootBanked = Signal.new()      -- (player, lootTable)
LootCarryService.LootDropped = Signal.new()     -- (position, lootTable, dropId)
LootCarryService.LootCollected = Signal.new()   -- (player, lootTable, dropId)

-- ============================================================================
-- TYPES
-- ============================================================================

export type LootTable = {
    gold: number,
    wood: number,
    food: number,
    gems: number,
}

export type DroppedLoot = {
    id: string,
    position: Vector3,
    loot: LootTable,
    expiresAt: number,
    model: Model?,
}

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

-- Session-only carried loot (NOT persisted)
local _carriedLoot: {[number]: LootTable} = {}

-- Visual cart models attached to players
local _cartModels: {[number]: Model} = {}

-- Dropped loot on the ground (from disconnects/deaths)
local _droppedLoot: {[string]: DroppedLoot} = {}

-- Counter for drop IDs
local _dropCounter = 0

-- Config shortcuts
local SMALL_THRESHOLD = OverworldConfig.Wilderness.LootCarry.SmallCartThreshold
local MEDIUM_THRESHOLD = OverworldConfig.Wilderness.LootCarry.MediumCartThreshold
local LARGE_THRESHOLD = OverworldConfig.Wilderness.LootCarry.LargeCartThreshold
local DROP_LIFETIME = OverworldConfig.Wilderness.LootCarry.DropLifetime
local DROP_COLLECT_RANGE = OverworldConfig.Wilderness.LootCarry.DropCollectRange

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

--[[
    Calculates the total value of a loot table for cart sizing.
    Gold=1, Wood=1, Food=1, Gems=100.
]]
local function getLootValue(loot: LootTable): number
    return loot.gold + loot.wood + loot.food + loot.gems * 100
end

--[[
    Determines cart size category based on loot value.
]]
local function getCartSize(loot: LootTable): string
    local value = getLootValue(loot)
    if value >= LARGE_THRESHOLD then return "large" end
    if value >= MEDIUM_THRESHOLD then return "medium" end
    if value >= SMALL_THRESHOLD then return "small" end
    return "none"
end

--[[
    Creates or updates the visual cart model attached to a player.
    Cart is a simple Part welded to HumanoidRootPart.
]]
local function updateCartVisual(player: Player)
    local userId = player.UserId
    local loot = _carriedLoot[userId]

    -- Remove existing cart
    local existingCart = _cartModels[userId]
    if existingCart then
        existingCart:Destroy()
        _cartModels[userId] = nil
    end

    -- No loot = no cart
    if not loot then return end

    local size = getCartSize(loot)
    if size == "none" then return end

    -- Need character
    local character = player.Character
    if not character then return end
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    -- Create cart model
    local cart = Instance.new("Model")
    cart.Name = "LootCart"

    -- Cart body (wooden box)
    local body = Instance.new("Part")
    body.Name = "CartBody"
    body.Anchored = false
    body.CanCollide = false
    body.Material = Enum.Material.WoodPlanks
    body.Color = Color3.fromRGB(139, 90, 43)

    if size == "small" then
        body.Size = Vector3.new(2, 1.5, 2)
    elseif size == "medium" then
        body.Size = Vector3.new(3, 2, 3)
    else -- large
        body.Size = Vector3.new(4, 2.5, 4)
    end

    body.Parent = cart

    -- Weld to player (behind them)
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = root
    weld.Part1 = body
    weld.Parent = body

    body.CFrame = root.CFrame * CFrame.new(0, -1, 3) -- Behind and below

    -- Gold sparkle on top for medium/large
    if size == "medium" or size == "large" then
        local sparkle = Instance.new("Part")
        sparkle.Name = "GoldTop"
        sparkle.Anchored = false
        sparkle.CanCollide = false
        sparkle.Material = Enum.Material.Foil
        sparkle.Color = Color3.fromRGB(255, 200, 50)
        sparkle.Size = Vector3.new(body.Size.X * 0.8, 0.3, body.Size.Z * 0.8)
        sparkle.Parent = cart

        local sparkleWeld = Instance.new("WeldConstraint")
        sparkleWeld.Part0 = body
        sparkleWeld.Part1 = sparkle
        sparkleWeld.Parent = sparkle

        sparkle.CFrame = body.CFrame * CFrame.new(0, body.Size.Y / 2 + 0.15, 0)
    end

    cart.PrimaryPart = body
    cart.Parent = workspace

    _cartModels[userId] = cart
end

--[[
    Creates a visual model for dropped loot on the ground.
]]
local function createDropModel(position: Vector3, size: string): Model
    local model = Instance.new("Model")
    model.Name = "DroppedLoot"

    local body = Instance.new("Part")
    body.Name = "Chest"
    body.Anchored = true
    body.CanCollide = false
    body.Material = Enum.Material.WoodPlanks
    body.Color = Color3.fromRGB(139, 90, 43)

    if size == "small" then
        body.Size = Vector3.new(2, 1.5, 1.5)
    elseif size == "medium" then
        body.Size = Vector3.new(3, 2, 2)
    else
        body.Size = Vector3.new(4, 2.5, 2.5)
    end

    body.Position = position + Vector3.new(0, body.Size.Y / 2, 0)
    body.Parent = model

    -- Gold accent
    local lid = Instance.new("Part")
    lid.Name = "Lid"
    lid.Anchored = true
    lid.CanCollide = false
    lid.Material = Enum.Material.Metal
    lid.Color = Color3.fromRGB(255, 200, 50)
    lid.Size = Vector3.new(body.Size.X, 0.3, body.Size.Z)
    lid.Position = body.Position + Vector3.new(0, body.Size.Y / 2 + 0.15, 0)
    lid.Parent = model

    -- Sparkle effect
    local sparkles = Instance.new("Sparkles")
    sparkles.SparkleColor = Color3.fromRGB(255, 215, 0)
    sparkles.Parent = lid

    -- Billboard indicator
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "LootLabel"
    billboard.Size = UDim2.new(0, 100, 0, 30)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 40
    billboard.Parent = body

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "Dropped Loot"
    label.TextColor3 = Color3.fromRGB(255, 215, 0)
    label.TextStrokeTransparency = 0.5
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    model.PrimaryPart = body
    model.Parent = workspace

    return model
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Gets the carried loot for a player.

    @param player Player
    @return LootTable? - Current carried loot or nil
]]
function LootCarryService:GetCarriedLoot(player: Player): LootTable?
    return _carriedLoot[player.UserId]
end

--[[
    Checks if a player is carrying any loot.

    @param player Player
    @return boolean
]]
function LootCarryService:IsCarryingLoot(player: Player): boolean
    local loot = _carriedLoot[player.UserId]
    if not loot then return false end
    return getLootValue(loot) > 0
end

--[[
    Checks if a player can teleport (not carrying loot).

    @param player Player
    @return boolean, string? - (canTeleport, errorReason)
]]
function LootCarryService:CanTeleport(player: Player): (boolean, string?)
    if self:IsCarryingLoot(player) then
        return false, "CARRYING_LOOT"
    end
    return true, nil
end

--[[
    Adds loot to a player's carried amount.
    Does NOT add to resources directly — player must bank at base.

    @param player Player
    @param loot LootTable - Loot to add
]]
function LootCarryService:AddLoot(player: Player, loot: LootTable)
    local userId = player.UserId
    local current = _carriedLoot[userId]

    if current then
        current.gold += loot.gold
        current.wood += loot.wood
        current.food += loot.food
        current.gems += loot.gems
    else
        _carriedLoot[userId] = {
            gold = loot.gold,
            wood = loot.wood,
            food = loot.food,
            gems = loot.gems,
        }
    end

    updateCartVisual(player)
    self.LootAdded:Fire(player, _carriedLoot[userId])
end

--[[
    Steals all carried loot from a player (PvP).
    Returns the stolen loot and clears the victim's carry.

    @param player Player - The victim
    @return LootTable? - The stolen loot, or nil if none
]]
function LootCarryService:StealAllLoot(player: Player): LootTable?
    local userId = player.UserId
    local loot = _carriedLoot[userId]
    if not loot or getLootValue(loot) <= 0 then
        return nil
    end

    local stolen: LootTable = {
        gold = loot.gold,
        wood = loot.wood,
        food = loot.food,
        gems = loot.gems,
    }

    _carriedLoot[userId] = nil
    updateCartVisual(player)

    return stolen
end

--[[
    Banks carried loot — transfers to DataService resources.
    Called when player walks within banking distance of own base.

    @param player Player
    @param dataService any - DataService reference for resource updates
    @return LootTable? - The banked loot, or nil if nothing to bank
]]
function LootCarryService:BankLoot(player: Player, dataService: any): LootTable?
    local userId = player.UserId
    local loot = _carriedLoot[userId]
    if not loot or getLootValue(loot) <= 0 then
        return nil
    end

    -- Transfer to player resources via DataService
    local playerData = dataService:GetPlayerData(player)
    if not playerData then
        warn("[LootCarryService] Cannot bank — no player data for", player.Name)
        return nil
    end

    -- Add resources
    if loot.gold > 0 then
        playerData.gold = (playerData.gold or 0) + loot.gold
    end
    if loot.wood > 0 then
        playerData.wood = (playerData.wood or 0) + loot.wood
    end
    if loot.food > 0 then
        playerData.food = (playerData.food or 0) + loot.food
    end
    if loot.gems > 0 then
        playerData.gems = (playerData.gems or 0) + loot.gems
    end

    local banked: LootTable = {
        gold = loot.gold,
        wood = loot.wood,
        food = loot.food,
        gems = loot.gems,
    }

    -- Clear carried loot
    _carriedLoot[userId] = nil
    updateCartVisual(player)

    self.LootBanked:Fire(player, banked)

    return banked
end

--[[
    Drops loot on the ground (called on disconnect or death).
    Creates a temporary world node collectible by other players.

    @param player Player
    @return DroppedLoot? - The drop info, or nil if no loot
]]
function LootCarryService:DropLoot(player: Player): DroppedLoot?
    local userId = player.UserId
    local loot = _carriedLoot[userId]
    if not loot or getLootValue(loot) <= 0 then
        -- Clean up cart visual
        if _cartModels[userId] then
            _cartModels[userId]:Destroy()
            _cartModels[userId] = nil
        end
        _carriedLoot[userId] = nil
        return nil
    end

    -- Get last known position
    local position = Vector3.new(1000, 0, 1000) -- fallback to center
    local character = player.Character
    if character then
        local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if root then
            position = root.Position
        end
    end

    -- Create drop
    _dropCounter += 1
    local dropId = "drop_" .. tostring(_dropCounter)
    local size = getCartSize(loot)

    local drop: DroppedLoot = {
        id = dropId,
        position = position,
        loot = {
            gold = loot.gold,
            wood = loot.wood,
            food = loot.food,
            gems = loot.gems,
        },
        expiresAt = os.time() + DROP_LIFETIME,
        model = createDropModel(position, if size == "none" then "small" else size),
    }

    _droppedLoot[dropId] = drop

    -- Clean up carried state
    _carriedLoot[userId] = nil
    if _cartModels[userId] then
        _cartModels[userId]:Destroy()
        _cartModels[userId] = nil
    end

    self.LootDropped:Fire(position, drop.loot, dropId)

    return drop
end

--[[
    Attempts to collect a dropped loot pile.
    Validates proximity and transfers to carried loot.

    @param player Player
    @param dropId string - The drop ID to collect
    @return boolean, string? - (success, errorReason)
]]
function LootCarryService:CollectDrop(player: Player, dropId: string): (boolean, string?)
    local drop = _droppedLoot[dropId]
    if not drop then
        return false, "DROP_NOT_FOUND"
    end

    -- Check expiry
    if os.time() > drop.expiresAt then
        self:_removeDrop(dropId)
        return false, "DROP_EXPIRED"
    end

    -- Check proximity
    local character = player.Character
    if not character then
        return false, "NO_CHARACTER"
    end

    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then
        return false, "NO_CHARACTER"
    end

    local dist = (root.Position - drop.position).Magnitude
    if dist > DROP_COLLECT_RANGE then
        return false, "TOO_FAR"
    end

    -- Add to carried loot
    self:AddLoot(player, drop.loot)

    -- Remove drop
    self:_removeDrop(dropId)

    self.LootCollected:Fire(player, drop.loot, dropId)

    return true, nil
end

--[[
    Removes an expired or collected drop.
]]
function LootCarryService:_removeDrop(dropId: string)
    local drop = _droppedLoot[dropId]
    if not drop then return end

    if drop.model then
        drop.model:Destroy()
    end

    _droppedLoot[dropId] = nil
end

--[[
    Cleans up expired drops. Should be called periodically.
]]
function LootCarryService:CleanupExpiredDrops()
    local now = os.time()
    local toRemove = {}

    for dropId, drop in _droppedLoot do
        if now > drop.expiresAt then
            table.insert(toRemove, dropId)
        end
    end

    for _, dropId in toRemove do
        self:_removeDrop(dropId)
    end
end

--[[
    Gets all active drops (for client sync).

    @return {DroppedLoot}
]]
function LootCarryService:GetAllDrops(): {DroppedLoot}
    local drops = {}
    for _, drop in _droppedLoot do
        table.insert(drops, drop)
    end
    return drops
end

--[[
    Cleans up all state for a leaving player.

    @param player Player
]]
function LootCarryService:CleanupPlayer(player: Player)
    local userId = player.UserId

    -- Drop loot on the ground if they have any
    if _carriedLoot[userId] and getLootValue(_carriedLoot[userId]) > 0 then
        self:DropLoot(player)
    else
        -- Just clean up
        _carriedLoot[userId] = nil
        if _cartModels[userId] then
            _cartModels[userId]:Destroy()
            _cartModels[userId] = nil
        end
    end
end

--[[
    Refreshes cart visual after character respawn.

    @param player Player
]]
function LootCarryService:RefreshCartVisual(player: Player)
    updateCartVisual(player)
end

return LootCarryService
