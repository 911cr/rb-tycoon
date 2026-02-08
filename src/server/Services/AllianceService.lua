--!strict
--[[
    AllianceService.lua

    Manages alliance/clan systems, membership, and troop donations.
    All operations are server-authoritative.

    SECURITY:
    - All alliance operations validated server-side
    - Permissions checked for role-based actions
    - Rate limiting on donations
    - Alliance data stored separately from player data

    Dependencies:
    - DataService (for player data)
    - TroopService (for donation troop management)

    Events:
    - AllianceCreated(creatorId, allianceId, name)
    - PlayerJoined(playerId, allianceId)
    - PlayerLeft(playerId, allianceId)
    - TroopDonated(donorId, recipientId, troopType, count)
    - RoleChanged(playerId, allianceId, newRole)
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TroopData = require(ReplicatedStorage.Shared.Constants.TroopData)
local BalanceConfig = require(ReplicatedStorage.Shared.Constants.BalanceConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declarations
local DataService
local TroopService

local AllianceService = {}
AllianceService.__index = AllianceService

-- Events
AllianceService.AllianceCreated = Signal.new()
AllianceService.PlayerJoined = Signal.new()
AllianceService.PlayerLeft = Signal.new()
AllianceService.TroopDonated = Signal.new()
AllianceService.RoleChanged = Signal.new()

-- Private state
local _alliances: {[string]: AllianceData} = {} -- Cache of loaded alliances
local _allianceStore = DataStoreService:GetDataStore("BattleTycoon_Alliances_v1")
local _initialized = false

-- Constants
local MAX_ALLIANCE_NAME_LENGTH = 20
local MIN_ALLIANCE_NAME_LENGTH = 3
local MAX_DESCRIPTION_LENGTH = 200
local ALLIANCE_CREATION_COST = { gold = 10000 }

-- Types
type AllianceRole = "leader" | "co-leader" | "elder" | "member"

type AllianceMember = {
    userId: number,
    username: string,
    role: AllianceRole,
    joinedAt: number,
    donationsThisWeek: number,
    donationsReceived: number,
    lastActiveAt: number,
}

type PendingRequest = {
    userId: number,
    username: string,
    requestedAt: number,
    message: string?,
}

type AllianceData = {
    id: string,
    name: string,
    description: string,
    badge: string?, -- Badge icon ID
    createdAt: number,
    createdBy: number,

    -- Membership
    members: {AllianceMember},
    pendingRequests: {PendingRequest},

    -- Settings
    joinType: string, -- "open" | "invite" | "closed"
    minTownHallLevel: number,
    minTrophies: number,

    -- Stats
    totalTrophies: number,
    totalDonations: number,
    warsWon: number,
    warsLost: number,
}

type CreateResult = {
    success: boolean,
    allianceId: string?,
    error: string?,
}

type JoinResult = {
    success: boolean,
    error: string?,
}

type DonateResult = {
    success: boolean,
    donated: number?,
    error: string?,
}

--[[
    Validates an alliance name.
]]
local function isValidAllianceName(name: string): (boolean, string?)
    if typeof(name) ~= "string" then
        return false, "INVALID_NAME_TYPE"
    end

    -- Length check
    if #name < MIN_ALLIANCE_NAME_LENGTH then
        return false, "NAME_TOO_SHORT"
    end
    if #name > MAX_ALLIANCE_NAME_LENGTH then
        return false, "NAME_TOO_LONG"
    end

    -- Alphanumeric and spaces only
    if not name:match("^[%w%s]+$") then
        return false, "NAME_INVALID_CHARS"
    end

    -- No leading/trailing spaces
    if name:match("^%s") or name:match("%s$") then
        return false, "NAME_INVALID_SPACES"
    end

    return true, nil
end

--[[
    Gets the role hierarchy level (higher = more permissions).
]]
local function getRoleLevel(role: AllianceRole): number
    local levels = {
        member = 1,
        elder = 2,
        ["co-leader"] = 3,
        leader = 4,
    }
    return levels[role] or 0
end

--[[
    Checks if a role can perform an action on another role.
]]
local function canActOnRole(actorRole: AllianceRole, targetRole: AllianceRole): boolean
    return getRoleLevel(actorRole) > getRoleLevel(targetRole)
end

--[[
    Gets the donation limit for a role.
]]
local function getDonationLimit(role: AllianceRole): number
    local limits = BalanceConfig.Alliance.DonationLimit
    if role == "leader" then
        return limits.Leader
    elseif role == "co-leader" then
        return limits.CoLeader
    elseif role == "elder" then
        return limits.Elder
    end
    return limits.Member
end

--[[
    Loads an alliance from DataStore.
]]
local function loadAlliance(allianceId: string): AllianceData?
    -- Check cache first
    if _alliances[allianceId] then
        return _alliances[allianceId]
    end

    -- Load from DataStore
    local success, result = pcall(function()
        return _allianceStore:GetAsync(allianceId)
    end)

    if success and result then
        _alliances[allianceId] = result
        return result
    end

    return nil
end

--[[
    Saves an alliance to DataStore.
]]
local function saveAlliance(alliance: AllianceData): boolean
    local success = pcall(function()
        _allianceStore:SetAsync(alliance.id, alliance)
    end)

    if success then
        _alliances[alliance.id] = alliance
    end

    return success
end

--[[
    Finds a member in an alliance.
]]
local function findMember(alliance: AllianceData, userId: number): (AllianceMember?, number?)
    for i, member in alliance.members do
        if member.userId == userId then
            return member, i
        end
    end
    return nil, nil
end

--[[
    Creates a new alliance.
]]
function AllianceService:CreateAlliance(player: Player, name: string, description: string): CreateResult
    -- Validate player
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, allianceId = nil, error = "NO_PLAYER_DATA" }
    end

    -- Check player isn't already in an alliance
    if playerData.alliance.allianceId then
        return { success = false, allianceId = nil, error = "ALREADY_IN_ALLIANCE" }
    end

    -- Check TH requirement
    if playerData.townHallLevel < BalanceConfig.Alliance.MinimumTHToJoin then
        return { success = false, allianceId = nil, error = "TH_TOO_LOW" }
    end

    -- Validate name
    local nameValid, nameError = isValidAllianceName(name)
    if not nameValid then
        return { success = false, allianceId = nil, error = nameError }
    end

    -- Validate description
    if typeof(description) ~= "string" then
        description = ""
    end
    description = description:sub(1, MAX_DESCRIPTION_LENGTH)

    -- Check creation cost
    if not DataService:CanAfford(player, ALLIANCE_CREATION_COST :: any) then
        return { success = false, allianceId = nil, error = "INSUFFICIENT_RESOURCES" }
    end

    -- Deduct cost
    DataService:DeductResources(player, ALLIANCE_CREATION_COST :: any)

    -- Generate alliance ID
    local allianceId = HttpService:GenerateGUID(false)
    local now = os.time()

    -- Create alliance
    local alliance: AllianceData = {
        id = allianceId,
        name = name,
        description = description,
        badge = nil,
        createdAt = now,
        createdBy = player.UserId,

        members = {
            {
                userId = player.UserId,
                username = player.Name,
                role = "leader",
                joinedAt = now,
                donationsThisWeek = 0,
                donationsReceived = 0,
                lastActiveAt = now,
            },
        },
        pendingRequests = {},

        joinType = "open",
        minTownHallLevel = 1,
        minTrophies = 0,

        totalTrophies = playerData.trophies.current,
        totalDonations = 0,
        warsWon = 0,
        warsLost = 0,
    }

    -- Save alliance
    if not saveAlliance(alliance) then
        -- Refund cost on failure
        DataService:UpdateResources(player, ALLIANCE_CREATION_COST :: any)
        return { success = false, allianceId = nil, error = "SAVE_FAILED" }
    end

    -- Update player data
    playerData.alliance = {
        allianceId = allianceId,
        role = "leader",
        joinedAt = now,
        donationsThisWeek = 0,
        donationsReceived = 0,
    }

    -- Fire event
    AllianceService.AllianceCreated:Fire(player.UserId, allianceId, name)

    return { success = true, allianceId = allianceId, error = nil }
end

--[[
    Requests to join an alliance.
]]
function AllianceService:JoinAlliance(player: Player, allianceId: string): JoinResult
    -- Validate player
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_PLAYER_DATA" }
    end

    -- Check player isn't already in an alliance
    if playerData.alliance.allianceId then
        return { success = false, error = "ALREADY_IN_ALLIANCE" }
    end

    -- Check TH requirement
    if playerData.townHallLevel < BalanceConfig.Alliance.MinimumTHToJoin then
        return { success = false, error = "TH_TOO_LOW" }
    end

    -- Validate alliance ID
    if typeof(allianceId) ~= "string" then
        return { success = false, error = "INVALID_ALLIANCE_ID" }
    end

    -- Load alliance
    local alliance = loadAlliance(allianceId)
    if not alliance then
        return { success = false, error = "ALLIANCE_NOT_FOUND" }
    end

    -- Check max members
    if #alliance.members >= BalanceConfig.Alliance.MaxMembers then
        return { success = false, error = "ALLIANCE_FULL" }
    end

    -- Check join requirements
    if playerData.townHallLevel < alliance.minTownHallLevel then
        return { success = false, error = "TH_TOO_LOW_FOR_ALLIANCE" }
    end

    if playerData.trophies.current < alliance.minTrophies then
        return { success = false, error = "TROPHIES_TOO_LOW" }
    end

    local now = os.time()

    -- Handle based on join type
    if alliance.joinType == "closed" then
        return { success = false, error = "ALLIANCE_CLOSED" }
    elseif alliance.joinType == "invite" then
        -- Add to pending requests
        -- Check if already pending
        for _, request in alliance.pendingRequests do
            if request.userId == player.UserId then
                return { success = false, error = "ALREADY_PENDING" }
            end
        end

        table.insert(alliance.pendingRequests, {
            userId = player.UserId,
            username = player.Name,
            requestedAt = now,
            message = nil,
        })

        saveAlliance(alliance)

        return { success = true, error = "REQUEST_PENDING" }
    end

    -- Open join - add directly
    local newMember: AllianceMember = {
        userId = player.UserId,
        username = player.Name,
        role = "member",
        joinedAt = now,
        donationsThisWeek = 0,
        donationsReceived = 0,
        lastActiveAt = now,
    }

    table.insert(alliance.members, newMember)
    alliance.totalTrophies += playerData.trophies.current

    -- Save alliance
    if not saveAlliance(alliance) then
        return { success = false, error = "SAVE_FAILED" }
    end

    -- Update player data
    playerData.alliance = {
        allianceId = allianceId,
        role = "member",
        joinedAt = now,
        donationsThisWeek = 0,
        donationsReceived = 0,
    }

    -- Fire event
    AllianceService.PlayerJoined:Fire(player.UserId, allianceId)

    return { success = true, error = nil }
end

--[[
    Leaves the current alliance.
]]
function AllianceService:LeaveAlliance(player: Player): JoinResult
    -- Validate player
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_PLAYER_DATA" }
    end

    -- Check player is in an alliance
    local allianceId = playerData.alliance.allianceId
    if not allianceId then
        return { success = false, error = "NOT_IN_ALLIANCE" }
    end

    -- Load alliance
    local alliance = loadAlliance(allianceId)
    if not alliance then
        -- Alliance doesn't exist, just clear player data
        playerData.alliance = {
            allianceId = nil,
            role = nil,
            joinedAt = nil,
            donationsThisWeek = 0,
            donationsReceived = 0,
        }
        return { success = true, error = nil }
    end

    -- Find member
    local member, memberIndex = findMember(alliance, player.UserId)
    if not member or not memberIndex then
        -- Not in alliance, just clear player data
        playerData.alliance = {
            allianceId = nil,
            role = nil,
            joinedAt = nil,
            donationsThisWeek = 0,
            donationsReceived = 0,
        }
        return { success = true, error = nil }
    end

    -- Check if leader is leaving
    if member.role == "leader" then
        -- Must transfer leadership or disband
        if #alliance.members > 1 then
            -- Find highest ranking member to promote
            local nextLeader: AllianceMember? = nil
            local nextLeaderIndex: number? = nil
            local highestRank = 0

            for i, m in alliance.members do
                if m.userId ~= player.UserId then
                    local rank = getRoleLevel(m.role)
                    if rank > highestRank then
                        highestRank = rank
                        nextLeader = m
                        nextLeaderIndex = i
                    end
                end
            end

            if nextLeader and nextLeaderIndex then
                nextLeader.role = "leader"

                -- Fire role change event
                local nextLeaderPlayer = Players:GetPlayerByUserId(nextLeader.userId)
                if nextLeaderPlayer then
                    local nextPlayerData = DataService:GetPlayerData(nextLeaderPlayer)
                    if nextPlayerData then
                        nextPlayerData.alliance.role = "leader"
                    end
                end

                AllianceService.RoleChanged:Fire(nextLeader.userId, allianceId, "leader")
            end
        else
            -- Last member, disband alliance
            pcall(function()
                _allianceStore:RemoveAsync(allianceId)
            end)
            _alliances[allianceId] = nil
        end
    end

    -- Remove from alliance
    table.remove(alliance.members, memberIndex)
    alliance.totalTrophies -= playerData.trophies.current

    -- Save alliance (if it still exists)
    if #alliance.members > 0 then
        saveAlliance(alliance)
    end

    -- Update player data
    playerData.alliance = {
        allianceId = nil,
        role = nil,
        joinedAt = nil,
        donationsThisWeek = 0,
        donationsReceived = 0,
    }

    -- Fire event
    AllianceService.PlayerLeft:Fire(player.UserId, allianceId)

    return { success = true, error = nil }
end

--[[
    Donates troops to another player in the same alliance.
]]
function AllianceService:DonateTroops(
    player: Player,
    targetUserId: number,
    troopType: string,
    count: number
): DonateResult
    -- Validate player
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, donated = nil, error = "NO_PLAYER_DATA" }
    end

    -- Check player is in an alliance
    local allianceId = playerData.alliance.allianceId
    if not allianceId then
        return { success = false, donated = nil, error = "NOT_IN_ALLIANCE" }
    end

    -- Validate inputs
    if typeof(targetUserId) ~= "number" then
        return { success = false, donated = nil, error = "INVALID_TARGET" }
    end

    if typeof(troopType) ~= "string" then
        return { success = false, donated = nil, error = "INVALID_TROOP_TYPE" }
    end

    if typeof(count) ~= "number" or count <= 0 or count ~= math.floor(count) then
        return { success = false, donated = nil, error = "INVALID_COUNT" }
    end

    count = math.min(count, 10) -- Cap at 10 per donation

    -- Can't donate to self
    if targetUserId == player.UserId then
        return { success = false, donated = nil, error = "CANNOT_DONATE_TO_SELF" }
    end

    -- Validate troop type
    local troopDef = TroopData.GetByType(troopType)
    if not troopDef then
        return { success = false, donated = nil, error = "INVALID_TROOP_TYPE" }
    end

    -- Load alliance
    local alliance = loadAlliance(allianceId)
    if not alliance then
        return { success = false, donated = nil, error = "ALLIANCE_NOT_FOUND" }
    end

    -- Find donor member
    local donorMember = findMember(alliance, player.UserId)
    if not donorMember then
        return { success = false, donated = nil, error = "NOT_IN_ALLIANCE" }
    end

    -- Find target member
    local targetMember = findMember(alliance, targetUserId)
    if not targetMember then
        return { success = false, donated = nil, error = "TARGET_NOT_IN_ALLIANCE" }
    end

    -- Check donation limit
    local limit = getDonationLimit(donorMember.role)
    if donorMember.donationsThisWeek >= limit then
        return { success = false, donated = nil, error = "DONATION_LIMIT_REACHED" }
    end

    local canDonate = math.min(count, limit - donorMember.donationsThisWeek)

    -- Check player has troops
    local available = TroopService:GetAvailableTroops(player)
    if not available[troopType] or available[troopType] < canDonate then
        canDonate = available[troopType] or 0
    end

    if canDonate <= 0 then
        return { success = false, donated = nil, error = "NO_TROOPS_TO_DONATE" }
    end

    -- Consume troops from donor
    if not TroopService:ConsumeTroops(player, troopType, canDonate) then
        return { success = false, donated = nil, error = "CONSUME_FAILED" }
    end

    -- Add troops to target
    local targetPlayer = Players:GetPlayerByUserId(targetUserId)
    if targetPlayer then
        local targetData = DataService:GetPlayerData(targetPlayer)
        if targetData then
            targetData.troops[troopType] = (targetData.troops[troopType] or 0) + canDonate
        end
    else
        -- Target is offline, load their data
        local targetData = DataService:GetPlayerDataById(targetUserId)
        if targetData then
            targetData.troops[troopType] = (targetData.troops[troopType] or 0) + canDonate
            -- Note: Data will be saved to DataStore
        end
    end

    -- Update donation stats
    donorMember.donationsThisWeek += canDonate
    targetMember.donationsReceived += canDonate
    alliance.totalDonations += canDonate

    playerData.alliance.donationsThisWeek += canDonate

    -- Save alliance
    saveAlliance(alliance)

    -- Fire event
    AllianceService.TroopDonated:Fire(player.UserId, targetUserId, troopType, canDonate)

    return { success = true, donated = canDonate, error = nil }
end

--[[
    Gets alliance data by ID.
]]
function AllianceService:GetAlliance(allianceId: string): AllianceData?
    if typeof(allianceId) ~= "string" then return nil end
    return loadAlliance(allianceId)
end

--[[
    Gets the alliance for a player.
]]
function AllianceService:GetPlayerAlliance(player: Player): AllianceData?
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return nil end

    local allianceId = playerData.alliance.allianceId
    if not allianceId then return nil end

    return loadAlliance(allianceId)
end

--[[
    Promotes a member to a higher role.
]]
function AllianceService:PromoteMember(player: Player, targetUserId: number): JoinResult
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_PLAYER_DATA" }
    end

    local allianceId = playerData.alliance.allianceId
    if not allianceId then
        return { success = false, error = "NOT_IN_ALLIANCE" }
    end

    local alliance = loadAlliance(allianceId)
    if not alliance then
        return { success = false, error = "ALLIANCE_NOT_FOUND" }
    end

    local actorMember = findMember(alliance, player.UserId)
    if not actorMember then
        return { success = false, error = "NOT_IN_ALLIANCE" }
    end

    local targetMember = findMember(alliance, targetUserId)
    if not targetMember then
        return { success = false, error = "TARGET_NOT_IN_ALLIANCE" }
    end

    -- Check actor can promote target
    if not canActOnRole(actorMember.role, targetMember.role) then
        return { success = false, error = "INSUFFICIENT_PERMISSIONS" }
    end

    -- Promote
    local promotions: {[AllianceRole]: AllianceRole} = {
        member = "elder",
        elder = "co-leader",
    }

    local newRole = promotions[targetMember.role]
    if not newRole then
        return { success = false, error = "CANNOT_PROMOTE_FURTHER" }
    end

    -- Can't promote to leader
    if newRole == "leader" then
        return { success = false, error = "CANNOT_PROMOTE_TO_LEADER" }
    end

    -- Check actor has permission for new role
    if getRoleLevel(actorMember.role) <= getRoleLevel(newRole) then
        return { success = false, error = "INSUFFICIENT_PERMISSIONS" }
    end

    targetMember.role = newRole

    -- Update target player data if online
    local targetPlayer = Players:GetPlayerByUserId(targetUserId)
    if targetPlayer then
        local targetData = DataService:GetPlayerData(targetPlayer)
        if targetData then
            targetData.alliance.role = newRole
        end
    end

    saveAlliance(alliance)

    AllianceService.RoleChanged:Fire(targetUserId, allianceId, newRole)

    return { success = true, error = nil }
end

--[[
    Demotes a member to a lower role.
]]
function AllianceService:DemoteMember(player: Player, targetUserId: number): JoinResult
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_PLAYER_DATA" }
    end

    local allianceId = playerData.alliance.allianceId
    if not allianceId then
        return { success = false, error = "NOT_IN_ALLIANCE" }
    end

    local alliance = loadAlliance(allianceId)
    if not alliance then
        return { success = false, error = "ALLIANCE_NOT_FOUND" }
    end

    local actorMember = findMember(alliance, player.UserId)
    if not actorMember then
        return { success = false, error = "NOT_IN_ALLIANCE" }
    end

    local targetMember = findMember(alliance, targetUserId)
    if not targetMember then
        return { success = false, error = "TARGET_NOT_IN_ALLIANCE" }
    end

    -- Check actor can demote target
    if not canActOnRole(actorMember.role, targetMember.role) then
        return { success = false, error = "INSUFFICIENT_PERMISSIONS" }
    end

    -- Demote
    local demotions: {[AllianceRole]: AllianceRole} = {
        ["co-leader"] = "elder",
        elder = "member",
    }

    local newRole = demotions[targetMember.role]
    if not newRole then
        return { success = false, error = "CANNOT_DEMOTE_FURTHER" }
    end

    targetMember.role = newRole

    -- Update target player data if online
    local targetPlayer = Players:GetPlayerByUserId(targetUserId)
    if targetPlayer then
        local targetData = DataService:GetPlayerData(targetPlayer)
        if targetData then
            targetData.alliance.role = newRole
        end
    end

    saveAlliance(alliance)

    AllianceService.RoleChanged:Fire(targetUserId, allianceId, newRole)

    return { success = true, error = nil }
end

--[[
    Kicks a member from the alliance.
]]
function AllianceService:KickMember(player: Player, targetUserId: number): JoinResult
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_PLAYER_DATA" }
    end

    local allianceId = playerData.alliance.allianceId
    if not allianceId then
        return { success = false, error = "NOT_IN_ALLIANCE" }
    end

    local alliance = loadAlliance(allianceId)
    if not alliance then
        return { success = false, error = "ALLIANCE_NOT_FOUND" }
    end

    local actorMember = findMember(alliance, player.UserId)
    if not actorMember then
        return { success = false, error = "NOT_IN_ALLIANCE" }
    end

    local targetMember, targetIndex = findMember(alliance, targetUserId)
    if not targetMember or not targetIndex then
        return { success = false, error = "TARGET_NOT_IN_ALLIANCE" }
    end

    -- Check actor can kick target
    if not canActOnRole(actorMember.role, targetMember.role) then
        return { success = false, error = "INSUFFICIENT_PERMISSIONS" }
    end

    -- Remove from alliance
    table.remove(alliance.members, targetIndex)

    -- Update target player data if online
    local targetPlayer = Players:GetPlayerByUserId(targetUserId)
    if targetPlayer then
        local targetData = DataService:GetPlayerData(targetPlayer)
        if targetData then
            alliance.totalTrophies -= targetData.trophies.current
            targetData.alliance = {
                allianceId = nil,
                role = nil,
                joinedAt = nil,
                donationsThisWeek = 0,
                donationsReceived = 0,
            }
        end
    end

    saveAlliance(alliance)

    AllianceService.PlayerLeft:Fire(targetUserId, allianceId)

    return { success = true, error = nil }
end

--[[
    Initializes the AllianceService.
]]
function AllianceService:Init()
    if _initialized then
        warn("AllianceService already initialized")
        return
    end

    -- Get service references
    local ServerScriptService = game:GetService("ServerScriptService")
    DataService = require(ServerScriptService.Services.DataService)
    TroopService = require(ServerScriptService.Services.TroopService)

    -- Weekly donation reset (runs at midnight Sunday UTC)
    task.spawn(function()
        while true do
            -- Wait until next Sunday midnight UTC
            local now = os.time()
            local date = os.date("!*t", now)
            local daysUntilSunday = (7 - date.wday) % 7
            if daysUntilSunday == 0 and date.hour >= 0 then
                daysUntilSunday = 7 -- Next Sunday
            end

            local nextReset = now + (daysUntilSunday * 86400) + ((24 - date.hour) * 3600) - (date.min * 60) - date.sec
            local waitTime = nextReset - now

            task.wait(math.min(waitTime, 3600)) -- Check every hour max

            -- Reset donations if it's time
            if os.time() >= nextReset then
                for _, alliance in _alliances do
                    for _, member in alliance.members do
                        member.donationsThisWeek = 0
                    end
                    saveAlliance(alliance)
                end

                -- Also update online players
                for _, player in Players:GetPlayers() do
                    local pData = DataService:GetPlayerData(player)
                    if pData then
                        pData.alliance.donationsThisWeek = 0
                    end
                end
            end
        end
    end)

    _initialized = true
    print("AllianceService initialized")
end

return AllianceService
