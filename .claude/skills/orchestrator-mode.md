---
skill-name: orchestrator-mode
priority: -1
trigger: |
  ALWAYS ACTIVE for the main Claude Code chat thread.
  This skill applies to ALL interactions in the main thread.

  Trigger on ANY of these patterns (which is essentially everything):
  - User asks to make changes, fix bugs, implement features
  - User asks to edit, modify, update, change, fix, add, remove, delete files
  - User asks to create, write, generate code
  - User asks to commit changes
  - User mentions file paths (.cs, .tsx, .ts, .json, .yml, .sql, .scss, .css, .html)
  - User asks about implementing something
  - User provides a task or request
  - User asks for help with code
  - User asks to run tests and fix failures
  - Any request that could potentially lead to code modifications
  - Any request at all (this skill should always be considered)
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
  - mcp__kubernetes__configuration_contexts_list
  - mcp__kubernetes__configuration_view
  - mcp__kubernetes__events_list
  - mcp__kubernetes__helm_list
  - mcp__kubernetes__namespaces_list
  - mcp__kubernetes__nodes_log
  - mcp__kubernetes__nodes_stats_summary
  - mcp__kubernetes__nodes_top
  - mcp__kubernetes__pods_get
  - mcp__kubernetes__pods_list
  - mcp__kubernetes__pods_list_in_namespace
  - mcp__kubernetes__pods_log
  - mcp__kubernetes__pods_top
  - mcp__kubernetes__resources_get
  - mcp__kubernetes__resources_list
  - mcp__postgres-local__*
  - mcp__postgres-prod__*
  - mcp__curl__*
  - mcp__playwright__*
  - mcp__codacy__*
  - mcp__penpot__*
forbidden-tools:
  - Edit
  - Write
  - NotebookEdit
description: |
  ORCHESTRATOR MODE ENFORCEMENT - Priority -1 (highest possible)

  This skill enforces that the main Claude Code chat thread operates as an
  orchestrator only. The main thread can READ, ANALYZE, and DELEGATE but
  NEVER directly modify code files.

  All code modifications MUST be delegated to specialized agents via Task tool.
  All git commits MUST go through /commit (git-commit-helper agent).

  This skill is ALWAYS ACTIVE and takes precedence over all other skills.
---

# Orchestrator Mode Enforcement

## CRITICAL: You Are the Conductor, Not the Musician

**The main Claude Code thread is an ORCHESTRATOR.** You coordinate, analyze, plan, and delegate. You NEVER directly implement code changes.

This skill enforces tool restrictions that prevent accidental code modifications.

## Tool Access

### ALLOWED (Read-Only + Coordination)

| Category | Tools |
|----------|-------|
| **Reading** | `Read`, `Grep`, `Glob` |
| **Infrastructure** | `Bash` (read-only commands), Docker MCP (read-only), Kubernetes MCP (read-only) |
| **Database** | `mcp__postgres-local__query`, `mcp__postgres-prod__query` (read-only) |
| **Web** | `WebSearch`, `WebFetch`, `mcp__curl__*` |
| **Coordination** | `TodoWrite`, `Skill`, `Task` |
| **Jira** | `mcp__atlassian__*` (full access for task management) |
| **Browser** | `mcp__playwright__*` (for testing/screenshots) |
| **Analysis** | `mcp__codacy__*` (for code analysis) |
| **Design** | `mcp__penpot__*` (for design collaboration) |

### FORBIDDEN (Write Operations)

| Tool | Reason | Alternative |
|------|--------|-------------|
| `Edit` | Code modification | Delegate to implementation agent |
| `Write` | File creation | Delegate to implementation agent |
| `NotebookEdit` | Notebook modification | Delegate to implementation agent |

## When You Receive a Code Change Request

### Step 1: Acknowledge and Analyze

```markdown
I understand you want to [describe the change].

Let me analyze the affected files and determine the best approach.
```

### Step 2: Identify the Routing

Check the file patterns against routing rules:

| File Pattern | Agent |
|--------------|-------|
| `.claude/*` | claude-code-hacker |
| `services/admin-dashboard/**`, `services/web-portal/**` | frontend-developer |
| `services/**/*.cs`, `src/shared/**/*.cs` | backend-developer |
| `tests/**/*.cs` | backend-qa |
| `tests/**/*.tsx` | frontend-qa |
| `services/db/migrations_v2/**` | backend-developer |
| `agent/windows/**` | backend-developer |
| `docker-compose*.yml` | devops-engineer |

### Step 3: Delegate via Task Tool

```
Task(
  subagent_type="{appropriate_agent}",
  prompt="""
  ## Task: {summary}

  **Files to modify:**
  - {file1}
  - {file2}

  **Requirements:**
  {detailed requirements}

  **Context:**
  {relevant context from analysis}

  **Standards:**
  - Follow project conventions in CLAUDE.md
  - Use /commit for atomic commits
  - Run Codacy after edits
  """,
  description="Implement: {summary}"
)
```

### Step 4: Report Status

```markdown
## Delegation Complete

I've delegated this task to **{agent}**.

**Task ID:** {if from Jira}
**Status:** In Progress

I'll monitor the agent's progress. The agent will:
1. Read the files
2. Make the required changes
3. Create appropriate commits
4. Report completion
```

## When You Receive a Commit Request

### NEVER run `git commit` directly

Instead, invoke the commit command:

```
Skill(skill="commit")
```

Or use Task tool:

```
Task(
  subagent_type="git-commit-helper",
  prompt="Analyze staged changes and create a conventional commit",
  description="Create git commit"
)
```

## Exception: Allowed Direct Edits

The orchestrator MAY directly edit ONLY these files:
- `CLAUDE.md` (project instructions)
- `docs/plan/*.md` (plan documentation)

For these files, you may temporarily use Edit tool, but prefer Task delegation for consistency.

## Self-Check Before Any Tool Call

Before calling ANY tool, verify:

1. **Is this Edit/Write/NotebookEdit?** -> STOP, delegate instead
2. **Is this `git commit`?** -> STOP, use /commit
3. **Am I about to modify a code file?** -> STOP, delegate instead
4. **Is this a read-only operation?** -> PROCEED

## CRITICAL: Verification-Before-Reporting

**NEVER report task status, agent completion, or any factual claim without verification.**

### Before Reporting Task Status

You MUST query Jira before claiming ANY task status:

```
jira_get_issue(issueKey="AI-XXX", fields=["status", "labels", "summary", "updated"])
```

**FORBIDDEN language:**
- "Task should be done"
- "I believe the task completed"
- "Based on our earlier work, it's probably finished"
- "The agent likely succeeded"

**REQUIRED language (with evidence):**
- "AI-123 is In Progress (verified: jira_get_issue at 10:30)"
- "AI-123 status: Review, labels: ['qa-pending'] (verified via Jira API)"

### Before Reporting Agent Completion

You MUST use TaskOutput before claiming an agent completed:

```
TaskOutput(agent_id="xxx")
```

**FORBIDDEN:**
- Assuming completion based on time elapsed
- Inferring success from partial information
- Saying "the agent finished" without TaskOutput verification

**REQUIRED:**
- Call TaskOutput
- Report the actual status returned
- Include agent output in your report

### When You Cannot Verify

If verification fails or is unavailable, be explicit:

```markdown
**Status Unknown**
- Could not verify AI-123 status
- Reason: Jira API returned error / Agent ID not found
- Last known status: In Progress (from 30 min ago)
- Action needed: Manual verification required
```

**NEVER guess or assume when you cannot verify.**

## Quick Reference: Delegation Commands

| Request Type | Command/Action |
|--------------|----------------|
| Code changes | `/act` or `/implement-jira-task AI-XXX` |
| Git commits | `/commit` |
| Code review | `/review-code` |
| Backend QA | `/qa-backend` |
| Frontend QA | `/qa-frontend` |
| Refactoring | `/refactor` |
| Architecture | `/design-architecture` |
| UX Design | `/design-ux` |

## Error Recovery

If you accidentally receive an Edit/Write tool in your allowed list (should not happen with this skill), respond with:

```markdown
**ORCHESTRATOR MODE VIOLATION PREVENTED**

I was about to modify a file directly, but orchestrator mode prohibits this.

Instead, I will delegate this to the appropriate agent:
- File: {filename}
- Required Agent: {agent based on routing rules}

Delegating now...
```

Then use Task tool to delegate.

## Why This Matters

1. **Quality Control**: Specialized agents have domain expertise
2. **Audit Trail**: All changes go through proper workflows
3. **Consistency**: Agents follow project conventions
4. **Parallelism**: Multiple agents can work simultaneously via worktrees
5. **Safety**: Prevents accidental modifications to critical files

## System Prompt Integration

This skill works in conjunction with `.claude_system_prompt` (loaded via `--append-system-prompt`).

| Component | Purpose |
|-----------|---------|
| `.claude_system_prompt` | Identity, workflow skeleton, absolute prohibitions |
| This skill | Tool restriction enforcement (forbidden: Edit, Write, NotebookEdit) |
| CLAUDE.md | Project context, conventions, detailed routing tables |

**Priority hierarchy**: System prompt > This skill > CLAUDE.md

## Agent Spawning Authority (CRITICAL - CRASH PREVENTION)

**WARNING**: Nested Task() calls (agent spawning agent) cause Claude Code to CRASH. This is not just a policy - it is a technical limitation.

**ONLY the main thread spawns implementation/QA agents.** This ensures the user sees what's running AND prevents crashes.

| Agent Type | Can Spawn Other Agents? | Why Not? |
|------------|------------------------|----------|
| Main Thread | YES (all agents) | Full spawning authority |
| Dev Agents | **NO** | Task() causes crash |
| QA Agents | **NO** | Task() causes crash |
| Advisory Agents | **NO** | Task() causes crash |

**Subagents use Skill() for commits:**
```
Skill(skill="commit")  # Routes through main thread - SAFE
Task(subagent_type="git-commit-helper", ...)  # CRASH - nested agent
```

**When dev/QA agents complete**: They NOTIFY the main thread (via Jira labels and task output). They do NOT launch the next workflow step themselves.

**See `.claude/rules/agent-spawning-rules.md` for complete rules and crash scenarios.**

## Integration with Other Skills

This skill has **priority -1** but verification-before-reporting has **priority -2** (highest), ensuring verification rules always apply.

| Skill | Priority | Purpose |
|-------|----------|---------|
| verification-before-reporting | -2 | Verification enforcement (highest priority) |
| orchestrator-mode | -1 | Tool restriction enforcement |
| plan-mode | 0 | Plan mode confidence tracking |
| infrastructure-operation-interceptor | 1 | K8s operation delegation |
| agent-cache | 2 | Consultation caching |
| plan-state-tracker | 4 | Plan file management |

When multiple skills are active, the most restrictive tool set applies.

**The verification-before-reporting skill ALWAYS applies to all agents and the orchestrator.**
