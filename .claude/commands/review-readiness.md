---
description: Assess production readiness with technical standards review
---

# Production Readiness Review

Launch the **staff-engineer-advisor** agent to:

1. Review code for production standards
2. Validate test coverage (>80% required)
3. Check API performance (<1s p95)
4. Assess company data isolation (company_uuid filtering)
5. Review observability (logging, metrics, tracing)
6. Evaluate scalability and reliability
7. Identify technical risks

## What You'll Get

- Technical focus area scores (0-10 scale)
- Production readiness assessment (Ready/Not Ready/Conditional)
- Blockers and critical issues
- Recommendations with severity
- Risk assessment
- Detailed technical review report

## Technical Focus Areas

1. **Scalability** - Handles growth, horizontal scaling
2. **Reliability** - Error handling, retries, circuit breakers
3. **Performance** - API <1s, optimized queries, caching
4. **Security** - Multi-tenant isolation, input validation, secrets
5. **Observability** - Structured logging, metrics, distributed tracing
6. **Testing** - >80% coverage, integration tests, E2E tests
7. **Multi-Tenancy** - Data isolation, company_uuid filtering
8. **Cost** - Resource usage, query efficiency

## When to Use

- Before major production deployment
- After significant architectural changes
- Planning production rollout
- Need technical standards validation
- Before marking feature as "production-ready"

## Example Usage

```
/review-readiness AI-68
```

## Next Steps

Based on readiness:
- **Ready**: Proceed with `/review-code` and PR creation
- **Not Ready**: Address blockers with `/implement-jira-task AI-XXX` (for fixes)
- **Conditional**: Fix critical issues via `/act`, re-run review
