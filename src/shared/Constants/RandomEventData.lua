--!strict
--[[
    RandomEventData.lua

    Defines server-wide random event types for the overworld.
    One event active at a time, lasting 10-30 minutes.
    Events trigger every 30-60 minutes.

    IMPORTANT: Changes to this file affect game balance.
    Consult game-designer agent before modifications.
]]

local RandomEventData = {}

-- ============================================================================
-- EVENT TYPES
-- ============================================================================

RandomEventData.Events = {
    {
        id = "gold_rush",
        name = "Gold Rush",
        description = "All gold rewards are doubled!",
        icon = "rbxassetid://0", -- placeholder
        color = Color3.fromRGB(255, 200, 50),
        effects = {
            goldMultiplier = 2.0,
            woodMultiplier = 1.0,
            foodMultiplier = 1.0,
        },
    },
    {
        id = "bandit_invasion",
        name = "Bandit Invasion",
        description = "Double bandit spawns with 50% more loot!",
        icon = "rbxassetid://0",
        color = Color3.fromRGB(200, 50, 50),
        effects = {
            banditSpawnMultiplier = 2.0,
            banditLootMultiplier = 1.5,
        },
    },
    {
        id = "merchant_festival",
        name = "Merchant Festival",
        description = "Better merchant prices! Buy at base rate, sell at 80%!",
        icon = "rbxassetid://0",
        color = Color3.fromRGB(50, 200, 50),
        effects = {
            merchantBuyRate = 1.0,  -- normally 1.2x
            merchantSellRate = 0.8, -- normally 0.6x
        },
    },
    {
        id = "forbidden_mist",
        name = "Forbidden Mist",
        description = "The Forbidden Zone's power weakens. Enemies are easier!",
        icon = "rbxassetid://0",
        color = Color3.fromRGB(150, 100, 200),
        effects = {
            forbiddenStatMultiplier = 1.5, -- normally 2.5x
        },
    },
}

-- ============================================================================
-- HELPERS
-- ============================================================================

function RandomEventData.GetEventById(id: string): any?
    for _, event in RandomEventData.Events do
        if event.id == id then
            return event
        end
    end
    return nil
end

function RandomEventData.GetAllEvents(): {any}
    return RandomEventData.Events
end

--[[
    Picks a random event.
    @return table - Random event definition
]]
function RandomEventData.PickRandomEvent(): any
    return RandomEventData.Events[math.random(1, #RandomEventData.Events)]
end

return RandomEventData
