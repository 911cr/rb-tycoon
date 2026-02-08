---
skill-name: infrastructure-operation-interceptor
priority: 1
trigger: |
  Activate when the user's request contains infrastructure operation phrases:
  - "scale down", "scale up", "scale the", "set replicas"
  - "restart the pod", "restart deployment", "restart service"
  - "check the cluster", "kubernetes status", "k8s"
  - "deploy to", "rollout", "rollback"
  - "pod logs", "container logs"
  - "increase limits", "memory limit", "cpu limit"
  - "statefulset", "daemonset", "cronjob"
  - "helm upgrade", "helm install"
  - "terraform", "infrastructure change"
  - Any request involving Kubernetes resources (pods, deployments, services, configmaps, secrets)
  - Any request to modify production/staging infrastructure
allowed-tools:
  - Read
  - Grep
  - Glob
  - Skill
  - TodoWrite
  - WebSearch
  - Task
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
forbidden-tools:
  - mcp__kubernetes__resources_scale
  - Edit
  - Write
description: |
  Intercepts infrastructure operation requests and ensures they are properly delegated
  to the devops-engineer agent. Allows read-only Kubernetes operations for context
  gathering but forbids any write operations (scaling, patching, deleting).
  Priority 1 ensures this skill activates first for any infrastructure requests.
---

# Infrastructure Operation Interceptor

## Critical: MCP vs CLI Tool Access

**UNDERSTAND THIS FIRST:**

| Thread | MCP Tools | CLI Tools (Bash) |
|--------|-----------|------------------|
| **Orchestrator (main thread)** | YES - full read-only access | YES |
| **Spawned agents (via Task)** | NO - not available | YES |

The orchestrator can use Kubernetes MCP for **read-only** context gathering.
The devops-engineer agent must use **kubectl via Bash** for all operations.

**Never tell devops-engineer to use `mcp__kubernetes__*` tools - they won't work!**

## Purpose

This skill intercepts requests for infrastructure operations and ensures they are properly delegated to the `devops-engineer` agent rather than handled directly by the orchestrator.

## When This Skill Activates

This skill activates when you detect infrastructure operation requests, including:

- **Scaling Operations**: "scale down", "scale up", "set replicas to 0", "increase replicas"
- **Pod/Deployment Operations**: "restart pod", "restart deployment", "rollout", "rollback"
- **Resource Modifications**: "increase memory limit", "change cpu limit", "update resource limits"
- **Kubernetes Resource Changes**: anything involving pods, deployments, statefulsets, daemonsets, services, configmaps, secrets
- **Infrastructure Changes**: "terraform", "helm upgrade", "infrastructure change"
- **Cluster Operations**: "check cluster", "node status", "namespace operations"

## Allowed vs Forbidden Operations

### ALLOWED (Read-Only)
These operations are allowed for context gathering:
- List pods, deployments, services, namespaces
- Get pod/resource details
- View logs
- Check events
- View Helm releases
- Check node status and metrics

### FORBIDDEN (Write Operations)
These operations MUST be delegated to devops-engineer:
- Scaling replicas (`mcp__kubernetes__resources_scale`)
- Creating/deleting resources
- Modifying configmaps/secrets
- Helm install/upgrade/delete
- Any mutation to cluster state

## Required Response Pattern

When you detect an infrastructure operation request:

### 1. Acknowledge and Gather Context (Read-Only)
```
I understand you want to [describe the operation]. Let me gather context about the current infrastructure state.
```

Use ONLY read-only Kubernetes MCP tools to:
- List relevant resources
- Check current state (replicas, status, etc.)
- View recent events or logs if relevant

### 2. Check for Terraform-Managed Resources

**CRITICAL**: Always check for `managed=terraform` label BEFORE delegating.

Use read-only Kubernetes MCP to check:
```
mcp__kubernetes__resources_get(apiVersion="apps/v1", kind="StatefulSet", name="postgres", namespace="ai-it-for-msps")
```

Look in the labels for `managed=terraform`.

### 3. Delegate to DevOps Engineer with Terraform Status

**CRITICAL**: You MUST tell devops-engineer whether the resource is Terraform-managed.

**If `managed=terraform` label is present:**
```
I'm delegating this to devops-engineer with CRITICAL information:
- This resource has the `managed=terraform` label
- devops-engineer MUST use /request-infra-change workflow
- devops-engineer must NOT execute kubectl write commands
```

**If NO `managed=terraform` label:**
```
I'm delegating this to devops-engineer:
- This resource is NOT Terraform-managed
- devops-engineer can execute kubectl commands directly after confirmation
```

**IMPORTANT**: When delegating, remind the devops-engineer:
1. To use kubectl CLI commands, NOT MCP tools (agents don't have MCP access)
2. Whether the resource IS or IS NOT Terraform-managed
3. If Terraform-managed: must use `/request-infra-change`, NOT kubectl

### 4. Task Tool Invocation Template

**For Terraform-Managed Resources:**
```
Task(
  subagent_type="devops-engineer",
  prompt="""
CRITICAL: This resource is TERRAFORM-MANAGED.

DO NOT execute kubectl write commands directly.
YOU MUST use /request-infra-change workflow.

Operation: {describe operation}

Context (gathered by orchestrator):
- Resource: {type}/{name}
- Namespace: {namespace}
- Label: managed=terraform (CONFIRMED)
- kubectl context: ai-toolkit-production

Required action:
1. Invoke /request-infra-change with the change specification
2. Provide Jira task link to user
3. DO NOT execute kubectl scale/patch/apply/delete commands
"""
)
```

**For Non-Terraform-Managed Resources:**
```
Task(
  subagent_type="devops-engineer",
  prompt="""
This resource is NOT Terraform-managed.

Operation: {describe operation}

Context (gathered by orchestrator):
- Resource: {type}/{name}
- Namespace: {namespace}
- Label: NO managed=terraform label found
- kubectl context: {context}

You may execute kubectl commands directly after confirmation.
"""
)
```

### 5. Direct /request-infra-change (Alternative)

If you already know the change is for a Terraform-managed resource, you can skip devops-engineer and invoke directly:

```
/request-infra-change [description of the infrastructure change needed]
```

This is appropriate when:
- The resource is confirmed Terraform-managed
- The change is straightforward (scaling, resource limits, etc.)
- No complex analysis needed

## NEVER Do This

```
FORBIDDEN: Using mcp__kubernetes__resources_scale directly
FORBIDDEN: Any write operations to Kubernetes without devops-engineer
FORBIDDEN: Helm install/upgrade/delete without delegation
FORBIDDEN: Creating or deleting Kubernetes resources directly
```

## Example Interceptions

### User: "Scale the old database server down to 0 replicas"

**Response:**
```
I understand you want to scale down a database resource. Let me gather context about the current state.

[Use read-only K8s MCP: mcp__kubernetes__resources_list to find StatefulSets]

Based on my analysis:
- Found StatefulSet `postgres` in `ai-it-for-msps` namespace
- Current replicas: 1/1
- Label: managed=terraform (Terraform-managed resource)

CRITICAL: This resource is Terraform-managed. Direct kubectl commands are forbidden.

Delegating to devops-engineer with explicit instructions to use /request-infra-change...
```

**Task tool invocation** (CORRECT - instructs to use /request-infra-change):
```
Task(
  subagent_type="devops-engineer",
  prompt="""
CRITICAL: This resource is TERRAFORM-MANAGED.

DO NOT execute kubectl write commands directly.
YOU MUST use /request-infra-change workflow.

Operation: Scale postgres StatefulSet to 0 replicas

Context (gathered by orchestrator):
- Resource: StatefulSet/postgres
- Namespace: ai-it-for-msps
- Current replicas: 1/1
- Label: managed=terraform (CONFIRMED)
- kubectl context: ai-toolkit-production

Required action:
1. Invoke /request-infra-change with the change specification
2. Provide Jira task link to user
3. DO NOT execute kubectl scale commands directly

For documentation, the kubectl equivalent would be:
kubectl --context=ai-toolkit-production scale statefulset postgres --replicas=0 -n ai-it-for-msps
(But do NOT run this - use /request-infra-change instead)
"""
)
```

### User: "Check the status of pods in production"

**Response:**
```
I can help you check pod status. This is a read-only operation.

[Use mcp__kubernetes__pods_list to show pod status]

Current pod status in ai-msps-production:
[Results]

If you need to make changes to any of these pods, I'll delegate to the devops-engineer agent.
```

### User: "Restart the workflow-engine deployment"

**Response:**
```
I understand you want to restart the workflow-engine deployment. This is a write operation that requires the devops-engineer agent.

Let me gather current context...

[Use read-only K8s MCP: mcp__kubernetes__resources_get for deployment details]

Current state:
- Deployment: workflow-engine
- Namespace: ai-it-for-msps
- Replicas: 1/1
- Last restart: [date from annotations]

Delegating restart operation to devops-engineer...
```

**Task tool invocation** (note: kubectl commands, NOT MCP):
```
Task(
  subagent_type="devops-engineer",
  prompt="""
Restart the workflow-engine deployment.

Context (gathered by orchestrator):
- Resource: Deployment/workflow-engine
- Namespace: ai-it-for-msps
- Current replicas: 1/1
- kubectl context: ai-toolkit-production

Execute using kubectl:
kubectl --context=ai-toolkit-production rollout restart deployment/workflow-engine -n ai-it-for-msps

Then verify with:
kubectl --context=ai-toolkit-production rollout status deployment/workflow-engine -n ai-it-for-msps
"""
)
```

## Resource Type to Agent Delegation

| Resource Type | Agent | Notes |
|---------------|-------|-------|
| Terraform-managed (has label) | devops-engineer + `/request-infra-change` | For permanent changes |
| Direct K8s resources | devops-engineer | For immediate changes |
| Helm releases | devops-engineer | Helm operations |
| Node operations | devops-engineer | Cluster-level changes |

## Remember

The orchestrator's role for infrastructure operations:
1. **Detect** - Recognize infrastructure operation requests
2. **Gather Context** - Use read-only operations to understand current state
3. **Delegate** - Route to devops-engineer for all write operations
4. **Guide** - Recommend `/request-infra-change` for Terraform-managed resources when appropriate
