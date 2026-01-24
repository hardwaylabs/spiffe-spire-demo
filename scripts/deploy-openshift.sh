#!/bin/bash
# Deploy the SPIFFE demo application to OpenShift
# Run after setup-spire-openshift.sh has completed
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying SPIFFE demo to OpenShift ==="

# Check if SPIRE is running
echo "Checking SPIRE status..."
if ! oc get pods -n spire-system -l app.kubernetes.io/name=server 2>/dev/null | grep -q Running; then
    echo "ERROR: SPIRE server is not running. Please run ./scripts/setup-spire-openshift.sh first."
    exit 1
fi

# Apply the OpenShift overlay
echo "Applying OpenShift overlay..."
oc apply -k "$PROJECT_ROOT/deploy/k8s/overlays/openshift"

# Wait for namespace and service account to be created
echo "Waiting for namespace resources..."
sleep 3

# Grant SCC to the default service account (must be done AFTER namespace/SA exist)
# The init containers need privileged access for SELinux relabeling
echo "Granting privileged SCC to demo service account..."
oc adm policy add-scc-to-user privileged -z default -n spiffe-demo

# Label the namespace with pod security labels
oc label namespace spiffe-demo \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged \
    --overwrite 2>/dev/null || true

# Force recreate pods to pick up SCC
echo "Restarting deployments to pick up SCC..."
oc rollout restart deployment -n spiffe-demo

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
oc wait --for=condition=ready pod -l app -n spiffe-demo --timeout=180s

echo ""
echo "=== SPIFFE demo deployment complete ==="
echo ""
oc get pods -n spiffe-demo
echo ""
echo "To access the dashboard:"
echo "  oc -n spiffe-demo port-forward svc/web-dashboard 8080:8080 &"
echo "  open http://localhost:8080"
echo ""
