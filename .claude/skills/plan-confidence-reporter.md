---
skill-name: plan-confidence-reporter
priority: 6
trigger: |
  Activate AFTER plan mode responses, specifically:
  - After any plan update or refinement in plan mode
  - When transitioning from plan mode to the main chat thread
  - When the user exits plan mode (shift+tab again)
  - When suggesting implementation readiness to the user
  - When /act or /create-plan-in-jira is about to be invoked
  - When asking the user "Should we implement this?"
allowed-tools:
  - Read
  - Grep
  - Glob
forbidden-tools:
  - Edit
  - Write
  - NotebookEdit
description: |
  Ensures plan confidence is ALWAYS surfaced to the main chat thread after plan updates.
  Solves the problem where confidence is only visible in plan files/windows but not in
  the main conversation. Priority 6 activates after plan state management.
---

# Plan Confidence Reporter Skill

## Purpose

This skill ensures that the **current plan confidence percentage** is ALWAYS visible in the main chat thread, not just buried in plan files or the plan mode window.

## CRITICAL REQUIREMENT

**Every time you suggest implementation or ask if the user is ready to proceed, you MUST include the current confidence level prominently in your message.**

## When to Report Confidence

### 1. After Plan Mode Updates

When the user has been working in plan mode and the plan is updated:

```
## Plan Update Summary

The plan for [feature/task] has been refined.

**Current Confidence: XX%** [STATUS_EMOJI]

[Brief summary of what changed]
```

### 2. When Suggesting Implementation

**NEVER suggest implementation without showing confidence:**

```markdown
## Ready to Implement?

**Plan Confidence: XX%** [STATUS_EMOJI]

[Summary of the plan]

### Confidence Breakdown
- Factors Increasing: [brief list]
- Factors Decreasing: [brief list]

### Next Steps
[Appropriate options based on confidence level]
```

### 3. Before /act or /create-plan-in-jira

When about to run either command, FIRST report:

```markdown
## Pre-Implementation Check

**Current Confidence: XX%** [STATUS_EMOJI]

[If >= 80%] Ready to proceed with `/act`.
[If 60-79%] Ready for `/create-plan-in-jira` but needs refinement before `/act`.
[If < 60%] NOT recommended. Continue refining the plan.
```

## Confidence Status Indicators

Use these visual indicators based on confidence level:

| Range | Status | Indicator | Action |
|-------|--------|-----------|--------|
| 90-100% | High | `[HIGH CONFIDENCE]` | Proceed with `/act` |
| 80-89% | Good | `[GOOD CONFIDENCE]` | Proceed with `/act` |
| 60-79% | Moderate | `[MODERATE CONFIDENCE]` | OK for `/create-plan-in-jira`, refine before `/act` |
| 40-59% | Low | `[LOW CONFIDENCE]` | Continue planning, do not proceed |
| Below 40% | Very Low | `[INSUFFICIENT CONFIDENCE]` | Significant unknowns, needs major refinement |

## Reading Current Confidence

To get the current plan confidence:

### From Active Plan State File
```
1. Find the most recent plan state file:
   Glob("docs/plan/PLAN-*_state.md")

2. Read the Metadata section for Confidence field:
   | Confidence | XX% |

3. If no state file, confidence should be in the plan mode response
```

### From Plan Mode Context
If currently in or just exited plan mode, the confidence should be at the end of the plan:
```
---
## Plan Confidence: XX%
```

## Mandatory Confidence Block Format

When reporting confidence in the main thread, use this format:

```markdown
---

## Current Plan Confidence: XX%

**Status**: [HIGH/GOOD/MODERATE/LOW/INSUFFICIENT] CONFIDENCE

| Factor | Impact |
|--------|--------|
| [Positive factor 1] | +X% |
| [Positive factor 2] | +X% |
| [Negative factor 1] | -X% |
| [Negative factor 2] | -X% |

**Recommendation**: [What action to take based on confidence]
```

## Implementation Prompts

### When Confidence >= 80%

```markdown
## Ready to Implement

**Plan Confidence: 85%** [GOOD CONFIDENCE]

Your plan is ready for implementation. You have two options:

1. **Implement Now** - Run `/act` to:
   - Create Jira tasks (if not already created)
   - Assign to active sprint
   - Start parallel agent implementation

2. **Review First** - Run `/create-plan-in-jira` to:
   - Create Jira tasks only (no implementation)
   - Review in Jira before implementing
   - Then run `/act` when ready

Which would you prefer?
```

### When Confidence 60-79%

```markdown
## Plan Needs Refinement

**Plan Confidence: 72%** [MODERATE CONFIDENCE]

The plan is partially ready but needs more refinement before implementation.

**Current Gaps:**
- [List factors decreasing confidence]

**Options:**
1. **Continue Planning** - Address the gaps above to increase confidence
2. **Create Tasks for Review** - Run `/create-plan-in-jira` to create tasks and refine in Jira
3. **Proceed Anyway** - Run `/act` (not recommended at this confidence level)

What would you like to do?
```

### When Confidence < 60%

```markdown
## Plan Not Ready

**Plan Confidence: 48%** [LOW CONFIDENCE]

The plan has significant gaps that should be addressed before implementation.

**Critical Issues:**
- [List major unknowns]

**Recommended Next Steps:**
1. [Specific action to increase confidence]
2. [Specific action to increase confidence]
3. [Specific action to increase confidence]

Let's continue refining the plan. [Ask a specific question to fill a gap]
```

## Integration with Commands

### /act Command Integration

Before executing `/act`, always:
1. Read current plan confidence
2. Display the confidence prominently
3. Warn if below 80%
4. Proceed only with user acknowledgment if below threshold

### /create-plan-in-jira Command Integration

Before executing `/create-plan-in-jira`, always:
1. Read current plan confidence
2. Display the confidence prominently
3. Warn if below 60%
4. Proceed only with user acknowledgment if below threshold

## Error Cases

### No Confidence Found
If you cannot determine the current confidence:

```markdown
## Confidence Unknown

I cannot determine the current plan confidence. This may happen if:
- No plan has been created yet
- The plan mode response didn't include a confidence section
- The plan state file is missing

**Action Required:** Please enter plan mode (shift+tab) and create or refine a plan with a confidence assessment.
```

### Stale Confidence
If the plan state file is older than 24 hours:

```markdown
## Confidence May Be Stale

**Last Updated Confidence: XX%** (from [date])

The plan confidence was assessed [X hours/days] ago. Changes to the codebase or requirements may have affected accuracy.

**Recommendation:** Re-enter plan mode (shift+tab) to reassess confidence with current context.
```

## Remember

1. **NEVER prompt for implementation without showing confidence**
2. **ALWAYS include the confidence percentage prominently**
3. **Use visual indicators** ([HIGH], [MODERATE], etc.) for quick scanning
4. **Provide context** - show factors affecting confidence
5. **Guide the user** - recommend appropriate actions based on confidence level
6. **Be honest** - if confidence is low, say so clearly
