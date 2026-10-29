#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
image_name=case-nest10-sd-probe:1

docker build -f "$project_dir/Dockerfile.sd-probe" -t "$image_name" "$project_dir"
docker run --rm \
  --network none \
  -v "$project_dir:/workspace" \
  -w /workspace \
  "$image_name" \
  sh ./scripts/build-sd-probe.sh
