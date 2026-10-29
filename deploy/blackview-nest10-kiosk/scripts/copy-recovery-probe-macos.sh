#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
volume=${1:-/Volumes/NEST_PROBE}
source_zip="$project_dir/output/recovery-signature-probe/NEST10-AOSP-TESTKEY-SIGNATURE-PROBE.zip"
source_hash="$source_zip.sha256"

[ -d "$volume" ] || { echo "Probe volume is not mounted: $volume" >&2; exit 1; }
[ -f "$volume/README.txt" ] || { echo "Volume does not contain the NEST probe marker: $volume/README.txt" >&2; exit 1; }
[ -d "$volume/NEST_PROBE_VISIBLE" ] || { echo "Volume does not contain NEST_PROBE_VISIBLE: $volume" >&2; exit 1; }
[ -f "$source_zip" ] || { echo "Build the Recovery probe first: $source_zip" >&2; exit 1; }
[ -f "$source_hash" ] || { echo "Missing package hash: $source_hash" >&2; exit 1; }

expected=$(awk '{ print $1 }' "$source_hash")
actual=$(shasum -a 256 "$source_zip" | awk '{ print $1 }')
[ "$actual" = "$expected" ] || { echo 'Recovery probe hash check failed.' >&2; exit 1; }

destination="$volume/$(basename "$source_zip")"
cp -f "$source_zip" "$destination"
sync

card_hash=$(shasum -a 256 "$destination" | awk '{ print $1 }')
[ "$card_hash" = "$expected" ] || { echo 'Recovery probe card readback failed.' >&2; exit 1; }

echo "Copied and verified: $destination"
echo "SHA-256: $card_hash"
echo 'Eject the card in Finder before removing it.'
