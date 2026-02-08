--!strict
--[[
    Signal.lua

    Custom event/signal implementation for decoupled communication.
    Similar to BindableEvent but more flexible and memory-safe.
]]

export type Connection = {
    Connected: boolean,
    Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
    Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
    Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
    Fire: (self: Signal<T...>, T...) -> (),
    Wait: (self: Signal<T...>) -> T...,
    DisconnectAll: (self: Signal<T...>) -> (),
    Destroy: (self: Signal<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

type SignalImpl = {
    _connections: {(any) -> ()},
    _destroyed: boolean,
}

function Signal.new<T...>(): Signal<T...>
    local self = setmetatable({
        _connections = {},
        _destroyed = false,
    }, Signal)

    return self :: any
end

function Signal:Connect(callback: (any) -> ()): Connection
    if self._destroyed then
        warn("Attempted to connect to destroyed Signal")
        return {
            Connected = false,
            Disconnect = function() end,
        }
    end

    table.insert(self._connections, callback)

    local connection = {
        Connected = true,
        Disconnect = function(conn)
            if not conn.Connected then return end
            conn.Connected = false

            local index = table.find(self._connections, callback)
            if index then
                table.remove(self._connections, index)
            end
        end,
    }

    return connection
end

function Signal:Once(callback: (any) -> ()): Connection
    local connection: Connection
    connection = self:Connect(function(...)
        connection:Disconnect()
        callback(...)
    end)
    return connection
end

function Signal:Fire(...: any)
    if self._destroyed then return end

    -- Copy connections to allow disconnection during iteration
    local connections = table.clone(self._connections)

    for _, callback in connections do
        task.spawn(callback, ...)
    end
end

function Signal:Wait(): any
    if self._destroyed then
        error("Attempted to wait on destroyed Signal")
    end

    local thread = coroutine.running()
    local connection: Connection

    connection = self:Connect(function(...)
        connection:Disconnect()
        task.spawn(thread, ...)
    end)

    return coroutine.yield()
end

function Signal:DisconnectAll()
    table.clear(self._connections)
end

function Signal:Destroy()
    self:DisconnectAll()
    self._destroyed = true
end

return Signal
