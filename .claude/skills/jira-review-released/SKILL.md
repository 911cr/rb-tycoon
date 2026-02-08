---
name: jira-review-released
description: Review Ready To Release tasks and transition merged PRs to Released
context: fork
agent: project-manager
disable-model-invocation: true
---

# Review Ready To Release Tasks

Review all tasks with status "Ready To Release" and transition them to "Released" after verifying their PRs have been merged to the main branch.

## Overview

This command handles the transition from "Ready To Release" to "Released". It verifies that:
1. The associated PR has been merged
2. The related commits are present on the `main` branch

This is an intermediate step between PR approval and final acceptance.

## Workflow

### Step 1: Search for Ready To Release Tasks

```
jira_search_jql(
  jql="project = AI AND status = 'Ready To Release'",
  fields=["key", "summary", "customfield_10000", "labels", "comment"]
)
```

### Step 2: For Each Task, Verify PR Merged

**Option A: Check via Jira Development Panel**

The `customfield_10000` (development panel) contains PR information:

```json
{
  "pullrequest": {
    "state": "MERGED",
    "stateCount": 1,
    "dataType": "pullrequest"
  }
}
```

**Option B: Check via GitHub CLI**

If the development panel is not populated, check comments for PR URLs and verify via gh CLI:

```bash
# Extract PR URL from task comments, then check status
gh pr view {pr_number} --json state,mergedAt
```

**Decision Matrix:**
| PR State | Action |
|----------|--------|
| `MERGED` | Transition to "Released" (ID: 3) |
| `OPEN` | Leave as "Ready To Release" (PR pending merge) |
| `CLOSED` (not merged) | Add warning comment, investigate |
| No PR found | Leave as is, add warning comment |

### Step 3: Verify Commits on Main Branch

Before transitioning, confirm the commits are on main:

```bash
# Get the Jira key from the task
# Check if commits with that key are on main
git log main --oneline --grep="AI-XXX" | head -5
```

If no commits found on main but PR shows merged, the merge may have been to a different branch - add a warning comment.

### Step 4: Transition to Released

```
jira_transition_issue(issueKey="AI-XXX", transitionId="3")
```

### Step 5: Add Release Comment

```
jira_add_comment(
  issueKey="AI-XXX",
  body="## Released\n\nPR merged to main branch.\n- PR: {pr_url}\n- Merged: {merge_date}\n- Commits on main: verified"
)
```

### Step 6: Report Summary

Provide a summary of:
- Total tasks found with "Ready To Release" status
- Tasks transitioned to "Released" (with PR links)
- Tasks left as "Ready To Release" (with reason: open PR)
- Any warnings or issues encountered

## Transition Reference

| From Status | To Status | Transition ID |
|-------------|-----------|---------------|
| Ready To Release | Released | 3 |

## Status Flow Context

```
Review → Ready To Release (code reviewer transitions on PR create)
                    ↓
   Ready To Release → Released (this command, after PR merge)
                    ↓
           Released → Accepted (via /jira-accept-released)
```

## Usage Notes

- Run this command after merging PRs to update Jira status
- The command verifies PRs are truly merged, not just approved
- Tasks without merged PRs remain in "Ready To Release"
- Use `/jira-accept-released` after this to complete the workflow
- The command is idempotent - running it multiple times is safe
