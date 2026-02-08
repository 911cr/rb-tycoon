---
description: Design scalable system architecture for multi-tenant SaaS platform
---

# Architecture Design

Launch the **system-architect** agent to:

1. Analyze existing system architecture
2. Design new system components
3. Define service boundaries and responsibilities
4. Plan database schema changes
5. Design API contracts
6. Define multi-tenant data isolation strategy
7. Create architecture decision records (ADRs)

## What You'll Get

- System architecture diagram (component relationships)
- Database schema design (tables, indexes, relationships)
- API endpoint specifications (RESTful design)
- Service dependencies and communication patterns
- Multi-tenant isolation strategy
- Migration plan for schema changes
- Architecture documentation saved to `docs/plan/{plan-id}/architecture/`

## When to Use

- Designing new microservices or features
- Planning significant refactoring
- Evaluating architectural options
- Need database schema design
- Before starting complex implementation

## Example Usage

```
/design-architecture Design notification delivery system for AI-68
```

## Next Steps

After architecture approval:
- `/create-plan-in-jira` - Create Jira tasks from the architecture plan
- `/implement-jira-task AI-XXX` - Start implementation of specific tasks
- Or use `/act` to create tasks and start implementation
