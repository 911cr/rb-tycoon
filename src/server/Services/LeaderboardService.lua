--!strict
--[[
    LeaderboardService.lua

    Manages trophy leagues, player rankings, and seasonal rewards.
    Provides global and alliance-based leaderboards.

    SECURITY: All rankings are computed server-side.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declarations
local DataService

local LeaderboardService = {}
LeaderboardService.__index = LeaderboardService

-- Events
LeaderboardService.LeagueChanged = Signal.new()
LeaderboardService.RankUpdated = Signal.new()
LeaderboardService.SeasonEnded = Signal.new()

-- Private state
local _initialized = false
local _globalLeaderboard: OrderedDataStore? = nil
local _leaderboardCache: {any} = {}
local _cacheTime = 0
local _cacheDuration = 60 -- Refresh cache every 60 seconds

-- League definitions
export type League = {
    id: string,
    name: string,
    minTrophies: number,
    maxTrophies: number?,
    icon: string,
    winBonus: number, -- Extra trophies for winning
    loseProtection: number, -- Reduce trophy loss
    lootBonus: number, -- Percentage bonus to loot
    leagueBonus: {gold: number, gems: number}?, -- Daily/season bonus
}

local Leagues: {League} = {
    {
        id = "unranked",
        name = "Unranked",
        minTrophies = 0,
        maxTrophies = 399,
        icon = "None",
        winBonus = 0,
        loseProtection = 0,
        lootBonus = 0,
    },
    {
        id = "bronze_3",
        name = "Bronze III",
        minTrophies = 400,
        maxTrophies = 499,
        icon = "Bronze",
        winBonus = 0,
        loseProtection = 0,
        lootBonus = 0,
    },
    {
        id = "bronze_2",
        name = "Bronze II",
        minTrophies = 500,
        maxTrophies = 599,
        icon = "Bronze",
        winBonus = 0,
        loseProtection = 0,
        lootBonus = 0,
    },
    {
        id = "bronze_1",
        name = "Bronze I",
        minTrophies = 600,
        maxTrophies = 799,
        icon = "Bronze",
        winBonus = 1,
        loseProtection = 0,
        lootBonus = 5,
    },
    {
        id = "silver_3",
        name = "Silver III",
        minTrophies = 800,
        maxTrophies = 999,
        icon = "Silver",
        winBonus = 1,
        loseProtection = 1,
        lootBonus = 10,
        leagueBonus = { gold = 1000, gems = 0 },
    },
    {
        id = "silver_2",
        name = "Silver II",
        minTrophies = 1000,
        maxTrophies = 1199,
        icon = "Silver",
        winBonus = 2,
        loseProtection = 1,
        lootBonus = 15,
        leagueBonus = { gold = 2500, gems = 0 },
    },
    {
        id = "silver_1",
        name = "Silver I",
        minTrophies = 1200,
        maxTrophies = 1399,
        icon = "Silver",
        winBonus = 2,
        loseProtection = 2,
        lootBonus = 20,
        leagueBonus = { gold = 5000, gems = 0 },
    },
    {
        id = "gold_3",
        name = "Gold III",
        minTrophies = 1400,
        maxTrophies = 1599,
        icon = "Gold",
        winBonus = 3,
        loseProtection = 2,
        lootBonus = 25,
        leagueBonus = { gold = 10000, gems = 0 },
    },
    {
        id = "gold_2",
        name = "Gold II",
        minTrophies = 1600,
        maxTrophies = 1799,
        icon = "Gold",
        winBonus = 3,
        loseProtection = 3,
        lootBonus = 30,
        leagueBonus = { gold = 25000, gems = 5 },
    },
    {
        id = "gold_1",
        name = "Gold I",
        minTrophies = 1800,
        maxTrophies = 1999,
        icon = "Gold",
        winBonus = 4,
        loseProtection = 3,
        lootBonus = 35,
        leagueBonus = { gold = 50000, gems = 10 },
    },
    {
        id = "crystal_3",
        name = "Crystal III",
        minTrophies = 2000,
        maxTrophies = 2199,
        icon = "Crystal",
        winBonus = 4,
        loseProtection = 4,
        lootBonus = 40,
        leagueBonus = { gold = 75000, gems = 20 },
    },
    {
        id = "crystal_2",
        name = "Crystal II",
        minTrophies = 2200,
        maxTrophies = 2399,
        icon = "Crystal",
        winBonus = 5,
        loseProtection = 4,
        lootBonus = 45,
        leagueBonus = { gold = 100000, gems = 30 },
    },
    {
        id = "crystal_1",
        name = "Crystal I",
        minTrophies = 2400,
        maxTrophies = 2599,
        icon = "Crystal",
        winBonus = 5,
        loseProtection = 5,
        lootBonus = 50,
        leagueBonus = { gold = 125000, gems = 50 },
    },
    {
        id = "master_3",
        name = "Master III",
        minTrophies = 2600,
        maxTrophies = 2799,
        icon = "Master",
        winBonus = 6,
        loseProtection = 5,
        lootBonus = 55,
        leagueBonus = { gold = 150000, gems = 75 },
    },
    {
        id = "master_2",
        name = "Master II",
        minTrophies = 2800,
        maxTrophies = 2999,
        icon = "Master",
        winBonus = 6,
        loseProtection = 6,
        lootBonus = 60,
        leagueBonus = { gold = 175000, gems = 100 },
    },
    {
        id = "master_1",
        name = "Master I",
        minTrophies = 3000,
        maxTrophies = 3199,
        icon = "Master",
        winBonus = 7,
        loseProtection = 6,
        lootBonus = 65,
        leagueBonus = { gold = 200000, gems = 125 },
    },
    {
        id = "champion_3",
        name = "Champion III",
        minTrophies = 3200,
        maxTrophies = 3499,
        icon = "Champion",
        winBonus = 7,
        loseProtection = 7,
        lootBonus = 70,
        leagueBonus = { gold = 250000, gems = 150 },
    },
    {
        id = "champion_2",
        name = "Champion II",
        minTrophies = 3500,
        maxTrophies = 3799,
        icon = "Champion",
        winBonus = 8,
        loseProtection = 7,
        lootBonus = 75,
        leagueBonus = { gold = 300000, gems = 200 },
    },
    {
        id = "champion_1",
        name = "Champion I",
        minTrophies = 3800,
        maxTrophies = 4099,
        icon = "Champion",
        winBonus = 8,
        loseProtection = 8,
        lootBonus = 80,
        leagueBonus = { gold = 350000, gems = 250 },
    },
    {
        id = "titan_3",
        name = "Titan III",
        minTrophies = 4100,
        maxTrophies = 4399,
        icon = "Titan",
        winBonus = 9,
        loseProtection = 8,
        lootBonus = 85,
        leagueBonus = { gold = 400000, gems = 300 },
    },
    {
        id = "titan_2",
        name = "Titan II",
        minTrophies = 4400,
        maxTrophies = 4699,
        icon = "Titan",
        winBonus = 9,
        loseProtection = 9,
        lootBonus = 90,
        leagueBonus = { gold = 450000, gems = 350 },
    },
    {
        id = "titan_1",
        name = "Titan I",
        minTrophies = 4700,
        maxTrophies = 4999,
        icon = "Titan",
        winBonus = 10,
        loseProtection = 9,
        lootBonus = 95,
        leagueBonus = { gold = 500000, gems = 400 },
    },
    {
        id = "legend",
        name = "Legend",
        minTrophies = 5000,
        maxTrophies = nil, -- No max
        icon = "Legend",
        winBonus = 10,
        loseProtection = 10,
        lootBonus = 100,
        leagueBonus = { gold = 600000, gems = 500 },
    },
}

--[[
    Gets the league for a trophy count.
]]
function LeaderboardService:GetLeague(trophies: number): League
    for i = #Leagues, 1, -1 do
        if trophies >= Leagues[i].minTrophies then
            return Leagues[i]
        end
    end
    return Leagues[1]
end

--[[
    Gets all league definitions.
]]
function LeaderboardService:GetAllLeagues(): {League}
    return Leagues
end

--[[
    Gets the player's current league.
]]
function LeaderboardService:GetPlayerLeague(player: Player): League
    local playerData = DataService:GetPlayerData(player)
    if not playerData or not playerData.trophies then
        return Leagues[1]
    end

    return self:GetLeague(playerData.trophies.current or 0)
end

--[[
    Updates a player's trophies and checks for league changes.
]]
function LeaderboardService:UpdateTrophies(player: Player, trophyChange: number): {
    newTrophies: number,
    oldLeague: League?,
    newLeague: League?,
    leagueChanged: boolean,
}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { newTrophies = 0, leagueChanged = false }
    end

    playerData.trophies = playerData.trophies or { current = 0, best = 0, seasonBest = 0 }

    local oldTrophies = playerData.trophies.current or 0
    local oldLeague = self:GetLeague(oldTrophies)

    -- Apply trophy change with league protection
    local actualChange = trophyChange
    if trophyChange < 0 then
        -- Apply lose protection
        actualChange = math.max(trophyChange, -math.abs(trophyChange) + oldLeague.loseProtection)
    elseif trophyChange > 0 then
        -- Apply win bonus
        actualChange = trophyChange + oldLeague.winBonus
    end

    local newTrophies = math.max(0, oldTrophies + actualChange)
    playerData.trophies.current = newTrophies

    -- Update best trophy records
    if newTrophies > (playerData.trophies.best or 0) then
        playerData.trophies.best = newTrophies
    end
    if newTrophies > (playerData.trophies.seasonBest or 0) then
        playerData.trophies.seasonBest = newTrophies
    end

    local newLeague = self:GetLeague(newTrophies)
    local leagueChanged = oldLeague.id ~= newLeague.id

    -- Update global leaderboard
    self:UpdateGlobalRank(player, newTrophies)

    if leagueChanged then
        LeaderboardService.LeagueChanged:Fire(player, oldLeague, newLeague)
    end

    LeaderboardService.RankUpdated:Fire(player, newTrophies)

    return {
        newTrophies = newTrophies,
        oldLeague = oldLeague,
        newLeague = newLeague,
        leagueChanged = leagueChanged,
    }
end

--[[
    Updates a player's rank in the global leaderboard.
]]
function LeaderboardService:UpdateGlobalRank(player: Player, trophies: number)
    if not _globalLeaderboard then return end

    local success, err = pcall(function()
        _globalLeaderboard:SetAsync(tostring(player.UserId), trophies)
    end)

    if not success then
        warn("[Leaderboard] Failed to update global rank:", err)
    end
end

--[[
    Gets the top players from the global leaderboard.
]]
function LeaderboardService:GetTopPlayers(count: number?): {{rank: number, userId: number, trophies: number, username: string}}
    count = count or 100

    -- Check cache
    local now = os.time()
    if now - _cacheTime < _cacheDuration and #_leaderboardCache > 0 then
        local result = {}
        for i = 1, math.min(count, #_leaderboardCache) do
            table.insert(result, _leaderboardCache[i])
        end
        return result
    end

    -- Fetch from DataStore
    local result = {}

    if _globalLeaderboard then
        local success, pages = pcall(function()
            return _globalLeaderboard:GetSortedAsync(false, count)
        end)

        if success and pages then
            local data = pages:GetCurrentPage()
            for rank, entry in data do
                local userId = tonumber(entry.key) or 0
                local username = "Unknown"

                -- Try to get username
                local nameSuccess, name = pcall(function()
                    return Players:GetNameFromUserIdAsync(userId)
                end)
                if nameSuccess then
                    username = name
                end

                table.insert(result, {
                    rank = rank,
                    userId = userId,
                    trophies = entry.value,
                    username = username,
                })
            end
        end
    end

    -- Update cache
    _leaderboardCache = result
    _cacheTime = now

    return result
end

--[[
    Gets a player's global rank.
]]
function LeaderboardService:GetPlayerRank(player: Player): number?
    if not _globalLeaderboard then return nil end

    local success, rank = pcall(function()
        return _globalLeaderboard:GetRankAsync(tostring(player.UserId))
    end)

    if success then
        return rank
    end
    return nil
end

--[[
    Gets leaderboard info for a player.
]]
function LeaderboardService:GetLeaderboardInfo(player: Player): {
    trophies: number,
    best: number,
    seasonBest: number,
    league: League,
    rank: number?,
}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return {
            trophies = 0,
            best = 0,
            seasonBest = 0,
            league = Leagues[1],
            rank = nil,
        }
    end

    local trophies = playerData.trophies or { current = 0, best = 0, seasonBest = 0 }

    return {
        trophies = trophies.current or 0,
        best = trophies.best or 0,
        seasonBest = trophies.seasonBest or 0,
        league = self:GetLeague(trophies.current or 0),
        rank = self:GetPlayerRank(player),
    }
end

--[[
    Processes season end rewards.
]]
function LeaderboardService:ProcessSeasonEnd()
    -- This would be called at the end of each season
    -- Grant league bonuses based on season best

    for _, player in Players:GetPlayers() do
        local playerData = DataService:GetPlayerData(player)
        if playerData and playerData.trophies then
            local seasonBest = playerData.trophies.seasonBest or 0
            local league = self:GetLeague(seasonBest)

            if league.leagueBonus then
                DataService:UpdateResources(player, league.leagueBonus :: any)

                LeaderboardService.SeasonEnded:Fire(player, league, league.leagueBonus)
            end

            -- Reset season best
            playerData.trophies.seasonBest = playerData.trophies.current or 0
        end
    end

    print("[Leaderboard] Season ended, rewards distributed")
end

--[[
    Initializes the LeaderboardService.
]]
function LeaderboardService:Init()
    if _initialized then
        warn("LeaderboardService already initialized")
        return
    end

    -- Get service references
    local ServerScriptService = game:GetService("ServerScriptService")
    DataService = require(ServerScriptService.Services.DataService)

    -- Initialize global leaderboard
    local success, leaderboard = pcall(function()
        return DataStoreService:GetOrderedDataStore("GlobalTrophyLeaderboard")
    end)

    if success then
        _globalLeaderboard = leaderboard
        print("[Leaderboard] Global leaderboard initialized")
    else
        warn("[Leaderboard] Failed to initialize global leaderboard:", leaderboard)
    end

    -- Update leaderboard for players when they join
    Players.PlayerAdded:Connect(function(player)
        task.defer(function()
            task.wait(5) -- Wait for data to load
            local playerData = DataService:GetPlayerData(player)
            if playerData and playerData.trophies then
                self:UpdateGlobalRank(player, playerData.trophies.current or 0)
            end
        end)
    end)

    _initialized = true
    print("LeaderboardService initialized")
end

return LeaderboardService
