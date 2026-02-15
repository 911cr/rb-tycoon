--!strict
--[[
    TeleportManager.lua

    Handles TeleportService operations for transitions between places:
    - Overworld -> Village (entering own base)
    - Village -> Overworld (exiting village)
    - Overworld -> Battle (attacking)

    Manages teleport data persistence and retry logic.
]]

local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for shared modules
repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local TeleportManager = {}
TeleportManager.__index = TeleportManager

-- ============================================================================
-- SIGNALS
-- ============================================================================

TeleportManager.TeleportStarted = Signal.new()
TeleportManager.TeleportCompleted = Signal.new()
TeleportManager.TeleportFailed = Signal.new()

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _initialized = false
local _pendingTeleports: {[number]: {
    player: Player,
    destination: string,
    placeId: number,
    startTime: number,
    retryCount: number,
}} = {}

-- Reference to DataService
local _dataService: any = nil

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Gets the DataService if available.
]]
local function getDataService(): any
    if _dataService then return _dataService end

    local ServerScriptService = game:GetService("ServerScriptService")
    local servicesFolder = ServerScriptService:FindFirstChild("Services")

    if servicesFolder then
        local dataServiceModule = servicesFolder:FindFirstChild("DataService")
        if dataServiceModule then
            _dataService = require(dataServiceModule)
        end
    end

    return _dataService
end

--[[
    Prepares player data for teleport (saves data + releases session lock).
    This MUST happen before TeleportAsync to prevent SESSION_LOCKED errors
    on the destination server.
]]
local function preparePlayerForTeleport(player: Player): boolean
    local dataService = getDataService()

    if dataService then
        -- Use PrepareForTeleport if available (saves + releases lock)
        if dataService.PrepareForTeleport then
            local success, prepResult = pcall(function()
                return dataService:PrepareForTeleport(player)
            end)

            if not success then
                warn(string.format("[TeleportManager] Failed to prepare teleport for %s: %s",
                    player.Name, tostring(prepResult)))
                return false
            end

            -- PrepareForTeleport returns false if save failed
            if not prepResult then
                warn(string.format("[TeleportManager] PrepareForTeleport returned false for %s (save failed)",
                    player.Name))
                return false
            end

            return true
        end

        -- Fallback: just save (old behavior)
        if dataService.SavePlayerData then
            local success, err = pcall(function()
                dataService:SavePlayerData(player)
            end)

            if not success then
                warn(string.format("[TeleportManager] Failed to save data for %s: %s",
                    player.Name, tostring(err)))
                return false
            end

            return true
        end
    end

    return true -- No DataService, assume success
end

--[[
    Creates teleport data package.
]]
local function createTeleportData(
    source: string,
    player: Player,
    returnPosition: Vector3?,
    targetBaseId: number?
): {[string]: any}
    return {
        [OverworldConfig.Teleport.DataKeys.Source] = source,
        [OverworldConfig.Teleport.DataKeys.PlayerId] = player.UserId,
        [OverworldConfig.Teleport.DataKeys.ReturnPosition] = returnPosition and {
            X = returnPosition.X,
            Y = returnPosition.Y,
            Z = returnPosition.Z,
        } or nil,
        [OverworldConfig.Teleport.DataKeys.Timestamp] = os.time(),
        [OverworldConfig.Teleport.DataKeys.TargetBase] = targetBaseId,
    }
end

--[[
    Performs teleport with retry logic.
]]
local function performTeleport(
    player: Player,
    placeId: number,
    teleportData: {[string]: any},
    destination: string
): (boolean, string?)
    local config = OverworldConfig.Teleport
    local userId = player.UserId

    -- Track pending teleport
    _pendingTeleports[userId] = {
        player = player,
        destination = destination,
        placeId = placeId,
        startTime = os.time(),
        retryCount = 0,
    }

    -- Fire started event
    TeleportManager.TeleportStarted:Fire(player, destination)

    -- Attempt teleport with retries
    for attempt = 1, config.MaxRetries do
        local success, result = pcall(function()
            local teleportOptions = Instance.new("TeleportOptions")
            teleportOptions:SetTeleportData(teleportData)

            return TeleportService:TeleportAsync(placeId, {player}, teleportOptions)
        end)

        if success then
            _pendingTeleports[userId] = nil
            TeleportManager.TeleportCompleted:Fire(player, destination)
            return true
        else
            warn(string.format("[TeleportManager] Teleport attempt %d failed for %s: %s",
                attempt, player.Name, tostring(result)))

            _pendingTeleports[userId].retryCount = attempt

            if attempt < config.MaxRetries then
                task.wait(config.RetryDelay)
            end
        end
    end

    -- All retries failed
    _pendingTeleports[userId] = nil
    TeleportManager.TeleportFailed:Fire(player, destination, "MAX_RETRIES_EXCEEDED")

    return false, "MAX_RETRIES_EXCEEDED"
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Initializes the TeleportManager.
]]
function TeleportManager:Init()
    if _initialized then
        warn("[TeleportManager] Already initialized")
        return
    end

    -- Handle teleport init data for arriving players
    TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
        warn(string.format("[TeleportManager] Teleport init failed for %s: %s - %s",
            player.Name, tostring(teleportResult), errorMessage))
    end)

    _initialized = true
    print("[TeleportManager] Initialized")
end

--[[
    Ensures a player has a village access code (reserved server).
    Called on first join so other players can always visit their base.

    @param player Player - The player
    @return boolean - True if access code exists or was created
]]
function TeleportManager:EnsureVillageAccessCode(player: Player): boolean
    local config = OverworldConfig.Teleport
    if config.VillagePlaceId == 0 then return false end

    local dataService = getDataService()
    if not dataService then return false end

    local playerData = dataService:GetPlayerData(player)
    if not playerData then return false end

    -- Already has one
    if playerData.villageAccessCode then return true end

    -- Reserve a new server
    local reserveSuccess, accessCode = pcall(function()
        return TeleportService:ReserveServer(config.VillagePlaceId)
    end)

    if reserveSuccess and accessCode then
        playerData.villageAccessCode = accessCode
        print(string.format("[TeleportManager] Auto-created village access code for %s", player.Name))
        return true
    end

    warn(string.format("[TeleportManager] Failed to create village access code for %s", player.Name))
    return false
end

--[[
    Teleports a player from overworld to their OWN village (private reserved server).

    Uses ReserveServer to create a private server per player. The access code
    is saved in PlayerData so subsequent visits reuse the same server.

    @param player Player - The player to teleport
    @param currentPosition Vector3 - Their current position in overworld (for return)
    @return boolean, string? - Success and optional error
]]
function TeleportManager:TeleportToVillage(player: Player, currentPosition: Vector3): (boolean, string?)
    local config = OverworldConfig.Teleport

    if config.VillagePlaceId == 0 then
        warn("[TeleportManager] Village PlaceId not configured!")
        return false, "PLACE_NOT_CONFIGURED"
    end

    -- Get or create access code for this player's private village server
    local dataService = getDataService()
    local accessCode = nil

    if dataService then
        local playerData = dataService:GetPlayerData(player)
        if playerData then
            accessCode = playerData.villageAccessCode
        end
    end

    -- If no access code, reserve a new server
    if not accessCode then
        local reserveSuccess, reserveResult = pcall(function()
            return TeleportService:ReserveServer(config.VillagePlaceId)
        end)

        if reserveSuccess and reserveResult then
            accessCode = reserveResult
            -- Save access code to player data
            if dataService then
                local playerData = dataService:GetPlayerData(player)
                if playerData then
                    playerData.villageAccessCode = accessCode
                end
            end
            print(string.format("[TeleportManager] Reserved new village server for %s", player.Name))
        else
            warn(string.format("[TeleportManager] Failed to reserve server: %s", tostring(reserveResult)))
            return false, "RESERVE_FAILED"
        end
    end

    -- Save data + release session lock before teleport
    if not preparePlayerForTeleport(player) then
        return false, "SAVE_FAILED"
    end

    -- Create teleport data with owner info
    local teleportData = createTeleportData("Overworld", player, currentPosition, nil)
    teleportData[config.DataKeys.OwnerUserId] = player.UserId
    teleportData[config.DataKeys.IsOwner] = true

    print(string.format("[TeleportManager] Teleporting %s to their village (private server)", player.Name))

    -- Use TeleportToPrivateServer instead of TeleportAsync
    local teleportSuccess, teleportErr = pcall(function()
        local teleportOptions = Instance.new("TeleportOptions")
        teleportOptions:SetTeleportData(teleportData)
        teleportOptions.ReservedServerAccessCode = accessCode
        return TeleportService:TeleportAsync(config.VillagePlaceId, {player}, teleportOptions)
    end)

    if teleportSuccess then
        TeleportManager.TeleportCompleted:Fire(player, "Village")
        return true
    end

    -- If teleport failed, the access code might be stale — regenerate and retry
    warn(string.format("[TeleportManager] Teleport failed (stale code?): %s. Regenerating...", tostring(teleportErr)))

    local retrySuccess, retryResult = pcall(function()
        return TeleportService:ReserveServer(config.VillagePlaceId)
    end)

    if retrySuccess and retryResult then
        accessCode = retryResult
        if dataService then
            local playerData = dataService:GetPlayerData(player)
            if playerData then
                playerData.villageAccessCode = accessCode
                -- Re-save with new code (best-effort — code works for this attempt regardless)
                local saveOk, saveErr = pcall(function()
                    return dataService:SavePlayerData(player)
                end)
                if not saveOk then
                    warn(string.format("[TeleportManager] Failed to persist new access code for %s: %s",
                        player.Name, tostring(saveErr)))
                end
            else
                warn(string.format("[TeleportManager] No player data to save new access code for %s", player.Name))
            end
        end

        local retryTeleport, retryErr2 = pcall(function()
            local teleportOptions = Instance.new("TeleportOptions")
            teleportOptions:SetTeleportData(teleportData)
            teleportOptions.ReservedServerAccessCode = accessCode
            return TeleportService:TeleportAsync(config.VillagePlaceId, {player}, teleportOptions)
        end)

        if retryTeleport then
            TeleportManager.TeleportCompleted:Fire(player, "Village")
            return true
        else
            warn(string.format("[TeleportManager] Retry also failed: %s", tostring(retryErr2)))
        end
    end

    TeleportManager.TeleportFailed:Fire(player, "Village", "TELEPORT_FAILED")
    return false, "TELEPORT_FAILED"
end

--[[
    Teleports a player to visit another player's village (as a visitor).

    @param player Player - The visiting player
    @param targetOwnerUserId number - The village owner's user ID
    @param currentPosition Vector3 - Visitor's current position for return
    @return boolean, string? - Success and optional error
]]
function TeleportManager:TeleportToVillageAsVisitor(
    player: Player,
    targetOwnerUserId: number,
    currentPosition: Vector3
): (boolean, string?)
    local config = OverworldConfig.Teleport

    if config.VillagePlaceId == 0 then
        return false, "PLACE_NOT_CONFIGURED"
    end

    -- Load target player's data to get their access code
    local dataService = getDataService()
    if not dataService then
        return false, "DATASERVICE_UNAVAILABLE"
    end

    local targetData = dataService:GetPlayerDataById(targetOwnerUserId)
    if not targetData or not targetData.villageAccessCode then
        warn(string.format("[TeleportManager] Target %d has no village access code", targetOwnerUserId))
        return false, "NO_VILLAGE"
    end

    local accessCode = targetData.villageAccessCode

    -- Save visitor's data before teleport
    if not preparePlayerForTeleport(player) then
        return false, "SAVE_FAILED"
    end

    -- Create teleport data (visitor, not owner)
    local teleportData = createTeleportData("Overworld", player, currentPosition, nil)
    teleportData[config.DataKeys.OwnerUserId] = targetOwnerUserId
    teleportData[config.DataKeys.IsOwner] = false

    print(string.format("[TeleportManager] Teleporting %s to visit %d's village", player.Name, targetOwnerUserId))

    local teleportSuccess, teleportErr = pcall(function()
        local teleportOptions = Instance.new("TeleportOptions")
        teleportOptions:SetTeleportData(teleportData)
        teleportOptions.ReservedServerAccessCode = accessCode
        return TeleportService:TeleportAsync(config.VillagePlaceId, {player}, teleportOptions)
    end)

    if teleportSuccess then
        TeleportManager.TeleportCompleted:Fire(player, "VillageVisit")
        return true
    end

    warn(string.format("[TeleportManager] Visitor teleport failed: %s", tostring(teleportErr)))
    TeleportManager.TeleportFailed:Fire(player, "VillageVisit", "TELEPORT_FAILED")
    return false, "TELEPORT_FAILED"
end

--[[
    Teleports a player from village back to overworld.

    @param player Player - The player to teleport
    @param returnPosition Vector3? - Position to return to (from teleport data)
    @return boolean, string? - Success and optional error
]]
function TeleportManager:TeleportToOverworld(player: Player, returnPosition: Vector3?): (boolean, string?)
    local config = OverworldConfig.Teleport

    -- Validate place ID is configured
    if config.OverworldPlaceId == 0 then
        warn("[TeleportManager] Overworld PlaceId not configured!")
        return false, "PLACE_NOT_CONFIGURED"
    end

    -- Save data + release session lock before teleport
    if not preparePlayerForTeleport(player) then
        return false, "SAVE_FAILED"
    end

    -- Create teleport data
    local teleportData = createTeleportData("Village", player, returnPosition, nil)

    print(string.format("[TeleportManager] Teleporting %s to Overworld", player.Name))

    return performTeleport(player, config.OverworldPlaceId, teleportData, "Overworld")
end

--[[
    Teleports a player to battle another player's base.

    @param player Player - The attacking player
    @param targetUserId number - The defender's user ID
    @param returnPosition Vector3 - Position to return to after battle
    @return boolean, string? - Success and optional error
]]
function TeleportManager:TeleportToBattle(
    player: Player,
    targetUserId: number,
    returnPosition: Vector3
): (boolean, string?)
    local config = OverworldConfig.Teleport

    -- Validate place ID is configured
    if config.BattlePlaceId == 0 then
        warn("[TeleportManager] Battle PlaceId not configured!")
        return false, "PLACE_NOT_CONFIGURED"
    end

    -- Save data + release session lock before teleport
    if not preparePlayerForTeleport(player) then
        return false, "SAVE_FAILED"
    end

    -- Create teleport data
    local teleportData = createTeleportData("Overworld", player, returnPosition, targetUserId)

    print(string.format("[TeleportManager] Teleporting %s to Battle vs %d", player.Name, targetUserId))

    return performTeleport(player, config.BattlePlaceId, teleportData, "Battle")
end

--[[
    Gets the teleport data for an arriving player.

    @param player Player - The player who just arrived
    @return table? - The teleport data, or nil if not from teleport
]]
function TeleportManager:GetArrivingPlayerData(player: Player): {[string]: any}?
    local success, data = pcall(function()
        return TeleportService:GetLocalPlayerTeleportData()
    end)

    if success and data then
        return data :: {[string]: any}
    end

    return nil
end

--[[
    Gets teleport data from a player's join data.

    @param player Player - The player
    @return table? - The teleport data
]]
function TeleportManager:GetJoinData(player: Player): {[string]: any}?
    local joinData = player:GetJoinData()

    if joinData and joinData.TeleportData then
        return joinData.TeleportData :: {[string]: any}
    end

    return nil
end

--[[
    Parses the return position from teleport data.

    @param teleportData table - The teleport data
    @return Vector3? - The return position, or nil
]]
function TeleportManager:ParseReturnPosition(teleportData: {[string]: any}): Vector3?
    local posData = teleportData[OverworldConfig.Teleport.DataKeys.ReturnPosition]

    if posData and typeof(posData) == "table" then
        return Vector3.new(posData.X or 0, posData.Y or 0, posData.Z or 0)
    end

    return nil
end

--[[
    Gets the source place from teleport data.

    @param teleportData table - The teleport data
    @return string? - The source place name
]]
function TeleportManager:GetSourcePlace(teleportData: {[string]: any}): string?
    return teleportData[OverworldConfig.Teleport.DataKeys.Source]
end

--[[
    Gets the target base ID from teleport data (for battle).

    @param teleportData table - The teleport data
    @return number? - The target user ID
]]
function TeleportManager:GetTargetBaseId(teleportData: {[string]: any}): number?
    return teleportData[OverworldConfig.Teleport.DataKeys.TargetBase]
end

--[[
    Checks if a player has a pending teleport.

    @param player Player - The player
    @return boolean - True if teleport is pending
]]
function TeleportManager:HasPendingTeleport(player: Player): boolean
    return _pendingTeleports[player.UserId] ~= nil
end

--[[
    Cancels a pending teleport (if possible).

    @param player Player - The player
    @return boolean - True if teleport was cancelled
]]
function TeleportManager:CancelPendingTeleport(player: Player): boolean
    local pending = _pendingTeleports[player.UserId]

    if pending then
        _pendingTeleports[player.UserId] = nil
        return true
    end

    return false
end

--[[
    Sets the Village PlaceId (for testing).

    @param placeId number - The Place ID
]]
function TeleportManager:SetVillagePlaceId(placeId: number)
    OverworldConfig.Teleport.VillagePlaceId = placeId
end

--[[
    Sets the Overworld PlaceId (for testing).

    @param placeId number - The Place ID
]]
function TeleportManager:SetOverworldPlaceId(placeId: number)
    OverworldConfig.Teleport.OverworldPlaceId = placeId
end

--[[
    Sets the Battle PlaceId (for testing).

    @param placeId number - The Place ID
]]
function TeleportManager:SetBattlePlaceId(placeId: number)
    OverworldConfig.Teleport.BattlePlaceId = placeId
end

return TeleportManager
