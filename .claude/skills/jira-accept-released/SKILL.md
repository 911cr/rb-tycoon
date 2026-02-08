---
name: jira-accept-released
description: Review Released tasks and mark merged PRs as Accepted
context: fork
agent: project-manager
disable-model-invocation: true
---

# Accept Released Tasks

Review all tasks with status "Released" and transition them to "Accepted" based on PR merge status.

## Overview

This command handles the final stage of the Jira workflow: transitioning merged PRs from "Released" to "Accepted". It verifies that associated PRs have been merged before marking tasks as complete.

## Workflow

### Step 1: Search for Released Tasks

```
jira_search_jql(
  jql="project = AI AND status = Released",
  fields=["key", "summary", "customfield_10000", "labels"]
)
```

### Step 2: For Each Task, Check PR Status

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

**Decision Matrix:**
| PR State | Action |
|----------|--------|
| `MERGED` | Transition to "Accepted" (ID: 31) |
| `OPEN` | Leave as "Released" (PR pending merge) |
| No PR data | Transition to "Accepted" (non-code task) |

### Step 3: Transition to Accepted

```
jira_transition_issue(issueKey="AI-XXX", transitionId="31")
```

### Step 4: Report Summary

Provide a summary of:
- Total tasks found with "Released" status
- Tasks transitioned to "Accepted" (with reason: merged PR or no PR)
- Tasks left as "Released" (with reason: open PR)
- Any errors encountered

## Transition Reference

| From Status | To Status | Transition ID |
|-------------|-----------|---------------|
| Released | Accepted | 31 |

## Status Flow Context

```
Ready To Release → Released (via /jira-review-released)
                        ↓
               Released → Accepted (this command)
```

## Usage Notes

- Run this command periodically to clean up completed work
- Tasks with open PRs will remain in "Released" until PRs are merged
- Non-code tasks (documentation, design) are automatically accepted
- The command is idempotent - running it multiple times is safe
