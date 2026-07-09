#!/bin/sh
set -eu

MODE="${1:-local}"
CONFIG_VERSION="$(sed -n 's/^version: "\([^"]*\)"/\1/p' case_core/config.yaml)"
VERSION="${CASE_HA_IMAGE_VERSION:-$CONFIG_VERSION}"
REGISTRY="${CASE_HA_IMAGE_REGISTRY:-ghcr.io/jamesb131/case-home-assistant}"
PLATFORMS="${CASE_HA_IMAGE_PLATFORMS:-linux/arm64,linux/amd64}"

if [ -z "$VERSION" ]; then
    echo "Could not determine CASE HA image version." >&2
    exit 2
fi

case "$MODE" in
    local)
        docker build \
            -f deploy/ha/case-https-proxy/Dockerfile \
            --build-arg BUILD_VERSION="$VERSION" \
            -t "$REGISTRY/case-https-proxy:$VERSION" \
            .

        docker build \
            -f deploy/ha/case-postgres/Dockerfile \
            --build-arg BUILD_VERSION="$VERSION" \
            -t "$REGISTRY/case-postgres:$VERSION" \
            .

        docker build \
            -f deploy/ha/case-core/Dockerfile \
            --build-arg BUILD_VERSION="$VERSION" \
            -t "$REGISTRY/case-core:$VERSION" \
            .
        ;;
    push)
        docker buildx build \
            --platform "$PLATFORMS" \
            -f deploy/ha/case-https-proxy/Dockerfile \
            --build-arg BUILD_VERSION="$VERSION" \
            -t "$REGISTRY/case-https-proxy:$VERSION" \
            --push \
            .

        docker buildx build \
            --platform "$PLATFORMS" \
            -f deploy/ha/case-postgres/Dockerfile \
            --build-arg BUILD_VERSION="$VERSION" \
            -t "$REGISTRY/case-postgres:$VERSION" \
            --push \
            .

        docker buildx build \
            --platform "$PLATFORMS" \
            -f deploy/ha/case-core/Dockerfile \
            --build-arg BUILD_VERSION="$VERSION" \
            -t "$REGISTRY/case-core:$VERSION" \
            --push \
            .
        ;;
    *)
        echo "Usage: $0 [local|push]" >&2
        exit 2
        ;;
esac
