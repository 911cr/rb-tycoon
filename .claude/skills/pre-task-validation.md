---
skill-name: pre-task-validation
priority: -1
trigger: |
  ALWAYS ACTIVE when delegating to implementation agents.

  This skill intercepts Task tool calls to implementation agents and BLOCKS dispatch
  until sprint validation passes.

  Triggers on Task calls with agent types:
  - backend-developer
  - frontend-developer
  - code-refactorer
  - platform-windows-developer
  - platform-linux-developer
  - platform-macos-developer
  - technical-writer
  - ui-design-ux
  - ui-design-lead
description: |
  PRE-TASK VALIDATION ENFORCEMENT - Priority -1 (highest possible with orchestrator-mode)

  This skill enforces that ALL implementation tasks are properly validated against Jira
  BEFORE any agent is dispatched. Validation ensures:
  1. The task exists in Jira
  2. The task is assigned to the current user
  3. The task is in the active sprint

  Validation failure BLOCKS agent dispatch.
---

# Pre-Task Validation Enforcement

## CRITICAL: No Implementation Without Validation

**Every Task tool call to an implementation agent MUST pass validation first.**

This skill works alongside `orchestrator-mode` to ensure that work is not only delegated to the correct agent, but also properly tracked in Jira with correct assignment and sprint placement.

## Target Agents

This validation applies to ALL of these agent types:

| Agent | Type | Validation Required |
|-------|------|---------------------|
| `backend-developer` | Implementation | YES |
| `frontend-developer` | Implementation | YES |
| `code-refactorer` | Implementation | YES |
| `platform-windows-developer` | Platform | YES |
| `platform-linux-developer` | Platform | YES |
| `platform-macos-developer` | Platform | YES |
| `technical-writer` | Documentation | YES |
| `ui-design-ux` | Design | YES |
| `ui-design-lead` | Design | YES |

## Validation Protocol

### Step 1: Extract Jira Key from Task Prompt

When preparing a Task tool call, scan the prompt for Jira references:

**Pattern**: `AI-\d+` (e.g., AI-123, AI-456)

```
Example prompt scan:
"Implement AI-456: Add pagination..."
-> Extracted key: AI-456
```

**If NO Jira key found:**
```
VALIDATION BLOCKED: No Jira key found in task prompt.

Tasks must reference a Jira issue (e.g., AI-XXX) to ensure proper tracking.

To proceed:
1. Create a Jira task first via jira_create_issue()
2. Include the Jira key in the agent prompt
```

### Step 2: Get Current User Account ID

```
jira_get_user_info()
```

Extract `accountId` from response for assignment verification.

### Step 3: Get Active Sprint

```
jira_get_sprints(boardId=1, state="active")
```

Extract the active sprint `id` for sprint membership verification.

**Sprint custom field**: `customfield_10020` (array of sprint IDs)

### Step 4: Get Task Details

```
jira_get_issue(
  issueKey="AI-XXX",
  fields=["status", "assignee", "customfield_10020", "summary"]
)
```

### Step 5: Validation Checks

| Check | Pass Condition | Failure Message |
|-------|----------------|-----------------|
| Task Exists | API returns 200 | "Task AI-XXX not found in Jira" |
| Task Assigned | `assignee.accountId == currentUser.accountId` | "Task AI-XXX not assigned to you" |
| In Active Sprint | Active sprint ID in `customfield_10020` array | "Task AI-XXX not in active sprint" |

## Validation Results

### VALIDATION PASSED

```markdown
## Pre-Task Validation: PASSED

| Check | Result | Details |
|-------|--------|---------|
| Task Exists | PASS | AI-456: Add pagination to users API |
| Assignee | PASS | Assigned to {current_user} |
| Sprint | PASS | In Sprint 15 (active) |

Proceeding with agent dispatch...
```

Then proceed with the Task tool call.

### VALIDATION FAILED (Blocking)

```markdown
## Pre-Task Validation: FAILED

| Check | Result | Details |
|-------|--------|---------|
| Task Exists | {PASS/FAIL} | {details} |
| Assignee | {PASS/FAIL} | {details} |
| Sprint | {PASS/FAIL} | {details} |

**BLOCKED**: Cannot dispatch agent until validation passes.

**Auto-Fix Available**: {yes/no}
```

## Auto-Fix Capability

When validation fails, the orchestrator (or project-manager) may auto-fix certain issues:

### Auto-Fixable Issues

| Issue | Auto-Fix Action | Permission Required |
|-------|-----------------|---------------------|
| Not assigned | `jira_edit_issue(issueKey, fields={"assignee": {"accountId": "{id}"}})` | project-manager or orchestrator |
| Not in sprint | `jira_move_issues_to_sprint(sprintId, issueKeys=[...])` | project-manager or orchestrator |

### Non-Auto-Fixable Issues

| Issue | Resolution |
|-------|------------|
| Task doesn't exist | User must create task first |
| Task in wrong project | User must create correct task |
| Task already assigned to someone else | Requires manual reassignment |

### Auto-Fix Flow

```markdown
## Pre-Task Validation: FAILED (Auto-Fix Available)

| Check | Result | Fix |
|-------|--------|-----|
| Task Exists | PASS | - |
| Assignee | FAIL | Will assign to current user |
| Sprint | FAIL | Will move to Sprint 15 |

Applying auto-fixes...

1. Assigning AI-456 to current user...
   jira_edit_issue(issueKey="AI-456", fields={"assignee": {"accountId": "..."}})
   Result: SUCCESS

2. Moving AI-456 to active sprint...
   jira_move_issues_to_sprint(sprintId=101, issueKeys=["AI-456"])
   Result: SUCCESS

## Re-Validation: PASSED

Proceeding with agent dispatch...
```

## Integration with /act and /implement-jira-task

Both commands call this validation automatically:

### /act Flow

```
/act
  |
  +-> Parse plan for Jira keys
  |
  +-> For EACH task to implement:
  |     |
  |     +-> PRE-TASK VALIDATION (this skill)
  |     |     |
  |     |     +-> Check task exists
  |     |     +-> Check assignee
  |     |     +-> Check sprint membership
  |     |     |
  |     |     +-> FAIL? -> Block or Auto-fix
  |     |     +-> PASS? -> Continue
  |     |
  |     +-> Create worktree
  |     +-> Launch agent
```

### /implement-jira-task Flow

```
/implement-jira-task AI-456
  |
  +-> PRE-TASK VALIDATION (this skill)
  |     |
  |     +-> Check task exists
  |     +-> Check assignee
  |     +-> Check sprint membership
  |     |
  |     +-> FAIL? -> Block or Auto-fix
  |     +-> PASS? -> Continue
  |
  +-> Create worktree
  +-> Launch agent
```

## Self-Check Before Dispatching

Before ANY `Task(agent="{implementation_agent}")` call, verify:

```
1. Is this an implementation agent? -> If yes, validate
2. Does the prompt contain a Jira key (AI-XXX)? -> If no, BLOCK
3. Has validation been run for this task? -> If no, run validation
4. Did validation pass? -> If no, BLOCK or auto-fix
5. Proceed with Task call
```

## Error Recovery

### Validation API Failure

If Jira API calls fail during validation:

```markdown
## Pre-Task Validation: ERROR

Could not complete validation due to API error:
- jira_get_issue returned: {error_message}

**Options:**
1. Retry validation
2. Proceed without validation (NOT RECOMMENDED - violates sprint discipline)
3. Cancel task dispatch
```

### Partial Validation

If some checks pass but API fails on others:

```markdown
## Pre-Task Validation: PARTIAL

| Check | Result |
|-------|--------|
| Task Exists | PASS |
| Assignee | ERROR: API timeout |
| Sprint | NOT CHECKED |

Cannot proceed with partial validation. Please retry.
```

## Why This Matters

1. **Sprint Discipline**: Ensures all work is tracked in the current sprint
2. **Assignment Accountability**: Prevents work on unassigned tasks
3. **Jira Accuracy**: Keeps Jira synchronized with actual work
4. **Visibility**: Team can see what's being worked on in real-time
5. **Velocity Metrics**: Accurate sprint data for planning
6. **Audit Trail**: Clear ownership of all changes

## Configuration Reference

This skill uses values from `.claude/config/jira-config.json`:

| Setting | Location | Value |
|---------|----------|-------|
| Board ID | `defaultBoard.id` | 1 |
| Sprint Field | `customFields.sprint` | customfield_10020 |
| Implementation Agents | `agentStatusTransitions.implementationAgents.agents` | [list] |

## Integration with Other Skills

| Skill | Priority | Relationship |
|-------|----------|--------------|
| verification-before-reporting | -2 | Verification after task dispatch |
| pre-task-validation | -1 | Validation BEFORE task dispatch |
| orchestrator-mode | -1 | Tool restrictions (co-priority) |

Both `pre-task-validation` and `orchestrator-mode` have priority -1, ensuring both are always active.
