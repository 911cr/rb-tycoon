# Domain Glossary

**Location**: `.claude/docs/domain-glossary.md`

Comprehensive terminology reference for Battle Tycoon: Conquest - a Roblox city-building conquest game.

**See Also**:
- `.claude/rules/routing-rules.md` - File pattern to agent mapping
- `docs/GAME_DESIGN_DOCUMENT.md` - Complete game design specification
- `CLAUDE.md` - Project overview and conventions

---

## Table of Contents

1. [Core Game Concepts](#core-game-concepts)
2. [Buildings & Structures](#buildings--structures)
3. [Military Units](#military-units)
4. [Combat System](#combat-system)
5. [Economy & Resources](#economy--resources)
6. [Progression System](#progression-system)
7. [Social Systems](#social-systems)
8. [Monetization](#monetization)
9. [Technical Architecture](#technical-architecture)
10. [Roblox Services](#roblox-services)

---

## Core Game Concepts

### City
**What**: Player's home base containing buildings
**Components**: Town Hall, resource buildings, defensive structures, army buildings
**Protection**: Shield system after attacks
**Ownership**: Players can own multiple cities through conquest

### World Map
**What**: Multiplayer overworld showing all player cities
**Features**: City discovery, target selection, alliance territories
**Implementation**: Separate Roblox place with TeleportService

### Battle Arena
**What**: Combat instance where attacks take place
**Type**: Simulated combat (not real-time PvP)
**Duration**: 3 minutes maximum
**Result**: Victory tiers based on destruction percentage

### Conquest
**What**: Taking over another player's city
**Requirement**: 100% destruction of enemy city
**Result**: Attacker gains control of city and its production

---

## Buildings & Structures

### Town Hall (TH)
**What**: Central progression building
**Levels**: 1-10
**Purpose**: Gates all other building upgrades
**Requirement**: Must be upgraded to unlock higher-level buildings

### Resource Buildings

| Building | Resource | Base Rate | Max Level |
|----------|----------|-----------|-----------|
| Gold Mine | Gold | 200/hr | 12 |
| Lumber Mill | Wood | 150/hr | 12 |
| Farm | Food | 100/hr | 12 |
| Storage | Capacity | N/A | 10 |

### Military Buildings

| Building | Function | Unlocks At |
|----------|----------|------------|
| Barracks | Infantry training | TH1 |
| Archery Range | Archer training | TH2 |
| Machine Shop | Vehicle training | TH4 |
| Tank Factory | Tank training | TH6 |
| Air Base | Aircraft training | TH8 |
| Spell Factory | Spell crafting | TH3 |

### Defensive Buildings

| Building | Type | Range | Unlocks At |
|----------|------|-------|------------|
| Cannon | Ground single | Medium | TH1 |
| Archer Tower | Ground/Air single | Long | TH2 |
| Mortar | Ground splash | Short | TH3 |
| Air Defense | Air only | Long | TH4 |
| Wizard Tower | Ground/Air splash | Medium | TH5 |
| Inferno Tower | Multi/Single target | Long | TH7 |

### Walls
**What**: Defensive barriers around buildings
**Levels**: 1-10 (upgrades with TH)
**Purpose**: Slow troop movement, funnel attackers

---

## Military Units

### Troop Types

| Type | Housing | Speed | Target | Training Time |
|------|---------|-------|--------|---------------|
| Barbarian | 1 | Fast | Ground | 20s |
| Archer | 1 | Medium | Ground/Air | 25s |
| Giant | 5 | Slow | Defenses | 120s |
| Wizard | 4 | Medium | Ground/Air | 90s |
| Dragon | 20 | Medium | Ground/Air | 300s |
| P.E.K.K.A | 25 | Slow | Ground | 360s |

### Troop Attributes
- **DPS**: Damage per second
- **HP**: Hit points (health)
- **Housing**: Space required in army camps
- **Preferred Target**: What the troop prioritizes attacking
- **Movement Speed**: How fast the troop moves

### Army Camps
**What**: Buildings that determine army size
**Housing**: 20 per camp (upgradeable)
**Max Camps**: Scales with TH level
**Note**: Troops are consumed in battle

---

## Combat System

### Battle Phases

1. **Scout**: 30-second preview of enemy base
2. **Deploy**: Place troops and spells (3 min limit)
3. **Simulate**: Combat resolves automatically
4. **Result**: Victory tier calculated

### Victory Tiers

| Tier | Destruction | Stars | Loot |
|------|-------------|-------|------|
| Defeat | 0-39% | 0 | 10% |
| Minor Victory | 40-59% | 1 | 40% |
| Major Victory | 60-79% | 2 | 60% |
| Total Victory | 80-99% | 2 | 80% |
| Conquest | 100% | 3 | 100% + City |

### Star System
- **1 Star**: 40% destruction OR Town Hall destroyed
- **2 Stars**: 40% destruction AND Town Hall destroyed
- **3 Stars**: 100% destruction

### Shield System
**What**: Protection from attacks after being attacked
**Duration**: Based on stars lost (8h/12h/16h)
**Purpose**: Prevents continuous targeting
**Break**: Shield breaks if you attack

### Revenge System
**What**: Free attack against someone who attacked you
**Duration**: Available for 24 hours
**Cost**: No shield break penalty
**Limit**: One revenge per attack received

---

## Economy & Resources

### Primary Resources

| Resource | Icon | Primary Source | Use |
|----------|------|----------------|-----|
| Gold | Coin | Gold Mines, Battles | Buildings, Upgrades |
| Wood | Log | Lumber Mills, Battles | Buildings, Walls |
| Food | Wheat | Farms | Troop Training |
| Gems | Diamond | Premium currency | Speed-ups, Premium items |

### Resource Flow
```
Production → Storage → Spending
   ↑                      ↓
Battles ←────────── Raiding
```

### Loot Calculation
**Available Loot**: 20% of enemy's stored resources
**Town Hall Bonus**: +10% if TH destroyed
**Storage Distribution**: Loot split across storages

### Economy Sinks (What removes resources)
- Building construction
- Building upgrades
- Wall upgrades
- Troop training
- Spell crafting
- Research

### Economy Faucets (What adds resources)
- Resource building production
- Battle loot
- Daily rewards
- Achievement rewards
- Event rewards
- Gem purchases

---

## Progression System

### Town Hall Gating
**Principle**: TH level determines max level of all other buildings
**Example**: TH5 → Max building level 5, max wall level 5

### Upgrade Times
**Pattern**: Exponential growth with TH level
**Speed-up**: Gems can instantly complete upgrades
**Builder**: Each builder can handle one upgrade

### Builder System
**Default**: 1 builder
**Max**: 5 builders
**Source**: 2nd builder from VIP, others from gems

### Trophies
**What**: PvP ranking points
**Gain**: Win battles
**Lose**: Lose defenses
**Leagues**: Trophy ranges for matchmaking

### Experience (XP)
**Source**: Completing upgrades, winning battles
**Purpose**: Player level, unlocks cosmetics
**Display**: Level badge on profile

---

## Social Systems

### Alliance (Clan)
**What**: Player group for cooperative play
**Size**: Up to 50 members
**Features**: Donations, wars, chat, territory

### Alliance War
**What**: 2-day alliance vs alliance competition
**Phases**: Preparation (1 day), Battle (1 day)
**Attacks**: Each member gets 2 attacks
**Victory**: Alliance with most stars wins

### Donations
**What**: Giving troops to alliance members
**Benefit**: Donated troops defend during attacks
**Limit**: Based on alliance rank
**Reward**: XP and alliance points

### Alliance Territory
**What**: Contested zones on world map
**Control**: Alliance that holds territory gets bonuses
**Warfare**: Alliances fight for control

---

## Monetization

### Premium Currency (Gems)
**Source**: Real money (Robux)
**Uses**: Speed-ups, builders, cosmetics, resource packs

### Gem Packages

| Package | Gems | Robux |
|---------|------|-------|
| Handful | 80 | 99 |
| Pouch | 500 | 449 |
| Bag | 1,200 | 899 |
| Chest | 6,500 | 3,399 |

### Battle Pass
**Duration**: 28 days per season
**Tiers**: 50 levels
**Tracks**: Free and Premium
**Cost**: 450 Robux for premium

### VIP Subscription
**Cost**: 450 Robux/month
**Benefits**:
- 50 gems daily
- 2nd builder permanent
- +20% resource production
- -20% upgrade times

### Starter Packs (One-time)
**Trigger**: Progression milestones
**Value**: 3-5x gem equivalent
**Purpose**: Convert free players

---

## Technical Architecture

### Multi-Place Architecture
**Pattern**: TeleportService between game places
**Places**: Menu, City, World Map, Battle, Alliance, Market

### DataStoreService
**What**: Roblox persistent data storage
**Pattern**: ProfileService wrapper recommended
**Key**: Player UserId
**Limits**: 4MB per key, 60 requests/minute

### Server Authority
**Principle**: "Never Trust the Client"
**Pattern**: All game logic server-side
**Client Role**: UI, input, visual feedback only
**Validation**: Server validates all requests

### RemoteEvent
**What**: Client-to-server communication
**Pattern**: Request → Validate → Execute → Response
**Security**: Rate limiting, type checking, permission checking

### ReplicatedStorage
**What**: Shared code between client and server
**Contents**: Types, constants, shared modules
**Note**: All code here is visible to exploiters

### ServerScriptService
**What**: Server-only code
**Contents**: Services, game logic, data management
**Security**: Code here cannot be read by clients

---

## Roblox Services

### Key Services Used

| Service | Purpose |
|---------|---------|
| `Players` | Player join/leave events |
| `DataStoreService` | Persistent data |
| `TeleportService` | Multi-place navigation |
| `MarketplaceService` | Robux purchases |
| `MessagingService` | Cross-server communication |
| `RunService` | Game loop, tick events |
| `ReplicatedStorage` | Shared assets/code |
| `ServerScriptService` | Server code |

### Game Lifecycle

```lua
-- Server startup
game:BindToClose(function()
    -- Save all player data
end)

-- Player lifecycle
Players.PlayerAdded → Load data → Initialize city
Players.PlayerRemoving → Save data → Cleanup
```

---

## Acronyms Quick Reference

| Acronym | Full Name | Context |
|---------|-----------|---------|
| TH | Town Hall | Central building |
| DPS | Damage Per Second | Troop stat |
| HP | Hit Points | Health/durability |
| AoE | Area of Effect | Splash damage |
| CC | Clan Castle | Alliance troop storage |
| CW | Clan War | Alliance vs alliance |
| NPC | Non-Player Character | AI enemies |
| UI | User Interface | Menus, HUD |
| VIP | Very Important Person | Subscription tier |
| XP | Experience Points | Player progression |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-08 | Initial domain glossary for Battle Tycoon: Conquest |

---

## Contributing

When adding new terms to this glossary:

1. Place in appropriate section (or create new section)
2. Use consistent format: **Term**, **What**, **Purpose**, etc.
3. Cross-reference related terms
4. Update Table of Contents if adding new section
5. Increment version number
6. Reference GDD section when applicable
