--!strict
--[[
    RandomEventService.lua

    Manages server-wide random events in the overworld.
    One event active at a time, lasting 10-30 minutes.
    Events trigger every 30-60 minutes.

    Event types: Gold Rush, Bandit Invasion, Merchant Festival, Forbidden Mist.
    Effects are applied by other services checking GetActiveEvent().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

repeat task.wait() until ReplicatedStorage:FindFirstChild("Shared")

local OverworldConfig = require(ReplicatedStorage.Shared.Constants.OverworldConfig)
local RandomEventData = require(ReplicatedStorage.Shared.Constants.RandomEventData)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local RandomEventService = {}
RandomEventService.__index = RandomEventService

-- ============================================================================
-- SIGNALS
-- ============================================================================

RandomEventService.EventStarted = Signal.new()  -- (eventType, eventData)
RandomEventService.EventEnded = Signal.new()     -- (eventType)

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _activeEvent: any = nil -- Current active event definition
local _eventEndTime: number = 0
local _nextEventTime: number = 0
local _initialized = false

local MIN_INTERVAL = OverworldConfig.Wilderness.Events.MinInterval
local MAX_INTERVAL = OverworldConfig.Wilderness.Events.MaxInterval
local MIN_DURATION = OverworldConfig.Wilderness.Events.MinDuration
local MAX_DURATION = OverworldConfig.Wilderness.Events.MaxDuration

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function RandomEventService:Init()
    if _initialized then return end
    _initialized = true

    -- Schedule first event
    _nextEventTime = os.time() + math.random(MIN_INTERVAL, MAX_INTERVAL)

    -- Event loop
    task.spawn(function()
        while true do
            task.wait(10) -- Check every 10 seconds
            local now = os.time()

            -- Check if active event has ended
            if _activeEvent and now >= _eventEndTime then
                local eventType = _activeEvent.id
                print(string.format("[RandomEventService] Event ended: %s", _activeEvent.name))
                _activeEvent = nil
                _eventEndTime = 0
                _nextEventTime = now + math.random(MIN_INTERVAL, MAX_INTERVAL)
                self.EventEnded:Fire(eventType)
            end

            -- Check if it's time for a new event
            if not _activeEvent and now >= _nextEventTime then
                local event = RandomEventData.PickRandomEvent()
                local duration = math.random(MIN_DURATION, MAX_DURATION)

                _activeEvent = event
                _eventEndTime = now + duration

                print(string.format("[RandomEventService] Event started: %s (duration: %ds)", event.name, duration))
                self.EventStarted:Fire(event.id, {
                    name = event.name,
                    description = event.description,
                    color = event.color,
                    effects = event.effects,
                    duration = duration,
                    endsAt = _eventEndTime,
                })
            end
        end
    end)

    print("[RandomEventService] Initialized")
end

--[[
    Gets the currently active event, if any.
    @return table? - Event definition with effects, or nil
]]
function RandomEventService:GetActiveEvent(): any?
    return _activeEvent
end

--[[
    Gets a specific effect value from the active event.
    Returns the default value if no event is active or the effect doesn't apply.
    @param effectKey string - Effect key (e.g. "goldMultiplier")
    @param default number - Default value if not active
    @return number
]]
function RandomEventService:GetEffect(effectKey: string, default: number): number
    if not _activeEvent then return default end
    local effects = _activeEvent.effects
    if effects and effects[effectKey] then
        return effects[effectKey]
    end
    return default
end

--[[
    Gets time remaining on the active event.
    @return number - Seconds remaining, or 0 if no event
]]
function RandomEventService:GetTimeRemaining(): number
    if not _activeEvent then return 0 end
    return math.max(0, _eventEndTime - os.time())
end

--[[
    Gets info about the active event for client sync.
    @return table?
]]
function RandomEventService:GetActiveEventInfo(): any?
    if not _activeEvent then return nil end
    return {
        id = _activeEvent.id,
        name = _activeEvent.name,
        description = _activeEvent.description,
        color = _activeEvent.color,
        effects = _activeEvent.effects,
        timeRemaining = self:GetTimeRemaining(),
    }
end

return RandomEventService
