---
description: Create Jira tasks from the current plan WITHOUT starting implementation - use /act to implement
---

# /create-plan-in-jira Command

Create Jira tasks from the current plan without starting implementation. This allows you to review tasks in Jira before committing to implementation.

## Use Cases

- **Review before implementation**: Create tasks, review in Jira, then run `/act` to implement
- **Team visibility**: Let team members see planned work before execution
- **Sprint planning**: Create tasks during planning, implement in a future sprint
- **Approval workflow**: Create tasks, get stakeholder approval, then `/act`

## MANDATORY: Phase 0 - Plan Artifact Verification (HARD BLOCKER)

**This phase runs FIRST, BEFORE any other phase. It is enforced by the `plan-prerequisites-enforcement` skill (priority -3).**

Before creating Jira tasks, verify required planning artifacts exist. This ensures tasks are created with proper technical context.

### Step 0.1: Identify the Current Plan

```bash
# Search for plan directories
Glob("docs/plan/PLAN-*")
Glob("docs/plan/*-*-*")
```

If no plan is identified:
```markdown
## No Plan Found

Cannot execute `/create-plan-in-jira` without a plan.

**To Create a Plan:**
1. Enter plan mode (shift+tab)
2. Describe what you want to build
3. Wait for system-architect to create technical-plan.md
4. For complex plans, wait for additional artifacts
5. Then run `/create-plan-in-jira`
```

### Step 0.2: Verify Required Artifacts

**Plan Directory:** `docs/plan/{plan-id}/`

**Check for artifacts:**

| Artifact | Required For | Source Agent | BLOCKER? |
|----------|--------------|--------------|----------|
| `technical-plan.md` | ALL plans | system-architect | YES |
| `user-requirements.md` | ALL plans (if user provided input) | system-architect | **YES - HARD BLOCKER** |
| `pseudo-code-plan.md` | 3+ tasks | staff-engineer-advisor | YES |
| `technical-spec.md` | 3+ tasks | system-architect | YES |
| `critical-constraints.md` | 3+ tasks | system-architect | YES |

**CRITICAL**: If user provided ANY specifications during planning (routes, column names, behaviors, etc.), `user-requirements.md` is **MANDATORY AND BLOCKING**. Without it, implementation agents will not know the user's exact specifications, and QA will have nothing to verify against.

**User requirements are WORD OF GOD.** If this file is missing when user provided specifications, task creation is BLOCKED.

### Step 0.3: Report Verification Results

**If artifacts are MISSING:**

```markdown
## Plan Artifact Verification: FAILED

**Plan:** {plan-id}

### Missing Required Artifacts

| Artifact | Status | Description |
|----------|--------|-------------|
| technical-plan.md | MISSING | Technical approach from system-architect |
| pseudo-code-plan.md | MISSING | Implementation guidance from staff-engineer-advisor |

### BLOCKED: Cannot Create Jira Tasks

Creating Jira tasks without proper planning documentation results in:
- Tasks without technical context
- Developers missing critical constraints
- Increased rework and QA failures

**To Resolve:**
1. Return to plan mode (shift+tab)
2. Request: "Complete planning artifacts"
3. Wait for artifacts to be created
4. Then run `/create-plan-in-jira`

**To Override:**
Type "proceed without planning" to create tasks anyway (not recommended).

**Alternative:**
Use `/quick-plan {description}` for simple changes.
```

**If artifacts EXIST:**

```markdown
## Plan Artifact Verification: PASSED

| Artifact | Status |
|----------|--------|
| technical-plan.md | FOUND |
| pseudo-code-plan.md | FOUND |

Proceeding with Jira task creation...
```

## MANDATORY: Confidence Display

**Before executing `/create-plan-in-jira`, you MUST display the current plan confidence prominently:**

```markdown
## Pre-Task Creation Confidence Check

**Plan Confidence: XX%** [STATUS]

| Status | Meaning |
|--------|---------|
| [HIGH CONFIDENCE] 90-100% | Excellent - tasks will be well-defined |
| [GOOD CONFIDENCE] 80-89% | Good - tasks ready for creation |
| [MODERATE CONFIDENCE] 60-79% | Acceptable - tasks may need Jira refinement |
| [LOW CONFIDENCE] <60% | Warning - consider more planning first |
```

### Confidence Gate Enforcement

**If confidence < 60%:**
```markdown
## Confidence Below Threshold

**Current Confidence: XX%** [LOW CONFIDENCE]

The plan confidence is below the 60% threshold for task creation.

**Options:**
1. Continue planning to address gaps and increase confidence
2. Override and create tasks anyway (type "create anyway" to confirm)

What would you like to do?
```

**If confidence >= 60%:**
```markdown
## Confidence Check Passed

**Plan Confidence: XX%** [STATUS]

Proceeding with Jira task creation...
```

## Workflow

### Phase 1: Plan Validation

Before creating Jira tasks:
1. Verify a plan exists (either in conversation context or plan state file)
2. **Display the confidence prominently** (see above)
3. Check plan confidence is at least 60% (lower threshold than `/act`)
4. Extract task list from plan

If no clear plan exists:
```
Error: No plan found. Please create a plan first using plan mode (shift+tab)
before running /create-plan-in-jira.
```

### Phase 2: Duplicate Detection

Search for existing tasks that might match this plan:

```
jira_search_jql(
  jql="project = AI AND summary ~ '{plan keywords}' AND created >= -14d",
  fields=["key", "summary", "status", "created"]
)
```

If potential duplicates found:
```
## Potential Duplicate Tasks Found

| Key | Summary | Status | Created |
|-----|---------|--------|---------|
| AI-450 | Add pagination to users API | To Do | 2025-12-22 |
| AI-451 | Pagination UI controls | To Do | 2025-12-22 |

These tasks may already cover your plan. Options:
1. **Use existing tasks** - Run `/act` to implement these existing tasks
2. **Create new tasks** - Reply "create new" to proceed with new task creation
3. **Cancel** - Reply "cancel" to abort
```

### Phase 3: Get Plan Identifier

Generate or use existing plan identifier:
```
PLAN-{YYYYMMDD}-{short-description}
```

Example: `PLAN-20251224-user-pagination`

### Phase 3b: Create Plan Documentation Directory

**CRITICAL**: Before creating Jira tasks, generate technical documentation to preserve context.

1. **Create plan directory:**
   ```bash
   mkdir -p docs/plan/{plan-identifier}
   ```

2. **Generate technical-spec.md:**
   Use template from `docs/plan/TEMPLATE_technical-spec.md` and populate:
   - Extract all file modifications from the plan
   - Document database changes (tables to create, modify, delete, PRESERVE)
   - Document API changes (endpoints to add, modify, remove)
   - Include code examples where provided
   - Copy advisory agent recommendations with priorities
   - List all contributing agents

   ```markdown
   # Technical Specification: {plan-identifier}

   ## Metadata
   | Field | Value |
   |-------|-------|
   | Plan ID | {plan-identifier} |
   | Created | {ISO timestamp} |
   | Contributing Agents | {list agents consulted during planning} |
   ...
   ```

3. **Generate critical-constraints.md:**
   Use template from `docs/plan/TEMPLATE_critical-constraints.md` and extract:
   - All "MUST" requirements from advisory agents
   - All "MUST NOT" / "DO NOT" prohibitions
   - All resources that must be preserved (tables, files, APIs)
   - Map each constraint to the source advisory agent

   ```markdown
   # Critical Constraints: {plan-identifier}

   ## MUST DO (Required Actions)
   | ID | Constraint | Details | Source Agent | Acknowledged |
   |----|------------|---------|--------------|--------------|
   | MD-1 | {constraint} | {details} | {advisor} | [ ] |
   ...

   ## MUST NOT DO (Prohibited Actions)
   | ID | Constraint | Consequence | Source Agent | Acknowledged |
   |----|------------|-------------|--------------|--------------|
   | MN-1 | {prohibition} | {consequence} | {advisor} | [ ] |
   ...

   ## PRESERVE (Do Not Modify)
   | ID | Resource | Type | Reason | Acknowledged |
   |----|----------|------|--------|--------------|
   | P-1 | {resource} | {type} | {reason} | [ ] |
   ...
   ```

4. **Track contributing agents:**
   Extract from conversation which advisory agents were consulted and what they contributed.

### Phase 4: Create Jira Tasks

For each task in the plan:

```
jira_create_issue(
  projectKey="AI",
  issueTypeName="{Task|Story|Subtask}",
  summary="{task summary}",
  description="============================================================
STOP! READ USER REQUIREMENTS FIRST (WORD OF GOD)
============================================================

**BEFORE ANY CODE:** You MUST read and acknowledge user requirements.

**Document:** docs/plan/{plan-identifier}/user-requirements.md

**Requirements for THIS TASK:**

| Req ID | User Said (VERBATIM - first 80 chars) | Category |
|--------|---------------------------------------|----------|
| UR-X | \"{EXACT user quote}...\" | API/DB/UI |
| UR-Y | \"{EXACT user quote}...\" | API/DB/UI |

**CRITICAL:** These are the user's EXACT words. Implement EXACTLY as specified.
If you implement differently, QA will FAIL the task.

============================================================

## Summary
{description}

## Acceptance Criteria (derived from user requirements)
- [ ] UR-X: {criterion derived from user verbatim quote}
- [ ] UR-Y: {criterion derived from user verbatim quote}
- [ ] {additional criteria}

## Technical Specification

**REQUIRED READING (after user requirements):**
- Full spec: docs/plan/{plan-identifier}/technical-spec.md
- Constraints: docs/plan/{plan-identifier}/critical-constraints.md

### Key Constraints (Summary)
- MUST: {top 2-3 constraints}
- MUST NOT: {top 2-3 prohibitions}

### Files to Modify
{Relevant files for this task}

## Agent Routing
- **Implement**: {agent}
- **QA**: {qa_agent}
- **Review**: senior-code-reviewer

## Plan Reference
{plan_identifier}

---
*Created via /create-plan-in-jira*"
)
```

**CRITICAL**: When creating task descriptions:
1. Extract user requirements (UR-X) assigned to this task from `user-requirements.md`
2. Include the verbatim user quote (first 100 chars with "...")
3. Derive acceptance criteria from the user-requirements.md acceptance criteria
4. Link to the full user-requirements.md document

**Note**: Does NOT move to sprint or assign to user (that's `/act`'s job)

### Phase 5: Store Plan State

After creating tasks, store the task keys for `/act` to use:

Create or update plan state file at `docs/plan/{plan-identifier}_state.md`:

```markdown
# Plan: {plan-identifier}

## Status: Tasks Created (Pending Implementation)

**Created**: {timestamp}
**Plan Confidence**: {confidence}%

## Jira Tasks

| Key | Summary | Type | Agent | Status |
|-----|---------|------|-------|--------|
| AI-456 | Add pagination to users API | Task | backend-developer | To Do |
| AI-457 | Add pagination UI controls | Task | frontend-developer | To Do |

## Next Steps

Run `/act` to:
1. Move tasks to active sprint
2. Assign to you
3. Start parallel agent implementation

Or review/modify tasks in Jira first:
- https://911it.atlassian.net/browse/AI-456
- https://911it.atlassian.net/browse/AI-457
```

### Phase 6: Return Task Keys

Display created tasks:

```
## Jira Tasks Created

| Key | Summary | Type | URL |
|-----|---------|------|-----|
| AI-456 | Add pagination to users API | Task | [View](https://911it.atlassian.net/browse/AI-456) |
| AI-457 | Add pagination UI controls | Task | [View](https://911it.atlassian.net/browse/AI-457) |

**Plan State Saved**: docs/plan/PLAN-20251224-user-pagination_state.md

### Next Steps

**Option 1: Implement Now**
```
/act
```
This will move tasks to the active sprint, assign to you, and start implementation.

**Option 2: Review First**
1. Review tasks in Jira: https://911it.atlassian.net/browse/AI-456
2. Make any modifications
3. Then run `/act` when ready
```

## Idempotency Guarantee

Running `/create-plan-in-jira` followed by `/act`:
1. `/create-plan-in-jira` creates tasks, stores keys in plan state
2. `/act` reads plan state, finds existing tasks
3. `/act` uses existing tasks instead of creating duplicates
4. `/act` proceeds with sprint assignment and implementation

Running `/create-plan-in-jira` multiple times:
1. Second run detects existing tasks via JQL search
2. Prompts user: "Use existing or create new?"
3. If "use existing": returns existing keys, no duplicates created
4. If "create new": proceeds with new task creation

## Example Usage

```
User: (in plan mode, plans a feature)
User: /create-plan-in-jira

Claude: Creating Jira tasks from the current plan...

Checking for duplicates...
No matching tasks found.

Generating plan identifier: PLAN-20251224-user-pagination

Creating tasks...
1. Created AI-456: Add pagination to users API
2. Created AI-457: Add pagination UI controls

## Jira Tasks Created

| Key | Summary | Type | URL |
|-----|---------|------|-----|
| AI-456 | Add pagination to users API | Task | [View](https://911it.atlassian.net/browse/AI-456) |
| AI-457 | Add pagination UI controls | Task | [View](https://911it.atlassian.net/browse/AI-457) |

**Plan State Saved**: docs/plan/PLAN-20251224-user-pagination_state.md

Tasks are now in Jira but NOT in the active sprint.
Run `/act` when ready to start implementation.
```

## Differences from /act

| Aspect | /create-plan-in-jira | /act |
|--------|----------------------|------|
| Creates Jira tasks | Yes | Yes (if not already created) |
| Moves to sprint | No | Yes |
| Assigns to user | No | Yes |
| Starts implementation | No | Yes |
| Creates worktrees | No | Yes |
| Launches agents | No | Yes |
| Minimum confidence | 60% | 80% |

## Error Handling

### No Plan Found
```
Error: No plan detected in conversation context.

To use this command:
1. Enter plan mode (shift+tab)
2. Describe what you want to build
3. Refine the plan until confidence >= 60%
4. Run /create-plan-in-jira
```

### Low Confidence
```
Warning: Plan confidence is {X}%, below the 60% threshold.

Continue anyway? (The plan may need refinement before implementation)
- Reply "yes" to create tasks anyway
- Reply "no" to return to planning
```

### Jira API Error
```
Error creating Jira task: {error message}

Troubleshooting:
1. Check Atlassian MCP connection: verify authentication
2. Check project access: ensure AI project is accessible
3. Check issue type: verify Task/Story types exist

Tasks created before error:
- AI-456: Add pagination to users API

Retry with: /create-plan-in-jira continue
```

## Plan State File Format

Location: `docs/plan/{plan-identifier}_state.md`

```markdown
# Plan: {plan-identifier}

## Metadata

| Field | Value |
|-------|-------|
| Created | {ISO timestamp} |
| Confidence | {X}% |
| Status | Tasks Created |
| Source | /create-plan-in-jira |

## Summary

{Brief plan description}

## Technical Documentation

| Document | Path | Status |
|----------|------|--------|
| **User Requirements** | `docs/plan/{plan-identifier}/user-requirements.md` | Created (WORD OF GOD) |
| Technical Spec | `docs/plan/{plan-identifier}/technical-spec.md` | Created |
| Critical Constraints | `docs/plan/{plan-identifier}/critical-constraints.md` | Created |

## Contributing Agents

| Agent | Contribution | Date |
|-------|--------------|------|
| {advisor-agent} | {what they contributed - e.g., "Database schema design recommendations"} | {timestamp} |
| {advisor-agent} | {what they contributed - e.g., "Security constraints for authentication"} | {timestamp} |
| {advisor-agent} | {what they contributed - e.g., "API design patterns"} | {timestamp} |

## Jira Tasks

| Key | Summary | Type | Agent | Status |
|-----|---------|------|-------|--------|
| AI-XXX | Task 1 | Task | backend-developer | To Do |
| AI-YYY | Task 2 | Task | frontend-developer | To Do |

## Plan Details

{Full plan content for reference}

## Execution Log

- {timestamp}: Tasks created via /create-plan-in-jira
- {timestamp}: Technical spec generated at docs/plan/{plan-identifier}/technical-spec.md
- {timestamp}: Critical constraints generated at docs/plan/{plan-identifier}/critical-constraints.md
- {timestamp}: (will be updated by /act)
```

## Remember

- **Create-only**: This command creates tasks but does NOT implement
- **Idempotent**: Safe to run after `/create-plan-in-jira` - uses existing tasks
- **Plan state**: Stores task keys for `/act` to use
- **Lower threshold**: Requires only 60% confidence (vs 80% for `/act`)
- **Team visibility**: Tasks visible in Jira for team review
