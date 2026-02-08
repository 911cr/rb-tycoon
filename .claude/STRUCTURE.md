# Claude Code Configuration Structure Standard

**Authoritative Document**: This file defines the official folder structure and organization conventions for the `.claude/` directory for Battle Tycoon: Conquest. The `claude-code-hacker` agent maintains this standard.

---

## Directory Structure

```
.claude/
├── STRUCTURE.md              # THIS FILE - structure standard
├── settings.json             # MUST BE ROOT - Claude Code requirement
├── settings.local.json       # MUST BE ROOT - Claude Code requirement
├── settings.local.json.example
├── agents/                   # Agent definitions
│   ├── roblox-developer.md       # Core Luau/Roblox developer
│   ├── roblox-ui-developer.md    # GUI/UX developer
│   ├── roblox-qa.md              # Quality assurance
│   ├── game-designer.md          # Game design advisory
│   ├── game-systems-architect.md # Architecture advisory
│   ├── game-psychologist.md      # Engagement/ethics advisory
│   ├── combat-designer.md        # Combat balance advisory
│   ├── economy-designer.md       # Economy balance advisory
│   ├── monetization-strategist.md # Revenue advisory
│   ├── live-ops-manager.md       # Events/content advisory
│   └── *.md
├── commands/                 # Slash commands
│   └── *.md
├── skills/                   # Behavioral skills
│   ├── README.md
│   └── *.md
├── rules/                    # Operational rules and policies
│   ├── routing-rules.md          # File to agent mapping
│   ├── luau-coding-standards.md  # Luau code style
│   ├── roblox-security-rules.md  # Server authority rules
│   └── worktree-rules.md
├── docs/                     # Claude Code documentation
│   └── domain-glossary.md        # Game terminology
└── config/                   # Configuration files (JSON)
    └── *.json
```

---

## Project Source Structure

```
rb-battle-tycoon/
├── .claude/                  # Claude Code configuration
├── docs/
│   └── GAME_DESIGN_DOCUMENT.md   # Complete GDD
├── src/
│   ├── server/               # Server-side code (ServerScriptService)
│   │   ├── Services/             # Game services
│   │   │   ├── DataService.lua       # Player data management
│   │   │   ├── BuildingService.lua   # Building placement/upgrades
│   │   │   ├── CombatService.lua     # Battle simulation
│   │   │   ├── EconomyService.lua    # Resource management
│   │   │   └── AllianceService.lua   # Clan systems
│   │   └── init.server.lua       # Server entry point
│   ├── client/               # Client-side code (StarterPlayerScripts)
│   │   ├── Controllers/          # UI controllers
│   │   │   ├── CityController.lua    # City view management
│   │   │   ├── BattleController.lua  # Battle UI
│   │   │   └── UIController.lua      # Main UI orchestration
│   │   └── init.client.lua       # Client entry point
│   └── shared/               # Shared code (ReplicatedStorage)
│       ├── Constants/            # Game data tables
│       │   ├── BuildingData.lua      # Building stats/costs
│       │   ├── TroopData.lua         # Troop stats
│       │   ├── SpellData.lua         # Spell effects
│       │   └── BalanceConfig.lua     # Tuning values
│       ├── Types/                # Type definitions
│       │   ├── PlayerTypes.lua
│       │   ├── BuildingTypes.lua
│       │   └── CombatTypes.lua
│       └── Modules/              # Shared utilities
│           ├── Signal.lua            # Event system
│           └── Promise.lua           # Async handling
├── tests/                    # Test files
│   ├── server/
│   └── shared/
├── assets/                   # Game assets
│   ├── gui/                      # UI assets
│   ├── models/                   # 3D models
│   └── sounds/                   # Audio files
└── CLAUDE.md                 # Project instructions
```

---

## Folder Purposes

### `/agents/` - Agent Definitions

**Purpose**: Contains all agent persona definitions for Battle Tycoon development.

**File Format**: Markdown with YAML frontmatter

**Naming**: `{agent-name}.md` (kebab-case)

**Agent Categories**:

| Category | Agents | Purpose |
|----------|--------|---------|
| **Implementation** | roblox-developer, roblox-ui-developer | Write code |
| **Quality** | roblox-qa | Test and validate |
| **Advisory** | game-designer, combat-designer, economy-designer, game-psychologist, monetization-strategist, live-ops-manager | Provide expertise |
| **Architecture** | game-systems-architect | System design |

---

### `/commands/` - Slash Commands

**Purpose**: Contains workflow orchestration commands invoked via `/command-name`.

**File Format**: Markdown with YAML frontmatter

**Naming**: `{command-name}.md` (kebab-case)

---

### `/skills/` - Behavioral Skills

**Purpose**: Contains skills that modify Claude's behavior, trigger-based activation, and executable workflow commands.

**Two Formats Supported**:

1. **Single-file skills** (behavioral/interceptor): `{skill-name}.md`
2. **Folder-based skills** (executable commands): `{skill-name}/SKILL.md`

---

### `/rules/` - Operational Rules and Policies

**Purpose**: Contains operational rules, routing policies, and coding standards.

**File Format**: Markdown

**Current Rules**:

| File | Purpose |
|------|---------|
| `routing-rules.md` | File pattern to agent mapping |
| `luau-coding-standards.md` | Luau code style and conventions |
| `roblox-security-rules.md` | Server authority and exploit prevention |
| `worktree-rules.md` | Git worktree coordination |

---

### `/docs/` - Claude Code Documentation

**Purpose**: Documentation about the Claude Code setup and domain knowledge.

**Current Docs**:

| File | Purpose |
|------|---------|
| `domain-glossary.md` | Game terminology reference |

---

### `/config/` - Configuration Files

**Purpose**: Contains JSON configuration files.

**File Format**: JSON

---

## File Pattern to Agent Mapping

| File Pattern | Required Agent |
|--------------|----------------|
| `.claude/**/*.md` | claude-code-hacker (EXCLUSIVE) |
| `src/server/**/*.lua` | roblox-developer |
| `src/client/**/*.lua` | roblox-developer |
| `src/shared/**/*.lua` | roblox-developer |
| `src/client/Controllers/UI*.lua` | roblox-ui-developer |
| `src/client/UI/**/*.lua` | roblox-ui-developer |
| `src/shared/Constants/*Data.lua` | Consult game-designer first |
| `src/shared/Constants/*Config.lua` | Consult game-designer first |
| `tests/**/*.lua` | roblox-qa |
| `docs/**/*.md` | technical-writer |

---

## Agent Advisory Domains

| Domain | Advisory Agent | Consult When |
|--------|----------------|--------------|
| Combat balance | combat-designer | Troop stats, damage formulas |
| Economy balance | economy-designer | Resource rates, costs |
| Game design | game-designer | New features, progression |
| Player engagement | game-psychologist | Retention, monetization ethics |
| Architecture | game-systems-architect | Multi-place design, data schemas |
| Revenue | monetization-strategist | Pricing, Battle Pass |
| Live ops | live-ops-manager | Events, seasonal content |

---

## Naming Conventions

### Agent Files
- Use kebab-case: `roblox-developer.md`
- Name reflects role: `combat-designer.md`
- Suffix with `-designer` for balance advisors

### Luau Files
- Use PascalCase for services: `BuildingService.lua`
- Use PascalCase for types: `BuildingTypes.lua`
- Use PascalCase for data: `BuildingData.lua`

### Command Files
- Use kebab-case: `qa-backend.md`
- Use verbs when possible: `commit.md`

---

## Enforcement

The `claude-code-hacker` agent is responsible for:

1. **Maintaining this standard** - All structure changes go through this agent
2. **Enforcing organization** - New files must follow the decision tree
3. **Migrating files** - Moving files to correct locations when found misplaced
4. **Updating references** - Ensuring all path references are updated after moves

### Self-Audit Checklist

When auditing `.claude/` structure:

- [ ] All agents in `/agents/` with valid frontmatter
- [ ] All commands in `/commands/` with valid frontmatter
- [ ] All skills in `/skills/` with valid frontmatter
- [ ] All JSON configs in `/config/`
- [ ] All rules/policies in `/rules/`
- [ ] All Claude Code docs in `/docs/`
- [ ] No loose files in `.claude/` root (except STRUCTURE.md)
- [ ] All file names use kebab-case
- [ ] All Luau files follow coding standards

---

## Version History

| Date | Change | Author |
|------|--------|--------|
| 2026-02-08 | Initial structure for Battle Tycoon: Conquest | claude-code-hacker |
