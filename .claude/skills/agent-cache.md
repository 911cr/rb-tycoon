---
skill-name: agent-cache
priority: 2
trigger: |
  Activate when:
  - Consulting advisory agents during planning
  - Multiple agents being consulted in parallel
  - User requests plan consultation status
  - Cache hit/miss reporting needed
  - Checking cached recommendations
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
forbidden-tools:
  - Edit
  - NotebookEdit
description: |
  Manages caching for multi-agent plan consultations.
  Priority 2 runs after plan-mode (0) but before orchestrator (3).
---

# Agent Cache Skill

Manages caching of multi-agent consultation results to improve performance and reduce redundant consultations.

## Cache Architecture

### Storage: Hybrid Approach

1. **Primary**: File-based cache in `.claude/cache/plan-consultations/{plan-hash}/`
2. **Secondary**: Summary embedded in `docs/plan/*_state.md`

### Directory Structure

```
.claude/cache/
  plan-consultations/
    {plan-hash}/
      metadata.json
      agent-recommendations/
        backend-developer.json
        security-engineer-advisor.json
      confidence-scores/
        aggregated.json
      domain-detection.json
```

### Cache Key Format

```
{session_id}:{plan_hash}:{agent_name}:{cache_type}
```

## TTL Strategy

| Cache Type | TTL | Invalidation |
|------------|-----|--------------|
| Agent Recommendations | 4 hours | Plan changed |
| Confidence Scores | 24 hours | Plan changed, reconsult |
| File Analysis | 1 hour | Git commit |
| Domain Detection | 4 hours | Plan description changed |

## Invalidation Rules

| Event | Action |
|-------|--------|
| Plan content changed | Invalidate ALL for that plan |
| Git commit on affected files | Invalidate file analysis |
| User requests "reconsult" | Invalidate specific agent |
| TTL expired | Auto-invalidate |
| 80% context window | LRU cleanup |

## Cached Confidence Schema

```json
{
  "agentName": "backend-developer",
  "consultedAt": "2024-01-15T10:30:00Z",
  "confidence": {
    "score": 85,
    "status": "GOOD",
    "effortPercent": 0.60,
    "factors": {
      "increasing": [{"id": "file_read", "value": 10}],
      "decreasing": [{"id": "security_not_analyzed", "value": -10}]
    },
    "domainWeight": 1.2,
    "weightedScore": 102
  },
  "recommendations": [
    "Follow existing pagination pattern from CompanyController"
  ],
  "questions": [
    {
      "to": "database-advisor",
      "question": "Composite vs separate index?",
      "required": true
    }
  ]
}
```

## Cache Operations

### Check Cache

Before consulting an agent:
1. Generate plan hash from plan content
2. Check if `.claude/cache/plan-consultations/{plan-hash}/{agent-name}.json` exists
3. Verify TTL has not expired
4. Return cached result if valid

### Write Cache

After agent consultation:
1. Create cache directory if not exists
2. Write agent result to JSON file
3. Update `metadata.json` with timestamp

### Invalidate Cache

On plan change:
1. Detect plan content change (hash mismatch)
2. Delete entire `{plan-hash}/` directory
3. Log invalidation reason

## Partial Cache Handling

When some domains cached, others not:
- Calculate partial composite from cached domains
- Recommend missing consultations
- Display with caveat: "Partial confidence (3/5 domains)"

## Usage

### Checking Cache Status

```markdown
### Cache Status

| Domain | Agent | Cached | Age | Expires |
|--------|-------|--------|-----|---------|
| Backend | backend-developer | Yes | 2h | 2h |
| Security | security-engineer-advisor | No | - | - |

**Cache Coverage:** 1/2 domains (50%)
```

### Forcing Re-consultation

Use `/consult-agents --force` to bypass cache and re-consult all agents.

## Integration

This skill works with:
- `plan-mode.md` (priority 0) - Triggers consultation
- `plan-state-tracker.md` - Stores question tracking
- `consult-agents.md` command - Executes parallel consultation
