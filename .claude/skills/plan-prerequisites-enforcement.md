---
skill-name: plan-prerequisites-enforcement
priority: -3
trigger: |
  ALWAYS ACTIVE - intercepts commands that create Jira tasks or start implementation:
  - /act command invocation
  - /create-plan-in-jira command invocation
  - /implement-jira-task command invocation (when no existing tasks)
  - Any attempt to create Jira tasks from a plan
  - Any attempt to start implementation from a plan
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - WebSearch
  - WebFetch
  - TodoWrite
  - Task
  - TaskOutput
  - mcp__atlassian__*
  - mcp__docker__*
  - mcp__postgres-local__*
forbidden-tools:
  - Edit
  - Write
  - NotebookEdit
description: |
  PLAN PREREQUISITES ENFORCEMENT - Priority -3 (highest, before verification-before-reporting)

  This skill enforces the MANDATORY planning workflow steps before Jira tasks can be
  created. It ensures that technical-plan.md, pseudo-code-plan.md, technical-spec.md,
  and critical-constraints.md are created BEFORE implementation begins.

  CORE PRINCIPLE: Plans must be documented before tasks are created.
  Skipping planning steps leads to poor implementations and rework.
---

# Plan Prerequisites Enforcement

## THE CARDINAL RULE

**Jira tasks CANNOT be created until required planning artifacts exist.**

This skill intercepts `/act` and `/create-plan-in-jira` to verify that the planning workflow steps have been completed.

---

## REQUIRED ARTIFACTS

**IMPORTANT: Artifacts should be created DURING planning, BEFORE `/act` is invoked.**

The planning workflow creates these artifacts through agent consultation (system-architect, staff-engineer-advisor). This skill validates their existence at `/act` time - it does NOT create them. If artifacts are missing, return to plan mode (shift+tab) to complete the planning workflow.

Before Jira tasks can be created, the following artifacts MUST exist in `docs/plan/{plan-id}/`:

### Always Required (for ALL plans)

| Artifact | Source Agent | Description |
|----------|--------------|-------------|
| `technical-plan.md` | system-architect | Technical approach, architecture decisions, affected services |
| `user-requirements.md` | system-architect | **VERBATIM** user input captured during planning (see TEMPLATE_user-requirements.md) |

### Required for Complex Plans (3+ tasks)

| Artifact | Source Agent | Description |
|----------|--------------|-------------|
| `pseudo-code-plan.md` | staff-engineer-advisor | Pseudo-code for implementation approach |
| `technical-spec.md` | system-architect | File changes, API changes, database changes |
| `critical-constraints.md` | system-architect | MUST DO, MUST NOT, PRESERVE constraints |

### Optional (Recommended)

| Artifact | Source Agent | Description |
|----------|--------------|-------------|
| `_state.md` | project-manager | Plan state tracking file |

---

## ENFORCEMENT LOGIC

### Step 1: Identify Plan Context

When `/act` or `/create-plan-in-jira` is invoked:

1. **Check conversation context** for plan identifier
2. **Search for plan directories:**
   ```
   Glob("docs/plan/PLAN-*")
   Glob("docs/plan/*-*")
   ```
3. **Identify the current plan** from:
   - Explicit plan ID in command
   - Most recent plan directory (by creation date)
   - Plan referenced in conversation

**Conflict Resolution:**
- If multiple plans found in `docs/plan/`, prompt user to specify: "Multiple plans found. Which plan? {list of plan IDs}"
- If no plan found, check for plan state file pattern `PLAN-*_state.md`
- If still no plan, require explicit plan ID: `/act PLAN-20260123-feature`
- Once plan is identified, reference it consistently throughout the session

### Step 2: Verify Required Artifacts

**For the identified plan directory:**

```bash
# Check for required artifacts (ALWAYS required)
ls docs/plan/{plan-id}/technical-plan.md
ls docs/plan/{plan-id}/user-requirements.md    # ALWAYS required - verbatim user input

# Check for complex plan artifacts (if 3+ tasks)
ls docs/plan/{plan-id}/pseudo-code-plan.md    # If complex plan
ls docs/plan/{plan-id}/technical-spec.md      # If complex plan
ls docs/plan/{plan-id}/critical-constraints.md # If complex plan
```

### Step 3: Count Tasks to Determine Complexity

**Simple Plan (1-2 tasks):** Only requires `technical-plan.md`
**Complex Plan (3+ tasks):** Requires all artifacts

**Task Counting Logic:**
1. Primary: Check plan state file for `| AI-XXX |` table entries
2. Fallback: Check technical-plan.md for numbered task items or "## Tasks" section
3. If uncertain (narrative description only), default to "complex" (requires all artifacts)
4. **Threshold:** 3+ tasks = complex plan requiring all artifacts

**Edge Cases:**
- Tasks split during planning: count the FINAL number before `/act`
- Subtasks don't count separately (only top-level tasks)
- If plan state shows tasks but no Jira keys yet, count table rows

### Step 4: Validate Artifact Content

After verifying files exist, use `Read` tool to verify minimum content:

**Artifact Quality Checks (in addition to existence):**

| Artifact | Minimum Content Requirement |
|----------|----------------------------|
| `technical-plan.md` | Must contain "## Tasks" or "## Implementation" section |
| `user-requirements.md` | Must contain at least 1 requirement entry (UR-1, UR-2, etc.) with verbatim user quote |
| `pseudo-code-plan.md` | Must contain at least 1 code block (``` markers) |
| `technical-spec.md` | Must contain at least 1 of: file path, API endpoint, or database table |
| `critical-constraints.md` | Must contain at least 1 constraint marker (MUST, MUST NOT, PRESERVE) |

**If content check fails:**

```markdown
## BLOCKED: Artifact Incomplete

**Plan:** {plan-id}
**Artifact:** {artifact-name}

**Expected:** {requirement}
**Found:** {actual content summary or "File is empty"}

The artifact exists but appears incomplete. Please complete the artifact before proceeding.

**To Resolve:**
1. Enter plan mode (shift+tab)
2. Request: "Complete {artifact-name} for {plan-id}"
3. Then run /{command} again
```

### Step 5: Block or Allow

**If artifacts are MISSING:**

```markdown
## Plan Prerequisites NOT Met

**Plan:** {plan-id}
**Location:** docs/plan/{plan-id}/

### Missing Required Artifacts

| Artifact | Status | How to Create |
|----------|--------|---------------|
| technical-plan.md | MISSING | Route to system-architect |
| user-requirements.md | MISSING | Capture verbatim user input during planning (see TEMPLATE_user-requirements.md) |
| pseudo-code-plan.md | MISSING | Route to staff-engineer-advisor |
| technical-spec.md | MISSING | Route to system-architect |
| critical-constraints.md | MISSING | Route to system-architect |

### BLOCKED: Cannot Proceed

**Reason:** Required planning artifacts are missing. The workflow requires:
1. system-architect creates technical-plan.md
2. Capture verbatim user requirements in user-requirements.md (ALWAYS required)
3. staff-engineer-advisor creates pseudo-code-plan.md (for 3+ tasks)
4. system-architect generates technical-spec.md and critical-constraints.md (for 3+ tasks)

**To Resolve:**
1. Enter plan mode (shift+tab)
2. Continue planning until artifacts are generated
3. Then run /{command} again

**To Override (NOT RECOMMENDED):**
Type "proceed without planning" to skip artifact verification.
This is NOT recommended as it may lead to implementation issues.

**Alternative:**
Use `/quick-plan` for simple changes that don't need full documentation.
```

**If artifacts are PRESENT:**

```markdown
## Plan Prerequisites Verified

**Plan:** {plan-id}
**Location:** docs/plan/{plan-id}/

### Required Artifacts

| Artifact | Status |
|----------|--------|
| technical-plan.md | FOUND |
| user-requirements.md | FOUND |
| pseudo-code-plan.md | FOUND |
| technical-spec.md | FOUND |
| critical-constraints.md | FOUND |

Proceeding with /{command}...
```

---

## BYPASS CONDITIONS

### Explicit User Override

If user types "proceed without planning", allow the command to proceed with a warning:

```markdown
## Override Accepted

**WARNING:** Proceeding without required planning artifacts.

This may result in:
- Incomplete implementation guidance
- Missing critical constraints
- Rework during QA

Proceeding with /{command}...
```

### Quick Plan Mode

If the plan was created via `/quick-plan`:
- Only require `technical-plan.md`
- Skip other artifact checks
- Note: `/quick-plan` creates a plan directory marker: `docs/plan/{plan-id}/.quick-plan`

### Existing Jira Tasks

If `/implement-jira-task AI-XXX` is invoked with an existing task:
- Skip artifact checks (task already has requirements in Jira)
- This command implements EXISTING tasks, not new ones

### Trivial Changes

If the plan is explicitly marked as trivial:
- Single file change
- Typo fix
- Documentation update
- Configuration change

Look for markers:
- Plan confidence notes mention "trivial"
- Single task identified
- No database/API changes

---

## INTEGRATION WITH WORKFLOW

### Complete Planning Workflow

```
STEP 1: User enters plan mode (shift+tab)
        |
STEP 2: system-architect creates technical-plan.md
        |
STEP 3: staff-engineer-advisor creates pseudo-code-plan.md (if complex)
        |
STEP 4: Agent review and confidence assessment
        |
STEP 5: system-architect generates technical-spec.md and critical-constraints.md
        |
STEP 6: User runs /act or /create-plan-in-jira
        |
        v
[THIS SKILL] Verifies artifacts exist
        |
        +-- MISSING -> BLOCK with guidance
        |
        +-- PRESENT -> Allow command to proceed
```

### How to Create Missing Artifacts

**If technical-plan.md is missing:**
```
Enter plan mode (shift+tab) and request:
"Create a technical plan for {description}"

The system-architect will analyze the request and create the plan.
```

**If pseudo-code-plan.md is missing:**
```
In plan mode, request:
"Create pseudo-code for the plan"

The staff-engineer-advisor will be invoked to create pseudo-code.
```

**If technical-spec.md or critical-constraints.md are missing:**
```
In plan mode, request:
"Generate technical specifications and constraints"

The system-architect will create both files.
```

---

## ARTIFACT TEMPLATES

### technical-plan.md Structure

```markdown
# Technical Plan: {plan-id}

## Summary
{Brief description of what this plan accomplishes}

## Architecture
{How this fits into the existing system}

## Services Affected
| Service | Changes |
|---------|---------|
| {service} | {changes} |

## Tasks
| # | Task | Agent | Estimate |
|---|------|-------|----------|
| 1 | {task} | {agent} | {size} |

## Dependencies
{Task ordering and dependencies}

## Risks
{Identified risks and mitigations}
```

### pseudo-code-plan.md Structure

```markdown
# Pseudo-Code Plan: {plan-id}

## Overview
{High-level implementation approach}

## Implementation Steps

### Step 1: {Component}
```pseudo
{Pseudo-code for this step}
```

### Step 2: {Component}
```pseudo
{Pseudo-code for this step}
```

## Data Flow
{How data flows through the system}

## Error Handling
{Error handling approach}
```

### technical-spec.md Structure

```markdown
# Technical Specification: {plan-id}

## Metadata
| Field | Value |
|-------|-------|
| Plan ID | {plan-id} |
| Created | {timestamp} |
| Contributing Agents | {list} |

## File Changes
| File | Action | Description |
|------|--------|-------------|
| {path} | ADD/MODIFY/DELETE | {description} |

## Database Changes
| Table | Action | Description |
|-------|--------|-------------|
| {table} | CREATE/ALTER/DROP | {description} |

## API Changes
| Endpoint | Method | Action | Description |
|----------|--------|--------|-------------|
| {path} | GET/POST/etc | ADD/MODIFY/DELETE | {description} |
```

### critical-constraints.md Structure

```markdown
# Critical Constraints: {plan-id}

## MUST DO (Required Actions)
| ID | Constraint | Details | Source Agent | Acknowledged |
|----|------------|---------|--------------|--------------|
| MD-1 | {constraint} | {details} | {agent} | [ ] |

## MUST NOT DO (Prohibited Actions)
| ID | Constraint | Consequence | Source Agent | Acknowledged |
|----|------------|-------------|--------------|--------------|
| MN-1 | {prohibition} | {consequence} | {agent} | [ ] |

## PRESERVE (Do Not Modify)
| ID | Resource | Type | Reason | Acknowledged |
|----|----------|------|--------|--------------|
| P-1 | {resource} | {type} | {reason} | [ ] |
```

---

## ERROR MESSAGES

### No Plan Found

```markdown
## No Plan Identified

I could not find a plan to execute. Before running /{command}:

1. Enter plan mode (shift+tab)
2. Describe what you want to build
3. Wait for planning artifacts to be created
4. Then run /{command}

**Or provide a specific plan:**
/{command} PLAN-20260123-description
```

### Plan Directory Empty

```markdown
## Plan Directory Empty

**Plan:** {plan-id}
**Location:** docs/plan/{plan-id}/

The plan directory exists but contains no planning artifacts.

This usually means planning was started but not completed.

**To Continue:**
1. Enter plan mode (shift+tab)
2. Request: "Continue planning for {plan-id}"
3. Complete the planning workflow
4. Then run /{command}
```

### Partial Artifacts

```markdown
## Partial Planning Artifacts

**Plan:** {plan-id}

Some planning steps were completed, but not all required artifacts exist.

| Artifact | Status |
|----------|--------|
| technical-plan.md | FOUND |
| user-requirements.md | MISSING |
| pseudo-code-plan.md | MISSING |
| technical-spec.md | MISSING |
| critical-constraints.md | MISSING |

**To Complete:**
1. Enter plan mode (shift+tab)
2. Request: "Complete planning artifacts for {plan-id}"
3. Then run /{command}
```

---

## PRIORITY AND ORDERING

This skill has **priority -3** (highest in the system):
1. **-3**: plan-prerequisites-enforcement (THIS SKILL)
2. **-2**: verification-before-reporting
3. **-1**: orchestrator-mode
4. **0**: plan-mode, code-change-interceptor, git-commit-interceptor

This ensures planning prerequisites are checked BEFORE any other skill processing.

---

## RELATION TO OTHER SKILLS

| Skill | Relation |
|-------|----------|
| plan-mode | Creates the artifacts this skill checks for |
| orchestrator-mode | Blocks direct code edits; this blocks premature task creation |
| verification-before-reporting | Verifies after actions; this verifies before actions |
| code-change-interceptor | Routes code changes; this gates plan execution |

---

## ENFORCEMENT SUMMARY

1. **Intercept** `/act`, `/create-plan-in-jira` commands
2. **Identify** the current plan from context
3. **Check** for required artifacts in plan directory
4. **Block** if artifacts missing, with clear guidance
5. **Allow** explicit user override ("proceed without planning")
6. **Allow** quick-plan and trivial change bypasses
7. **Proceed** once artifacts are verified
