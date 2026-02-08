---
name: qa-backend
description: Run comprehensive backend testing with migration verification, test execution, and company isolation validation
user-invocable: false
---

# Backend QA

Instructions for the main thread to spawn the **backend-qa** agent for comprehensive quality gate verification.

## Spawning Instructions

When this skill is invoked, the main thread should spawn the backend-qa agent:

```
Task(
  subagent_type="backend-qa",
  prompt="""
  ## Backend QA Request

  **Jira Task**: {jira_key}
  **Worktree Path**: {worktree_path if applicable}

  Run comprehensive backend QA with ALL quality gates.
  See /qa-backend command for full requirements.

  MANDATORY: ALL gates must pass before adding qa-backend-passed label.
  """,
  description="Run backend QA for {jira_key}"
)
```

## Quality Gates (ALL MUST PASS)

| Gate | Requirement | Blocking |
|------|-------------|----------|
| Migration Verification | All migrations in `services/db/migrations_v2/` succeed | YES |
| Unit Tests | ALL tests pass (0 failures) | YES |
| Integration Tests | ALL tests pass for modified services | YES |
| API Contract Verification | Integration tests match API contracts | YES |
| Code Coverage | >= 80% for changed files | YES |
| Company Isolation | company_uuid filtering verified | YES |

**CRITICAL**: QA will NOT approve changes unless ALL gates pass.

## What the Agent Does

1. **Identify Scope**: `git diff main...HEAD --name-only`
2. **Check for Migrations**: Verify any new migrations in `services/db/migrations_v2/`
3. **Migration Verification** (if applicable):
   - Rebuild and run migrations-runner (`docker compose up --build migrations-runner`)
   - Check docker logs for `[OK]` status
   - BLOCK if any migration fails
4. **Run Unit Tests**: Execute all unit tests for modified services
5. **Run Integration Tests**: Execute integration tests for modified services
6. **Verify API Contracts**: Ensure integration tests match any changed APIs
7. **Check Code Coverage**: Collect and verify >= 80%
8. **Validate Company Isolation**: Verify company_uuid filtering
9. **Update Jira**: Document all gate results

## Integration Test Projects

| Service | Integration Test Project |
|---------|-------------------------|
| auth-service | `tests/AuthService.IntegrationTests` |
| company-service | `tests/CompanyService.IntegrationTests` |
| ai-engine | `tests/AiEngine.IntegrationTests` |
| workflow-engine | `tests/WorkflowEngine.IntegrationTests` |
| integration-service | `tests/IntegrationService.IntegrationTests` |
| script-management | `tests/ScriptManagement.IntegrationTests` |
| data-ingestion | `tests/DataIngestion.IntegrationTests` |
| notifications-service | `tests/NotificationsService.IntegrationTests` |

## Decision Matrix

| Migration | Unit Tests | Integration Tests | Result |
|-----------|------------|-------------------|--------|
| PASS/N/A | PASS | PASS | **qa-backend-passed** |
| FAIL | any | any | **qa-backend-blocked** |
| any | FAIL | any | **qa-backend-failed** |
| any | any | FAIL | **qa-backend-failed** |

## Next Steps

- **QA Passed**: Proceed to `/review-code`
- **QA Failed**: Fix issues in subtasks, re-run `/qa-backend`
- **QA Blocked**: Resolve migration/contract blockers first
