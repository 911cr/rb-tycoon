---
skill-name: verification-before-reporting
priority: -2
trigger: |
  ALWAYS ACTIVE for ALL agents and the main orchestrator.
  This skill applies to ANY interaction where:
  - Status is being reported to the user
  - Task completion is being claimed
  - Jira status is being described
  - Agent work results are being summarized
  - Any statement of fact about external systems (Jira, git, databases)
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
  - mcp__kubernetes__*
  - mcp__postgres-local__*
  - mcp__postgres-prod__*
  - mcp__curl__*
  - mcp__codacy__*
description: |
  VERIFICATION-FIRST ENFORCEMENT - Priority -2 (highest possible)

  This skill enforces MANDATORY verification before reporting any status,
  completion, or factual claims about external systems (Jira, git, databases, etc.)

  CORE PRINCIPLE: Never claim something is true without first verifying it.
  If you cannot verify, say "I cannot verify" - NEVER guess.
---

# Verification-Before-Reporting Enforcement

## THE CARDINAL RULE

**NEVER report status, completion, or any factual claim without FIRST querying the source of truth.**

This is non-negotiable. If you cannot verify something, you MUST say "I don't know" or "I cannot verify" - NEVER guess, assume, or infer.

---

## ABSOLUTE PROHIBITIONS

### 1. NEVER Guess Task Status

**FORBIDDEN:**
- Assuming a task is complete because code was written
- Inferring status from conversation context alone
- Reporting status without a recent Jira API call
- Saying "AI-123 is complete" without `jira_get_issue(issueKey="AI-123")`

**REQUIRED:**
- Always call `jira_get_issue()` before reporting ANY task status
- Include the actual status field value from the API response
- Show the timestamp of when you verified

### 2. NEVER Infer Agent Completion Without Checking

**FORBIDDEN:**
- Assuming a background agent succeeded because time passed
- Reporting agent completion without `TaskOutput(agent_id=...)`
- Saying "the agent finished" without actual verification

**REQUIRED:**
- Call `TaskOutput(agent_id=...)` to get actual agent status
- Report the exact status returned: "running", "completed", "failed"
- If agent output is unclear, say so explicitly

### 3. NEVER Report Jira Labels/Status Without Fresh Query

**FORBIDDEN:**
- Remembering labels from earlier in conversation
- Assuming a transition succeeded without verification
- Reporting labels without querying Jira

**REQUIRED:**
- After ANY transition, call `jira_get_issue()` to verify
- Include the actual labels array from the response
- Report if the transition failed or status didn't change

### 4. NEVER Claim Completion Based on Partial Evidence

**FORBIDDEN:**
- Seeing "a hint of something" and reporting it as fact
- Extrapolating from one data point
- Making logical assumptions about what "must have" happened

**REQUIRED:**
- Verify each claim independently
- If you only have partial information, explicitly say so
- Use phrases like "I can confirm X, but I cannot verify Y"

---

## MANDATORY VERIFICATION PATTERNS

### Before Reporting Task Status

```markdown
**CORRECT PATTERN:**

1. Query Jira: jira_get_issue(issueKey="AI-123", fields=["status", "labels", "summary"])
2. Receive response: { status: { name: "In Progress" }, labels: ["worktree-active"], ... }
3. Report: "AI-123 is currently **In Progress** with label `worktree-active` (verified via Jira API)"

**WRONG PATTERN:**

1. Remember that we started AI-123 earlier
2. Report: "AI-123 should be done by now"  <- FORBIDDEN
```

### Before Reporting Agent Completion

```markdown
**CORRECT PATTERN:**

1. Query agent: TaskOutput(agent_id="abc123")
2. Receive response: { status: "completed", output: "..." }
3. Report: "Agent abc123 has **completed** (verified via TaskOutput)"

**WRONG PATTERN:**

1. Launched agent 10 minutes ago
2. Report: "The agent should be done"  <- FORBIDDEN
```

### Before Reporting Multiple Tasks

```markdown
**CORRECT PATTERN:**

For each task AI-101, AI-102, AI-103:
1. jira_get_issue(issueKey="AI-101")
2. jira_get_issue(issueKey="AI-102")
3. jira_get_issue(issueKey="AI-103")

Then report table with ACTUAL values from each response.

**WRONG PATTERN:**

1. Query AI-101, see it's done
2. Assume AI-102 and AI-103 are also done  <- FORBIDDEN
```

---

## REQUIRED LANGUAGE PATTERNS

### When You CAN Verify

Use definitive language WITH evidence:

```markdown
**AI-123 Status: In Progress**
- Verified: 2025-01-14T10:30:00Z via jira_get_issue
- Labels: ["worktree-active", "backend"]
- Assignee: john.doe@example.com
```

### When You CANNOT Verify

Be explicit about uncertainty:

```markdown
**AI-123 Status: Unknown**
- I could not verify the status because [reason]
- Last known status was [X] at [timestamp]
- To get current status, I would need to [action]
```

### When Verification Fails

Report the failure honestly:

```markdown
**AI-123 Status: Verification Failed**
- Attempted: jira_get_issue(issueKey="AI-123")
- Error: [error message]
- Cannot confirm current status
```

---

## STATUS REPORTING TEMPLATE

Whenever reporting task status, use this format:

```markdown
## Task Status Report

**Verified At:** [ISO timestamp]
**Method:** jira_get_issue / TaskOutput / git status

| Task | Status | Labels | Last Updated | Verified |
|------|--------|--------|--------------|----------|
| AI-101 | In Progress | worktree-active | 2025-01-14T10:00 | YES |
| AI-102 | Review | qa-pending | 2025-01-14T09:30 | YES |
| AI-103 | Unknown | - | - | NO (API error) |

**Verification Notes:**
- AI-101, AI-102: Confirmed via Jira API
- AI-103: Could not verify - Jira returned 404
```

---

## BEFORE ANY STATUS CLAIM

Run this mental checklist:

1. **Am I about to claim something is true?**
   - YES -> Continue to step 2
   - NO -> Proceed normally

2. **Have I queried the source of truth in the last 60 seconds?**
   - YES -> Proceed with claim, cite the query
   - NO -> Query first, then make claim

3. **Did the query succeed and return clear data?**
   - YES -> Report the actual data
   - NO -> Report "cannot verify" with reason

4. **Am I making any assumptions beyond what the data shows?**
   - YES -> Stop, query for missing data or say "I don't know"
   - NO -> Proceed with verified claim

---

## AGENT-TO-AGENT COMMUNICATION

When receiving information from another agent:

1. **Do NOT trust agent claims without verification**
2. **If agent says task is complete, verify with Jira**
3. **If agent reports an error, verify the error**
4. **Report to user: "Agent X reported Y - I verified this is correct/incorrect"**

---

## COMMON MISTAKES TO AVOID

| Mistake | Why It's Wrong | Correct Approach |
|---------|----------------|------------------|
| "Task should be done" | "Should" is a guess | Query Jira, report actual status |
| "I believe the agent completed" | "Believe" is uncertain | Call TaskOutput, report actual result |
| "Based on our earlier work..." | Earlier != current | Query current state before reporting |
| "The task is probably in Review" | "Probably" is a guess | Query Jira, report actual status |
| "It looks like X happened" | "Looks like" is inference | Verify X happened, then report |

---

## ENFORCEMENT

This skill has **priority -2** (highest possible), meaning it runs before all other skills including orchestrator-mode (-1).

**Every agent, every response, every status claim MUST follow these rules.**

If you find yourself about to report status without verification:
1. STOP
2. Query the source of truth
3. Report with evidence
4. Include verification timestamp

**There are ZERO exceptions to this rule.**
