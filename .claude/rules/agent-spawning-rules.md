# Agent Spawning Rules

**Location**: `.claude/rules/agent-spawning-rules.md`

This document defines the CRITICAL rules for agent spawning authority in the Claude Code system.

---

## The Rule (ABSOLUTE)

**Only the main thread (orchestrator) can spawn agents via Task tool.**

All subagents (any agent spawned by the main thread) MUST NOT use Task to spawn other agents.

---

## Why This Matters

Claude Code does not support nested agent spawning. When a subagent attempts to spawn another agent via Task tool, Claude Code crashes.

**Root Cause**: Agent-under-agent execution (nested Task calls) destabilizes the system.

**Discovery**: This was identified when claude-code-hacker attempted to spawn git-commit-helper directly, causing a system crash.

---

## Correct Patterns

| Scenario | Correct Approach | WRONG (crashes) |
|----------|------------------|-----------------|
| Agent needs to commit | `Skill(skill="commit")` | `Task(subagent_type="git-commit-helper")` |
| Agent needs QA | Signal via Jira label, main thread spawns QA | `Task(subagent_type="backend-qa")` |
| Agent needs consultation | `Skill(skill="...")` for advisory workflows | `Task(subagent_type="database-advisor")` |
| Agent needs help | Report in task output, main thread decides | Spawn another implementation agent |

---

## Agent Categories and Spawning Authority

| Category | Can Spawn Agents? | What They Can Do |
|----------|-------------------|------------------|
| **Main Thread (Orchestrator)** | YES | Only entity that can use Task tool for agent spawning |
| **Implementation Agents** | NO | Use `Skill(skill="commit")` for commits, signal completion via Jira labels |
| **QA Agents** | NO | Report results via Jira labels, task output |
| **Advisory Agents** | NO | Consultation only, provide recommendations |
| **Meta-Controller** | NO | claude-code-hacker uses `Skill(skill="commit")` like all other agents |

### Implementation Agents (NO spawning)
- backend-developer
- frontend-developer
- code-refactorer
- platform-windows-developer
- platform-linux-developer
- platform-macos-developer
- platform-lead-developer
- platform-build-engineer
- go-developer
- ui-design-ux
- ui-design-lead
- technical-writer

### QA Agents (NO spawning)
- backend-qa
- frontend-qa
- platform-qa
- go-qa

### Advisory Agents (NO spawning)
- ai-prompt-advisor
- database-advisor
- devops-engineer
- network-engineer-advisor
- product-strategy-advisor
- security-engineer-advisor
- staff-engineer-advisor
- system-architect

### Strategic Agents (LIMITED spawning - main thread only)
- project-manager (analyzes dependencies, reports to main thread - does NOT spawn)
- git-commit-helper (executes commits only)

---

## Task vs Skill Tool Distinction

### Task Tool - ORCHESTRATOR ONLY

The Task tool with `subagent_type` parameter is **exclusively for the main thread**:

```python
# ONLY the main thread can do this:
Task(
  subagent_type="backend-developer",
  prompt="Implement AI-XXX...",
  description="Implement feature"
)
```

### Skill Tool - ALL AGENTS CAN USE

The Skill tool loads command content **inline** into the calling agent's context. It does NOT "route through main thread".

```python
# ANY agent can do this:
Skill(skill="commit")     # Loads /commit command inline - command has context detection
Skill(skill="review-code")  # Loads command inline
```

**IMPORTANT**: Because Skill loads content inline, commands must be **context-aware**:
- The `/commit` command detects whether caller is main thread or subagent
- Main thread path: spawn git-commit-helper via Task
- Subagent path: execute commit directly (no Task spawning)

This design allows subagents to safely use `Skill(skill="commit")` without crashing.

---

## Workflow for Subagents

### When You Need to Commit Changes

1. Stage the files you modified using Bash (`git add <file>`)
2. Invoke the commit skill: `Skill(skill="commit")`
3. The `/commit` command will detect you are a subagent and provide **direct commit instructions** (no agent spawning)
4. Follow the subagent path in the command to execute the commit directly
5. Continue with your task or report completion

**Note**: The Skill tool does NOT route through main thread. It loads command content inline. The `/commit` command has context detection that provides different instructions for subagents vs main thread.

### When You Need QA

1. Complete your implementation
2. Update Jira label from `worktree-active` to `worktree-qa-pending`
3. Add a comment to the Jira task summarizing changes
4. Report "implementation complete" in your task output
5. **STOP** - Do NOT spawn QA agent
6. Main thread will handle QA dispatch

### When You Need Consultation

1. Document your question in your task output
2. Use appropriate Skill command if available
3. Or request consultation in your task output
4. Main thread will decide whether to spawn advisory agent

---

## Context-Aware Command Pattern

Commands invoked via `Skill(skill="...")` load **inline** into the calling agent's context. They do NOT route through main thread.

To make commands safe for both main thread and subagents, commands must include **context detection**:

### Example: /commit Command

```markdown
## Step 1: Detect Your Context

**You are the MAIN THREAD if:**
- Responding directly to user input
- NOT spawned by Task()
- No parent_tool_use_id

**You are a SUBAGENT if:**
- Spawned via Task(subagent_type="...")
- Running in background task
- Has parent_tool_use_id

## Step 2: Follow Correct Path

### PATH A: Main Thread
[spawn git-commit-helper via Task]

### PATH B: Subagent
[execute commit directly - NO Task spawning]
```

### Commands That Need Context Detection

| Command | Main Thread Path | Subagent Path |
|---------|-----------------|---------------|
| `/commit` | Spawn git-commit-helper | Execute commit directly |
| `/review-code` | Spawn senior-code-reviewer | Report findings in output |
| `/qa-backend` | Spawn backend-qa | Signal via Jira label |

---

## Enforcement

This rule is currently documentation-enforced. Each agent has an "Agent Spawning Authority" section.

### Future Enhancement

A PreToolUse hook could be added to block Task calls from subagent context by checking `parent_tool_use_id`:

```bash
# Pseudo-code for potential future hook
if [ -n "$parent_tool_use_id" ] && [ "$tool_name" = "Task" ]; then
  echo "BLOCKED: Subagents cannot spawn other agents via Task tool"
  exit 2
fi
```

---

## Quick Reference

**ALWAYS:**
- Use `Skill(skill="commit")` for commits
- Signal completion via Jira labels
- Report status in task output
- Let main thread coordinate multi-agent workflows

**NEVER:**
- Use `Task(subagent_type="...")` from any subagent
- Spawn QA agents directly
- Spawn implementation agents directly
- Create nested agent chains

---

## Cross-References

- **Orchestrator Mode**: `.claude/skills/orchestrator-mode.md` - Tool restrictions for main thread
- **Git Commit Interceptor**: `.claude/skills/git-commit-interceptor.md` - Commit workflow routing
- **Routing Rules**: `.claude/rules/routing-rules.md` - File pattern to agent mapping
- **Worktree Rules**: `.claude/rules/worktree-rules.md` - Merge authority and workflow
