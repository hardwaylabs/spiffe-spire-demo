# API Testing Guide

This document describes the web dashboard API endpoints and provides curl commands for testing various authorization scenarios.

## Prerequisites

Before running tests, ensure:
1. The Kind cluster is running with SPIRE
2. All services are deployed and healthy
3. Port-forwarding is active

```bash
# Check pod status
kubectl get pods -n spiffe-demo

# Start port-forwarding to web-dashboard
kubectl port-forward -n spiffe-demo svc/web-dashboard 8080:8080 &
```

---

## Web Dashboard API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/api/users` | GET | List all users |
| `/api/agents` | GET | List all AI agents |
| `/api/documents` | GET | List all documents |
| `/api/access-direct` | POST | Direct user access to document |
| `/api/access-delegated` | POST | Delegated access via AI agent |
| `/api/status` | GET | System status |
| `/events` | GET | SSE stream for real-time logs |

---

## Test Users and Their Departments

| User | Departments | SPIFFE ID |
|------|-------------|-----------|
| Alice | engineering, finance | `spiffe://demo.example.com/user/alice` |
| Bob | finance, admin | `spiffe://demo.example.com/user/bob` |
| Carol | hr | `spiffe://demo.example.com/user/carol` |

## Test Agents and Their Capabilities

| Agent | Capabilities | SPIFFE ID |
|-------|--------------|-----------|
| GPT-4 | engineering, finance | `spiffe://demo.example.com/agent/gpt4` |
| Claude | engineering, finance, admin, hr | `spiffe://demo.example.com/agent/claude` |
| Summarizer | finance | `spiffe://demo.example.com/agent/summarizer` |

## Test Documents and Required Departments

| Document | Title | Required Departments |
|----------|-------|---------------------|
| DOC-001 | Engineering Roadmap | engineering |
| DOC-002 | Q4 Financial Report | finance |
| DOC-003 | Admin Policies | admin |
| DOC-004 | HR Guidelines | hr |
| DOC-005 | Budget Projections | finance, engineering |
| DOC-006 | Compliance Audit | admin, finance |
| DOC-007 | All-Hands Summary | (public) |

---

## Direct Access Tests

### Successful Access

```bash
# Alice accessing engineering document (Alice has engineering)
curl -s -X POST http://localhost:8080/api/access-direct \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "document_id": "DOC-001"}' | jq .

# Expected: {"granted": true, "reason": "Access granted", "document": {...}}
```

```bash
# Bob accessing finance document (Bob has finance)
curl -s -X POST http://localhost:8080/api/access-direct \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "document_id": "DOC-002"}' | jq .

# Expected: {"granted": true, ...}
```

```bash
# Bob accessing admin document (Bob has admin)
curl -s -X POST http://localhost:8080/api/access-direct \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "document_id": "DOC-003"}' | jq .

# Expected: {"granted": true, ...}
```

### Denied Access (Wrong Department)

```bash
# Bob accessing engineering document (Bob lacks engineering)
curl -s -X POST http://localhost:8080/api/access-direct \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "document_id": "DOC-001"}' | jq .

# Expected: {"granted": false, "reason": "Insufficient permissions"}
```

```bash
# Carol accessing finance document (Carol lacks finance)
curl -s -X POST http://localhost:8080/api/access-direct \
  -H "Content-Type: application/json" \
  -d '{"user_id": "carol", "document_id": "DOC-002"}' | jq .

# Expected: {"granted": false, "reason": "Insufficient permissions"}
```

```bash
# Alice accessing admin document (Alice lacks admin)
curl -s -X POST http://localhost:8080/api/access-direct \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "document_id": "DOC-003"}' | jq .

# Expected: {"granted": false, "reason": "Insufficient permissions"}
```

```bash
# Alice accessing HR document (Alice lacks hr)
curl -s -X POST http://localhost:8080/api/access-direct \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "document_id": "DOC-004"}' | jq .

# Expected: {"granted": false, "reason": "Insufficient permissions"}
```

---

## Delegated Access Tests

### Successful Delegation

```bash
# Alice delegates to GPT-4 for engineering doc (both have engineering)
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "agent_id": "gpt4", "document_id": "DOC-001"}' | jq .

# Expected: {"granted": true, "reason": "Delegated access granted", ...}
```

```bash
# Bob delegates to Claude for admin doc (both have admin)
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "agent_id": "claude", "document_id": "DOC-003"}' | jq .

# Expected: {"granted": true, ...}
```

```bash
# Carol delegates to Claude for HR doc (both have hr)
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"user_id": "carol", "agent_id": "claude", "document_id": "DOC-004"}' | jq .

# Expected: {"granted": true, ...}
```

### Denied Delegation (Agent Without User Context)

```bash
# Agent trying to access without user delegation
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "gpt4", "document_id": "DOC-001"}' | jq .

# Expected: {"granted": false, "reason": "Agent requests require user delegation context..."}
```

### Denied Delegation (Capability Mismatch)

```bash
# Alice delegates to Summarizer for engineering doc (Summarizer lacks engineering)
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "agent_id": "summarizer", "document_id": "DOC-001"}' | jq .

# Expected: {"granted": false, "reason": "Insufficient permissions", ...}
```

```bash
# Bob delegates to GPT-4 for admin doc (GPT-4 lacks admin)
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "agent_id": "gpt4", "document_id": "DOC-003"}' | jq .

# Expected: {"granted": false, "reason": "Insufficient permissions", ...}
```

```bash
# Alice delegates to GPT-4 for HR doc (neither has hr)
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "agent_id": "gpt4", "document_id": "DOC-004"}' | jq .

# Expected: {"granted": false, "reason": "Insufficient permissions", ...}
```

---

## Utility Endpoints

### List Resources

```bash
# List all users
curl -s http://localhost:8080/api/users | jq .

# List all agents
curl -s http://localhost:8080/api/agents | jq .

# List all documents
curl -s http://localhost:8080/api/documents | jq .
```

### Health Check

```bash
# Web dashboard health
curl -s http://localhost:8080/health | jq .

# Expected: {"status": "healthy"}
```

### System Status

```bash
# Get system status (services connectivity)
curl -s http://localhost:8080/api/status | jq .
```

---

## Batch Testing Script

Run all authorization tests at once:

```bash
#!/bin/bash
# test-authorization.sh

echo "=== Direct Access Tests ==="

echo -n "Alice -> DOC-001 (should GRANT): "
curl -s -X POST http://localhost:8080/api/access-direct \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "document_id": "DOC-001"}' | jq -r '.granted'

echo -n "Bob -> DOC-001 (should DENY): "
curl -s -X POST http://localhost:8080/api/access-direct \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "document_id": "DOC-001"}' | jq -r '.granted'

echo -n "Carol -> DOC-002 (should DENY): "
curl -s -X POST http://localhost:8080/api/access-direct \
  -H "Content-Type: application/json" \
  -d '{"user_id": "carol", "document_id": "DOC-002"}' | jq -r '.granted'

echo -n "Alice -> DOC-003 (should DENY): "
curl -s -X POST http://localhost:8080/api/access-direct \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "document_id": "DOC-003"}' | jq -r '.granted'

echo ""
echo "=== Delegated Access Tests ==="

echo -n "Alice -> GPT-4 -> DOC-001 (should GRANT): "
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "agent_id": "gpt4", "document_id": "DOC-001"}' | jq -r '.granted'

echo -n "Bob -> Claude -> DOC-003 (should GRANT): "
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "agent_id": "claude", "document_id": "DOC-003"}' | jq -r '.granted'

echo -n "GPT-4 -> DOC-001 (no user, should DENY): "
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "gpt4", "document_id": "DOC-001"}' | jq -r '.granted'

echo -n "Alice -> Summarizer -> DOC-001 (should DENY): "
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "agent_id": "summarizer", "document_id": "DOC-001"}' | jq -r '.granted'

echo -n "Bob -> GPT-4 -> DOC-003 (should DENY): "
curl -s -X POST http://localhost:8080/api/access-delegated \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "agent_id": "gpt4", "document_id": "DOC-003"}' | jq -r '.granted'

echo ""
echo "=== Tests Complete ==="
```

---

## Permission Intersection Logic

When a user delegates to an agent:
```
Effective Permissions = User Departments ∩ Agent Capabilities
```

For access to be granted, the intersection must include ALL required departments for the document.

### Example: Alice → GPT-4 → DOC-005

- Alice's departments: `{engineering, finance}`
- GPT-4's capabilities: `{engineering, finance}`
- Intersection: `{engineering, finance}`
- DOC-005 requires: `{finance, engineering}`
- Result: **GRANTED** (intersection contains all required)

### Example: Alice → Summarizer → DOC-005

- Alice's departments: `{engineering, finance}`
- Summarizer's capabilities: `{finance}`
- Intersection: `{finance}`
- DOC-005 requires: `{finance, engineering}`
- Result: **DENIED** (intersection missing `engineering`)

---

## Troubleshooting

### Port-forward not working

```bash
# Kill existing port-forwards
pkill -f "kubectl port-forward.*8080"

# Restart port-forward
kubectl port-forward -n spiffe-demo svc/web-dashboard 8080:8080 &
```

### Services not responding

```bash
# Check pod status
kubectl get pods -n spiffe-demo

# Check service logs
kubectl logs -n spiffe-demo -l app=web-dashboard --tail=20
kubectl logs -n spiffe-demo -l app=user-service --tail=20
kubectl logs -n spiffe-demo -l app=document-service --tail=20
```

### SPIFFE identity issues

```bash
# Check SPIRE entries
kubectl exec -n spire-system spire-server-0 -c spire-server -- \
  spire-server entry show

# Check service SPIFFE ID
kubectl logs -n spiffe-demo -l app=opa-service | grep -i spiffe
```
