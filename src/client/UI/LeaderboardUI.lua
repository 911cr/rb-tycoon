--!strict
--[[
    LeaderboardUI.lua

    Displays global trophy leaderboard and player rankings.
    Shows current league and progress towards next league.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local LeaderboardUI = {}
LeaderboardUI.__index = LeaderboardUI

-- Events
LeaderboardUI.CloseRequested = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _leaderboardContainer: ScrollingFrame? = nil
local _playerInfoFrame: Frame? = nil
local _initialized = false

-- League colors
local LeagueColors = {
    unranked = Color3.fromRGB(128, 128, 128),
    bronze_3 = Color3.fromRGB(205, 127, 50),
    bronze_2 = Color3.fromRGB(205, 127, 50),
    bronze_1 = Color3.fromRGB(205, 127, 50),
    silver_3 = Color3.fromRGB(192, 192, 192),
    silver_2 = Color3.fromRGB(192, 192, 192),
    silver_1 = Color3.fromRGB(192, 192, 192),
    gold_3 = Color3.fromRGB(255, 215, 0),
    gold_2 = Color3.fromRGB(255, 215, 0),
    gold_1 = Color3.fromRGB(255, 215, 0),
    crystal_3 = Color3.fromRGB(138, 43, 226),
    crystal_2 = Color3.fromRGB(138, 43, 226),
    crystal_1 = Color3.fromRGB(138, 43, 226),
    master_3 = Color3.fromRGB(0, 191, 255),
    master_2 = Color3.fromRGB(0, 191, 255),
    master_1 = Color3.fromRGB(0, 191, 255),
    champion_3 = Color3.fromRGB(220, 20, 60),
    champion_2 = Color3.fromRGB(220, 20, 60),
    champion_1 = Color3.fromRGB(220, 20, 60),
    titan_3 = Color3.fromRGB(255, 20, 147),
    titan_2 = Color3.fromRGB(255, 20, 147),
    titan_1 = Color3.fromRGB(255, 20, 147),
    legend = Color3.fromRGB(255, 215, 0),
}

--[[
    Gets the color for a league.
]]
local function getLeagueColor(leagueId: string): Color3
    return LeagueColors[leagueId] or Components.Colors.TextPrimary
end

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
    Creates a leaderboard entry row.
]]
local function createLeaderboardEntry(data: {rank: number, userId: number, username: string, trophies: number}, parent: ScrollingFrame): Frame
    local isCurrentPlayer = data.userId == _player.UserId

    local row = Components.CreateFrame({
        Name = "Entry_" .. data.rank,
        Size = UDim2.new(1, -16, 0, 50),
        BackgroundColor = isCurrentPlayer and Components.Colors.Primary or Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- Highlight current player
    if isCurrentPlayer then
        local stroke = Instance.new("UIStroke")
        stroke.Color = Components.Colors.Warning
        stroke.Thickness = 2
        stroke.Parent = row
    end

    -- Rank
    local rankColor = Components.Colors.TextPrimary
    if data.rank == 1 then
        rankColor = Color3.fromRGB(255, 215, 0) -- Gold
    elseif data.rank == 2 then
        rankColor = Color3.fromRGB(192, 192, 192) -- Silver
    elseif data.rank == 3 then
        rankColor = Color3.fromRGB(205, 127, 50) -- Bronze
    end

    local rankLabel = Components.CreateLabel({
        Name = "Rank",
        Text = "#" .. data.rank,
        Size = UDim2.new(0, 50, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        TextColor = rankColor,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    -- Username
    local usernameLabel = Components.CreateLabel({
        Name = "Username",
        Text = data.username,
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0, 60, 0, 0),
        TextColor = isCurrentPlayer and Components.Colors.TextPrimary or Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = isCurrentPlayer and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    -- Trophy count
    local trophyContainer = Components.CreateFrame({
        Name = "TrophyContainer",
        Size = UDim2.new(0, 100, 0, 30),
        Position = UDim2.new(1, -16, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor = Components.Colors.Warning,
        BackgroundTransparency = 0.8,
        CornerRadius = UDim.new(0, 6),
        Parent = row,
    })

    local trophyLabel = Components.CreateLabel({
        Name = "Trophies",
        Text = formatNumber(data.trophies),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.Warning,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = trophyContainer,
    })

    return row
end

--[[
    Creates the player info section.
]]
local function createPlayerInfo(parent: Frame): Frame
    local container = Components.CreateFrame({
        Name = "PlayerInfo",
        Size = UDim2.new(1, -32, 0, 120),
        Position = UDim2.new(0.5, 0, 0, 60),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = parent,
    })

    -- League icon placeholder
    local leagueIcon = Components.CreateFrame({
        Name = "LeagueIcon",
        Size = UDim2.new(0, 80, 0, 80),
        Position = UDim2.new(0, 20, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = Components.Colors.Warning,
        CornerRadius = UDim.new(0.5, 0),
        Parent = container,
    })

    local leagueIconLabel = Components.CreateLabel({
        Name = "LeagueIconText",
        Text = "L",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = 32,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = leagueIcon,
    })

    -- League name
    local leagueName = Components.CreateLabel({
        Name = "LeagueName",
        Text = "Unranked",
        Size = UDim2.new(0.5, 0, 0, 28),
        Position = UDim2.new(0, 115, 0, 15),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container,
    })

    -- Trophy count
    local trophyLabel = Components.CreateLabel({
        Name = "Trophies",
        Text = "0 Trophies",
        Size = UDim2.new(0.3, 0, 0, 22),
        Position = UDim2.new(0, 115, 0, 45),
        TextColor = Components.Colors.Warning,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container,
    })

    -- Rank label
    local rankLabel = Components.CreateLabel({
        Name = "Rank",
        Text = "Global Rank: --",
        Size = UDim2.new(0.3, 0, 0, 22),
        Position = UDim2.new(0, 115, 0, 68),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container,
    })

    -- Best trophies
    local bestLabel = Components.CreateLabel({
        Name = "Best",
        Text = "Best: 0",
        Size = UDim2.new(0.2, 0, 0, 22),
        Position = UDim2.new(1, -20, 0, 25),
        AnchorPoint = Vector2.new(1, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = container,
    })

    -- Season best
    local seasonLabel = Components.CreateLabel({
        Name = "SeasonBest",
        Text = "Season: 0",
        Size = UDim2.new(0.2, 0, 0, 22),
        Position = UDim2.new(1, -20, 0, 50),
        AnchorPoint = Vector2.new(1, 0),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = container,
    })

    return container
end

--[[
    Refreshes the leaderboard data.
]]
function LeaderboardUI:Refresh()
    if not _leaderboardContainer or not _playerInfoFrame then return end

    -- Clear existing entries
    for _, child in _leaderboardContainer:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    -- Get player info
    local info = ClientAPI.GetLeaderboardInfo()
    if info then
        local leagueName = _playerInfoFrame:FindFirstChild("LeagueName") :: TextLabel?
        local trophyLabel = _playerInfoFrame:FindFirstChild("Trophies") :: TextLabel?
        local rankLabel = _playerInfoFrame:FindFirstChild("Rank") :: TextLabel?
        local bestLabel = _playerInfoFrame:FindFirstChild("Best") :: TextLabel?
        local seasonLabel = _playerInfoFrame:FindFirstChild("SeasonBest") :: TextLabel?
        local leagueIcon = _playerInfoFrame:FindFirstChild("LeagueIcon") :: Frame?

        if leagueName then
            leagueName.Text = info.league and info.league.name or "Unranked"
            leagueName.TextColor3 = getLeagueColor(info.league and info.league.id or "unranked")
        end
        if trophyLabel then
            trophyLabel.Text = formatNumber(info.trophies) .. " Trophies"
        end
        if rankLabel then
            if info.rank then
                rankLabel.Text = "Global Rank: #" .. formatNumber(info.rank)
            else
                rankLabel.Text = "Global Rank: Unranked"
            end
        end
        if bestLabel then
            bestLabel.Text = "Best: " .. formatNumber(info.best)
        end
        if seasonLabel then
            seasonLabel.Text = "Season: " .. formatNumber(info.seasonBest)
        end
        if leagueIcon then
            leagueIcon.BackgroundColor3 = getLeagueColor(info.league and info.league.id or "unranked")
        end
    end

    -- Get leaderboard
    local leaderboard = ClientAPI.GetLeaderboard(100)
    if leaderboard then
        for _, entry in leaderboard do
            createLeaderboardEntry(entry, _leaderboardContainer)
        end
    end
end

--[[
    Shows the leaderboard UI.
]]
function LeaderboardUI:Show()
    if _screenGui then
        _screenGui.Enabled = true

        -- Animate in
        if _mainFrame then
            _mainFrame.Position = UDim2.new(1.5, 0, 0.5, 0)
            TweenService:Create(_mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Position = UDim2.new(0.5, 0, 0.5, 0)
            }):Play()
        end

        self:Refresh()
    end
end

--[[
    Hides the leaderboard UI.
]]
function LeaderboardUI:Hide()
    if _screenGui and _mainFrame then
        local tween = TweenService:Create(_mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(1.5, 0, 0.5, 0)
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
function LeaderboardUI:IsVisible(): boolean
    return _screenGui and _screenGui.Enabled or false
end

--[[
    Initializes the LeaderboardUI.
]]
function LeaderboardUI:Init()
    if _initialized then
        warn("LeaderboardUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "LeaderboardUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.DisplayOrder = 50
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Create main panel
    _mainFrame = Components.CreateFrame({
        Name = "MainFrame",
        Size = UDim2.new(0.6, 0, 0.8, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor = Components.Colors.Background,
        CornerRadius = Components.Sizes.CornerRadiusLarge,
        Parent = _screenGui,
    })

    -- Add border
    local stroke = Instance.new("UIStroke")
    stroke.Color = Components.Colors.Warning
    stroke.Thickness = 2
    stroke.Parent = _mainFrame

    -- Header
    local header = Components.CreateLabel({
        Name = "Header",
        Text = "Global Leaderboard",
        Size = UDim2.new(1, 0, 0, 50),
        Position = UDim2.new(0, 0, 0, 8),
        TextColor = Components.Colors.Warning,
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
            LeaderboardUI.CloseRequested:Fire()
        end,
        Parent = _mainFrame,
    })

    -- Player info section
    _playerInfoFrame = createPlayerInfo(_mainFrame)

    -- Leaderboard list
    local listContainer = Components.CreateFrame({
        Name = "ListContainer",
        Size = UDim2.new(1, -32, 1, -220),
        Position = UDim2.new(0.5, 0, 0, 195),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = _mainFrame,
    })

    _leaderboardContainer = Instance.new("ScrollingFrame")
    _leaderboardContainer.Name = "LeaderboardList"
    _leaderboardContainer.Size = UDim2.new(1, -8, 1, -8)
    _leaderboardContainer.Position = UDim2.new(0, 4, 0, 4)
    _leaderboardContainer.BackgroundTransparency = 1
    _leaderboardContainer.BorderSizePixel = 0
    _leaderboardContainer.ScrollBarThickness = 6
    _leaderboardContainer.ScrollBarImageColor3 = Components.Colors.Secondary
    _leaderboardContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    _leaderboardContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    _leaderboardContainer.Parent = listContainer

    local listLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 4),
        Parent = _leaderboardContainer,
    })

    -- Refresh button
    local refreshButton = Components.CreateButton({
        Name = "RefreshButton",
        Text = "Refresh",
        Size = UDim2.new(0, 100, 0, 36),
        Position = UDim2.new(0.5, 0, 1, -20),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = Components.Colors.Primary,
        OnClick = function()
            self:Refresh()
        end,
        Parent = _mainFrame,
    })

    -- Listen for league changes
    local Events = ReplicatedStorage:WaitForChild("Events")
    Events.LeagueChanged.OnClientEvent:Connect(function(data)
        -- Refresh if visible
        if self:IsVisible() then
            self:Refresh()
        end
    end)

    _initialized = true
    print("LeaderboardUI initialized")
end

return LeaderboardUI
