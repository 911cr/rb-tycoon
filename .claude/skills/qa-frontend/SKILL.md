---
name: qa-frontend
description: Run comprehensive frontend testing with accessibility validation and responsive design checks
user-invocable: false
---

# Frontend QA

Instructions for the main thread to spawn the **frontend-qa** agent for comprehensive quality validation.

## Spawning Instructions

When this skill is invoked, the main thread should spawn the frontend-qa agent:

```
Task(
  subagent_type="frontend-qa",
  prompt="""
  ## Frontend QA Request

  **Jira Task**: {jira_key}
  **Worktree Path**: {worktree_path if applicable}

  Run comprehensive frontend QA with ALL quality gates.
  See /qa-frontend command for full requirements.

  MANDATORY: ALL gates must pass before adding qa-frontend-passed label.
  """,
  description="Run frontend QA for {jira_key}"
)
```

## What the Agent Does

1. Identify changed frontend code (`git diff main...HEAD`)
2. Create/update component and E2E tests
3. Validate WCAG AA accessibility compliance
4. Test responsive design (mobile/tablet/desktop)
5. Run tests via Docker
6. Check code coverage (>80% target)
7. Update Jira with test results

## Testing Scope

**What Gets Tested:**
- components/**/*.tsx -> Component tests
- app/**/page.tsx -> E2E tests (if critical flows)
- hooks/*.ts -> Hook tests
- lib/*.ts -> Utility tests

**Only Changed Files:**
Uses `git diff main...HEAD --name-only` to scope testing

## Component Testing

- Rendering with various props
- User interactions (click, type, select, drag)
- State changes and effects
- Conditional rendering
- Error boundaries
- Form validation
- Loading and error states

## Edge Cases Tested

- Null/undefined props
- Empty data sets
- Maximum data sets (1000+ items)
- Invalid prop types
- Extreme viewport sizes
- Rapid user interactions
- Network failures
- Long text content
- Special characters in user input

## Accessibility Testing (WCAG AA)

Using `@testing-library/react` and `jest-axe`:
- Keyboard navigation (Tab, Enter, Space, Escape, Arrow keys)
- ARIA attributes (role, aria-label, aria-describedby)
- Semantic HTML (nav, main, article, button vs div)
- Screen reader announcements (aria-live regions)
- Focus management (modals, dialogs)
- Touch targets (min 44x44px)
- Color contrast ratios (4.5:1 text, 3:1 UI)

## Test Results Include

- Test execution summary (X passed, Y failed, Z skipped)
- Code coverage for changed files (%)
- Accessibility validation (WCAG AA checklist)
- Responsive design validation (mobile/tablet/desktop)
- MUI integration confirmation
- Subtasks created for issues (with Jira keys)
- QA label applied
- Next steps recommendation

## Labels Applied

- `qa-frontend-passed` - All gates passed, proceed to code review
- `qa-frontend-failed` - Tests failed, developer fixes required
- `qa-frontend-blocked` - Blockers found, resolve first

## Next Steps

- **QA Passed**: Proceed to `/review-code`
- **QA Failed**: Fix issues in subtasks, re-run `/qa-frontend`
- **QA Blocked**: Resolve blockers, re-run
