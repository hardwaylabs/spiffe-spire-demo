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

echo "Installing SPIRE (this may take a few minutes)..."
helm upgrade --install spire spiffe/spire \
    --namespace spire-system \
    --create-namespace \
    --values "$PROJECT_ROOT/deploy/spire/values.yaml" \
    --wait \
    --timeout 5m

echo "Waiting for SPIRE server to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=server -n spire-server --timeout=120s

echo "Waiting for SPIRE agents to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=agent -n spire-system --timeout=120s

echo "Applying ClusterSPIFFEID registrations..."
kubectl apply -f "$PROJECT_ROOT/deploy/spire/clusterspiffeids.yaml"

echo ""
echo "=== SPIRE setup complete ==="
echo ""
echo "SPIRE Server: running in spire-server namespace"
echo "SPIRE Agents: running in spire-system namespace"
echo "Trust Domain: demo.example.com"
echo ""
echo "To verify SPIRE is working:"
echo "  kubectl exec -n spire-server spire-server-0 -- spire-server entry show"
echo ""
echo "Next step: Deploy the demo application with:"
echo "  kubectl apply -f deploy/k8s/"
