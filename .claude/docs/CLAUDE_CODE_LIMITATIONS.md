# Claude Code Limitations and Workarounds

**Location**: `.claude/docs/CLAUDE_CODE_LIMITATIONS.md`
**Last Updated**: 2026-01-21
**Maintainer**: claude-code-hacker

This document records known Claude Code limitations, incidents, and the workarounds implemented in this project.

---

## Incident: Session Crash from Concurrent Agent Spawning

**Date**: 2026-01-21
**Severity**: Critical
**Status**: Mitigated

### What Happened

During execution of a 10-task plan, the project-manager agent spawned 9 QA agents simultaneously without any rate limiting or batching. This caused Claude Code to become unresponsive and crash, losing the session state.

### Root Cause Analysis

1. **No spawn rate limiting**: Agents were spawned in rapid succession with no delay between spawns
2. **No concurrency limit**: 9 agents running simultaneously exceeded system capacity
3. **All worktrees created upfront**: 10 worktrees were created at the start instead of in batches
4. **No merge gate**: Batches were not properly separated; next batch started before previous batch merged

### Technical Details

```
Timeline:
10:00:00 - Plan execution started
10:00:01 - 10 worktrees created (WRONG: should be 5 per batch)
10:00:02 - 5 implementation agents spawned
10:00:03 - 4 more QA agents spawned (WRONG: no rate limiting)
10:00:05 - System became unresponsive
10:00:30 - Session terminated
```

### Mitigation Implemented

#### 1. Spawn Rate Limiting

**Configuration**: `.claude/config/execution-limits.json`

| Setting | Value | Purpose |
|---------|-------|---------|
| `maxConcurrent` | 5 | Max implementation/QA agents at once |
| `spawnDelayMs` | 2000 | Wait 2s between spawns |
| `batchCooldownMs` | 5000 | Wait 5s after spawning 5 agents |

**Skill**: `.claude/skills/agent-spawn-limiter.md` (priority -1)

#### 2. Dependency-Based Batching

Tasks are now grouped into batches based on dependencies:
- Batch 1: Tasks with NO dependencies
- Batch N+1: Tasks whose dependencies are ALL in completed batches
- Maximum 5 tasks per batch

#### 3. Mandatory Merge Gate

**CRITICAL**: The most important fix.

```
Batch 1: Create worktrees → Run agents → QA → MERGE ALL
         ↓ (MERGE GATE - don't proceed until merged)
Batch 2: Create worktrees → Run agents → QA → MERGE ALL
         ↓ (MERGE GATE)
Batch N: Continue...
```

The merge gate ensures:
- No Batch N+1 worktrees are created until ALL Batch N worktrees are merged
- Build is verified after each batch's merges
- Sequential integration prevents merge conflicts

### Verification

These rules are enforced at multiple levels:

| Layer | File | Enforcement |
|-------|------|-------------|
| Configuration | `execution-limits.json` | Defines limits |
| Skill | `agent-spawn-limiter.md` | Intercepts Task calls |
| Agent Instructions | `project-manager.md` | Workflow documentation |
| Rules | `worktree-rules.md` | Operational rules |

---

## Known Limitation: Background Agent Monitoring

### Issue

Claude Code's `TaskOutput` function can sometimes return stale data or fail to report agent completion promptly.

### Workaround

1. Always cross-verify with Jira status (agents update Jira on completion)
2. Use multiple `TaskOutput` calls before assuming status
3. Never report completion without verification evidence

### Enforcement

See `.claude/skills/verification-before-reporting.md`

---

## Known Limitation: Context Window Management

### Issue

Large plans with many tasks can exceed context window limits, causing loss of tracking state.

### Workaround

1. Track parallel agents in plan state file: `docs/plan/{plan-id}/batch-state.json`
2. Use Jira labels for state tracking (survives context loss)
3. Keep agent tracking mental model simple

### Jira Labels for State Tracking

| Label | Meaning |
|-------|---------|
| `worktree-active` | Task being worked in worktree |
| `worktree-qa-pending` | Development complete, awaiting QA |
| `worktree-ready-to-merge` | QA passed, awaiting merge |
| `worktree-merging` | Merge in progress (lock) |

---

## Best Practices Derived from Incidents

### DO

- Create worktrees in batches of max 5
- Wait 2 seconds between agent spawns
- Verify each agent started before spawning next
- Complete ALL merges for a batch before creating next batch's worktrees
- Use Jira labels for persistent state tracking
- Verify via API before reporting any status

### DO NOT

- Create all worktrees upfront
- Spawn more than 5 agents simultaneously
- Skip the merge gate between batches
- Assume completion based on time elapsed
- Report status without verification

---

## Configuration Quick Reference

**All limits in**: `.claude/config/execution-limits.json`

```json
{
  "worktrees": { "maxPerBatch": 5 },
  "agents": {
    "implementation": { "maxConcurrent": 5, "spawnDelayMs": 2000 },
    "qa": { "maxConcurrent": 5, "spawnDelayMs": 2000 }
  },
  "systemTotal": { "maxConcurrentAgents": 5 },
  "mergeGate": { "enabled": true, "enforcement": "MANDATORY" }
}
```

---

## Reporting New Issues

If you discover a new Claude Code limitation:

1. Document the incident (date, what happened, root cause)
2. Implement workaround in appropriate configuration/skill
3. Add documentation to this file
4. Update relevant agent instructions
5. Notify maintainer (claude-code-hacker)
