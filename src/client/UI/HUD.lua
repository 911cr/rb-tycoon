--!strict
--[[
    HUD.lua

    Main heads-up display showing resources, builders, and navigation.
    Always visible during gameplay (except during battles).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

--[[
    Formats a number for display.
]]
local function formatNumber(value: number): string
    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fK", value / 1000)
    else
        return tostring(math.floor(value))
    end
end

local HUD = {}
HUD.__index = HUD

-- Events
HUD.BuildMenuRequested = Signal.new()
HUD.AttackRequested = Signal.new()
HUD.ShopRequested = Signal.new()
HUD.QuestsRequested = Signal.new()
HUD.LeaderboardRequested = Signal.new()
HUD.ProfileRequested = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _resourceDisplays: {[string]: Frame} = {}
local _builderDisplay: Frame
local _initialized = false

-- Cache UI references
local _goldLabel: TextLabel
local _woodLabel: TextLabel
local _foodLabel: TextLabel
local _foodProductionLabel: TextLabel
local _foodUsageLabel: TextLabel
local _buildersLabel: TextLabel
local _trophyLabel: TextLabel
local _troopsLabel: TextLabel
local _troopsDisplay: Frame

--[[
    Creates the resource bar at the top of the screen.
    Positioned to avoid Roblox's menu button (top-left) and chat icon.
]]
local function createResourceBar(parent: ScreenGui): Frame
    -- Create a container that's positioned after the Roblox UI elements
    -- Roblox menu button is ~48px, chat is ~48px, plus some padding
    local bar = Components.CreateFrame({
        Name = "ResourceBar",
        Size = UDim2.new(0, 380, 0, 46),  -- Smaller now without gems
        Position = UDim2.new(0.5, 0, 0, 8),  -- Centered at top with padding
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.Background,
        BackgroundTransparency = 0.2,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- Add border for visibility
    local stroke = Instance.new("UIStroke")
    stroke.Color = Components.Colors.GoldDark
    stroke.Thickness = 2
    stroke.Parent = bar

    -- Add gradient for polish
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.85, 0.85, 0.85)),
    })
    gradient.Parent = bar

    -- Resource container (centered)
    local resourceContainer = Components.CreateFrame({
        Name = "Resources",
        Size = UDim2.new(1, -16, 1, -8),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Parent = bar,
    })

    local listLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 12),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = resourceContainer,
    })

    -- Gold display
    local goldDisplay = Components.CreateResourceDisplay({
        Name = "GoldDisplay",
        ResourceType = "Gold",
        Size = UDim2.new(0, 105, 0, 34),
        Parent = resourceContainer,
    })
    _goldLabel = goldDisplay:FindFirstChild("Amount", true) :: TextLabel
    _resourceDisplays["Gold"] = goldDisplay

    -- Wood display
    local woodDisplay = Components.CreateResourceDisplay({
        Name = "WoodDisplay",
        ResourceType = "Wood",
        Size = UDim2.new(0, 105, 0, 34),
        Parent = resourceContainer,
    })
    _woodLabel = woodDisplay:FindFirstChild("Amount", true) :: TextLabel
    _resourceDisplays["Wood"] = woodDisplay

    -- Food supply display (production/usage)
    local foodSupplyDisplay = Components.CreateFrame({
        Name = "FoodSupplyDisplay",
        Size = UDim2.new(0, 140, 0, 34),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = resourceContainer,
    })

    -- Food icon
    local foodIcon = Instance.new("ImageLabel")
    foodIcon.Name = "FoodIcon"
    foodIcon.Size = UDim2.new(0, 24, 0, 24)
    foodIcon.Position = UDim2.new(0, 4, 0.5, 0)
    foodIcon.AnchorPoint = Vector2.new(0, 0.5)
    foodIcon.BackgroundTransparency = 1
    foodIcon.Image = "rbxassetid://6031094678" -- Turkey/meat icon (matches resource display)
    foodIcon.ImageColor3 = Components.Colors.Food or Color3.fromRGB(255, 100, 100)
    foodIcon.ScaleType = Enum.ScaleType.Fit
    foodIcon.Parent = foodSupplyDisplay

    -- Production label (green)
    _foodProductionLabel = Components.CreateLabel({
        Name = "Production",
        Text = "+0/m",
        Size = UDim2.new(0, 50, 1, 0),
        Position = UDim2.new(0, 30, 0, 0),
        TextColor = Color3.fromRGB(100, 200, 100),
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = foodSupplyDisplay,
    })

    -- Usage label (yellow/red when over)
    _foodUsageLabel = Components.CreateLabel({
        Name = "Usage",
        Text = "-0/m",
        Size = UDim2.new(0, 50, 1, 0),
        Position = UDim2.new(0, 85, 0, 0),
        TextColor = Color3.fromRGB(200, 200, 100),
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = foodSupplyDisplay,
    })

    _resourceDisplays["FoodSupply"] = foodSupplyDisplay

    return bar
end

--[[
    Creates the builder status display (clickable to open profile).
    Positioned on the left side, below the Roblox menu area.
]]
local function createBuilderDisplay(parent: ScreenGui): Frame
    -- Use a button as the container for click detection
    local container = Instance.new("TextButton")
    container.Name = "BuilderDisplay"
    container.Size = UDim2.new(0, 100, 0, 36)
    container.Position = UDim2.new(0, 8, 0, 62)  -- Below Roblox menu button area
    container.BackgroundColor3 = Components.Colors.BackgroundLight
    container.BorderSizePixel = 0
    container.Text = ""
    container.AutoButtonColor = true
    container.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = Components.Sizes.CornerRadius
    corner.Parent = container

    local stroke = Instance.new("UIStroke")
    stroke.Color = Components.Colors.Secondary
    stroke.Thickness = 2
    stroke.Parent = container

    -- Click handler
    container.MouseButton1Click:Connect(function()
        HUD.ProfileRequested:Fire()
    end)

    -- Builder icon background
    local iconBg = Components.CreateFrame({
        Name = "IconBg",
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(0, 4, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = Components.Colors.Secondary,
        CornerRadius = UDim.new(0.5, 0),
        Parent = container,
    })

    -- Builder icon (hammer image)
    local iconImage = Instance.new("ImageLabel")
    iconImage.Name = "IconImage"
    iconImage.Size = UDim2.new(0, 20, 0, 20)
    iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
    iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
    iconImage.BackgroundTransparency = 1
    iconImage.Image = "rbxassetid://6035053746"  -- Hammer/tool icon
    iconImage.ImageColor3 = Color3.new(1, 1, 1)
    iconImage.ScaleType = Enum.ScaleType.Fit
    iconImage.Parent = iconBg

    -- Builder count
    _buildersLabel = Components.CreateLabel({
        Name = "Count",
        Text = "0/1",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 36, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        Parent = container,
    })

    return container :: any
end

--[[
    Creates the trophy display (clickable to open leaderboard).
    Positioned next to builder display.
]]
local function createTrophyDisplay(parent: ScreenGui): Frame
    -- Use a button as the container for click detection
    local container = Instance.new("TextButton")
    container.Name = "TrophyDisplay"
    container.Size = UDim2.new(0, 90, 0, 36)
    container.Position = UDim2.new(0, 116, 0, 62)  -- Next to builder display
    container.BackgroundColor3 = Components.Colors.BackgroundLight
    container.BorderSizePixel = 0
    container.Text = ""
    container.AutoButtonColor = true
    container.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = Components.Sizes.CornerRadius
    corner.Parent = container

    local stroke = Instance.new("UIStroke")
    stroke.Color = Components.Colors.Warning
    stroke.Thickness = 2
    stroke.Parent = container

    -- Click handler
    container.MouseButton1Click:Connect(function()
        HUD.LeaderboardRequested:Fire()
    end)

    -- Trophy icon background
    local iconBg = Components.CreateFrame({
        Name = "IconBg",
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(0, 4, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = Components.Colors.Warning,
        CornerRadius = UDim.new(0.5, 0),
        Parent = container,
    })

    -- Trophy icon (trophy/star image)
    local iconImage = Instance.new("ImageLabel")
    iconImage.Name = "IconImage"
    iconImage.Size = UDim2.new(0, 20, 0, 20)
    iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
    iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
    iconImage.BackgroundTransparency = 1
    iconImage.Image = "rbxassetid://6034767593"  -- Trophy/star icon
    iconImage.ImageColor3 = Color3.new(1, 1, 1)
    iconImage.ScaleType = Enum.ScaleType.Fit
    iconImage.Parent = iconBg

    -- Trophy count
    _trophyLabel = Components.CreateLabel({
        Name = "Count",
        Text = "0",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 36, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        Parent = container,
    })

    return container :: any
end

--[[
    Creates the troop count display.
    Positioned next to trophy display.
]]
local function createTroopDisplay(parent: ScreenGui): Frame
    local container = Instance.new("TextButton")
    container.Name = "TroopDisplay"
    container.Size = UDim2.new(0, 100, 0, 36)
    container.Position = UDim2.new(0, 214, 0, 62)  -- Next to trophy display
    container.BackgroundColor3 = Components.Colors.BackgroundLight
    container.BorderSizePixel = 0
    container.Text = ""
    container.AutoButtonColor = true
    container.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = Components.Sizes.CornerRadius
    corner.Parent = container

    local stroke = Instance.new("UIStroke")
    stroke.Color = Components.Colors.Danger or Color3.fromRGB(220, 80, 80)
    stroke.Thickness = 2
    stroke.Parent = container

    -- Click handler (could open troop menu in future)
    container.MouseButton1Click:Connect(function()
        -- Could open army/troop panel
        print("[HUD] Troop display clicked")
    end)

    -- Troop icon background
    local iconBg = Components.CreateFrame({
        Name = "IconBg",
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(0, 4, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = Components.Colors.Danger or Color3.fromRGB(220, 80, 80),
        CornerRadius = UDim.new(0.5, 0),
        Parent = container,
    })

    -- Troop icon (sword/soldier image)
    local iconImage = Instance.new("ImageLabel")
    iconImage.Name = "IconImage"
    iconImage.Size = UDim2.new(0, 20, 0, 20)
    iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
    iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
    iconImage.BackgroundTransparency = 1
    iconImage.Image = "rbxassetid://6034509993"  -- Sword/soldier icon
    iconImage.ImageColor3 = Color3.new(1, 1, 1)
    iconImage.ScaleType = Enum.ScaleType.Fit
    iconImage.Parent = iconBg

    -- Troop count (current/max)
    _troopsLabel = Components.CreateLabel({
        Name = "Count",
        Text = "0/25",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 36, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        Parent = container,
    })

    return container :: any
end

--[[
    Creates the bottom action bar with main buttons.
]]
local function createActionBar(parent: ScreenGui): Frame
    local bar = Components.CreateFrame({
        Name = "ActionBar",
        Size = UDim2.new(1, 0, 0, 80),
        Position = UDim2.new(0, 0, 1, 0),
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor = Components.Colors.Background,
        BackgroundTransparency = 0.3,
        Parent = parent,
    })

    -- Add gradient
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = -90
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    gradient.Parent = bar

    -- Button container
    local buttonContainer = Components.CreateFrame({
        Name = "Buttons",
        Size = UDim2.new(1, -32, 0, 60),
        Position = UDim2.new(0.5, 0, 0, 10),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Parent = bar,
    })

    local listLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 16),
        Parent = buttonContainer,
    })

    -- Quests button
    local questsButton = Components.CreateButton({
        Name = "QuestsButton",
        Text = "Quests",
        Size = UDim2.new(0, 80, 0, 50),
        BackgroundColor = Components.Colors.Warning,
        OnClick = function()
            HUD.QuestsRequested:Fire()
        end,
        Parent = buttonContainer,
    })

    -- Shop button
    local shopButton = Components.CreateButton({
        Name = "ShopButton",
        Text = "Shop",
        Size = UDim2.new(0, 80, 0, 50),
        BackgroundColor = Components.Colors.Gems,
        OnClick = function()
            HUD.ShopRequested:Fire()
        end,
        Parent = buttonContainer,
    })

    -- Build button
    local buildButton = Components.CreateButton({
        Name = "BuildButton",
        Text = "Build",
        Size = UDim2.new(0, 100, 0, 50),
        BackgroundColor = Components.Colors.Secondary,
        OnClick = function()
            HUD.BuildMenuRequested:Fire()
        end,
        Parent = buttonContainer,
    })

    -- Attack button
    local attackButton = Components.CreateButton({
        Name = "AttackButton",
        Text = "Attack!",
        Size = UDim2.new(0, 100, 0, 50),
        BackgroundColor = Components.Colors.Danger,
        OnClick = function()
            HUD.AttackRequested:Fire()
        end,
        Parent = buttonContainer,
    })

    return bar
end

--[[
    Updates the resource displays with current values.
]]
function HUD:UpdateResources(resources: {gold: number, wood: number, food: number})
    if _goldLabel then
        _goldLabel.Text = formatNumber(resources.gold or 0)
    end
    if _woodLabel then
        _woodLabel.Text = formatNumber(resources.wood or 0)
    end
end

--[[
    Updates the food supply display with production and usage per minute.
]]
function HUD:UpdateFoodSupply(production: number, usage: number, isPaused: boolean)
    print(string.format("[HUD] UpdateFoodSupply: +%.1f/-%.1f paused=%s, labels exist: prod=%s usage=%s",
        production, usage, tostring(isPaused),
        tostring(_foodProductionLabel ~= nil), tostring(_foodUsageLabel ~= nil)))

    if _foodProductionLabel then
        _foodProductionLabel.Text = string.format("+%d/m", math.floor(production))
        _foodProductionLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
    end

    if _foodUsageLabel then
        _foodUsageLabel.Text = string.format("-%d/m", math.floor(usage))
        -- Color red if usage exceeds production (paused)
        if isPaused then
            _foodUsageLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        elseif usage > production * 0.8 then
            _foodUsageLabel.TextColor3 = Color3.fromRGB(255, 200, 100) -- Warning yellow
        else
            _foodUsageLabel.TextColor3 = Color3.fromRGB(200, 200, 100) -- Normal
        end
    end
end

--[[
    Updates the builder display.
]]
function HUD:UpdateBuilders(freeBuilders: number, maxBuilders: number)
    if _buildersLabel then
        _buildersLabel.Text = string.format("%d/%d", freeBuilders, maxBuilders)
    end
end

--[[
    Updates the trophy display.
]]
function HUD:UpdateTrophies(trophies: number)
    if _trophyLabel then
        _trophyLabel.Text = formatNumber(trophies)
    end
end

--[[
    Updates the troop count display.
]]
function HUD:UpdateTroops(currentTroops: number, maxTroops: number)
    if _troopsLabel then
        _troopsLabel.Text = string.format("%d/%d", currentTroops, maxTroops)

        -- Color code based on army size
        if currentTroops >= maxTroops then
            _troopsLabel.TextColor3 = Components.Colors.Danger or Color3.fromRGB(220, 80, 80)
        elseif currentTroops >= maxTroops * 0.8 then
            _troopsLabel.TextColor3 = Components.Colors.Warning or Color3.fromRGB(240, 180, 80)
        else
            _troopsLabel.TextColor3 = Components.Colors.TextPrimary
        end
    end
end

--[[
    Shows or hides the HUD.
]]
function HUD:SetVisible(visible: boolean)
    if _screenGui then
        _screenGui.Enabled = visible
    end
end

--[[
    Initializes the HUD.
]]
function HUD:Init()
    if _initialized then
        warn("HUD already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create main ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "HUD"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.IgnoreGuiInset = true
    _screenGui.Parent = playerGui

    -- Create UI elements
    createResourceBar(_screenGui)
    _builderDisplay = createBuilderDisplay(_screenGui)
    createTrophyDisplay(_screenGui)
    _troopsDisplay = createTroopDisplay(_screenGui)
    createActionBar(_screenGui)

    -- Listen for data updates
    local Events = ReplicatedStorage:WaitForChild("Events")
    Events.SyncPlayerData.OnClientEvent:Connect(function(data)
        if data.resources then
            self:UpdateResources(data.resources)
        end
        if data.builders then
            local freeBuilders = 0
            for _, builder in data.builders do
                if not builder.busy then
                    freeBuilders += 1
                end
            end
            self:UpdateBuilders(freeBuilders, #data.builders)
        end
        if data.trophies then
            self:UpdateTrophies(data.trophies.current or 0)
        end
        -- Troop count
        if data.troops ~= nil or data.armyCampCapacity ~= nil then
            local totalTroops = 0
            if data.troops then
                for _, count in data.troops do
                    totalTroops = totalTroops + count
                end
            end
            self:UpdateTroops(totalTroops, data.armyCampCapacity or 25)
        end
        -- Food supply system
        if data.foodProduction ~= nil or data.foodUsage ~= nil then
            self:UpdateFoodSupply(
                data.foodProduction or 0,
                data.foodUsage or 0,
                data.trainingPaused or false
            )
        end
    end)

    -- Listen for food supply updates (sent after farm/troop changes)
    local FoodSupplyUpdate = Events:WaitForChild("FoodSupplyUpdate", 10)
    if FoodSupplyUpdate then
        print("[HUD] FoodSupplyUpdate event found, connecting...")
        FoodSupplyUpdate.OnClientEvent:Connect(function(production, usage, isPaused)
            print(string.format("[HUD] FoodSupplyUpdate received: +%.1f/-%.1f paused=%s",
                production or 0, usage or 0, tostring(isPaused)))
            self:UpdateFoodSupply(production or 0, usage or 0, isPaused or false)
        end)
    else
        warn("[HUD] FoodSupplyUpdate event not found!")
    end

    -- Check if data already exists (in case we initialized after server sent data)
    task.defer(function()
        task.wait(0.5) -- Brief wait for ClientAPI to be ready
        local existingData = ClientAPI.GetPlayerData()
        if existingData then
            if existingData.resources then
                self:UpdateResources(existingData.resources)
            end
            if existingData.builders then
                local freeBuilders = 0
                for _, builder in existingData.builders do
                    if not builder.busy then
                        freeBuilders += 1
                    end
                end
                self:UpdateBuilders(freeBuilders, #existingData.builders)
            end
            if existingData.trophies then
                self:UpdateTrophies(existingData.trophies.current or 0)
            end
            -- Troop count
            if existingData.troops ~= nil or existingData.armyCampCapacity ~= nil then
                local totalTroops = 0
                if existingData.troops then
                    for _, count in existingData.troops do
                        totalTroops = totalTroops + count
                    end
                end
                self:UpdateTroops(totalTroops, existingData.armyCampCapacity or 25)
            end
            -- Food supply system
            if existingData.foodProduction ~= nil or existingData.foodUsage ~= nil then
                self:UpdateFoodSupply(
                    existingData.foodProduction or 0,
                    existingData.foodUsage or 0,
                    existingData.trainingPaused or false
                )
            end
        else
            -- Request fresh data from server
            Events.SyncPlayerData:FireServer()
        end
    end)

    _initialized = true
    print("HUD initialized")
end

return HUD
