# Battle Tycoon: Conquest
## Game Design Document v1.0

---

# Table of Contents

1. [Game Overview](#1-game-overview)
2. [Core Gameplay Loop](#2-core-gameplay-loop)
3. [World Architecture](#3-world-architecture)
4. [Building System](#4-building-system)
5. [Building Mini-Games](#5-building-mini-games) *(NEW - Immersive Resource Generation)*
6. [Troop System](#6-troop-system)
7. [Combat System](#7-combat-system)
8. [Economy System](#8-economy-system)
9. [Progression System](#9-progression-system)
10. [Alliance System](#10-alliance-system)
11. [Monetization](#11-monetization)
12. [Engagement Systems](#12-engagement-systems)
13. [UI/UX Design](#13-uiux-design)
14. [Onboarding & Tutorial](#14-onboarding--tutorial)
15. [Events & Live Operations](#15-events--live-operations)
16. [Technical Architecture](#16-technical-architecture)
17. [Audio Design](#17-audio-design)
18. [Metrics & Analytics](#18-metrics--analytics)
19. [Development Roadmap](#19-development-roadmap)

---

# 1. Game Overview

## 1.1 Concept Statement

**Battle Tycoon: Conquest** is a Roblox city-building conquest game with **immersive walkthrough gameplay**. Unlike traditional top-down strategy games, players control a third-person character who physically walks through their medieval city, entering buildings to perform hands-on mini-games that generate resources.

Players build and upgrade their cities, train armies, and conquer other players' cities to expand their empire. The unique **building mini-game system** lets players manually mine gold, chop wood, harvest crops, and train soldiers—then hire workers to automate these tasks as they progress. Players can own multiple cities, harvest resources, trade in a player-driven economy, and compete in alliance wars for global domination.

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

1. **Immersive Walkthrough Gameplay** - Walk through your city in third-person, enter buildings, and interact with everything
2. **Building Mini-Games** - Each building has unique mini-games to generate resources (mine gold, chop wood, forge weapons)
3. **Worker Progression Loop** - Start manual → hire workers → upgrade equipment → automate → expand
4. **Multi-City Empire Building** - Own up to 5 cities simultaneously
5. **Tiered Conquest System** - Choose to raid, occupy, or permanently conquer
6. **Real Economy** - Player-driven market for resources and troops
7. **Alliance Territory Wars** - Clans fight for control of the World Map
8. **Fantasy-Medieval Theme** - Knights, mages, dragons, AND tanks/mechs

## 1.5 Core Pillars

| Pillar | Description |
|--------|-------------|
| **Explore** | Walk through your medieval city in third-person, discovering buildings and interacting with the world |
| **Work** | Perform hands-on mini-games inside buildings to generate resources (mining, chopping, forging, training) |
| **Build** | Create and upgrade your city with 20+ building types, hire workers, upgrade equipment |
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
| 4 → 5 | All buildings at L4 + 10,000 gold + 8,000 wood | Mage Tower, Market, **2nd City Slot** |
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
| 5 | 3 | 6, 4, 4 | 4 of each | 125 |
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
| Builder 2 | 25,000 Gold | In-game shop purchase |
| Builder 3 | 75,000 Gold | In-game shop purchase |
| Builder 4 | 200,000 Gold | In-game shop purchase |
| Builder 5 | 500,000 Gold | In-game shop purchase |

> **Note:** All builders are purchasable with gold earned through gameplay. No premium currency required.

---

# 5. Building Mini-Games

The **Building Mini-Game System** is what makes Battle Tycoon unique. Instead of passively collecting resources from buildings, players physically walk into each building and perform interactive mini-games to generate resources. This creates an immersive, hands-on gameplay loop that evolves as players progress.

## 5.1 Mini-Game Philosophy

### 5.1.1 Core Design Principles

| Principle | Description |
|-----------|-------------|
| **Manual First** | Every building starts with manual labor—players do the work themselves |
| **Hire to Automate** | As buildings level up, players can hire workers to automate tasks |
| **Upgrade to Multiply** | Equipment upgrades increase output per action |
| **Prestige Loop** | High-level buildings unlock entirely new mini-games and mechanics |

### 5.1.2 Progression Loop

```
┌─────────────────────────────────────────────────────────────────┐
│                   BUILDING PROGRESSION LOOP                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  LEVEL 1-2: MANUAL LABOR                                        │
│  • Player performs all actions manually                         │
│  • Basic tools, slow output                                     │
│  • Learn the mini-game mechanics                                │
│                                                                 │
│  LEVEL 3-4: FIRST WORKER                                        │
│  • Hire 1 worker (costs resources)                              │
│  • Worker produces slowly while offline                         │
│  • Player can still do manual work for bonus                    │
│                                                                 │
│  LEVEL 5-6: EQUIPMENT UPGRADES                                  │
│  • Upgrade tools (pickaxe, axe, etc.) for faster work           │
│  • Upgrade processing equipment (refiner, sawmill, etc.)        │
│  • +50% output per equipment level                              │
│                                                                 │
│  LEVEL 7-8: WORKER EXPANSION                                    │
│  • Hire up to 3 workers                                         │
│  • Workers gain experience and efficiency                       │
│  • Unlock secondary resources                                   │
│                                                                 │
│  LEVEL 9-10: AUTOMATION & PRESTIGE                              │
│  • Full automation available                                    │
│  • Prestige option: Reset for permanent bonuses                 │
│  • Unlock rare resource generation                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 5.2 Gold Mine Mini-Game (Prototype)

The Gold Mine is the primary gold-generating building and serves as the prototype for all building mini-games.

### 5.2.1 Building Layout

```
┌─────────────────────────────────────────────────────────────────┐
│                      GOLD MINE INTERIOR                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│     ┌─────────────┐                                             │
│     │   ENTRANCE  │ ← Player enters here                        │
│     └──────┬──────┘                                             │
│            │                                                    │
│     ┌──────▼──────┐     ┌─────────────┐     ┌─────────────┐     │
│     │   MINE      │     │   REFINER   │     │   OUTPUT    │     │
│     │   SHAFT     │────▶│  STATION    │────▶│   CHEST     │     │
│     │ (Mine Ore)  │     │(Smelt Gold) │     │(Collect $)  │     │
│     └─────────────┘     └─────────────┘     └─────────────┘     │
│                                                                 │
│     ┌─────────────┐     ┌─────────────┐                         │
│     │   WORKER    │     │  EQUIPMENT  │                         │
│     │    HUT      │     │   BENCH     │                         │
│     │(Hire Miners)│     │(Upgrades)   │                         │
│     └─────────────┘     └─────────────┘                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2.2 Mini-Game Flow

**Step 1: Mine Ore**
- Player approaches ore vein
- ProximityPrompt: "Mine Gold Ore" (hold 1 second)
- Animation: Pickaxe swing, particles fly
- Result: +1 Gold Ore added to inventory (max 10)
- XP: +5 Mining XP

**Step 2: Carry to Refiner**
- Player walks to Refiner Station (carrying ore)
- ProximityPrompt: "Load Refiner" (instant)
- Result: Ore transferred to refiner queue

**Step 3: Smelt Gold**
- ProximityPrompt: "Smelt Gold" (hold 2 seconds)
- Animation: Furnace glows, molten gold pours
- Result: 1 Ore → 10 Gold (base rate)
- XP: +10 Refining XP

**Step 4: Collect Gold**
- ProximityPrompt: "Collect Gold" at Output Chest
- Gold added to player's resources
- Building XP gained based on gold collected

### 5.2.3 Unlimited Equipment Upgrade System

All Gold Mine equipment uses an unlimited level-based system with NO maximum level. Upgrade costs scale using the formula: `baseCost * (level ^ 1.8)`

**Equipment Levels and Benefits:**

| Equipment | Output Formula | Speed | Notes |
|-----------|---------------|-------|-------|
| Pickaxe | ore per swing = level | - | Linear scaling with level |
| Smelter | gold per ore = level | Milestone bonuses | Speed only improves at milestones |
| Miner (NPC) | capacity = 5 + (level * 5) | walkSpeed = 4 + level | Automated mining worker |
| Collector (NPC) | capacity = 2 + level | walkSpeed = 4 + level | Automated gold collector |

**Smelter Speed Milestones:**

| Level | Speed Bonus | Description |
|-------|-------------|-------------|
| 10 | +10% | First efficiency upgrade |
| 20 | +20% | Improved mechanisms |
| 50 | +35% | Industrial grade |
| 100 | +50% | Master smelter |
| 200 | +65% | Expert smelter |
| 500 | +80% | Legendary smelter |
| 1000 | +100% | Ultimate smelter |

### 5.2.4 NPC Worker System (Gold Mine)

Workers are NPC characters with status billboards displayed above their heads showing current action and progress.

**Miners:**
- Walk to ore vein and mine with visible progress display
- Walk to smelter when inventory full
- Deposit ore into smelter queue
- Repeat cycle automatically
- Max 3 Miners per Gold Mine
- Hire cost: 500 gold each

**Collectors:**
- Wait at smelter for processed gold
- Walk to output chest when gold is ready
- Deposit gold into chest for player collection
- Repeat cycle automatically
- Max 3 Collectors per Gold Mine
- Hire cost: 500 gold each

**Status Billboard Display:**
- Shows worker name and level
- Current action (Mining, Walking, Depositing, Waiting)
- Progress bar for current action
- Inventory count (ore/gold carried)

### 5.2.5 Independent Processing System

The Smelter operates independently from miners and runs continuously when ore is available.

**Smelter Mechanics:**
- Processes ore from queue one at a time
- Progress bar fills from 0% to 100% per ore processed
- Gold output = smelter level per ore
- Processing speed affected by milestone bonuses

**Smelter UI Display:**
- Current queue size (ore waiting)
- Smelter level
- Gold per ore output
- Progress bar for current ore
- Processing speed multiplier

### 5.2.6 Unified Upgrade Shop

All equipment upgrades are purchased from a single location with 4 upgrade pedestals.

**Upgrade Pedestals:**
| Pedestal | Equipment | Cost Formula |
|----------|-----------|--------------|
| 1 | Pickaxe | 100 * (level ^ 1.8) gold |
| 2 | Smelter | 150 * (level ^ 1.8) gold |
| 3 | Miner | 200 * (level ^ 1.8) gold |
| 4 | Collector | 200 * (level ^ 1.8) gold |

**Example Costs (Pickaxe):**
| Level | Cost |
|-------|------|
| 1 → 2 | 348 gold |
| 5 → 6 | 2,089 gold |
| 10 → 11 | 6,310 gold |
| 50 → 51 | 102,400 gold |
| 100 → 101 | 398,107 gold |

## 5.3 Lumber Mill Mini-Game

The Lumber Mill is the primary wood-generating building with a full progression loop similar to the Gold Mine.

### 5.3.1 Building Layout

```
┌─────────────────────────────────────────────────────────────────┐
│                     LUMBER MILL INTERIOR                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐                                                │
│  │ TREE GROVE  │ ← Choppable trees (4 trees, regrow)            │
│  │   🌲🌲🌲🌲   │                                                │
│  └──────┬──────┘                                                │
│         │                                                       │
│  ┌──────▼──────┐     ┌─────────────┐     ┌─────────────┐        │
│  │  LOG PILE   │────▶│   SAWMILL   │────▶│  OUTPUT     │        │
│  │ (Load Logs) │     │  (Process)  │     │  (Collect)  │        │
│  └─────────────┘     └─────────────┘     └─────────────┘        │
│                                                                 │
│  ┌─────────────┐     ┌─────────────┐                            │
│  │   WORKER    │     │    TOOL     │                            │
│  │   CABIN     │     │    SHED     │                            │
│  │(Hire Workers│     │ (Upgrades)  │                            │
│  └─────────────┘     └─────────────┘                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3.2 Mini-Game Flow

**Step 1: Chop Trees**
- Player approaches tree in tree grove
- ProximityPrompt: "Chop Tree" (hold 1.2 seconds)
- Trees require 3 hits to fell (health system)
- Animation: Axe swing, wood chips fly
- Result: +1-2 Logs per chop (based on axe), bonus logs on fell
- Carry capacity: Max 8 logs

**Step 2: Carry Logs**
- Player walks with logs to log pile
- Visual indicator shows logs being carried

**Step 3: Load Log Pile**
- ProximityPrompt: "Load Logs" (instant)
- Result: All carried logs transferred to processing queue

**Step 4: Process at Sawmill**
- ProximityPrompt: "Process Logs" (hold 2 seconds)
- Animation: Saw blade spins, sawdust flies, planks emerge
- Result: 1 Log → 8-16 Wood (based on sawmill level)

**Step 5: Collect Wood**
- ProximityPrompt: "Collect Wood" at Output Pile
- Wood added to player's resources
- Building XP gained

### 5.3.3 Unlimited Equipment Upgrade System

All Lumber Mill equipment uses an unlimited level-based system with NO maximum level. Upgrade costs scale using the formula: `baseCost * (level ^ 1.8)`

**Equipment Levels and Benefits:**

| Equipment | Output Formula | Speed | Notes |
|-----------|---------------|-------|-------|
| Axe | logs per chop = level | - | Linear scaling with level |
| Sawmill | planks per log = level | Milestone bonuses | Speed only improves at milestones |
| Logger (NPC) | capacity = 5 + (level * 5) | walkSpeed = 4 + level | Automated logging worker |
| Hauler (NPC) | capacity = 2 + level | walkSpeed = 4 + level | Automated plank hauler |

**Sawmill Speed Milestones:**

| Level | Speed Bonus | Description |
|-------|-------------|-------------|
| 10 | +10% | First efficiency upgrade |
| 20 | +20% | Improved mechanisms |
| 50 | +35% | Industrial grade |
| 100 | +50% | Master sawmill |
| 200 | +65% | Expert sawmill |
| 500 | +80% | Legendary sawmill |
| 1000 | +100% | Ultimate sawmill |

### 5.3.4 NPC Worker System (Lumber Mill)

Workers are NPC characters with status billboards displayed above their heads showing current action and progress.

**Loggers:**
- Walk to tree and chop with visible progress display
- Walk to sawmill when inventory full
- Deposit logs into sawmill queue
- Repeat cycle automatically
- Max 3 Loggers per Lumber Mill
- Hire cost: 500 gold each

**Haulers:**
- Wait at sawmill for processed planks
- Walk to output pile when planks are ready
- Deposit planks into pile for player collection
- Repeat cycle automatically
- Max 3 Haulers per Lumber Mill
- Hire cost: 500 gold each

**Status Billboard Display:**
- Shows worker name and level
- Current action (Chopping, Walking, Depositing, Waiting)
- Progress bar for current action
- Inventory count (logs/planks carried)

### 5.3.5 Independent Processing System

The Sawmill operates independently from loggers and runs continuously when logs are available.

**Sawmill Mechanics:**
- Processes logs from queue one at a time
- Progress bar fills from 0% to 100% per log processed
- Plank output = sawmill level per log
- Processing speed affected by milestone bonuses

**Sawmill UI Display:**
- Current queue size (logs waiting)
- Sawmill level
- Planks per log output
- Progress bar for current log
- Processing speed multiplier

### 5.3.6 Unified Upgrade Shop

All equipment upgrades are purchased from a single location with 4 upgrade pedestals.

**Upgrade Pedestals:**
| Pedestal | Equipment | Cost Formula |
|----------|-----------|--------------|
| 1 | Axe | 100 * (level ^ 1.8) gold |
| 2 | Sawmill | 150 * (level ^ 1.8) gold |
| 3 | Logger | 200 * (level ^ 1.8) gold |
| 4 | Hauler | 200 * (level ^ 1.8) gold |

**Example Costs (Axe):**
| Level | Cost |
|-------|------|
| 1 → 2 | 348 gold |
| 5 → 6 | 2,089 gold |
| 10 → 11 | 6,310 gold |
| 50 → 51 | 102,400 gold |
| 100 → 101 | 398,107 gold |

### 5.3.7 Unique Mechanics

- **Tree Regrowth:** Trees respawn after 15-30 seconds
- **Tree Health:** Trees require 3 hits to fell; bonus logs awarded on fell
- **Rare Trees:** Oak (common), Pine (uncommon), Ironwood (rare = 2x wood)

## 5.4 Farm Mini-Game

The Farm is the primary food-generating building with a full crop growth and processing loop.

### 5.4.1 Building Layout

```
┌─────────────────────────────────────────────────────────────────┐
│                        FARM LAYOUT                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────┐  ┌─────────────────────────────────┐             │
│  │SEED SHED  │  │      CROP FIELD (4x6 plots)     │  🌾🌾🌾     │
│  │(Get Seeds)│  │  [Plot][Plot][Plot][Plot][Plot] │  SCARECROW  │
│  └───────────┘  │  [Plot][Plot][Plot][Plot][Plot] │             │
│                 │  [Plot][Plot][Plot][Plot][Plot] │             │
│  ┌───────────┐  │  [Plot][Plot][Plot][Plot][Plot] │             │
│  │   WELL    │  └─────────────────────────────────┘             │
│  │(Water)    │                                                  │
│  └───────────┘                                                  │
│                                                                 │
│  ┌───────────┐     ┌───────────┐     ┌───────────┐              │
│  │ HARVEST   │────▶│ WINDMILL  │────▶│   SILO    │              │
│  │  BASKET   │     │ (Process) │     │ (Collect) │              │
│  └───────────┘     └───────────┘     └───────────┘              │
│                                                                 │
│  ┌───────────┐     ┌───────────┐                                │
│  │   BARN    │     │ TOOL SHED │                                │
│  │ (Workers) │     │ (Upgrades)│                                │
│  └───────────┘     └───────────┘                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.4.2 Mini-Game Flow

**Step 1: Get Seeds**
- Player approaches Seed Shed
- ProximityPrompt: "Get Seeds" (instant)
- Seeds added to inventory (unlimited for prototype)

**Step 2: Plant Seeds**
- Player approaches empty plot (4x6 grid = 24 plots)
- ProximityPrompt: "Plant Seeds" (hold 0.8 seconds)
- Crop appears at stage 1 (small, transparent)
- Crops unlock by level: Wheat (L1), Corn (L3), Carrots (L5), Pumpkins (L7)

**Step 3: Water Crops**
- Player draws water from Well
- ProximityPrompt: "Draw Water" (hold 1 second)
- Waters multiple plots based on watering can level
- Watered crops advance growth stage immediately
- Result: Crops grow faster (stage 1 → 2 → 3)

**Step 4: Harvest**
- When crops reach stage 3 (full size, opaque)
- ProximityPrompt changes to "Harvest" on the plot
- Result: 1-3 crops based on hoe level
- Carry capacity: Max 20 crops

**Step 5: Load Basket**
- Player walks to Harvest Basket
- ProximityPrompt: "Load Crops" (instant)
- All carried crops transferred to processing queue

**Step 6: Process at Windmill**
- ProximityPrompt: "Process Crops" (hold 2 seconds)
- Animation: Windmill grinds, grain particles
- Result: Crops → Food (5-15 per crop based on windmill level)

**Step 7: Collect Food**
- ProximityPrompt: "Collect Food" at Silo
- Food added to player's resources
- Building XP gained

### 5.4.3 Unlimited Equipment Upgrade System

All Farm equipment uses an unlimited level-based system with NO maximum level. Upgrade costs scale using the formula: `baseCost * (level ^ 1.8)`

**Equipment Levels and Benefits:**

| Equipment | Output Formula | Speed | Notes |
|-----------|---------------|-------|-------|
| Hoe | crops per harvest = level | - | Linear scaling with level |
| Watering Can | plots per water = level | - | Area coverage scales with level |
| Windmill | grain per crop = level | Milestone bonuses | Speed only improves at milestones |
| Farmer (NPC) | capacity = 5 + (level * 5) | walkSpeed = 4 + level | Automated farming worker |
| Carrier (NPC) | capacity = 2 + level | walkSpeed = 4 + level | Automated grain carrier |

**Windmill Speed Milestones:**

| Level | Speed Bonus | Description |
|-------|-------------|-------------|
| 10 | +10% | First efficiency upgrade |
| 20 | +20% | Improved mechanisms |
| 50 | +35% | Industrial grade |
| 100 | +50% | Master windmill |
| 200 | +65% | Expert windmill |
| 500 | +80% | Legendary windmill |
| 1000 | +100% | Ultimate windmill |

### 5.4.4 Crop Types

| Crop | Grow Time | Food Value | Unlock Level | Color |
|------|-----------|------------|--------------|-------|
| Wheat | 10 sec | 5 food | Level 1 | Golden yellow |
| Corn | 15 sec | 8 food | Level 3 | Bright yellow |
| Carrots | 8 sec | 4 food | Level 5 | Orange |
| Pumpkins | 20 sec | 12 food | Level 7 | Deep orange |
| Golden Wheat | 25 sec | 20 food | Level 10 | Shimmering gold |

### 5.4.5 NPC Worker System (Farm)

Workers are NPC characters with status billboards displayed above their heads showing current action and progress.

**Farmers:**
- Walk to crop field and harvest with visible progress display
- Walk to windmill when inventory full
- Deposit crops into windmill queue
- Repeat cycle automatically
- Max 3 Farmers per Farm
- Hire cost: 500 gold each

**Carriers:**
- Wait at windmill for processed grain
- Walk to silo when grain is ready
- Deposit grain into silo for player collection
- Repeat cycle automatically
- Max 3 Carriers per Farm
- Hire cost: 500 gold each

### 5.4.6 Multi-Farm System

Players can purchase up to 6 farms total, each with its own separate interior and independent production:

**Farm Expansion:**

| Farm | Cost | Requirements | Position |
|------|------|--------------|----------|
| Farm 1 | Free | Default | X=25, Z=100 |
| Farm 2 | 1,000 Gold + 500 Wood | Town Hall Lvl 2 | X=25, Z=130 |
| Farm 3 | 3,000 Gold + 1,500 Wood | Town Hall Lvl 3 | X=95, Z=130 |
| Farm 4 | 10,000 Gold + 5,000 Wood | Town Hall Lvl 4 | X=10, Z=115 |
| Farm 5 | 30,000 Gold + 15,000 Wood | Town Hall Lvl 5 | X=110, Z=115 |
| Farm 6 | 75,000 Gold + 35,000 Wood | Town Hall Lvl 6 | X=60, Z=140 |

**Farm Independence:**
- Each farm has a separate interior at a different Y level (700, 720, 740, etc.)
- Each farm has its own crop plots, windmill, and storage
- Each farm has its own equipment upgrades (hoe, watering can, windmill level)
- Each farm can hire its own farmers and carriers (3 each max)
- Workers from one farm cannot access another farm

**Exterior Stats Display:**
- Each farm displays a billboard showing production stats
- Shows: Food in storage, Crops in queue, Farm level
- Updates in real-time as production changes
- Visible from village without entering the farm

**Status Billboard Display:**
- Shows worker name and level
- Current action (Harvesting, Walking, Depositing, Waiting)
- Progress bar for current action
- Inventory count (crops/grain carried)

### 5.4.6 Independent Processing System

The Windmill operates independently from farmers and runs continuously when crops are available.

**Windmill Mechanics:**
- Processes crops from queue one at a time
- Progress bar fills from 0% to 100% per crop processed
- Grain output = windmill level per crop
- Processing speed affected by milestone bonuses

**Windmill UI Display:**
- Current queue size (crops waiting)
- Windmill level
- Grain per crop output
- Progress bar for current crop
- Processing speed multiplier

### 5.4.7 Unified Upgrade Shop

All equipment upgrades are purchased from a single location with 5 upgrade pedestals.

**Upgrade Pedestals:**
| Pedestal | Equipment | Cost Formula |
|----------|-----------|--------------|
| 1 | Hoe | 100 * (level ^ 1.8) gold |
| 2 | Watering Can | 80 * (level ^ 1.8) gold |
| 3 | Windmill | 150 * (level ^ 1.8) gold |
| 4 | Farmer | 200 * (level ^ 1.8) gold |
| 5 | Carrier | 200 * (level ^ 1.8) gold |

**Example Costs (Hoe):**
| Level | Cost |
|-------|------|
| 1 → 2 | 348 gold |
| 5 → 6 | 2,089 gold |
| 10 → 11 | 6,310 gold |
| 50 → 51 | 102,400 gold |
| 100 → 101 | 398,107 gold |

### 5.4.8 Unique Mechanics

- **Growth Stages:** Crops progress through 3 visual stages (sprout → growing → ready)
- **Watering Bonus:** Watered crops skip one growth stage instantly
- **Scarecrow:** Protects crops from random "crow attack" events (-10% yield)
- **Fertilizer:** Use sawdust from Lumber Mill for +25% yield

## 5.5 Barracks Mini-Game

The Barracks is the military training facility where players recruit peasants, train them into soldiers, equip them with weapons and armor, and deploy them to their army.

### 5.5.1 Building Layout

```
┌─────────────────────────────────────────────────────────────────┐
│                      BARRACKS LAYOUT                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────┐                    ┌───────────────┐         │
│  │  RECRUITMENT  │                    │    ARMORY     │         │
│  │    BOARD      │                    │ (Equip Gear)  │         │
│  │ (Get Trainees)│                    │ 🗡️ Weapons    │         │
│  │   📜 📜 📜    │                    │ 🛡️ Armor      │         │
│  └───────────────┘                    └───────────────┘         │
│        👤 👤                                                     │
│   (Waiting peasants)                                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────┐        │
│  │              TRAINING YARD (Dirt Ground)             │        │
│  │                                                      │        │
│  │   [DUMMY 1]      [DUMMY 2]      [DUMMY 3]           │        │
│  │      💪            💪             💪                │        │
│  │                                                      │        │
│  └─────────────────────────────────────────────────────┘        │
│                                                                 │
│  ┌───────────────┐     ┌───────────────┐     ┌───────────────┐  │
│  │ SERGEANT HUT  │     │  ARMY CAMP    │     │    FORGE      │  │
│  │(Hire Workers) │     │ (Deploy Army) │     │  (Upgrades)   │  │
│  │  Level 3+     │     │ ⛺ ⛺ 🔥       │     │  🔥 ⚒️        │  │
│  └───────────────┘     └───────────────┘     └───────────────┘  │
│                                                                 │
│              ═══════ MAIN BARRACKS BUILDING ═══════             │
│              │  🏰 Stone walls, battlements  │                  │
│              │       Military Banner 🚩      │                  │
│              ═══════════════════════════════                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.5.2 Mini-Game Flow

**Step 1: Recruit Trainee**
- Player approaches Recruitment Board
- ProximityPrompt: "Recruit Trainee (10 Food)" (hold 1.5 seconds)
- Costs 10 food per trainee
- Trainee added to player's inventory
- Visual: Peasants waiting by the board

**Step 2: Train at Dummy**
- Player takes trainee to Training Yard
- ProximityPrompt: "Train Recruit" (hold 2 seconds)
- Animation: Dummy wobbles, combat sparks fly
- Result: Trainee → Trained Recruit
- XP gained based on training dummy quality

**Step 3: Equip at Armory**
- Player takes trained recruit to Armory
- ProximityPrompt: "Equip Soldier" (hold 2 seconds)
- Animation: Metal clanking particles
- Result: Recruit equipped with current weapon + armor tier
- Soldier stats based on equipment quality

**Step 4: Deploy to Army**
- Player takes equipped soldier to Army Camp
- ProximityPrompt: "Deploy Soldier" (hold 1.5 seconds)
- Animation: Glory particles, trumpet visual
- Result: Soldier joins player's army roster
- +30 gold reward, +25 XP to barracks

### 5.5.3 Barracks Progression

| Level | Train Speed | Soldiers/Deploy | Deploy Reward | Workers | Unlocks |
|-------|-------------|-----------------|---------------|---------|---------|
| 1 | 1.0x | 1 soldier | 30 gold | 0 | Basic Training |
| 2 | 1.0x | 1 soldier | 35 gold | 0 | Basic Weapons |
| 3 | 1.2x | 1 soldier | 40 gold | 1 | Sergeant Hut |
| 4 | 1.4x | 1-2 soldiers | 50 gold | 1 | Iron Equipment |
| 5 | 1.6x | 1-2 soldiers | 60 gold | 2 | Steel Equipment |
| 6 | 1.8x | 2 soldiers | 75 gold | 2 | Advanced Dummies |
| 7 | 2.0x | 2 soldiers | 90 gold | 3 | Mithril Equipment |
| 8 | 2.3x | 2-3 soldiers | 110 gold | 3 | Specialization |
| 9 | 2.6x | 2-3 soldiers | 130 gold | 4 | Enchanted Dummies |
| 10 | 3.0x | 3 soldiers | 150 gold | 5 | Elite Troops |

### 5.5.4 Equipment Upgrades

**Training Dummies:**
| Dummy Type | Train Speed | XP Bonus | Cost | Unlock |
|------------|-------------|----------|------|--------|
| Basic Dummy | 1.0x | 1x | Free | Level 1 |
| Reinforced Dummy | 1.5x | 2x | 500 gold, 300 wood | Level 4 |
| Steel Dummy | 2.0x | 3x | 2,500 gold, 1,500 wood | Level 6 |
| Enchanted Dummy | 3.0x | 5x | 12,000 gold, 6,000 wood | Level 9 |

**Weapons:**
| Weapon Tier | Damage | Cost | Unlock |
|-------------|--------|------|--------|
| Basic Sword | 10 | Free | Level 1 |
| Iron Sword | 18 | 800 gold, 400 wood | Level 4 |
| Steel Sword | 28 | 4,000 gold, 2,000 wood | Level 5 |
| Mithril Sword | 45 | 20,000 gold, 10,000 wood | Level 7 |

**Armor:**
| Armor Tier | Defense | Cost | Unlock |
|------------|---------|------|--------|
| Basic Leather | 5 | Free | Level 1 |
| Iron Plate | 12 | 600 gold, 300 wood | Level 4 |
| Steel Plate | 22 | 3,000 gold, 1,500 wood | Level 5 |
| Mithril Plate | 40 | 15,000 gold, 7,500 wood | Level 7 |

### 5.5.5 Worker System (Drill Sergeants)

| Sergeant Level | Train Speed | Capacity | Auto-Equip | Hire Cost |
|----------------|-------------|----------|------------|-----------|
| Recruit Sergeant | 50% of player | 1 at a time | No | 300 gold, 150 food |
| Veteran Sergeant | 75% of player | 2 at a time | Basic only | 800 gold, 400 food |
| Elite Sergeant | 100% of player | 3 at a time | Iron tier | 2,000 gold, 1,000 food |
| Master Sergeant | 120% of player | 4 at a time | Steel tier | 5,000 gold, 2,500 food |

### 5.5.6 Unique Mechanics

- **Food Cost:** Each recruit costs food (peasants need to eat!)
- **Equipment Inheritance:** Soldiers retain equipment quality; higher = stronger troops
- **Batch Training:** Multiple dummies allow training multiple recruits simultaneously
- **Drill Sergeants:** Auto-train recruits while offline (Level 3+)
- **Army Roster:** Deployed soldiers visible in Army Camp tents
- **Specialization (Level 8+):** Train specialized troops:
  - **Knight:** +50% defense, slower training
  - **Berserker:** +50% damage, -25% defense
  - **Ranger:** Ranged attacks, lower HP
- **Forge Upgrades:** Permanently improve all future soldiers
- **Combat XP:** Soldiers gain XP in battles, improving stats
- **Morale System:** Well-fed army fights better (+10% damage if food surplus)

## 5.6 Town Hall Mini-Game

The Town Hall is the central administrative building where players manage their growing settlement through taxation, population registration, research, and treasury management.

### 5.6.1 Building Layout

```
┌─────────────────────────────────────────────────────────────────┐
│                      TOWN HALL LAYOUT                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────┐                    ┌───────────────┐         │
│  │  TAX OFFICE   │                    │   RESEARCH    │         │
│  │(Collect Taxes)│                    │   LIBRARY     │         │
│  │  💰 Citizens  │                    │  📚 Scrolls   │         │
│  └───────────────┘                    └───────────────┘         │
│                                                                 │
│  ┌───────────────┐     ═══════════     ┌───────────────┐        │
│  │ CENSUS DESK   │     ║ MAIN   ║     │   TREASURY    │        │
│  │(Register Pop) │     ║ HALL   ║     │    VAULT      │        │
│  │  📜 Quill     │     ║ 🏛️    ║     │  🔒 Gold      │        │
│  └───────────────┘     ═══════════     └───────────────┘        │
│                           🚩 🚩                                  │
│                        Red Carpet                                │
│                                                                 │
│  ┌───────────────┐                    ┌───────────────┐         │
│  │   ADVISOR     │                    │    ROYAL      │         │
│  │  QUARTERS     │                    │   ARCHIVES    │         │
│  │(Hire Workers) │                    │  (Upgrades)   │         │
│  │  Level 3+     │                    │   🔮 Runes    │         │
│  └───────────────┘                    └───────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.6.2 Mini-Game Flow

**Step 1: Collect Taxes**
- Player approaches Tax Office
- ProximityPrompt: "Collect Taxes" (hold 2 seconds)
- Gold earned = Population × 2 × Tax Rate multiplier
- Animation: Gold coin sparkle effect
- Taxes stored in player's inventory for later deposit

**Step 2: Register Citizens**
- Player approaches Census Desk
- ProximityPrompt: "Register Citizen" (hold 1.5 seconds)
- Animation: Ink writing particles from quill
- Every 5 registrations → +1 population
- Higher population = more tax income

**Step 3: Study Scrolls**
- Player approaches Research Library
- ProximityPrompt: "Study Scrolls" (hold 2.5 seconds)
- Animation: Magical blue particles rise from scroll
- Earn research points based on scroll tier
- Research points unlock building upgrades

**Step 4: Deposit Gold**
- Player approaches Treasury Vault with collected taxes
- ProximityPrompt: "Deposit Gold" (hold 1.5 seconds)
- Animation: Gold particles flow into vault
- Gold added to player's total resources
- Building XP gained

### 5.6.3 Town Hall Progression

| Level | Tax Rate | Research/Study | Population Bonus | Workers | Unlocks |
|-------|----------|----------------|------------------|---------|---------|
| 1 | 1.0x | 1 point | +0 | 0 | Basic Administration |
| 2 | 1.1x | 1 point | +2 | 0 | Copper Ledgers |
| 3 | 1.2x | 2 points | +4 | 1 | Advisor Quarters |
| 4 | 1.3x | 2 points | +6 | 1 | Ancient Scrolls |
| 5 | 1.4x | 2 points | +8 | 2 | Reinforced Vault |
| 6 | 1.5x | 3 points | +10 | 2 | Silver Ledgers |
| 7 | 1.6x | 3 points | +12 | 3 | Enchanted Scrolls |
| 8 | 1.8x | 4 points | +15 | 3 | Iron Vault |
| 9 | 1.9x | 4 points | +18 | 4 | Gold Ledgers |
| 10 | 2.0x | 5 points | +20 | 5 | Royal Vault, Legendary Scrolls |

### 5.6.4 Equipment Upgrades

**Ledgers (Tax Collection):**
| Ledger Tier | Tax Rate | Efficiency | Cost | Unlock |
|-------------|----------|------------|------|--------|
| Basic Ledger | 1.0x | 1x | Free | Level 1 |
| Copper Ledger | 1.3x | 2x | 800 gold, 400 wood | Level 2 |
| Silver Ledger | 1.6x | 3x | 4,000 gold, 2,000 wood | Level 6 |
| Gold Ledger | 2.0x | 5x | 20,000 gold, 10,000 wood | Level 9 |

**Scrolls (Research):**
| Scroll Tier | Research Speed | Points/Study | Cost | Unlock |
|-------------|----------------|--------------|------|--------|
| Basic Scrolls | 1.0x | 1 | Free | Level 1 |
| Ancient Scrolls | 1.5x | 2 | 1,000 gold, 500 wood | Level 4 |
| Enchanted Scrolls | 2.0x | 3 | 5,000 gold, 2,500 wood | Level 7 |
| Legendary Scrolls | 3.0x | 5 | 25,000 gold, 12,500 wood | Level 10 |

**Treasury Vault:**
| Vault Tier | Capacity | Security | Cost | Unlock |
|------------|----------|----------|------|--------|
| Basic Vault | 1,000 gold | 1.0x | Free | Level 1 |
| Reinforced Vault | 5,000 gold | 1.5x | 1,500 gold, 750 wood | Level 5 |
| Iron Vault | 20,000 gold | 2.0x | 7,500 gold, 3,750 wood | Level 8 |
| Royal Vault | 100,000 gold | 3.0x | 40,000 gold, 20,000 wood | Level 10 |

### 5.6.5 Worker System (Advisors)

| Advisor Level | Specialty | Efficiency | Auto-Task | Hire Cost |
|---------------|-----------|------------|-----------|-----------|
| Apprentice Advisor | Tax | 50% of player | Tax collection only | 500 gold, 200 food |
| Senior Advisor | Census | 75% of player | Tax + Census | 1,500 gold, 600 food |
| Royal Advisor | Research | 100% of player | Tax + Census + Research | 4,000 gold, 1,500 food |
| Grand Vizier | Treasury | 120% of player | All tasks | 10,000 gold, 4,000 food |

### 5.6.6 Unique Mechanics

- **Population Growth:** Registering citizens increases town population, which increases tax income
- **Tax Accumulation:** Taxes must be deposited to vault to claim gold (prevents auto-farming)
- **Research Points:** Accumulate to unlock global building upgrades (affects ALL buildings)
- **Advisor Specialties:** Each advisor specializes in one task but can assist with others
- **Security Multiplier:** Higher vault security reduces gold loss from enemy raids
- **Diplomacy (Level 8+):** Unlock alliance bonuses and trade agreements
- **Royal Decrees:** Spend research points on temporary buffs:
  - **Tax Holiday:** +50% gold for 10 minutes
  - **Census Drive:** +2 population per registration for 10 minutes
  - **Scholar's Focus:** +100% research points for 10 minutes
- **Town Festivals:** At Level 10, host festivals that boost all production by 25%

## 5.7 Building XP and Leveling

### 5.6.1 XP Sources

| Action | XP Gained | Notes |
|--------|-----------|-------|
| Manual work (per action) | 5-15 XP | Based on action difficulty |
| Worker production (per unit) | 1 XP | Passive accumulation |
| Equipment upgrade | 50-500 XP | One-time bonus |
| Prestige reset | 1,000+ XP | Milestone bonus |

### 5.6.2 Level Requirements

| Level | Total XP Required | New Unlocks |
|-------|-------------------|-------------|
| 1 | 0 | Basic tools, manual work |
| 2 | 100 | Faster action speed |
| 3 | 300 | First worker slot |
| 4 | 600 | Tool upgrade tier 2 |
| 5 | 1,000 | Processing upgrade tier 2 |
| 6 | 1,500 | Second worker slot |
| 7 | 2,200 | Tool upgrade tier 3 |
| 8 | 3,000 | Processing upgrade tier 3 |
| 9 | 4,000 | Third worker slot, rare resources |
| 10 | 5,500 | Master equipment, prestige option |

### 5.6.3 Prestige System (Level 10+)

At max level, players can **prestige** a building:
- Building resets to Level 1
- Lose all workers (must rehire)
- Keep equipment unlocks
- Gain **Prestige Star** (+10% permanent output bonus)
- Max 5 Prestige Stars per building (+50% total)

## 5.8 Mini-Game UI Elements

### 5.7.1 Building Interior HUD

```
┌─────────────────────────────────────────────────────────────────┐
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  GOLD MINE (Level 4)          ⭐⭐ (2 Prestige)           │   │
│  │  XP: 580/600 [████████░░] 97%                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐                 │
│  │ ORE: 5/10  │  │ REFINER    │  │ OUTPUT     │                 │
│  │ [█████░░░░]│  │ Queue: 3   │  │ 250 Gold   │                 │
│  └────────────┘  └────────────┘  └────────────┘                 │
│                                                                 │
│  WORKERS: [👷 Working] [👷 Carrying] [💤 Idle]                  │
│                                                                 │
│  [EXIT BUILDING]                              [UPGRADE MENU]    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.7.2 Interaction Prompts

- **ProximityPrompt Style:** Medieval wooden sign aesthetic
- **Progress Bar:** Shows during hold actions
- **Reward Popup:** "+10 Gold" floats above collection point
- **Level Up Celebration:** Fanfare, confetti, stats comparison

---

# 6. Troop System

## 6.1 Troop Categories

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

## 6.2 Troop Training

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

## 6.3 Troop Upgrades

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

# 7. Combat System

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
│    - You pay 500,000 gold                                      │
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

| Duration | Gold Cost | Notes |
|----------|-----------|-------|
| 1 day | 10,000 gold | Basic protection |
| 2 days | 18,000 gold | Extended protection |
| 7 days | 50,000 gold | Maximum protection |

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

# 8. Economy System

## 7.1 Resource Types

### 7.1.1 Primary Resources

| Resource | Source | Used For | Storage |
|----------|--------|----------|---------|
| **Gold** | Gold Mine, raids, trading, quests, daily rewards | Troops, upgrades, builders, shields | Treasury |
| **Wood** | Lumber Mill, raids, trading | Buildings, walls | Warehouse |
| **Food** | Farm, raids | Troop upkeep, training | Warehouse |

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
│  • Pay 5% listing fee (in gold)                                │
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

# 9. Progression System

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
| 5 | 1,000 Gold, Title: "Settler" |
| 10 | 2,500 Gold, Profile Frame |
| 15 | 5,000 Gold, Title: "Builder" |
| 20 | 10,000 Gold, Exclusive Decoration |
| 25 | 25,000 Gold, Title: "Commander" |
| 30 | 50,000 Gold, Title: "Conqueror" |
| 40 | 100,000 Gold, Title: "Emperor" |
| 50 | 250,000 Gold, Title: "Legend", Golden Castle Skin |

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
| First Blood | Win 1 battle | 500 Gold |
| Warrior | Win 50 battles | 5,000 Gold |
| Conqueror | Win 500 battles | 25,000 Gold |
| Warlord | Win 5,000 battles | 100,000 Gold |
| Perfect Strike | Win with 100% destruction | 2,500 Gold |
| Untouchable | Win without losing any troops | 10,000 Gold |

**Building Achievements:**
| Achievement | Requirement | Reward |
|-------------|-------------|--------|
| Architect | Build 10 buildings | 2,000 Gold |
| City Planner | Build 50 buildings | 10,000 Gold |
| Urban Legend | Max all buildings | 250,000 Gold |

**Social Achievements:**
| Achievement | Requirement | Reward |
|-------------|-------------|--------|
| Team Player | Join an alliance | 2,500 Gold |
| Generous | Donate 100 troops | 5,000 Gold |
| War Hero | Win 10 alliance wars | 50,000 Gold |

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

# 10. Alliance System

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
│  • Winning Alliance: War Chest (gold, resources)               │
│  • Individual: Based on stars earned                           │
│  • Participation: Bonus for using both attacks                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**War Rewards:**

| Performance | Winner | Loser |
|-------------|--------|-------|
| Alliance | 50,000 gold (split) + resources | 10,000 gold (split) |
| Per star earned | 1,000 gold | 500 gold |
| Both attacks used | +5,000 gold | +2,500 gold |

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

# 11. Monetization

## 10.1 Monetization Philosophy

**Core Principle: Pay for TIME, not POWER**

- Everything purchasable can also be earned through gameplay (gold only)
- Paying players get cosmetics and convenience items
- No exclusive troops or stat advantages
- Single currency economy (Gold) - no premium gems currency

## 10.2 In-Game Economy (Gold Only)

### 10.2.1 Gold Sources

| Source | Amount | Notes |
|--------|--------|-------|
| Gold Mine (manual) | 10-50/collection | Based on equipment level |
| Gold Mine (workers) | Passive income | Based on worker count |
| Daily Rewards | 500-5,000 gold | 7-day cycle |
| Quests | 1,000-5,000 gold | Daily quests |
| Achievements | 5,000-50,000 gold | One-time rewards |
| Battle loot | Variable | Based on opponent |
| Streak Milestones | 2,500-250,000 gold | 1 week to 1 year streaks |

### 10.2.2 Gold Uses (In-Game Shop)

| Use | Gold Cost | Additional Cost | Notes |
|-----|-----------|-----------------|-------|
| **Builders** |
| 2nd Builder | 25,000 | - | Permanent |
| 3rd Builder | 75,000 | - | Permanent |
| 4th Builder | 200,000 | - | Permanent |
| 5th Builder | 500,000 | - | Permanent |
| **Farm Plots** |
| 2nd Farm Plot | 1,000 | 500 Wood | Unlocks Farm 2 |
| 3rd Farm Plot | 3,000 | 1,500 Wood | Unlocks Farm 3 |
| 4th Farm Plot | 10,000 | 5,000 Wood | Unlocks Farm 4 |
| 5th Farm Plot | 30,000 | 15,000 Wood | Unlocks Farm 5 |
| 6th Farm Plot | 75,000 | 35,000 Wood | Unlocks Farm 6 |
| **Shields** |
| 1-Day Shield | 10,000 | - | Protection from attacks |
| 2-Day Shield | 18,000 | - | Protection from attacks |
| 7-Day Shield | 50,000 | - | Protection from attacks |
| **Resources** |
| Wood Pack (5K) | 7,500 | - | Resource conversion |
| Wood Crate (20K) | 25,000 | - | Resource conversion |
| Wood Warehouse (50K) | 55,000 | - | Resource conversion |
| Food Pack (2K) | 5,000 | - | Resource conversion |
| Food Crate (10K) | 20,000 | - | Resource conversion |
| Food Warehouse (25K) | 45,000 | - | Resource conversion |
| **Other** |
| Speed up (per minute) | 100 | - | Skip build time |

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
| 5 | 1,000 Gold | 5,000 Gold + 1hr Speedup |
| 10 | 1,000 Wood | 5,000 Wood + Building Decoration |
| 15 | Common Troop Skin | Rare Troop Skin + Emote |
| 20 | 2,000 Gold | 10,000 Gold + Resource Boost |
| 25 | 2,000 Food | 10,000 Food + Title |
| 30 | Training Speedup | Training Speedup + Castle Skin |
| 35 | 3,000 Gold | 15,000 Gold + Profile Frame |
| 40 | 5,000 Gold | 25,000 Gold + Exclusive Banner |
| 45 | 5,000 Gold | 25,000 Gold + War Paint (troops) |
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
| 5,000 Gold daily | 150,000 gold/month |
| 2nd Builder permanent | Included while subscribed |
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
| VIP Silver | 3-5 | +10% more gold daily |
| VIP Gold | 6-11 | +20% more gold + exclusive skin |
| VIP Platinum | 12+ | +30% more gold + exclusive troop |

## 10.5 Starter Packs

One-time purchases with exceptional value (cosmetics and resources):

| Pack | Robux | Contents | Unlock Condition |
|------|-------|----------|------------------|
| Beginner's Pack | 99 | 25,000 gold, 10,000 each resource, 1 Rare Troop Skin | TH1-2 |
| Builder's Pack | 249 | 50,000 gold, 3x 1hr speedups, Exclusive Banner | TH3+ |
| Commander's Pack | 499 | Rare Commander Skin, 100,000 gold, 50,000 resources | TH5+ |
| Conqueror's Pack | 999 | Epic Commander Skin, 250,000 gold, 5x speedups | TH7+ |
| Legend Pack | 1,999 | Legendary Commander Skin, 500,000 gold, Exclusive Skin Set | TH9+ |

## 10.6 Special Offers

### 10.6.1 Triggered Offers

| Trigger | Offer |
|---------|-------|
| First defeat | "Revenge Pack" - Troops + Shield |
| TH upgrade complete | Growth bundle for new TH level |
| Return after 7+ days | "Welcome Back" - Resources + Gold Bonus |
| Low resources | "Resource Rescue" - Discounted pack |

### 10.6.2 Limited Time Offers

- Flash Sales (24 hours)
- Weekend Warrior (Friday-Sunday)
- Holiday Events (Seasonal)

## 10.7 Cosmetics Shop

All cosmetics are visual only with zero gameplay impact (purchased with Robux):

| Category | Examples | Robux Price |
|----------|----------|-------------|
| Troop Skins | Golden Knight, Fire Archer | 50-150 Robux |
| Building Skins | Crystal Farm, Dark Castle | 75-200 Robux |
| Castle Themes | Winter, Volcanic, Enchanted | 150-400 Robux |
| Emotes | Victory dance, Taunt, Wave | 25-75 Robux |
| Profile Frames | League frames, Event frames | Achievement/Purchase |
| Banners | Alliance banners, Player flags | 50-150 Robux |

---

# 12. Engagement Systems

## 11.1 Daily Login Rewards

### 11.1.1 Weekly Cycle

| Day | Reward |
|-----|--------|
| 1 | 500 Gold |
| 2 | 750 Gold |
| 3 | 1,000 Gold |
| 4 | 1,500 Gold |
| 5 | 2,000 Gold + 500 Wood |
| 6 | 2,500 Gold + 500 Food |
| 7 | **5,000 Gold + 1,000 Wood + 500 Food** |

**Streak Bonus:** Complete all 7 days → 5,000 bonus gold

### 11.1.2 Monthly Calendar

Streak milestones with bonus gold:
- 1 Week Streak: 2,500 Gold
- 2 Week Streak: 5,000 Gold
- 1 Month Streak: 10,000 Gold
- 3 Month Streak: 50,000 Gold
- 6 Month Streak: 100,000 Gold
- 1 Year Streak: 250,000 Gold

## 11.2 Daily Missions

### 11.2.1 Mission Pool

| Mission | Requirement | Reward |
|---------|-------------|--------|
| Train troops | Train 50 housing worth | 15 tokens, 500 gold |
| Win battles | Win 3 battles | 20 tokens, 750 gold |
| Collect resources | Collect 10,000 total | 10 tokens, 500 gold |
| Upgrade building | Complete 1 upgrade | 15 tokens, 1,000 gold |
| Donate troops | Donate 10 housing | 10 tokens, 500 gold |
| Use spells | Use 5 spells in battle | 15 tokens, 1,000 gold |

### 11.2.2 Daily Mission Slots

- 3 missions available per day
- Refresh at midnight (player's local time)
- Complete all 3 → Bonus mission chest

## 11.3 Weekly Challenges

| Challenge | Requirement | Reward |
|-----------|-------------|--------|
| War Veteran | Win 10 attacks | 50 tokens, 10,000 gold |
| Architect | Complete 5 upgrades | 40 tokens, 5,000 gold |
| Generous | Donate 100 troop housing | 30 tokens, 7,500 gold |
| Collector | Collect 100,000 resources | 25 tokens, 5,000 gold |

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
| 3-6 days | 24hr Shield + 5,000 gold |
| 7-13 days | 48hr Shield + 10,000 gold + Resources |
| 14-29 days | 72hr Shield + 25,000 gold + Resource Boost |
| 30+ days | 7-day Shield + 50,000 gold + Care Package |

### 11.6.2 Catch-Up Mechanics

- Reduced upgrade times for first 48 hours back
- Double resources from first 10 battles
- Free Battle Pass tier skip (if active season)

---

# 13. UI/UX Design

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

# 14. Onboarding & Tutorial

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
│  • 5,000 Gold                                                   │
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

# 15. Events & Live Operations

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
│  ├── 25,000: Gold Pack (25,000)                                │
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

# 16. Technical Architecture

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

# 17. Audio Design

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

# 18. Metrics & Analytics

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

# 19. Development Roadmap

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
| 17 | Gold economy, shop, speed-ups |
| 18 | Battle Pass system |
| 19 | VIP subscription, cosmetics shop |

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
| **Gold** | Primary currency for all in-game purchases |
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
