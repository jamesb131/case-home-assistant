#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
image=case-nest10-buildroot:2026.08.1

command -v docker >/dev/null 2>&1 || { echo 'Docker is required.' >&2; exit 1; }
docker build -t "$image" -f "$project_dir/Dockerfile.builder" "$project_dir"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp/home \
  -e JOBS="${JOBS:-}" \
  -v "$project_dir:/workspace" \
  -w /workspace \
  "$image" ./scripts/build.sh "$@"
