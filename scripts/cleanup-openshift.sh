#!/bin/bash
# Clean up SPIRE and demo deployment on OpenShift
set -e

echo "=== Cleaning up SPIFFE/SPIRE demo on OpenShift ==="

# Check if oc CLI is installed
if ! command -v oc &> /dev/null; then
    echo "ERROR: oc CLI is not installed. Please install the OpenShift CLI first."
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "ERROR: helm is not installed. Please install helm first."
    exit 1
fi

# Delete demo namespace
echo "Deleting spiffe-demo namespace..."
oc delete namespace spiffe-demo --ignore-not-found --timeout=60s || true

# Uninstall SPIRE Helm releases
echo "Uninstalling SPIRE Helm releases..."
helm uninstall spire -n spire-system 2>/dev/null || true
helm uninstall spire-crds -n spire-system 2>/dev/null || true

# Wait for resources to be deleted
echo "Waiting for SPIRE pods to terminate..."
oc delete pods -n spire-system --all --force --grace-period=0 2>/dev/null || true

# Delete SPIRE namespace
echo "Deleting spire-system namespace..."
oc delete namespace spire-system --ignore-not-found --timeout=60s || true

# Clean up cluster-scoped resources
echo "Cleaning up ClusterSPIFFEID resources..."
oc delete clusterspiffeid --all 2>/dev/null || true

# Clean up CRDs if needed
echo "Cleaning up SPIRE CRDs..."
oc delete crd clusterspiffeids.spire.spiffe.io 2>/dev/null || true
oc delete crd clusterfederatedtrustdomains.spire.spiffe.io 2>/dev/null || true
oc delete crd controllermanagerconfigs.spire.spiffe.io 2>/dev/null || true

# Remove SCC bindings
echo "Removing SCC bindings..."
oc adm policy remove-scc-from-user anyuid -z spire-server -n spire-system 2>/dev/null || true
oc adm policy remove-scc-from-user privileged -z spire-agent -n spire-system 2>/dev/null || true
oc adm policy remove-scc-from-user privileged -z spire-spiffe-csi-driver -n spire-system 2>/dev/null || true
oc adm policy remove-scc-from-user privileged -z default -n spiffe-demo 2>/dev/null || true

echo ""
echo "=== Cleanup complete ==="
echo ""
echo "To redeploy, run:"
echo "  ./scripts/setup-spire-openshift.sh"
echo "  ./scripts/deploy-openshift.sh"
echo ""
