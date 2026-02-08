---
description: Force multi-agent consultation for the current plan to gather domain-specific perspectives
---

# Consult Agents Command

Force comprehensive multi-agent consultation for the current plan by routing through system-architect with the `comprehensive` mode flag.

## Usage

```
/consult-agents
```

## What This Command Does

This command routes your current plan to the `system-architect` agent with instructions to consult **ALL relevant agents** (not just selectively chosen ones).

## Execution

When `/consult-agents` is invoked:

```
Task(
  subagent_type="system-architect",
  prompt="## Plan Mode Request - COMPREHENSIVE CONSULTATION

**User Request:**
{current_plan_context}

**Current Context:**
- Branch: {current_branch}
- Plan so far: {existing_plan_details}

**Mode:** comprehensive

**COMPREHENSIVE MODE INSTRUCTIONS:**
You MUST consult ALL agents that have ANY relevance to this plan.
Do not skip agents for simplicity. The user explicitly requested
exhaustive consultation for maximum validation.

Please analyze this request and provide a plan following your Plan Mode Coordinator Role,
ensuring you invoke all relevant domain agents.",
  description="Comprehensive plan consultation via system-architect"
)
```

## When to Use

Use this command when:
- You want expert perspectives even for a simple plan
- You want to validate a plan before implementation
- You're uncertain about specific domains
- You want the enhanced confidence format with per-agent breakdown
- High-risk changes where you want maximum validation

## When NOT to Use

- For trivial changes (use `/quick-plan` instead)
- When speed is more important than thoroughness
- When you've already validated with specific agents

## What System-Architect Does in Comprehensive Mode

1. **Identifies ALL relevant domains** based on files and keywords
2. **Consults ALL matching agents** in parallel (no selective filtering)
3. **Aggregates confidence** from all responding agents
4. **Reports per-agent breakdown** with individual confidence scores
5. **Provides actionable items** to address concerns from each agent

## Output Format

System-architect returns a comprehensive plan with:

```markdown
## Plan: {Title}

### Summary
{Plan description}

### Tasks
| # | Task | Agent | Effort |
|---|------|-------|--------|

### Agent Consultations (Comprehensive)

| Agent | Confidence | Status | Key Input |
|-------|------------|--------|-----------|
| backend-developer | 85% | [GOOD] | Pattern exists |
| frontend-developer | 72% | [MODERATE] | Component structure unclear |
| database-advisor | 90% | [HIGH] | Simple query change |

**Aggregate Confidence:** 82%
**Lowest Domain:** Frontend (72%)

### Per-Agent Recommendations

**backend-developer:**
> Follow existing pagination pattern from CompanyController

**frontend-developer:**
> Check MUI DataGrid documentation for built-in pagination

### Risks & Considerations
- {Risk from agent 1}
- {Risk from agent 2}

---

## Plan Confidence: 82%

**Status**: [GOOD]

**To Increase Confidence:**
- [ ] Address frontend concern (+8%)
```

## Related Commands

| Command | Mode | Agent Consultation |
|---------|------|-------------------|
| `/quick-plan` | quick | None (skip consultation) |
| (default plan) | standard | Selective (system-architect decides) |
| `/consult-agents` | comprehensive | ALL relevant agents |

## Comparison: Standard vs Comprehensive

| Aspect | Standard Mode | Comprehensive Mode |
|--------|--------------|-------------------|
| Agent selection | System-architect decides | ALL relevant agents |
| Speed | Faster | Slower |
| Thoroughness | Balanced | Maximum |
| Best for | Most plans | High-risk, complex plans |

## Notes

- System-architect handles all agent invocation and aggregation
- Agents provide ADVISORY input only - they don't make changes
- All agents are consulted in parallel for speed
- Timeout agents are marked "unvalidated" but don't block others
- Results help you make informed decisions before `/act`
