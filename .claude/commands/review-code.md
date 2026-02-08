---
description: Comprehensive 5-part code review with GitHub PR creation on approval
---

## CRITICAL: Orchestrator Delegation Required

**The orchestrator MUST NOT perform code reviews directly.**

When `/review-code` is invoked, the orchestrator MUST:

1. Use Task tool to spawn senior-code-reviewer agent:
```
Task(
  subagent_type="senior-code-reviewer",
  prompt="Perform comprehensive 5-part code review for {JIRA_KEY}. Apply severity classification, check QA labels, and create GitHub PR if approved.",
  description="Code review for {JIRA_KEY}"
)
```

2. Wait for agent to complete
3. Report result to user (approval status, PR link if created)

**FORBIDDEN in orchestrator thread:**
- Directly reviewing code quality
- Creating GitHub PRs
- Transitioning Jira issues for code review
- Applying code-review labels

---

# Senior Code Review

Launch the **senior-code-reviewer** agent to:

1. Verify QA labels show passing (`qa-backend-passed` and/or `qa-frontend-passed`)
2. Apply 5-part review framework
3. Categorize issues by severity (Blocker/Critical/Major/Minor/Suggestion)
4. Create GitHub PR if approved
5. Transition Jira to "Ready to Release"
6. Request changes if blockers/critical issues found

## 5-Part Review Framework

**1. Document Alignment** - CLAUDE.md, .cursor/rules, architecture patterns
**2. Code Quality** - SOLID, clean code, separation of concerns
**3. Testing Strategy** - Coverage >80%, edge cases, company isolation tests
**4. Performance & Scalability** - API <1s, optimized queries, caching
**5. Security Audit** - OWASP, company data isolation (company_uuid filtering), input validation

## Severity Classification

🔴 **BLOCKER** - Must fix before merge (security vulnerabilities, data leakage, breaking bugs)
🟠 **CRITICAL** - Should fix before merge (poor error handling, missing tests, performance issues)
🟡 **MAJOR** - Should fix soon (code smells, missing edge cases, tech debt)
🟢 **MINOR** - Nice to have (naming improvements, formatting, comments)
💡 **SUGGESTION** - Optional (alternative approaches, micro-optimizations)

## When to Use

- After QA passes (backend and/or frontend)
- Ready to create pull request
- Before deployment to production
- Need comprehensive code review

## Example Usage

```
/review-code AI-68
```

## Prerequisites

Agent will **block review** if:
- QA not passed (no `qa-backend-passed` or `qa-frontend-passed` labels)
- QA failed (has `qa-backend-failed` or `qa-frontend-failed` labels)

## CRITICAL: Code Review Timing

**Code review happens ONCE at the END of the plan** - after ALL tasks are complete and ALL QA has passed.

- Do NOT review individual tasks in isolation
- Wait for entire plan completion before `/review-code`
- Creates a SINGLE PR for the entire plan
- **NEVER auto-merge** - PR requires human approval

## Agent Will

1. Verify QA labels (block if not passed)
2. Read Jira task description and acceptance criteria
3. Review `git diff main...HEAD` to understand scope
4. Apply 5-part framework systematically
5. Document findings with severity and file:line references
6. Provide fix suggestions with code examples
7. Make decision: **Approve** or **Request Changes**

**If Approved:**
8. Add Jira comment with executive summary
9. Remove any `code-review-*` labels
10. Add label `code-review-approved`
11. Read Jira comments to extract QA test reports
12. Check available Jira transitions
13. Create GitHub PR with QA data from Jira
14. Update Jira with PR link
15. Transition Jira to "Ready to Release" (or similar)

**If Changes Needed:**
8. Create Jira subtasks for blockers/critical issues
9. Add label `code-review-changes-requested`
10. Block PR creation
11. List required fixes

## GitHub PR Structure

```markdown
## Summary
[Extract from Jira or write based on changes]

## Changes
- Added: [new features/files]
- Modified: [changed behavior]
- Fixed: [bug fixes]

## Testing

### Backend QA
[Extract from Jira "Backend QA Test Results"]
- Unit Tests: {actual counts}
- Coverage: {actual percentage}
- Multi-Tenant Security: PASS

### Frontend QA
[Extract from Jira "Frontend QA Test Results"]
- Component Tests: {actual counts}
- Accessibility: WCAG AA PASS
- Coverage: {actual percentage}

### Code Review
- Document Alignment: PASS
- Code Quality: PASS
- Testing Strategy: PASS
- Performance: PASS
- Security Audit: PASS

## Breaking Changes
[If any, describe. Otherwise: None]

## Deployment Notes
[Migration steps, config changes. Otherwise: Standard deployment]

## Jira
Closes AI-XXX
```

## Review Report Includes

- Executive summary with decision
- 5-part review scores
- Issues categorized by severity
- Specific file:line references
- Code examples for fixes
- Strengths and positive feedback
- **GitHub PR link** (if approved)
- **Jira status transition** confirmation
- Next steps
- Label applied

## Next Steps

- **Approved**: PR created, Jira transitioned, ready for release
- **Changes Requested**: Fix subtasks, re-run `/review-code`
