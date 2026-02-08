--!strict
--[[
    AudioController.lua

    Manages game audio - music and sound effects.
    Integrates with SettingsUI for volume and toggle controls.
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioController = {}
AudioController.__index = AudioController

-- Private state
local _initialized = false
local _player = Players.LocalPlayer

-- Sound groups
local _musicGroup: SoundGroup
local _sfxGroup: SoundGroup

-- Settings
local _settings = {
    musicEnabled = true,
    sfxEnabled = true,
    musicVolume = 0.5,
    sfxVolume = 0.7,
}

-- Currently playing music
local _currentMusic: Sound? = nil
local _currentMusicName: string? = nil

-- Sound pools for frequently used SFX
local _soundPools: {[string]: {Sound}} = {}

-- Sound definitions
local SoundIds = {
    -- UI Sounds
    ButtonClick = "rbxassetid://0", -- Placeholder - replace with actual sound ID
    ButtonHover = "rbxassetid://0",
    PanelOpen = "rbxassetid://0",
    PanelClose = "rbxassetid://0",
    Notification = "rbxassetid://0",

    -- Game Sounds
    BuildingPlaced = "rbxassetid://0",
    BuildingUpgrade = "rbxassetid://0",
    ResourceCollected = "rbxassetid://0",
    GoldCoin = "rbxassetid://0",

    -- Combat Sounds
    TroopDeploy = "rbxassetid://0",
    TroopDeath = "rbxassetid://0",
    BuildingDestroyed = "rbxassetid://0",
    Victory = "rbxassetid://0",
    Defeat = "rbxassetid://0",
    StarEarned = "rbxassetid://0",

    -- Music
    MusicCity = "rbxassetid://0",
    MusicBattle = "rbxassetid://0",
    MusicMenu = "rbxassetid://0",
}

--[[
    Gets whether music is enabled.
]]
function AudioController:IsMusicEnabled(): boolean
    return _settings.musicEnabled
end

--[[
    Gets whether SFX are enabled.
]]
function AudioController:IsSfxEnabled(): boolean
    return _settings.sfxEnabled
end

--[[
    Sets music enabled state.
]]
function AudioController:SetMusicEnabled(enabled: boolean)
    _settings.musicEnabled = enabled

    if _currentMusic then
        if enabled then
            _currentMusic:Resume()
        else
            _currentMusic:Pause()
        end
    end
end

--[[
    Sets SFX enabled state.
]]
function AudioController:SetSfxEnabled(enabled: boolean)
    _settings.sfxEnabled = enabled
end

--[[
    Sets music volume (0-1).
]]
function AudioController:SetMusicVolume(volume: number)
    _settings.musicVolume = math.clamp(volume, 0, 1)
    _musicGroup.Volume = _settings.musicVolume
end

--[[
    Sets SFX volume (0-1).
]]
function AudioController:SetSfxVolume(volume: number)
    _settings.sfxVolume = math.clamp(volume, 0, 1)
    _sfxGroup.Volume = _settings.sfxVolume
end

--[[
    Gets current music volume.
]]
function AudioController:GetMusicVolume(): number
    return _settings.musicVolume
end

--[[
    Gets current SFX volume.
]]
function AudioController:GetSfxVolume(): number
    return _settings.sfxVolume
end

--[[
    Creates a sound instance.
]]
local function createSound(soundId: string, parent: Instance, group: SoundGroup): Sound
    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.SoundGroup = group
    sound.Parent = parent
    return sound
end

--[[
    Gets or creates a sound from the pool.
]]
local function getPooledSound(soundName: string): Sound?
    local soundId = SoundIds[soundName]
    if not soundId or soundId == "rbxassetid://0" then
        return nil -- No valid sound ID
    end

    local pool = _soundPools[soundName]
    if not pool then
        pool = {}
        _soundPools[soundName] = pool
    end

    -- Find an available sound in the pool
    for _, sound in pool do
        if not sound.IsPlaying then
            return sound
        end
    end

    -- Create a new sound if pool is small enough
    if #pool < 5 then
        local sound = createSound(soundId, SoundService, _sfxGroup)
        table.insert(pool, sound)
        return sound
    end

    -- Pool is full and all sounds are playing, return nil
    return nil
end

--[[
    Plays a sound effect.
]]
function AudioController:PlaySound(soundName: string)
    if not _settings.sfxEnabled then return end

    local sound = getPooledSound(soundName)
    if sound then
        sound:Play()
    end
end

--[[
    Plays music by name.
]]
function AudioController:PlayMusic(musicName: string)
    if _currentMusicName == musicName then return end

    -- Stop current music
    if _currentMusic then
        _currentMusic:Stop()
        _currentMusic:Destroy()
        _currentMusic = nil
    end

    local soundId = SoundIds[musicName]
    if not soundId or soundId == "rbxassetid://0" then
        _currentMusicName = nil
        return
    end

    -- Create new music
    _currentMusic = createSound(soundId, SoundService, _musicGroup)
    _currentMusic.Looped = true
    _currentMusicName = musicName

    if _settings.musicEnabled then
        _currentMusic:Play()
    end
end

--[[
    Stops the current music.
]]
function AudioController:StopMusic()
    if _currentMusic then
        _currentMusic:Stop()
        _currentMusic:Destroy()
        _currentMusic = nil
        _currentMusicName = nil
    end
end

--[[
    Fades music to a new track.
]]
function AudioController:FadeToMusic(musicName: string, fadeDuration: number?)
    fadeDuration = fadeDuration or 1

    if _currentMusicName == musicName then return end

    -- Fade out current music
    if _currentMusic and _settings.musicEnabled then
        local oldMusic = _currentMusic
        local startVolume = oldMusic.Volume

        task.spawn(function()
            local elapsed = 0
            while elapsed < fadeDuration do
                elapsed += task.wait()
                local alpha = 1 - (elapsed / fadeDuration)
                oldMusic.Volume = startVolume * alpha
            end
            oldMusic:Stop()
            oldMusic:Destroy()
        end)

        _currentMusic = nil
    end

    -- Start new music with fade in
    local soundId = SoundIds[musicName]
    if not soundId or soundId == "rbxassetid://0" then
        _currentMusicName = nil
        return
    end

    _currentMusic = createSound(soundId, SoundService, _musicGroup)
    _currentMusic.Looped = true
    _currentMusic.Volume = 0
    _currentMusicName = musicName

    if _settings.musicEnabled then
        _currentMusic:Play()

        -- Fade in
        task.spawn(function()
            local elapsed = 0
            local targetVolume = _settings.musicVolume
            while elapsed < fadeDuration and _currentMusic do
                elapsed += task.wait()
                local alpha = math.min(elapsed / fadeDuration, 1)
                if _currentMusic then
                    _currentMusic.Volume = targetVolume * alpha
                end
            end
        end)
    end
end

--[[
    Plays UI click sound.
]]
function AudioController:PlayClick()
    self:PlaySound("ButtonClick")
end

--[[
    Plays UI hover sound.
]]
function AudioController:PlayHover()
    self:PlaySound("ButtonHover")
end

--[[
    Plays notification sound.
]]
function AudioController:PlayNotification()
    self:PlaySound("Notification")
end

--[[
    Initializes the AudioController.
]]
function AudioController:Init()
    if _initialized then
        warn("AudioController already initialized")
        return
    end

    -- Create sound groups
    _musicGroup = Instance.new("SoundGroup")
    _musicGroup.Name = "Music"
    _musicGroup.Volume = _settings.musicVolume
    _musicGroup.Parent = SoundService

    _sfxGroup = Instance.new("SoundGroup")
    _sfxGroup.Name = "SFX"
    _sfxGroup.Volume = _settings.sfxVolume
    _sfxGroup.Parent = SoundService

    -- Connect to SettingsUI if available
    task.defer(function()
        local Controllers = _player:WaitForChild("PlayerScripts"):FindFirstChild("Controllers")
        if Controllers then
            local uiControllerModule = Controllers:FindFirstChild("UIController")
            if uiControllerModule then
                -- Try to get SettingsUI reference
                local SettingsUI = script.Parent.Parent:FindFirstChild("UI") and
                    script.Parent.Parent.UI:FindFirstChild("SettingsUI")

                if SettingsUI then
                    local settingsModule = require(SettingsUI)
                    if settingsModule and settingsModule.SettingChanged then
                        settingsModule.SettingChanged:Connect(function(setting: string, value: any)
                            if setting == "musicEnabled" then
                                self:SetMusicEnabled(value)
                            elseif setting == "sfxEnabled" then
                                self:SetSfxEnabled(value)
                            elseif setting == "musicVolume" then
                                self:SetMusicVolume(value)
                            elseif setting == "sfxVolume" then
                                self:SetSfxVolume(value)
                            end
                        end)
                    end
                end
            end
        end
    end)

    -- Start with city music
    task.defer(function()
        self:PlayMusic("MusicCity")
    end)

    _initialized = true
    print("AudioController initialized")
end

return AudioController
