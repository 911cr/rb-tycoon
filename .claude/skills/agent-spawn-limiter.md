---
skill-name: agent-spawn-limiter
priority: -1
trigger: |
  ALWAYS ACTIVE when spawning background agents via Task tool.
  Intercepts ALL Task(run_in_background=true) calls.

  Triggers:
  - Any Task tool call with run_in_background=true
  - Multiple Task calls in rapid succession
  - Batch agent spawning attempts
allowed-tools:
  - Task
  - TaskOutput
  - Read
  - Bash
  - mcp__atlassian__*
forbidden-tools: []
description: |
  AGENT SPAWN RATE LIMITER - Priority -1 (highest)

  Prevents Claude Code crashes by enforcing rate limits on background agent spawning.
  Created in response to 2026-01-21 session crash where 9 QA agents were spawned simultaneously.

  Configuration: .claude/config/execution-limits.json
---

# Agent Spawn Limiter

## Purpose

Prevents Claude Code system overload by rate-limiting background agent spawning. This skill was created after a production incident where spawning 9 agents simultaneously caused Claude Code to crash.

## THE RULES (MANDATORY)

### Rule 1: Maximum 5 Concurrent Implementation/QA Agents

**NEVER have more than 5 implementation or QA agents running simultaneously.**

Before spawning a new agent:
1. Count currently running agents (via mental tracking or TaskOutput)
2. If count >= 5, WAIT for at least one to complete
3. Do NOT spawn the 6th agent

### Rule 2: Spawn Delay Between Agents

**Wait 2 seconds between each agent spawn.**

```
Spawn Agent 1 → Wait 2000ms → Spawn Agent 2 → Wait 2000ms → ... → Spawn Agent 5 → STOP
```

### Rule 3: Batch Cooldown

**After spawning 5 agents, wait 5 seconds before considering more.**

Even if an agent completes quickly, do not immediately spawn a replacement. Wait for the batch cooldown.

### Rule 4: Verify Before Continuing

**After each spawn, verify the agent started successfully.**

```
Task(run_in_background=true) → Returns agent_id
Wait 2000ms
TaskOutput(agent_id=...) → Verify status is "running"
Only then consider spawning next agent
```

## Pre-Spawn Checklist (Execute Before EVERY Task Call)

Before calling `Task(run_in_background=true)`:

```markdown
## Pre-Spawn Check

1. **Current Running Agents**: {list agent IDs and count}
   - Agent 1: {agent_id} - {running/completed/failed}
   - Agent 2: {agent_id} - {running/completed/failed}
   - Agent 3: {agent_id} - {running/completed/failed}
   - Agent 4: {agent_id} - {running/completed/failed}
   - Agent 5: {agent_id} - {running/completed/failed}

2. **Count Check**: {count}/5 implementation/QA agents running
   - [ ] Count < 5? → PROCEED
   - [ ] Count >= 5? → WAIT for completion

3. **Spawn Delay Check**: Last spawn was {X}ms ago
   - [ ] >= 2000ms? → PROCEED
   - [ ] < 2000ms? → WAIT {2000-X}ms more

4. **System Health Check**: Recent TaskOutput calls
   - [ ] All succeeded? → PROCEED
   - [ ] 3+ consecutive failures? → PAUSE 30 seconds
```

## Spawn Protocol

### Safe Spawn Pattern (Follow This EXACTLY)

```python
# Pseudocode - agent MUST follow this mental model

running_agents = []
MAX_CONCURRENT = 5
SPAWN_DELAY_MS = 2000
BATCH_COOLDOWN_MS = 5000

for task in tasks_to_execute:
    # Step 1: Count running agents
    running_count = count_running_agents()

    # Step 2: Wait if at capacity
    while running_count >= MAX_CONCURRENT:
        wait_for_any_completion()
        running_count = count_running_agents()

    # Step 3: Check spawn delay
    if time_since_last_spawn() < SPAWN_DELAY_MS:
        wait(SPAWN_DELAY_MS - time_since_last_spawn())

    # Step 4: Spawn agent
    agent_id = Task(run_in_background=true, ...)
    running_agents.append(agent_id)

    # Step 5: Verify agent started
    wait(SPAWN_DELAY_MS)
    status = TaskOutput(agent_id)
    if status != "running":
        handle_spawn_failure(agent_id)

    # Step 6: Batch cooldown after 5 spawns
    if len(running_agents) % 5 == 0:
        wait(BATCH_COOLDOWN_MS)
```

### Spawning Multiple Agents (CORRECT Pattern)

```markdown
## Launching 5 QA Agents (CORRECT)

**Batch 1** (agents 1-5):
1. Spawn QA Agent for AI-962 → agent_id: qa_1
   Wait 2000ms, verify running
2. Spawn QA Agent for AI-963 → agent_id: qa_2
   Wait 2000ms, verify running
3. Spawn QA Agent for AI-964 → agent_id: qa_3
   Wait 2000ms, verify running
4. Spawn QA Agent for AI-965 → agent_id: qa_4
   Wait 2000ms, verify running
5. Spawn QA Agent for AI-966 → agent_id: qa_5
   Wait 2000ms, verify running

**Batch Cooldown**: Wait 5000ms (all 5 slots used)

**Batch 2** (agents 6+, after cooldown and capacity frees):
6. Check: qa_1-qa_5 all running (5/5)
   WAIT - at capacity
   [qa_1 completes] → Now 4/5
   Spawn QA Agent for AI-967 → agent_id: qa_6
   Wait 2000ms, verify running
   Now 5/5 again - WAIT for next completion
```

### Spawning Multiple Agents (INCORRECT Pattern - DO NOT DO)

```markdown
## Launching 5 QA Agents (INCORRECT - CAUSES CRASH)

Task(backend-qa, AI-962, run_in_background=true)
Task(backend-qa, AI-963, run_in_background=true)
Task(backend-qa, AI-964, run_in_background=true)
Task(backend-qa, AI-965, run_in_background=true)
Task(backend-qa, AI-966, run_in_background=true)

❌ NO! This spawns 5 agents with no delay, no verification, no capacity check.
```

## Graceful Degradation

### If TaskOutput Calls Start Failing

```markdown
## System Overload Detected

If 3 consecutive TaskOutput calls fail or timeout:

1. **IMMEDIATELY STOP** spawning new agents
2. **LOG**: "[SPAWN] System overload detected - pausing spawns for 30 seconds"
3. **WAIT** 30 seconds
4. **CHECK** status of existing agents
5. **RESUME** with SINGLE AGENT mode:
   - Spawn 1 agent
   - Wait for completion
   - Spawn next agent
   - Continue until system stabilizes
```

### If Claude Code Becomes Unresponsive

```markdown
## Recovery Protocol

1. STOP all pending spawn attempts
2. Do NOT retry failed spawns immediately
3. Wait for any running agents to complete naturally
4. After 60 seconds, attempt single agent spawn
5. If successful, gradually increase concurrency
```

## Integration with Other Components

### With project-manager.md

The project-manager agent MUST follow these limits when launching agents:
- When creating worktrees, create max 5 per batch
- When launching implementation agents, max 5 concurrent
- When launching QA agents, max 5 concurrent
- Always use the pre-spawn checklist

### With pre-task-validation.md

Pre-task validation runs BEFORE spawn limiting:
1. pre-task-validation verifies Jira state
2. agent-spawn-limiter enforces rate limits
3. Only then does agent actually spawn

### With verification-before-reporting.md

After agents complete:
1. Use TaskOutput to verify completion
2. Do NOT assume completion based on time
3. Verify Jira state before reporting

## Configuration Reference

All limits are defined in `.claude/config/execution-limits.json`:

| Setting | Value | Purpose |
|---------|-------|---------|
| `agents.implementation.maxConcurrent` | 5 | Max implementation agents |
| `agents.qa.maxConcurrent` | 5 | Max QA agents |
| `agents.implementation.spawnDelayMs` | 2000 | Delay between spawns |
| `agents.implementation.batchCooldownMs` | 5000 | Delay after 5 spawns |
| `systemTotal.maxConcurrentAgents` | 5 | Absolute max across all types |

## Incident History

### 2026-01-21: Session Crash from 9 Simultaneous QA Agents

**What happened:**
- Project-manager spawned 5 QA agents in one batch
- Immediately spawned 4 more QA agents
- Total: 9 agents with no delay, no verification
- Result: Claude Code crashed/became unresponsive

**Root cause:**
- No rate limiting on agent spawns
- No capacity checking before spawn
- Documentation encouraged "all at once" pattern

**Fix:**
- This skill created
- Limits defined in execution-limits.json
- Project-manager updated with batch rules
