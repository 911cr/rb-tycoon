# Routing Rules

**Location**: `.claude/rules/routing-rules.md`

File-path based routing to enforce orchestrator delegation to appropriate agents for the Battle Tycoon: Conquest Roblox game.

---

## File Pattern → Agent Mapping

### Meta-Controller Domain (claude-code-hacker EXCLUSIVE)

| File Pattern | Required Agent | Authority |
|--------------|----------------|-----------|
| `.claude/agents/*.md` | claude-code-hacker | EXCLUSIVE |
| `.claude/commands/*.md` | claude-code-hacker | EXCLUSIVE |
| `.claude/skills/*.md` | claude-code-hacker | EXCLUSIVE |
| `.claude/rules/*.md` | claude-code-hacker | EXCLUSIVE |
| `.claude/config/*.json` | claude-code-hacker | EXCLUSIVE |
| `.claude/STRUCTURE.md` | claude-code-hacker | EXCLUSIVE |

### Core Development Domain

| File Pattern | Required Agent | Task Invocation |
|--------------|----------------|-----------------|
| `src/server/**/*.lua` | roblox-developer | `Task(subagent_type="roblox-developer")` |
| `src/client/**/*.lua` | roblox-developer | `Task(subagent_type="roblox-developer")` |
| `src/shared/**/*.lua` | roblox-developer | `Task(subagent_type="roblox-developer")` |

### UI Domain

| File Pattern | Required Agent | Task Invocation |
|--------------|----------------|-----------------|
| `src/client/Controllers/UI*.lua` | roblox-ui-developer | `Task(subagent_type="roblox-ui-developer")` |
| `src/client/UI/**/*.lua` | roblox-ui-developer | `Task(subagent_type="roblox-ui-developer")` |
| `*.rbxm` (GUI assets) | roblox-ui-developer | `Task(subagent_type="roblox-ui-developer")` |

### Game Design Domain

| File Pattern | Required Agent | Task Invocation |
|--------------|----------------|-----------------|
| `src/shared/Constants/*Data.lua` | game-designer | Consult before changes |
| `src/shared/Constants/*Config.lua` | game-designer | Consult before changes |
| `docs/GAME_DESIGN_DOCUMENT.md` | game-designer | Consult for updates |

### Quality Domain

| File Pattern | Required Agent | Notes |
|--------------|----------------|-------|
| `tests/**/*.lua` | roblox-qa | `Task(subagent_type="roblox-qa")` |
| `tests/**/*.spec.lua` | roblox-qa | Test specifications |

### Documentation Domain

| File Pattern | Required Agent | Notes |
|--------------|----------------|-------|
| `docs/**/*.md` (excluding GDD) | technical-writer | General documentation |
| `docs/GAME_DESIGN_DOCUMENT.md` | game-designer | GDD updates |

---

## Advisory Agent Consultation

Before implementing features in these areas, consult the appropriate advisor:

| Area | Consult Agent | When |
|------|---------------|------|
| **Combat Balance** | combat-designer | Troop stats, damage formulas, spell effects |
| **Economy Balance** | economy-designer | Resource rates, costs, market prices |
| **Game Design** | game-designer | New features, progression, balance changes |
| **Player Psychology** | game-psychologist | Monetization, rewards, retention mechanics |
| **Architecture** | game-systems-architect | Multi-service design, data schemas |
| **Monetization** | monetization-strategist | Pricing, Battle Pass, offers |
| **Live Ops** | live-ops-manager | Events, seasonal content |

---

## Tool Selection: Task vs Skill

### Task Tool - For Spawning Agents

Use the `Task` tool with `subagent_type` parameter:

```python
# Spawn implementation agent
Task(
  subagent_type="roblox-developer",
  prompt="Implement the BuildingService...",
  description="Implement BuildingService"
)

# Get advisory consultation
Task(
  subagent_type="game-psychologist",
  prompt="Review the daily login reward design...",
  description="Review engagement design"
)
```

### Skill Tool - For Workflow Commands

```python
# Invoke commit workflow
Skill(skill="commit")
```

---

## Enforcement

The orchestrator MUST delegate to appropriate agents based on file patterns. Direct edits to implementation files by the orchestrator are prohibited.

### Allowed Orchestrator Edits

- `docs/plan/*.md` (planning artifacts)
- `README.md` (project readme)
- `.gitignore`

Everything else requires delegation via Task tool.
