#!/bin/bash
# Preload SPIRE images into Kind cluster to avoid slow pulls
set -e

CLUSTER_NAME="${1:-spiffe-demo}"

echo "=== Preloading SPIRE images into Kind cluster: $CLUSTER_NAME ==="

# Core SPIRE images
IMAGES=(
    "ghcr.io/spiffe/spire-server:1.13.2"
    "ghcr.io/spiffe/spire-agent:1.13.2"
    "ghcr.io/spiffe/spire-controller-manager:0.6.2"
    "ghcr.io/spiffe/spiffe-csi-driver:0.2.7"
    "ghcr.io/spiffe/spiffe-helper:0.11.0"
    "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.9.4"
    "busybox:1.37.0-uclibc"
)

for img in "${IMAGES[@]}"; do
    echo "Pulling $img..."
    docker pull "$img" || podman pull "$img"
done

echo ""
echo "Loading images into Kind cluster..."
for img in "${IMAGES[@]}"; do
    echo "Loading $img..."
    kind load docker-image "$img" --name "$CLUSTER_NAME" 2>/dev/null || \
    podman save "$img" | kind load image-archive /dev/stdin --name "$CLUSTER_NAME"
done

echo ""
echo "=== Done! Images preloaded into Kind cluster ==="
