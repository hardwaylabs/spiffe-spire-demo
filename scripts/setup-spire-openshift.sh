#!/bin/bash
# Setup SPIRE infrastructure on OpenShift
# OpenShift requires additional Security Context Constraints (SCC) configuration
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Setting up SPIRE infrastructure on OpenShift ==="

# Check if we're on OpenShift
if ! command -v oc &> /dev/null; then
    echo "ERROR: oc CLI is not installed. Please install the OpenShift CLI first."
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "ERROR: helm is not installed. Please install helm first."
    exit 1
fi

# Check if user can grant required SCCs
if ! oc auth can-i use scc/anyuid &> /dev/null; then
    echo "ERROR: You don't have permission to grant 'anyuid' SCC."
    echo "Please ask a cluster administrator to run this script or grant you the permission."
    exit 1
fi

if ! oc auth can-i use scc/privileged &> /dev/null; then
    echo "ERROR: You don't have permission to grant 'privileged' SCC."
    echo "SPIRE agent and CSI driver require privileged access for hostNetwork, hostPID, and hostPath."
    echo "Please ask a cluster administrator to run this script or grant you the permission."
    exit 1
fi

# Check if spiffe repo is added
if ! helm repo list | grep -q spiffe; then
    echo "Adding SPIFFE Helm repository..."
    helm repo add spiffe https://spiffe.github.io/helm-charts-hardened/
fi

helm repo update

# Create namespace
echo "Creating namespace..."
oc create namespace spire-system 2>/dev/null || true

# Label namespace for Helm adoption
oc label namespace spire-system app.kubernetes.io/managed-by=Helm --overwrite
oc annotate namespace spire-system meta.helm.sh/release-name=spire meta.helm.sh/release-namespace=spire-system --overwrite

# Phase 1: Install SPIRE CRDs first
echo "Phase 1: Installing SPIRE CRDs..."
helm upgrade --install spire-crds spiffe/spire-crds \
    --namespace spire-system \
    --wait \
    --timeout 2m

# Phase 2: Install SPIRE components (without --wait, as pods will fail initially)
# This creates the service accounts we need for SCC binding
echo "Phase 2: Installing SPIRE components (pods will fail initially due to SCC)..."
helm upgrade --install spire spiffe/spire \
    --namespace spire-system \
    --values "$PROJECT_ROOT/deploy/spire/values-openshift.yaml" \
    --set global.spire.namespaces.create=false \
    --timeout 5m \
    --wait=false || true

# Wait for service accounts to be created
echo "Waiting for service accounts to be created..."
sleep 5

# Phase 3: Grant SCC permissions to SPIRE service accounts
# - spire-server needs 'anyuid' for specific user IDs
# - spire-agent needs 'privileged' for hostNetwork, hostPID, hostPath
# - spiffe-csi-driver needs 'privileged' for privileged containers and hostPath
echo "Phase 3: Granting SCC to SPIRE service accounts..."
oc adm policy add-scc-to-user anyuid -z spire-server -n spire-system
oc adm policy add-scc-to-user privileged -z spire-agent -n spire-system
oc adm policy add-scc-to-user privileged -z spire-spiffe-csi-driver -n spire-system

# Phase 4: Restart StatefulSets and DaemonSets to pick up SCC
echo "Phase 4: Restarting SPIRE components to apply SCC..."
oc rollout restart statefulset/spire-server -n spire-system 2>/dev/null || true
oc rollout restart daemonset/spire-agent -n spire-system 2>/dev/null || true

echo "Waiting for SPIRE server to be ready..."
oc wait --for=condition=ready pod -l app.kubernetes.io/name=server -n spire-system --timeout=180s

echo "Waiting for SPIRE agents to be ready..."
oc wait --for=condition=ready pod -l app.kubernetes.io/name=agent -n spire-system --timeout=180s

echo "Applying ClusterSPIFFEID registrations for demo workloads..."
oc apply -f "$PROJECT_ROOT/deploy/spire/clusterspiffeids.yaml"

echo ""
echo "=== SPIRE setup on OpenShift complete ==="
echo ""
echo "SPIRE Server: running in spire-system namespace"
echo "SPIRE Agents: running in spire-system namespace"
echo "Trust Domain: demo.example.com"
echo ""
echo "To verify SPIRE is working:"
echo "  oc exec -n spire-system spire-server-0 -c spire-server -- spire-server entry show"
echo ""
echo "Next step: Deploy the demo application with:"
echo "  oc apply -k deploy/k8s/overlays/openshift"
echo ""
