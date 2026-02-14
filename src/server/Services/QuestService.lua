--!strict
--[[
    QuestService.lua

    Manages daily quests and achievements for player progression.
    Provides goals and rewards to keep players engaged.

    SECURITY: All quest completion is validated server-side.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

-- Forward declarations
local DataService

local QuestService = {}
QuestService.__index = QuestService

-- Events
QuestService.QuestCompleted = Signal.new()
QuestService.QuestProgressUpdated = Signal.new()
QuestService.AchievementUnlocked = Signal.new()

-- Private state
local _initialized = false

-- Quest types
export type QuestType = "daily" | "weekly" | "achievement"

export type Quest = {
    id: string,
    type: QuestType,
    title: string,
    description: string,
    target: number,
    reward: { gold: number?, wood: number?, food: number?, xp: number? },
    trackingEvent: string, -- Event name to track
}

-- Daily Quest Templates (all gold rewards)
local DailyQuestTemplates: {Quest} = {
    {
        id = "daily_attack_3",
        type = "daily",
        title = "Battle Ready",
        description = "Attack 3 enemy bases",
        target = 3,
        reward = { gold = 3000 },
        trackingEvent = "battle_completed",
    },
    {
        id = "daily_win_1",
        type = "daily",
        title = "Victorious",
        description = "Win 1 battle with at least 1 star",
        target = 1,
        reward = { gold = 2000 },
        trackingEvent = "battle_won",
    },
    {
        id = "daily_collect_10k",
        type = "daily",
        title = "Gold Collector",
        description = "Collect 10,000 gold from mines",
        target = 10000,
        reward = { gold = 1500 },
        trackingEvent = "gold_collected",
    },
    {
        id = "daily_train_20",
        type = "daily",
        title = "Army Builder",
        description = "Train 20 troops",
        target = 20,
        reward = { gold = 2000 },
        trackingEvent = "troop_trained",
    },
    {
        id = "daily_upgrade_1",
        type = "daily",
        title = "Builder's Work",
        description = "Start 1 building upgrade",
        target = 1,
        reward = { gold = 1500 },
        trackingEvent = "upgrade_started",
    },
    {
        id = "daily_donate_5",
        type = "daily",
        title = "Generous Ally",
        description = "Donate 5 troops to alliance members",
        target = 5,
        reward = { gold = 1000 },
        trackingEvent = "troop_donated",
    },
    {
        id = "daily_3star_1",
        type = "daily",
        title = "Perfect Attack",
        description = "Get a 3-star victory",
        target = 1,
        reward = { gold = 5000 },
        trackingEvent = "three_star_win",
    },
    {
        id = "daily_destroy_defenses_10",
        type = "daily",
        title = "Defense Crusher",
        description = "Destroy 10 defensive buildings",
        target = 10,
        reward = { gold = 2500 },
        trackingEvent = "defense_destroyed",
    },
}

-- Achievement Templates (permanent) - All gold rewards
local AchievementTemplates: {Quest} = {
    -- Building achievements
    {
        id = "ach_th_5",
        type = "achievement",
        title = "Town Builder",
        description = "Upgrade Town Hall to level 5",
        target = 5,
        reward = { gold = 10000 },
        trackingEvent = "townhall_level",
    },
    {
        id = "ach_th_10",
        type = "achievement",
        title = "City Architect",
        description = "Upgrade Town Hall to level 10",
        target = 10,
        reward = { gold = 50000 },
        trackingEvent = "townhall_level",
    },
    -- Combat achievements
    {
        id = "ach_wins_50",
        type = "achievement",
        title = "Warrior",
        description = "Win 50 battles",
        target = 50,
        reward = { gold = 5000 },
        trackingEvent = "total_wins",
    },
    {
        id = "ach_wins_500",
        type = "achievement",
        title = "Conqueror",
        description = "Win 500 battles",
        target = 500,
        reward = { gold = 25000 },
        trackingEvent = "total_wins",
    },
    {
        id = "ach_3stars_100",
        type = "achievement",
        title = "Perfect Commander",
        description = "Get 100 three-star victories",
        target = 100,
        reward = { gold = 15000 },
        trackingEvent = "total_three_stars",
    },
    -- Trophy achievements
    {
        id = "ach_trophies_1000",
        type = "achievement",
        title = "Rising Champion",
        description = "Reach 1,000 trophies",
        target = 1000,
        reward = { gold = 10000 },
        trackingEvent = "trophies",
    },
    {
        id = "ach_trophies_3000",
        type = "achievement",
        title = "Elite Champion",
        description = "Reach 3,000 trophies",
        target = 3000,
        reward = { gold = 50000 },
        trackingEvent = "trophies",
    },
    -- Collection achievements
    {
        id = "ach_loot_1m",
        type = "achievement",
        title = "Treasure Hunter",
        description = "Loot 1,000,000 gold total",
        target = 1000000,
        reward = { gold = 25000 },
        trackingEvent = "total_gold_looted",
    },
    -- Alliance achievements
    {
        id = "ach_donations_100",
        type = "achievement",
        title = "Team Player",
        description = "Donate 100 troops",
        target = 100,
        reward = { gold = 5000 },
        trackingEvent = "total_donations",
    },
}

--[[
    Gets the current day number (for daily reset).
]]
local function getDayNumber(): number
    return math.floor(os.time() / 86400)
end

--[[
    Selects daily quests for a player.
]]
local function selectDailyQuests(count: number): {Quest}
    local selected = {}
    local available = table.clone(DailyQuestTemplates)

    for i = 1, math.min(count, #available) do
        local index = math.random(1, #available)
        table.insert(selected, available[index])
        table.remove(available, index)
    end

    return selected
end

--[[
    Gets or creates daily quests for a player.
]]
function QuestService:GetDailyQuests(player: Player): {[string]: {quest: Quest, progress: number, completed: boolean}}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return {} end

    local today = getDayNumber()
    local questData = playerData.dailyQuests or {}

    -- Check if quests need refresh
    if questData.day ~= today then
        -- Generate new daily quests
        local newQuests = selectDailyQuests(3)
        questData = {
            day = today,
            quests = {},
        }

        for _, quest in newQuests do
            questData.quests[quest.id] = {
                progress = 0,
                completed = false,
                claimed = false,
            }
        end

        playerData.dailyQuests = questData
    end

    -- Build result with quest definitions
    local result = {}
    for questId, progress in questData.quests do
        -- Find quest template
        for _, template in DailyQuestTemplates do
            if template.id == questId then
                result[questId] = {
                    quest = template,
                    progress = progress.progress,
                    completed = progress.completed,
                    claimed = progress.claimed,
                }
                break
            end
        end
    end

    return result
end

--[[
    Gets achievements for a player.
]]
function QuestService:GetAchievements(player: Player): {[string]: {quest: Quest, progress: number, completed: boolean}}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return {} end

    local achievements = playerData.achievements or {}
    local result = {}

    for _, template in AchievementTemplates do
        local achData = achievements[template.id] or { progress = 0, completed = false, claimed = false }

        result[template.id] = {
            quest = template,
            progress = achData.progress,
            completed = achData.completed,
            claimed = achData.claimed,
        }
    end

    return result
end

--[[
    Tracks progress for an event.
]]
function QuestService:TrackEvent(player: Player, eventName: string, amount: number?)
    local playerData = DataService:GetPlayerData(player)
    if not playerData then return end

    amount = amount or 1

    -- Track daily quests
    local dailyQuests = playerData.dailyQuests
    if dailyQuests and dailyQuests.quests then
        for questId, progress in dailyQuests.quests do
            if progress.completed then continue end

            -- Find matching template
            for _, template in DailyQuestTemplates do
                if template.id == questId and template.trackingEvent == eventName then
                    progress.progress = (progress.progress or 0) + amount

                    -- Check completion
                    if progress.progress >= template.target then
                        progress.completed = true
                        QuestService.QuestCompleted:Fire(player, template)
                    else
                        QuestService.QuestProgressUpdated:Fire(player, questId, progress.progress, template.target)
                    end
                    break
                end
            end
        end
    end

    -- Track achievements
    local achievements = playerData.achievements or {}
    playerData.achievements = achievements

    for _, template in AchievementTemplates do
        if template.trackingEvent == eventName then
            local achData = achievements[template.id] or { progress = 0, completed = false, claimed = false }
            achievements[template.id] = achData

            if achData.completed then continue end

            achData.progress = (achData.progress or 0) + amount

            -- Check completion
            if achData.progress >= template.target then
                achData.completed = true
                QuestService.AchievementUnlocked:Fire(player, template)
            end
        end
    end
end

--[[
    Claims reward for a completed quest.
]]
function QuestService:ClaimReward(player: Player, questId: string): {success: boolean, reward: any?, error: string?}
    local playerData = DataService:GetPlayerData(player)
    if not playerData then
        return { success = false, error = "NO_DATA" }
    end

    -- Check daily quests
    local dailyQuests = playerData.dailyQuests
    if dailyQuests and dailyQuests.quests and dailyQuests.quests[questId] then
        local progress = dailyQuests.quests[questId]

        if not progress.completed then
            return { success = false, error = "NOT_COMPLETED" }
        end
        if progress.claimed then
            return { success = false, error = "ALREADY_CLAIMED" }
        end

        -- Find template
        local template = nil
        for _, t in DailyQuestTemplates do
            if t.id == questId then
                template = t
                break
            end
        end

        if not template then
            return { success = false, error = "INVALID_QUEST" }
        end

        -- Grant reward
        progress.claimed = true
        DataService:UpdateResources(player, template.reward :: any)

        return { success = true, reward = template.reward }
    end

    -- Check achievements
    local achievements = playerData.achievements or {}
    if achievements[questId] then
        local achData = achievements[questId]

        if not achData.completed then
            return { success = false, error = "NOT_COMPLETED" }
        end
        if achData.claimed then
            return { success = false, error = "ALREADY_CLAIMED" }
        end

        -- Find template
        local template = nil
        for _, t in AchievementTemplates do
            if t.id == questId then
                template = t
                break
            end
        end

        if not template then
            return { success = false, error = "INVALID_QUEST" }
        end

        -- Grant reward
        achData.claimed = true
        DataService:UpdateResources(player, template.reward :: any)

        return { success = true, reward = template.reward }
    end

    return { success = false, error = "QUEST_NOT_FOUND" }
end

--[[
    Initializes the QuestService.
]]
function QuestService:Init()
    if _initialized then
        warn("QuestService already initialized")
        return
    end

    -- Get service references
    local ServerScriptService = game:GetService("ServerScriptService")
    DataService = require(ServerScriptService.Services.DataService)

    _initialized = true
    print("QuestService initialized")
end

return QuestService
