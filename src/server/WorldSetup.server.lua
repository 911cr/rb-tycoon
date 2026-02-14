--[[
    WorldSetup.server.lua

    Server-side world initialization.
    Sets up lighting, atmosphere, and ambient environment.

    NOTE: Village building is handled by SimpleTest.server.lua
]]

local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

print("Initializing world environment...")

-- ============================================================================
-- CLEAR EXISTING LIGHTING EFFECTS
-- ============================================================================

for _, child in Lighting:GetChildren() do
    if child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("BloomEffect")
       or child:IsA("ColorCorrectionEffect") or child:IsA("SunRaysEffect") then
        child:Destroy()
    end
end

-- ============================================================================
-- MEDIEVAL FANTASY ATMOSPHERE
-- ============================================================================

-- Atmosphere (distant haze for depth)
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.3
atmosphere.Color = Color3.fromRGB(200, 210, 230)
atmosphere.Decay = Color3.fromRGB(160, 140, 110)
atmosphere.Glare = 0.15
atmosphere.Haze = 1.5
atmosphere.Offset = 0.1
atmosphere.Parent = Lighting

-- Sky
local sky = Instance.new("Sky")
sky.SunAngularSize = 14
sky.MoonAngularSize = 10
sky.StarCount = 2500
sky.Parent = Lighting

-- Bloom (subtle glow)
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.4
bloom.Size = 20
bloom.Threshold = 0.92
bloom.Parent = Lighting

-- Color correction (warm medieval feel)
local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Brightness = 0.03
colorCorrection.Contrast = 0.08
colorCorrection.Saturation = 0.12
colorCorrection.TintColor = Color3.fromRGB(255, 250, 242)
colorCorrection.Parent = Lighting

-- Sun rays
local sunRays = Instance.new("SunRaysEffect")
sunRays.Intensity = 0.08
sunRays.Spread = 0.6
sunRays.Parent = Lighting

-- ============================================================================
-- LIGHTING CONFIGURATION
-- ============================================================================

Lighting.Ambient = Color3.fromRGB(70, 70, 85)
Lighting.OutdoorAmbient = Color3.fromRGB(120, 120, 135)
Lighting.Brightness = 2.2
Lighting.ClockTime = 10.5  -- Mid-morning
Lighting.GeographicLatitude = 40
Lighting.GlobalShadows = true
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.4
Lighting.ShadowSoftness = 0.25
Lighting.Technology = Enum.Technology.Future
Lighting.ColorShift_Bottom = Color3.fromRGB(20, 15, 10)
Lighting.ColorShift_Top = Color3.fromRGB(255, 245, 230)

-- ============================================================================
-- AMBIENT SOUNDS
-- ============================================================================

-- Create sound group for ambient audio
local ambientGroup = Instance.new("SoundGroup")
ambientGroup.Name = "AmbientSounds"
ambientGroup.Volume = 0.5
ambientGroup.Parent = SoundService

-- Village ambience (will play when near buildings)
local villageAmbience = Instance.new("Sound")
villageAmbience.Name = "VillageAmbience"
villageAmbience.SoundId = "rbxassetid://9120349113"  -- Birds/nature
villageAmbience.Volume = 0.15
villageAmbience.Looped = true
villageAmbience.SoundGroup = ambientGroup
villageAmbience.Parent = SoundService
villageAmbience:Play()

-- Wind
local windSound = Instance.new("Sound")
windSound.Name = "Wind"
windSound.SoundId = "rbxassetid://9120355676"
windSound.Volume = 0.08
windSound.Looped = true
windSound.SoundGroup = ambientGroup
windSound.Parent = SoundService
windSound:Play()

print("World environment initialized")
print("  - Medieval fantasy lighting configured")
print("  - Atmospheric effects enabled")
print("  - Ambient sounds playing")
print("  - Village will be built by SimpleTest.server.lua")
