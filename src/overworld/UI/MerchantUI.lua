--!strict
--[[
    MerchantUI.lua

    Buy/sell interface for interacting with wandering merchants.
    Shows current merchant inventory with buy/sell options.
    Triggered by InteractMerchant server response.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local MerchantUI = {}
MerchantUI.__index = MerchantUI

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _player = Players.LocalPlayer
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _initialized = false
local _currentMerchantId: string? = nil

-- ============================================================================
-- UI CONSTRUCTION
-- ============================================================================

local function createUI()
    local playerGui = _player:WaitForChild("PlayerGui")

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MerchantUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 8
    screenGui.Parent = playerGui
    _screenGui = screenGui
end

local function showMerchantPanel(merchantId: string, inventory: any)
    if not _screenGui then return end

    -- Remove previous
    if _mainFrame then
        _mainFrame:Destroy()
        _mainFrame = nil
    end

    _currentMerchantId = merchantId

    local Events = ReplicatedStorage:FindFirstChild("Events")
    local MerchantTransaction = Events and Events:FindFirstChild("MerchantTransaction") :: RemoteEvent?

    -- Overlay
    local overlay = Instance.new("Frame")
    overlay.Name = "MerchantOverlay"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.6
    overlay.BorderSizePixel = 0
    overlay.Parent = _screenGui
    _mainFrame = overlay

    -- Panel
    local panel = Instance.new("Frame")
    panel.Name = "MerchantPanel"
    panel.Size = UDim2.new(0, 380, 0, 420)
    panel.Position = UDim2.new(0.5, -190, 0.5, -210)
    panel.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
    panel.BackgroundTransparency = 0.05
    panel.BorderSizePixel = 0
    panel.Parent = overlay

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = panel

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(50, 200, 50)
    stroke.Thickness = 2
    stroke.Parent = panel

    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 35)
    title.BackgroundTransparency = 1
    title.Text = "Merchant"
    title.TextColor3 = Color3.fromRGB(50, 220, 50)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = panel

    -- Buy section
    local buyTitle = Instance.new("TextLabel")
    buyTitle.Size = UDim2.new(1, 0, 0, 20)
    buyTitle.Position = UDim2.new(0, 0, 0, 40)
    buyTitle.BackgroundTransparency = 1
    buyTitle.Text = "BUY (Pay Gold)"
    buyTitle.TextColor3 = Color3.fromRGB(200, 200, 100)
    buyTitle.TextScaled = true
    buyTitle.Font = Enum.Font.GothamBold
    buyTitle.Parent = panel

    local yPos = 65
    if inventory and inventory.buy then
        for _, item in inventory.buy do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(0.9, 0, 0, 35)
            row.Position = UDim2.new(0.05, 0, 0, yPos)
            row.BackgroundColor3 = Color3.fromRGB(40, 35, 30)
            row.BorderSizePixel = 0
            row.Parent = panel

            local rowCorner = Instance.new("UICorner")
            rowCorner.CornerRadius = UDim.new(0, 4)
            rowCorner.Parent = row

            local itemLabel = Instance.new("TextLabel")
            itemLabel.Size = UDim2.new(0.55, 0, 1, 0)
            itemLabel.Position = UDim2.new(0.02, 0, 0, 0)
            itemLabel.BackgroundTransparency = 1
            itemLabel.Text = string.format("%s (%d)", item.displayName, item.amount)
            itemLabel.TextColor3 = Color3.new(1, 1, 1)
            itemLabel.TextScaled = true
            itemLabel.TextXAlignment = Enum.TextXAlignment.Left
            itemLabel.Font = Enum.Font.Gotham
            itemLabel.Parent = row

            local buyBtn = Instance.new("TextButton")
            buyBtn.Size = UDim2.new(0.35, 0, 0.8, 0)
            buyBtn.Position = UDim2.new(0.62, 0, 0.1, 0)
            buyBtn.BackgroundColor3 = Color3.fromRGB(50, 120, 50)
            buyBtn.Text = string.format("Buy (%dg)", item.baseGoldCost)
            buyBtn.TextColor3 = Color3.new(1, 1, 1)
            buyBtn.TextScaled = true
            buyBtn.Font = Enum.Font.GothamBold
            buyBtn.BorderSizePixel = 0
            buyBtn.Parent = row

            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, 4)
            btnCorner.Parent = buyBtn

            buyBtn.MouseButton1Click:Connect(function()
                if MerchantTransaction then
                    MerchantTransaction:FireServer({
                        merchantId = merchantId,
                        action = "buy",
                        itemId = item.id,
                        quantity = 1,
                    })
                end
            end)

            yPos += 40
        end
    end

    -- Sell section
    local sellTitle = Instance.new("TextLabel")
    sellTitle.Size = UDim2.new(1, 0, 0, 20)
    sellTitle.Position = UDim2.new(0, 0, 0, yPos + 5)
    sellTitle.BackgroundTransparency = 1
    sellTitle.Text = "SELL (Get Gold)"
    sellTitle.TextColor3 = Color3.fromRGB(200, 150, 100)
    sellTitle.TextScaled = true
    sellTitle.Font = Enum.Font.GothamBold
    sellTitle.Parent = panel

    yPos += 30
    if inventory and inventory.sell then
        for _, item in inventory.sell do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(0.9, 0, 0, 35)
            row.Position = UDim2.new(0.05, 0, 0, yPos)
            row.BackgroundColor3 = Color3.fromRGB(40, 35, 30)
            row.BorderSizePixel = 0
            row.Parent = panel

            local rowCorner = Instance.new("UICorner")
            rowCorner.CornerRadius = UDim.new(0, 4)
            rowCorner.Parent = row

            local itemLabel = Instance.new("TextLabel")
            itemLabel.Size = UDim2.new(0.55, 0, 1, 0)
            itemLabel.Position = UDim2.new(0.02, 0, 0, 0)
            itemLabel.BackgroundTransparency = 1
            itemLabel.Text = string.format("Sell %d %s", item.amount, item.resource)
            itemLabel.TextColor3 = Color3.new(1, 1, 1)
            itemLabel.TextScaled = true
            itemLabel.TextXAlignment = Enum.TextXAlignment.Left
            itemLabel.Font = Enum.Font.Gotham
            itemLabel.Parent = row

            local sellBtn = Instance.new("TextButton")
            sellBtn.Size = UDim2.new(0.35, 0, 0.8, 0)
            sellBtn.Position = UDim2.new(0.62, 0, 0.1, 0)
            sellBtn.BackgroundColor3 = Color3.fromRGB(120, 80, 30)
            sellBtn.Text = string.format("+%dg", item.goldReturn)
            sellBtn.TextColor3 = Color3.new(1, 1, 1)
            sellBtn.TextScaled = true
            sellBtn.Font = Enum.Font.GothamBold
            sellBtn.BorderSizePixel = 0
            sellBtn.Parent = row

            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, 4)
            btnCorner.Parent = sellBtn

            sellBtn.MouseButton1Click:Connect(function()
                if MerchantTransaction then
                    MerchantTransaction:FireServer({
                        merchantId = merchantId,
                        action = "sell",
                        itemId = item.id,
                        quantity = 1,
                    })
                end
            end)

            yPos += 40
        end
    end

    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0.3, 0, 0, 30)
    closeBtn.Position = UDim2.new(0.35, 0, 1, -40)
    closeBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
    closeBtn.Text = "Close"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.TextScaled = true
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = panel

    local closeBtnCorner = Instance.new("UICorner")
    closeBtnCorner.CornerRadius = UDim.new(0, 4)
    closeBtnCorner.Parent = closeBtn

    closeBtn.MouseButton1Click:Connect(function()
        if _mainFrame then
            _mainFrame:Destroy()
            _mainFrame = nil
        end
        _currentMerchantId = nil
    end)

    -- Resize panel to fit content
    panel.Size = UDim2.new(0, 380, 0, math.max(420, yPos + 50))
    panel.Position = UDim2.new(0.5, -190, 0.5, -math.max(420, yPos + 50) / 2)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function MerchantUI:Init()
    if _initialized then return end
    _initialized = true
    createUI()

    local Events = ReplicatedStorage:WaitForChild("Events")
    local ServerResponse = Events:WaitForChild("ServerResponse") :: RemoteEvent

    ServerResponse.OnClientEvent:Connect(function(eventName, data)
        if eventName == "InteractMerchant" and data.success and data.inventory then
            -- Find merchant ID from data (InteractMerchant handler sends it)
            showMerchantPanel(_currentMerchantId or "merchant_1", data.inventory)
        end
    end)
end

--[[
    Opens merchant UI for a specific merchant.
    Called from client proximity detection.
]]
function MerchantUI:RequestMerchant(merchantId: string)
    _currentMerchantId = merchantId
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if Events then
        local InteractMerchant = Events:FindFirstChild("InteractMerchant") :: RemoteEvent?
        if InteractMerchant then
            InteractMerchant:FireServer({ merchantId = merchantId })
        end
    end
end

function MerchantUI:Destroy()
    if _screenGui then
        _screenGui:Destroy()
        _screenGui = nil
    end
    _initialized = false
end

return MerchantUI
