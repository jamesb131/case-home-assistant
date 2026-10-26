#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
dtb=${1:-"$project_dir/artifacts/nest10.dtb"}
output_dir="$project_dir/probe-output"
dts="$output_dir/nest10.dts"
summary="$output_dir/nest10-dtb-summary.txt"

command -v dtc >/dev/null 2>&1 || { echo 'dtc is required to inspect a device tree.' >&2; exit 1; }
[ -f "$dtb" ] || { echo "Missing device tree: $dtb" >&2; exit 1; }
mkdir -p "$output_dir"
dtc -I dtb -O dts -o "$dts" "$dtb"
{
  echo "Source: $dtb"
  sha256sum "$dtb"
  echo
  echo 'Relevant board declarations (review the full DTS as well):'
  grep -Ein 'model =|compatible =|panel|dsi|touch|goodix|focaltech|wifi|wireless|mmc|sdio|pwm-backlight|regulator' "$dts" || true
} >"$summary"
echo "Wrote $dts and $summary"
