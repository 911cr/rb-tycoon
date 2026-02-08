---
skill-name: code-change-interceptor
priority: 0
trigger: |
  Activate when the user's request involves code modifications:
  - "fix", "change", "modify", "update", "edit", "add", "remove", "delete"
  - "implement", "create", "build", "develop", "write"
  - "refactor", "rename", "move", "extract"
  - "bug", "issue", "error", "broken", "failing"
  - Any request mentioning specific file paths
  - Any request mentioning code elements (functions, classes, components)
  - "make it", "can you", "please", "I need", "I want" followed by code-related nouns
  - File extensions: .cs, .tsx, .ts, .js, .json, .yml, .yaml, .sql, .scss, .css, .html, .md
  - Service names: auth-service, company-service, ai-engine, workflow-engine, admin-dashboard
  - Component names: Controller, Service, Repository, Component, Page, Hook
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - WebSearch
  - WebFetch
  - TodoWrite
  - Skill
  - Task
  - mcp__atlassian__*
  - mcp__docker__*
  - mcp__postgres-local__*
  - mcp__postgres-prod__*
  - mcp__codacy__*
forbidden-tools:
  - Edit
  - Write
  - NotebookEdit
description: |
  Intercepts code change requests and routes them to appropriate implementation agents.
  Priority 0 ensures this runs early for any code-related request.
  Works with orchestrator-mode skill (priority -1) for defense in depth.
---

# Code Change Interceptor

## Purpose

This skill intercepts ANY request that involves modifying code and ensures it is properly delegated to the appropriate implementation agent rather than handled directly by the orchestrator.

## Detection Patterns

### Action Verbs (Code Modification Intent)

- **Creation**: implement, create, build, develop, write, add, generate
- **Modification**: fix, change, modify, update, edit, refactor, rename
- **Removal**: remove, delete, drop, deprecate

### File Indicators

| Extension | Language/Type | Agent |
|-----------|---------------|-------|
| `.cs` | C# | backend-developer |
| `.tsx`, `.ts`, `.js` | TypeScript/JavaScript | frontend-developer |
| `.json` (config) | Configuration | depends on location |
| `.yml`, `.yaml` | YAML config | depends on location |
| `.sql` | SQL | backend-developer |
| `.scss`, `.css` | Styles | frontend-developer |
| `.html` | HTML | frontend-developer |

### Service Indicators

| Service Name | Agent |
|--------------|-------|
| auth-service | backend-developer |
| company-service | backend-developer |
| ai-engine | backend-developer |
| workflow-engine | backend-developer |
| data-ingestion | backend-developer |
| integration-service | backend-developer |
| script-management | backend-developer |
| agent-generation | backend-developer |
| admin-dashboard | frontend-developer |
| web-portal | frontend-developer |

## Response Pattern

When you detect a code change request:

### 1. Acknowledge the Request

```markdown
I understand you want to {action} the {component/file}.

As the orchestrator, I'll analyze the request and delegate to the appropriate agent.
```

### 2. Analyze the Scope

```markdown
## Analysis

**Affected Files:**
- `{file1}` - {brief description}
- `{file2}` - {brief description}

**Required Agent:** {agent based on file patterns}

**Complexity:** {Low/Medium/High}
```

### 3. Route to Agent

**For simple, single-file changes:**

```
Task(
  subagent_type="{agent}",
  prompt="""
  ## Code Change Request

  **Action:** {what to do}
  **File(s):** {file paths}

  **Requirements:**
  {user's requirements}

  **Context:**
  {any relevant context you gathered}

  **Standards:**
  - Follow CLAUDE.md conventions
  - Use /commit for atomic commits
  - Run Codacy after changes
  """,
  description="Code change: {summary}"
)
```

**For complex, multi-file changes:**

```markdown
This request involves multiple files/services. I recommend:

1. **Create a plan first** (shift+tab for plan mode)
2. **Use /act** to create Jira tasks and coordinate agents
3. **Or use /implement-jira-task** if you have existing tasks

Would you like me to help create a plan?
```

### 4. Report Delegation

```markdown
## Delegated to {agent}

The {agent} agent will:
1. Read the relevant files
2. Implement the requested changes
3. Create appropriate commits
4. Run Codacy for quality checks

I'll monitor progress and report when complete.
```

## File Path Routing Rules

**Canonical routing from `.claude/rules/routing-rules.md`:**

| Pattern | Agent |
|---------|-------|
| `.claude/agents/*` | claude-code-hacker |
| `.claude/commands/*` | claude-code-hacker |
| `.claude/skills/*` | claude-code-hacker |
| `.claude/*.json` | claude-code-hacker |
| `services/admin-dashboard/**` | frontend-developer |
| `services/web-portal/**` | frontend-developer |
| `services/**/*.cs` | backend-developer |
| `src/shared/**/*.cs` | backend-developer |
| `tests/**/*.cs` | backend-qa |
| `tests/**/*.tsx` | frontend-qa |
| `services/db/migrations_v2/**` | backend-developer |
| `agent/windows/**` | backend-developer |
| `docker-compose*.yml` | devops-engineer |

## Example Interceptions

### Example 1: Bug Fix Request

**User:** "Fix the null reference exception in GuideSelectionService"

**Response:**
```markdown
I understand you want to fix a null reference exception in GuideSelectionService.

## Analysis

**File:** `services/ai-engine/Services/GuideSelectionService.cs`
**Service:** ai-engine (C# backend)
**Required Agent:** backend-developer

Let me delegate this to the backend-developer agent.
```

Then invoke Task tool with backend-developer.

### Example 2: UI Change Request

**User:** "Add a loading spinner to the dashboard"

**Response:**
```markdown
I understand you want to add a loading spinner to the dashboard.

## Analysis

**Service:** admin-dashboard (Next.js frontend)
**Required Agent:** frontend-developer

**Potential Files:**
- Component file for spinner
- Dashboard component(s) to integrate spinner

Let me delegate this to the frontend-developer agent.
```

Then invoke Task tool with frontend-developer.

### Example 3: Multi-Service Request

**User:** "Add pagination to the users API and update the UI"

**Response:**
```markdown
I understand you want to add pagination across the stack.

## Analysis

This request involves multiple services:
1. **Backend API** (company-service) - backend-developer
2. **Frontend UI** (admin-dashboard) - frontend-developer

This is a multi-agent task. I recommend:

**Option A:** Create a plan (shift+tab) then use /act for coordinated execution
**Option B:** Create separate Jira tasks and use /implement-jira-task

Would you like me to help create a plan for this feature?
```

## NEVER Do This

```
FORBIDDEN: Using Edit tool directly on any code file
FORBIDDEN: Using Write tool to create code files
FORBIDDEN: Running git commit directly
FORBIDDEN: Implementing code changes in the orchestrator thread
```

## Integration

This skill works alongside:
- **orchestrator-mode** (priority -1): Primary tool restriction
- **plan-mode** (priority 0): For plan-related requests
- **infrastructure-operation-interceptor** (priority 1): For K8s operations

The combination provides defense in depth:
1. orchestrator-mode blocks the tools
2. code-change-interceptor routes to correct agent
3. Other skills handle specific domains
