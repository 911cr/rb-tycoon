---
description: Create a quick plan without multi-agent consultation for simple changes
---

# Quick Plan Command

Create a quick plan by routing through system-architect with the `quick` mode flag, which skips agent consultation entirely.

## Usage

```
/quick-plan [description]
```

**Examples:**
```
/quick-plan Add a new button to the settings page
/quick-plan Fix typo in error message
/quick-plan Update API response format
```

## What This Command Does

This command routes your request to the `system-architect` agent with instructions to skip agent consultation and provide a quick single-perspective plan.

## Execution

When `/quick-plan` is invoked:

```
Task(
  subagent_type="system-architect",
  prompt="## Plan Mode Request - QUICK MODE

**User Request:**
{description}

**Current Context:**
- Branch: {current_branch}

**Mode:** quick

**QUICK MODE INSTRUCTIONS:**
Skip agent consultation entirely. Provide a quick, single-perspective
plan without invoking other agents. The user wants speed over
comprehensive validation.

Please analyze this request and provide a plan following your Plan Mode Coordinator Role,
using quick mode (no agent consultation).",
  description="Quick plan via system-architect (no consultation)"
)
```

## When to Use

Use this command when:
- Making trivial changes (typo fixes, small UI tweaks)
- Single-domain changes with clear requirements
- You're confident and don't need expert perspectives
- Speed is more important than comprehensive analysis
- Following well-established patterns

## When NOT to Use

Do NOT use quick plan for:
- Multi-domain changes (backend + frontend)
- Security-sensitive changes
- Breaking changes or migrations
- New features requiring architectural decisions
- Changes affecting multiple services

## What System-Architect Does in Quick Mode

1. **Creates plan directory**: `docs/plan/PLAN-{YYYYMMDD}-{description}/`
2. **Creates quick-plan marker**: `docs/plan/{plan-id}/.quick-plan` (enables simplified artifact requirements)
3. **Analyzes the request** without invoking other agents
4. **Identifies affected files** and components
5. **Creates technical-plan.md** (ONLY required artifact for quick plans)
6. **Calculates confidence** without domain breakdown
7. **Returns quickly** (no parallel agent calls)

## Quick Plan Artifact Requirements

Quick plans have **simplified artifact requirements**:

| Artifact | Required? | Notes |
|----------|-----------|-------|
| `technical-plan.md` | YES | Always required |
| `pseudo-code-plan.md` | NO | Optional for quick plans |
| `technical-spec.md` | NO | Optional for quick plans |
| `critical-constraints.md` | NO | Optional for quick plans |

The `.quick-plan` marker file signals to the `plan-prerequisites-enforcement` skill (priority -3) that only `technical-plan.md` is required.

## Output Format

System-architect returns a streamlined plan:

```markdown
## Plan: {Title}

### Summary
{Brief description of the change}

### Tasks
| # | Task | Agent | Effort |
|---|------|-------|--------|
| 1 | {task} | {agent} | S |

### Agent Consultations
Single-perspective analysis (no agent consultation)

### Files Affected
- `{file path 1}`
- `{file path 2}`

---

## Plan Confidence: XX%

**Status**: [HIGH/GOOD/MODERATE/LOW]

**Factors Increasing Confidence:**
- {Factor 1}
- {Factor 2}

**Factors Decreasing Confidence:**
- {Concern 1}

**To Increase Confidence:**
- [ ] {Action item 1}

---

*Quick plan mode - agent consultation skipped*
*Run `/consult-agents` for domain-specific perspectives*
```

## Related Commands

| Command | Mode | Agent Consultation |
|---------|------|-------------------|
| `/quick-plan` | quick | None (skip consultation) |
| (default plan) | standard | Selective (system-architect decides) |
| `/consult-agents` | comprehensive | ALL relevant agents |

## Upgrading to Full Consultation

If you create a quick plan but later want agent perspectives:

```
/consult-agents
```

This will run comprehensive consultation on your existing plan and provide per-agent confidence breakdown.

## Triggering Quick Mode

Besides using `/quick-plan`, you can also trigger quick mode by saying:
- "quick plan"
- "simple plan"
- "no consultation"
- "skip agents"

These keywords are detected by the `plan-mode` skill.

## Notes

- Quick plans still require 80% confidence for `/act`
- System-architect handles all analysis (no other agents invoked)
- You can upgrade to comprehensive consultation at any time
- For trivial changes, quick plan is the recommended approach
