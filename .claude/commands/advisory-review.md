---
description: Get advisory agents who contributed to a plan to review the implementation before QA
---

# /advisory-review Command

Spawn advisory agents who contributed to a plan to review the implementation and provide approval or feedback. This ensures that technical guidance provided during planning was correctly applied.

## Usage

```bash
/advisory-review {plan-id}                 # Review by plan ID
/advisory-review AI-XXX                    # Review by Jira task
/advisory-review                           # Review most recent plan
```

## Purpose

Advisory agents (database-advisor, security-engineer-advisor, etc.) often provide critical guidance during planning. This command:

1. Identifies which advisors contributed to the plan
2. Spawns each advisor to review the implementation
3. Collects approval/rejection from each
4. Blocks QA until all advisors approve

## Workflow

### Phase 1: Locate Plan State and Contributing Agents

1. **Find plan state file:**
   ```
   Read("docs/plan/{plan-id}_state.md")
   # Or find by Jira task
   # Or find most recent: Glob("docs/plan/PLAN-*_state.md")
   ```

2. **Extract contributing agents:**
   Parse the "Contributing Agents" section:
   ```markdown
   ## Contributing Agents
   | Agent | Contribution | Date |
   |-------|--------------|------|
   | database-advisor | Schema design for user_pagination table | 2025-12-24 |
   | security-engineer-advisor | Company isolation requirements | 2025-12-24 |
   ```

3. **Get Jira tasks for the plan:**
   ```
   jira_search_jql(
     jql="project = AI AND description ~ '{plan-id}'",
     fields=["key", "summary", "status"]
   )
   ```

### Phase 2: Identify Files Changed

1. **Get git diff for each task's worktree (if applicable):**
   ```bash
   git diff {base-branch}...HEAD --name-only
   ```

2. **Or read from Jira comments for completed tasks:**
   Look for commit references and file lists.

### Phase 3: Spawn Advisory Reviews

For each contributing advisor, spawn a review task:

```
Task(
  description: "Advisory review by {advisor} for {plan-id}",
  prompt: "
    ADVISORY IMPLEMENTATION REVIEW
    ==============================
    Plan: {plan-id}
    Your Role: {advisor}
    Your Contribution: {contribution from plan state}

    REVIEW SCOPE:
    You provided guidance during planning for this feature.
    Now review the implementation to verify your recommendations were followed.

    TECHNICAL SPECIFICATION:
    docs/plan/{plan-id}/technical-spec.md

    YOUR ORIGINAL RECOMMENDATIONS:
    {Extract advisor's recommendations from technical-spec.md}

    FILES CHANGED:
    {list of files modified}

    REVIEW CHECKLIST:
    1. Read the implementation in the changed files
    2. Compare against your original recommendations
    3. Verify each recommendation was correctly applied
    4. Identify any deviations or concerns

    PROVIDE:
    1. APPROVAL STATUS: APPROVED | CHANGES REQUESTED | BLOCKED
    2. RECOMMENDATION COMPLIANCE:
       | Rec ID | Recommendation | Status | Notes |
       |--------|----------------|--------|-------|
       | A1 | {rec} | FOLLOWED / PARTIAL / NOT FOLLOWED | {notes} |
    3. CONCERNS (if any):
       - {concern with severity: BLOCKER / MAJOR / MINOR}
    4. OVERALL ASSESSMENT:
       {1-2 sentence summary}

    If BLOCKED or CHANGES REQUESTED, specify what must be fixed.
  ",
  agent: "{advisor}",
  run_in_background: true
)
```

### Phase 4: Collect Results

Monitor all advisor review tasks:

```
TaskOutput(agent_id: "{advisor_1_id}")
TaskOutput(agent_id: "{advisor_2_id}")
...
```

Parse each response for:
- Approval status (APPROVED / CHANGES REQUESTED / BLOCKED)
- Recommendation compliance table
- Concerns list

### Phase 5: Generate Consolidated Report

```markdown
## Advisory Review Report: {plan-id}

**Plan:** `docs/plan/{plan-id}/`
**Reviewed:** {ISO timestamp}
**Overall Status:** {ALL APPROVED | CHANGES REQUESTED | BLOCKED}

### Review Summary

| Advisor | Contribution | Status | Concerns |
|---------|--------------|--------|----------|
| database-advisor | Schema design | APPROVED | None |
| security-engineer-advisor | Company isolation | CHANGES REQUESTED | 1 MAJOR |

### Detailed Reviews

#### database-advisor Review

**Status:** APPROVED

**Recommendation Compliance:**
| ID | Recommendation | Status |
|----|----------------|--------|
| A1 | Use UUID for primary keys | FOLLOWED |
| A2 | Add company_uuid index | FOLLOWED |
| A3 | Use parameterized queries | FOLLOWED |

**Assessment:** All database recommendations were correctly implemented.

---

#### security-engineer-advisor Review

**Status:** CHANGES REQUESTED

**Recommendation Compliance:**
| ID | Recommendation | Status | Notes |
|----|----------------|--------|-------|
| B1 | Validate company_uuid from JWT | FOLLOWED | - |
| B2 | Add rate limiting to endpoint | NOT FOLLOWED | Missing |

**Concerns:**
- MAJOR: Rate limiting not implemented on new pagination endpoint

**Assessment:** Company isolation is correct, but rate limiting must be added.

---

### Required Actions

{If not all APPROVED:}

| Priority | Action | Assigned Agent | Jira Task |
|----------|--------|----------------|-----------|
| MAJOR | Add rate limiting to /api/users endpoint | backend-developer | AI-XXX |

### Next Steps

{Based on outcome:}
- **ALL APPROVED:** Proceed to QA
  - `/qa-backend {jira-key}`
  - `/qa-frontend {jira-key}`
- **CHANGES REQUESTED:** Address concerns, then re-run `/advisory-review`
- **BLOCKED:** Critical issues must be resolved before proceeding
```

### Phase 6: Update Jira

1. **Add review report as comment:**
   ```
   jira_add_comment(
     issueKey="AI-XXX",
     body="## Advisory Review Complete\n\n{summary}\n\nSee full report: `docs/plan/{plan-id}/advisory-review-{timestamp}.md`"
   )
   ```

2. **Add label based on outcome:**
   - All approved: `advisory-review-approved`
   - Changes requested: `advisory-review-changes-requested`
   - Blocked: `advisory-review-blocked`

3. **If changes requested, create subtask:**
   ```
   jira_create_issue(
     projectKey="AI",
     issueTypeName="Subtask",
     parentKey="AI-XXX",
     summary="Address advisory review feedback: {concern}",
     description="## Concern\n{concern details}\n\n## Source\n{advisor}\n\n## Required Fix\n{what needs to change}"
   )
   ```

## Example Usage

```
User: /advisory-review PLAN-20251224-user-pagination

Claude: Starting advisory review for PLAN-20251224-user-pagination...

Reading plan state...
Found 2 contributing advisors:
- database-advisor (Schema design for pagination)
- security-engineer-advisor (Company isolation requirements)

Finding changed files...
12 files modified across 2 tasks (AI-456, AI-457).

Spawning advisory reviews...
- database-advisor review started [agent_id: db_review_123]
- security-engineer-advisor review started [agent_id: sec_review_456]

Waiting for reviews to complete...

## Advisory Review Report

**Overall Status:** ALL APPROVED

| Advisor | Status | Concerns |
|---------|--------|----------|
| database-advisor | APPROVED | None |
| security-engineer-advisor | APPROVED | None |

All advisors have approved the implementation.

Next step: `/qa-backend AI-456`
```

## When to Use

1. **After implementation, before QA:**
   - `/act` completes -> `/advisory-review` -> `/qa-backend`

2. **When advised by multiple specialists:**
   - Complex features with database, security, and architecture input

3. **For high-risk features:**
   - Authentication, data isolation, encryption changes

## Skipping Advisory Review

If a plan had NO advisory agent contributions (simple feature), this command will:
```
No advisory agents contributed to plan {plan-id}.
Advisory review not required.

Proceed to QA: `/qa-backend {jira-key}`
```

## Error Handling

### Advisor Agent Unavailable
```
Warning: Could not spawn {advisor} for review.
Reason: {error}

Options:
1. Retry the review for this advisor
2. Skip this advisor (document reason)
3. Get manual review from team member
```

### Advisor Reports Blocker
```
BLOCKED: {advisor} has identified a critical issue.

Issue: {description}
Severity: BLOCKER
Required Fix: {what must change}

The implementation cannot proceed to QA until this is resolved.

Create fix task? (yes/no)
```

## Related Commands

- `/create-plan-in-jira` - Tracks contributing agents during planning
- `/verify-constraints` - Verifies constraint compliance (complementary to this)
- `/qa-backend` - Backend QA (run after advisory review)
- `/qa-frontend` - Frontend QA (run after advisory review)
- `/review-code` - Code review (run after QA)
