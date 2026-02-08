---
name: list-agents
description: List all available Claude Code agents with descriptions and use cases
user-invocable: false
---

# Available Agents

Display all custom Claude Code agents configured for this project, organized by layer.

## Strategic Layer

**product-strategy-advisor** - `blue`
- Analyze feature requirements and prioritize using ICE scoring
- Use when: Starting new features, prioritizing backlog, evaluating options
- Invoke via: `/act` or Task tool

**system-architect** - `green`
- Design scalable system architecture for multi-tenant SaaS
- Use when: Designing new services, planning refactoring, schema design
- Command: `/design-architecture`

**project-manager** - `purple`
- Coordinate task execution, Jira orchestration, parallel agent management
- Use when: Executing plans, coordinating implementation
- Commands: `/act`, `/implement-jira-task`

**staff-engineer-advisor** - `white`
- Assess production readiness with technical standards review
- Use when: Pre-deployment review, validating production standards
- Command: `/review-readiness`

**database-advisor** - `red`
- Database design, query optimization, indexing strategy
- Use when: Schema design, migration planning, query performance issues
- Invoke via: Task tool

## Implementation Layer

**backend-developer** - `green`
- Implement C# .NET backend with SOLID principles
- Use when: Backend development, API creation, service implementation
- Routed via: `/act` or `/implement-jira-task`

**frontend-developer** - `blue`
- Implement React frontend with Next.js and Material-UI
- Use when: UI development, component creation, page implementation
- Routed via: `/act` or `/implement-jira-task`

**ui-design-ux** - `magenta`
- Create UX design specifications with WCAG AA accessibility
- Use when: Designing UI, improving UX, creating design specs
- Command: `/design-ux`

**git-commit-helper** - `yellow`
- Generate conventional commit messages with Jira linking
- Use when: Creating commits, ensuring semantic-release format
- Command: `/commit`

## Platform Layer

**platform-lead-developer** - `purple`
- PAL interface design, cross-platform coordination, tie-breaking
- Use when: Designing platform abstraction layer, coordinating platform devs
- Invoke via: Task tool

**platform-windows-developer** - `green`
- Windows platform providers (WMI, Registry, DPAPI, MSI)
- Use when: Windows agent implementation, Win32 APIs
- Routed via: `/implement-jira-task` (auto-routed by file pattern)

**platform-linux-developer** - `green`
- Linux platform providers (systemd, /proc, libsecret, .deb/.rpm)
- Use when: Linux agent implementation, multi-distro support
- Routed via: `/implement-jira-task` (auto-routed by file pattern)

**platform-macos-developer** - `green`
- macOS platform providers (IOKit, launchd, Keychain, .pkg)
- Use when: macOS agent implementation, Apple notarization
- Routed via: `/implement-jira-task` (auto-routed by file pattern)

**platform-qa** - `red`
- Cross-platform testing, installer validation, multi-distro testing
- Use when: Platform testing, verifying cross-platform consistency
- Invoke via: Task tool

**platform-build-engineer** - `indigo`
- MSI/WiX, .pkg, .deb/.rpm packaging, code signing
- Use when: Agent installer creation, CI/CD packaging pipelines
- Invoke via: Task tool

## Quality Layer

**backend-qa** - `orange`
- Comprehensive backend testing with company isolation validation
- Use when: Testing backend code, validating security, before PR
- Command: `/qa-backend`

**frontend-qa** - `teal`
- Frontend testing with accessibility and responsive design validation
- Use when: Testing UI components, validating accessibility, before PR
- Command: `/qa-frontend`

**senior-code-reviewer** - `red`
- 5-part code review with GitHub PR creation on approval
- Use when: Ready for PR, comprehensive review needed
- Command: `/review-code`

**code-refactorer** - `purple`
- Systematic refactoring with technical debt cleanup
- Use when: Cleaning tech debt, improving code quality, optimization
- Command: `/refactor`

## Key Commands

Primary commands for development workflow:

| Command | Purpose |
|---------|---------|
| `/act` | Execute plan (creates tasks, starts parallel implementation) |
| `/implement-jira-task AI-XXX` | Implement existing Jira task(s) directly |
| `/commit` | Create semantic commits with Jira linking |
| `/qa-backend`, `/qa-frontend` | Run QA testing |
| `/review-code` | Code review and PR creation |

## Agent Directory

All agents are located in `.claude/agents/`:

**Strategic:**
- `product-strategy-advisor.md`, `system-architect.md`, `project-manager.md`
- `staff-engineer-advisor.md`, `database-advisor.md`

**Implementation:**
- `backend-developer.md`, `frontend-developer.md`
- `ui-design-ux.md`, `ui-design-lead.md`, `git-commit-helper.md`

**Platform:**
- `platform-lead-developer.md`, `platform-windows-developer.md`
- `platform-linux-developer.md`, `platform-macos-developer.md`
- `platform-qa.md`, `platform-build-engineer.md`

**Quality:**
- `backend-qa.md`, `frontend-qa.md`
- `senior-code-reviewer.md`, `code-refactorer.md`

## Usage

To learn more about a specific agent:
- Read the agent file: `.claude/agents/{agent-name}.md`
- Or use: `/agent-help {agent-name}`
