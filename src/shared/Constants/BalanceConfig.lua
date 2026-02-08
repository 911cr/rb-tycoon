--!strict
--[[
    BalanceConfig.lua

    Global balance tuning values for Battle Tycoon: Conquest.
    Reference: docs/GAME_DESIGN_DOCUMENT.md Section 8

    IMPORTANT: Changes to this file affect entire game balance.
    Consult economy-designer and game-designer agents before modifications.
]]

local BalanceConfig = {}

--[[
    RESOURCE ECONOMY
]]
BalanceConfig.Economy = {
    -- Starting resources for new players
    StartingResources = {
        gold = 1000,
        wood = 1000,
        food = 500,
        gems = 50, -- Generous start to show gem value
    },

    -- Loot percentages
    Loot = {
        AvailablePercent = 0.20, -- 20% of stored resources available as loot
        TownHallBonus = 0.10, -- +10% if TH destroyed
        StorageProtection = 0.05, -- 5% of resources protected per storage level
    },

    -- VIP bonuses
    VIP = {
        ResourceProductionBonus = 0.20, -- +20%
        UpgradeTimeReduction = 0.20, -- -20%
        DailyGems = 50,
    },
}

--[[
    COMBAT BALANCE
]]
BalanceConfig.Combat = {
    -- Battle timing
    BattleDuration = 180, -- 3 minutes
    ScoutDuration = 30, -- 30 seconds

    -- Victory thresholds
    VictoryThresholds = {
        { destruction = 0, stars = 0, lootPercent = 0.10, name = "Defeat" },
        { destruction = 40, stars = 1, lootPercent = 0.40, name = "Minor Victory" },
        { destruction = 60, stars = 2, lootPercent = 0.60, name = "Major Victory" },
        { destruction = 80, stars = 2, lootPercent = 0.80, name = "Total Victory" },
        { destruction = 100, stars = 3, lootPercent = 1.00, name = "Conquest", takesCity = true },
    },

    -- Star conditions
    StarConditions = {
        DestructionForOneStar = 50, -- OR TH destroyed
        THDestroyedForOneStar = true,
        TwoStarsRequireTHAndDestruction = true, -- 50% AND TH
    },

    -- Shield durations (hours)
    ShieldDuration = {
        OneStar = 8,
        TwoStar = 12,
        ThreeStar = 16,
    },

    -- Revenge window (hours)
    RevengeWindow = 24,

    -- Trophy calculations
    Trophies = {
        BaseWin = 30,
        BaseLoss = 20,
        THDifferenceMultiplier = 1.2, -- More/fewer trophies for TH difference
    },
}

--[[
    MATCHMAKING
]]
BalanceConfig.Matchmaking = {
    -- Trophy range for matchmaking
    TrophyRange = {
        Min = 200, -- Search within 200 trophies at minimum
        Max = 500, -- Expand to 500 if no matches
    },

    -- TH level matching
    THRange = {
        Below = 2, -- Can attack up to 2 TH levels below
        Above = 1, -- Can attack up to 1 TH level above
    },

    -- Search cost
    NextSearchCost = 0, -- Free to search (encourage attacking)

    -- Timeout before widening search
    SearchWidenTimeout = 15, -- seconds
}

--[[
    PROGRESSION GATES
]]
BalanceConfig.Progression = {
    -- Town Hall gates max building levels
    THBuildingGates = {
        [1] = { maxBuildingLevel = 1, maxWallLevel = 1 },
        [2] = { maxBuildingLevel = 2, maxWallLevel = 2 },
        [3] = { maxBuildingLevel = 3, maxWallLevel = 3 },
        [4] = { maxBuildingLevel = 4, maxWallLevel = 4 },
        [5] = { maxBuildingLevel = 5, maxWallLevel = 5 },
        [6] = { maxBuildingLevel = 6, maxWallLevel = 6 },
        [7] = { maxBuildingLevel = 7, maxWallLevel = 7 },
        [8] = { maxBuildingLevel = 8, maxWallLevel = 8 },
        [9] = { maxBuildingLevel = 9, maxWallLevel = 9 },
        [10] = { maxBuildingLevel = 10, maxWallLevel = 10 },
    },

    -- Building counts per TH level
    BuildingCounts = {
        [1] = { GoldMine = 1, LumberMill = 1, Farm = 1, GoldStorage = 1, ArmyCamp = 1, Barracks = 1, Cannon = 2, Wall = 25 },
        [2] = { GoldMine = 2, LumberMill = 2, Farm = 2, GoldStorage = 1, ArmyCamp = 1, Barracks = 1, Cannon = 2, ArcherTower = 1, Wall = 50 },
        [3] = { GoldMine = 3, LumberMill = 3, Farm = 3, GoldStorage = 2, ArmyCamp = 2, Barracks = 2, Cannon = 2, ArcherTower = 2, Mortar = 1, Wall = 75 },
        [4] = { GoldMine = 4, LumberMill = 4, Farm = 4, GoldStorage = 2, ArmyCamp = 2, Barracks = 2, Cannon = 3, ArcherTower = 3, Mortar = 1, AirDefense = 1, Wall = 100 },
        [5] = { GoldMine = 5, LumberMill = 5, Farm = 5, GoldStorage = 2, ArmyCamp = 3, Barracks = 3, Cannon = 3, ArcherTower = 3, Mortar = 2, AirDefense = 1, WizardTower = 1, Wall = 125 },
        [6] = { GoldMine = 5, LumberMill = 5, Farm = 5, GoldStorage = 3, ArmyCamp = 3, Barracks = 3, Cannon = 4, ArcherTower = 4, Mortar = 2, AirDefense = 2, WizardTower = 2, Wall = 150 },
        [7] = { GoldMine = 6, LumberMill = 6, Farm = 6, GoldStorage = 3, ArmyCamp = 4, Barracks = 4, Cannon = 5, ArcherTower = 5, Mortar = 3, AirDefense = 2, WizardTower = 2, Wall = 175 },
        [8] = { GoldMine = 6, LumberMill = 6, Farm = 6, GoldStorage = 4, ArmyCamp = 4, Barracks = 4, Cannon = 5, ArcherTower = 5, Mortar = 3, AirDefense = 3, WizardTower = 3, Wall = 200 },
        [9] = { GoldMine = 6, LumberMill = 6, Farm = 6, GoldStorage = 4, ArmyCamp = 4, Barracks = 4, Cannon = 6, ArcherTower = 6, Mortar = 4, AirDefense = 3, WizardTower = 3, Wall = 225 },
        [10] = { GoldMine = 6, LumberMill = 6, Farm = 6, GoldStorage = 4, ArmyCamp = 4, Barracks = 4, Cannon = 6, ArcherTower = 6, Mortar = 4, AirDefense = 4, WizardTower = 4, Wall = 250 },
    },

    -- XP per action
    XPRewards = {
        BuildingUpgrade = 10, -- per level
        WallUpgrade = 1,
        TroopUpgrade = 20,
        SpellUpgrade = 20,
        BattleWin = 50,
        BattleLoss = 10,
    },

    -- Level XP requirements (cumulative)
    LevelXP = {
        [1] = 0,
        [2] = 30,
        [3] = 80,
        [4] = 150,
        [5] = 250,
        [6] = 400,
        [7] = 600,
        [8] = 900,
        [9] = 1300,
        [10] = 1800,
        -- ... continues
    },
}

--[[
    MONETIZATION
]]
BalanceConfig.Monetization = {
    -- Gem costs for time skips
    GemSkipRate = 1, -- 1 gem per minute (minimum 1)

    -- Gem packages (for reference - actual shop in MarketplaceService)
    GemPackages = {
        { name = "Handful", gems = 80, robux = 99 },
        { name = "Pouch", gems = 500, robux = 449 },
        { name = "Bag", gems = 1200, robux = 899 },
        { name = "Box", gems = 2500, robux = 1599 },
        { name = "Chest", gems = 6500, robux = 3399 },
        { name = "Vault", gems = 14000, robux = 5999 },
    },

    -- Battle Pass
    BattlePass = {
        SeasonLength = 28, -- days
        TotalTiers = 50,
        XPPerTier = 1000,
        PremiumCost = 450, -- robux
    },

    -- Builder costs
    BuilderCosts = {
        [2] = 0, -- Free with VIP
        [3] = 500, -- gems
        [4] = 1000,
        [5] = 2000,
    },
}

--[[
    SOCIAL / ALLIANCE
]]
BalanceConfig.Alliance = {
    -- Alliance size
    MaxMembers = 50,
    MinimumTHToJoin = 2,

    -- Donation limits per day
    DonationLimit = {
        Member = 5,
        Elder = 8,
        CoLeader = 10,
        Leader = 15,
    },

    -- Alliance War
    War = {
        PreparationHours = 24,
        BattleHours = 24,
        AttacksPerMember = 2,
    },

    -- Territory bonuses
    TerritoryBonus = {
        ResourceProduction = 0.05, -- +5% per territory
        TrophyGain = 0.02, -- +2% per territory
    },
}

--[[
    ENGAGEMENT TIMERS
]]
BalanceConfig.Engagement = {
    -- Daily login rewards reset
    DailyResetHourUTC = 0, -- Midnight UTC

    -- Session targets (for game-psychologist reference)
    TargetSessionLength = 15, -- minutes
    TargetSessionsPerDay = 3,

    -- Notification timings
    Notifications = {
        UpgradeComplete = true,
        TroopTrainingComplete = true,
        ArmyFull = true,
        StorageFull = true,
        ShieldExpiring = 1800, -- 30 minutes before
        AttackedWhileOffline = true,
    },
}

--[[
    RATE LIMITS (Anti-Exploit)
]]
BalanceConfig.RateLimits = {
    PlaceBuilding = 2, -- per second
    CollectResource = 10,
    DeployTroop = 20,
    UseSpell = 5,
    SendChat = 3,
    RequestData = 5,
}

return BalanceConfig
