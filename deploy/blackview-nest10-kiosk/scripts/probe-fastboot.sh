#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
output_dir="$project_dir/probe-output"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
output="$output_dir/fastboot-$timestamp.txt"

command -v fastboot >/dev/null 2>&1 || { echo 'fastboot is not installed or is not on PATH.' >&2; exit 1; }
mkdir -p "$output_dir"
devices=$(fastboot devices 2>&1 || true)
printf '%s\n' "$devices" | grep -q '[[:space:]]fastboot$' || {
  echo 'No device is currently visible in fastboot mode.' >&2
  exit 1
}
{
  echo "Captured: $timestamp"
  echo "$devices"
  echo 'Read-only fastboot getvars follow.'
  for variable in \
    product secure unlocked current-slot slot-count version-bootloader \
    has-slot:boot has-slot:dtbo has-slot:vbmeta has-slot:vendor_boot has-slot:super \
    partition-size:boot_a partition-size:boot_b \
    partition-size:dtbo_a partition-size:dtbo_b \
    partition-size:vbmeta_a partition-size:vbmeta_b \
    partition-size:vendor_boot_a partition-size:vendor_boot_b \
    partition-size:super max-download-size; do
    echo "--- $variable ---"
    fastboot getvar "$variable" 2>&1 || true
  done
} >"$output"
echo "Wrote read-only probe: $output"
