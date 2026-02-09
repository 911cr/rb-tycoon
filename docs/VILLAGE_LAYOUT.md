# Medieval Village Layout Design

## Overview
A cohesive rustic medieval village with cobblestone streets, connected buildings, and distinct zones. All buildings face the main path with the Town Hall at the end of the road as the centerpiece. The village is enclosed by defensive walls with battlements.

## Village Layout (Current Implementation)

```
                         [NORTH - Town Hall Plaza]
                        ┌────────────────────────────────┐
                        │         ⛪ TOWN HALL           │
                        │       (faces SOUTH)            │
                        │      Center of village         │
                        │   Position: X=60, Z=155        │
                        └────────────────────────────────┘
                                    │
                    ═══════════════════════════════════
                              TOWN HALL PLAZA
                    ═══════════════════════════════════
                                    │
    ┌───────────────────────────────┴───────────────────────────────┐
    │                                                               │
    │   ┌──────────┐                                 ┌──────────┐  │
    │   │  FARM    │                                 │ BARRACKS │  │
    │   │ (East→)  │                                 │ (←West)  │  │
    │   │ X=25     │         MAIN PATH               │ X=95     │  │
    │   │ Z=100    │         (cobblestone)           │ Z=100    │  │
    │   └──────────┘              │                  └──────────┘  │
    │                             │                                 │
    │                   ══════════╪══════════                      │
    │                   Cross Path (Z=100)                         │
    │                   ══════════╪══════════                      │
    │                             │                                 │
    │   ┌──────────┐              │                  ┌──────────┐  │
    │   │  LUMBER  │              │                  │   GOLD   │  │
    │   │   MILL   │              │                  │   MINE   │  │
    │   │ (East→)  │              │                  │ (←West)  │  │
    │   │ X=25     │              │                  │ X=95     │  │
    │   │ Z=50     │              │                  │ Z=50     │  │
    │   └──────────┘              │                  └──────────┘  │
    │                             │                                 │
    │                   ══════════╪══════════                      │
    │                   Cross Path (Z=50)                          │
    │                   ══════════╪══════════                      │
    │                             │                                 │
    ├─────────────────────────────┼─────────────────────────────────┤
    │                             │                                 │
    │   ████████████████████████  │  ████████████████████████████  │
    │   █  VILLAGE WALLS (with battlements around perimeter)   █  │
    │   ████████████████████████  │  ████████████████████████████  │
    │                             │                                 │
    │                    ┌────────┴────────┐                       │
    │                    │   🏰 ENTRANCE   │                       │
    │                    │      GATE       │                       │
    │                    │   (Z=0 area)    │                       │
    │                    │ Towers + Torches│                       │
    │                    └─────────────────┘                       │
    │                                                               │
    └───────────────────────────────────────────────────────────────┘
                              [SOUTH - Entrance]
```

## Building Positions & Facing Directions

### Current Implementation (SimpleTest.server.lua)

| Building    | Position (X, Z) | Size         | Facing    | Notes                           |
|-------------|-----------------|--------------|-----------|----------------------------------|
| Town Hall   | (60, 155)       | 20x14x18     | South     | End of path, faces incoming players |
| Farm 1      | (25, 100)       | 18x8x15      | East      | Default farm, left side         |
| Barracks    | (95, 100)       | 18x10x16     | West      | Right side, entrance toward path |
| Lumber Mill | (25, 50)        | 18x10x16     | East      | Left side, entrance toward path |
| Gold Mine   | (95, 50)        | 16x8x14      | West      | Right side, entrance toward path |
| Entrance Gate| (60, 0)        | Arch + Towers| North     | Main entry to village           |

### Additional Farm Positions (Purchased via Shop)

| Farm  | Position (X, Z) | Facing | Interior Y | Purchase Cost           |
|-------|-----------------|--------|------------|-------------------------|
| Farm 1| (25, 100)       | East   | Y=700      | Free (default)          |
| Farm 2| (25, 130)       | East   | Y=720      | 1,000 Gold + 500 Wood   |
| Farm 3| (95, 130)       | West   | Y=740      | 3,000 Gold + 1,500 Wood |
| Farm 4| (10, 115)       | East   | Y=760      | 10,000 Gold + 5,000 Wood|
| Farm 5| (110, 115)      | West   | Y=780      | 30,000 Gold + 15,000 Wood|
| Farm 6| (60, 140)       | South  | Y=800      | 75,000 Gold + 35,000 Wood|

Each farm has:
- **Separate interior** at its own Y level (isolated from other farms)
- **Independent production** (crops, windmill, storage)
- **Own workers** (farmers and carriers)
- **Own upgrade levels** (hoe, watering can, windmill, etc.)
- **Production stats billboard** on exterior sign showing food and crop count

### Facing Direction Key
- **North**: Default, entrance on -Z side
- **South**: Entrance on +Z side (toward entrance gate)
- **East**: Entrance on +X side (right, toward center path)
- **West**: Entrance on -X side (left, toward center path)

## Ground Dimensions

| Element        | Size (studs)  | Position           | Notes                    |
|----------------|---------------|--------------------|--------------------------|
| Ground         | 130 x 170     | Centered at X=60   | Green grass floor        |
| Main Path      | 8 x 150       | X=60, Z=5 to Z=155 | Cobblestone, north-south |
| Cross Path 1   | 70 x 6        | Z=50               | Cobblestone, east-west   |
| Cross Path 2   | 70 x 6        | Z=100              | Cobblestone, east-west   |
| Town Hall Plaza| 40 x 20       | Z=155              | Larger cobblestone area  |

## Village Walls

### Wall Specifications
- **Height**: 8 studs
- **Thickness**: 3 studs
- **Material**: Cobblestone (gray)
- **Battlements**: Every 12 studs, 2 stud protrusions

### Wall Segments
| Segment  | Position            | Size        | Notes              |
|----------|---------------------|-------------|---------------------|
| West Wall | X=-5 to X=-5       | 3 x 8 x 170 | Left perimeter      |
| East Wall | X=125 to X=125     | 3 x 8 x 170 | Right perimeter     |
| North Wall| Z=170              | 130 x 8 x 3 | Behind Town Hall    |
| South Left| X=-5 to X=40, Z=0  | 45 x 8 x 3  | Gate gap on left    |
| South Right| X=80 to X=125, Z=0| 45 x 8 x 3  | Gate gap on right   |

## Entrance Gate

### Components
- **Gate Opening**: 40 studs wide (X=40 to X=80)
- **Towers**: 10x10x18 studs, on each side of gate
- **Torches**: 4 torches on each tower (fire effect)
- **Sign**: "VILLAGE" above gate

## Farm Expansion System

### Multi-Farm Architecture
Players start with Farm 1 and can purchase additional farms (up to 6) through the Shop UI:
- **Shop → Expansion tab**: Lists all available farm plots
- **Town Hall Level**: Unlocks additional farm slot capacity
- **Resource Cost**: Gold + Wood required for each new farm

### Farm Interior Isolation
Each farm has a completely separate interior space at a different Y level:
- Farm 1: Y=700
- Farm 2: Y=720 (20 studs apart to prevent overlap)
- Farm 3: Y=740
- Farm 4: Y=760
- Farm 5: Y=780
- Farm 6: Y=800

This ensures players in different farms never see each other's interiors.

## Future Expansion Areas

### Additional Building Plots
When more buildings are purchased, they can be placed:

1. **Behind Town Hall** (Z > 155): Space for advanced buildings
2. **Extended paths**: Extend main path and add more cross-paths

## Decorative Elements

### Street Furniture
- Wooden barrels (near shops)
- Crates and sacks (near storage)
- Street lamps (torch style, every 20 studs on path)
- Flower boxes on buildings

### Wall Decorations
- Battlements with gaps for archers
- Corner towers with torches
- Banners on gate towers

### Ambient Details
- Smoke particles from chimneys
- Flags/banners on Town Hall
- Signs on buildings with building names

## Farming System

### Wheat Growth Stages
1. Planted (just dirt with seeds)
2. Sprouting (small green shoots)
3. Growing (medium height, green)
4. Mature (tall, golden wheat)
5. Ready to Harvest (swaying animation)

### Transport Upgrades
| Level | Vehicle | Capacity | Speed |
|-------|---------|----------|-------|
| 1     | Wheelbarrow | 10 wheat | Slow |
| 2     | Hand Cart | 25 wheat | Slow |
| 3     | Horse Cart | 50 wheat | Medium |
| 4     | Draft Horse Cart | 100 wheat | Medium |
| 5     | Ox Cart | 200 wheat | Fast |
