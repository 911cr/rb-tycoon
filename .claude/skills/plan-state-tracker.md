---
skill-name: plan-state-tracker
priority: 4
trigger: |
  Activate when:
  - User runs /act or /create-plan-in-jira
  - User asks about plan status
  - User wants to resume a previous plan
  - Creating or updating plan state files
allowed-tools:
  - Read
  - Write
  - Grep
  - Glob
  - mcp__atlassian__*
forbidden-tools:
  - Edit
description: |
  Manages plan state files for tracking plan-to-implementation workflow.
  Ensures idempotent task creation by tracking Jira task keys.
  Priority 4. Works with plan-mode skill (priority 1) for confidence display.
---

# Plan State Tracker Skill

## Purpose

This skill manages plan state files that track the lifecycle of plans from creation through implementation. It enables idempotent task creation by recording which Jira tasks have already been created for a plan.

## Plan State File Location

All plan state files are stored in:
```
docs/plan/PLAN-{YYYYMMDD}-{short-description}_state.md
```

## When to Create/Update Plan State

### On `/create-plan-in-jira`

After creating Jira tasks:

1. Generate plan identifier if not exists
2. Create plan state file with:
   - Metadata (created, confidence, status="Tasks Created")
   - Jira task keys and summaries
   - Plan details for reference
3. Status: `Tasks Created`

### On `/act`

When starting implementation:

1. Check for existing plan state file
2. If exists: Read Jira task keys, skip duplicate creation
3. If not exists: Create plan state file after task creation
4. Update status: `In Progress`
5. Add execution log entries

### On Task Completion

Update plan state:

1. Mark task status in table
2. Add worktree info if applicable
3. Add execution log entry
4. Check if all tasks complete -> Status: `Complete`

## Reading Plan State

To check if a plan has existing tasks:

```python
# Pseudo-code for duplicate detection
plan_state = Read(f"docs/plan/{plan_identifier}_state.md")

if "## Jira Tasks" in plan_state:
    # Parse the table to extract task keys
    existing_keys = parse_jira_tasks_table(plan_state)
    return existing_keys
else:
    return []
```

## Writing Plan State

Use the template structure from `docs/plan/PLAN_STATE_TEMPLATE.md`:

```markdown
# Plan: PLAN-20251224-user-pagination

## Metadata

| Field | Value |
|-------|-------|
| Created | 2025-12-24T10:30:00Z |
| Updated | 2025-12-24T10:30:00Z |
| Confidence | 88% |
| Status | Tasks Created |
| Source | /create-plan-in-jira |

## Jira Tasks

| Key | Summary | Type | Agent | Status | Worktree |
|-----|---------|------|-------|--------|----------|
| AI-456 | Add pagination to users API | Task | backend-developer | To Do | - |
| AI-457 | Add pagination UI controls | Task | frontend-developer | To Do | - |

## Execution Log

- 2025-12-24T10:30:00Z: Tasks created via /create-plan-in-jira
```

## Plan Identifier Generation

When a plan needs an identifier:

1. Use current date: `YYYYMMDD`
2. Extract 2-4 keywords from plan summary
3. Lowercase, hyphen-separated
4. Format: `PLAN-{date}-{keywords}`

Examples:
- `PLAN-20251224-user-pagination`
- `PLAN-20251224-auth-refresh-token`
- `PLAN-20251224-dashboard-widget`

## Duplicate Detection Flow

```
User runs /act or /create-plan-in-jira
    |
    v
Generate/get plan identifier
    |
    v
Check: docs/plan/{identifier}_state.md exists?
    |
    +-- YES --> Read Jira task keys from file
    |               |
    |               v
    |           Return existing keys (skip creation)
    |
    +-- NO --> Search Jira for similar tasks
                   |
                   v
               If found: Prompt user for confirmation
               If not: Proceed with creation
```

## Status Values

| Status | Meaning |
|--------|---------|
| Planning | Plan in progress, no tasks created |
| Tasks Created | Jira tasks exist, not yet in sprint |
| In Progress | Tasks in sprint, agents working |
| Complete | All tasks done, plan finished |

## Execution Log Format

Each entry should include:
- ISO timestamp
- Action taken
- Relevant details (task key, agent, status)

```markdown
## Execution Log

- 2025-12-24T10:30:00Z: Plan created via plan mode (88% confidence)
- 2025-12-24T10:35:00Z: Tasks created via /create-plan-in-jira
- 2025-12-24T11:00:00Z: Implementation started via /act
- 2025-12-24T11:05:00Z: Worktree created for AI-456 (AI-456-a3f2)
- 2025-12-24T11:05:00Z: Worktree created for AI-457 (AI-457-b7c9)
- 2025-12-24T11:30:00Z: AI-456 completed by backend-developer
- 2025-12-24T11:45:00Z: AI-457 completed by frontend-developer
- 2025-12-24T12:00:00Z: QA passed for AI-456
- 2025-12-24T12:15:00Z: QA passed for AI-457
- 2025-12-24T12:30:00Z: PR created (github.com/...)
- 2025-12-24T12:30:00Z: Plan complete
```

## Finding Recent Plans

To find plans created recently:

```
Glob("docs/plan/PLAN-*.md")
```

Then filter by date in filename or read metadata to find most recent.

## Resuming a Plan

If user wants to resume a previous plan:

1. Search for plan state files matching keywords
2. Display matching plans with status
3. User selects plan
4. Read plan state to get:
   - Existing Jira task keys
   - Current status
   - What's complete vs pending
5. Continue from where left off

## Integration with Commands

| Command | Plan State Action |
|---------|-------------------|
| `/create-plan-in-jira` | Create state file with task keys |
| `/act` | Check for existing state, update on progress |
| `/act status` | Read state file, display current status |
| `/act continue` | Read state file, resume execution |
