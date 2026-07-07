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

Routine publishes should use GitHub Actions instead of local GHCR tokens:

```text
.github/workflows/publish-ha-images.yml
```

The pushed image names match the add-on manifests:

```text
ghcr.io/jamesb131/case-home-assistant/case-postgres:<config version>
ghcr.io/jamesb131/case-home-assistant/case-core:<config version>
```

The tag is derived from `case_core/config.yaml` unless
`CASE_HA_IMAGE_VERSION` is explicitly set.
