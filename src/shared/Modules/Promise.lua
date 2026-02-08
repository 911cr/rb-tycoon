--!strict
--[[
    Promise.lua

    Lightweight Promise implementation for async operations.
    Follows Promise/A+ spec patterns adapted for Luau.
]]

export type PromiseStatus = "Pending" | "Resolved" | "Rejected"

export type Promise<T> = {
    andThen: (self: Promise<T>, onResolve: (T) -> any, onReject: ((any) -> any)?) -> Promise<any>,
    catch: (self: Promise<T>, onReject: (any) -> any) -> Promise<T>,
    finally: (self: Promise<T>, onFinally: () -> ()) -> Promise<T>,
    await: (self: Promise<T>) -> (boolean, T),
    getStatus: (self: Promise<T>) -> PromiseStatus,
}

local Promise = {}
Promise.__index = Promise

type PromiseImpl<T> = {
    _status: PromiseStatus,
    _value: T?,
    _error: any?,
    _resolveCallbacks: {(T) -> ()},
    _rejectCallbacks: {(any) -> ()},
}

local function createPromise<T>(): PromiseImpl<T>
    return {
        _status = "Pending",
        _value = nil,
        _error = nil,
        _resolveCallbacks = {},
        _rejectCallbacks = {},
    }
end

function Promise.new<T>(executor: (resolve: (T) -> (), reject: (any) -> ()) -> ()): Promise<T>
    local self = setmetatable(createPromise(), Promise)

    local function resolve(value: T)
        if self._status ~= "Pending" then return end

        self._status = "Resolved"
        self._value = value

        for _, callback in self._resolveCallbacks do
            task.spawn(callback, value)
        end
    end

    local function reject(err: any)
        if self._status ~= "Pending" then return end

        self._status = "Rejected"
        self._error = err

        for _, callback in self._rejectCallbacks do
            task.spawn(callback, err)
        end
    end

    task.spawn(function()
        local success, err = pcall(executor, resolve, reject)
        if not success then
            reject(err)
        end
    end)

    return self :: any
end

function Promise.resolve<T>(value: T): Promise<T>
    return Promise.new(function(resolve)
        resolve(value)
    end)
end

function Promise.reject(err: any): Promise<any>
    return Promise.new(function(_, reject)
        reject(err)
    end)
end

function Promise:andThen(onResolve: (any) -> any, onReject: ((any) -> any)?): Promise<any>
    return Promise.new(function(resolve, reject)
        local function handleResolve(value)
            local success, result = pcall(onResolve, value)
            if success then
                resolve(result)
            else
                reject(result)
            end
        end

        local function handleReject(err)
            if onReject then
                local success, result = pcall(onReject, err)
                if success then
                    resolve(result)
                else
                    reject(result)
                end
            else
                reject(err)
            end
        end

        if self._status == "Resolved" then
            task.spawn(handleResolve, self._value)
        elseif self._status == "Rejected" then
            task.spawn(handleReject, self._error)
        else
            table.insert(self._resolveCallbacks, handleResolve)
            table.insert(self._rejectCallbacks, handleReject)
        end
    end)
end

function Promise:catch(onReject: (any) -> any): Promise<any>
    return self:andThen(function(value)
        return value
    end, onReject)
end

function Promise:finally(onFinally: () -> ()): Promise<any>
    return self:andThen(function(value)
        onFinally()
        return value
    end, function(err)
        onFinally()
        error(err)
    end)
end

function Promise:await(): (boolean, any)
    if self._status == "Resolved" then
        return true, self._value
    elseif self._status == "Rejected" then
        return false, self._error
    end

    local thread = coroutine.running()
    local resolved = false

    self:andThen(function(value)
        resolved = true
        task.spawn(thread, true, value)
    end, function(err)
        resolved = false
        task.spawn(thread, false, err)
    end)

    return coroutine.yield()
end

function Promise:getStatus(): PromiseStatus
    return self._status
end

-- Static methods for combining promises

function Promise.all(promises: {Promise<any>}): Promise<{any}>
    return Promise.new(function(resolve, reject)
        local results = {}
        local remaining = #promises

        if remaining == 0 then
            resolve(results)
            return
        end

        for i, promise in promises do
            promise:andThen(function(value)
                results[i] = value
                remaining -= 1
                if remaining == 0 then
                    resolve(results)
                end
            end, function(err)
                reject(err)
            end)
        end
    end)
end

function Promise.race(promises: {Promise<any>}): Promise<any>
    return Promise.new(function(resolve, reject)
        for _, promise in promises do
            promise:andThen(resolve, reject)
        end
    end)
end

function Promise.delay(seconds: number): Promise<nil>
    return Promise.new(function(resolve)
        task.delay(seconds, function()
            resolve(nil)
        end)
    end)
end

return Promise
