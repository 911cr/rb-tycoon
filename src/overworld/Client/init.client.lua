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

-- Connect Go to City button
if OverworldHUD and OverworldHUD.GoToCityClicked then
    OverworldHUD.GoToCityClicked:Connect(function()
        print("[CLIENT] Go to City clicked - requesting teleport to village")
        RequestTeleportToVillage:FireServer()
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
                local entryFrame = Instance.new("Frame")
                entryFrame.Name = "Entry_" .. i
                entryFrame.Size = UDim2.new(1, -8, 0, 70)
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
        -- Don't show raw error codes for matchmaking - handled by MatchmakingUI
        if eventName ~= "ConfirmMatchmaking" then
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

print("========================================")
print("BATTLE TYCOON: CONQUEST - OVERWORLD CLIENT READY!")
print("========================================")

return OverworldClient
