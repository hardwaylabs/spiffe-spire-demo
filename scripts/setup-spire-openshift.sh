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
echo "Phase 1: Creating spire-system namespace..."
oc create namespace spire-system 2>/dev/null || true

# Label namespace for Helm adoption
oc label namespace spire-system app.kubernetes.io/managed-by=Helm --overwrite
oc annotate namespace spire-system meta.helm.sh/release-name=spire meta.helm.sh/release-namespace=spire-system --overwrite

# Install SPIRE CRDs first
echo "Phase 2: Installing SPIRE CRDs..."
helm upgrade --install spire-crds spiffe/spire-crds \
    --namespace spire-system \
    --wait \
    --timeout 2m

# Pre-create service accounts and grant SCC BEFORE Helm install
# This avoids the chicken-and-egg problem where pods can't start without SCC
echo "Phase 3: Pre-creating service accounts and granting SCC..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spire-server
  namespace: spire-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spire-agent
  namespace: spire-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spire-spiffe-csi-driver
  namespace: spire-system
EOF

# Grant SCC permissions to SPIRE service accounts
# - spire-server needs 'anyuid' for specific user IDs
# - spire-agent needs 'privileged' for hostNetwork, hostPID, hostPath
# - spiffe-csi-driver needs 'privileged' for privileged containers and hostPath
oc adm policy add-scc-to-user anyuid -z spire-server -n spire-system
oc adm policy add-scc-to-user privileged -z spire-agent -n spire-system
oc adm policy add-scc-to-user privileged -z spire-spiffe-csi-driver -n spire-system

# Install SPIRE components with OpenShift-specific values
echo "Phase 4: Installing SPIRE components..."
helm upgrade --install spire spiffe/spire \
    --namespace spire-system \
    --values "$PROJECT_ROOT/deploy/spire/values-openshift.yaml" \
    --set global.spire.namespaces.create=false \
    --set global.installAndUpgradeHooks.enabled=false \
    --timeout 5m \
    --wait

echo "Waiting for SPIRE server to be ready..."
oc wait --for=condition=ready pod -l app.kubernetes.io/name=server -n spire-system --timeout=180s

echo "Waiting for SPIRE agents to be ready..."
oc wait --for=condition=ready pod -l app.kubernetes.io/name=agent -n spire-system --timeout=180s

echo "Phase 5: Applying ClusterSPIFFEID registrations for demo workloads..."
oc apply -f "$PROJECT_ROOT/deploy/spire/clusterspiffeids.yaml"

# Prepare demo namespace with SCC
echo "Phase 6: Creating spiffe-demo namespace and granting SCC..."
oc create namespace spiffe-demo 2>/dev/null || true
oc label namespace spiffe-demo \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged \
    --overwrite
oc adm policy add-scc-to-user privileged -z default -n spiffe-demo

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
echo "  ./scripts/deploy-openshift.sh"
echo ""
