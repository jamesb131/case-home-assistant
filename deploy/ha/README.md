# Home Assistant image builds

This directory contains Dockerfiles for the Home Assistant Green app images.

## Images

- `deploy/ha/case-postgres/Dockerfile`
- `deploy/ha/case-core/Dockerfile`

The images are designed for `linux/arm64` on the Green and `linux/amd64` for
local smoke tests.

## Build locally

```bash
scripts/build-ha-images.sh local
```

## Build and push multi-arch images

```bash
scripts/build-ha-images.sh push
```

The pushed image names match the add-on manifests:

```text
ghcr.io/jamesb131/case-home-assistant/case-postgres:0.1.0
ghcr.io/jamesb131/case-home-assistant/case-core:0.1.0
```
