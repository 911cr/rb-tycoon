---
description: Run Codacy static analysis on changed files or specified paths. Checks code quality, security vulnerabilities, and dependency issues.
---

# Codacy Check Command

This command runs comprehensive Codacy analysis on the codebase.

## Usage

```
/codacy-check                    # Analyze all changed files (vs main)
/codacy-check --all              # Analyze entire codebase
/codacy-check --security         # Run Trivy security scan
/codacy-check services/ai-engine # Analyze specific path
```

## What This Command Does

1. **Identify Files to Analyze**
   - If no args: Get changed files vs main branch
   - If path specified: Analyze that path
   - If --all: Analyze entire src/services directories

2. **Run Static Analysis**
   ```
   codacy_cli_analyze(files=[<files>])
   ```

3. **Run Security Scan** (if --security or package files changed)
   ```
   codacy_cli_analyze(tool="trivy", files=[<paths>])
   ```

4. **Report Results**
   - Summary by severity
   - File-by-file breakdown
   - Recommendations for fixes

## Workflow

### Step 1: Determine Scope

```bash
# Get changed files vs main
git diff main...HEAD --name-only --diff-filter=ACMR
```

Filter by file type:
- Backend: `*.cs`, `*.csproj`
- Frontend: `*.ts`, `*.tsx`, `*.scss`
- Config: `*.json`, `*.yml`

### Step 2: Run Codacy Analysis

For each group of changed files, run:
```
codacy_cli_analyze(files=["/path/to/file1.cs", "/path/to/file2.cs"])
```

### Step 3: Security Scan (if applicable)

If package files changed (`*.csproj`, `package.json`), run Trivy:
```
codacy_cli_analyze(tool="trivy", files=["/path/to/service/"])
```

### Step 4: Handle Results

| Severity | Action |
|----------|--------|
| Critical | MUST list with fix recommendations |
| High | MUST list with fix recommendations |
| Medium | List and recommend fixing |
| Low/Info | List as optional improvements |

### Step 5: Handle Errors

If 404 error received:
- Repository may need to be added to Codacy dashboard
- Suggest user visit Codacy to add the repository
- Continue with other analysis if possible

## Output Format

```markdown
## Codacy Analysis Report

**Scope**: {X} files analyzed
**Branch**: {current branch} vs main

### Summary

| Severity | Count |
|----------|-------|
| Critical | X |
| High | X |
| Medium | X |
| Low | X |

### Issues by File

#### path/to/file.cs
- [HIGH] Line 42: Description of issue
- [MEDIUM] Line 88: Description of issue

#### path/to/file.tsx
- [LOW] Line 15: Description of issue

### Security Scan (Trivy)

| Package | Vulnerability | Severity | Fix Version |
|---------|---------------|----------|-------------|
| pkg-name | CVE-XXXX-XXXX | HIGH | 1.2.3 |

### Recommendations

1. **Critical/High Issues**: Must be fixed before merge
2. **Medium Issues**: Should be fixed, create tech-debt task if not
3. **Security Vulnerabilities**: Update packages to fix versions

### Next Steps

- Fix critical/high issues before `/commit`
- Use `/qa-backend` or `/qa-frontend` for full QA with Codacy gate
- Security issues should block deployment
```

## Integration with Workflow

- Use before `/commit` for quality gate
- Use after `/refactor` to verify improvements
- QA agents run Codacy automatically as Gate 7
- Code reviewer validates Codacy results before PR

## CRITICAL: Pagination for Large Result Sets

**Codacy MCP tools return a MAXIMUM of 100 results per API call.** Failing to paginate will miss issues beyond the first 100.

### When to Paginate

| Scenario | Tool | Pagination Required |
|----------|------|---------------------|
| PR issues | `codacy_list_pull_request_issues` | If PR has >100 issues |
| Repo issues | `codacy_list_repository_issues` | ALWAYS (repos often have 100+) |
| Security items | `codacy_search_repository_srm_items` | ALWAYS |
| File list | `codacy_list_files` | Large repos |

### Pagination Pattern

```python
# Step 1: Get expected count first (for verification)
pr_info = codacy_get_repository_pull_request(
    provider="gh",
    organization="911it",
    repository="ai-it-for-msps",
    pullRequestNumber=XXX
)
expected_issues = pr_info.newIssues

# Step 2: Paginate until ALL issues retrieved
all_issues = []
cursor = None
page = 1

while True:
    result = codacy_list_pull_request_issues(
        provider="gh",
        organization="911it",
        repository="ai-it-for-msps",
        pullRequestNumber=XXX,
        cursor=cursor,
        limit=100
    )
    all_issues.extend(result.data)

    if not result.cursor:
        break
    cursor = result.cursor
    page += 1

# Step 3: Verify complete retrieval
if len(all_issues) != expected_issues:
    print(f"WARNING: Got {len(all_issues)}, expected {expected_issues}")
```

### Verification Reporting

Always report pagination status in output:

```markdown
**Codacy Analysis**: Retrieved X issues across N API calls (verified complete)
```

### Red Flag: Exactly 100 Issues

If you see exactly 100 issues in results, **STOP and verify**:
- Did you paginate? (check if cursor was returned)
- Does the count match the expected total from summary endpoints?

**Missing issues due to lack of pagination is a CRITICAL ERROR.**
