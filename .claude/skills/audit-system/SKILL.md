---
name: audit-system
description: Run comprehensive Claude Code system health audit via claude-code-hacker agent
context: fork
agent: claude-code-hacker
argument-hint: "[quick|enforcement|agents|permissions|custom]"
---

# System Health Audit

Run a comprehensive health audit of the entire Claude Code system configuration.

## Scope Interpretation

- **Empty/full**: Full system audit (all checks)
- **quick**: Only check critical items (orchestrator-mode, hook, guard script, CLAUDE.md rules)
- **enforcement**: Focus on workflow enforcement mechanisms
- **agents**: Audit agent configurations only
- **permissions**: Audit permission system only

## Audit Protocol

Run the appropriate audit protocol from agent instructions (Part 6: System Health Audit Protocol).

### Full Audit Checklist

**1. Configuration File Integrity**
- [ ] All agent files have valid YAML frontmatter
- [ ] All command files have valid YAML frontmatter
- [ ] All skill files have valid YAML frontmatter
- [ ] .claude/settings.json is valid JSON
- [ ] .claude/config/*.json files are valid JSON
- [ ] .mcp.json is valid JSON
- [ ] Structure follows `.claude/STRUCTURE.md` standard

**2. Workflow Enforcement**
- [ ] orchestrator-mode skill exists at priority -1
- [ ] PreToolUse hook configured for Edit|Write|NotebookEdit
- [ ] orchestrator-guard.sh is executable
- [ ] orchestrator-guard.sh logic is correct
- [ ] CLAUDE.md has ORCHESTRATOR MODE section

**3. Agent Routing**
- [ ] .claude/rules/routing-rules.md has complete file pattern table
- [ ] All file extensions have assigned agents
- [ ] No overlapping patterns with different agents

**4. Skill Precedence**
- [ ] No priority conflicts (same number, different skills)
- [ ] orchestrator-mode has lowest priority number
- [ ] All skills have explicit priority

**5. Permission Consistency**
- [ ] No deny rules blocking required tools
- [ ] MCP tools have allow entries
- [ ] No conflicting allow/deny patterns

**6. Token Efficiency**
- [ ] CLAUDE.md < 15K tokens
- [ ] Agent files < 5K tokens each
- [ ] Skills < 2K tokens each

### Quick Check (for scope="quick")

Only verify:
- orchestrator-mode skill exists at priority -1
- PreToolUse hook configured
- orchestrator-guard.sh is executable
- CLAUDE.md has orchestrator rules

## Output Requirements

1. Follow the Audit Report Format exactly
2. Categorize issues by severity (Critical, Warning, Info)
3. Auto-fix safe issues and report what was fixed
4. Propose fixes for issues requiring user approval
5. Include specific file paths and line numbers for all issues

## Audit Report Format

```markdown
# Claude Code System Health Audit

**Date**: {date}
**Auditor**: claude-code-hacker
**Scope**: {scope}

## Summary
- Total Issues: X
- Critical: X
- Warning: X
- Info: X

## Critical Issues
{issues requiring immediate fix}

## Warnings
{issues that should be addressed}

## Recommendations
{optimization opportunities}

## Auto-Fixed
{list of issues automatically repaired}

## Enforcement Status
- orchestrator-mode skill: ACTIVE/MISSING
- PreToolUse hook: CONFIGURED/MISSING
- orchestrator-guard.sh: EXECUTABLE/MISSING
- CLAUDE.md orchestrator rules: PRESENT/MISSING
```
