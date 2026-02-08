---
name: list-advisors
description: List all available advisory agents with their expertise domains
user-invocable: false
---

# Advisory Agents

Display comprehensive information about all strategic advisory agents available for consultation.

## Strategic Layer Advisors

**product-strategy-advisor**
- **Expertise**: Feature prioritization, ICE scoring, product roadmap
- **Consult for**: New feature ideas, backlog prioritization, strategic planning
- **Use command**: `/plan-feature {description}`

**system-architect**
- **Expertise**: Multi-tenant SaaS architecture, microservices, database design
- **Consult for**: Architectural decisions, system design, scalability planning
- **Use command**: `/design-architecture {description}`

**staff-engineer-advisor**
- **Expertise**: Production readiness, technical excellence, engineering standards
- **Consult for**: High-risk decisions, production deployment gates, performance SLOs
- **Use command**: `/review-readiness {jira-key}`

**ai-prompt-advisor**
- **Expertise**: Azure OpenAI, prompt engineering, token optimization, RAG
- **Consult for**: System prompts, AI quality issues, Azure AI Foundry integration
- **Invoke**: Task tool with `subagent_type="ai-prompt-advisor"`

**security-engineer-advisor**
- **Expertise**: Security architecture, encryption, compliance (GDPR/SOC2/HIPAA)
- **Consult for**: Authentication/authorization, vulnerability assessment, company data isolation
- **Invoke**: Task tool with `subagent_type="security-engineer-advisor"`

**network-engineer-advisor**
- **Expertise**: Network protocols (HTTP/gRPC/WebSocket), load balancing, mTLS
- **Consult for**: Protocol selection, gRPC optimization, network troubleshooting
- **Invoke**: Task tool with `subagent_type="network-engineer-advisor"`

**devops-engineer**
- **Expertise**: Docker, Kubernetes, k3s, CI/CD pipelines, WSL2 development
- **Consult for**: Containerization, deployment readiness, infrastructure code review
- **Invoke**: Task tool with `subagent_type="devops-engineer"`

**database-advisor**
- **Expertise**: Database design, query optimization, indexing, PostgreSQL, Redis, pgvector
- **Consult for**: Schema design, migration planning, N+1 queries, performance tuning, multi-tenant data patterns
- **Invoke**: Task tool with `subagent_type="database-advisor"`

## When to Consult Advisors

- **Before** making high-risk technical decisions
- **During** complex feature design (get early feedback)
- **When** facing unfamiliar domain challenges (AI, security, networking)
- **After** implementation for specialized review (security audit, performance review)

## How to Consult

1. **Via Slash Command** (if available): `/review-readiness AI-123`
2. **Via Task Tool**: `Task(subagent_type="security-engineer-advisor", prompt="Review authentication implementation for AI-123")`
3. **Via Project Manager**: Route work to project-manager, who will coordinate advisory consultation

Use `/agent-help {advisor-name}` for detailed expertise, examples, and capabilities.
