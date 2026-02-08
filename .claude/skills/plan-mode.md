---
skill-name: plan-mode
priority: 0
trigger: |
  ALWAYS ACTIVE when plan mode is involved:
  - User enters plan mode (shift+tab)
  - User is creating or refining a plan
  - User exits plan mode
  - User asks about plan status or confidence
  - Before suggesting /act or /create-plan-in-jira
  - After any plan update
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - WebSearch
  - WebFetch
  - TodoWrite
  - Task
  - mcp__atlassian__*
  - mcp__docker__*
  - mcp__postgres-local__*
forbidden-tools:
  - Edit
  - Write
  - NotebookEdit
description: |
  Consolidated plan mode skill. Routes ALL plan requests to system-architect
  for central coordination. Priority 0 (highest) guarantees this runs first.
---

# Plan Mode Routing (MANDATORY)

## THE PRIMARY RULE

**ALL plan mode input MUST be routed to the `system-architect` agent.**

The system-architect is the central planning coordinator who:
- Analyzes requests and identifies affected domains
- Decides which agents to consult (if any)
- Aggregates input and finalizes the plan
- Calculates and reports confidence

### How to Route

When plan mode is active (user entered via shift+tab or is discussing plans):

```
Task(
  subagent_type="system-architect",
  prompt="## Plan Mode Request

**User Request:**
{user_input}

**Current Context:**
- Branch: {current_branch}
- Recent changes: {relevant_context}

**Mode:** {standard | quick | comprehensive}

Please analyze this request and provide a plan following your Plan Mode Coordinator Role.",
  description="Route plan request to system-architect"
)
```

### Mode Selection

| User Action | Mode | What system-architect Does |
|-------------|------|---------------------------|
| Normal plan request | `standard` | Selective agent consultation based on complexity |
| `/quick-plan` | `quick` | Skip agent consultation entirely |
| `/consult-agents` | `comprehensive` | Consult ALL relevant agents |

### After Routing

When system-architect returns the plan:
1. Present the plan to the user exactly as formatted
2. The plan WILL include confidence percentage (system-architect handles this)
3. If confidence >= 80%, user can proceed with `/act` or `/create-plan-in-jira`
4. If confidence < 80%, suggest continuing to refine the plan

---

# Plan Mode Confidence (MANDATORY)

## THE ONE RULE

**Every plan mode response MUST end with a confidence block. Every suggestion to implement MUST show confidence prominently.**

## In Plan Mode: End Every Response With This

```markdown
---
## Plan Confidence: XX%

**Status**: [HIGH] / [GOOD] / [MODERATE] / [LOW]

**Increasing Confidence:**
- Factor 1
- Factor 2

**Decreasing Confidence:**
- Concern 1 (-X%)
- Concern 2 (-X%)

**To Increase Confidence:**
- [ ] Action 1 (+X%)
- [ ] Action 2 (+X%)
```

## After Plan Mode: Report to Main Thread

When exiting plan mode OR suggesting implementation, say:

```markdown
## Plan Summary

**Plan Confidence: XX%** [STATUS]

[1-2 sentence summary]

**Next Steps:**
- [If >= 80%] Ready for `/act`
- [If 60-79%] Use `/create-plan-in-jira` first, refine before `/act`
- [If < 60%] Continue planning
```

## Before /act or /create-plan-in-jira: ALWAYS Show Confidence

**NEVER suggest these commands without showing confidence first.**

```markdown
**Current Confidence: XX%** [STATUS]

[If < 80% for /act] Warning: Recommend 80%+ before implementation.
```

## Confidence Thresholds

| Range | Status | Meaning |
|-------|--------|---------|
| 90-100% | `[HIGH]` | Proceed confidently |
| 80-89% | `[GOOD]` | Ready for /act |
| 60-79% | `[MODERATE]` | OK for /create-plan-in-jira, needs work before /act |
| Below 60% | `[LOW]` | Keep planning, do not proceed |

## Calculating Confidence

**Start at 50% and adjust:**

| Factor | Adjustment |
|--------|------------|
| Read and understood key files | +10% |
| Found similar pattern in codebase | +10% |
| Clear, unambiguous requirements | +10% |
| **Test strategy defined** | **+10%** |
| Test patterns exist in codebase | +5% |
| All affected services identified | +5% |
| Database schema understood | +5% |
| Haven't read key files yet | -10% |
| **No test strategy defined** | **-15%** |
| Requirements unclear | -15% |
| Breaking changes possible | -10% |
| Security not analyzed | -10% |
| New/novel pattern (no precedent) | -5% |

**Test Strategy Weighting:**
Test strategy is now weighted more heavily because:
- TDD is mandatory for critical paths
- QA agents verify TDD compliance via git history
- Missing test strategy leads to TDD violations and QA blockers
- Well-defined test strategy = smoother implementation and QA phases

## Plan State Files (Optional)

For tracking, create: `docs/plan/PLAN-YYYYMMDD-{description}_state.md`

```markdown
# Plan: PLAN-YYYYMMDD-description

## Metadata
| Field | Value |
|-------|-------|
| Confidence | XX% |
| Status | Planning / Tasks Created / In Progress / Complete |

## Jira Tasks
| Key | Summary | Status |
|-----|---------|--------|
| AI-XXX | Task title | To Do |
```

## Multi-Agent Consultation

**Agent consultation is handled by system-architect.** Do not invoke agents directly for plan consultation.

The system-architect decides:
- Which agents to consult based on affected domains
- Whether to run quick (no consultation), standard (selective), or comprehensive (all agents)
- How to aggregate confidence from multiple agent responses

**Commands for consultation control:**
- `/quick-plan` - Tell system-architect to skip consultation
- `/consult-agents` - Tell system-architect to consult ALL relevant agents
- Default - System-architect decides selectively based on complexity

See `.claude/agents/system-architect.md` for the agent consultation decision matrix.

## Required Plan Artifacts (MANDATORY for /act and /create-plan-in-jira)

**CRITICAL**: Before `/act` or `/create-plan-in-jira` can be executed, the `plan-prerequisites-enforcement` skill (priority -3) will verify that required planning artifacts exist.

### Required Artifacts

**Plan Directory:** `docs/plan/{plan-id}/`

| Artifact | Required For | Source Agent |
|----------|--------------|--------------|
| `technical-plan.md` | ALL plans | system-architect |
| `pseudo-code-plan.md` | 3+ tasks | staff-engineer-advisor |
| `technical-spec.md` | 3+ tasks | system-architect |
| `critical-constraints.md` | 3+ tasks | system-architect |

### Artifact Creation Workflow

```
1. User enters plan mode (shift+tab)
        |
2. system-architect creates technical-plan.md
        |
3. For complex plans (3+ tasks):
   a. staff-engineer-advisor creates pseudo-code-plan.md
   b. Agent review (confidence-based or full sign-off)
   c. system-architect generates technical-spec.md
   d. system-architect generates critical-constraints.md
        |
4. Confidence >= 80% -> User runs /act
        |
5. plan-prerequisites-enforcement skill verifies artifacts
        |
6. PASS -> Proceed with implementation
   FAIL -> BLOCK with guidance to complete planning
```

### Quick Plan Exception

If `/quick-plan` was used:
- A marker file `docs/plan/{plan-id}/.quick-plan` is created
- Only `technical-plan.md` is required
- Other artifacts are optional

### Before Suggesting /act or /create-plan-in-jira

**Always verify artifacts exist first:**

```markdown
## Plan Artifacts Status

| Artifact | Status |
|----------|--------|
| technical-plan.md | FOUND/MISSING |
| pseudo-code-plan.md | FOUND/MISSING/N/A (quick plan) |
| technical-spec.md | FOUND/MISSING/N/A (quick plan) |
| critical-constraints.md | FOUND/MISSING/N/A (quick plan) |

[If any MISSING for complex plan]
**WARNING:** Cannot run /act - missing required artifacts.
Complete planning first, then try again.
```

---

## Quick Reference

1. **In plan mode** = End with confidence block
2. **Exiting plan mode** = Report confidence to main thread
3. **Before /act** = Show confidence prominently AND verify artifacts
4. **Before /create-plan-in-jira** = Show confidence prominently AND verify artifacts
5. **Asked about plan** = Show current confidence
6. **Artifacts missing** = BLOCK with guidance to complete planning

**When in doubt: SHOW THE CONFIDENCE PERCENTAGE AND VERIFY ARTIFACTS.**
