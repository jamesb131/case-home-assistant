#!/bin/sh
set -eu

MODE="${1:-local}"
TARGETS="${2:-all}"
CONFIG_VERSION="$(sed -n 's/^version: "\([^"]*\)"/\1/p' case_core/config.yaml)"
VERSION="${CASE_HA_IMAGE_VERSION:-$CONFIG_VERSION}"
REGISTRY="${CASE_HA_IMAGE_REGISTRY:-ghcr.io/jamesb131/case-home-assistant}"
PLATFORMS="${CASE_HA_IMAGE_PLATFORMS:-linux/arm64,linux/amd64}"

if [ -z "$VERSION" ]; then
    echo "Could not determine CASE HA image version." >&2
    exit 2
fi

should_build() {
    target="$1"

    if [ "$TARGETS" = "all" ]; then
        return 0
    fi

    for selected in $TARGETS; do
        if [ "$selected" = "$target" ]; then
            return 0
        fi
    done

    return 1
}

case "$MODE" in
    local)
        if should_build "https-proxy"; then
            docker build \
                -f deploy/ha/case-https-proxy/Dockerfile \
                --build-arg BUILD_VERSION="$VERSION" \
                -t "$REGISTRY/case-https-proxy:$VERSION" \
                .
        fi

        if should_build "postgres"; then
            docker build \
                -f deploy/ha/case-postgres/Dockerfile \
                --build-arg BUILD_VERSION="$VERSION" \
                -t "$REGISTRY/case-postgres:$VERSION" \
                .
        fi

        if should_build "core"; then
            docker build \
                -f deploy/ha/case-core/Dockerfile \
                --build-arg BUILD_VERSION="$VERSION" \
                -t "$REGISTRY/case-core:$VERSION" \
                .
        fi
        ;;
    push)
        if should_build "https-proxy"; then
            docker buildx build \
                --platform "$PLATFORMS" \
                -f deploy/ha/case-https-proxy/Dockerfile \
                --build-arg BUILD_VERSION="$VERSION" \
                -t "$REGISTRY/case-https-proxy:$VERSION" \
                --push \
                .
        fi

        if should_build "postgres"; then
            docker buildx build \
                --platform "$PLATFORMS" \
                -f deploy/ha/case-postgres/Dockerfile \
                --build-arg BUILD_VERSION="$VERSION" \
                -t "$REGISTRY/case-postgres:$VERSION" \
                --push \
                .
        fi

        if should_build "core"; then
            docker buildx build \
                --platform "$PLATFORMS" \
                -f deploy/ha/case-core/Dockerfile \
                --build-arg BUILD_VERSION="$VERSION" \
                -t "$REGISTRY/case-core:$VERSION" \
                --push \
                .
        fi
        ;;
    *)
        echo "Usage: $0 [local|push] [all|core|postgres|https-proxy...]" >&2
        exit 2
        ;;
esac
