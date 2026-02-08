# Claude Code Skills System

## Overview

Skills provide behavior modification, tool restriction, and executable workflow commands for the main Claude Code chat thread. They work alongside CLAUDE.md instructions to enforce orchestrator mode.

## Two Skill Formats

### 1. Single-File Skills (Behavioral/Interceptors)

Location: `.claude/skills/{skill-name}.md`

Used for: Mode enforcement, interceptors, validators, state tracking.

These skills modify behavior and have priorities that determine execution order.

### 2. Folder-Based Skills (Commands with `context: fork`)

Location: `.claude/skills/{skill-name}/SKILL.md`

Used for: Executable commands that spawn agents (migrated from `.claude/commands/`).

These skills use `context: fork` to spawn agents and execute workflows.

**Migrated Commands (now folder-based skills):**
- `commit/SKILL.md` - Generate conventional commits via git-commit-helper
- `qa-backend/SKILL.md` - Run backend QA via backend-qa agent
- `qa-frontend/SKILL.md` - Run frontend QA via frontend-qa agent
- `list-agents/SKILL.md` - List available agents
- `list-advisors/SKILL.md` - List advisory agents
- `audit-system/SKILL.md` - Run system audit via claude-code-hacker
- `jira-review-released/SKILL.md` - Review released Jira tasks
- `jira-accept-released/SKILL.md` - Accept released Jira tasks

## Skill Priority Order (Single-File Skills Only)

| Priority | Skill | Purpose |
|----------|-------|---------|
| **-2** | verification-before-reporting | **HIGHEST**: Enforce verification before any status claims |
| **-1** | orchestrator-mode | Primary tool restriction (Edit/Write/NotebookEdit forbidden) |
| **-1** | pre-task-validation | Sprint/assignment validation before agent dispatch |
| **-1** | agent-spawn-limiter | Rate limit background agent spawning (prevents crashes) |
| **0** | plan-mode | Plan mode routing to system-architect |
| **0** | code-change-interceptor | Route code changes to implementation agents |
| **0** | git-commit-interceptor | Route commits to git-commit-helper |
| **1** | infrastructure-operation-interceptor | Route K8s operations to devops-engineer |
| **2** | agent-cache | Consultation result caching |
| **4** | plan-state-tracker | Plan file management |

**Lower priority number = Higher precedence**

### Critical: Verification-Before-Reporting (Priority -2)

The `verification-before-reporting` skill has the highest priority and enforces:
- NEVER claim task completion without querying Jira first
- NEVER report agent status without TaskOutput verification
- NEVER guess or assume - verify or say "I don't know"

This skill prevents the orchestrator and agents from "lying" about task status by requiring actual API verification before any status claims.

### Agent Spawn Limiter (Priority -1)

The `agent-spawn-limiter` skill prevents Claude Code crashes by rate-limiting background agent spawning:
- Maximum 5 concurrent implementation/QA agents
- 2-second delay between agent spawns
- 5-second cooldown after spawning 5 agents
- Graceful degradation if system overload detected

**Created after 2026-01-21 incident** where spawning 9 QA agents simultaneously caused Claude Code to crash.

Configuration: `.claude/config/execution-limits.json`

## How Skills Work

### Trigger-Based Activation

Skills activate based on pattern matching in the user's input:

```yaml
trigger: |
  Activate when the user mentions:
  - "commit", "git commit"
  - etc.
```

### Tool Restrictions

Skills can allow or forbid specific tools:

```yaml
allowed-tools:
  - Read
  - Grep
  - Task
forbidden-tools:
  - Edit
  - Write
```

When multiple skills are active, the **most restrictive** set applies.

### Priority Resolution

When multiple skills match a request:
1. All matching skills activate
2. forbidden-tools from ALL skills are combined (union)
3. allowed-tools are intersected (only tools allowed by all)
4. Lower priority number takes precedence for behavioral instructions

## Orchestrator Mode Enforcement

The orchestrator-mode skill (priority -1) provides the primary enforcement:

### Forbidden Tools

- `Edit` - Modify existing files
- `Write` - Create new files
- `NotebookEdit` - Modify Jupyter notebooks

### Allowed Tools

- Reading: `Read`, `Grep`, `Glob`
- Infrastructure: `Bash` (read commands), Docker MCP, K8s MCP (read-only)
- Database: `mcp__postgres-*__query` (read-only)
- Coordination: `TodoWrite`, `Skill`, `Task`
- External: `mcp__atlassian__*`, `mcp__curl__*`, etc.

### Delegation Pattern

When code changes are needed:

```
User Request -> Orchestrator analyzes -> Task(agent) -> Agent implements
```

## Code Change Interceptor

The code-change-interceptor (priority 0) detects code modification requests and routes them:

| File Pattern | Agent |
|--------------|-------|
| `.claude/*` | claude-code-hacker |
| `services/admin-dashboard/**` | frontend-developer |
| `services/**/*.cs` | backend-developer |
| `tests/**/*.cs` | backend-qa |
| etc. | See routing-rules.md |

## Git Commit Interceptor

The git-commit-interceptor (priority 0) ensures all commits go through git-commit-helper:

```
User: "commit" -> Skill(skill="commit") -> git-commit-helper agent
```

---

## CRITICAL: Skill vs Task Tool Distinction

**The Skill tool and Task tool are COMPLETELY DIFFERENT. Confusing them causes crashes.**

### Skill Tool - For Workflow Commands ONLY

```python
# CORRECT: Invoke workflow commands
Skill(skill="commit")       # Invoke /commit command
Skill(skill="review-code")  # Invoke /review-code command
Skill(skill="qa-backend")   # Invoke /qa-backend command
Skill(skill="act")          # Invoke /act command
```

### Task Tool - For Spawning Agents

```python
# CORRECT: Spawn any agent
Task(subagent_type="backend-developer", prompt="...", description="...")
Task(subagent_type="backend-qa", prompt="...", description="...")
Task(subagent_type="database-advisor", prompt="...", description="...")
```

### FORBIDDEN (WILL CRASH)

```python
# WRONG - These patterns DO NOT EXIST and will crash
Skill(agent-backend-developer)          # NOT A VALID SKILL
Skill(skill="agent-backend-developer")  # NOT A VALID SKILL
Skill("backend-developer")              # INVALID SYNTAX

# WRONG - Task uses subagent_type, not agent
Task(agent="backend-developer")         # WRONG PARAMETER NAME
```

### Why This Matters

The Skill tool invokes WORKFLOW COMMANDS (defined in `.claude/commands/*.md`).
The Task tool spawns AGENTS (defined in `.claude/agents/*.md`).

There is NO skill named "agent-backend-developer" - attempting to invoke it crashes Claude Code.

---

## Infrastructure Interceptor

The infrastructure-operation-interceptor (priority 1) handles K8s operations:

- **Read-only** operations allowed directly via MCP
- **Write** operations delegated to devops-engineer

## Plan Mode

The plan-mode skill (priority 0) routes planning to system-architect:

- All plan requests go to system-architect agent
- Confidence tracking enforced
- Consultation mode control via /quick-plan and /consult-agents

## Limitations

### Skills Are Trigger-Based

Skills activate based on user input patterns. If a request doesn't match the trigger, the skill may not activate. However, orchestrator-mode has such a broad trigger that it should activate for almost everything.

### Not True Tool Blocking

Skills provide "soft enforcement" - they tell Claude what tools to avoid, but Claude could potentially still use forbidden tools. True blocking requires hooks (see GitHub issue #6885).

### Hook-Based Alternative

For hard enforcement, consider using Claude Code hooks (pre-commit hooks that parse transcripts). See:
- https://github.com/anthropics/claude-code/issues/6885
- `.claude/hooks/` directory (if implementing)

## Testing Skills

To test if skills are working:

1. Ask Claude to make a code change directly
2. Expected: Claude should delegate to appropriate agent
3. If Claude uses Edit directly, skill may not have activated

## Debugging

If skills aren't working:

1. Check trigger patterns match user input
2. Verify YAML frontmatter is valid
3. Check priority ordering
4. Ensure skill file is in `.claude/skills/`
5. Check Claude Code recognizes the skill (restart session)

## Related Files

- `.claude/rules/routing-rules.md` - File pattern to agent mapping
- `.claude/commands/*.md` - Remaining slash commands (act, implement-jira-task, refactor, etc.)
- `.claude/skills/{name}/SKILL.md` - Migrated commands (commit, qa-backend, qa-frontend, etc.)
- `.claude/agents/*.md` - Agent definitions
- `.claude/settings.json` - Project permissions
- `CLAUDE.md` - Primary orchestrator instructions

**See `.claude/STRUCTURE.md` for the complete folder organization standard.**
