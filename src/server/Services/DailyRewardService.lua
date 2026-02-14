--!strict
--[[
    DailyRewardService.lua

    Manages daily login rewards and streak bonuses.
    Encourages players to log in every day.

    SECURITY: All rewards are granted server-side.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declarations
local DataService

local DailyRewardService = {}
DailyRewardService.__index = DailyRewardService

-- Events
DailyRewardService.RewardClaimed = Signal.new()
DailyRewardService.StreakUpdated = Signal.new()

-- Private state
local _initialized = false

-- Reward schedule (7-day cycle) - All gold rewards
local DailyRewards = {
    [1] = { gold = 500, description = "Day 1: Gold" },
    [2] = { gold = 750, description = "Day 2: More Gold" },
    [3] = { gold = 1000, description = "Day 3: Gold Bonus" },
    [4] = { gold = 1500, description = "Day 4: Gold Boost" },
    [5] = { gold = 2000, wood = 500, description = "Day 5: Mixed Reward" },
    [6] = { gold = 2500, food = 500, description = "Day 6: Resource Bonus" },
    [7] = { gold = 5000, wood = 1000, food = 500, description = "Day 7: Weekly Jackpot!" },
}

-- Streak milestones (extra gold rewards)
local StreakMilestones = {
    [7] = { gold = 2500, description = "1 Week Streak!" },
    [14] = { gold = 5000, description = "2 Week Streak!" },
    [30] = { gold = 10000, description = "1 Month Streak!" },
    [60] = { gold = 25000, description = "2 Month Streak!" },
    [90] = { gold = 50000, description = "3 Month Streak!" },
    [180] = { gold = 100000, description = "6 Month Streak!" },
    [365] = { gold = 250000, description = "1 Year Streak!" },
}

--[[
    Gets the current day number.
]]
local function getDayNumber(): number
    return math.floor(os.time() / 86400)
end

--[[
    Gets the reward for a specific day in the cycle.
]]
local function getRewardForDay(cycleDay: number): {[string]: any}
    local dayInCycle = ((cycleDay - 1) % 7) + 1
    return DailyRewards[dayInCycle]
end

--[[
    Checks if player can claim daily reward.
]]
function DailyRewardService:CanClaim(player: Player): boolean
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return false end

    local today = getDayNumber()
    local lastClaim = playerData.dailyReward and playerData.dailyReward.lastClaimDay or 0

    return today > lastClaim
end

--[[
    Gets the current streak for a player.
]]
function DailyRewardService:GetStreak(player: Player): number
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return 0 end

    return playerData.dailyReward and playerData.dailyReward.streak or 0
end

--[[
    Gets daily reward info for a player.
]]
function DailyRewardService:GetRewardInfo(player: Player): {
    canClaim: boolean,
    streak: number,
    todayReward: any,
    streakMilestone: any?,
    nextMilestone: number?,
}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return {
            canClaim = false,
            streak = 0,
            todayReward = DailyRewards[1],
            streakMilestone = nil,
            nextMilestone = 7,
        }
    end

    local today = getDayNumber()
    local rewardData = playerData.dailyReward or { lastClaimDay = 0, streak = 0, totalClaims = 0 }

    local canClaim = today > rewardData.lastClaimDay
    local currentStreak = rewardData.streak

    -- If claiming today, streak would increase
    local projectedStreak = currentStreak
    if canClaim then
        local daysSinceLastClaim = today - rewardData.lastClaimDay
        if daysSinceLastClaim == 1 then
            projectedStreak = currentStreak + 1
        else
            projectedStreak = 1 -- Reset streak
        end
    end

    -- Get today's reward based on projected streak
    local todayReward = getRewardForDay(projectedStreak)

    -- Check for streak milestone
    local streakMilestone = StreakMilestones[projectedStreak]

    -- Find next milestone
    local nextMilestone = nil
    for milestone in StreakMilestones do
        if milestone > projectedStreak then
            if nextMilestone == nil or milestone < nextMilestone then
                nextMilestone = milestone
            end
        end
    end

    return {
        canClaim = canClaim,
        streak = projectedStreak,
        todayReward = todayReward,
        streakMilestone = streakMilestone,
        nextMilestone = nextMilestone,
    }
end

--[[
    Claims the daily reward for a player.
]]
function DailyRewardService:ClaimReward(player: Player): {
    success: boolean,
    reward: any?,
    streakBonus: any?,
    newStreak: number?,
    error: string?,
}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_DATA" }
    end

    local today = getDayNumber()
    local rewardData = playerData.dailyReward or { lastClaimDay = 0, streak = 0, totalClaims = 0 }

    -- Check if already claimed today
    if rewardData.lastClaimDay >= today then
        return { success = false, error = "ALREADY_CLAIMED" }
    end

    -- Calculate streak
    local daysSinceLastClaim = today - rewardData.lastClaimDay
    local newStreak = 1

    if daysSinceLastClaim == 1 then
        -- Consecutive day - increase streak
        newStreak = rewardData.streak + 1
    elseif daysSinceLastClaim == 0 then
        -- Same day (shouldn't happen due to check above)
        return { success = false, error = "ALREADY_CLAIMED" }
    else
        -- Streak broken - reset to 1
        newStreak = 1
    end

    -- Get reward for this day
    local reward = getRewardForDay(newStreak)

    -- Check for streak milestone
    local streakBonus = StreakMilestones[newStreak]

    -- Update player data
    rewardData.lastClaimDay = today
    rewardData.streak = newStreak
    rewardData.totalClaims = (rewardData.totalClaims or 0) + 1
    playerData.dailyReward = rewardData

    -- Grant rewards
    local totalReward = {}
    if reward.gold then totalReward.gold = reward.gold end
    if reward.gems then totalReward.gems = reward.gems end

    if streakBonus then
        if streakBonus.gold then
            totalReward.gold = (totalReward.gold or 0) + streakBonus.gold
        end
        if streakBonus.gems then
            totalReward.gems = (totalReward.gems or 0) + streakBonus.gems
        end
    end

    DataService:UpdateResources(player, totalReward :: any)

    -- Fire events
    DailyRewardService.RewardClaimed:Fire(player, reward, newStreak)
    DailyRewardService.StreakUpdated:Fire(player, newStreak)

    return {
        success = true,
        reward = reward,
        streakBonus = streakBonus,
        newStreak = newStreak,
    }
end

--[[
    Gets all available rewards in the cycle.
]]
function DailyRewardService:GetRewardCalendar(): {{[string]: any}}
    local calendar = {}
    for i = 1, 7 do
        table.insert(calendar, {
            day = i,
            reward = DailyRewards[i],
        })
    end
    return calendar
end

--[[
    Gets all streak milestones.
]]
function DailyRewardService:GetStreakMilestones(): {[number]: {[string]: any}}
    return StreakMilestones
end

--[[
    Initializes the DailyRewardService.
]]
function DailyRewardService:Init()
    if _initialized then
        warn("DailyRewardService already initialized")
        return
    end

    -- Get service references
    local ServerScriptService = game:GetService("ServerScriptService")
    DataService = require(ServerScriptService.Services.DataService)

    -- Notify players when they join if they can claim
    Players.PlayerAdded:Connect(function(player)
        task.defer(function()
            task.wait(3) -- Wait for data to load
            if self:CanClaim(player) then
                -- Could send notification to client
                print(string.format("[DailyReward] %s can claim daily reward!", player.Name))
            end
        end)
    end)

    _initialized = true
    print("DailyRewardService initialized")
end

return DailyRewardService
