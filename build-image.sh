#!/bin/bash

set -e

# Parse command line arguments
PUSH=false
REPO=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH=true
            REPO="$2"
            if [ -z "$REPO" ]; then
                echo "Error: --push requires a repository argument"
                echo "Usage: $0 [--push <repo>[:<tag>]]"
                exit 1
            fi
            shift 2
            ;;
        *)
            echo "Usage: $0 [--push <repo>[:<tag>]]"
            exit 1
            ;;
    esac
done

cd "$(dirname "$0")"

echo "=========================================="
echo "Building OpenSSH Server Installer"
echo "=========================================="

echo "Checking required files..."
for file in scripts/install-openssh.sh docker/Dockerfile; do
    if [[ ! -f "$file" ]]; then
        echo "Missing required file: $file"
        exit 1
    fi
done

# Check if buildkit_20 already exists before creating it
if ! docker buildx inspect buildkit_20 &>/dev/null; then
    docker buildx create --use --driver-opt image=moby/buildkit:v0.20.2 --name buildkit_20
fi

git rev-parse HEAD > .GIT_REV
TEMP_TAG="dstack-openssh-installer-temp:$(date +%s)"

docker buildx build --builder buildkit_20 --no-cache --platform linux/amd64 \
    -f docker/Dockerfile \
    --build-arg SOURCE_DATE_EPOCH="0" \
    --build-arg DSTACK_REV="$(cat .GIT_REV)" \
    --output type=oci,dest=./oci.tar,rewrite-timestamp=true \
    --output type=docker,name="$TEMP_TAG",rewrite-timestamp=true .

if [ "$?" -ne 0 ]; then
    echo "Build failed"
    rm -f .GIT_REV
    exit 1
fi

echo ""
echo "Build completed, manifest digest:"
echo ""
skopeo inspect oci-archive:./oci.tar | jq .Digest
echo ""

if [ "$PUSH" = true ]; then
    echo "Pushing image to $REPO..."
    skopeo copy --insecure-policy oci-archive:./oci.tar docker://"$REPO"
    echo "Image pushed successfully to $REPO"
else
    echo "To push the image to a registry, run:"
    echo ""
    echo " $0 --push <repo>[:<tag>]"
    echo ""
    echo "Or use skopeo directly:"
    echo ""
    echo " skopeo copy --insecure-policy oci-archive:./oci.tar docker://<repo>[:<tag>]"
    echo ""
fi
echo ""

# Clean up the temporary image from Docker daemon
docker rmi "$TEMP_TAG" 2>/dev/null || true
rm -f .GIT_REV

echo "=========================================="
echo "Build Complete!"
echo "=========================================="
echo ""
echo "OCI archive: ./oci.tar"
echo ""
echo "Usage (after pushing or loading):"
echo ""
echo "Single-command installation (with SSH public key):"
echo "  docker run --rm --privileged --pid=host --net=host -v /:/host \\"
echo "    -e SSH_PUBKEY=\"ssh-ed25519 AAAA... user@host\" \\"
echo "    <repo>[:<tag>]"
echo ""
echo "Interactive installation:"
echo "  docker run -it --rm --privileged --pid=host --net=host -v /:/host \\"
echo "    <repo>[:<tag>] bash"
echo ""
echo "Check build info:"
echo "  docker run --rm <repo>[:<tag>] cat /usr/local/share/BUILD_INFO"
echo ""
