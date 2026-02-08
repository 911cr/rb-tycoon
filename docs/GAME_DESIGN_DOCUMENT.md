# Battle Tycoon: Conquest
## Game Design Document v1.0

---

# Table of Contents

1. [Game Overview](#1-game-overview)
2. [Core Gameplay Loop](#2-core-gameplay-loop)
3. [World Architecture](#3-world-architecture)
4. [Building System](#4-building-system)
5. [Troop System](#5-troop-system)
6. [Combat System](#6-combat-system)
7. [Economy System](#7-economy-system)
8. [Progression System](#8-progression-system)
9. [Alliance System](#9-alliance-system)
10. [Monetization](#10-monetization)
11. [Engagement Systems](#11-engagement-systems)
12. [UI/UX Design](#12-uiux-design)
13. [Onboarding & Tutorial](#13-onboarding--tutorial)
14. [Events & Live Operations](#14-events--live-operations)
15. [Technical Architecture](#15-technical-architecture)
16. [Audio Design](#16-audio-design)
17. [Metrics & Analytics](#17-metrics--analytics)
18. [Development Roadmap](#18-development-roadmap)

---

# 1. Game Overview

## 1.1 Concept Statement

**Battle Tycoon: Conquest** is a Roblox city-building conquest game where players build and upgrade their cities, train armies, and conquer other players' cities to expand their empire. Players can own multiple cities, harvest resources, trade in a player-driven economy, and compete in alliance wars for global domination.

## 1.2 Genre

- Primary: City Builder / Strategy
- Secondary: Tycoon / Conquest / PvP

## 1.3 Target Audience

| Attribute | Value |
|-----------|-------|
| Age Range | 10-16 years old |
| Platform | Roblox (PC, Mobile, Console) |
| Session Length | 15-30 minutes |
| Play Style | Casual to Mid-Core |

## 1.4 Unique Selling Points

1. **Multi-City Empire Building** - Own up to 5 cities simultaneously
2. **Tiered Conquest System** - Choose to raid, occupy, or permanently conquer
3. **Real Economy** - Player-driven market for resources and troops
4. **Alliance Territory Wars** - Clans fight for control of the World Map
5. **Fantasy-Medieval Theme** - Knights, mages, dragons, AND tanks/mechs

## 1.5 Core Pillars

| Pillar | Description |
|--------|-------------|
| **Build** | Create and upgrade your city with 20+ building types |
| **Train** | Raise armies of infantry, cavalry, mages, dragons, and war machines |
| **Conquer** | Attack other players to steal resources and expand your empire |
| **Dominate** | Join alliances, win wars, and climb the global leaderboards |

## 1.6 Comparable Games

| Game | What We Take | What We Improve |
|------|--------------|-----------------|
| Clash of Clans | Combat deployment, shield system, clan wars | Multi-city ownership, occupation mechanics |
| Rise of Kingdoms | World map, territory control, troop variety | Simpler onboarding, Roblox-native experience |
| Boom Beach | Task force attacks, resource islands | Fantasy theme, deeper building variety |

---

# 2. Core Gameplay Loop

## 2.1 Primary Loop (Session)

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│    ┌──────────┐     ┌──────────┐     ┌──────────┐              │
│    │  COLLECT │────▶│  BUILD   │────▶│  TRAIN   │              │
│    │ Resources│     │ Upgrade  │     │  Troops  │              │
│    └──────────┘     └──────────┘     └──────────┘              │
│          ▲                                  │                   │
│          │                                  ▼                   │
│    ┌──────────┐                      ┌──────────┐              │
│    │  LOOT    │◀────────────────────│  ATTACK  │              │
│    │ Rewards  │                      │  Enemy   │              │
│    └──────────┘                      └──────────┘              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Loop Duration:** 5-15 minutes per cycle

## 2.2 Secondary Loop (Daily)

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  LOGIN ──▶ COLLECT OFFLINE EARNINGS ──▶ CLAIM DAILY REWARD     │
│                                                                 │
│     │                                                           │
│     ▼                                                           │
│                                                                 │
│  CHECK BATTLE LOG ──▶ REVENGE ATTACKS ──▶ ALLIANCE CHAT        │
│                                                                 │
│     │                                                           │
│     ▼                                                           │
│                                                                 │
│  COMPLETE BATTLE PASS MISSIONS ──▶ UPGRADE BUILDINGS            │
│                                                                 │
│     │                                                           │
│     ▼                                                           │
│                                                                 │
│  ATTACK FOR RESOURCES ──▶ DONATE TO ALLIANCE ──▶ LOGOUT        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 2.3 Tertiary Loop (Weekly)

- Alliance War participation (2 wars per week)
- Season Battle Pass tier completion
- Weekly events and challenges
- Alliance boss battles

## 2.4 Meta Loop (Monthly/Seasonal)

- Season resets (Battle Pass, Leagues)
- Major content updates
- Limited-time events
- Alliance Season rankings

---

# 3. World Architecture

## 3.1 Place Structure

The game uses Roblox's multi-place architecture with TeleportService:

```
┌─────────────────────────────────────────────────────────────────┐
│                         GAME UNIVERSE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐                                            │
│  │   MAIN MENU     │  Entry point, account management          │
│  │   (Place 1)     │  Tutorial start, settings                 │
│  └────────┬────────┘                                            │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────┐                                            │
│  │   CITY VIEW     │  Player's city instance                   │
│  │   (Place 2)     │  Building, troop training                 │
│  └────────┬────────┘  Upgrades, management                     │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────┐                                            │
│  │   WORLD MAP     │  Overview of all cities                   │
│  │   (Place 3)     │  Target selection, alliance territory     │
│  └────────┬────────┘  Travel between owned cities              │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────┐                                            │
│  │  BATTLE ARENA   │  Combat instance                          │
│  │   (Place 4)     │  Troop deployment, spell usage            │
│  └─────────────────┘  Victory/defeat calculation               │
│                                                                 │
│  ┌─────────────────┐                                            │
│  │  ALLIANCE HQ    │  Alliance management                      │
│  │   (Place 5)     │  War room, donations, chat                │
│  └─────────────────┘                                            │
│                                                                 │
│  ┌─────────────────┐                                            │
│  │     MARKET      │  Player-to-player trading                 │
│  │   (Place 6)     │  Resource exchange, troop sales           │
│  └─────────────────┘                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 3.2 City View (Place 2)

### 3.2.1 Layout

- **Grid-Based Building Placement:** 40x40 tile grid
- **Terrain:** Grass base with decorative elements
- **Walls:** Player-placed perimeter defense
- **Zoom Levels:** 3 levels (Close, Medium, Far)

### 3.2.2 Player Actions in City View

| Action | Description |
|--------|-------------|
| Place Building | Tap empty space, select building from menu |
| Upgrade Building | Tap building, press Upgrade button |
| Move Building | Tap building, drag to new location |
| Train Troops | Tap military building, select troop type |
| Collect Resources | Tap resource building or "Collect All" button |
| Edit Mode | Rearrange all buildings freely |

### 3.2.3 Camera Controls

| Platform | Control |
|----------|---------|
| PC | WASD/Arrow keys to pan, scroll to zoom, right-click drag to rotate |
| Mobile | Pinch to zoom, drag to pan, two-finger rotate |
| Console | Left stick pan, triggers zoom, right stick rotate |

## 3.3 World Map (Place 3)

### 3.3.1 Map Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                         WORLD MAP                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  The world is divided into REGIONS (10x10 grid per region)      │
│                                                                 │
│  ┌─────────┬─────────┬─────────┬─────────┐                      │
│  │ Region  │ Region  │ Region  │ Region  │                      │
│  │  NORTH  │  EAST   │  SOUTH  │  WEST   │                      │
│  │         │         │         │         │                      │
│  │ [Cities]│ [Cities]│ [Cities]│ [Cities]│                      │
│  └─────────┴─────────┴─────────┴─────────┘                      │
│                                                                 │
│  Each region contains:                                          │
│  • Player cities (dots on map)                                  │
│  • Resource nodes (gold/wood/food deposits)                     │
│  • Alliance territories (colored zones)                         │
│  • NPC camps (PvE targets)                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.3.2 Map Features

| Feature | Description |
|---------|-------------|
| Player Cities | Shown as castle icons, color = alliance |
| Alliance Territory | Shaded region, claimed by alliance |
| Resource Tiles | Gatherable nodes (limited time occupation) |
| NPC Camps | AI enemies for PvE practice and loot |
| Fog of War | Unexplored areas hidden until scouted |

## 3.4 Battle Arena (Place 4)

### 3.4.1 Arena Structure

- **Defender's City** is loaded as the battlefield
- **Attacker** views from outside the walls
- **3-Minute Timer** for attack completion
- **Deployment Zone** around city perimeter

### 3.4.2 Battle Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                       BATTLE SEQUENCE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. SCOUTING PHASE (10 seconds)                                 │
│     • View enemy city layout                                    │
│     • Plan attack strategy                                      │
│     • Select troops to deploy                                   │
│                                                                 │
│  2. DEPLOYMENT PHASE (3 minutes)                                │
│     • Tap to deploy troops at chosen locations                  │
│     • Troops automatically attack nearest target               │
│     • Use spells (Rage, Heal, Lightning, etc.)                 │
│     • Watch battle unfold in real-time                         │
│                                                                 │
│  3. RESULTS PHASE                                               │
│     • Destruction percentage calculated                         │
│     • Stars awarded (1-3 based on destruction)                 │
│     • Loot distributed                                         │
│     • Trophy adjustment                                         │
│     • Return to World Map or Replay option                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

# 4. Building System

## 4.1 Building Categories

### 4.1.1 Core Buildings

| Building | Function | Max Level | Unlock TH |
|----------|----------|-----------|-----------|
| **Town Hall** | Gates all upgrades, city level, worker count | 10 | 1 |
| **Warehouse** | Stores resources, protects % from raids | 10 | 1 |
| **Treasury** | Stores gold, protected from raids | 10 | 2 |
| **Builder's Hut** | Each hut = 1 concurrent construction | 5 | 1 |

### 4.1.2 Economy Buildings

| Building | Resource Produced | Max Level | Unlock TH |
|----------|-------------------|-----------|-----------|
| **Farm** | Food (feeds troops) | 10 | 1 |
| **Lumber Mill** | Wood (buildings) | 10 | 2 |
| **Gold Mine** | Gold (troops, upgrades) | 10 | 1 |
| **Gem Mine** | Gems (premium currency) - slow | 5 | 4 |
| **Market** | Trade resources with players | 10 | 5 |

### 4.1.3 Military Buildings

| Building | Troops Trained | Max Level | Unlock TH |
|----------|----------------|-----------|-----------|
| **Barracks** | Warriors, Knights, Berserkers | 10 | 1 |
| **Archery Range** | Archers, Crossbowmen, Longbowmen | 10 | 2 |
| **Stable** | Light Cavalry, Heavy Cavalry, Wolf Riders | 10 | 3 |
| **Mage Tower** | Wizards, Healers, Necromancers | 10 | 5 |
| **Siege Workshop** | Catapults, Battering Rams, Ballistas | 10 | 6 |
| **Dragon Roost** | Fire Dragon, Ice Dragon, Storm Dragon | 10 | 8 |
| **War Factory** | Battle Tank, War Mech, Artillery | 10 | 9 |
| **Army Camp** | Stores trained troops | 10 | 1 |

### 4.1.4 Defense Buildings

| Building | Function | Max Level | Unlock TH |
|----------|----------|-----------|-----------|
| **Walls** | Blocks/slows ground troops | 10 | 1 |
| **Archer Tower** | Rapid-fire arrows, medium range | 10 | 2 |
| **Cannon** | High damage, slow fire, ground only | 10 | 2 |
| **Wizard Tower** | Splash magic damage, air + ground | 10 | 4 |
| **Air Defense** | High damage to air units only | 10 | 6 |
| **Bomb Trap** | Hidden, explodes on contact | 5 | 2 |
| **Spring Trap** | Hidden, launches troops away | 5 | 3 |
| **Tesla Tower** | Hidden, high DPS, air + ground | 10 | 7 |
| **Castle** | Houses defensive garrison troops | 10 | 3 |

### 4.1.5 Support Buildings

| Building | Function | Max Level | Unlock TH |
|----------|----------|-----------|-----------|
| **Academy** | Research troop/building upgrades | 10 | 4 |
| **Hospital** | Heals wounded troops (saves resources) | 10 | 6 |
| **Spell Forge** | Creates battle spells | 10 | 4 |
| **Watchtower** | Early warning of incoming attacks | 5 | 5 |
| **Embassy** | Houses alliance reinforcement troops | 10 | 3 |

## 4.2 Town Hall Gating Rules

### 4.2.1 Core Rule

**No building can exceed the Town Hall level.**

```
Example:
- Town Hall Level 4
- Maximum building level for ANY building = Level 4
- Barracks Level 4 ✓
- Barracks Level 5 ✗ (Requires TH5)
```

### 4.2.2 Town Hall Upgrade Requirements

| TH Level | Requirement | Unlocks |
|----------|-------------|---------|
| 1 → 2 | All buildings at L1 | Archery Range, Lumber Mill, Archer Tower, Treasury |
| 2 → 3 | All buildings at L2 + 2,000 gold | Stable, Cannon, Castle, Embassy |
| 3 → 4 | All buildings at L3 + 5,000 gold + 3,000 wood | Academy, Spell Forge, Wizard Tower |
| 4 → 5 | All buildings at L4 + 10,000 gold + 8,000 wood | Mage Tower, Market, Gem Mine, **2nd City Slot** |
| 5 → 6 | All buildings at L5 + 25,000 gold + 20,000 wood | Siege Workshop, Hospital, Air Defense |
| 6 → 7 | All buildings at L6 + 50,000 gold + 40,000 wood | Watchtower, Tesla Tower |
| 7 → 8 | All buildings at L7 + 100,000 gold + 80,000 wood | Dragon Roost, **3rd City Slot** |
| 8 → 9 | All buildings at L8 + 200,000 gold + 150,000 wood | War Factory |
| 9 → 10 | All buildings at L9 + 500,000 gold + 400,000 wood | Ultimate buildings, **5th City Slot** |

### 4.2.3 Building Count Limits by TH

| TH Level | Army Camps | Resource Buildings | Defense Buildings | Walls |
|----------|------------|-------------------|-------------------|-------|
| 1 | 1 | 2 Farms, 1 Gold Mine | 0 | 25 |
| 2 | 2 | 3 Farms, 2 Gold Mines, 1 Lumber Mill | 1 Archer Tower, 1 Cannon | 50 |
| 3 | 2 | 4 Farms, 2 Gold Mines, 2 Lumber Mills | 2 of each | 75 |
| 4 | 3 | 5 Farms, 3 Gold Mines, 3 Lumber Mills | 3 of each + Wizard Tower | 100 |
| 5 | 3 | 6, 4, 4 + Gem Mine | 4 of each | 125 |
| 6 | 4 | 7, 5, 5, 1 | 5 of each + Air Defense | 150 |
| 7 | 4 | 8, 6, 6, 1 | 6 of each + Tesla | 175 |
| 8 | 5 | 9, 7, 7, 2 | 7 of each | 200 |
| 9 | 5 | 10, 8, 8, 2 | 8 of each | 225 |
| 10 | 6 | 12, 10, 10, 3 | 10 of each | 250 |

## 4.3 Upgrade Times & Costs

### 4.3.1 Upgrade Time Scaling

| Level | Base Time | With VIP (-20%) |
|-------|-----------|-----------------|
| 1 → 2 | 1 minute | 48 seconds |
| 2 → 3 | 5 minutes | 4 minutes |
| 3 → 4 | 30 minutes | 24 minutes |
| 4 → 5 | 2 hours | 1h 36m |
| 5 → 6 | 8 hours | 6h 24m |
| 6 → 7 | 24 hours | 19h 12m |
| 7 → 8 | 2 days | 1d 14h |
| 8 → 9 | 4 days | 3d 4h |
| 9 → 10 | 7 days | 5d 14h |

### 4.3.2 Cost Formula

```lua
-- Gold cost formula
goldCost = baseGold * (level ^ 1.8)

-- Wood cost formula
woodCost = baseWood * (level ^ 1.6)

-- Example: Barracks (baseGold = 100, baseWood = 50)
-- Level 5: 100 * (5^1.8) = 1,850 gold, 50 * (5^1.6) = 680 wood
```

## 4.4 Builder System

### 4.4.1 Builder Mechanics

- Start with **1 Builder** (free)
- Can have up to **5 Builders** total
- Each builder works on ONE project at a time
- Builders are shared across ALL cities

### 4.4.2 Builder Acquisition

| Builder | Cost | Method |
|---------|------|--------|
| Builder 1 | Free | Starting |
| Builder 2 | 250 Gems OR VIP Subscription | Purchase |
| Builder 3 | 500 Gems | Purchase |
| Builder 4 | 1,000 Gems | Purchase |
| Builder 5 | 2,000 Gems | Purchase |

---

# 5. Troop System

## 5.1 Troop Categories

### 5.1.1 Infantry (Barracks)

| Troop | Housing | Training Time | DPS | HP | Target | Special |
|-------|---------|---------------|-----|-----|--------|---------|
| **Warrior** | 1 | 20s | 15 | 100 | Ground | Basic melee unit |
| **Knight** | 2 | 45s | 35 | 250 | Ground | Heavy armor, slow |
| **Berserker** | 3 | 60s | 75 | 150 | Ground | Rage: +50% damage at low HP |

### 5.1.2 Ranged (Archery Range)

| Troop | Housing | Training Time | DPS | HP | Target | Special |
|-------|---------|---------------|-----|-----|--------|---------|
| **Archer** | 1 | 25s | 12 | 40 | Ground + Air | Basic ranged |
| **Crossbowman** | 2 | 50s | 28 | 60 | Ground + Air | Armor penetration |
| **Longbowman** | 2 | 60s | 20 | 50 | Ground + Air | Extended range |

### 5.1.3 Cavalry (Stable)

| Troop | Housing | Training Time | DPS | HP | Target | Special |
|-------|---------|---------------|-----|-----|--------|---------|
| **Light Cavalry** | 3 | 90s | 40 | 200 | Ground | Fast movement |
| **Heavy Cavalry** | 5 | 180s | 80 | 450 | Ground | Charge: 2x first hit |
| **Wolf Rider** | 4 | 150s | 60 | 300 | Ground | Howl: Boosts nearby allies |

### 5.1.4 Magic (Mage Tower)

| Troop | Housing | Training Time | DPS | HP | Target | Special |
|-------|---------|---------------|-----|-----|--------|---------|
| **Wizard** | 4 | 240s | 50 | 100 | Ground + Air | Splash damage |
| **Healer** | 5 | 300s | 0 | 150 | Allies | Heals nearby troops |
| **Necromancer** | 6 | 360s | 35 | 120 | Ground | Summons skeletons from kills |

### 5.1.5 Siege (Siege Workshop)

| Troop | Housing | Training Time | DPS | HP | Target | Special |
|-------|---------|---------------|-----|-----|--------|---------|
| **Catapult** | 8 | 600s | 100 | 300 | Buildings | Long range, splash |
| **Battering Ram** | 10 | 900s | 200 | 800 | Buildings | Walls and buildings only |
| **Ballista** | 6 | 480s | 150 | 200 | Ground + Air | High single-target damage |

### 5.1.6 Air (Dragon Roost)

| Troop | Housing | Training Time | DPS | HP | Target | Special |
|-------|---------|---------------|-----|-----|--------|---------|
| **Fire Dragon** | 15 | 1800s | 200 | 600 | Ground | Splash fire damage |
| **Ice Dragon** | 15 | 1800s | 150 | 800 | Ground + Air | Slows targets |
| **Storm Dragon** | 20 | 2400s | 250 | 500 | Ground + Air | Chain lightning |

### 5.1.7 Machines (War Factory)

| Troop | Housing | Training Time | DPS | HP | Target | Special |
|-------|---------|---------------|-----|-----|--------|---------|
| **Battle Tank** | 20 | 2400s | 300 | 1500 | Ground | Heavy armor, slow |
| **War Mech** | 25 | 3000s | 400 | 2000 | Ground + Air | Walking fortress |
| **Artillery** | 15 | 1800s | 350 | 400 | Buildings | Extreme range |

## 5.2 Troop Training

### 5.2.1 Training Queue

- Each military building has a **training queue** of 5 slots
- Multiple buildings of same type share queue
- Training continues when offline

### 5.2.2 Army Camp Capacity

| Army Camp Level | Capacity |
|-----------------|----------|
| 1 | 20 |
| 2 | 25 |
| 3 | 30 |
| 4 | 35 |
| 5 | 40 |
| 6 | 50 |
| 7 | 60 |
| 8 | 70 |
| 9 | 80 |
| 10 | 100 |

**Total Army Size = Sum of all Army Camp capacities**

## 5.3 Troop Upgrades

Troop levels are upgraded at the **Academy**, not at individual buildings.

| Troop Level | Academy Required | Stat Boost |
|-------------|------------------|------------|
| 1 | - | Base stats |
| 2 | Academy L2 | +10% DPS, +10% HP |
| 3 | Academy L3 | +20% DPS, +20% HP |
| 4 | Academy L4 | +30% DPS, +30% HP |
| 5 | Academy L5 | +40% DPS, +40% HP |
| 6 | Academy L6 | +50% DPS, +50% HP |
| 7 | Academy L7 | +60% DPS, +60% HP |
| 8 | Academy L8 | +70% DPS, +70% HP |
| 9 | Academy L9 | +80% DPS, +80% HP |
| 10 | Academy L10 | +100% DPS, +100% HP |

---

# 6. Combat System

## 6.1 Combat Overview

Combat is **simulated with live viewing** - players deploy troops and watch the battle unfold with AI-controlled units. Players can use spells during combat but don't directly control troop movement.

## 6.2 Battle Flow

### 6.2.1 Pre-Battle: Target Selection

```
MATCHMAKING CRITERIA:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  PRIMARY: Trophy Count (±200 trophies)                          │
│  SECONDARY: Town Hall Level (±1 level)                          │
│  TERTIARY: Active Players (online in last 24 hours preferred)   │
│                                                                 │
│  EXCLUSIONS:                                                    │
│  • Players with active shield                                   │
│  • Same alliance members                                        │
│  • Players you attacked in last 24 hours                       │
│  • Your own cities                                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2.2 Scouting Phase (10 seconds)

- View enemy city layout
- See building levels (tap to inspect)
- See trap locations (NOT hidden ones)
- Cannot see troops in Castle
- Plan deployment strategy

### 6.2.3 Deployment Phase (3 minutes)

```
DEPLOYMENT RULES:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  • Tap anywhere in the DEPLOYMENT ZONE (outside walls)          │
│  • Select troop type from bottom bar                           │
│  • Tap multiple times for multiple troops                      │
│  • Troops immediately start attacking                          │
│                                                                 │
│  TROOP AI BEHAVIOR:                                             │
│  • Infantry: Attack nearest building                           │
│  • Ranged: Attack nearest enemy within range                   │
│  • Cavalry: Rush to nearest defense building                   │
│  • Siege: Target walls and defenses                            │
│  • Dragons: Fly over walls, target highest HP building         │
│                                                                 │
│  SPELLS:                                                        │
│  • Tap spell from bar, then tap target location                │
│  • Limited uses per spell (based on Spell Forge level)         │
│  • Spells have cooldowns                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2.4 Battle Resolution

```
DESTRUCTION CALCULATION:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  Total Destruction % = (Destroyed Buildings HP / Total HP) × 100│
│                                                                 │
│  STAR RATING:                                                   │
│  ⭐ = 50% destruction                                           │
│  ⭐⭐ = 75% destruction                                          │
│  ⭐⭐⭐ = 100% destruction OR Town Hall destroyed                 │
│                                                                 │
│  TOWN HALL BONUS:                                               │
│  • Destroying Town Hall = automatic 1 star + 25% destruction   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 6.3 Victory Tiers

| Destruction | Result | Loot | Trophies | Special |
|-------------|--------|------|----------|---------|
| 0-39% | **Defeat** | 5% resources | -5 to -15 | None |
| 40-59% | **Raid** | 20% resources | +10 to +20 | None |
| 60-79% | **Major Raid** | 40% resources | +20 to +30 | Can place Outpost |
| 80-99% | **Conquest** | 60% resources | +30 to +50 | Can Occupy (3 days) |
| 100% | **Domination** | 80% resources | +50 to +75 | Can Occupy (7 days) |

## 6.4 Occupation System

### 6.4.1 Outpost (60-79% Victory)

- Place a small outpost on defeated player's territory
- Collect 5% of their resource production daily
- Lasts until they attack and destroy it
- Maximum 5 outposts across all enemies

### 6.4.2 Occupation (80%+ Victory)

```
OCCUPATION MECHANICS:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  80-99% DESTRUCTION:                                            │
│  • Occupy for 3 days                                            │
│  • Collect 15% of their resource production                    │
│  • They cannot attack anyone during occupation                 │
│  • After 3 days: They get 24hr shield, you leave               │
│                                                                 │
│  100% DESTRUCTION:                                              │
│  • Occupy for 7 days                                            │
│  • Collect 25% of their resource production                    │
│  • PERMANENT TAKEOVER option if:                                │
│    - Player inactive 14+ days                                  │
│    - You have available city slot                              │
│    - You pay 50,000 gems                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.4.3 Permanent Takeover

When permanently taking over a city:

- Buildings transfer at 50% of their level (rounded down)
- All buildings marked as "damaged" (need repair)
- Resources in storage transfer (minus 20% destruction)
- Troops do NOT transfer
- City location changes to your region on World Map

## 6.5 Spells

### 6.5.1 Available Spells

| Spell | Effect | Radius | Duration | Forge Level |
|-------|--------|--------|----------|-------------|
| **Lightning** | 500 damage to point | 3 tiles | Instant | 1 |
| **Rage** | +30% damage, +20% speed | 5 tiles | 8 seconds | 2 |
| **Heal** | Restore 300 HP/second | 4 tiles | 6 seconds | 3 |
| **Freeze** | Stop defenses | 4 tiles | 4 seconds | 4 |
| **Jump** | Troops leap over walls | 4 tiles | 6 seconds | 5 |
| **Earthquake** | 25% damage to buildings | 6 tiles | Instant | 6 |
| **Bat Swarm** | Summon bats | 4 tiles | 10 seconds | 7 |
| **Invisibility** | Troops become untargetable | 3 tiles | 4 seconds | 8 |

### 6.5.2 Spell Capacity

| Spell Forge Level | Spell Slots |
|-------------------|-------------|
| 1 | 2 |
| 2 | 3 |
| 3-4 | 4 |
| 5-6 | 5 |
| 7-8 | 6 |
| 9-10 | 8 |

## 6.6 Shield System

### 6.6.1 Automatic Shields

| Trigger | Shield Duration |
|---------|-----------------|
| New player | 72 hours (one-time) |
| Attacked (40-59% damage) | 8 hours |
| Attacked (60-79% damage) | 12 hours |
| Attacked (80-99% damage) | 14 hours |
| Attacked (100% damage) | 16 hours |

### 6.6.2 Purchased Shields

| Duration | Gem Cost | Robux Cost |
|----------|----------|------------|
| 1 day | 100 gems | 50 Robux |
| 2 days | 180 gems | 80 Robux |
| 7 days | 500 gems | 200 Robux |

### 6.6.3 Shield Breaking

**Your shield BREAKS when you:**
- Attack another player
- Scout another player
- Search for opponent (even if you "Next")

**Your shield does NOT break when:**
- Attacking NPC camps
- Alliance war battles
- Revenge attacks (special exception!)

## 6.7 Revenge System

- When attacked, you have 24 hours to Revenge
- Revenge attacks do NOT break your shield
- Revenge attacks give +20% bonus loot
- Target must not have a shield (they don't get one during your revenge window)

---

# 7. Economy System

## 7.1 Resource Types

### 7.1.1 Primary Resources

| Resource | Source | Used For | Storage |
|----------|--------|----------|---------|
| **Gold** | Gold Mine, raids, trading | Troops, upgrades | Treasury |
| **Wood** | Lumber Mill, raids, trading | Buildings, walls | Warehouse |
| **Food** | Farm, raids | Troop upkeep, training | Warehouse |
| **Gems** | Gem Mine, achievements, purchase | Premium actions | No storage (account-wide) |

### 7.1.2 Special Resources

| Resource | Source | Used For |
|----------|--------|----------|
| **Trophies** | Winning battles | Matchmaking, leagues |
| **Alliance Coins** | Donations, wars | Alliance shop |
| **Battle Tokens** | Battle Pass missions | Battle Pass tier progress |

## 7.2 Resource Production

### 7.2.1 Production Rates (Per Building Per Hour)

| Building Level | Gold Mine | Lumber Mill | Farm |
|----------------|-----------|-------------|------|
| 1 | 100 | 80 | 120 |
| 2 | 150 | 120 | 180 |
| 3 | 225 | 180 | 270 |
| 4 | 340 | 270 | 405 |
| 5 | 510 | 405 | 610 |
| 6 | 765 | 610 | 915 |
| 7 | 1,150 | 915 | 1,375 |
| 8 | 1,725 | 1,375 | 2,060 |
| 9 | 2,590 | 2,060 | 3,090 |
| 10 | 3,885 | 3,090 | 4,635 |

### 7.2.2 Gem Mine (Slow Premium Currency)

| Level | Gems/Day |
|-------|----------|
| 1 | 2 |
| 2 | 3 |
| 3 | 4 |
| 4 | 5 |
| 5 | 7 |

## 7.3 Offline Resource Accumulation

### 7.3.1 Offline Earnings

- Resources accumulate while offline
- **Maximum offline duration: 24 hours**
- After 24 hours, production STOPS (encourages daily login)
- VIP players: 36 hour cap

### 7.3.2 Offline Calculation

```lua
function calculateOfflineEarnings(lastLogin, buildings)
    local offlineHours = math.min(os.time() - lastLogin, 24 * 3600) / 3600
    local earnings = {gold = 0, wood = 0, food = 0}

    for _, building in ipairs(buildings) do
        local rate = getProductionRate(building.type, building.level)
        -- Offline production is 50% of online rate
        earnings[building.resourceType] = earnings[building.resourceType] + (rate * offlineHours * 0.5)
    end

    return earnings
end
```

## 7.4 Resource Protection

### 7.4.1 Storage Protection

| Storage Level | Protection % |
|---------------|--------------|
| 1 | 10% |
| 2 | 15% |
| 3 | 20% |
| 4 | 25% |
| 5 | 30% |
| 6 | 35% |
| 7 | 40% |
| 8 | 45% |
| 9 | 50% |
| 10 | 60% |

**Example:** If you have 100,000 gold and a Level 5 Treasury (30% protection), raiders can only steal from the 70,000 unprotected gold.

## 7.5 Market System

### 7.5.1 Player Trading

Located in the Market building (unlocks TH5):

```
TRADING MECHANICS:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  POST OFFER:                                                    │
│  • Select resource to sell (Gold, Wood, Food)                  │
│  • Select resource to receive                                  │
│  • Set exchange rate                                           │
│  • Pay 5% listing fee (in gems)                                │
│  • Offer visible to all players for 24 hours                  │
│                                                                 │
│  ACCEPT OFFER:                                                  │
│  • Browse available offers                                      │
│  • Filter by resource type, rate                               │
│  • Accept partial or full amount                               │
│  • 5% transaction fee (paid by buyer)                          │
│                                                                 │
│  RATE LIMITS:                                                   │
│  • Minimum: 0.5:1 (to prevent exploitation)                    │
│  • Maximum: 3:1 (to prevent exploitation)                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 7.5.2 NPC Market (Quick Sell)

Instant sell to NPC at worse rates:

| Trade | Rate |
|-------|------|
| Gold → Wood | 1.5:1 |
| Gold → Food | 1.2:1 |
| Wood → Gold | 0.5:1 |
| Wood → Food | 0.8:1 |
| Food → Gold | 0.7:1 |
| Food → Wood | 1:1 |

## 7.6 Troop Upkeep

### 7.6.1 Food Consumption

All troops consume food per hour based on housing space:

```
Food Consumption = Total Army Housing × 2 per hour
```

**Example:** 200 housing army = 400 food/hour upkeep

### 7.6.2 Starvation Penalty

If food reaches 0:
- Troops don't die
- Troops fight at 50% effectiveness
- Cannot train new troops
- Warning notifications sent

---

# 8. Progression System

## 8.1 Player Level

### 8.1.1 Experience Sources

| Action | XP Gained |
|--------|-----------|
| Complete building upgrade | Building Level × 50 |
| Complete troop upgrade | Troop Level × 100 |
| Win battle | 10 + (Stars × 20) |
| Complete daily mission | 25-100 |
| Complete achievement | 50-500 |

### 8.1.2 Level Rewards

| Player Level | Reward |
|--------------|--------|
| 5 | 100 Gems, Title: "Settler" |
| 10 | 200 Gems, Profile Frame |
| 15 | 500 Gems, Title: "Builder" |
| 20 | 1,000 Gems, Exclusive Decoration |
| 25 | 2,000 Gems, Title: "Commander" |
| 30 | 5,000 Gems, Title: "Conqueror" |
| 40 | 10,000 Gems, Title: "Emperor" |
| 50 | 25,000 Gems, Title: "Legend", Golden Castle Skin |

## 8.2 Trophy Leagues

### 8.2.1 League Tiers

| League | Trophy Range | Daily Bonus | Loot Bonus |
|--------|--------------|-------------|------------|
| Bronze I | 0-399 | 50 gold | +0% |
| Bronze II | 400-599 | 100 gold | +2% |
| Bronze III | 600-799 | 200 gold | +4% |
| Silver I | 800-999 | 500 gold | +6% |
| Silver II | 1000-1199 | 750 gold | +8% |
| Silver III | 1200-1399 | 1,000 gold | +10% |
| Gold I | 1400-1599 | 1,500 gold | +12% |
| Gold II | 1600-1799 | 2,000 gold | +14% |
| Gold III | 1800-1999 | 2,500 gold | +16% |
| Platinum I | 2000-2199 | 3,000 gold | +18% |
| Platinum II | 2200-2399 | 3,500 gold | +20% |
| Platinum III | 2400-2599 | 4,000 gold | +22% |
| Diamond I | 2600-2799 | 5,000 gold | +24% |
| Diamond II | 2800-2999 | 6,000 gold | +26% |
| Diamond III | 3000-3499 | 7,500 gold | +28% |
| Champion | 3500-3999 | 10,000 gold | +30% |
| Legend | 4000+ | 15,000 gold | +35% |

### 8.2.2 Season Resets

- Seasons last 4 weeks
- At reset, trophies above 2000 are reduced:
  - New Trophies = 2000 + ((Old Trophies - 2000) × 0.5)
- Season rewards based on highest league reached

## 8.3 Achievement System

### 8.3.1 Achievement Categories

**Combat Achievements:**
| Achievement | Requirement | Reward |
|-------------|-------------|--------|
| First Blood | Win 1 battle | 10 Gems |
| Warrior | Win 50 battles | 50 Gems |
| Conqueror | Win 500 battles | 500 Gems |
| Warlord | Win 5,000 battles | 5,000 Gems |
| Perfect Strike | Win with 100% destruction | 25 Gems |
| Untouchable | Win without losing any troops | 100 Gems |

**Building Achievements:**
| Achievement | Requirement | Reward |
|-------------|-------------|--------|
| Architect | Build 10 buildings | 20 Gems |
| City Planner | Build 50 buildings | 100 Gems |
| Urban Legend | Max all buildings | 10,000 Gems |

**Social Achievements:**
| Achievement | Requirement | Reward |
|-------------|-------------|--------|
| Team Player | Join an alliance | 25 Gems |
| Generous | Donate 100 troops | 100 Gems |
| War Hero | Win 10 alliance wars | 500 Gems |

## 8.4 Multi-City Progression

### 8.4.1 City Slots

| Town Hall Level | City Slots |
|-----------------|------------|
| 1-4 | 1 |
| 5-7 | 2 |
| 8-9 | 3 |
| 10 | 5 |

### 8.4.2 New City Founding

**Requirements to found new city:**
1. Have available city slot
2. Pay founding cost (scales with city number)
3. Select location on World Map (within your region)

| City # | Founding Cost |
|--------|---------------|
| 2nd | 50,000 gold + 50,000 wood |
| 3rd | 150,000 gold + 150,000 wood |
| 4th | 500,000 gold + 500,000 wood |
| 5th | 1,000,000 gold + 1,000,000 wood |

### 8.4.3 Managing Multiple Cities

- Switch cities via World Map or City Selector UI
- Builders are SHARED across all cities
- Each city has separate:
  - Resources
  - Buildings
  - Troops
  - Shield status
- Resources can be transferred between cities (10% tax)

---

# 9. Alliance System

## 9.1 Alliance Overview

Alliances are player-created groups that cooperate for mutual benefit.

## 9.2 Alliance Creation

### 9.2.1 Requirements

- Town Hall Level 3+
- 1,000 gold founding cost
- Choose name (3-20 characters)
- Choose tag (3-5 characters)
- Choose emblem (from preset options)
- Set description

### 9.2.2 Alliance Settings

| Setting | Options |
|---------|---------|
| Join Type | Open / Invite Only / Closed |
| Minimum Trophies | 0 - 3000 |
| Minimum TH Level | 1 - 10 |
| Language | All languages |
| War Frequency | Always / Twice Weekly / Once Weekly / Never |

## 9.3 Alliance Roles

| Role | Members | Permissions |
|------|---------|-------------|
| **Leader** | 1 | Full control, promote/demote, settings, disband |
| **Co-Leader** | Up to 5 | Kick, accept, start war, promote to Elder |
| **Elder** | Up to 10 | Accept applications |
| **Member** | Unlimited | Donate, chat, participate |

## 9.4 Alliance Features

### 9.4.1 Donations

**Troop Donations:**
- Request troops in chat
- Alliance members can donate from their army
- Donated troops go to your Castle (defense) or Embassy (attack reinforcements)
- Earn Alliance Coins for donating

| Donation | Alliance Coins Earned |
|----------|----------------------|
| Per troop housing donated | 1 coin per housing |
| Daily donation cap | 50 housing |

### 9.4.2 Alliance Chat

- Real-time text chat
- System messages for join/leave, donations, war results
- Moderation tools for leaders
- Profanity filter (Roblox standard)

### 9.4.3 Alliance Territory

**World Map Territory:**
- Alliance can claim a territory on World Map
- Territory = 5x5 region around a central point
- Members in territory get +10% resource production
- Territory can be contested in Territory Wars

**Claiming Territory:**
1. Leader selects unclaimed territory
2. Alliance pays 10,000 gold (collective)
3. Territory is claimed for 7 days
4. Must be renewed or can be lost

### 9.4.4 Alliance Wars

**War Declaration:**
- Co-Leader or Leader starts matchmaking
- Matched with similar alliance (member count ±3, total power ±15%)
- Preparation Day: 24 hours to scout, plan
- War Day: 24 hours to attack

**War Mechanics:**
```
WAR STRUCTURE:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  PREPARATION DAY (24 hours):                                    │
│  • Scout enemy bases (free)                                     │
│  • Plan attacks in war chat                                     │
│  • Cannot attack yet                                            │
│  • Donate to alliance members                                   │
│                                                                 │
│  WAR DAY (24 hours):                                            │
│  • Each member gets 2 attacks                                   │
│  • Attack any enemy base                                        │
│  • Stars earned count for alliance total                       │
│  • Can only 3-star a base once (no double-dipping)             │
│                                                                 │
│  VICTORY CONDITION:                                             │
│  • Most total stars wins                                        │
│  • Tie-breaker: Total destruction %                            │
│                                                                 │
│  REWARDS:                                                       │
│  • Winning Alliance: War Chest (gems, resources)               │
│  • Individual: Based on stars earned                           │
│  • Participation: Bonus for using both attacks                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**War Rewards:**

| Performance | Winner | Loser |
|-------------|--------|-------|
| Alliance | 500 gems (split) + resources | 100 gems (split) |
| Per star earned | 10 gems | 5 gems |
| Both attacks used | +50 gems | +25 gems |

## 9.5 Alliance Shop

Currency: **Alliance Coins**

| Item | Cost | Description |
|------|------|-------------|
| Resource Pack (Small) | 50 coins | 10,000 of each resource |
| Resource Pack (Large) | 200 coins | 50,000 of each resource |
| Speedup (1 hour) | 30 coins | Skip 1 hour of any timer |
| Speedup (8 hours) | 200 coins | Skip 8 hours of any timer |
| Builder Potion | 500 coins | All builders work 10x faster for 1 hour |
| Research Potion | 500 coins | Academy research 10x faster for 1 hour |
| Exclusive Troop Skin | 1,000 coins | Visual upgrade for troops |
| Alliance Banner | 2,000 coins | Decoration for your city |

## 9.6 Alliance Perks (Post-Launch)

Future expansion will include:

- **Alliance Buildings:** Collective structures that buff all members
- **Alliance Bosses:** Weekly PvE boss that alliance attacks together
- **Alliance Seasons:** Quarterly rankings with exclusive rewards

---

# 10. Monetization

## 10.1 Monetization Philosophy

**Core Principle: Pay for TIME, not POWER**

- Everything purchasable can also be earned through gameplay
- Paying players progress FASTER, not STRONGER
- No exclusive troops or stat advantages
- Cosmetics and convenience only

## 10.2 Premium Currency

### 10.2.1 Gems

**Earning Gems (Free):**
| Source | Amount |
|--------|--------|
| Gem Mine (daily) | 2-7 gems |
| Achievements | 10-10,000 gems |
| Daily rewards | 5-50 gems |
| Battle Pass (free track) | 100 gems/season |
| Removing obstacles | 1-5 gems |
| Alliance wars | 5-50 gems |

**Buying Gems (Robux):**
| Package | Gems | Robux | Bonus |
|---------|------|-------|-------|
| Handful | 80 | 99 | - |
| Pouch | 500 | 449 | +11% |
| Bag | 1,200 | 899 | +25% |
| Box | 2,500 | 1,599 | +35% |
| Chest | 6,500 | 3,399 | +50% |
| Vault | 14,000 | 5,999 | +75% |

### 10.2.2 Gem Uses

| Use | Cost |
|-----|------|
| Speed up 1 hour | 20 gems |
| Speed up 1 day | 260 gems |
| Buy 10,000 gold | 50 gems |
| Buy 10,000 wood | 50 gems |
| Buy 10,000 food | 40 gems |
| 2nd Builder | 250 gems |
| 3rd Builder | 500 gems |
| 4th Builder | 1,000 gems |
| 5th Builder | 2,000 gems |
| Shield (1 day) | 100 gems |
| Shield (7 days) | 500 gems |

## 10.3 Battle Pass

### 10.3.1 Structure

- **Season Length:** 28 days
- **Total Tiers:** 50
- **Free Track:** Available to all
- **Premium Track:** 450 Robux

### 10.3.2 Tier Rewards

| Tier | Free Track | Premium Track |
|------|------------|---------------|
| 1 | 500 Gold | 2,000 Gold + Warrior Skin |
| 5 | 10 Gems | 50 Gems + 1hr Speedup |
| 10 | 1,000 Wood | 5,000 Wood + Building Decoration |
| 15 | Common Troop Skin | Rare Troop Skin + Emote |
| 20 | 20 Gems | 100 Gems + Resource Boost |
| 25 | 2,000 Food | 10,000 Food + Title |
| 30 | Training Speedup | Training Speedup + Castle Skin |
| 35 | 30 Gems | 150 Gems + Profile Frame |
| 40 | 5,000 Gold | 25,000 Gold + Exclusive Banner |
| 45 | 50 Gems | 250 Gems + War Paint (troops) |
| 50 | Bronze Frame | **LEGENDARY COMMANDER** + Gold Frame |

### 10.3.3 Battle Token Sources

| Source | Tokens |
|--------|--------|
| Win battle | 5 |
| Win alliance war attack | 10 |
| Complete daily mission | 15 |
| Login streak (7 days) | 25 |
| Complete weekly challenge | 50 |

### 10.3.4 Tier Buy Option

- Skip tiers: 150 Robux per tier
- Buy remaining tiers: Discounted bundle

## 10.4 VIP Subscription

### 10.4.1 VIP Benefits

**Monthly Cost:** 450 Robux

| Benefit | Value |
|---------|-------|
| 50 Gems daily | 1,500 gems/month |
| 2nd Builder permanent | 250 gems value |
| +20% resource production | Significant boost |
| +10% battle loot | Extra resources |
| -20% upgrade times | Faster progression |
| VIP chat badge | Status symbol |
| VIP-only deals | Exclusive offers |
| 36-hour offline cap | vs 24 hours |
| Priority matchmaking | Faster opponent search |

### 10.4.2 VIP Tiers (Future)

| Tier | Months Subscribed | Extra Perk |
|------|-------------------|------------|
| VIP Bronze | 1-2 | Base benefits |
| VIP Silver | 3-5 | +5% more gems daily |
| VIP Gold | 6-11 | +10% more gems + exclusive skin |
| VIP Platinum | 12+ | +15% more gems + exclusive troop |

## 10.5 Starter Packs

One-time purchases with exceptional value:

| Pack | Robux | Contents | Unlock Condition |
|------|-------|----------|------------------|
| Beginner's Pack | 99 | 500 gems, 10,000 each resource, 1 Rare Troop | TH1-2 |
| Builder's Pack | 249 | 2nd Builder, 1,000 gems, 3x 1hr speedups | TH3+ |
| Commander's Pack | 499 | Rare Commander, 2,500 gems, 50,000 resources | TH5+ |
| Conqueror's Pack | 999 | Epic Commander, 6,000 gems, 5x speedups | TH7+ |
| Legend Pack | 1,999 | Legendary Commander, 15,000 gems, Exclusive Skin | TH9+ |

## 10.6 Special Offers

### 10.6.1 Triggered Offers

| Trigger | Offer |
|---------|-------|
| First defeat | "Revenge Pack" - Troops + Shield |
| TH upgrade complete | Growth bundle for new TH level |
| Return after 7+ days | "Welcome Back" - Resources + Gems |
| Low resources | "Resource Rescue" - Discounted pack |

### 10.6.2 Limited Time Offers

- Flash Sales (24 hours)
- Weekend Warrior (Friday-Sunday)
- Holiday Events (Seasonal)

## 10.7 Cosmetics Shop

All cosmetics are visual only with zero gameplay impact:

| Category | Examples | Price Range |
|----------|----------|-------------|
| Troop Skins | Golden Knight, Fire Archer | 100-500 gems |
| Building Skins | Crystal Farm, Dark Castle | 200-1,000 gems |
| Castle Themes | Winter, Volcanic, Enchanted | 500-2,000 gems |
| Emotes | Victory dance, Taunt, Wave | 50-200 gems |
| Profile Frames | League frames, Event frames | Achievement/Purchase |
| Banners | Alliance banners, Player flags | 100-500 gems |

---

# 11. Engagement Systems

## 11.1 Daily Login Rewards

### 11.1.1 Weekly Cycle

| Day | Reward |
|-----|--------|
| 1 | 1,000 Gold |
| 2 | 1,000 Wood |
| 3 | 10 Gems |
| 4 | 1,000 Food |
| 5 | Training Speedup (30 min) |
| 6 | 25 Gems |
| 7 | **Rare Chest** (random rare item) |

**Streak Bonus:** Complete all 7 days → 50 bonus gems

### 11.1.2 Monthly Calendar

Additional monthly rewards on specific days:
- Day 7: 100 Gems
- Day 14: Rare Troop
- Day 21: Epic Decoration
- Day 28: Legendary Chest OR 500 Gems

## 11.2 Daily Missions

### 11.2.1 Mission Pool

| Mission | Requirement | Reward |
|---------|-------------|--------|
| Train troops | Train 50 housing worth | 15 tokens, 500 gold |
| Win battles | Win 3 battles | 20 tokens, 750 gold |
| Collect resources | Collect 10,000 total | 10 tokens, 5 gems |
| Upgrade building | Complete 1 upgrade | 15 tokens, 1,000 gold |
| Donate troops | Donate 10 housing | 10 tokens, 500 gold |
| Use spells | Use 5 spells in battle | 15 tokens, 10 gems |

### 11.2.2 Daily Mission Slots

- 3 missions available per day
- Refresh at midnight (player's local time)
- Complete all 3 → Bonus mission chest

## 11.3 Weekly Challenges

| Challenge | Requirement | Reward |
|-----------|-------------|--------|
| War Veteran | Win 10 attacks | 50 tokens, 100 gems |
| Architect | Complete 5 upgrades | 40 tokens, 50 gems |
| Generous | Donate 100 troop housing | 30 tokens, 75 gems |
| Collector | Collect 100,000 resources | 25 tokens, 50 gems |

## 11.4 Achievements (Long-term)

See Section 8.3 for full achievement list.

## 11.5 Push Notifications

### 11.5.1 Notification Types

| Event | Notification |
|-------|--------------|
| Building complete | "Your [Building] is ready!" |
| Troops trained | "Your troops have finished training!" |
| Under attack | "[Player] is attacking your city!" |
| Shield expiring | "Your shield expires in 30 minutes!" |
| Storage full | "Your [Resource] storage is full!" |
| Alliance war starting | "War Day begins in 1 hour!" |
| Daily reward ready | "Your daily reward is waiting!" |
| Inactivity (24h) | "Your city misses you! Resources are piling up." |

### 11.5.2 Notification Settings

Players can toggle each category:
- Battle alerts
- Building/Training complete
- Alliance notifications
- Promotional notifications

## 11.6 Returning Player Mechanics

### 11.6.1 Welcome Back Bonus

If player is away 3+ days:

| Days Away | Bonus |
|-----------|-------|
| 3-6 days | 24hr Shield + 500 gems |
| 7-13 days | 48hr Shield + 1,000 gems + Resources |
| 14-29 days | 72hr Shield + 2,000 gems + Rare Troop |
| 30+ days | 7-day Shield + 5,000 gems + Care Package |

### 11.6.2 Catch-Up Mechanics

- Reduced upgrade times for first 48 hours back
- Double resources from first 10 battles
- Free Battle Pass tier skip (if active season)

---

# 12. UI/UX Design

## 12.1 Design Principles

1. **Clarity:** Every action should be obvious
2. **Feedback:** Immediate response to all inputs
3. **Consistency:** Same patterns across all screens
4. **Accessibility:** Work on all devices (PC/Mobile/Console)
5. **Progression Visibility:** Always show what's next

## 12.2 Main HUD (City View)

```
┌─────────────────────────────────────────────────────────────────┐
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │  [GEMS: 💎 1,234]  [GOLD: 🪙 45,678]  [WOOD: 🪵 23,456]     │ │
│ │  [FOOD: 🌾 34,567]  [TROPHIES: 🏆 1,234]                    │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌────────┐                                         ┌──────────┐ │
│ │ PLAYER │                                         │  SHOP    │ │
│ │ LEVEL  │                                         │  BUTTON  │ │
│ │  32    │                                         └──────────┘ │
│ └────────┘                                                      │
│                                                                 │
│                    [CITY VIEW AREA]                             │
│                                                                 │
│                                                                 │
│                                                                 │
│                                                                 │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐         │
│ │  MAP   │ │ ATTACK │ │  ARMY  │ │ALLIANCE│ │ BATTLE │         │
│ │  🗺️    │ │  ⚔️    │ │  🛡️    │ │  🏰    │ │  PASS  │         │
│ └────────┘ └────────┘ └────────┘ └────────┘ └────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

## 12.3 Building Interaction

**Tap on Building:**

```
┌─────────────────────────────────────────────────────────────────┐
│                     BARRACKS (Level 4)                          │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  [TRAIN]   [UPGRADE]   [INFO]   [MOVE]                     │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  UPGRADE TO LEVEL 5:                                            │
│  Cost: 5,000 Gold, 3,000 Wood                                   │
│  Time: 2 hours                                                  │
│  Unlocks: Knight troop                                          │
│                                                                 │
│         [UPGRADE NOW]        [SPEED UP: 💎 52]                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 12.4 Battle UI

```
┌─────────────────────────────────────────────────────────────────┐
│  ⏱️ 2:45                                    DESTRUCTION: 45%    │
│                                              ⭐ (earned)        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                     [BATTLE ARENA]                              │
│                                                                 │
│                   Enemy City Layout                             │
│                                                                 │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  TROOPS:                          SPELLS:                       │
│  [⚔️ x20] [🏹 x30] [🐎 x5]       [⚡] [❤️] [🧊]                  │
│                                                                 │
│           [END BATTLE]                                          │
└─────────────────────────────────────────────────────────────────┘
```

## 12.5 Key Screens

### 12.5.1 Screen List

| Screen | Purpose |
|--------|---------|
| Main Menu | Entry, settings, account |
| City View | Building management |
| World Map | Navigation, targets |
| Battle | Combat gameplay |
| Army | Troop management, training |
| Alliance | Social features |
| Battle Pass | Season progression |
| Shop | Monetization |
| Leaderboards | Rankings |
| Profile | Stats, achievements |
| Settings | Game options |

### 12.5.2 Navigation Flow

```
MAIN MENU
    │
    ├──▶ CITY VIEW (Default)
    │       │
    │       ├──▶ Building Menu
    │       ├──▶ Army Screen
    │       ├──▶ Shop
    │       └──▶ World Map
    │               │
    │               ├──▶ Target Selection
    │               │       │
    │               │       └──▶ Battle
    │               │               │
    │               │               └──▶ Results ──▶ City View
    │               │
    │               └──▶ Other Cities (if owned)
    │
    ├──▶ Alliance HQ
    │       │
    │       ├──▶ Chat
    │       ├──▶ War Room
    │       ├──▶ Members
    │       └──▶ Alliance Shop
    │
    └──▶ Battle Pass
            │
            └──▶ Tier Progression
```

## 12.6 Mobile Optimization

| Feature | Implementation |
|---------|----------------|
| Touch targets | Minimum 44x44 pixels |
| Gestures | Pinch zoom, drag pan, tap select |
| One-hand mode | Key actions reachable with thumb |
| Portrait/Landscape | Both supported, landscape preferred |
| Loading | Background loading, no long waits |

## 12.7 Accessibility

| Feature | Implementation |
|---------|----------------|
| Color blindness | Patterns + colors for all indicators |
| Text size | Scalable UI option |
| Audio cues | Sound feedback for actions |
| Captions | All dialogue captioned |
| Control remapping | Console controller options |

---

# 13. Onboarding & Tutorial

## 13.1 Tutorial Philosophy

- **Learn by doing**, not reading
- **One concept at a time**
- **Immediate rewards** for completing steps
- **Skip option** after basics (for returning players)
- **Under 5 minutes** for core tutorial

## 13.2 Tutorial Flow

### Phase 1: First 2 Minutes

```
STEP 1: Build First Building (30 sec)
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  "Welcome, Commander! Let's build your first Gold Mine."        │
│                                                                 │
│  [Arrow pointing to empty spot]                                 │
│                                                                 │
│  Player taps spot → Gold Mine appears (instant, no wait)        │
│                                                                 │
│  REWARD: "Great job! Here's 100 gold to get started."           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

STEP 2: Collect Resources (20 sec)
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  "Your Gold Mine produces gold. Tap to collect!"                │
│                                                                 │
│  [Gold pile appears above mine]                                 │
│                                                                 │
│  Player taps → Satisfying coin sound + animation                │
│                                                                 │
│  REWARD: 200 gold collected                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

STEP 3: Train First Troop (30 sec)
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  "Now build a Barracks to train Warriors."                      │
│                                                                 │
│  [Arrow pointing to barracks spot]                              │
│                                                                 │
│  Player builds → "Tap to train your first Warrior!"             │
│                                                                 │
│  [Training is instant for tutorial]                             │
│                                                                 │
│  REWARD: 1 Warrior + "You now have an army!"                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Phase 2: First Battle (2 Minutes)

```
STEP 4: Attack NPC Base (60 sec)
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  "Time to attack! This goblin camp has stolen our gold."        │
│                                                                 │
│  [Auto-navigate to easy NPC base]                               │
│                                                                 │
│  "Tap anywhere to deploy your Warriors!"                        │
│                                                                 │
│  [Player deploys → Warriors destroy weak base easily]           │
│                                                                 │
│  VICTORY! 100% destruction achieved!                            │
│                                                                 │
│  REWARD: 500 gold, 200 wood, "Congratulations, Commander!"      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

STEP 5: Upgrade Building (30 sec)
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  "Use your loot to upgrade the Gold Mine!"                      │
│                                                                 │
│  [Arrow to upgrade button]                                      │
│                                                                 │
│  [Upgrade is instant for tutorial]                              │
│                                                                 │
│  "Level 2! You now produce more gold."                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Phase 3: Tutorial Complete

```
STEP 6: Summary & Next Steps
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  🎉 TUTORIAL COMPLETE! 🎉                                       │
│                                                                 │
│  You've learned:                                                │
│  ✓ Building structures                                          │
│  ✓ Collecting resources                                         │
│  ✓ Training troops                                              │
│  ✓ Attacking enemies                                            │
│  ✓ Upgrading buildings                                          │
│                                                                 │
│  STARTER REWARDS:                                               │
│  • 500 Gems                                                     │
│  • 72-hour Shield                                               │
│  • 5,000 of each resource                                       │
│                                                                 │
│  NEXT GOALS:                                                    │
│  • Upgrade Town Hall to Level 2                                 │
│  • Join an Alliance                                             │
│  • Win 5 battles                                                │
│                                                                 │
│              [START PLAYING]                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 13.3 Progressive Tutorials

Additional tutorials unlock as player progresses:

| Unlock | Tutorial |
|--------|----------|
| TH Level 2 | Advanced combat (spells) |
| TH Level 3 | Alliance features |
| TH Level 4 | Academy research |
| TH Level 5 | Market trading |
| TH Level 5 | Multi-city management |
| First Alliance War | War mechanics |

## 13.4 New Player Protection

| Protection | Duration |
|------------|----------|
| Attack shield | 72 hours |
| Matchmaking protection | First 10 battles against NPC/easy |
| Reduced loss on defense | First 5 defenses: 50% less resource loss |
| Daily login calendar | 7-day new player calendar (better rewards) |

---

# 14. Events & Live Operations

## 14.1 Event Calendar

### 14.1.1 Weekly Events

| Day | Event |
|-----|-------|
| Monday | War Monday (2x War loot) |
| Tuesday | Training Tuesday (Troops train 50% faster) |
| Wednesday | Wild Wednesday (NPC camps give 2x rewards) |
| Thursday | Territory Thursday (Alliance territory battles) |
| Friday | Farming Friday (Resources +50%) |
| Saturday | Siege Saturday (Siege troops cost 50% less) |
| Sunday | Super Sunday (All bonuses at 25%) |

### 14.1.2 Monthly Events

| Week | Event Type |
|------|------------|
| Week 1 | Clan Games (collective goals) |
| Week 2 | Builder Base (special building event) |
| Week 3 | League Season Finals |
| Week 4 | Limited-time Challenge |

### 14.1.3 Seasonal Events

| Season | Event | Duration |
|--------|-------|----------|
| Winter (Dec-Feb) | Frost Festival | 3 weeks |
| Spring (Mar-May) | Dragon's Rise | 2 weeks |
| Summer (Jun-Aug) | Beach Bash | 3 weeks |
| Fall (Sep-Nov) | Harvest Warfare | 2 weeks |
| Year-End | Anniversary Event | 1 week |

## 14.2 Event Mechanics

### 14.2.1 Challenge Events

```
CHALLENGE EVENT STRUCTURE:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  EVENT: Dragon's Rise                                           │
│  DURATION: 14 days                                              │
│                                                                 │
│  OBJECTIVES:                                                    │
│  ├── Win 50 battles ─────────────────────── 500 Event Tokens   │
│  ├── Destroy 100 Dragon Roosts ──────────── 750 Event Tokens   │
│  ├── Use Dragons in 30 attacks ──────────── 1,000 Event Tokens │
│  └── Win 10 Alliance War attacks ────────── 500 Event Tokens   │
│                                                                 │
│  EVENT SHOP:                                                    │
│  ├── Dragon Skin (Fire) ─────────────────── 500 Tokens         │
│  ├── Dragon Skin (Ice) ──────────────────── 500 Tokens         │
│  ├── Legendary Dragon Egg ───────────────── 2,000 Tokens       │
│  ├── Resource Pack (Large) ──────────────── 300 Tokens         │
│  └── Exclusive Castle Theme ─────────────── 1,500 Tokens       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 14.2.2 Clan Games

```
CLAN GAMES:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  ALLIANCE COLLECTIVE GOAL: 50,000 points                        │
│  CURRENT: 32,450 / 50,000                                       │
│                                                                 │
│  YOUR CONTRIBUTION: 2,350 points                                │
│                                                                 │
│  AVAILABLE CHALLENGES (pick one at a time):                     │
│  ├── Win 5 battles (500 points)                                │
│  ├── Donate 50 troop housing (300 points)                      │
│  ├── Destroy 20 Wizard Towers (400 points)                     │
│  └── Upgrade 3 buildings (350 points)                          │
│                                                                 │
│  REWARDS AT THRESHOLDS:                                         │
│  ├── 10,000: Resource Pack                                     │
│  ├── 25,000: Gem Pack (100)                                    │
│  ├── 40,000: Builder Potion                                    │
│  └── 50,000: Legendary Chest                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 14.3 Content Updates

### 14.3.1 Update Schedule

| Type | Frequency | Content |
|------|-----------|---------|
| Hotfix | As needed | Bug fixes, balance |
| Minor Update | Every 2 weeks | Events, QoL |
| Major Update | Every 6-8 weeks | New features, troops, buildings |
| Season Update | Every 3 months | Battle Pass, meta changes |

### 14.3.2 Update Communication

- In-game news popup
- Loading screen tips
- Discord announcements
- Roblox game page updates

---

# 15. Technical Architecture

## 15.1 Roblox Services Used

| Service | Purpose |
|---------|---------|
| **DataStoreService** | Player data persistence |
| **TeleportService** | Multi-place navigation |
| **MessagingService** | Cross-server communication |
| **MarketplaceService** | Robux purchases |
| **BadgeService** | Achievements |
| **PolicyService** | Age-appropriate content |
| **TextService** | Chat filtering |

## 15.2 Data Architecture

### 15.2.1 Player Data Structure

```lua
PlayerData = {
    -- Account
    userId = 123456789,
    username = "PlayerName",
    created = 1704067200,
    lastLogin = 1704153600,

    -- Progression
    level = 32,
    experience = 45000,
    trophies = 1856,
    gems = 1234,

    -- Cities (array, supports multiple)
    cities = {
        {
            id = "city_1",
            name = "Capital",
            location = {x = 100, y = 50},
            buildings = {...},
            troops = {...},
            resources = {gold = 45678, wood = 23456, food = 34567},
            shield = {active = true, expires = 1704240000},
        },
        -- Additional cities...
    },

    -- Alliance
    alliance = {
        id = "alliance_123",
        role = "Elder",
        donations = 1500,
        warStars = 45,
    },

    -- Battle Pass
    battlePass = {
        season = 5,
        tier = 23,
        tokens = 340,
        premium = true,
        claimed = {1, 2, 3, ...23},
    },

    -- Achievements
    achievements = {"first_blood", "warrior", ...},

    -- Settings
    settings = {
        notifications = true,
        music = 0.8,
        sfx = 1.0,
    },
}
```

### 15.2.2 City Data Structure

```lua
CityData = {
    id = "city_1",
    ownerId = 123456789,
    name = "Capital",

    -- World Map position
    region = "NORTH",
    position = {x = 100, y = 50},

    -- Buildings (dictionary by buildingId)
    buildings = {
        ["building_1"] = {
            type = "TownHall",
            level = 5,
            position = {x = 20, y = 20},
            upgrading = false,
            upgradeCompletes = nil,
        },
        ["building_2"] = {
            type = "Barracks",
            level = 4,
            position = {x = 15, y = 22},
            trainingQueue = {"Warrior", "Warrior", "Knight"},
            queueCompletes = 1704200000,
        },
        -- ... more buildings
    },

    -- Troops in army camps
    troops = {
        Warrior = 20,
        Archer = 30,
        Knight = 5,
    },

    -- Resources
    resources = {
        gold = 45678,
        wood = 23456,
        food = 34567,
    },

    -- Last collection time (for offline earnings)
    lastCollection = 1704150000,

    -- Defense log
    defenseLog = {
        {attackerId = 987654321, result = "loss", damage = 65, timestamp = 1704100000},
        -- ... more logs
    },

    -- Shield
    shield = {
        active = true,
        expires = 1704240000,
        type = "post_attack",
    },

    -- Occupation (if occupied by another player)
    occupation = nil, -- or {occupierId = ..., expires = ...}
}
```

### 15.2.3 Alliance Data Structure

```lua
AllianceData = {
    id = "alliance_123",
    name = "Dragon Warriors",
    tag = "DW",
    emblem = "dragon_red",
    description = "Active war clan!",

    -- Settings
    joinType = "invite_only",
    minTrophies = 1000,
    minTH = 5,
    warFrequency = "twice_weekly",

    -- Members
    members = {
        {userId = 123456789, role = "Leader", trophies = 2500, donations = 500},
        {userId = 234567890, role = "Co-Leader", trophies = 2200, donations = 450},
        -- ... more members
    },

    -- Territory
    territory = {
        region = "NORTH",
        center = {x = 150, y = 75},
        claimedAt = 1704000000,
        expires = 1704604800,
    },

    -- War state
    war = {
        active = true,
        opponentId = "alliance_456",
        phase = "war_day", -- or "preparation"
        phaseEnds = 1704200000,
        ourStars = 45,
        theirStars = 38,
    },

    -- Stats
    stats = {
        totalWars = 50,
        warsWon = 35,
        totalTrophies = 45000,
    },
}
```

## 15.3 Server Architecture

### 15.3.1 Place Responsibilities

| Place | Responsibilities |
|-------|------------------|
| Main Menu | Authentication, initial data load |
| City View | Building management, troop training, offline earnings |
| World Map | City discovery, target selection, navigation |
| Battle Arena | Combat simulation, result calculation |
| Alliance HQ | Chat, donations, war management |
| Market | Trade listings, transactions |

### 15.3.2 Cross-Server Communication

```lua
-- Example: Notifying player of incoming attack
MessagingService:PublishAsync("attack_notification", {
    targetUserId = 123456789,
    attackerName = "EnemyPlayer",
    cityId = "city_1",
    timestamp = os.time(),
})

-- Receiving on target's server
MessagingService:SubscribeAsync("attack_notification", function(message)
    local data = message.Data
    if data.targetUserId == localPlayer.UserId then
        showAttackNotification(data.attackerName)
    end
end)
```

## 15.4 Performance Optimization

### 15.4.1 City View Optimization

| Technique | Implementation |
|-----------|----------------|
| LOD (Level of Detail) | Reduce building detail at far zoom |
| Frustum Culling | Don't render off-screen buildings |
| Instance Pooling | Reuse building models |
| Batch Rendering | Group similar buildings |

### 15.4.2 Battle Optimization

| Technique | Implementation |
|-----------|----------------|
| Server-side simulation | Client receives state updates |
| Troop grouping | Similar troops move as units |
| Simplified collision | Use simple hitboxes |
| Damage batching | Calculate damage in ticks |

### 15.4.3 Data Optimization

| Technique | Implementation |
|-----------|----------------|
| Lazy loading | Only load active city data |
| Compression | Compress building layouts |
| Caching | Cache frequently accessed data |
| Throttling | Limit DataStore requests |

## 15.5 Security Considerations

### 15.5.1 Anti-Cheat Measures

| Threat | Mitigation |
|--------|------------|
| Speed hacks | Server-authoritative timers |
| Resource manipulation | Server-side resource tracking |
| Battle manipulation | Server-side combat simulation |
| Fake purchases | Verify with MarketplaceService |

### 15.5.2 Data Validation

```lua
-- Example: Validate building placement
function validateBuildingPlacement(player, buildingType, position)
    local cityData = getCityData(player)

    -- Check if player has resources
    local cost = getBuildingCost(buildingType)
    if cityData.resources.gold < cost.gold then
        return false, "Insufficient gold"
    end

    -- Check if position is valid
    if not isPositionEmpty(cityData, position) then
        return false, "Position occupied"
    end

    -- Check if player can build this type
    if not canBuildType(cityData.townHallLevel, buildingType) then
        return false, "Town Hall too low"
    end

    return true, nil
end
```

---

# 16. Audio Design

## 16.1 Music

### 16.1.1 Music Tracks

| Location | Style | Mood |
|----------|-------|------|
| Main Menu | Orchestral | Epic, welcoming |
| City View | Medieval ambient | Peaceful, productive |
| World Map | Adventure theme | Exploration, tension |
| Battle | Combat drums | Intense, exciting |
| Victory | Fanfare | Triumphant |
| Defeat | Somber | Reflective, not punishing |
| Alliance | Fellowship theme | Community, warmth |

### 16.1.2 Dynamic Music

- Battle music intensifies as destruction increases
- City music changes based on time of day (if implemented)
- Special event music during holidays

## 16.2 Sound Effects

### 16.2.1 UI Sounds

| Action | Sound |
|--------|-------|
| Button tap | Soft click |
| Building placed | Hammer strike |
| Upgrade complete | Triumphant chime |
| Resource collected | Coin jingle |
| Achievement unlocked | Fanfare |
| Notification | Bell ding |

### 16.2.2 Combat Sounds

| Action | Sound |
|--------|-------|
| Troop deployed | War cry |
| Sword strike | Metal clang |
| Arrow shot | Whoosh + thud |
| Spell cast | Magic whoosh |
| Building destroyed | Crash + crumble |
| Troop death | Poof (not violent) |

### 16.2.3 Ambient Sounds

| Location | Ambient |
|----------|---------|
| City | Birds, wind, distant hammering |
| Battle | Distant shouts, fire crackling |
| World Map | Wind, occasional eagle cry |

## 16.3 Audio Settings

- Master Volume (0-100%)
- Music Volume (0-100%)
- SFX Volume (0-100%)
- Mute All toggle

---

# 17. Metrics & Analytics

## 17.1 Key Performance Indicators (KPIs)

### 17.1.1 Engagement Metrics

| Metric | Target | Description |
|--------|--------|-------------|
| DAU | Growth | Daily Active Users |
| MAU | Growth | Monthly Active Users |
| DAU/MAU | >20% | Stickiness ratio |
| Session Length | 15-30 min | Average play time |
| Sessions/Day | >2 | Return frequency |

### 17.1.2 Retention Metrics

| Metric | Target | Description |
|--------|--------|-------------|
| D1 Retention | >40% | Return next day |
| D7 Retention | >20% | Return after week |
| D30 Retention | >10% | Return after month |

### 17.1.3 Monetization Metrics

| Metric | Description |
|--------|-------------|
| Conversion Rate | % of players who make first purchase |
| ARPU | Average Revenue Per User |
| ARPPU | Average Revenue Per Paying User |
| LTV | Lifetime Value of player |

## 17.2 Funnel Tracking

### 17.2.1 New Player Funnel

```
FUNNEL STAGES:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  1. Game Loaded ─────────────────────────────────────── 100%    │
│     │                                                           │
│  2. Tutorial Started ────────────────────────────────── 95%     │
│     │                                                           │
│  3. Tutorial Completed ──────────────────────────────── 85%     │
│     │                                                           │
│  4. First Attack ────────────────────────────────────── 80%     │
│     │                                                           │
│  5. First TH Upgrade ────────────────────────────────── 60%     │
│     │                                                           │
│  6. Joined Alliance ─────────────────────────────────── 40%     │
│     │                                                           │
│  7. First Purchase ──────────────────────────────────── 5%      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 17.2.2 Key Events to Track

| Event | Data Points |
|-------|-------------|
| `game_start` | Platform, referral source |
| `tutorial_step` | Step number, time spent |
| `building_placed` | Building type, level |
| `battle_started` | Troop composition, target TH |
| `battle_ended` | Result, destruction %, stars |
| `purchase_made` | Item, price, currency |
| `alliance_joined` | Alliance size, level |
| `session_end` | Duration, activities performed |

## 17.3 A/B Testing Framework

### 17.3.1 Test Areas

| Area | Variables |
|------|-----------|
| Onboarding | Tutorial length, rewards |
| Monetization | Pricing, bundle contents |
| Engagement | Daily rewards, notification timing |
| Balance | Troop stats, building costs |

### 17.3.2 Test Implementation

```lua
-- Example: A/B test for starter pack price
local testGroup = getABTestGroup(player.UserId, "starter_pack_price")

if testGroup == "A" then
    starterPackPrice = 99  -- Control
elseif testGroup == "B" then
    starterPackPrice = 79  -- Test lower price
else
    starterPackPrice = 129 -- Test higher price
end

trackEvent("starter_pack_shown", {
    group = testGroup,
    price = starterPackPrice,
})
```

---

# 18. Development Roadmap

## 18.1 Development Phases

### Phase 1: Core Foundation (Weeks 1-4)

**Goal:** Playable single-city experience

| Week | Deliverables |
|------|--------------|
| 1 | Project setup, basic city grid, Town Hall |
| 2 | Resource buildings (Farm, Mine, Mill), collection system |
| 3 | Barracks, troop training, Army Camp |
| 4 | Basic combat (vs NPC), victory/defeat, loot |

**Milestone:** Player can build city, train troops, attack NPCs

### Phase 2: Core Loop Complete (Weeks 5-8)

**Goal:** Full build-train-attack-loot loop

| Week | Deliverables |
|------|--------------|
| 5 | PvP matchmaking, attack other players |
| 6 | Defensive buildings (Walls, Towers, Cannons) |
| 7 | Shield system, offline earnings |
| 8 | Trophy system, basic leaderboard |

**Milestone:** Player can attack and defend against other players

### Phase 3: Progression & Variety (Weeks 9-12)

**Goal:** Deep progression with varied content

| Week | Deliverables |
|------|--------------|
| 9 | TH upgrade gating, all economy buildings |
| 10 | All military buildings (Stable, Mage Tower, etc.) |
| 11 | All troops (cavalry, magic, siege) |
| 12 | Academy research, troop upgrades |

**Milestone:** Full building and troop variety

### Phase 4: Social Features (Weeks 13-16)

**Goal:** Alliance system and social gameplay

| Week | Deliverables |
|------|--------------|
| 13 | Alliance creation, joining, chat |
| 14 | Troop donations, Embassy |
| 15 | Alliance Wars (preparation + war day) |
| 16 | Alliance territory, leaderboards |

**Milestone:** Players can join alliances and war

### Phase 5: Monetization (Weeks 17-19)

**Goal:** Sustainable revenue model

| Week | Deliverables |
|------|--------------|
| 17 | Gem system, shop, speed-ups |
| 18 | Battle Pass system |
| 19 | VIP subscription, starter packs |

**Milestone:** Full monetization system live

### Phase 6: Multi-City & Endgame (Weeks 20-23)

**Goal:** Empire building and endgame content

| Week | Deliverables |
|------|--------------|
| 20 | World Map, multiple city support |
| 21 | City founding, city switching |
| 22 | Occupation system, conquest mechanics |
| 23 | Dragon Roost, War Factory (TH8-10 content) |

**Milestone:** Players can own multiple cities

### Phase 7: Polish & Launch (Weeks 24-26)

**Goal:** Launch-ready quality

| Week | Deliverables |
|------|--------------|
| 24 | Bug fixes, balance tuning |
| 25 | Performance optimization, testing |
| 26 | Soft launch, monitoring, final fixes |

**LAUNCH**

## 18.2 Post-Launch Roadmap

### Month 1-2: Stabilization

- Bug fixes based on player feedback
- Balance adjustments
- Server optimization
- First seasonal event

### Month 3-4: First Major Update

- Alliance Buildings
- Alliance Bosses
- New troop type
- Quality of life improvements

### Month 5-6: Second Major Update

- New map regions
- Seasonal Battle Pass refinement
- New defensive building
- Tournament system

### Month 7+: Ongoing

- Regular seasonal events
- New troops every 2-3 months
- New buildings every 3-4 months
- Feature expansions based on player demand

## 18.3 Success Criteria

### Launch Targets (Week 1)

| Metric | Target |
|--------|--------|
| Downloads | 100,000 |
| D1 Retention | 35% |
| Avg Session | 15 minutes |
| Crash Rate | <1% |

### Month 1 Targets

| Metric | Target |
|--------|--------|
| DAU | 20,000 |
| D7 Retention | 15% |
| Revenue | Positive |
| Rating | 4.0+ stars |

### Month 3 Targets

| Metric | Target |
|--------|--------|
| DAU | 50,000 |
| D30 Retention | 8% |
| Conversion Rate | 3% |
| ARPU | Positive ROI |

---

# Appendix A: Glossary

| Term | Definition |
|------|------------|
| **Army Camp** | Building that stores trained troops |
| **Battle Pass** | Seasonal progression system with rewards |
| **Builder** | Worker that constructs/upgrades buildings |
| **Conquest** | 80%+ destruction victory, enables occupation |
| **Domination** | 100% destruction victory |
| **Embassy** | Stores alliance reinforcement troops |
| **Gems** | Premium currency |
| **Housing** | Space a troop takes in Army Camp |
| **Occupation** | Temporary control of enemy city |
| **Outpost** | Small installation on enemy territory |
| **Raid** | 40-79% destruction victory, loot only |
| **Shield** | Protection from attacks |
| **Town Hall (TH)** | Main building, gates all progression |
| **Trophies** | PvP ranking points |

---

# Appendix B: Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-07 | Initial GDD creation |

---

**Document Status:** Complete Draft
**Last Updated:** 2026-02-07
**Author:** Development Team

---

*This document serves as the blueprint for Battle Tycoon: Conquest. All features and numbers are subject to balancing and testing during development.*
