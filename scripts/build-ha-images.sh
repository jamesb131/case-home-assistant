#!/bin/sh
set -eu

MODE="${1:-local}"
VERSION="${CASE_HA_IMAGE_VERSION:-0.1.0}"
REGISTRY="${CASE_HA_IMAGE_REGISTRY:-ghcr.io/jamesb131/case-home-assistant}"
PLATFORMS="${CASE_HA_IMAGE_PLATFORMS:-linux/arm64,linux/amd64}"

case "$MODE" in
    local)
        docker build \
            -f deploy/ha/case-postgres/Dockerfile \
            -t "$REGISTRY/case-postgres:$VERSION" \
            .

        docker build \
            -f deploy/ha/case-core/Dockerfile \
            -t "$REGISTRY/case-core:$VERSION" \
            .
        ;;
    push)
        docker buildx build \
            --platform "$PLATFORMS" \
            -f deploy/ha/case-postgres/Dockerfile \
            -t "$REGISTRY/case-postgres:$VERSION" \
            --push \
            .

        docker buildx build \
            --platform "$PLATFORMS" \
            -f deploy/ha/case-core/Dockerfile \
            -t "$REGISTRY/case-core:$VERSION" \
            --push \
            .
        ;;
    *)
        echo "Usage: $0 [local|push]" >&2
        exit 2
        ;;
esac
