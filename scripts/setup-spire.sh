#!/bin/bash
# Setup SPIRE infrastructure for the demo
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Setting up SPIRE infrastructure ==="

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "ERROR: helm is not installed. Please install helm first."
    exit 1
fi

# Check if spiffe repo is added
if ! helm repo list | grep -q spiffe; then
    echo "Adding SPIFFE Helm repository..."
    helm repo add spiffe https://spiffe.github.io/helm-charts-hardened/
fi

helm repo update

# Create namespace manually to avoid Helm ownership conflicts
echo "Creating namespace..."
kubectl create namespace spire-system 2>/dev/null || true

# Label namespace for Helm adoption
kubectl label namespace spire-system app.kubernetes.io/managed-by=Helm --overwrite
kubectl annotate namespace spire-system meta.helm.sh/release-name=spire meta.helm.sh/release-namespace=spire-system --overwrite

# Phase 1: Install SPIRE CRDs first
echo "Phase 1: Installing SPIRE CRDs..."
helm upgrade --install spire-crds spiffe/spire-crds \
    --namespace spire-system \
    --wait \
    --timeout 2m

# Phase 2: Install SPIRE components
echo "Phase 2: Installing SPIRE components (this may take a few minutes)..."
helm upgrade --install spire spiffe/spire \
    --namespace spire-system \
    --values "$PROJECT_ROOT/deploy/spire/values.yaml" \
    --set global.spire.namespaces.create=false \
    --wait \
    --timeout 10m

echo "Waiting for SPIRE server to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=server -n spire-system --timeout=120s

echo "Waiting for SPIRE agents to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=agent -n spire-system --timeout=120s

echo "Applying ClusterSPIFFEID registrations for demo workloads..."
kubectl apply -f "$PROJECT_ROOT/deploy/spire/clusterspiffeids.yaml"

echo ""
echo "=== SPIRE setup complete ==="
echo ""
echo "SPIRE Server: running in spire-system namespace"
echo "SPIRE Agents: running in spire-system namespace"
echo "Trust Domain: demo.example.com"
echo ""
echo "To verify SPIRE is working:"
echo "  kubectl exec -n spire-system spire-server-0 -c spire-server -- spire-server entry show"
echo ""
echo "Next step: Deploy the demo application with:"
echo "  kubectl apply -k deploy/k8s/overlays/local"
echo ""
echo "Alternatively, you can use the GHCR-based overlay with:"
echo "  kubectl apply -k deploy/k8s/overlays/ghcr"
