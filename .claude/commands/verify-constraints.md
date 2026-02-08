---
description: Verify that all critical constraints from a plan were satisfied during implementation
---

# /verify-constraints Command

Verify that all **user requirements** (from `user-requirements.md`) and **critical constraints** (from `critical-constraints.md`) were satisfied during implementation. User requirements are WORD OF GOD - implementation must match EXACTLY.

This command provides the final verification between QA and code review.

## Usage

```bash
/verify-constraints {plan-id}              # Verify by plan ID
/verify-constraints AI-XXX                 # Verify by Jira task (extracts plan from description)
/verify-constraints                        # Verify most recent plan
```

## Workflow

### Phase 1: Locate Plan Documents

1. **If plan-id provided:**
   ```
   Read("docs/plan/{plan-id}/user-requirements.md")      # CRITICAL - WORD OF GOD
   Read("docs/plan/{plan-id}/critical-constraints.md")
   ```

2. **If Jira key provided:**
   ```
   jira_get_issue(issueKey="AI-XXX", fields=["description"])
   # Extract plan-id from description (look for docs/plan/{plan-id}/)
   Read("docs/plan/{plan-id}/user-requirements.md")      # CRITICAL - WORD OF GOD
   Read("docs/plan/{plan-id}/critical-constraints.md")
   ```

3. **If no argument:**
   ```
   # Find most recent plan directory
   Glob("docs/plan/PLAN-*/user-requirements.md")
   Glob("docs/plan/PLAN-*/critical-constraints.md")
   # Use the most recently modified
   ```

**IMPORTANT**: `user-requirements.md` contains VERBATIM user input that MUST be matched EXACTLY.

### Phase 2: Verify User Requirements (WORD OF GOD)

**This phase verifies user requirements FIRST. User input is WORD OF GOD.**

For each requirement (UR-1, UR-2, etc.) in `user-requirements.md`:

1. **Read the verbatim user quote** - EXACT words the user used
2. **Read the acceptance criteria** - what must be true
3. **Search for implementation evidence:**
   ```
   # For routes
   Grep(pattern="{exact route from user}", path="services/*/Controllers/")

   # For database columns
   Grep(pattern="{exact column name from user}", path="services/db/migrations_v2/")

   # For behaviors
   Grep(pattern="{behavior pattern}", path="services/*/Services/")
   ```
4. **Compare VERBATIM** - implementation must match user's exact words
5. **Determine status:**
   - MET: Implementation matches user's exact specification
   - VIOLATED: Implementation differs from user's exact specification
   - UNABLE TO VERIFY: Cannot find relevant implementation

**User Requirements Verification Report:**

```markdown
### User Requirements Verification

| Req ID | Verbatim User Quote | Status | Evidence |
|--------|---------------------|--------|----------|
| UR-1 | "The route should be `/api/v1/companies/...`" | MET | `AssetController.cs:45` |
| UR-2 | "Add a `storage_path` column" | VIOLATED | Found `minio_path` instead |

**User Requirements Summary:** X MET, Y VIOLATED, Z Unable to Verify
```

**CRITICAL**: If ANY user requirement is VIOLATED, the verification FAILS regardless of other results.

### Phase 3: Parse Critical Constraints

Extract all constraints from the critical-constraints.md file:

```
MUST_DO = [
  { id: "MD-1", constraint: "...", source_agent: "...", details: "..." },
  { id: "MD-2", constraint: "...", source_agent: "...", details: "..." },
]

MUST_NOT = [
  { id: "MN-1", constraint: "...", consequence: "...", source_agent: "..." },
  { id: "MN-2", constraint: "...", consequence: "...", source_agent: "..." },
]

PRESERVE = [
  { id: "P-1", resource: "...", type: "...", reason: "..." },
  { id: "P-2", resource: "...", type: "...", reason: "..." },
]
```

### Phase 4: Verify MUST DO Constraints

For each MUST DO constraint:

1. **Search codebase** for evidence the action was taken:
   ```
   Grep(pattern="{relevant pattern}", path="{relevant path}")
   ```

2. **Check Jira comments** for verification statements:
   ```
   jira_get_issue(issueKey="AI-XXX", expand=["changelog", "comments"])
   # Look for "CONSTRAINT VERIFICATION" comments
   ```

3. **Review git history** for relevant commits:
   ```bash
   git log --oneline --grep="{constraint keyword}" -- {relevant files}
   ```

4. **Determine status:**
   - COMPLETED: Evidence found that constraint was satisfied
   - FAILED: Evidence shows constraint was not satisfied
   - UNKNOWN: Unable to determine (needs manual review)

### Phase 5: Verify MUST NOT Constraints

For each MUST NOT constraint:

1. **Search codebase** for violations:
   ```
   Grep(pattern="{prohibited pattern}", path="{relevant path}")
   ```

2. **Check for absence** of prohibited changes:
   ```bash
   git diff {base-branch}...HEAD -- {relevant files}
   ```

3. **Determine status:**
   - VERIFIED: No evidence of violation found
   - VIOLATED: Evidence of prohibited action found
   - UNKNOWN: Unable to determine

### Phase 6: Verify PRESERVE Constraints

For each PRESERVE resource:

1. **Check if resource was modified:**
   ```bash
   git diff {base-branch}...HEAD -- {resource path}
   ```

2. **For database tables:**
   ```
   mcp__postgres-local__query(sql="SELECT column_name FROM information_schema.columns WHERE table_name = '{table}'")
   # Compare to expected schema
   ```

3. **Determine status:**
   - INTACT: Resource unchanged
   - MODIFIED: Resource was changed (violation)
   - DELETED: Resource was removed (violation)

### Phase 7: Generate Report

```markdown
## Constraint Verification Report: {plan-id}

**Plan:** `docs/plan/{plan-id}/`
**Verified:** {ISO timestamp}
**Overall Status:** {PASS | FAIL | NEEDS REVIEW}

### User Requirements (WORD OF GOD)

| Req ID | Verbatim User Quote | Status | Evidence |
|--------|---------------------|--------|----------|
| UR-1 | "{exact user quote, first 100 chars}..." | MET | {file:line} |
| UR-2 | "{exact user quote, first 100 chars}..." | VIOLATED | {what was found instead} |

**User Requirements Score:** {X}/{total} MET

### MUST DO Constraints

| ID | Constraint | Status | Evidence |
|----|------------|--------|----------|
| MD-1 | {constraint} | COMPLETED | {evidence} |
| MD-2 | {constraint} | FAILED | {why failed} |

**MUST DO Score:** {X}/{total} completed

### MUST NOT Constraints

| ID | Constraint | Status | Verification |
|----|------------|--------|--------------|
| MN-1 | {prohibition} | VERIFIED | {how verified} |
| MN-2 | {prohibition} | VIOLATED | {what violated} |

**MUST NOT Score:** {X}/{total} verified

### PRESERVE Constraints

| ID | Resource | Status | Evidence |
|----|----------|--------|----------|
| P-1 | {resource} | INTACT | No changes in git diff |
| P-2 | {resource} | MODIFIED | {what changed} |

**PRESERVE Score:** {X}/{total} intact

### Summary

| Category | Passed | Failed | Unknown | Total |
|----------|--------|--------|---------|-------|
| **USER REQUIREMENTS** | {n} | {n} | {n} | {n} |
| MUST DO | {n} | {n} | {n} | {n} |
| MUST NOT | {n} | {n} | {n} | {n} |
| PRESERVE | {n} | {n} | {n} | {n} |
| **TOTAL** | {n} | {n} | {n} | {n} |

**CRITICAL**: If ANY user requirement is VIOLATED, overall status is FAIL.

### Recommendation

{Based on results:}
- **PASS**: All constraints satisfied. Proceed to QA.
- **FAIL**: {X} constraints not satisfied. Block until resolved.
- **NEEDS REVIEW**: {X} constraints could not be verified automatically.

### Failed Constraints (if any)

{For each failed constraint, provide:}
- What was expected
- What was found
- Recommended remediation

### Next Steps

{Based on outcome:}
1. If PASS: `/qa-backend {jira-key}` or `/qa-frontend {jira-key}`
2. If FAIL: Fix issues, then re-run `/verify-constraints`
3. If NEEDS REVIEW: Manual verification required for listed items
```

### Phase 8: Update Jira

Add verification report as a Jira comment:

```
jira_add_comment(
  issueKey="AI-XXX",
  body="## Constraint Verification Report\n\n{summary}\n\nFull report: `docs/plan/{plan-id}/constraint-verification-{timestamp}.md`"
)
```

If all constraints pass, add label:
```
jira_edit_issue(issueKey="AI-XXX", fields={"labels": ["constraints-verified"]})
```

## Example Usage

```
User: /verify-constraints PLAN-20251224-user-pagination

Claude: Verifying constraints for PLAN-20251224-user-pagination...

Reading constraints file...
Found 3 MUST DO, 2 MUST NOT, 4 PRESERVE constraints.

Verifying MUST DO constraints...
- MD-1: Add company_uuid filter to all queries... COMPLETED
- MD-2: Use IDatabaseConnectionHandler for connections... COMPLETED
- MD-3: Implement pagination with limit/offset... COMPLETED

Verifying MUST NOT constraints...
- MN-1: Do not modify company_tokens table... VERIFIED
- MN-2: Do not expose internal IDs in API... VERIFIED

Verifying PRESERVE constraints...
- P-1: companies table schema... INTACT
- P-2: auth-service API contract... INTACT
- P-3: user_roles table... INTACT
- P-4: JWT token format... INTACT

## Constraint Verification Report

**Overall Status:** PASS

All 9 constraints verified successfully.

| Category | Passed | Failed | Total |
|----------|--------|--------|-------|
| MUST DO | 3 | 0 | 3 |
| MUST NOT | 2 | 0 | 2 |
| PRESERVE | 4 | 0 | 4 |

Recommendation: Proceed to QA.

Next step: `/qa-backend AI-456`
```

## Error Handling

### Constraints File Not Found
```
Error: Could not find critical-constraints.md for plan {plan-id}.

Possible reasons:
1. Plan was created before constraint tracking was implemented
2. Plan ID is incorrect
3. Constraints file was not generated

Options:
1. Create constraints retroactively from plan state file
2. Proceed without constraint verification (not recommended)
```

### Unable to Verify Constraint
```
Warning: Could not automatically verify constraint {id}.

Constraint: {description}
Reason: {why unable to verify}

This constraint requires manual verification.
Please confirm: Was this constraint satisfied? (yes/no)
```

## Related Commands

- `/create-plan-in-jira` - Creates constraints file during planning
- `/act` - Requires constraint acknowledgment before implementation
- `/advisory-review` - Gets advisory agents to review implementation
- `/qa-backend` - Backend QA (run after constraints verified)
- `/qa-frontend` - Frontend QA (run after constraints verified)
