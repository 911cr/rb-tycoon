--!strict
--[[
    MerchantService.lua

    Manages wandering merchant NPCs in the overworld.
    2 merchants active at a time, each walking between waypoints.
    Inventory rotates every 30 minutes.
    Buy resources at 1.2x rate, sell at 0.6x rate (gold as currency).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local MerchantData = require(ReplicatedStorage.Shared.Constants.MerchantData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local MerchantService = {}
MerchantService.__index = MerchantService

-- ============================================================================
-- SIGNALS
-- ============================================================================

MerchantService.InventoryRotated = Signal.new() -- (merchantId, newInventory)

-- ============================================================================
-- TYPES
-- ============================================================================

type MerchantState = {
    id: string,
    npc: Model?,
    currentWaypoint: number,
    inventory: {buy: {any}, sell: {any}},
    lastRotation: number,
}

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _merchants: {[string]: MerchantState} = {}
local _initialized = false
local _patrolConnection: RBXScriptConnection? = nil

local INTERACT_RANGE = OverworldConfig.Wilderness.Merchants.InteractRange
local ROTATION_INTERVAL = OverworldConfig.Wilderness.Merchants.InventoryRotation

-- Lazy-load DataService
local _dataService: any = nil
local function getDataService()
    if not _dataService then
        local module = ServerScriptService:FindFirstChild("Services")
            and ServerScriptService.Services:FindFirstChild("DataService")
        if module then
            local ok, svc = pcall(require, module)
            if ok then _dataService = svc end
        end
    end
    return _dataService
end

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

local function getTerrainY(x: number, z: number): number
    return OverworldConfig.GetTerrainHeight(x, z)
end

local function createMerchantNPC(merchantInfo: any): Model?
    local waypoint = merchantInfo.waypoints[1]
    local x, z = waypoint.x, waypoint.z
    local y = getTerrainY(x, z)

    local model = Instance.new("Model")
    model.Name = "Merchant_" .. merchantInfo.id

    -- Body
    local torso = Instance.new("Part")
    torso.Name = "HumanoidRootPart"
    torso.Size = Vector3.new(2, 2, 1)
    torso.Anchored = true
    torso.CanCollide = false
    torso.Material = Enum.Material.SmoothPlastic
    torso.Color = merchantInfo.appearance.bodyColor
    torso.CFrame = CFrame.new(x, y + 3, z)
    torso.Parent = model

    -- Head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Shape = Enum.PartType.Ball
    head.Size = Vector3.new(1.2, 1.2, 1.2)
    head.Anchored = true
    head.CanCollide = false
    head.Material = Enum.Material.SmoothPlastic
    head.Color = merchantInfo.appearance.headColor
    head.CFrame = CFrame.new(x, y + 4.6, z)
    head.Parent = model

    -- Hat
    local hat = Instance.new("Part")
    hat.Name = "Hat"
    hat.Size = Vector3.new(1.5, 0.6, 1.5)
    hat.Anchored = true
    hat.CanCollide = false
    hat.Material = Enum.Material.Fabric
    hat.Color = merchantInfo.appearance.hatColor
    hat.CFrame = CFrame.new(x, y + 5.4, z)
    hat.Parent = model

    -- Legs
    local legs = Instance.new("Part")
    legs.Name = "Legs"
    legs.Size = Vector3.new(2, 2, 1)
    legs.Anchored = true
    legs.CanCollide = false
    legs.Material = Enum.Material.SmoothPlastic
    legs.Color = merchantInfo.appearance.bodyColor
    legs.CFrame = CFrame.new(x, y + 1, z)
    legs.Parent = model

    -- Backpack visual
    local backpack = Instance.new("Part")
    backpack.Name = "Backpack"
    backpack.Size = Vector3.new(1.5, 2, 0.8)
    backpack.Anchored = true
    backpack.CanCollide = false
    backpack.Material = Enum.Material.WoodPlanks
    backpack.Color = Color3.fromRGB(139, 90, 43)
    backpack.CFrame = CFrame.new(x, y + 3, z + 1)
    backpack.Parent = model

    -- Humanoid
    local humanoid = Instance.new("Humanoid")
    humanoid.MaxHealth = 100
    humanoid.Health = 100
    humanoid.Parent = model

    -- Billboard
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 140, 0, 30)
    billboard.StudsOffset = Vector3.new(0, 4, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 40
    billboard.Parent = head

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 1, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = merchantInfo.name
    nameLabel.TextColor3 = Color3.fromRGB(50, 200, 50)
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    model.PrimaryPart = torso

    -- Parent
    local owFolder = workspace:FindFirstChild("Overworld")
    if not owFolder then
        owFolder = Instance.new("Folder")
        owFolder.Name = "Overworld"
        owFolder.Parent = workspace
    end
    local merchantFolder = owFolder:FindFirstChild("Merchants")
    if not merchantFolder then
        merchantFolder = Instance.new("Folder")
        merchantFolder.Name = "Merchants"
        merchantFolder.Parent = owFolder
    end

    model.Parent = merchantFolder
    return model
end

local function moveMerchantTo(state: MerchantState, x: number, z: number)
    if not state.npc then return end
    local y = getTerrainY(x, z)

    local root = state.npc:FindFirstChild("HumanoidRootPart") :: BasePart?
    if root then root.CFrame = CFrame.new(x, y + 3, z) end
    local head = state.npc:FindFirstChild("Head") :: BasePart?
    if head then head.CFrame = CFrame.new(x, y + 4.6, z) end
    local hat = state.npc:FindFirstChild("Hat") :: BasePart?
    if hat then hat.CFrame = CFrame.new(x, y + 5.4, z) end
    local legs = state.npc:FindFirstChild("Legs") :: BasePart?
    if legs then legs.CFrame = CFrame.new(x, y + 1, z) end
    local backpack = state.npc:FindFirstChild("Backpack") :: BasePart?
    if backpack then backpack.CFrame = CFrame.new(x, y + 3, z + 1) end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function MerchantService:Init()
    if _initialized then return end
    _initialized = true

    for _, merchantInfo in MerchantData.Merchants do
        local state: MerchantState = {
            id = merchantInfo.id,
            npc = nil,
            currentWaypoint = 1,
            inventory = MerchantData.GenerateInventory(),
            lastRotation = os.time(),
        }
        _merchants[merchantInfo.id] = state

        task.defer(function()
            state.npc = createMerchantNPC(merchantInfo)
        end)
    end

    -- Patrol loop: move between waypoints
    local elapsed = 0
    _patrolConnection = RunService.Heartbeat:Connect(function(dt)
        elapsed += dt
        if elapsed < 8 then return end -- Move every 8 seconds
        elapsed = 0

        for merchantId, state in _merchants do
            local merchantInfo = MerchantData.GetMerchantById(merchantId)
            if not merchantInfo then continue end

            -- Advance to next waypoint
            state.currentWaypoint += 1
            if state.currentWaypoint > #merchantInfo.waypoints then
                state.currentWaypoint = 1
            end

            local wp = merchantInfo.waypoints[state.currentWaypoint]
            moveMerchantTo(state, wp.x, wp.z)
        end
    end)

    -- Inventory rotation loop
    task.spawn(function()
        while true do
            task.wait(60) -- Check every minute

            local now = os.time()
            for merchantId, state in _merchants do
                if now - state.lastRotation >= ROTATION_INTERVAL then
                    state.inventory = MerchantData.GenerateInventory()
                    state.lastRotation = now
                    self.InventoryRotated:Fire(merchantId, state.inventory)
                end
            end
        end
    end)

    print(string.format("[MerchantService] Initialized %d merchants", #MerchantData.Merchants))
end

--[[
    Gets merchant inventory for client display.
    @param merchantId string
    @return {buy: {any}, sell: {any}}?
]]
function MerchantService:GetInventory(merchantId: string): any?
    local state = _merchants[merchantId]
    if not state then return nil end
    return state.inventory
end

--[[
    Processes a buy or sell transaction.
    @param player Player
    @param merchantId string
    @param action "buy" | "sell"
    @param itemId string
    @param quantity number?
    @return boolean, string?
]]
function MerchantService:ProcessTransaction(
    player: Player,
    merchantId: string,
    action: string,
    itemId: string,
    quantity: any
): (boolean, string?)
    local state = _merchants[merchantId]
    if not state then return false, "MERCHANT_NOT_FOUND" end

    -- Proximity check
    local character = player.Character
    if not character then return false, "NO_CHARACTER" end
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return false, "NO_CHARACTER" end

    if state.npc then
        local merchantRoot = state.npc:FindFirstChild("HumanoidRootPart") :: BasePart?
        if merchantRoot then
            local dist = (root.Position - merchantRoot.Position).Magnitude
            if dist > INTERACT_RANGE then
                return false, "TOO_FAR"
            end
        end
    end

    local ds = getDataService()
    if not ds then return false, "SERVICE_UNAVAILABLE" end

    local playerData = ds:GetPlayerData(player)
    if not playerData then return false, "NO_PLAYER_DATA" end

    local qty = math.max(1, math.floor(tonumber(quantity) or 1))

    if action == "buy" then
        local item = MerchantData.GetBuyItem(itemId)
        if not item then return false, "ITEM_NOT_FOUND" end

        local totalCost = item.baseGoldCost * qty
        if (playerData.gold or 0) < totalCost then
            return false, "INSUFFICIENT_GOLD"
        end

        playerData.gold = (playerData.gold or 0) - totalCost
        local resource = item.resource
        playerData[resource] = (playerData[resource] or 0) + item.amount * qty

        return true, nil

    elseif action == "sell" then
        local item = MerchantData.GetSellItem(itemId)
        if not item then return false, "ITEM_NOT_FOUND" end

        local resource = item.resource
        local totalResource = item.amount * qty
        if (playerData[resource] or 0) < totalResource then
            return false, "INSUFFICIENT_RESOURCES"
        end

        playerData[resource] = (playerData[resource] or 0) - totalResource
        playerData.gold = (playerData.gold or 0) + item.goldReturn * qty

        return true, nil
    end

    return false, "INVALID_ACTION"
end

function MerchantService:Destroy()
    if _patrolConnection then
        _patrolConnection:Disconnect()
        _patrolConnection = nil
    end
    for _, state in _merchants do
        if state.npc then state.npc:Destroy() end
    end
    _merchants = {}
    _initialized = false
end

return MerchantService
