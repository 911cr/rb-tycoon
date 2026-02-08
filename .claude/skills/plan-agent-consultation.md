---
skill-name: plan-agent-consultation
priority: 3
trigger: |
  Activate during plan mode when:
  - Building or refining a plan that affects multiple domains
  - User explicitly requests agent consultation ("consult agents", "get expert input")
  - Plan complexity warrants multi-agent perspective (3+ affected areas)
  - User enters plan mode (shift+tab) for non-trivial changes

  Do NOT activate for:
  - Quick plans (user says "quick plan" or "simple plan")
  - Single-domain trivial changes
  - When user explicitly skips consultation ("skip consultation", "no agents")
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - WebSearch
  - WebFetch
  - TodoWrite
  - mcp__atlassian__*
  - mcp__postgres-local__*
  - mcp__docker__*
forbidden-tools:
  - Edit
  - Write
  - NotebookEdit
description: |
  Orchestrates multi-agent consultation during plan mode to gather domain-specific
  perspectives and confidence assessments from specialized agents. Aggregates
  individual agent confidences into an overall plan confidence with breakdown.
  Priority 3 activates alongside orchestrator mode during planning.
---

# Plan Agent Consultation Skill

## Purpose

This skill enhances plan mode by consulting specialized agents during planning, not just during implementation. Each agent provides their domain-specific perspective, risks, and confidence assessment, which are aggregated into a comprehensive plan confidence report.

## IMPORTANT: Advisory Mode Only

During plan mode consultation, agents operate in **ADVISORY MODE**:
- They analyze and provide recommendations
- They do NOT make changes or take actions
- They provide confidence assessments and risk factors
- They identify concerns and considerations from their domain

## Domain Detection

### Automatic Domain Detection

Detect affected domains based on:

1. **File Patterns** (from plan description and analysis):

| Domain | Patterns | Agent |
|--------|----------|-------|
| Backend | `services/*-service/**/*.cs`, `**/Controllers/**`, `**/Services/**/*.cs`, `**/Repositories/**` | `backend-developer` |
| Frontend | `services/admin-dashboard/**/*.tsx`, `services/web-portal/**`, `**/components/**`, `**/*.module.scss` | `frontend-developer` |
| Database | `services/db/migrations_v2/**/*.sql`, `**/Repositories/**`, schema changes | `database-advisor` |
| Infrastructure | `docker-compose.yml`, `Dockerfile*`, `**/k8s/**`, CI/CD | `devops-engineer` |
| Security | auth, encryption, JWT, RLS, multi-tenant isolation | `security-engineer-advisor` |
| AI/Prompts | Azure OpenAI, prompts, tokens, RAG, ai-engine | `ai-prompt-advisor` |
| Architecture | New services, major refactoring, cross-service changes | `system-architect` |
| Production | Critical features, breaking changes, high-risk | `staff-engineer-advisor` |

2. **Keyword Detection** (from `jira-config.json` advisoryTriggers):

```json
{
  "database": ["postgresql", "migration", "index", "query optimization", ...],
  "security": ["authentication", "encryption", "multi-tenant", ...],
  "aiPrompt": ["azure openai", "prompt engineering", "token optimization", ...],
  "network": ["grpc", "websocket", "mtls", "load balancer", ...],
  "infrastructure": ["docker", "kubernetes", "ci/cd", ...]
}
```

### Consultation Decision Matrix

| Plan Scope | Affected Domains | Agents to Consult |
|------------|------------------|-------------------|
| Trivial | 1 domain, <3 files | Skip consultation (use single confidence) |
| Simple | 1-2 domains | Consult primary domain agent only |
| Standard | 2-3 domains | Consult all affected domain agents |
| Complex | 4+ domains | Consult all affected + system-architect + staff-engineer-advisor |
| Critical | Security/breaking changes | Always include security-engineer-advisor |

## Consultation Workflow

### Phase 1: Domain Analysis

1. **Analyze the plan** to identify:
   - Files that will be modified
   - Services affected
   - Database changes required
   - Security implications
   - Infrastructure changes

2. **Map to domains**:
   ```
   Plan: "Add user pagination to API and dashboard"

   Detected Domains:
   - Backend (services/auth-service/Controllers/UsersController.cs)
   - Frontend (services/admin-dashboard/src/components/users/...)
   - Database (pagination query changes)
   ```

3. **Select agents for consultation**:
   ```
   Required Consultations:
   - backend-developer (API changes)
   - frontend-developer (UI changes)
   - database-advisor (query optimization)
   ```

### Phase 2: Agent Consultation

For each selected agent, request their advisory input:

**Consultation Request Format:**
```
## Plan Consultation Request

**Context:** [Plan summary and affected areas for this agent's domain]

**Questions:**
1. What are the key implementation considerations in your domain?
2. What risks or concerns do you identify?
3. What is your confidence level (0-100%) for this plan in your domain?
4. What would increase your confidence?

**Provide:**
- Domain-specific confidence percentage
- Key factors affecting confidence (positive and negative)
- Recommendations or concerns
```

**Agent Response Format (Expected):**
```
## Domain Consultation: [Agent Name]

**Domain Confidence: XX%**

**Factors Increasing Confidence:**
- [Domain-specific positive factors]

**Factors Decreasing Confidence:**
- [Domain-specific concerns]

**Recommendations:**
- [Specific guidance from this domain]

**Risks Identified:**
- [Domain-specific risks]
```

### Phase 3: Confidence Aggregation

Aggregate individual agent confidences using weighted average:

**Base Weights:**
| Domain | Weight | Rationale |
|--------|--------|-----------|
| Architecture | 1.5x | Foundational decisions affect everything |
| Security | 1.3x | Security gaps are critical |
| Production Readiness | 1.2x | Production impact is high |
| Backend/Frontend | 1.0x | Standard implementation |
| Database | 1.1x | Data integrity is important |
| Infrastructure | 1.0x | Standard weight |
| AI/Prompts | 1.0x | Standard weight |

**Aggregation Formula:**
```
Overall Confidence = Sum(domain_confidence * weight) / Sum(weights)
```

**Weakest Link Rule:**
If any domain confidence is below 60%, flag it prominently as the blocking concern.

## Output Format

### Comprehensive Plan Confidence Report

```markdown
---

## Plan Confidence: XX% [STATUS]

### Domain Breakdown

| Domain | Agent | Confidence | Status | Key Concern |
|--------|-------|------------|--------|-------------|
| Architecture | system-architect | 90% | [HIGH] | - |
| Backend | backend-developer | 85% | [GOOD] | - |
| Frontend | frontend-developer | 72% | [MODERATE] | Component structure unclear |
| Database | database-advisor | 88% | [GOOD] | - |
| Security | security-engineer-advisor | 80% | [GOOD] | - |

**Weighted Average:** 82%
**Lowest Domain:** Frontend (72%) - requires attention

### Aggregate Factors

**Increasing Confidence:**
- [From system-architect] Clean service boundaries, follows existing patterns
- [From backend-developer] Similar pagination exists in CompanyController
- [From database-advisor] Efficient keyset pagination recommended
- [From security-engineer-advisor] company_uuid filtering well-established

**Decreasing Confidence:**
- [From frontend-developer] MUI DataGrid pagination approach unclear (-8%)
- [From staff-engineer-advisor] Performance benchmarks not defined (-5%)

### Agent Recommendations

**system-architect:**
> Follow existing pagination pattern from CompanyService

**database-advisor:**
> Use keyset pagination instead of OFFSET for large datasets

**frontend-developer:**
> Verify MUI DataGrid built-in pagination before custom implementation

### To Increase Overall Confidence

1. [ ] Read UsersList.tsx to confirm component structure (+5% frontend)
2. [ ] Define performance requirements (target p95 latency) (+3% production)
3. [ ] Check MUI DataGrid documentation for pagination (+5% frontend)

---
```

## Quick Plan Mode

When user requests a quick plan, skip multi-agent consultation:

**Triggers:**
- "quick plan"
- "simple plan"
- "no consultation"
- "skip agents"

**Behavior:**
- Use standard single-perspective confidence calculation
- Note: "Quick plan mode - agent consultation skipped"
- Provide option: "Run /consult-agents to get domain-specific perspectives"

## Integration with Plan Mode Confidence

This skill works WITH `plan-mode-confidence` skill:

1. `plan-mode-confidence` defines the confidence format and thresholds
2. `plan-agent-consultation` enhances it with multi-agent perspectives
3. Both skills contribute to the final confidence report

**Execution Order:**
1. Orchestrator enters plan mode
2. `plan-agent-consultation` detects domains and consults agents
3. `plan-mode-confidence` formats and validates the final output
4. User sees comprehensive multi-agent confidence report

## Commands Integration

| Command | Behavior with Agent Consultation |
|---------|----------------------------------|
| Plan Mode (shift+tab) | Auto-consult based on complexity |
| `/consult-agents` | Force agent consultation |
| `/quick-plan` | Skip consultation, single perspective |
| `/act` | Requires 80% overall confidence |
| `/create-plan-in-jira` | Shows domain breakdown in task descriptions |

## Example: Full Consultation Flow

**User Request:** "Add API rate limiting per company"

**Step 1: Domain Detection**
```
Affected Domains:
- Backend (middleware, rate limit logic)
- Database (rate limit tracking)
- Security (multi-tenant enforcement)
- Infrastructure (Redis for rate counters)
- Architecture (cross-cutting concern)
```

**Step 2: Agent Consultations**

```
Consulting system-architect...
  -> Recommends middleware pattern, Redis for counters
  -> Confidence: 88%

Consulting backend-developer...
  -> Can implement middleware pattern
  -> Needs to understand existing middleware chain
  -> Confidence: 75%

Consulting database-advisor...
  -> Redis preferred over PostgreSQL for counters
  -> Needs schema for persistent limits
  -> Confidence: 85%

Consulting security-engineer-advisor...
  -> Critical: company_uuid must be validated
  -> Concern: Rate limit bypass attacks
  -> Confidence: 80%

Consulting devops-engineer...
  -> Redis already in docker-compose
  -> No infrastructure changes needed
  -> Confidence: 95%
```

**Step 3: Aggregated Output**

```markdown
## Plan Confidence: 83% [GOOD CONFIDENCE]

### Domain Breakdown

| Domain | Agent | Confidence | Status |
|--------|-------|------------|--------|
| Architecture | system-architect | 88% | [GOOD] |
| Backend | backend-developer | 75% | [MODERATE] |
| Database | database-advisor | 85% | [GOOD] |
| Security | security-engineer-advisor | 80% | [GOOD] |
| Infrastructure | devops-engineer | 95% | [HIGH] |

**Lowest Domain:** Backend (75%)
- Concern: Middleware chain needs analysis

### To Reach 80% Backend Confidence
1. [ ] Read existing middleware in api-gateway
2. [ ] Understand request pipeline order
```

## Remember

1. **Advisory only** - Agents provide perspective, not implementation
2. **Efficiency** - Don't over-consult for trivial plans
3. **Transparency** - Show which agents were consulted and why
4. **Actionable** - "To Increase Confidence" should be specific
5. **Aggregation** - Weighted average with weakest-link visibility
6. **Quick mode** - Allow skipping for simple plans
