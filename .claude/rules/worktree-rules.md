# Git Worktree Rules for Agents

This document defines the rules and workflow for agents working with git worktrees in the ai-it-for-msps project.

---

## Merge Authority (CRITICAL)

**Only the main thread (orchestrator) is authorized to merge worktree branches into the base branch.**

All agents (project-manager, backend-developer, frontend-developer, code-refactorer, etc.) must:
1. Complete their work (implementation or analysis)
2. Signal completion via Jira labels (`worktree-qa-pending` for dev, `worktree-ready-to-merge` for QA)
3. Wait for the main thread to handle the merge

**Project-manager's role**: Analyze dependencies, verify QA completion via Jira, and report readiness to main thread. Project-manager does NOT execute merges.

**Merge Lock Protocol:**
1. Before merge, main thread adds `worktree-merging` label (lock)
2. Only ONE task can merge at a time
3. After merge, main thread removes the lock and notifies project-manager
4. Other tasks queue based on `worktree-ready-to-merge` order

---

## When to Use Worktrees

### Decision Matrix

| Scenario | Use Worktree? | Reason |
|----------|---------------|--------|
| Single agent, single task | NO | No benefit, adds complexity |
| Multiple agents, same feature (backend + frontend) | YES | Parallel work without blocking |
| Multiple agents, independent features | YES | Isolated branches, no conflicts |
| Quick bug fix while feature in progress | YES | Keep feature work separate from hotfix |
| Long-running feature with frequent main updates | YES | Easier to rebase without disrupting work |
| Single developer, sequential tasks | NO | Just use branch switching |

### Automatic Worktree Triggers

Agents SHOULD create a worktree when:
1. **Parallel task execution requested** - User explicitly asks for parallel work
2. **Independent subtasks identified** - Backend and frontend can proceed simultaneously
3. **Hotfix during feature work** - Urgent fix needed while feature branch has uncommitted changes
4. **Multi-agent coordination** - Project manager assigns multiple agents to same Epic

Agents SHOULD NOT create a worktree when:
1. **Single sequential task** - No parallelism benefit
2. **Quick changes** - Less than 30 minutes of work
3. **Already in clean main** - No need to preserve separate state
4. **Dependent tasks** - Frontend blocked waiting for backend API

---

## Directory Structure

### Worktree Location

**Path**: `/development/ai-it-for-msps.worktrees/{unique-identifier}`

```
/development/
├── ai-it-for-msps/                         # Main worktree (primary)
│   ├── .git/                               # Git directory (shared metadata)
│   └── ...
│
└── ai-it-for-msps.worktrees/               # Worktrees directory
    ├── AI-101-a3f2/                        # Worktree for AI-101 task
    └── AI-102-b7c9/                        # Worktree for AI-102 task
```

### Naming Conventions

**Branch Pattern**: `{base-branch}-wt-{jira-key}-{short-hash}`
- Example: `feat/AI-100-wt-AI-101-a3f2`

**Directory Pattern**: `{jira-key}-{short-hash}`
- Example: `AI-101-a3f2`

### Maximum Concurrent Worktrees

**Limit**: 8 active worktrees maximum (conservative limit for stability)

If limit reached:
1. Check `scripts/worktree-status.sh` for worktree states
2. Prioritize merging `worktree-ready-to-merge` tasks
3. Clean up completed worktrees
4. Then create new worktree

---

## DEPENDENCY MERGE GATE (ABSOLUTE - CRITICAL)

**A task's worktree is ONLY created after ALL tasks it depends on are MERGED into the active branch.**

This is the most critical rule for parallel execution. Without it, dependent tasks start with stale code and fail.

### The Rule (MANDATORY)

| Requirement | Description |
|-------------|-------------|
| **Dependencies must be MERGED** | Not just "complete" - the code must be MERGED into active branch |
| **Worktree created just-in-time** | Worktree is created immediately before agent launch, after dependencies verified |
| **Never pre-create worktrees** | Do NOT create worktrees for tasks whose dependencies haven't merged |

### Why This Matters

On 2026-01-21, creating all worktrees upfront and launching all agents simultaneously:
- Caused tasks with dependencies to fail (code they needed didn't exist)
- Wasted compute on tasks that couldn't succeed
- Contributed to Claude Code crash from spawning 9 agents at once

**The fix:** Worktrees are created **just-in-time** only when a task's dependencies are **MERGED**.

---

## Just-In-Time Worktree Creation Protocol

**Create worktrees ONLY when a task is ready to execute (all dependencies MERGED into active branch):**

```
1. Parse plan state file dependency graph
2. Identify tasks with ZERO unmet dependencies (no blockers, or all blockers MERGED)
3. For each ready task:
   a. VERIFY all dependencies are MERGED (not just complete - MERGED to active branch)
   b. Create worktree (just-in-time)
   c. Launch agent
4. When task completes + QA passes:
   a. MERGE IMMEDIATELY (do not wait for other tasks)
   b. Cleanup worktree
   c. Check if blocked tasks are now unblocked (their dependencies now MERGED)
5. Repeat until all tasks complete
```

**CRITICAL DISTINCTION:**
- "Complete" = Agent finished, QA passed
- "MERGED" = Code integrated into active branch

**A dependency is NOT satisfied until it is MERGED.** Completion alone is insufficient.

### Dependency-Based Execution Example

**Given these dependencies:**
```
AI-964 → AI-965 → AI-967
AI-966 → AI-967
AI-962, AI-963 → AI-968
AI-967 → AI-972
```

**Correct execution flow:**
```
T=0: Tasks with no dependencies: AI-962, AI-963, AI-964, AI-966
     Create 4 worktrees, launch 4 agents (rate limited)

T=5min: AI-962 completes → QA → MERGE IMMEDIATELY → cleanup
        AI-963 completes → QA → MERGE IMMEDIATELY → cleanup
        → Check: AI-968 now unblocked (AI-962+AI-963 done)
        → Create worktree for AI-968, launch agent

T=8min: AI-964 completes → QA → MERGE IMMEDIATELY → cleanup
        → Check: AI-965 now unblocked
        → Create worktree for AI-965, launch agent

T=10min: AI-966 completes → QA → MERGE IMMEDIATELY → cleanup
         (AI-967 still waiting for AI-965)

... continues with dependency-based unlocking ...
```

**INCORRECT approach (DO NOT DO):**
```
❌ Create ALL 8 worktrees at once
❌ Launch ALL 8 agents at once
❌ AI-972 immediately fails because AI-967 code doesn't exist
❌ AI-967 fails because AI-965 code doesn't exist
```

### Configuration Reference

Limits are defined in `.claude/config/execution-limits.json`:

| Setting | Value | Purpose |
|---------|-------|---------|
| `worktrees.maxConcurrent` | 8 | Max active worktrees at any time |
| `agents.maxConcurrentImplementation` | 8 | Max implementation agents |
| `dependencyBatching.enabled` | false | NO BATCHES - just-in-time instead |
| `justInTimeWorktrees.enabled` | true | Create worktrees only when ready |
| `mergeImmediately.enabled` | true | Merge each task as it completes |

---

## IMMEDIATE MERGE (CRITICAL - MANDATORY)

**Merge each task IMMEDIATELY after QA passes. Do not accumulate merges.**

### Why Immediate Merge?

Tasks must be merged immediately to:
1. **Unblock dependent tasks** - dependent tasks cannot start until dependencies are MERGED
2. Keep active branch current for dependent tasks
3. Prevent merge conflicts from accumulating
4. Allow dependent tasks to start as soon as their blockers complete

**The Dependency Unlock Chain:**
```
Task A completes → QA passes → MERGE immediately → Task B now unblocked → Create worktree for B
```

If you delay merging Task A, Task B cannot start (even if A is "complete").

```
┌─────────────────────────────────────────────────────────────────────┐
│                    JUST-IN-TIME EXECUTION FLOW                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   TASK LIFECYCLE (each task independently):                         │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │ 1. Check dependencies met                                   │   │
│   │ 2. Create worktree (just-in-time)                           │   │
│   │ 3. Launch agent                                             │   │
│   │ 4. Wait for agent to complete                               │   │
│   │ 5. QA task                                                  │   │
│   │ 6. MERGE IMMEDIATELY (do not wait for other tasks)          │   │
│   │ 7. Cleanup worktree                                         │   │
│   │ 8. Check for newly unblocked tasks                          │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│   DEPENDENCY UNLOCKING:                                             │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │ When task merges:                                           │   │
│   │   → Mark task as "completed" in dependency graph            │   │
│   │   → Find tasks whose ALL dependencies are now complete      │   │
│   │   → Those tasks are now "ready" - create worktrees for them │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Why Immediate Merge Is Mandatory

**Without immediate merge (BROKEN workflow - what went wrong on 2026-01-21):**
```
1. Create ALL worktrees upfront
2. Launch ALL agents simultaneously
3. Agents complete, but NOTHING is merged
4. Result: 10 divergent branches with massive merge conflicts
5. Work is LOST because branches cannot be reconciled
6. Dependent tasks fail because code they need doesn't exist
```

**With immediate merge (CORRECT workflow):**
```
1. Task A ready (no deps) → Create worktree → Agent → QA → MERGE
2. Task B depends on A → A is now MERGED → Create worktree for B → Agent → QA → MERGE
3. Task C depends on B → B is now MERGED → Create worktree for C → Agent → QA → MERGE
4. Result: Clean sequential integration, no conflicts, dependencies always available
```

### Dependency Merge Gate Enforcement Rules (ABSOLUTE)

| Rule | Description | Violation Consequence |
|------|-------------|----------------------|
| **GATE-1** | Task's worktree created ONLY after ALL dependencies MERGED | Task fails - code doesn't exist |
| **GATE-2** | Merge ONE task at a time (worktree-merging lock) | Concurrent merge corruption |
| **GATE-3** | Merge IMMEDIATELY after QA passes | Dependent tasks blocked |
| **GATE-4** | If ANY merge fails, STOP and resolve before continuing | Cascading failures |

### Pre-Worktree Verification (Per-Task)

Before creating a worktree for ANY task, the main thread MUST verify (with project-manager's dependency analysis):

```markdown
## Pre-Worktree Verification: {AI-XXX}

### Dependency Status (ALL must be MERGED - not just complete):
- [ ] Dependency AI-AAA: MERGED to active branch (verified via git log)
- [ ] Dependency AI-BBB: MERGED to active branch (verified via git log)
- [ ] Active branch builds successfully

### Verification Passed:
- [ ] All dependencies MERGED → Create worktree → Launch agent
- [ ] ANY dependency NOT merged → WAIT - cannot create worktree yet
```

### Merge Gate Violations

**If you skip the dependency merge gate:**
1. Task will start with stale code (dependency code doesn't exist)
2. Task will fail or produce incorrect output
3. Work may need to be discarded and redone
4. Merge conflicts will accumulate

**Main thread is responsible for enforcing the dependency merge gate using project-manager's analysis.** Development agents must NEVER create worktrees - they only work in worktrees created by the main thread after verifying all dependencies are MERGED.

---

## Agent Working Directory Rules

### Handoff Protocol

When project-manager or QA hands off a task to a development agent, the handoff MUST include:

```
WORKTREE TASK ASSIGNMENT
------------------------
Jira Task:      AI-101
Worktree Path:  /development/ai-it-for-msps.worktrees/AI-101-a3f2
Branch:         feat/AI-100-wt-AI-101-a3f2
Base Branch:    feat/AI-100

IMPORTANT: All file operations MUST be performed in the
worktree path above. Do NOT modify files in
/development/ai-it-for-msps (main project directory).
```

### Mandatory First Action

Before making any changes, the agent MUST verify correct context:

```bash
# 1. Change to worktree directory
cd /development/ai-it-for-msps.worktrees/AI-101-a3f2

# 2. Verify path
pwd
# Expected: /development/ai-it-for-msps.worktrees/AI-101-a3f2

# 3. Verify branch
git branch
# Expected: * feat/AI-100-wt-AI-101-a3f2

# 4. Verify worktree is listed
git worktree list | grep "AI-101"
```

**If verification fails** - STOP and alert project-manager. Do not proceed.

### Working Directory Awareness

Agents MUST:
1. Verify working directory matches assigned worktree path before ANY file operation
2. Never make changes in main project directory when assigned to worktree
3. Use absolute paths when referencing files
4. Include worktree path in Jira comments for audit trail

---

## Commit Rules

All commits must follow CLAUDE.md rules:
- Conventional commit format: `type(scope): description`
- NO emoji in commits
- Include Jira reference: `Refs AI-XXX` or `Closes AI-XXX`

### FORBIDDEN in Commits (ABSOLUTE)

| Pattern | NEVER Include |
|---------|---------------|
| AI Generation | `Generated with [Claude Code]` or similar |
| Claude Attribution | `Co-Authored-By: Claude` (any variant) |
| Anthropic Email | `<noreply@anthropic.com>` or `*@anthropic.com` |
| Claude Links | `claude.ai` |
| Anthropic Links | `anthropic.com` |
| Robot Emoji | Lines starting with robot emoji |

**Use `/commit` (git-commit-helper) which validates against these patterns.**

---

## Branch Management

- Each worktree has exactly ONE branch checked out
- Do not checkout different branches within a worktree
- Use main repository to manage branch operations
- Merge/rebase operations should be done from main worktree

### Worktree Branch Protection

Agents MUST NOT:
1. Force delete any branch containing `-wt-` in the name
2. Force push to worktree branches
3. Rebase worktree branches from the main project directory
4. Checkout a different branch while inside a worktree

**If branch operation is needed**: Work from within the worktree itself, not from main project.

---

## Docker Handling

### Rule: No Containers in Worktrees

Worktrees are for **code changes only**. Docker containers run exclusively in the main worktree.

**Workflow:**
1. Make code changes in worktree
2. Commit and push changes
3. Switch to main worktree to test with Docker
4. Or: Main worktree hot-reloads mounted source if configured

**Testing in worktrees:**
- Unit tests: Run directly in worktree (`dotnet test`, `npm test`)
- Integration tests: Merge to main, test with Docker stack

---

## Jira Label State Tracking

Track worktree lifecycle via Jira labels:

| Label | Meaning | Applied When |
|-------|---------|--------------|
| `worktree-active` | Task is being worked in a worktree | Worktree created |
| `worktree-qa-pending` | Worktree work complete, awaiting QA | Development complete |
| `worktree-ready-to-merge` | QA approved, waiting for main ready | QA passes |
| `worktree-merging` | Merge in progress | Merge started |

**Label Lifecycle**:
```
worktree-active → worktree-qa-pending → worktree-ready-to-merge → worktree-merging → (removed)
```

**Useful Jira Queries**:
```
# All active worktrees
project = AI AND labels = worktree-active

# Ready to merge
project = AI AND labels = worktree-ready-to-merge

# All worktree tasks (any state)
project = AI AND labels in (worktree-active, worktree-qa-pending, worktree-ready-to-merge, worktree-merging)
```

---

## Merge Queue

**Only ONE task can merge at a time.** Use `worktree-merging` label as a lock.

```
Before Merge:
1. Query Jira: project = AI AND labels = worktree-merging AND key != ${JIRA_KEY}
2. If results exist → WAIT (another merge in progress)
3. If no results → Add "worktree-merging" label to current task, proceed

After Merge Complete:
4. Remove "worktree-merging" label
5. Next queued task can proceed
```

**Queue Priority**: First-come-first-served based on when `worktree-ready-to-merge` label was added.

---

## Conflict Resolution

When merge conflicts occur, invoke `staff-engineer-advisor` agent.

**Conflict Resolution Decision Framework:**

| Conflict Type | Resolution Strategy |
|---------------|---------------------|
| Same file, different sections | Git auto-merges (no action needed) |
| Same function/method modified | Keep worktree changes (QA-approved, newer) |
| Database migration conflicts | Renumber worktree migration to follow base |
| Shared library conflicts | Keep base, re-apply worktree if compatible |
| Configuration conflicts | Merge both (usually additive) |
| Security-related conflicts | **BLOCK** - require explicit review |

**Multi-Tenant Security Check** (mandatory after conflict resolution):
```bash
# After resolving conflicts, before committing
grep -r "FROM.*WHERE" --include="*.cs" | grep -v "company_uuid" | grep -v "tenant_id"
# If matches found → BLOCK MERGE, require explicit review
```

---

## Build Failure Handling

**If build fails after merge** → Create fix worktree, don't rollback (fix forward):

| Failed Service | Hand Off To |
|----------------|-------------|
| `auth-service`, `company-service`, `ai-engine`, `workflow-engine`, `data-ingestion`, `knowledge-base`, `psa-integration`, `script-management` | `backend-developer` |
| `admin-dashboard`, `web-portal` | `frontend-developer` |
| `migrations-runner` | `backend-developer` |
| Shared libraries (`src/shared/*`) | `staff-engineer-advisor` |

---

## Scripts Reference

**IMPORTANT**: All scripts should be executed from the main repository directory (`/development/ai-it-for-msps/`). The scripts use dynamic path resolution to locate worktrees relative to the main repo.

| Script | Purpose |
|--------|---------|
| `scripts/worktree-create.sh {key}` | Create worktree with proper naming, writes `.worktree-base-branch` file |
| `scripts/worktree-status.sh` | Show all worktrees with current state |
| `scripts/worktree-complete-merge.sh {key}` | **Preferred**: Full workflow (merge + build verify + cleanup) |
| `scripts/worktree-merge.sh {key}` | Merge worktree branch into base branch |
| `scripts/worktree-cleanup.sh {key} [--force]` | Remove worktree and branch after merge |
| `scripts/verify-merge-readiness.sh` | Pre-merge validation checks |
| `scripts/verify-build-after-merge.sh` | Post-merge build verification |

### Cleanup --force Flag

The `--force` flag skips all confirmation prompts, enabling non-interactive execution for agents:

```bash
# From main repo directory: /development/ai-it-for-msps/

# Interactive (asks for confirmation)
scripts/worktree-cleanup.sh AI-101

# Non-interactive (for agents)
scripts/worktree-cleanup.sh AI-101 --force
```

### Complete Merge Workflow (Preferred)

For the main thread (orchestrator), use the orchestration wrapper from the main repo directory:

```bash
# From main repo directory: /development/ai-it-for-msps/
scripts/worktree-complete-merge.sh AI-101
```

This runs:
1. `worktree-merge.sh` - Merge branch
2. `verify-build-after-merge.sh` - Build verification
3. `worktree-cleanup.sh --force` - Cleanup

**Note**: Project-manager does NOT execute this script. Project-manager analyzes dependencies and reports readiness; the main thread executes merges.

---

## Complete Worktree Lifecycle

```
MAIN THREAD asks PROJECT-MANAGER for task analysis
        |
        v
PROJECT-MANAGER returns task list with dependencies and agent routing
        |
        v
MAIN THREAD creates worktree --> spawns DEVELOPER agent
        |
        v
DEVELOPER --> implements --> commits --> signals QA (worktree-qa-pending label)
        |
        v
MAIN THREAD spawns QA agent
        |
        v
QA --> reviews
        |
        +-- REJECT --> returns to same developer (same worktree) for fixes
        |
        +-- ACCEPT --> adds worktree-ready-to-merge label
        |
        v
PROJECT-MANAGER verifies via Jira --> reports readiness to MAIN THREAD
        |
        v
MAIN THREAD --> merge lock --> merge --> build verify --> cleanup
        |
        v
MAIN THREAD notifies PROJECT-MANAGER --> PM updates dependency analysis
```

### Key Rules

| Scenario | Action |
|----------|--------|
| QA fails | Same worktree, same developer fixes the issues |
| Merge conflict | **Escalate immediately to staff-engineer-advisor** |
| Build fails after merge | Create new worktree for fix (fix forward, don't rollback) |
| Multiple tasks ready to merge | Queue via Jira labels, merge ONE at a time |

---

## Recovery Strategies

### Fix Forward (Preferred)

If build fails after merge:
1. Keep merge commit in place
2. Create new worktree for fix: `{jira-key}-fix-{hash}`
3. Hand off to appropriate agent
4. Agent fixes build issue
5. Merge fix worktree
6. Verify all builds pass

### Rollback (Only for Critical Failures)

Only use rollback when:
- Security vulnerability introduced
- Data corruption risk
- Multiple services completely broken

```bash
# Revert merge (preserves history, safer)
git revert -m 1 HEAD -m "revert: rollback merge due to critical failure

Refs ${JIRA_KEY}"
```
