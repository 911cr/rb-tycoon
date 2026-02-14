--!strict
--[[
    init.client.lua - Overworld Client Entry Point

    Initializes all client controllers for the overworld experience.
    Handles camera setup, movement, and base interaction.
]]

print("========================================")
print("BATTLE TYCOON: CONQUEST - OVERWORLD CLIENT")
print("========================================")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Wait for shared modules
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Waiting for shared modules...")

repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Shared")

print("[CLIENT] Shared modules loaded")

-- Wait for events
repeat
    task.wait()
until ReplicatedStorage:FindFirstChild("Events")

print("[CLIENT] Events folder found")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Load modules and configuration
-- ═══════════════════════════════════════════════════════════════════════════════
local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Get services
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Get events
local Events = ReplicatedStorage:WaitForChild("Events")
local UpdatePosition = Events:WaitForChild("UpdatePosition") :: RemoteEvent
local GetNearbyBases = Events:WaitForChild("GetNearbyBases") :: RemoteFunction
local GetBaseData = Events:WaitForChild("GetBaseData") :: RemoteFunction
local GetOwnBaseData = Events:WaitForChild("GetOwnBaseData") :: RemoteFunction
local SpawnBase = Events:WaitForChild("SpawnBase") :: RemoteEvent
local RemoveBase = Events:WaitForChild("RemoveBase") :: RemoteEvent
local PositionSync = Events:WaitForChild("PositionSync") :: RemoteEvent
local ApproachBase = Events:WaitForChild("ApproachBase") :: RemoteEvent
local LeaveBase = Events:WaitForChild("LeaveBase") :: RemoteEvent
local BaseInteractionResult = Events:WaitForChild("BaseInteractionResult") :: RemoteEvent
local RequestTeleportToVillage = Events:WaitForChild("RequestTeleportToVillage") :: RemoteEvent
local RequestTeleportToBattle = Events:WaitForChild("RequestTeleportToBattle") :: RemoteEvent -- legacy
local RequestBattle = Events:WaitForChild("RequestBattle", 10) :: RemoteEvent? -- BattleArenaService
local TeleportStarted = Events:WaitForChild("TeleportStarted") :: RemoteEvent
local TeleportFailed = Events:WaitForChild("TeleportFailed") :: RemoteEvent
local ServerResponse = Events:WaitForChild("ServerResponse") :: RemoteEvent
local RequestRevenge = Events:WaitForChild("RequestRevenge", 10) :: RemoteEvent?

-- Goblin camp events
local AttackGoblinCamp = Events:WaitForChild("AttackGoblinCamp", 10) :: RemoteEvent?
local GetGoblinCamps = Events:WaitForChild("GetGoblinCamps", 10) :: RemoteFunction?

-- Resource node events
local CollectResourceNode = Events:WaitForChild("CollectResourceNode", 10) :: RemoteEvent?
local GetResourceNodes = Events:WaitForChild("GetResourceNodes", 10) :: RemoteFunction?

-- ═══════════════════════════════════════════════════════════════════════════════
-- Load controllers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Loading controllers...")

-- Controllers and UI are siblings in StarterPlayerScripts
local ControllersFolder = script.Parent:FindFirstChild("Controllers")

-- Load individual controllers
local OverworldController: any
local BaseInteractionController: any

local function loadController(name: string): any?
    if ControllersFolder then
        local module = ControllersFolder:FindFirstChild(name)
        if module then
            local success, result = pcall(function()
                return require(module)
            end)
            if success then
                print(string.format("[CLIENT] Loaded: %s", name))
                return result
            else
                warn(string.format("[CLIENT] Failed to load %s: %s", name, tostring(result)))
            end
        end
    end
    return nil
end

OverworldController = loadController("OverworldController")
BaseInteractionController = loadController("BaseInteractionController")

-- Load UI modules
local UIFolder = script.Parent:FindFirstChild("UI")

local BaseInfoUI: any
local OverworldHUD: any
local MatchmakingUI: any
local TradeUI: any

local function loadUI(name: string): any?
    if UIFolder then
        local module = UIFolder:FindFirstChild(name)
        if module then
            local success, result = pcall(function()
                return require(module)
            end)
            if success then
                print(string.format("[CLIENT] Loaded UI: %s", name))
                return result
            else
                warn(string.format("[CLIENT] Failed to load UI %s: %s", name, tostring(result)))
            end
        end
    end
    return nil
end

BaseInfoUI = loadUI("BaseInfoUI")
OverworldHUD = loadUI("OverworldHUD")
MatchmakingUI = loadUI("MatchmakingUI")
TradeUI = loadUI("TradeUI")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Initialize controllers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Initializing controllers...")

local function initController(controller: any, name: string)
    if controller and controller.Init then
        local success, err = pcall(function()
            controller:Init()
        end)
        if success then
            print(string.format("[CLIENT] Initialized: %s", name))
        else
            warn(string.format("[CLIENT] Failed to init %s: %s", name, tostring(err)))
        end
    end
end

initController(OverworldController, "OverworldController")
initController(BaseInteractionController, "BaseInteractionController")
initController(BaseInfoUI, "BaseInfoUI")
initController(OverworldHUD, "OverworldHUD")
initController(MatchmakingUI, "MatchmakingUI")
initController(TradeUI, "TradeUI")

-- Connect Go to City button
if OverworldHUD and OverworldHUD.GoToCityClicked then
    OverworldHUD.GoToCityClicked:Connect(function()
        print("[CLIENT] Go to City clicked - requesting teleport to village")
        RequestTeleportToVillage:FireServer()
    end)
end

-- Resource refresh loop (updates resource display and raid risk indicator)
if OverworldHUD and OverworldHUD.UpdateResources then
    local GetPlayerResources = Events:FindFirstChild("GetPlayerResources") :: RemoteFunction?
    if GetPlayerResources then
        -- Initial fetch
        task.spawn(function()
            task.wait(1)
            local success, resources = pcall(function()
                return GetPlayerResources:InvokeServer()
            end)
            if success and resources then
                OverworldHUD:UpdateResources(resources)
            end
        end)

        -- Periodic refresh every 10 seconds
        task.spawn(function()
            while true do
                task.wait(10)
                local success, resources = pcall(function()
                    return GetPlayerResources:InvokeServer()
                end)
                if success and resources then
                    OverworldHUD:UpdateResources(resources)
                end
            end
        end)
        print("[CLIENT] Resource refresh loop started")
    else
        warn("[CLIENT] GetPlayerResources RemoteFunction not found - resource display unavailable")
    end
end

-- Connect Enter Base button -> teleport to visit another player's village
if BaseInfoUI and BaseInfoUI.EnterBaseClicked then
    local RequestVisitBase = Events:FindFirstChild("RequestVisitBase") :: RemoteEvent?

    BaseInfoUI.EnterBaseClicked:Connect(function(baseData)
        if not baseData or not baseData.userId then return end
        if not RequestVisitBase then
            RequestVisitBase = Events:FindFirstChild("RequestVisitBase") :: RemoteEvent?
        end
        if RequestVisitBase then
            RequestVisitBase:FireServer({ targetUserId = baseData.userId })
            print(string.format("[CLIENT] Requesting visit to %s's village", baseData.username or "Unknown"))
        end
    end)
end

-- Connect Defense Log button -> show defense log popup
if OverworldHUD and OverworldHUD.DefenseLogClicked then
    -- Defense log popup state
    local _defenseLogGui: ScreenGui? = nil
    local _defenseLogVisible = false

    local function formatNumber(num: number): string
        local formatted = tostring(math.floor(num))
        local k
        while true do
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then break end
        end
        return formatted
    end

    local function formatTimeAgo(timestamp: number): string
        local now = os.time()
        local diff = now - timestamp
        if diff < 60 then return "Just now"
        elseif diff < 3600 then return math.floor(diff / 60) .. "m ago"
        elseif diff < 86400 then return math.floor(diff / 3600) .. "h ago"
        else return math.floor(diff / 86400) .. "d ago"
        end
    end

    local function showDefenseLog()
        if _defenseLogVisible and _defenseLogGui then
            _defenseLogGui.Enabled = false
            _defenseLogVisible = false
            return
        end

        -- Fetch defense log from server
        local GetDefenseLog = Events:FindFirstChild("GetDefenseLog") :: RemoteFunction?
        if not GetDefenseLog then
            if OverworldHUD and OverworldHUD.ShowError then
                OverworldHUD:ShowError("Defense log unavailable")
            end
            return
        end

        local logData = GetDefenseLog:InvokeServer()

        -- Create or reuse ScreenGui
        if not _defenseLogGui then
            _defenseLogGui = Instance.new("ScreenGui")
            _defenseLogGui.Name = "DefenseLogPopup"
            _defenseLogGui.ResetOnSpawn = false
            _defenseLogGui.DisplayOrder = 50
            _defenseLogGui.Parent = PlayerGui
        end

        -- Clear previous content
        for _, child in _defenseLogGui:GetChildren() do
            child:Destroy()
        end

        -- Dark overlay
        local overlay = Instance.new("Frame")
        overlay.Name = "Overlay"
        overlay.Size = UDim2.new(1, 0, 1, 0)
        overlay.BackgroundColor3 = Color3.new(0, 0, 0)
        overlay.BackgroundTransparency = 0.5
        overlay.Parent = _defenseLogGui

        -- Main panel
        local panel = Instance.new("Frame")
        panel.Name = "Panel"
        panel.Size = UDim2.new(0, 420, 0, 500)
        panel.Position = UDim2.new(0.5, 0, 0.5, 0)
        panel.AnchorPoint = Vector2.new(0.5, 0.5)
        panel.BackgroundColor3 = Color3.fromRGB(30, 25, 22)
        panel.BorderSizePixel = 0
        panel.Parent = _defenseLogGui

        local panelCorner = Instance.new("UICorner")
        panelCorner.CornerRadius = UDim.new(0, 12)
        panelCorner.Parent = panel

        local panelStroke = Instance.new("UIStroke")
        panelStroke.Color = Color3.fromRGB(160, 60, 60)
        panelStroke.Thickness = 2
        panelStroke.Parent = panel

        -- Header
        local header = Instance.new("TextLabel")
        header.Name = "Header"
        header.Size = UDim2.new(1, 0, 0, 50)
        header.Position = UDim2.new(0, 0, 0, 8)
        header.BackgroundTransparency = 1
        header.Text = "Defense Log"
        header.TextColor3 = Color3.fromRGB(240, 220, 180)
        header.TextSize = 24
        header.Font = Enum.Font.GothamBold
        header.Parent = panel

        -- Close button
        local closeButton = Instance.new("TextButton")
        closeButton.Name = "Close"
        closeButton.Size = UDim2.new(0, 36, 0, 36)
        closeButton.Position = UDim2.new(1, -12, 0, 12)
        closeButton.AnchorPoint = Vector2.new(1, 0)
        closeButton.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
        closeButton.Text = "X"
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeButton.TextSize = 18
        closeButton.Font = Enum.Font.GothamBold
        closeButton.BorderSizePixel = 0
        closeButton.Parent = panel

        local closeCorner = Instance.new("UICorner")
        closeCorner.CornerRadius = UDim.new(0, 6)
        closeCorner.Parent = closeButton

        closeButton.MouseButton1Click:Connect(function()
            _defenseLogGui.Enabled = false
            _defenseLogVisible = false
        end)

        -- Also close on overlay click
        local overlayButton = Instance.new("TextButton")
        overlayButton.Size = UDim2.new(1, 0, 1, 0)
        overlayButton.BackgroundTransparency = 1
        overlayButton.Text = ""
        overlayButton.Parent = overlay
        overlayButton.MouseButton1Click:Connect(function()
            _defenseLogGui.Enabled = false
            _defenseLogVisible = false
        end)

        -- Log scroll container
        local scrollFrame = Instance.new("ScrollingFrame")
        scrollFrame.Name = "LogScroll"
        scrollFrame.Size = UDim2.new(1, -24, 1, -80)
        scrollFrame.Position = UDim2.new(0, 12, 0, 68)
        scrollFrame.BackgroundColor3 = Color3.fromRGB(40, 35, 30)
        scrollFrame.BorderSizePixel = 0
        scrollFrame.ScrollBarThickness = 6
        scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(120, 80, 60)
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scrollFrame.Parent = panel

        local scrollCorner = Instance.new("UICorner")
        scrollCorner.CornerRadius = UDim.new(0, 8)
        scrollCorner.Parent = scrollFrame

        local listLayout = Instance.new("UIListLayout")
        listLayout.Padding = UDim.new(0, 6)
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        listLayout.Parent = scrollFrame

        local listPadding = Instance.new("UIPadding")
        listPadding.PaddingTop = UDim.new(0, 4)
        listPadding.PaddingLeft = UDim.new(0, 4)
        listPadding.PaddingRight = UDim.new(0, 4)
        listPadding.Parent = scrollFrame

        -- Populate entries
        if logData and #logData > 0 then
            -- Sort by timestamp descending
            local sorted = table.clone(logData)
            table.sort(sorted, function(a, b)
                return (a.timestamp or 0) > (b.timestamp or 0)
            end)

            for i, entry in sorted do
                -- Determine if revenge is available for this entry
                local canRevenge = entry.canRevenge and RequestRevenge ~= nil

                local entryFrame = Instance.new("Frame")
                entryFrame.Name = "Entry_" .. i
                entryFrame.Size = UDim2.new(1, -8, 0, canRevenge and 90 or 70)
                entryFrame.BackgroundColor3 = Color3.fromRGB(50, 45, 38)
                entryFrame.BorderSizePixel = 0
                entryFrame.LayoutOrder = i
                entryFrame.Parent = scrollFrame

                local entryCorner = Instance.new("UICorner")
                entryCorner.CornerRadius = UDim.new(0, 6)
                entryCorner.Parent = entryFrame

                -- Attacker name
                local nameLabel = Instance.new("TextLabel")
                nameLabel.Size = UDim2.new(0.5, 0, 0, 22)
                nameLabel.Position = UDim2.new(0, 12, 0, 6)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Text = entry.attackerName or "Unknown"
                nameLabel.TextColor3 = Color3.fromRGB(240, 220, 180)
                nameLabel.TextSize = 14
                nameLabel.Font = Enum.Font.GothamBold
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.Parent = entryFrame

                -- Time ago
                local timeLabel = Instance.new("TextLabel")
                timeLabel.Size = UDim2.new(0.5, -12, 0, 22)
                timeLabel.Position = UDim2.new(0.5, 0, 0, 6)
                timeLabel.BackgroundTransparency = 1
                timeLabel.Text = formatTimeAgo(entry.timestamp or 0)
                timeLabel.TextColor3 = Color3.fromRGB(150, 140, 120)
                timeLabel.TextSize = 12
                timeLabel.Font = Enum.Font.Gotham
                timeLabel.TextXAlignment = Enum.TextXAlignment.Right
                timeLabel.Parent = entryFrame

                -- Stars
                local stars = entry.stars or 0
                local starText = ""
                for s = 1, 3 do
                    starText = starText .. (s <= stars and "★" or "☆")
                end
                local starLabel = Instance.new("TextLabel")
                starLabel.Size = UDim2.new(0, 60, 0, 20)
                starLabel.Position = UDim2.new(0, 12, 0, 30)
                starLabel.BackgroundTransparency = 1
                starLabel.Text = starText
                starLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
                starLabel.TextSize = 14
                starLabel.Font = Enum.Font.GothamBold
                starLabel.TextXAlignment = Enum.TextXAlignment.Left
                starLabel.Parent = entryFrame

                -- Destruction
                local destLabel = Instance.new("TextLabel")
                destLabel.Size = UDim2.new(0, 60, 0, 20)
                destLabel.Position = UDim2.new(0, 80, 0, 30)
                destLabel.BackgroundTransparency = 1
                destLabel.Text = math.floor(entry.destruction or 0) .. "%"
                destLabel.TextColor3 = Color3.fromRGB(200, 80, 60)
                destLabel.TextSize = 12
                destLabel.Font = Enum.Font.Gotham
                destLabel.TextXAlignment = Enum.TextXAlignment.Left
                destLabel.Parent = entryFrame

                -- Loot stolen
                local lootLabel = Instance.new("TextLabel")
                lootLabel.Size = UDim2.new(0.5, -12, 0, 20)
                lootLabel.Position = UDim2.new(0, 12, 0, 48)
                lootLabel.BackgroundTransparency = 1
                lootLabel.Text = "-" .. formatNumber(entry.goldStolen or 0) .. " Gold"
                lootLabel.TextColor3 = Color3.fromRGB(200, 80, 60)
                lootLabel.TextSize = 12
                lootLabel.Font = Enum.Font.Gotham
                lootLabel.TextXAlignment = Enum.TextXAlignment.Left
                lootLabel.Parent = entryFrame

                -- Trophy change
                local trophyChange = entry.trophyChange or 0
                local trophyLabel = Instance.new("TextLabel")
                trophyLabel.Size = UDim2.new(0.5, -12, 0, 20)
                trophyLabel.Position = UDim2.new(0.5, 0, 0, 48)
                trophyLabel.BackgroundTransparency = 1
                trophyLabel.Text = (trophyChange >= 0 and "+" or "") .. trophyChange .. " Trophies"
                trophyLabel.TextColor3 = trophyChange >= 0 and Color3.fromRGB(80, 200, 80) or Color3.fromRGB(200, 80, 60)
                trophyLabel.TextSize = 12
                trophyLabel.Font = Enum.Font.Gotham
                trophyLabel.TextXAlignment = Enum.TextXAlignment.Right
                trophyLabel.Parent = entryFrame

                -- Revenge button (only if canRevenge is true and RequestRevenge event exists)
                if canRevenge then
                    local revengeButton = Instance.new("TextButton")
                    revengeButton.Name = "RevengeButton"
                    revengeButton.Size = UDim2.new(0, 80, 0, 26)
                    revengeButton.Position = UDim2.new(1, -12, 1, -6)
                    revengeButton.AnchorPoint = Vector2.new(1, 1)
                    revengeButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
                    revengeButton.Text = "Revenge"
                    revengeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
                    revengeButton.TextSize = 12
                    revengeButton.Font = Enum.Font.GothamBold
                    revengeButton.BorderSizePixel = 0
                    revengeButton.Parent = entryFrame

                    local revCorner = Instance.new("UICorner")
                    revCorner.CornerRadius = UDim.new(0, 4)
                    revCorner.Parent = revengeButton

                    local revStroke = Instance.new("UIStroke")
                    revStroke.Color = Color3.fromRGB(220, 60, 60)
                    revStroke.Thickness = 1
                    revStroke.Parent = revengeButton

                    revengeButton.MouseButton1Click:Connect(function()
                        -- Disable button immediately to prevent double-click
                        revengeButton.Active = false
                        revengeButton.Text = "Attacking..."
                        revengeButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)

                        -- Fire revenge request
                        if RequestRevenge then
                            RequestRevenge:FireServer({ targetUserId = entry.attackerId })
                        end

                        -- Close defense log popup after a brief delay
                        task.delay(1, function()
                            if _defenseLogGui then
                                _defenseLogGui.Enabled = false
                                _defenseLogVisible = false
                            end
                        end)
                    end)
                end
            end
        else
            local emptyLabel = Instance.new("TextLabel")
            emptyLabel.Size = UDim2.new(1, 0, 0, 60)
            emptyLabel.BackgroundTransparency = 1
            emptyLabel.Text = "No attacks on your base yet!"
            emptyLabel.TextColor3 = Color3.fromRGB(150, 140, 120)
            emptyLabel.TextSize = 16
            emptyLabel.Font = Enum.Font.Gotham
            emptyLabel.Parent = scrollFrame
        end

        _defenseLogGui.Enabled = true
        _defenseLogVisible = true
    end

    OverworldHUD.DefenseLogClicked:Connect(function()
        print("[CLIENT] Defense Log clicked")
        showDefenseLog()
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Shield timer HUD
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Setting up shield timer...")

do
    local RunService = game:GetService("RunService")
    local _shieldActive = false
    local _shieldExpiresAt = 0
    local _shieldUpdateConnection: RBXScriptConnection? = nil

    -- Fetch shield status from server
    local GetShieldStatus = Events:FindFirstChild("GetShieldStatus") :: RemoteFunction?
    if not GetShieldStatus then
        -- Wait briefly in case server hasn't created it yet
        task.delay(2, function()
            GetShieldStatus = Events:FindFirstChild("GetShieldStatus") :: RemoteFunction?
        end)
    end

    local function fetchAndUpdateShield()
        if not GetShieldStatus then
            GetShieldStatus = Events:FindFirstChild("GetShieldStatus") :: RemoteFunction?
        end
        if not GetShieldStatus then return end

        local success, shieldData = pcall(function()
            return GetShieldStatus:InvokeServer()
        end)

        if not success or not shieldData then
            _shieldActive = false
            if OverworldHUD and OverworldHUD.UpdateShield then
                OverworldHUD:UpdateShield({ active = false })
            end
            return
        end

        _shieldActive = shieldData.active == true
        _shieldExpiresAt = shieldData.expiresAt or 0

        if OverworldHUD and OverworldHUD.UpdateShield then
            OverworldHUD:UpdateShield(shieldData)
        end
    end

    -- Start countdown loop that updates every second
    local function startShieldCountdown()
        -- Disconnect any existing update loop
        if _shieldUpdateConnection then
            _shieldUpdateConnection:Disconnect()
            _shieldUpdateConnection = nil
        end

        local _lastUpdateTime = 0

        _shieldUpdateConnection = RunService.Heartbeat:Connect(function()
            if not _shieldActive then return end

            local now = os.clock()
            -- Only update once per second
            if now - _lastUpdateTime < 1 then return end
            _lastUpdateTime = now

            local remaining = math.max(0, _shieldExpiresAt - os.time())

            if remaining <= 0 then
                -- Shield expired
                _shieldActive = false
                if OverworldHUD and OverworldHUD.UpdateShield then
                    OverworldHUD:UpdateShield({ active = false })
                end
                return
            end

            -- Update the display with current remaining time
            if OverworldHUD and OverworldHUD.UpdateShield then
                OverworldHUD:UpdateShield({
                    active = true,
                    expiresAt = _shieldExpiresAt,
                    remainingSeconds = remaining,
                })
            end
        end)
    end

    -- Initial fetch after a brief delay to let server init
    task.spawn(function()
        task.wait(2)
        fetchAndUpdateShield()
        startShieldCountdown()
        print("[CLIENT] Shield timer initialized")
    end)

    -- Periodic re-fetch from server every 60 seconds to stay in sync
    task.spawn(function()
        while true do
            task.wait(60)
            fetchAndUpdateShield()
        end
    end)
end

-- Connect Find Battle button -> open MatchmakingUI
if OverworldHUD and OverworldHUD.FindBattleClicked then
    OverworldHUD.FindBattleClicked:Connect(function()
        print("[CLIENT] Find Battle clicked - opening matchmaking")
        if MatchmakingUI then
            if not MatchmakingUI:IsInitialized() then
                MatchmakingUI:Init()
            end
            if not MatchmakingUI:IsVisible() then
                MatchmakingUI:Show()
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Goblin camp overworld markers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Setting up goblin camp markers...")

do
    local _goblinMarkers: {[string]: Model} = {} -- [campId] = marker model
    local _goblinCampsFolder: Folder? = nil

    -- Difficulty color mapping
    local DIFFICULTY_COLORS = {
        Easy = Color3.fromRGB(60, 160, 60),     -- Green
        Medium = Color3.fromRGB(200, 160, 40),   -- Yellow/Gold
        Hard = Color3.fromRGB(200, 50, 50),      -- Red
    }

    -- Creates a 3D visual marker for a goblin camp in the overworld
    local function createCampMarker(camp: any)
        if _goblinMarkers[camp.id] then return end -- Already exists

        -- Ensure folder exists
        if not _goblinCampsFolder then
            _goblinCampsFolder = workspace:FindFirstChild("GoblinCamps") :: Folder?
            if not _goblinCampsFolder then
                local folder = Instance.new("Folder")
                folder.Name = "GoblinCamps"
                folder.Parent = workspace
                _goblinCampsFolder = folder
            end
        end

        local markerColor = DIFFICULTY_COLORS[camp.difficulty] or Color3.fromRGB(60, 160, 60)

        -- Create marker model
        local marker = Instance.new("Model")
        marker.Name = "GoblinCamp_" .. camp.id

        -- Base platform (circular feel using a part)
        local base = Instance.new("Part")
        base.Name = "Base"
        base.Size = Vector3.new(12, 1, 12)
        base.Position = Vector3.new(camp.position.X, camp.position.Y + 0.5, camp.position.Z)
        base.Anchored = true
        base.CanCollide = false
        base.Material = Enum.Material.Grass
        base.Color = Color3.fromRGB(50, 90, 30)
        base.Shape = Enum.PartType.Cylinder
        base.Orientation = Vector3.new(0, 0, 90)
        base.Parent = marker

        -- Goblin hut (main structure)
        local hut = Instance.new("Part")
        hut.Name = "Hut"
        hut.Size = Vector3.new(6, 5, 6)
        hut.Position = Vector3.new(camp.position.X, camp.position.Y + 3.5, camp.position.Z)
        hut.Anchored = true
        hut.CanCollide = false
        hut.Material = Enum.Material.WoodPlanks
        hut.Color = Color3.fromRGB(80, 55, 30)
        hut.Parent = marker

        -- Roof (cone-like using a wedge or colored part)
        local roof = Instance.new("Part")
        roof.Name = "Roof"
        roof.Size = Vector3.new(8, 3, 8)
        roof.Position = Vector3.new(camp.position.X, camp.position.Y + 7.5, camp.position.Z)
        roof.Anchored = true
        roof.CanCollide = false
        roof.Material = Enum.Material.Fabric
        roof.Color = markerColor
        roof.Shape = Enum.PartType.Ball
        roof.Parent = marker

        -- Difficulty flag pole
        local pole = Instance.new("Part")
        pole.Name = "FlagPole"
        pole.Size = Vector3.new(0.3, 8, 0.3)
        pole.Position = Vector3.new(camp.position.X + 3, camp.position.Y + 5, camp.position.Z + 3)
        pole.Anchored = true
        pole.CanCollide = false
        pole.Material = Enum.Material.Metal
        pole.Color = Color3.fromRGB(80, 80, 80)
        pole.Parent = marker

        -- Flag
        local flag = Instance.new("Part")
        flag.Name = "Flag"
        flag.Size = Vector3.new(3, 1.5, 0.1)
        flag.Position = Vector3.new(camp.position.X + 4.5, camp.position.Y + 8.5, camp.position.Z + 3)
        flag.Anchored = true
        flag.CanCollide = false
        flag.Material = Enum.Material.Fabric
        flag.Color = markerColor
        flag.Parent = marker

        -- BillboardGui with camp info + attack button
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "CampInfo"
        billboard.Size = UDim2.new(0, 200, 0, 120)
        billboard.StudsOffset = Vector3.new(0, 8, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 120
        billboard.Adornee = hut
        billboard.Parent = marker

        -- Background frame
        local bgFrame = Instance.new("Frame")
        bgFrame.Name = "Background"
        bgFrame.Size = UDim2.new(1, 0, 1, 0)
        bgFrame.BackgroundColor3 = Color3.fromRGB(25, 20, 18)
        bgFrame.BackgroundTransparency = 0.2
        bgFrame.BorderSizePixel = 0
        bgFrame.Parent = billboard

        local bgCorner = Instance.new("UICorner")
        bgCorner.CornerRadius = UDim.new(0, 8)
        bgCorner.Parent = bgFrame

        local bgStroke = Instance.new("UIStroke")
        bgStroke.Color = markerColor
        bgStroke.Thickness = 2
        bgStroke.Parent = bgFrame

        -- Camp name
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "CampName"
        nameLabel.Size = UDim2.new(1, -8, 0, 22)
        nameLabel.Position = UDim2.new(0, 4, 0, 4)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = camp.name
        nameLabel.TextColor3 = Color3.fromRGB(240, 220, 180)
        nameLabel.TextSize = 14
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Parent = bgFrame

        -- Difficulty badge
        local diffLabel = Instance.new("TextLabel")
        diffLabel.Name = "Difficulty"
        diffLabel.Size = UDim2.new(0.5, -4, 0, 18)
        diffLabel.Position = UDim2.new(0, 4, 0, 26)
        diffLabel.BackgroundTransparency = 1
        diffLabel.Text = camp.difficulty .. " (TH" .. camp.thEquivalent .. ")"
        diffLabel.TextColor3 = markerColor
        diffLabel.TextSize = 11
        diffLabel.Font = Enum.Font.GothamBold
        diffLabel.TextXAlignment = Enum.TextXAlignment.Left
        diffLabel.Parent = bgFrame

        -- Loot preview
        local lootText = ""
        if camp.loot then
            lootText = tostring(camp.loot.gold) .. "G / " ..
                       tostring(camp.loot.wood) .. "W / " ..
                       tostring(camp.loot.food) .. "F"
        end
        local lootLabel = Instance.new("TextLabel")
        lootLabel.Name = "LootPreview"
        lootLabel.Size = UDim2.new(1, -8, 0, 16)
        lootLabel.Position = UDim2.new(0, 4, 0, 46)
        lootLabel.BackgroundTransparency = 1
        lootLabel.Text = "Loot: " .. lootText
        lootLabel.TextColor3 = Color3.fromRGB(200, 180, 120)
        lootLabel.TextSize = 10
        lootLabel.Font = Enum.Font.Gotham
        lootLabel.TextXAlignment = Enum.TextXAlignment.Left
        lootLabel.Parent = bgFrame

        -- Attack button
        local attackButton = Instance.new("TextButton")
        attackButton.Name = "AttackButton"
        attackButton.Size = UDim2.new(0.8, 0, 0, 30)
        attackButton.Position = UDim2.new(0.1, 0, 0, 68)
        attackButton.BackgroundColor3 = Color3.fromRGB(180, 50, 30)
        attackButton.Text = "ATTACK"
        attackButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        attackButton.TextSize = 14
        attackButton.Font = Enum.Font.GothamBold
        attackButton.BorderSizePixel = 0
        attackButton.Parent = bgFrame

        local atkCorner = Instance.new("UICorner")
        atkCorner.CornerRadius = UDim.new(0, 6)
        atkCorner.Parent = attackButton

        local atkStroke = Instance.new("UIStroke")
        atkStroke.Color = Color3.fromRGB(220, 80, 50)
        atkStroke.Thickness = 1
        atkStroke.Parent = attackButton

        -- Attack button click handler
        attackButton.MouseButton1Click:Connect(function()
            if not AttackGoblinCamp then
                if OverworldHUD and OverworldHUD.ShowError then
                    OverworldHUD:ShowError("Goblin camps not available")
                end
                return
            end

            -- Disable button to prevent double-click
            attackButton.Active = false
            attackButton.Text = "Attacking..."
            attackButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)

            -- Fire attack request
            AttackGoblinCamp:FireServer(camp.id)

            -- Re-enable after a delay
            task.delay(3, function()
                if attackButton and attackButton.Parent then
                    attackButton.Active = true
                    attackButton.Text = "ATTACK"
                    attackButton.BackgroundColor3 = Color3.fromRGB(180, 50, 30)
                end
            end)
        end)

        marker.Parent = _goblinCampsFolder
        _goblinMarkers[camp.id] = marker
    end

    -- Removes a camp marker from the overworld
    local function removeCampMarker(campId: string)
        local marker = _goblinMarkers[campId]
        if marker then
            marker:Destroy()
            _goblinMarkers[campId] = nil
        end
    end

    -- Refreshes all goblin camp markers by fetching active camps from server
    local function refreshGoblinCamps()
        if not GetGoblinCamps then return end

        local success, camps = pcall(function()
            return GetGoblinCamps:InvokeServer()
        end)

        if not success or not camps then return end

        -- Build set of active camp IDs
        local activeCampIds: {[string]: boolean} = {}
        for _, camp in camps do
            activeCampIds[camp.id] = true
            -- Create or keep marker
            createCampMarker(camp)
        end

        -- Remove markers for camps that are no longer active
        for campId, _ in _goblinMarkers do
            if not activeCampIds[campId] then
                removeCampMarker(campId)
            end
        end
    end

    -- Initial load of goblin camps (after a brief delay to let server init)
    task.spawn(function()
        task.wait(2)
        refreshGoblinCamps()
        print("[CLIENT] Goblin camp markers loaded")
    end)

    -- Periodic refresh of goblin camp markers (every 60 seconds)
    task.spawn(function()
        while true do
            task.wait(60)
            refreshGoblinCamps()
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Resource node overworld markers
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Setting up resource node markers...")

do
    local _nodeMarkers: {[string]: Model} = {} -- [nodeId] = marker model
    local _nodesFolder: Folder? = nil

    -- Resource node type visual config
    local NODE_TYPE_VISUALS = {
        Gold = {
            displayName = "Gold Vein",
            color = Color3.fromRGB(255, 200, 50),
            secondaryColor = Color3.fromRGB(180, 140, 30),
            material = Enum.Material.Metal,
            shape = "Rock", -- Rock formation
            billboardColor = Color3.fromRGB(255, 200, 50),
        },
        Wood = {
            displayName = "Lumber Patch",
            color = Color3.fromRGB(140, 90, 40),
            secondaryColor = Color3.fromRGB(100, 65, 25),
            material = Enum.Material.WoodPlanks,
            shape = "Stump", -- Tree stump
            billboardColor = Color3.fromRGB(180, 130, 70),
        },
        Food = {
            displayName = "Berry Bush",
            color = Color3.fromRGB(50, 160, 60),
            secondaryColor = Color3.fromRGB(180, 40, 60),
            material = Enum.Material.Grass,
            shape = "Bush", -- Round bush
            billboardColor = Color3.fromRGB(80, 200, 80),
        },
    }

    -- Creates a 3D visual marker for a resource node in the overworld
    local function createNodeMarker(node: any)
        if _nodeMarkers[node.id] then return end -- Already exists

        -- Ensure folder exists
        if not _nodesFolder then
            _nodesFolder = workspace:FindFirstChild("ResourceNodes") :: Folder?
            if not _nodesFolder then
                local folder = Instance.new("Folder")
                folder.Name = "ResourceNodes"
                folder.Parent = workspace
                _nodesFolder = folder
            end
        end

        local visuals = NODE_TYPE_VISUALS[node.type] or NODE_TYPE_VISUALS.Gold
        local pos = node.position

        -- Create marker model
        local marker = Instance.new("Model")
        marker.Name = "ResourceNode_" .. node.id

        if node.type == "Gold" then
            -- Gold Vein: cluster of golden rocks with sparkle
            local rock1 = Instance.new("Part")
            rock1.Name = "Rock1"
            rock1.Size = Vector3.new(4, 3, 4)
            rock1.Position = Vector3.new(pos.X, pos.Y + 1.5, pos.Z)
            rock1.Anchored = true
            rock1.CanCollide = false
            rock1.Material = Enum.Material.Metal
            rock1.Color = visuals.color
            rock1.Parent = marker

            local rock2 = Instance.new("Part")
            rock2.Name = "Rock2"
            rock2.Size = Vector3.new(2.5, 2, 2.5)
            rock2.Position = Vector3.new(pos.X + 2, pos.Y + 1, pos.Z + 1)
            rock2.Anchored = true
            rock2.CanCollide = false
            rock2.Material = Enum.Material.Metal
            rock2.Color = visuals.secondaryColor
            rock2.Parent = marker

            local rock3 = Instance.new("Part")
            rock3.Name = "Rock3"
            rock3.Size = Vector3.new(2, 1.5, 2)
            rock3.Position = Vector3.new(pos.X - 1.5, pos.Y + 0.75, pos.Z - 1)
            rock3.Anchored = true
            rock3.CanCollide = false
            rock3.Material = Enum.Material.Metal
            rock3.Color = visuals.color
            rock3.Parent = marker

            -- Sparkle effect on main rock
            local sparkle = Instance.new("ParticleEmitter")
            sparkle.Name = "Sparkle"
            sparkle.Rate = 5
            sparkle.Lifetime = NumberRange.new(0.5, 1.5)
            sparkle.Speed = NumberRange.new(1, 3)
            sparkle.SpreadAngle = Vector2.new(180, 180)
            sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 100))
            sparkle.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.2),
                NumberSequenceKeypoint.new(0.5, 0.4),
                NumberSequenceKeypoint.new(1, 0),
            })
            sparkle.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.5),
                NumberSequenceKeypoint.new(1, 1),
            })
            sparkle.LightEmission = 1
            sparkle.Parent = rock1

        elseif node.type == "Wood" then
            -- Lumber Patch: tree stump with logs
            local stump = Instance.new("Part")
            stump.Name = "Stump"
            stump.Size = Vector3.new(4, 2, 4)
            stump.Position = Vector3.new(pos.X, pos.Y + 1, pos.Z)
            stump.Anchored = true
            stump.CanCollide = false
            stump.Material = Enum.Material.WoodPlanks
            stump.Color = visuals.color
            stump.Shape = Enum.PartType.Cylinder
            stump.Orientation = Vector3.new(0, 0, 90)
            stump.Parent = marker

            -- Fallen log nearby
            local log = Instance.new("Part")
            log.Name = "Log"
            log.Size = Vector3.new(5, 1.2, 1.2)
            log.Position = Vector3.new(pos.X + 2, pos.Y + 0.6, pos.Z + 2)
            log.Anchored = true
            log.CanCollide = false
            log.Material = Enum.Material.WoodPlanks
            log.Color = visuals.secondaryColor
            log.Orientation = Vector3.new(0, 30, 0)
            log.Parent = marker

            -- Second smaller log
            local log2 = Instance.new("Part")
            log2.Name = "Log2"
            log2.Size = Vector3.new(3.5, 1, 1)
            log2.Position = Vector3.new(pos.X - 1.5, pos.Y + 0.5, pos.Z + 1.5)
            log2.Anchored = true
            log2.CanCollide = false
            log2.Material = Enum.Material.WoodPlanks
            log2.Color = visuals.color
            log2.Orientation = Vector3.new(0, -20, 10)
            log2.Parent = marker

        elseif node.type == "Food" then
            -- Berry Bush: green bush with red berry accents
            local bush = Instance.new("Part")
            bush.Name = "Bush"
            bush.Size = Vector3.new(5, 3, 5)
            bush.Position = Vector3.new(pos.X, pos.Y + 1.5, pos.Z)
            bush.Anchored = true
            bush.CanCollide = false
            bush.Material = Enum.Material.Grass
            bush.Color = visuals.color
            bush.Shape = Enum.PartType.Ball
            bush.Parent = marker

            -- Berry clusters (small red spheres)
            local berryPositions = {
                Vector3.new(1.5, 1, 1),
                Vector3.new(-1, 1.5, 1.5),
                Vector3.new(0.5, 2, -1),
                Vector3.new(-1.5, 0.8, -0.5),
                Vector3.new(1, 0.5, -1.5),
            }

            for i, berryOffset in berryPositions do
                local berry = Instance.new("Part")
                berry.Name = "Berry_" .. i
                berry.Size = Vector3.new(0.6, 0.6, 0.6)
                berry.Position = Vector3.new(pos.X + berryOffset.X, pos.Y + berryOffset.Y, pos.Z + berryOffset.Z)
                berry.Anchored = true
                berry.CanCollide = false
                berry.Material = Enum.Material.SmoothPlastic
                berry.Color = visuals.secondaryColor
                berry.Shape = Enum.PartType.Ball
                berry.Parent = marker
            end
        end

        -- Get the primary part for billboard adornee
        local adorneePart = marker:FindFirstChild("Rock1") or marker:FindFirstChild("Stump") or marker:FindFirstChild("Bush")

        -- BillboardGui with node info + collect button
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "NodeInfo"
        billboard.Size = UDim2.new(0, 180, 0, 100)
        billboard.StudsOffset = Vector3.new(0, 5, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 80
        billboard.Adornee = adorneePart
        billboard.Parent = marker

        -- Background frame
        local bgFrame = Instance.new("Frame")
        bgFrame.Name = "Background"
        bgFrame.Size = UDim2.new(1, 0, 1, 0)
        bgFrame.BackgroundColor3 = Color3.fromRGB(25, 20, 18)
        bgFrame.BackgroundTransparency = 0.2
        bgFrame.BorderSizePixel = 0
        bgFrame.Parent = billboard

        local bgCorner = Instance.new("UICorner")
        bgCorner.CornerRadius = UDim.new(0, 8)
        bgCorner.Parent = bgFrame

        local bgStroke = Instance.new("UIStroke")
        bgStroke.Color = visuals.billboardColor
        bgStroke.Thickness = 2
        bgStroke.Parent = bgFrame

        -- Node name
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NodeName"
        nameLabel.Size = UDim2.new(1, -8, 0, 20)
        nameLabel.Position = UDim2.new(0, 4, 0, 4)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = node.displayName or visuals.displayName
        nameLabel.TextColor3 = Color3.fromRGB(240, 220, 180)
        nameLabel.TextSize = 13
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Parent = bgFrame

        -- Amount range
        local amountText = ""
        if node.amount then
            local resourceName = string.lower(node.type)
            if resourceName == "gold" then
                amountText = node.amount.min .. "-" .. node.amount.max .. " gold"
            elseif resourceName == "wood" then
                amountText = node.amount.min .. "-" .. node.amount.max .. " wood"
            elseif resourceName == "food" then
                amountText = node.amount.min .. "-" .. node.amount.max .. " food"
            end
        end

        local amountLabel = Instance.new("TextLabel")
        amountLabel.Name = "AmountRange"
        amountLabel.Size = UDim2.new(1, -8, 0, 16)
        amountLabel.Position = UDim2.new(0, 4, 0, 26)
        amountLabel.BackgroundTransparency = 1
        amountLabel.Text = amountText
        amountLabel.TextColor3 = visuals.billboardColor
        amountLabel.TextSize = 11
        amountLabel.Font = Enum.Font.Gotham
        amountLabel.TextXAlignment = Enum.TextXAlignment.Center
        amountLabel.Parent = bgFrame

        -- Collect button
        local collectButton = Instance.new("TextButton")
        collectButton.Name = "CollectButton"
        collectButton.Size = UDim2.new(0.8, 0, 0, 28)
        collectButton.Position = UDim2.new(0.1, 0, 0, 50)
        collectButton.BackgroundColor3 = Color3.fromRGB(50, 140, 50)
        collectButton.Text = "COLLECT"
        collectButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        collectButton.TextSize = 13
        collectButton.Font = Enum.Font.GothamBold
        collectButton.BorderSizePixel = 0
        collectButton.Parent = bgFrame

        local collectCorner = Instance.new("UICorner")
        collectCorner.CornerRadius = UDim.new(0, 6)
        collectCorner.Parent = collectButton

        local collectStroke = Instance.new("UIStroke")
        collectStroke.Color = Color3.fromRGB(80, 200, 80)
        collectStroke.Thickness = 1
        collectStroke.Parent = collectButton

        -- Collect button click handler
        collectButton.MouseButton1Click:Connect(function()
            if not CollectResourceNode then
                if OverworldHUD and OverworldHUD.ShowError then
                    OverworldHUD:ShowError("Resource nodes not available")
                end
                return
            end

            -- Disable button to prevent double-click
            collectButton.Active = false
            collectButton.Text = "Collecting..."
            collectButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)

            -- Fire collect request
            CollectResourceNode:FireServer(node.id)

            -- Re-enable after a delay (in case server response is slow)
            task.delay(3, function()
                if collectButton and collectButton.Parent then
                    collectButton.Active = true
                    collectButton.Text = "COLLECT"
                    collectButton.BackgroundColor3 = Color3.fromRGB(50, 140, 50)
                end
            end)
        end)

        marker.Parent = _nodesFolder
        _nodeMarkers[node.id] = marker
    end

    -- Removes a node marker from the overworld
    local function removeNodeMarker(nodeId: string)
        local marker = _nodeMarkers[nodeId]
        if marker then
            marker:Destroy()
            _nodeMarkers[nodeId] = nil
        end
    end

    -- Shows a floating "+X Resource" text at a position (collection feedback)
    local function showFloatingText(position: Vector3, text: string, color: Color3)
        local part = Instance.new("Part")
        part.Name = "FloatingText"
        part.Size = Vector3.new(1, 1, 1)
        part.Position = position + Vector3.new(0, 5, 0)
        part.Anchored = true
        part.CanCollide = false
        part.Transparency = 1
        part.Parent = workspace

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 200, 0, 40)
        billboard.StudsOffset = Vector3.new(0, 0, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 100
        billboard.Adornee = part
        billboard.Parent = part

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = color
        label.TextSize = 20
        label.Font = Enum.Font.GothamBlack
        label.TextStrokeTransparency = 0.5
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.Parent = billboard

        -- Animate upward and fade out
        task.spawn(function()
            for i = 1, 30 do
                task.wait(0.05)
                part.Position = part.Position + Vector3.new(0, 0.15, 0)
                label.TextTransparency = i / 30
                label.TextStrokeTransparency = 0.5 + (i / 30) * 0.5
            end
            part:Destroy()
        end)
    end

    -- Refreshes all resource node markers by fetching available nodes from server
    local function refreshResourceNodes()
        if not GetResourceNodes then return end

        local success, nodes = pcall(function()
            return GetResourceNodes:InvokeServer()
        end)

        if not success or not nodes then return end

        -- Build set of active node IDs
        local activeNodeIds: {[string]: boolean} = {}
        for _, node in nodes do
            activeNodeIds[node.id] = true
            -- Create or keep marker
            createNodeMarker(node)
        end

        -- Remove markers for nodes that are no longer available (on cooldown for this player)
        for nodeId, _ in _nodeMarkers do
            if not activeNodeIds[nodeId] then
                removeNodeMarker(nodeId)
            end
        end
    end

    -- Listen for ServerResponse to handle collection results
    -- (We hook into the existing ServerResponse handler below, but also handle
    -- the node removal and floating text here)
    task.spawn(function()
        -- Wait for ServerResponse to be available
        local sr = Events:WaitForChild("ServerResponse", 10) :: RemoteEvent?
        if not sr then return end

        sr.OnClientEvent:Connect(function(eventName, result)
            if eventName ~= "CollectResourceNode" then return end

            if result.success then
                local nodeId = result.nodeId
                local resourceType = result.resourceType
                local amount = result.amount

                -- Remove the collected node marker
                if nodeId then
                    -- Get node position before removing for floating text
                    local marker = _nodeMarkers[nodeId]
                    local markerPos = Vector3.new(0, 0, 0)
                    if marker then
                        local primaryPart = marker:FindFirstChild("Rock1") or marker:FindFirstChild("Stump") or marker:FindFirstChild("Bush")
                        if primaryPart then
                            markerPos = (primaryPart :: BasePart).Position
                        end
                    end

                    removeNodeMarker(nodeId)

                    -- Show floating collection text
                    if amount and resourceType then
                        local visuals = NODE_TYPE_VISUALS[resourceType]
                        local color = if visuals then visuals.billboardColor else Color3.fromRGB(255, 255, 255)
                        local resourceName = if resourceType == "Gold" then "Gold"
                            elseif resourceType == "Wood" then "Wood"
                            elseif resourceType == "Food" then "Food"
                            else resourceType
                        showFloatingText(markerPos, "+" .. tostring(amount) .. " " .. resourceName .. "!", color)
                    end
                end

                print(string.format("[CLIENT] Collected resource node: +%d %s", amount or 0, resourceType or "?"))
            else
                -- Handle error (show user-friendly message for specific errors)
                if result.error and OverworldHUD and OverworldHUD.ShowError then
                    local errorMsg = result.error
                    if errorMsg == "TOO_FAR" then
                        errorMsg = "Get closer to collect"
                    elseif errorMsg == "ON_COOLDOWN" then
                        errorMsg = "Already collected - respawns later"
                    elseif errorMsg == "RATE_LIMITED" then
                        errorMsg = "Please wait before collecting again"
                    elseif errorMsg == "NODE_NOT_FOUND" then
                        errorMsg = "Node not found"
                    end
                    OverworldHUD:ShowError(errorMsg)
                end
            end
        end)
    end)

    -- Initial load of resource nodes (after a brief delay to let server init)
    task.spawn(function()
        task.wait(3)
        refreshResourceNodes()
        print("[CLIENT] Resource node markers loaded")
    end)

    -- Periodic refresh of resource node markers (every 60 seconds)
    task.spawn(function()
        while true do
            task.wait(60)
            refreshResourceNodes()
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Trading system
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Setting up trading system...")

do
    -- Get trade events
    local ProposeTrade = Events:FindFirstChild("ProposeTrade") :: RemoteEvent?
    local TradeProposal = Events:FindFirstChild("TradeProposal") :: RemoteEvent?
    local RespondToTrade = Events:FindFirstChild("RespondToTrade") :: RemoteEvent?
    local TradeResult = Events:FindFirstChild("TradeResult") :: RemoteEvent?
    local CancelTrade = Events:FindFirstChild("CancelTrade") :: RemoteEvent?

    -- Connect BaseInfoUI Trade button -> open trade panel
    if BaseInfoUI and BaseInfoUI.TradeClicked then
        BaseInfoUI.TradeClicked:Connect(function(baseData)
            if not TradeUI or not baseData then return end

            -- Fetch current resources to show "you have X" in the UI
            local GetPlayerResources = Events:FindFirstChild("GetPlayerResources") :: RemoteFunction?
            local resources = { gold = 0, wood = 0, food = 0 }
            if GetPlayerResources then
                local ok, res = pcall(function() return GetPlayerResources:InvokeServer() end)
                if ok and res then resources = res end
            end

            TradeUI:ShowProposalPanel(baseData, resources)
        end)
    end

    -- TradeUI proposes trade -> fire to server
    if TradeUI and ProposeTrade then
        TradeUI.TradeProposed:Connect(function(targetUserId, offering, requesting)
            ProposeTrade:FireServer({
                targetUserId = targetUserId,
                offering = offering,
                requesting = requesting,
            })
        end)
    end

    -- Server sends incoming trade proposal -> show to target
    if TradeProposal and TradeUI then
        TradeProposal.OnClientEvent:Connect(function(tradeData)
            TradeUI:ShowIncomingTrade(tradeData)
        end)
    end

    -- TradeUI accept/decline -> fire to server
    if TradeUI and RespondToTrade then
        TradeUI.TradeAccepted:Connect(function(tradeId)
            RespondToTrade:FireServer({ tradeId = tradeId, accepted = true })
        end)
        TradeUI.TradeDeclined:Connect(function(tradeId)
            RespondToTrade:FireServer({ tradeId = tradeId, accepted = false })
        end)
    end

    -- TradeUI cancel -> fire to server
    if TradeUI and CancelTrade then
        TradeUI.TradeCancelled:Connect(function(tradeId)
            CancelTrade:FireServer({ tradeId = tradeId })
        end)
    end

    -- Server trade results -> show feedback
    if TradeResult and TradeUI then
        TradeResult.OnClientEvent:Connect(function(result)
            if result.status == "accepted" then
                TradeUI:ShowResult("Trade completed!", true)
            elseif result.status == "declined" then
                TradeUI:ShowResult("Trade declined.", false)
            elseif result.status == "cancelled" then
                TradeUI:ShowResult("Trade cancelled.", false)
            elseif result.status == "expired" then
                TradeUI:ShowResult("Trade expired.", false)
            elseif result.status == "error" then
                TradeUI:ShowResult(result.error or "Trade failed.", false)
            elseif result.status == "proposed" then
                TradeUI:ShowResult("Trade proposed! Waiting for response...", true)
            end
        end)
    end

    print("[CLIENT] Trading system wired")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Event connections
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Connecting events...")

-- Handle base spawns from server
SpawnBase.OnClientEvent:Connect(function(baseData)
    if OverworldController and OverworldController.OnBaseSpawned then
        OverworldController:OnBaseSpawned(baseData)
    end
end)

-- Handle base removals
RemoveBase.OnClientEvent:Connect(function(userId)
    if OverworldController and OverworldController.OnBaseRemoved then
        OverworldController:OnBaseRemoved(userId)
    end
end)

-- Handle position sync updates
PositionSync.OnClientEvent:Connect(function(nearbyBases)
    if OverworldController and OverworldController.OnPositionSync then
        OverworldController:OnPositionSync(nearbyBases)
    end
end)

-- Handle base interaction results
BaseInteractionResult.OnClientEvent:Connect(function(action, baseData)
    if BaseInteractionController and BaseInteractionController.OnInteractionResult then
        BaseInteractionController:OnInteractionResult(action, baseData)
    end

    if action == "approach" and baseData and BaseInfoUI and BaseInfoUI.Show then
        BaseInfoUI:Show(baseData)
    elseif action == "leave" and BaseInfoUI and BaseInfoUI.Hide then
        BaseInfoUI:Hide()
    end
end)

-- Handle teleport started
TeleportStarted.OnClientEvent:Connect(function(destination)
    print(string.format("[CLIENT] Teleporting to: %s", destination))
    -- Show loading screen
    if OverworldHUD and OverworldHUD.ShowTeleportLoading then
        OverworldHUD:ShowTeleportLoading(destination)
    end
end)

-- Handle teleport failed
TeleportFailed.OnClientEvent:Connect(function(destination, errorMsg)
    warn(string.format("[CLIENT] Teleport failed: %s - %s", destination, errorMsg))
    if OverworldHUD and OverworldHUD.HideTeleportLoading then
        OverworldHUD:HideTeleportLoading()
    end
    if OverworldHUD and OverworldHUD.ShowError then
        OverworldHUD:ShowError("Teleport Failed: " .. errorMsg)
    end
end)

-- Server response handler
ServerResponse.OnClientEvent:Connect(function(eventName, result)
    print(string.format("[CLIENT] Server response for %s: %s", eventName, result.success and "success" or "failed"))

    if not result.success and OverworldHUD and OverworldHUD.ShowError then
        -- Don't show raw error codes for matchmaking/revenge/goblin camps/resource nodes - handled specifically
        if eventName ~= "ConfirmMatchmaking" and eventName ~= "RequestRevenge" and eventName ~= "AttackGoblinCamp" and eventName ~= "CollectResourceNode" then
            OverworldHUD:ShowError(result.error or "Unknown error")
        end
    end

    -- Handle matchmaking confirm result
    if eventName == "ConfirmMatchmaking" then
        if result.success then
            print("[CLIENT] Battle started from matchmaking! battleId:", result.battleId)
            -- Battle arena will handle camera and UI via BattleArenaReady event
        else
            if OverworldHUD and OverworldHUD.ShowError then
                OverworldHUD:ShowError(result.error or "Failed to start battle")
            end
        end
    end

    -- Handle revenge result
    if eventName == "RequestRevenge" then
        if result.success then
            print("[CLIENT] Revenge battle started! battleId:", result.battleId)
            -- Battle arena will handle camera and UI via BattleArenaReady event
        else
            if OverworldHUD and OverworldHUD.ShowError then
                local errorMsg = result.error or "Revenge failed"
                if errorMsg == "NO_REVENGE_AVAILABLE" then
                    errorMsg = "No revenge available for this player"
                elseif errorMsg == "ALREADY_IN_BATTLE" then
                    errorMsg = "Already in a battle"
                elseif errorMsg == "RATE_LIMITED" then
                    errorMsg = "Please wait before trying again"
                end
                OverworldHUD:ShowError(errorMsg)
            end
        end
    end

    -- Handle goblin camp attack result
    if eventName == "AttackGoblinCamp" then
        if result.success then
            print("[CLIENT] Goblin camp attack started!")
            -- Battle arena will handle camera and UI via BattleArenaReady event
        else
            if OverworldHUD and OverworldHUD.ShowError then
                local errorMsg = result.error or "Attack failed"
                if errorMsg == "CAMP_NOT_ACTIVE" then
                    errorMsg = "This camp has already been cleared"
                elseif errorMsg == "ALREADY_IN_BATTLE" then
                    errorMsg = "Already in a battle"
                elseif errorMsg == "NO_TROOPS" then
                    errorMsg = "You need troops to attack"
                elseif errorMsg == "RATE_LIMITED" then
                    errorMsg = "Please wait before trying again"
                elseif errorMsg == "CAMP_NOT_FOUND" then
                    errorMsg = "Camp not found"
                end
                OverworldHUD:ShowError(errorMsg)
            end
        end
    end
end)

-- Handle BattleArenaReady event (sent by BattleArenaService when arena is created)
local BattleArenaReady = Events:FindFirstChild("BattleArenaReady") :: RemoteEvent?
if not BattleArenaReady then
    -- Wait briefly for BattleArenaService to create the event
    task.delay(2, function()
        BattleArenaReady = Events:FindFirstChild("BattleArenaReady") :: RemoteEvent?
        if BattleArenaReady then
            BattleArenaReady.OnClientEvent:Connect(function(arenaData)
                if arenaData.error then
                    if OverworldHUD and OverworldHUD.ShowError then
                        OverworldHUD:ShowError(arenaData.error)
                    end
                    return
                end
                print(string.format("[CLIENT] Battle arena ready: battleId=%s, defender=%s",
                    arenaData.battleId or "?", arenaData.defenderName or "?"))
                -- Hide the OverworldHUD during battle
                if OverworldHUD then
                    OverworldHUD:Hide()
                end
            end)
            print("[CLIENT] Connected to BattleArenaReady event (deferred)")
        end
    end)
else
    BattleArenaReady.OnClientEvent:Connect(function(arenaData)
        if arenaData.error then
            if OverworldHUD and OverworldHUD.ShowError then
                OverworldHUD:ShowError(arenaData.error)
            end
            return
        end
        print(string.format("[CLIENT] Battle arena ready: battleId=%s, defender=%s",
            arenaData.battleId or "?", arenaData.defenderName or "?"))
        -- Hide the OverworldHUD during battle
        if OverworldHUD then
            OverworldHUD:Hide()
        end
    end)
    print("[CLIENT] Connected to BattleArenaReady event")
end

-- Handle ReturnToOverworld event (sent after battle ends)
local ReturnToOverworld = Events:FindFirstChild("ReturnToOverworld") :: RemoteEvent?
if not ReturnToOverworld then
    task.delay(2, function()
        ReturnToOverworld = Events:FindFirstChild("ReturnToOverworld") :: RemoteEvent?
        if ReturnToOverworld then
            ReturnToOverworld.OnClientEvent:Connect(function()
                print("[CLIENT] Returning to overworld after battle")
                if OverworldHUD then
                    OverworldHUD:Show()
                end
            end)
        end
    end)
else
    ReturnToOverworld.OnClientEvent:Connect(function()
        print("[CLIENT] Returning to overworld after battle")
        if OverworldHUD then
            OverworldHUD:Show()
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Player setup
-- ═══════════════════════════════════════════════════════════════════════════════
print("[CLIENT] Setting up player...")

-- Wait for character
local function onCharacterAdded(character: Model)
    print("[CLIENT] Character loaded")

    -- Wait for humanoid root part
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)
    if not humanoidRootPart then
        warn("[CLIENT] HumanoidRootPart not found!")
        return
    end

    -- Start position update loop
    if OverworldController and OverworldController.StartPositionUpdates then
        OverworldController:StartPositionUpdates(humanoidRootPart :: Part)
    end

    -- Start proximity detection loop
    if BaseInteractionController and BaseInteractionController.StartProximityDetection then
        BaseInteractionController:StartProximityDetection(humanoidRootPart :: Part)
    end
end

-- Connect character added
Player.CharacterAdded:Connect(onCharacterAdded)

-- If character already exists, run setup
if Player.Character then
    onCharacterAdded(Player.Character)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Expose public API for other scripts
-- ═══════════════════════════════════════════════════════════════════════════════
local OverworldClient = {}

function OverworldClient.RequestEnterVillage()
    RequestTeleportToVillage:FireServer()
end

function OverworldClient.RequestAttack(targetUserId: number)
    -- Use BattleArenaService's RequestBattle event for same-server arena battles
    if RequestBattle then
        RequestBattle:FireServer(targetUserId)
    else
        -- Fallback to legacy teleport-based battle (will be rejected by server)
        RequestTeleportToBattle:FireServer(targetUserId)
    end
end

function OverworldClient.GetNearbyBases(centerPos: Vector3?, maxCount: number?): {any}
    return GetNearbyBases:InvokeServer(centerPos, maxCount)
end

function OverworldClient.GetBaseData(targetUserId: number): any?
    return GetBaseData:InvokeServer(targetUserId)
end

function OverworldClient.GetOwnBaseData(): any?
    return GetOwnBaseData:InvokeServer()
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Raid splash screen - "You Were Raided!" popup on join
-- ═══════════════════════════════════════════════════════════════════════════════
do
    local function formatRaidNumber(num: number): string
        local formatted = tostring(math.floor(num))
        local k
        while true do
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then break end
        end
        return formatted
    end

    task.spawn(function()
        -- Wait for the Events folder and the GetUnreadAttacks RemoteFunction
        local raidEvents = ReplicatedStorage:WaitForChild("Events", 10)
        if not raidEvents then return end

        local GetUnreadAttacks = raidEvents:FindFirstChild("GetUnreadAttacks") :: RemoteFunction?
        if not GetUnreadAttacks then
            -- Wait a bit longer in case it hasn't been created yet
            task.wait(3)
            GetUnreadAttacks = raidEvents:FindFirstChild("GetUnreadAttacks") :: RemoteFunction?
        end
        if not GetUnreadAttacks then
            warn("[CLIENT] GetUnreadAttacks RemoteFunction not found - skipping raid splash")
            return
        end

        -- Invoke server to get unread attacks
        local success, unreadAttacks = pcall(function()
            return GetUnreadAttacks:InvokeServer()
        end)

        if not success or not unreadAttacks or #unreadAttacks == 0 then
            return -- No unread attacks, nothing to show
        end

        -- Sort by timestamp descending to get most recent first
        table.sort(unreadAttacks, function(a, b)
            return (a.timestamp or 0) > (b.timestamp or 0)
        end)

        local mostRecent = unreadAttacks[1]
        local attackCount = #unreadAttacks

        print(string.format("[CLIENT] Player was raided %d time(s) - showing splash", attackCount))

        -- Create the splash ScreenGui
        local splashGui = Instance.new("ScreenGui")
        splashGui.Name = "RaidSplashScreen"
        splashGui.ResetOnSpawn = false
        splashGui.DisplayOrder = 100 -- Above other UI
        splashGui.Parent = PlayerGui

        -- Auto-dismiss timer
        local autoDismissTime = 15
        local dismissed = false

        local function dismissSplash()
            if dismissed then return end
            dismissed = true
            if splashGui and splashGui.Parent then
                splashGui:Destroy()
            end
        end

        -- Dark overlay
        local overlay = Instance.new("Frame")
        overlay.Name = "Overlay"
        overlay.Size = UDim2.new(1, 0, 1, 0)
        overlay.BackgroundColor3 = Color3.new(0, 0, 0)
        overlay.BackgroundTransparency = 0.3
        overlay.ZIndex = 1
        overlay.Parent = splashGui

        -- Center panel
        local panel = Instance.new("Frame")
        panel.Name = "RaidPanel"
        panel.Size = UDim2.new(0, 460, 0, 420)
        panel.Position = UDim2.new(0.5, 0, 0.5, 0)
        panel.AnchorPoint = Vector2.new(0.5, 0.5)
        panel.BackgroundColor3 = Color3.fromRGB(35, 15, 15)
        panel.BorderSizePixel = 0
        panel.ZIndex = 2
        panel.Parent = splashGui

        local panelCorner = Instance.new("UICorner")
        panelCorner.CornerRadius = UDim.new(0, 14)
        panelCorner.Parent = panel

        local panelStroke = Instance.new("UIStroke")
        panelStroke.Color = Color3.fromRGB(200, 40, 40)
        panelStroke.Thickness = 3
        panelStroke.Parent = panel

        -- Inner gradient for dramatic look
        local panelGradient = Instance.new("UIGradient")
        panelGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 20, 20)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(35, 15, 15)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 10, 10)),
        })
        panelGradient.Rotation = 90
        panelGradient.Parent = panel

        -- Title: "YOUR BASE WAS RAIDED!"
        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 50)
        title.Position = UDim2.new(0, 0, 0, 16)
        title.BackgroundTransparency = 1
        title.Text = "YOUR BASE WAS RAIDED!"
        title.TextColor3 = Color3.fromRGB(255, 60, 60)
        title.TextSize = 28
        title.Font = Enum.Font.GothamBlack
        title.ZIndex = 3
        title.Parent = panel

        -- Attack count subtitle (if multiple attacks)
        if attackCount > 1 then
            local countLabel = Instance.new("TextLabel")
            countLabel.Name = "AttackCount"
            countLabel.Size = UDim2.new(1, 0, 0, 24)
            countLabel.Position = UDim2.new(0, 0, 0, 60)
            countLabel.BackgroundTransparency = 1
            countLabel.Text = string.format("You were raided %d times!", attackCount)
            countLabel.TextColor3 = Color3.fromRGB(200, 160, 120)
            countLabel.TextSize = 16
            countLabel.Font = Enum.Font.GothamBold
            countLabel.ZIndex = 3
            countLabel.Parent = panel
        end

        -- Divider line
        local divider = Instance.new("Frame")
        divider.Name = "Divider"
        divider.Size = UDim2.new(0.85, 0, 0, 2)
        divider.Position = UDim2.new(0.075, 0, 0, 90)
        divider.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
        divider.BorderSizePixel = 0
        divider.ZIndex = 3
        divider.Parent = panel

        -- Most recent attack details
        local detailsStartY = 105

        -- Attacker name
        local attackerLabel = Instance.new("TextLabel")
        attackerLabel.Name = "AttackerLabel"
        attackerLabel.Size = UDim2.new(0.4, 0, 0, 24)
        attackerLabel.Position = UDim2.new(0.08, 0, 0, detailsStartY)
        attackerLabel.BackgroundTransparency = 1
        attackerLabel.Text = "Attacker:"
        attackerLabel.TextColor3 = Color3.fromRGB(150, 130, 110)
        attackerLabel.TextSize = 14
        attackerLabel.Font = Enum.Font.Gotham
        attackerLabel.TextXAlignment = Enum.TextXAlignment.Left
        attackerLabel.ZIndex = 3
        attackerLabel.Parent = panel

        local attackerValue = Instance.new("TextLabel")
        attackerValue.Name = "AttackerValue"
        attackerValue.Size = UDim2.new(0.48, 0, 0, 24)
        attackerValue.Position = UDim2.new(0.44, 0, 0, detailsStartY)
        attackerValue.BackgroundTransparency = 1
        attackerValue.Text = mostRecent.attackerName or "Unknown"
        attackerValue.TextColor3 = Color3.fromRGB(255, 220, 180)
        attackerValue.TextSize = 16
        attackerValue.Font = Enum.Font.GothamBold
        attackerValue.TextXAlignment = Enum.TextXAlignment.Right
        attackerValue.ZIndex = 3
        attackerValue.Parent = panel

        -- Stars earned
        local starsLabel = Instance.new("TextLabel")
        starsLabel.Name = "StarsLabel"
        starsLabel.Size = UDim2.new(0.4, 0, 0, 28)
        starsLabel.Position = UDim2.new(0.08, 0, 0, detailsStartY + 32)
        starsLabel.BackgroundTransparency = 1
        starsLabel.Text = "Stars Earned:"
        starsLabel.TextColor3 = Color3.fromRGB(150, 130, 110)
        starsLabel.TextSize = 14
        starsLabel.Font = Enum.Font.Gotham
        starsLabel.TextXAlignment = Enum.TextXAlignment.Left
        starsLabel.ZIndex = 3
        starsLabel.Parent = panel

        local stars = mostRecent.stars or 0
        local starText = ""
        for s = 1, 3 do
            starText = starText .. (s <= stars and "★" or "☆")
        end
        local starsValue = Instance.new("TextLabel")
        starsValue.Name = "StarsValue"
        starsValue.Size = UDim2.new(0.48, 0, 0, 28)
        starsValue.Position = UDim2.new(0.44, 0, 0, detailsStartY + 32)
        starsValue.BackgroundTransparency = 1
        starsValue.Text = starText
        starsValue.TextColor3 = Color3.fromRGB(255, 200, 50)
        starsValue.TextSize = 24
        starsValue.Font = Enum.Font.GothamBold
        starsValue.TextXAlignment = Enum.TextXAlignment.Right
        starsValue.ZIndex = 3
        starsValue.Parent = panel

        -- Destruction %
        local destLabel = Instance.new("TextLabel")
        destLabel.Name = "DestructionLabel"
        destLabel.Size = UDim2.new(0.4, 0, 0, 24)
        destLabel.Position = UDim2.new(0.08, 0, 0, detailsStartY + 68)
        destLabel.BackgroundTransparency = 1
        destLabel.Text = "Destruction:"
        destLabel.TextColor3 = Color3.fromRGB(150, 130, 110)
        destLabel.TextSize = 14
        destLabel.Font = Enum.Font.Gotham
        destLabel.TextXAlignment = Enum.TextXAlignment.Left
        destLabel.ZIndex = 3
        destLabel.Parent = panel

        local destValue = Instance.new("TextLabel")
        destValue.Name = "DestructionValue"
        destValue.Size = UDim2.new(0.48, 0, 0, 24)
        destValue.Position = UDim2.new(0.44, 0, 0, detailsStartY + 68)
        destValue.BackgroundTransparency = 1
        destValue.Text = math.floor(mostRecent.destruction or 0) .. "%"
        destValue.TextColor3 = Color3.fromRGB(255, 80, 60)
        destValue.TextSize = 18
        destValue.Font = Enum.Font.GothamBold
        destValue.TextXAlignment = Enum.TextXAlignment.Right
        destValue.ZIndex = 3
        destValue.Parent = panel

        -- Loot stolen
        local lootHeaderLabel = Instance.new("TextLabel")
        lootHeaderLabel.Name = "LootHeader"
        lootHeaderLabel.Size = UDim2.new(0.4, 0, 0, 24)
        lootHeaderLabel.Position = UDim2.new(0.08, 0, 0, detailsStartY + 100)
        lootHeaderLabel.BackgroundTransparency = 1
        lootHeaderLabel.Text = "Loot Stolen:"
        lootHeaderLabel.TextColor3 = Color3.fromRGB(150, 130, 110)
        lootHeaderLabel.TextSize = 14
        lootHeaderLabel.Font = Enum.Font.Gotham
        lootHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
        lootHeaderLabel.ZIndex = 3
        lootHeaderLabel.Parent = panel

        local goldStolen = mostRecent.goldStolen or 0
        local woodStolen = mostRecent.woodStolen or 0
        local foodStolen = mostRecent.foodStolen or 0

        local lootValue = Instance.new("TextLabel")
        lootValue.Name = "LootValue"
        lootValue.Size = UDim2.new(0.48, 0, 0, 24)
        lootValue.Position = UDim2.new(0.44, 0, 0, detailsStartY + 100)
        lootValue.BackgroundTransparency = 1
        lootValue.Text = "-" .. formatRaidNumber(goldStolen) .. " Gold"
        lootValue.TextColor3 = Color3.fromRGB(255, 200, 50)
        lootValue.TextSize = 14
        lootValue.Font = Enum.Font.GothamBold
        lootValue.TextXAlignment = Enum.TextXAlignment.Right
        lootValue.ZIndex = 3
        lootValue.Parent = panel

        local lootValue2 = Instance.new("TextLabel")
        lootValue2.Name = "LootValue2"
        lootValue2.Size = UDim2.new(0.48, 0, 0, 24)
        lootValue2.Position = UDim2.new(0.44, 0, 0, detailsStartY + 120)
        lootValue2.BackgroundTransparency = 1
        lootValue2.Text = "-" .. formatRaidNumber(woodStolen) .. " Wood, -" .. formatRaidNumber(foodStolen) .. " Food"
        lootValue2.TextColor3 = Color3.fromRGB(200, 160, 120)
        lootValue2.TextSize = 12
        lootValue2.Font = Enum.Font.Gotham
        lootValue2.TextXAlignment = Enum.TextXAlignment.Right
        lootValue2.ZIndex = 3
        lootValue2.Parent = panel

        -- Trophy change
        local trophyLabel = Instance.new("TextLabel")
        trophyLabel.Name = "TrophyLabel"
        trophyLabel.Size = UDim2.new(0.4, 0, 0, 24)
        trophyLabel.Position = UDim2.new(0.08, 0, 0, detailsStartY + 152)
        trophyLabel.BackgroundTransparency = 1
        trophyLabel.Text = "Trophy Change:"
        trophyLabel.TextColor3 = Color3.fromRGB(150, 130, 110)
        trophyLabel.TextSize = 14
        trophyLabel.Font = Enum.Font.Gotham
        trophyLabel.TextXAlignment = Enum.TextXAlignment.Left
        trophyLabel.ZIndex = 3
        trophyLabel.Parent = panel

        local trophyChange = mostRecent.trophyChange or 0
        local trophyValue = Instance.new("TextLabel")
        trophyValue.Name = "TrophyValue"
        trophyValue.Size = UDim2.new(0.48, 0, 0, 24)
        trophyValue.Position = UDim2.new(0.44, 0, 0, detailsStartY + 152)
        trophyValue.BackgroundTransparency = 1
        trophyValue.Text = (trophyChange >= 0 and "+" or "") .. trophyChange .. " Trophies"
        trophyValue.TextColor3 = trophyChange >= 0
            and Color3.fromRGB(80, 200, 80)
            or Color3.fromRGB(255, 80, 60)
        trophyValue.TextSize = 16
        trophyValue.Font = Enum.Font.GothamBold
        trophyValue.TextXAlignment = Enum.TextXAlignment.Right
        trophyValue.ZIndex = 3
        trophyValue.Parent = panel

        -- Divider before buttons
        local divider2 = Instance.new("Frame")
        divider2.Name = "Divider2"
        divider2.Size = UDim2.new(0.85, 0, 0, 2)
        divider2.Position = UDim2.new(0.075, 0, 0, detailsStartY + 190)
        divider2.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
        divider2.BorderSizePixel = 0
        divider2.ZIndex = 3
        divider2.Parent = panel

        -- Button container
        local buttonY = detailsStartY + 210

        -- REVENGE button (red)
        local revengeButton = Instance.new("TextButton")
        revengeButton.Name = "RevengeButton"
        revengeButton.Size = UDim2.new(0, 180, 0, 50)
        revengeButton.Position = UDim2.new(0.5, -195, 0, buttonY)
        revengeButton.BackgroundColor3 = Color3.fromRGB(180, 35, 35)
        revengeButton.Text = "REVENGE"
        revengeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        revengeButton.TextSize = 20
        revengeButton.Font = Enum.Font.GothamBlack
        revengeButton.BorderSizePixel = 0
        revengeButton.ZIndex = 3
        revengeButton.Parent = panel

        local revengeCorner = Instance.new("UICorner")
        revengeCorner.CornerRadius = UDim.new(0, 10)
        revengeCorner.Parent = revengeButton

        local revengeStroke = Instance.new("UIStroke")
        revengeStroke.Color = Color3.fromRGB(255, 80, 80)
        revengeStroke.Thickness = 2
        revengeStroke.Parent = revengeButton

        -- DEFEND button (blue)
        local defendButton = Instance.new("TextButton")
        defendButton.Name = "DefendButton"
        defendButton.Size = UDim2.new(0, 180, 0, 50)
        defendButton.Position = UDim2.new(0.5, 15, 0, buttonY)
        defendButton.BackgroundColor3 = Color3.fromRGB(40, 80, 160)
        defendButton.Text = "DISMISS"
        defendButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        defendButton.TextSize = 20
        defendButton.Font = Enum.Font.GothamBold
        defendButton.BorderSizePixel = 0
        defendButton.ZIndex = 3
        defendButton.Parent = panel

        local defendCorner = Instance.new("UICorner")
        defendCorner.CornerRadius = UDim.new(0, 10)
        defendCorner.Parent = defendButton

        local defendStroke = Instance.new("UIStroke")
        defendStroke.Color = Color3.fromRGB(80, 120, 220)
        defendStroke.Thickness = 2
        defendStroke.Parent = defendButton

        -- Auto-dismiss countdown label
        local countdownLabel = Instance.new("TextLabel")
        countdownLabel.Name = "Countdown"
        countdownLabel.Size = UDim2.new(1, 0, 0, 20)
        countdownLabel.Position = UDim2.new(0, 0, 1, -28)
        countdownLabel.BackgroundTransparency = 1
        countdownLabel.Text = "Auto-dismiss in " .. autoDismissTime .. "s"
        countdownLabel.TextColor3 = Color3.fromRGB(120, 100, 80)
        countdownLabel.TextSize = 12
        countdownLabel.Font = Enum.Font.Gotham
        countdownLabel.ZIndex = 3
        countdownLabel.Parent = panel

        -- Wire REVENGE button
        revengeButton.MouseButton1Click:Connect(function()
            -- Fire RequestRevenge RemoteEvent if it exists
            local requestRevenge = raidEvents:FindFirstChild("RequestRevenge") :: RemoteEvent?
            if requestRevenge then
                requestRevenge:FireServer({
                    targetUserId = mostRecent.attackerUserId or mostRecent.attackerId,
                })
                print("[CLIENT] Revenge requested against:", mostRecent.attackerName or "Unknown")
            else
                warn("[CLIENT] RequestRevenge RemoteEvent not found")
                if OverworldHUD and OverworldHUD.ShowError then
                    OverworldHUD:ShowError("Revenge system not available yet")
                end
            end
            dismissSplash()
        end)

        -- Wire DEFEND/DISMISS button
        defendButton.MouseButton1Click:Connect(function()
            dismissSplash()
        end)

        -- Auto-dismiss countdown
        task.spawn(function()
            for remaining = autoDismissTime, 1, -1 do
                if dismissed then return end
                if countdownLabel and countdownLabel.Parent then
                    countdownLabel.Text = "Auto-dismiss in " .. remaining .. "s"
                end
                task.wait(1)
            end
            dismissSplash()
        end)
    end)
end

print("========================================")
print("BATTLE TYCOON: CONQUEST - OVERWORLD CLIENT READY!")
print("========================================")

return OverworldClient
