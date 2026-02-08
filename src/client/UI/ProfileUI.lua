--!strict
--[[
    ProfileUI.lua

    Displays player profile, stats, and achievements.
    Shows combat history, building progress, and account info.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local ProfileUI = {}
ProfileUI.__index = ProfileUI

-- Events
ProfileUI.CloseRequested = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _statsContainer: Frame? = nil
local _initialized = false

--[[
    Formats a number with commas.
]]
local function formatNumber(num: number): string
    local formatted = tostring(math.floor(num))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

--[[
    Creates a stat row.
]]
local function createStatRow(label: string, value: string, parent: Frame): Frame
    local row = Components.CreateFrame({
        Name = label,
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local labelText = Components.CreateLabel({
        Name = "Label",
        Text = label,
        Size = UDim2.new(0.6, 0, 1, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local valueText = Components.CreateLabel({
        Name = "Value",
        Text = value,
        Size = UDim2.new(0.4, 0, 1, 0),
        Position = UDim2.new(0.6, 0, 0, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row,
    })

    return row
end

--[[
    Creates a stat section with header.
]]
local function createStatSection(title: string, parent: Frame): Frame
    local section = Components.CreateFrame({
        Name = title,
        Size = UDim2.new(1, -16, 0, 0), -- Auto height
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    local headerLabel = Components.CreateLabel({
        Name = "Header",
        Text = title,
        Size = UDim2.new(1, -16, 0, 28),
        Position = UDim2.new(0, 8, 0, 8),
        TextColor = Components.Colors.Primary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = section,
    })

    local contentContainer = Components.CreateFrame({
        Name = "Content",
        Size = UDim2.new(1, -16, 0, 0),
        Position = UDim2.new(0, 8, 0, 40),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = section,
    })

    local listLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 4),
        Parent = contentContainer,
    })

    return section
end

--[[
    Creates the player header section.
]]
local function createPlayerHeader(parent: Frame): Frame
    local header = Components.CreateFrame({
        Name = "PlayerHeader",
        Size = UDim2.new(1, -32, 0, 100),
        Position = UDim2.new(0.5, 0, 0, 60),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- Avatar placeholder
    local avatarBg = Components.CreateFrame({
        Name = "Avatar",
        Size = UDim2.new(0, 70, 0, 70),
        Position = UDim2.new(0, 15, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = Components.Colors.Primary,
        CornerRadius = UDim.new(0.5, 0),
        Parent = header,
    })

    local avatarLabel = Components.CreateLabel({
        Name = "AvatarText",
        Text = string.sub(_player.Name, 1, 2):upper(),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = 28,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = avatarBg,
    })

    -- Player name
    local nameLabel = Components.CreateLabel({
        Name = "PlayerName",
        Text = _player.Name,
        Size = UDim2.new(0.5, 0, 0, 28),
        Position = UDim2.new(0, 100, 0, 18),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })

    -- Town Hall level
    local thLabel = Components.CreateLabel({
        Name = "TownHall",
        Text = "Town Hall Level: 1",
        Size = UDim2.new(0.4, 0, 0, 22),
        Position = UDim2.new(0, 100, 0, 48),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })

    -- Join date
    local joinLabel = Components.CreateLabel({
        Name = "JoinDate",
        Text = "Playing since: Today",
        Size = UDim2.new(0.4, 0, 0, 20),
        Position = UDim2.new(0, 100, 0, 70),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })

    -- League badge
    local leagueBadge = Components.CreateFrame({
        Name = "LeagueBadge",
        Size = UDim2.new(0, 60, 0, 60),
        Position = UDim2.new(1, -20, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor = Components.Colors.Warning,
        CornerRadius = UDim.new(0.5, 0),
        Parent = header,
    })

    local leagueLabel = Components.CreateLabel({
        Name = "LeagueText",
        Text = "L",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = 24,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = leagueBadge,
    })

    return header
end

--[[
    Refreshes the profile data.
]]
function ProfileUI:Refresh()
    if not _mainFrame then return end

    local playerData = ClientAPI.GetPlayerData()
    local leaderboardInfo = ClientAPI.GetLeaderboardInfo()

    -- Update player header
    local header = _mainFrame:FindFirstChild("PlayerHeader")
    if header and playerData then
        local thLabel = header:FindFirstChild("TownHall") :: TextLabel?
        if thLabel then
            thLabel.Text = "Town Hall Level: " .. (playerData.townHallLevel or 1)
        end
    end

    -- Update stats
    if not _statsContainer then return end

    -- Clear existing sections
    for _, child in _statsContainer:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    if playerData then
        -- Combat Stats section
        local combatSection = createStatSection("Combat Stats", _statsContainer)
        local combatContent = combatSection:FindFirstChild("Content")
        if combatContent then
            local stats = playerData.stats or {}
            createStatRow("Attacks Won", formatNumber(stats.attacksWon or 0), combatContent)
            createStatRow("Defenses Won", formatNumber(stats.defensesWon or 0), combatContent)
            createStatRow("3-Star Wins", formatNumber(stats.threeStarWins or 0), combatContent)
            createStatRow("Troops Donated", formatNumber(stats.troopsDonated or 0), combatContent)
            createStatRow("Gold Looted", formatNumber(stats.goldLooted or 0), combatContent)

            -- Update section height
            combatSection.Size = UDim2.new(1, -16, 0, 40 + (#combatContent:GetChildren() - 1) * 36)
        end

        -- Trophy Stats section
        local trophySection = createStatSection("Trophy Stats", _statsContainer)
        local trophyContent = trophySection:FindFirstChild("Content")
        if trophyContent and playerData.trophies then
            createStatRow("Current Trophies", formatNumber(playerData.trophies.current or 0), trophyContent)
            createStatRow("Best Trophies", formatNumber(playerData.trophies.best or 0), trophyContent)
            createStatRow("Season Best", formatNumber(playerData.trophies.seasonBest or 0), trophyContent)

            if leaderboardInfo and leaderboardInfo.rank then
                createStatRow("Global Rank", "#" .. formatNumber(leaderboardInfo.rank), trophyContent)
            end

            if leaderboardInfo and leaderboardInfo.league then
                createStatRow("League", leaderboardInfo.league.name, trophyContent)
            end

            trophySection.Size = UDim2.new(1, -16, 0, 40 + (#trophyContent:GetChildren() - 1) * 36)
        end

        -- Progress section
        local progressSection = createStatSection("Progress", _statsContainer)
        local progressContent = progressSection:FindFirstChild("Content")
        if progressContent then
            local buildings = playerData.buildings or {}
            createStatRow("Buildings Placed", formatNumber(#buildings), progressContent)
            createStatRow("Builders", tostring(#(playerData.builders or {})), progressContent)

            local troops = playerData.troops or {}
            local totalTroops = 0
            for _, count in troops do
                totalTroops += count
            end
            createStatRow("Army Size", formatNumber(totalTroops), progressContent)

            local spells = playerData.spells or {}
            local totalSpells = 0
            for _, count in spells do
                totalSpells += count
            end
            createStatRow("Spells Ready", formatNumber(totalSpells), progressContent)

            progressSection.Size = UDim2.new(1, -16, 0, 40 + (#progressContent:GetChildren() - 1) * 36)
        end

        -- Resources section
        local resourceSection = createStatSection("Resources", _statsContainer)
        local resourceContent = resourceSection:FindFirstChild("Content")
        if resourceContent and playerData.resources then
            createStatRow("Gold", formatNumber(playerData.resources.gold or 0), resourceContent)
            createStatRow("Wood", formatNumber(playerData.resources.wood or 0), resourceContent)
            createStatRow("Food", formatNumber(playerData.resources.food or 0), resourceContent)
            createStatRow("Gems", formatNumber(playerData.resources.gems or 0), resourceContent)

            resourceSection.Size = UDim2.new(1, -16, 0, 40 + (#resourceContent:GetChildren() - 1) * 36)
        end
    end
end

--[[
    Shows the profile UI.
]]
function ProfileUI:Show()
    if _screenGui then
        _screenGui.Enabled = true

        -- Animate in
        if _mainFrame then
            _mainFrame.Position = UDim2.new(-0.5, 0, 0.5, 0)
            TweenService:Create(_mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Position = UDim2.new(0.5, 0, 0.5, 0)
            }):Play()
        end

        self:Refresh()
    end
end

--[[
    Hides the profile UI.
]]
function ProfileUI:Hide()
    if _screenGui and _mainFrame then
        local tween = TweenService:Create(_mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(-0.5, 0, 0.5, 0)
        })
        tween:Play()
        tween.Completed:Connect(function()
            if _screenGui then
                _screenGui.Enabled = false
            end
        end)
    end
end

--[[
    Checks if the UI is visible.
]]
function ProfileUI:IsVisible(): boolean
    return _screenGui and _screenGui.Enabled or false
end

--[[
    Initializes the ProfileUI.
]]
function ProfileUI:Init()
    if _initialized then
        warn("ProfileUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "ProfileUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.DisplayOrder = 50
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Create main panel
    _mainFrame = Components.CreateFrame({
        Name = "MainFrame",
        Size = UDim2.new(0.5, 0, 0.8, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor = Components.Colors.Background,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        Parent = _screenGui,
    })

    -- Add border
    local stroke = Instance.new("UIStroke")
    stroke.Color = Components.Colors.Primary
    stroke.Thickness = 2
    stroke.Parent = _mainFrame

    -- Header
    local header = Components.CreateLabel({
        Name = "Header",
        Text = "Player Profile",
        Size = UDim2.new(1, 0, 0, 50),
        Position = UDim2.new(0, 0, 0, 8),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = _mainFrame,
    })

    -- Close button
    local closeButton = Components.CreateButton({
        Name = "CloseButton",
        Text = "X",
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(1, -12, 0, 12),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor = Components.Colors.Danger,
        OnClick = function()
            self:Hide()
            ProfileUI.CloseRequested:Fire()
        end,
        Parent = _mainFrame,
    })

    -- Player header
    createPlayerHeader(_mainFrame)

    -- Stats container (scrollable)
    local statsContainerFrame = Components.CreateFrame({
        Name = "StatsContainerFrame",
        Size = UDim2.new(1, -32, 1, -200),
        Position = UDim2.new(0.5, 0, 0, 175),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        Parent = _mainFrame,
    })

    _statsContainer = Instance.new("ScrollingFrame")
    _statsContainer.Name = "StatsContainer"
    _statsContainer.Size = UDim2.new(1, 0, 1, 0)
    _statsContainer.BackgroundTransparency = 1
    _statsContainer.BorderSizePixel = 0
    _statsContainer.ScrollBarThickness = 6
    _statsContainer.ScrollBarImageColor3 = Components.Colors.Secondary
    _statsContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    _statsContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    _statsContainer.Parent = statsContainerFrame

    local listLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 12),
        Parent = _statsContainer,
    })

    _initialized = true
    print("ProfileUI initialized")
end

return ProfileUI
