--!strict
--[[
    AllianceUI.lua

    Alliance/Clan management interface.
    Shows alliance info, members, and donation requests.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(script.Parent.Components)
local ClientAPI = require(ReplicatedStorage.Shared.Modules.ClientAPI)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local AllianceUI = {}
AllianceUI.__index = AllianceUI

-- Events
AllianceUI.Closed = Signal.new()
AllianceUI.CreateRequested = Signal.new()
AllianceUI.SearchRequested = Signal.new()

-- Private state
local _player = Players.LocalPlayer
local _screenGui: ScreenGui
local _mainPanel: Frame
local _noAlliancePanel: Frame
local _alliancePanel: Frame
local _membersList: ScrollingFrame
local _isVisible = false
local _initialized = false
local _currentAlliance: any = nil

-- Tab state
local _currentTab = "Members"

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

--[[
    Creates a member row.
]]
local function createMemberRow(member: any, parent: GuiObject): Frame
    local row = Components.CreateFrame({
        Name = "Member_" .. member.userId,
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = parent,
    })

    -- Role badge
    local roleColors = {
        leader = Components.Colors.Warning,
        ["co-leader"] = Components.Colors.Primary,
        elder = Components.Colors.Secondary,
        member = Components.Colors.TextMuted,
    }

    local roleBadge = Components.CreateFrame({
        Name = "RoleBadge",
        Size = UDim2.new(0, 8, 0, 40),
        Position = UDim2.new(0, 4, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = roleColors[member.role] or Components.Colors.TextMuted,
        CornerRadius = Components.Sizes.CornerRadiusSmall,
        Parent = row,
    })

    -- Avatar placeholder
    local avatar = Components.CreateFrame({
        Name = "Avatar",
        Size = UDim2.new(0, 36, 0, 36),
        Position = UDim2.new(0, 20, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = Components.Colors.Primary,
        CornerRadius = UDim.new(0.5, 0),
        Parent = row,
    })

    local avatarLabel = Components.CreateLabel({
        Name = "Initial",
        Text = string.sub(member.username, 1, 1):upper(),
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = avatar,
    })

    -- Name and role
    local nameLabel = Components.CreateLabel({
        Name = "Name",
        Text = member.username,
        Size = UDim2.new(0.4, -60, 0, 20),
        Position = UDim2.new(0, 64, 0, 8),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeMedium,
        Font = Enum.Font.GothamMedium,
        Parent = row,
    })

    local roleLabel = Components.CreateLabel({
        Name = "Role",
        Text = member.role:gsub("^%l", string.upper),
        Size = UDim2.new(0.4, -60, 0, 16),
        Position = UDim2.new(0, 64, 0, 28),
        TextColor = roleColors[member.role] or Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = row,
    })

    -- Donations this week
    local donationsLabel = Components.CreateLabel({
        Name = "Donations",
        Text = "Donated: " .. formatNumber(member.donationsThisWeek or 0),
        Size = UDim2.new(0, 100, 0, 20),
        Position = UDim2.new(1, -108, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeSmall,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row,
    })

    return row
end

--[[
    Creates the "No Alliance" panel for players not in an alliance.
]]
local function createNoAlliancePanel(parent: Frame): Frame
    local panel = Components.CreateFrame({
        Name = "NoAlliance",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    -- Info text
    local infoLabel = Components.CreateLabel({
        Name = "Info",
        Text = "You are not in an alliance.\nJoin or create one to unlock:\n- Troop donations\n- Alliance wars\n- Chat with allies",
        Size = UDim2.new(1, -32, 0, 80),
        Position = UDim2.new(0, 16, 0, 20),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = panel,
    })
    infoLabel.TextWrapped = true

    -- Create button
    local createButton = Components.CreateButton({
        Name = "CreateButton",
        Text = "Create Alliance (10K Gold)",
        Size = UDim2.new(0.8, 0, 0, 50),
        Position = UDim2.new(0.5, 0, 0, 120),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.Secondary,
        OnClick = function()
            AllianceUI.CreateRequested:Fire()
        end,
        Parent = panel,
    })

    -- Search button
    local searchButton = Components.CreateButton({
        Name = "SearchButton",
        Text = "Search Alliances",
        Size = UDim2.new(0.8, 0, 0, 50),
        Position = UDim2.new(0.5, 0, 0, 180),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor = Components.Colors.Primary,
        OnClick = function()
            AllianceUI.SearchRequested:Fire()
        end,
        Parent = panel,
    })

    return panel
end

--[[
    Creates the alliance info panel for players in an alliance.
]]
local function createAlliancePanel(parent: Frame): Frame
    local panel = Components.CreateFrame({
        Name = "AllianceInfo",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    panel.Visible = false

    -- Alliance header
    local header = Components.CreateFrame({
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 70),
        BackgroundColor = Components.Colors.BackgroundLight,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = panel,
    })

    -- Alliance badge placeholder
    local badge = Components.CreateFrame({
        Name = "Badge",
        Size = UDim2.new(0, 50, 0, 50),
        Position = UDim2.new(0, 10, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor = Components.Colors.Primary,
        CornerRadius = Components.Sizes.CornerRadius,
        Parent = header,
    })

    local badgeLabel = Components.CreateLabel({
        Name = "BadgeText",
        Text = "A",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeXLarge,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = badge,
    })

    -- Alliance name
    local nameLabel = Components.CreateLabel({
        Name = "AllianceName",
        Text = "Alliance Name",
        Size = UDim2.new(1, -140, 0, 24),
        Position = UDim2.new(0, 70, 0, 12),
        TextColor = Components.Colors.TextPrimary,
        TextSize = Components.Sizes.FontSizeLarge,
        Font = Enum.Font.GothamBold,
        Parent = header,
    })

    -- Trophy count
    local trophyLabel = Components.CreateLabel({
        Name = "Trophies",
        Text = "0 Trophies",
        Size = UDim2.new(1, -140, 0, 18),
        Position = UDim2.new(0, 70, 0, 38),
        TextColor = Components.Colors.Warning,
        TextSize = Components.Sizes.FontSizeSmall,
        Parent = header,
    })

    -- Member count
    local memberCountLabel = Components.CreateLabel({
        Name = "MemberCount",
        Text = "0/50",
        Size = UDim2.new(0, 60, 0, 24),
        Position = UDim2.new(1, -10, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        TextColor = Components.Colors.TextSecondary,
        TextSize = Components.Sizes.FontSizeMedium,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = header,
    })

    -- Tab buttons
    local tabContainer = Components.CreateFrame({
        Name = "Tabs",
        Size = UDim2.new(1, 0, 0, 36),
        Position = UDim2.new(0, 0, 0, 78),
        BackgroundTransparency = 1,
        Parent = panel,
    })

    local tabLayout = Components.CreateListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 4),
        Parent = tabContainer,
    })

    local tabs = {"Members", "Requests", "Settings"}
    for _, tabName in tabs do
        local isActive = tabName == _currentTab
        local tabButton = Components.CreateButton({
            Name = tabName .. "Tab",
            Text = tabName,
            Size = UDim2.new(0, 90, 0, 30),
            BackgroundColor = isActive and Components.Colors.Primary or Components.Colors.BackgroundLight,
            TextSize = Components.Sizes.FontSizeSmall,
            CornerRadius = Components.Sizes.CornerRadiusSmall,
            Parent = tabContainer,
        })
    end

    -- Members list
    _membersList = Components.CreateScrollFrame({
        Name = "MembersList",
        Size = UDim2.new(1, 0, 1, -130),
        Position = UDim2.new(0, 0, 0, 120),
        Parent = panel,
    })

    local listLayout = Components.CreateListLayout({
        Padding = UDim.new(0, 4),
        Parent = _membersList,
    })

    -- Leave button
    local leaveButton = Components.CreateButton({
        Name = "LeaveButton",
        Text = "Leave Alliance",
        Size = UDim2.new(0, 140, 0, 36),
        Position = UDim2.new(0.5, 0, 1, -8),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor = Components.Colors.Danger,
        TextSize = Components.Sizes.FontSizeSmall,
        OnClick = function()
            ClientAPI.LeaveAlliance()
        end,
        Parent = panel,
    })

    return panel
end

--[[
    Updates the alliance display with current data.
]]
function AllianceUI:UpdateAlliance(allianceData: any?)
    _currentAlliance = allianceData

    if not allianceData then
        -- Show "no alliance" panel
        _noAlliancePanel.Visible = true
        _alliancePanel.Visible = false
        return
    end

    -- Show alliance panel
    _noAlliancePanel.Visible = false
    _alliancePanel.Visible = true

    -- Update header
    local header = _alliancePanel:FindFirstChild("Header") :: Frame
    local nameLabel = header:FindFirstChild("AllianceName") :: TextLabel
    local trophyLabel = header:FindFirstChild("Trophies") :: TextLabel
    local memberCountLabel = header:FindFirstChild("MemberCount") :: TextLabel
    local badgeLabel = header:FindFirstChild("Badge"):FindFirstChild("BadgeText") :: TextLabel

    nameLabel.Text = allianceData.name or "Alliance"
    trophyLabel.Text = formatNumber(allianceData.totalTrophies or 0) .. " Trophies"
    memberCountLabel.Text = string.format("%d/50", #(allianceData.members or {}))
    badgeLabel.Text = string.sub(allianceData.name or "A", 1, 1):upper()

    -- Update members list
    for _, child in _membersList:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    if allianceData.members then
        for _, member in allianceData.members do
            createMemberRow(member, _membersList)
        end
    end
end

--[[
    Shows the alliance UI.
]]
function AllianceUI:Show()
    if _isVisible then return end
    _isVisible = true

    -- Get current alliance data
    local playerData = ClientAPI.GetPlayerData()
    if playerData and playerData.alliance and playerData.alliance.allianceId then
        -- Would need to fetch alliance data here
        -- For now, show no alliance
        self:UpdateAlliance(nil)
    else
        self:UpdateAlliance(nil)
    end

    _screenGui.Enabled = true
    Components.SlideIn(_mainPanel, "right")
end

--[[
    Hides the alliance UI.
]]
function AllianceUI:Hide()
    if not _isVisible then return end
    _isVisible = false

    Components.SlideOut(_mainPanel, "right")
    task.delay(0.3, function()
        if not _isVisible then
            _screenGui.Enabled = false
        end
    end)

    AllianceUI.Closed:Fire()
end

--[[
    Toggles visibility.
]]
function AllianceUI:Toggle()
    if _isVisible then
        self:Hide()
    else
        self:Show()
    end
end

--[[
    Checks if visible.
]]
function AllianceUI:IsVisible(): boolean
    return _isVisible
end

--[[
    Initializes the AllianceUI.
]]
function AllianceUI:Init()
    if _initialized then
        warn("AllianceUI already initialized")
        return
    end

    local playerGui = _player:WaitForChild("PlayerGui")

    -- Create ScreenGui
    _screenGui = Instance.new("ScreenGui")
    _screenGui.Name = "AllianceUI"
    _screenGui.ResetOnSpawn = false
    _screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _screenGui.IgnoreGuiInset = true
    _screenGui.Enabled = false
    _screenGui.Parent = playerGui

    -- Background overlay
    local overlay = Components.CreateFrame({
        Name = "Overlay",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.5,
        Parent = _screenGui,
    })

    local overlayButton = Instance.new("TextButton")
    overlayButton.Size = UDim2.new(1, 0, 1, 0)
    overlayButton.BackgroundTransparency = 1
    overlayButton.Text = ""
    overlayButton.Parent = overlay
    overlayButton.MouseButton1Click:Connect(function()
        self:Hide()
    end)

    -- Main panel (slides from right)
    _mainPanel = Components.CreatePanel({
        Name = "AlliancePanel",
        Title = "Alliance",
        Size = UDim2.new(0, 340, 1, -100),
        Position = UDim2.new(1, -16, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        ShowCloseButton = true,
        OnClose = function()
            self:Hide()
        end,
        Parent = _screenGui,
    })

    local content = _mainPanel:FindFirstChild("Content") :: Frame

    -- Create sub-panels
    _noAlliancePanel = createNoAlliancePanel(content)
    _alliancePanel = createAlliancePanel(content)

    _initialized = true
    print("AllianceUI initialized")
end

return AllianceUI
