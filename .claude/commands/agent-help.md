---
description: Show detailed help and documentation for a specific agent
---

# Agent Help

Display detailed documentation for a specific Claude Code agent, including capabilities, when to use, and examples.

## Usage

```
/agent-help {agent-name}
```

## Available Agents

### Strategic Layer
- `product-strategy-advisor`
- `system-architect`
- `project-manager`
- `staff-engineer-advisor`
- `database-advisor`

### Implementation Layer
- `backend-developer`
- `frontend-developer`
- `ui-design-ux`
- `ui-design-lead`
- `git-commit-helper`

### Platform Layer
- `platform-lead-developer`
- `platform-windows-developer`
- `platform-linux-developer`
- `platform-macos-developer`
- `platform-qa`
- `platform-build-engineer`

### Quality Layer
- `backend-qa`
- `frontend-qa`
- `senior-code-reviewer`
- `code-refactorer`

## Examples

```
/agent-help backend-developer
/agent-help senior-code-reviewer
/agent-help product-strategy-advisor
```

## What You'll Get

When you run this command, it will display:

1. **Agent Purpose** - What the agent does
2. **Core Principles** - Agent's guiding principles
3. **When to Use** - Scenarios where this agent helps
4. **What You'll Get** - Expected outputs
5. **Toolkit** - Tools and capabilities available
6. **Process** - Step-by-step workflow
7. **Examples** - Real-world usage examples
8. **Quick Start Command** - How to launch the agent

## Agent Documentation

All agent documentation is stored in `.claude/agents/{agent-name}.md`

You can also read the markdown files directly:
- `cat .claude/agents/backend-developer.md`
- `less .claude/agents/senior-code-reviewer.md`

## Related Commands

- `/list-agents` - See all available agents
- `/act` - Execute plan with parallel agent implementation
- `/implement-jira-task AI-XXX` - Implement existing Jira tasks directly

## Full Documentation

For comprehensive project documentation:
- `CLAUDE.md` - Project overview and conventions
- `docs/GITHUB_CLI_SETUP.md` - GitHub CLI installation
- `.claude/commands/` - All available commands
- `.cursor/rules/` - Cursor IDE operation modes
