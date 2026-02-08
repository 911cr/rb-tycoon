---
description: Request infrastructure changes from the ai-toolkit-terraform project via Jira task creation
---

# /request-infra-change Command

Request infrastructure changes (Kubernetes deployments, secrets, configmaps, ingress rules, database changes, etc.) by creating a Jira task that the ai-toolkit-terraform project can process.

## Use Cases

- **New Environment Variable**: Add a configmap or secret for a microservice
- **Ingress Changes**: Add/modify domain routing or middleware
- **Resource Scaling**: Update CPU/memory limits in deployments
- **New Service Deployment**: Request k3s deployment for a new microservice
- **Database Provisioning**: Request PostgreSQL changes via db-postgres module
- **Storage Changes**: Request MinIO bucket or PVC modifications

## Workflow

### Phase 1: Gather Requirements

Determine what infrastructure change is needed based on:
- Current plan requirements
- New feature deployments
- Performance/scaling needs
- Security updates (credential rotation, etc.)

Ask the user (or analyze the context) to determine:
1. **What** needs to change
2. **Why** (business/technical justification)
3. **Which service(s)** are affected
4. **Urgency** (low/medium/high/critical)

### Phase 2: Generate Technical Specification

Based on the change type, extract specific details:

**For Secrets/ConfigMaps:**
- Key names and types (literal vs file)
- Target namespace (usually `ai-it-for-msps`)
- Which deployments consume it
- Sensitive value handling (reference only, never include actual secrets)

**For Deployments:**
- Resource requests/limits
- Replica count
- Health probe configuration
- Environment variable references

**For Ingress:**
- Domain(s)
- Backend service and port
- Middleware requirements (auth, rate limiting, redirect)
- TLS requirements

**For Database (PostgreSQL):**
- max_connections changes
- Memory limit adjustments (auto-calculates shared_buffers)
- PostgreSQL version (17 or 18)
- pgvector configuration

### Phase 3: Create Jira Task

Use the Atlassian MCP to create the task:

```
jira_create_issue(
  projectKey="AI",
  issueTypeName="Task",
  summary="[INFRA] {brief description}",
  description="{generated description using template below}"
)

# Add infrastructure request label
jira_edit_issue(
  issueKey="{new_task_key}",
  fields={"labels": ["devops-terraform-request"]}
)
```

### Phase 3.5: Assign to Sprint (REQUIRED)

**CRITICAL**: Infrastructure requests MUST be moved to the current active sprint for proper tracking.

```
# Get authenticated user for task assignment
jira_get_user_info()

# Get active sprint for the default board (board ID: 1)
jira_get_sprints(boardId=1, state="active")

# Move to active sprint
jira_move_issues_to_sprint(
  sprintId={active_sprint_id},
  issueKeys=["{new_task_key}"]
)

# Assign to current user
jira_edit_issue(
  issueKey="{new_task_key}",
  fields={"assignee": {"accountId": "{user_account_id}"}}
)
```

### Phase 4: Return Task Link

Display the created task and next steps:

```
## Infrastructure Request Created

**Task**: [{task_key}](https://911it.atlassian.net/browse/{task_key})
**Summary**: [INFRA] {description}
**Label**: devops-terraform-request
**Sprint**: {sprint_name}
**Assigned To**: {user_email}

### What Happens Next

1. The task is now visible in Jira with the `devops-terraform-request` label
2. In the `ai-toolkit-terraform` project, run:
   ```
   /complete-jira-ai-it-for-msps-requests
   ```
3. The devops-engineer agent will:
   - Read the task requirements
   - Implement Terraform changes
   - Create a PR for review
   - Update the Jira task with PR link

### If Changes Are Urgent

- **High/Critical**: Notify the team via Slack/Teams
- **Standard**: Process during normal workflow cycles
```

## Task Description Template

The Jira task description MUST follow this structured format:

```markdown
## Infrastructure Change Request

**Source Project:** ai-it-for-msps
**Requested By:** {user context or agent name}
**Urgency:** {low|medium|high|critical}
**Related Issue:** {AI-XXX if applicable, or "N/A"}

---

## Change Description

{What needs to change and business/technical justification}

---

## Technical Specification

### Resource Type
{secret | configmap | deployment | ingress | database | storage | other}

### Environment
{production | staging | development}

### Target Namespace
{namespace name, e.g., ai-it-for-msps}

### Service(s) Affected
- {service-1}
- {service-2}

---

## Expected Configuration

{Include relevant YAML structure examples - DO NOT include actual secret values}

### For Secrets/ConfigMaps:
```yaml
# Example structure (DO NOT include actual secret values)
apiVersion: v1
kind: Secret
metadata:
  name: {secret-name}
  namespace: ai-it-for-msps
type: Opaque
data:
  KEY_NAME: "<value-from-terraform-cloud>"
```

### For Deployments:
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

### For Ingress:
```yaml
domains:
  - {domain.example.com}
backend:
  service: {service-name}
  port: {port}
middleware:
  - http-to-https-redirect
```

### For Database (PostgreSQL):
```yaml
module: db-postgres
changes:
  - max_connections: 200
  - memory_limit: "2Gi"
```

---

## Acceptance Criteria

- [ ] {Criterion 1 - specific and testable}
- [ ] {Criterion 2}
- [ ] {Criterion 3}
- [ ] Terraform plan shows expected changes
- [ ] Terraform apply succeeds without errors
- [ ] Service is accessible/functioning as expected

---

## Context & References

- **Related PR**: {link if applicable}
- **Related Issue**: {AI-XXX if applicable}
- **Documentation**: {relevant docs links}

---

*Created via `/request-infra-change` from ai-it-for-msps*
```

## Error Handling

### Missing Required Information

If critical details are missing, prompt the user:

```
Warning: Missing required details for infrastructure request.

Please provide:
- [ ] What needs to change (description)
- [ ] Target environment (production/staging)
- [ ] Affected service(s)

Would you like to continue with the interactive prompt?
```

### Duplicate Detection

Before creating a new task, check for similar pending requests:

```
jira_search_jql(
  jql="project = AI AND labels = 'devops-terraform-request' AND summary ~ '{keywords}' AND status != Done AND created >= -30d",
  fields=["key", "summary", "status"]
)
```

If duplicates found:
```
## Similar Infrastructure Requests Found

| Key | Summary | Status |
|-----|---------|--------|
| AI-XXX | [INFRA] Similar request | In Progress |

Options:
1. **Add comment** to existing task with additional details
2. **Create new task** if this is a different request
3. **Cancel** and review existing task first

Which would you like to do?
```

## Security Notes

- **NEVER include actual secret values** in Jira descriptions
- Use placeholders like `<value-from-terraform-cloud>` or `<from-vault>`
- Secrets should be:
  - Entered manually in Terraform Cloud
  - Or referenced from external secret management
  - Or provided via encrypted channels

## Integration

This command works with the cross-project workflow:
- **This project (ai-it-for-msps)**: Creates the Jira task
- **ai-toolkit-terraform project**: Processes via `/complete-jira-ai-it-for-msps-requests`
- **Terraform Cloud**: Applies changes to production k3s cluster
