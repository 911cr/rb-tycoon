---
description: Implement one or more Jira tasks directly - reads requirements from Jira, detects dependencies, and starts parallel agent execution
---

# /implement-jira-task Command

Implement one or more Jira tasks by reading their requirements directly from Jira, detecting dependencies, and starting parallel agent execution via worktrees.

## Usage

```bash
/implement-jira-task AI-21              # Single task
/implement-jira-task AI-21 AI-22        # Multiple tasks
/implement-jira-task AI-100             # Epic (expands to child tasks)
```

## Workflow

### Phase 1: Receive and Parse Jira Keys

Parse the provided Jira key(s) from the command arguments.

### Phase 1.5: MANDATORY Pre-Implementation Validation (HARD BLOCKER)

**CRITICAL: This validation MUST pass BEFORE any implementation begins.**

For EVERY task key provided, validate against Jira to ensure sprint discipline and proper tracking.

**Step 1: Get Current User and Active Sprint**
```
# Get authenticated user (once)
jira_get_user_info()
-> Extract accountId: "{user_account_id}"

# Get active sprint (once)
jira_get_sprints(boardId=1, state="active")
-> Extract sprint id: {active_sprint_id}
```

**Step 2: Validate Each Task**
```
jira_get_issue(
  issueKey="AI-XXX",
  fields=["status", "assignee", "customfield_10020", "summary"]
)
```

**Step 3: Check Validation Criteria**

| Check | Pass Condition | Failure Action |
|-------|----------------|----------------|
| Task Exists | API returns 200 (not 404) | **ABORT** - Task must exist |
| Assigned to Me | `assignee.accountId == currentUser.accountId` | **AUTO-FIX** or ABORT |
| In Active Sprint | Active sprint ID in `customfield_10020` array | **AUTO-FIX** or ABORT |

**Step 4: Apply Auto-Fixes (if needed)**

| Issue | Auto-Fix Command |
|-------|------------------|
| Not assigned to me | `jira_edit_issue(issueKey="AI-XXX", fields={"assignee": {"accountId": "{user_id}"}})` |
| Not in active sprint | `jira_move_issues_to_sprint(sprintId={id}, issueKeys=["AI-XXX"])` |

**Step 5: Report Validation Results**

```markdown
## Pre-Implementation Validation Results

| Task | Exists | Assigned | In Sprint | Status |
|------|--------|----------|-----------|--------|
| AI-456 | PASS | PASS | PASS | READY |
| AI-457 | PASS | FIXED | FIXED | READY |
| AI-458 | FAIL | - | - | BLOCKED |

**Summary:**
- 2 tasks ready for implementation
- 1 task blocked (does not exist)
```

**ABORT Conditions (Cannot Proceed):**
- Task does not exist in Jira (404 error)
- Task is assigned to someone else (not just unassigned)
- Jira API errors prevent validation
- User explicitly cancels auto-fix

**If validation fails:**
```markdown
## Pre-Implementation Validation: FAILED

Cannot proceed with implementation. Issues found:

| Task | Issue | Resolution Required |
|------|-------|---------------------|
| AI-458 | Not found | Create task in Jira first |
| AI-459 | Assigned to Jane Doe | Manual reassignment needed |

**WORKFLOW ABORTED**

Fix the issues above and run `/implement-jira-task` again.
```

**NEVER skip this validation. NEVER start implementation without all tasks passing.**

---

### Phase 2: Expand Epics to Child Tasks

For each Jira key, check if it's an Epic:

```
jira_get_issue(issueKey="AI-XXX", fields=["issuetype", "subtasks"])
```

If `issuetype.name == "Epic"`:
1. Search for child issues:
   ```
   jira_search_jql(
     jql="'Epic Link' = AI-XXX OR parent = AI-XXX",
     fields=["key", "summary", "issuetype", "status"]
   )
   ```
2. Replace the Epic key with all child task keys
3. Inform user: "AI-100 is an Epic with 5 child tasks. Expanding to: AI-101, AI-102, AI-103, AI-104, AI-105"

### Phase 3: Read Requirements from Jira

For each task, read the full description and acceptance criteria:

```
jira_get_issue(
  issueKey="AI-XXX",
  fields=["summary", "description", "issuetype", "status", "issuelinks", "labels", "customfield_*"]
)
```

Extract:
- **Summary**: Task title
- **Description**: Full requirements (markdown)
- **Acceptance Criteria**: Checkbox items from description
- **Agent Routing**: Look for "Agent Routing" section or infer from file patterns
- **Issue Links**: Dependencies (blocks/is-blocked-by)

### Phase 4: Detect Dependencies

Check for Jira issue links:

```
issuelinks: [
  { type: "Blocks", inwardIssue: { key: "AI-20" } },      // AI-20 blocks this task
  { type: "Blocks", outwardIssue: { key: "AI-22" } }      // This task blocks AI-22
]
```

**If dependencies found:**

```
## Dependency Warning

The following tasks have dependencies:

| Task | Blocked By | Blocks |
|------|------------|--------|
| AI-21 | AI-20 | AI-22 |

**Options:**
1. **Proceed anyway** - Implement in parallel (may need rework)
2. **Sequential order** - Implement in dependency order (slower)
3. **Skip blocked** - Only implement unblocked tasks
4. **Cancel** - Review dependencies first

How would you like to proceed?
```

Wait for user response before continuing.

### Phase 5: Assign to User and Move to Sprint

Get user context and assign tasks:

```
# Get authenticated user
jira_get_user_info()

# Get active sprint
jira_get_sprints(boardId=1, state="active")

# For each task
jira_move_issues_to_sprint(sprintId={id}, issueKeys=["AI-XXX"])
jira_edit_issue(issueKey="AI-XXX", fields={"assignee": {"accountId": "{id}"}})
```

### Phase 6: Determine Agent Routing

For each task, determine the appropriate agent:

1. **From Jira description**: Look for "Agent Routing" section
   ```
   ## Agent Routing
   - Implement: backend-developer
   - Consult: database-advisor
   ```

2. **From file patterns in description**: Infer from mentioned files
   | Pattern | Agent |
   |---------|-------|
   | `*.cs`, `Controllers/*`, `Services/*` | backend-developer |
   | `*.tsx`, `*.ts`, `components/*` | frontend-developer |
   | `*.md` (in docs/) | technical-writer |

3. **From task labels**: Check Jira labels
   | Label | Agent |
   |-------|-------|
   | `backend` | backend-developer |
   | `frontend` | frontend-developer |
   | `full-stack` | backend-developer (primary), frontend-developer (secondary) |

### Phase 7: Start Parallel Execution via Worktrees

For independent tasks (max 5 concurrent):

1. **Create worktrees:**
   ```bash
   /development/ai-it-for-msps/scripts/worktree-create.sh AI-XXX
   ```

2. **Add Jira labels:**
   ```
   jira_edit_issue(issueKey="AI-XXX", fields={"labels": ["worktree-active"]})
   ```

3. **Transition to In Progress:**
   ```
   jira_transition_issue(issueKey="AI-XXX", transitionId="21")
   ```

4. **Launch background agents:**
   ```
   Task(
     description: "Implement AI-XXX: {summary}",
     prompt: "
       WORKTREE TASK ASSIGNMENT
       ========================
       Jira Task:      AI-XXX
       Worktree Path:  {worktree_path}
       Branch:         {branch_name}
       Base Branch:    {base_branch}

       CRITICAL: All file operations MUST be in the worktree path above.

       ============================================================
       TECHNICAL SPECIFICATION CHECK (HARD BLOCKER)
       ============================================================
       Before implementing, check if a technical specification exists:

       1. Check for plan reference in Jira description
          Look for: 'docs/plan/{plan-id}/technical-spec.md'

       2. If technical spec exists, you MUST:
          a. Read FULL technical specification
          b. Read critical constraints file
          c. Post acknowledgment to Jira BEFORE implementing:
             'CONSTRAINT ACKNOWLEDGMENT:
             - MUST DO [1]: {constraint} - UNDERSTOOD
             - MUST NOT [1]: {constraint} - UNDERSTOOD
             - PRESERVE [1]: {resource} - UNDERSTOOD'

       3. If NO technical spec referenced:
          - Proceed with implementation using Jira requirements
          - Document any technical decisions in Jira comments

       4. After implementation (if spec existed), post verification:
          'CONSTRAINT VERIFICATION:
          - MUST DO [1]: COMPLETED
          - MUST NOT [1]: VERIFIED
          - PRESERVE [1]: INTACT'

       IMPLEMENTATION IS BLOCKED until acknowledgment (if spec exists).
       ============================================================

       ============================================================
       TEST-DRIVEN DEVELOPMENT (TDD) REQUIREMENTS
       ============================================================

       TDD is MANDATORY for critical paths. Follow Red-Green-Refactor:

       **TDD REQUIRED Categories (MUST write test FIRST):**
       | Category | Example Files |
       |----------|---------------|
       | Security/Auth | JWT validation, role checks |
       | Company Isolation | Repository filtering by company_uuid |
       | Business Logic | *Service.cs, *Handler.cs |
       | Bug Fixes | Any fix: commit |
       | Repositories | *Repository.cs |
       | Logic Hooks (Frontend) | *.logic.ts |

       **TDD OPTIONAL Categories (test after is acceptable):**
       | Category | Example Files |
       |----------|---------------|
       | Simple DTOs | *Dto.cs, *Request.cs, *Response.cs |
       | Thin Controllers | *Controller.cs (delegates to services) |
       | UI Components | *.tsx (atoms, molecules) |
       | Styling | *.module.scss, *.css |

       **TDD Commit Sequence (for required categories):**
       1. Commit failing test: 'test: add test for X'
       2. Commit implementation: 'feat: implement X to pass tests'
       3. Commit refactor (if needed): 'refactor: improve X'

       **Bug Fix Pattern (MANDATORY):**
       1. Write test that reproduces the bug (proves it exists)
       2. Commit: 'test: add failing test for bug (AI-XXX)'
       3. Write fix that makes test pass
       4. Commit: 'fix: resolve issue description (AI-XXX)'

       QA will verify TDD compliance via git history. Violations on
       critical paths will result in BLOCKED status with tdd-violation label.
       ============================================================

       TASK REQUIREMENTS:
       {description from Jira}

       ACCEPTANCE CRITERIA:
       {acceptance criteria from Jira}

       WORKFLOW:
       1. Transition Jira to 'In Progress' (if not already)
       2. Check for technical spec (if exists, read and acknowledge)
       3. Verify working directory (pwd, git branch)
       4. Determine if task touches TDD-required categories
       5. If TDD required: Write failing test FIRST, commit, then implement
       6. If TDD optional: Implement, then write tests
       7. Use @agent-git-commit-helper for small, frequent commits
       8. Post constraint verification (if spec existed)
       9. Update Jira on completion

       Report: TASK_COMPLETE or TASK_BLOCKED with reason.
     ",
     subagent_type="{routed_agent}",
     run_in_background=true
   )
   ```

### Phase 8: Monitor and Report

Display execution status:

```
## Execution Started

| Task | Summary | Agent | Worktree | Status |
|------|---------|-------|----------|--------|
| AI-21 | Add user pagination | backend-developer | AI-21-a3f2 | running |
| AI-22 | Add pagination UI | frontend-developer | AI-22-b7c9 | running |

**Active Agents**: 2/5
**Active Worktrees**: 2/10

Use `/act status` to check progress.
```

## Example Usage

### Single Task

```
User: /implement-jira-task AI-456

Claude: Reading AI-456 from Jira...

**AI-456: Add pagination to users API**

Requirements:
- Add limit/offset parameters to GET /api/users
- Default limit: 50, max: 100
- Return total count in response header

Agent Routing: backend-developer (from description)
Dependencies: None

Creating worktree... AI-456-a3f2
Assigning to current user...
Moving to Sprint 15...
Launching backend-developer...

## Execution Status

| Task | Agent | Status |
|------|-------|--------|
| AI-456 | backend-developer | running |
```

### Multiple Tasks

```
User: /implement-jira-task AI-456 AI-457

Claude: Reading tasks from Jira...

**Tasks:**
1. AI-456: Add pagination to users API (backend)
2. AI-457: Add pagination UI controls (frontend)

Dependencies: None (independent tasks)

Creating worktrees...
- AI-456-a3f2 (backend-developer)
- AI-457-b7c9 (frontend-developer)

Launching parallel agents...

## Execution Status

| Task | Agent | Status |
|------|-------|--------|
| AI-456 | backend-developer | running |
| AI-457 | frontend-developer | running |

**Active Agents**: 2/5
```

### Epic Expansion

```
User: /implement-jira-task AI-100

Claude: AI-100 is an Epic. Expanding to child tasks...

Found 3 child tasks:
- AI-101: Backend API endpoint (backend-developer)
- AI-102: Frontend component (frontend-developer)
- AI-103: Documentation update (technical-writer)

All tasks are independent. Proceeding with parallel execution...
```

## Dependency Handling

When tasks have dependencies, the user chooses the approach:

1. **Proceed anyway**: All tasks run in parallel (fastest, may need rework if dependencies matter)
2. **Sequential order**: Tasks run in topological order based on dependencies
3. **Skip blocked**: Only tasks without blockers run now
4. **Cancel**: User reviews and fixes dependencies in Jira first

## Error Handling

### Task Not Found
```
Error: AI-999 not found in Jira. Please verify the task key.
```

### Task Already Complete
```
AI-456 is already in 'Done' status. Skipping.
```

### Worktree Limit Reached
```
Warning: Maximum worktrees (8) reached.
Waiting for existing agents to complete before starting more.
```

## Differences from /act

| Feature | /implement-jira-task | /act |
|---------|---------------------|------|
| Input | Jira keys directly | Plan from conversation |
| Task creation | Never (uses existing) | Creates if needed |
| Epic handling | Expands to children | N/A |
| Dependency detection | Yes, prompts user | No |
| Primary use case | Direct task implementation | Plan-to-execution workflow |

## Related Commands

- `/act` - Execute a plan (creates tasks if needed)
- `/create-plan-in-jira` - Create tasks from plan without implementation
- `/commit` - Create semantic commits
- `/review-code` - Code review and PR creation
