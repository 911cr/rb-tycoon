--!strict
--[[
    MerchantData.lua

    Defines wandering merchant configurations for the overworld.
    2 merchants active at a time, walking between waypoints.
    Buy resources at 1.2x rate, sell at 0.6x rate (gold as currency).
    Inventory rotates every 30 minutes.

    IMPORTANT: Changes to this file affect game balance.
    Consult economy-designer agent before modifications.
]]

local MerchantData = {}

-- ============================================================================
-- MERCHANT ROUTES
-- ============================================================================

MerchantData.Merchants = {
    {
        id = "merchant_1",
        name = "Traveling Trader",
        description = "A wandering merchant with supplies from distant lands.",
        waypoints = {
            { x = 700, z = 500 },
            { x = 900, z = 600 },
            { x = 1100, z = 700 },
            { x = 1300, z = 600 },
            { x = 1100, z = 500 },
        },
        appearance = {
            bodyColor = Color3.fromRGB(80, 100, 140),
            headColor = Color3.fromRGB(200, 170, 140),
            hatColor = Color3.fromRGB(140, 50, 50),
        },
    },
    {
        id = "merchant_2",
        name = "Resource Peddler",
        description = "A shrewd dealer specializing in bulk resource trades.",
        waypoints = {
            { x = 800, z = 1200 },
            { x = 1000, z = 1300 },
            { x = 1200, z = 1400 },
            { x = 1000, z = 1500 },
            { x = 800, z = 1400 },
        },
        appearance = {
            bodyColor = Color3.fromRGB(100, 80, 50),
            headColor = Color3.fromRGB(190, 160, 130),
            hatColor = Color3.fromRGB(50, 100, 50),
        },
    },
}

-- ============================================================================
-- INVENTORY POOLS (items rotate from these pools)
-- ============================================================================

MerchantData.InventoryPools = {
    -- Resources that can be bought (player pays gold)
    Buy = {
        {
            id = "buy_wood_small",
            displayName = "Wood Bundle (Small)",
            resource = "wood",
            amount = 200,
            baseGoldCost = 240, -- 1.2x value
        },
        {
            id = "buy_wood_large",
            displayName = "Wood Bundle (Large)",
            resource = "wood",
            amount = 500,
            baseGoldCost = 600,
        },
        {
            id = "buy_food_small",
            displayName = "Food Crate (Small)",
            resource = "food",
            amount = 150,
            baseGoldCost = 180,
        },
        {
            id = "buy_food_large",
            displayName = "Food Crate (Large)",
            resource = "food",
            amount = 400,
            baseGoldCost = 480,
        },
        {
            id = "buy_gold_boost",
            displayName = "Gold Ingot",
            resource = "gold",
            amount = 500,
            baseGoldCost = 600,
        },
    },

    -- Resources that can be sold (player gets gold)
    Sell = {
        {
            id = "sell_wood",
            displayName = "Sell Wood",
            resource = "wood",
            amount = 100,
            goldReturn = 60, -- 0.6x value
        },
        {
            id = "sell_food",
            displayName = "Sell Food",
            resource = "food",
            amount = 100,
            goldReturn = 60,
        },
        {
            id = "sell_wood_bulk",
            displayName = "Sell Wood (Bulk)",
            resource = "wood",
            amount = 500,
            goldReturn = 300,
        },
        {
            id = "sell_food_bulk",
            displayName = "Sell Food (Bulk)",
            resource = "food",
            amount = 500,
            goldReturn = 300,
        },
    },
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

function MerchantData.GetMerchantById(id: string): any?
    for _, merchant in MerchantData.Merchants do
        if merchant.id == id then
            return merchant
        end
    end
    return nil
end

--[[
    Generates a random inventory selection for a merchant rotation.
    Picks 3 buy items and 2 sell items from the pools.
    @return {buy: {any}, sell: {any}}
]]
function MerchantData.GenerateInventory(): {buy: {any}, sell: {any}}
    local buyPool = table.clone(MerchantData.InventoryPools.Buy)
    local sellPool = table.clone(MerchantData.InventoryPools.Sell)

    -- Shuffle buy pool
    for i = #buyPool, 2, -1 do
        local j = math.random(1, i)
        buyPool[i], buyPool[j] = buyPool[j], buyPool[i]
    end

    -- Shuffle sell pool
    for i = #sellPool, 2, -1 do
        local j = math.random(1, i)
        sellPool[i], sellPool[j] = sellPool[j], sellPool[i]
    end

    local buy = {}
    for i = 1, math.min(3, #buyPool) do
        table.insert(buy, buyPool[i])
    end

    local sell = {}
    for i = 1, math.min(2, #sellPool) do
        table.insert(sell, sellPool[i])
    end

    return { buy = buy, sell = sell }
end

function MerchantData.GetBuyItem(itemId: string): any?
    for _, item in MerchantData.InventoryPools.Buy do
        if item.id == itemId then return item end
    end
    return nil
end

function MerchantData.GetSellItem(itemId: string): any?
    for _, item in MerchantData.InventoryPools.Sell do
        if item.id == itemId then return item end
    end
    return nil
end

return MerchantData
