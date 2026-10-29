#!/bin/sh
set -eu

if [ "$(uname -s)" != Darwin ]; then
  echo 'This wrapper is for macOS.' >&2
  exit 1
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)

if ! command -v docker >/dev/null 2>&1; then
  echo 'Docker Desktop is not installed or docker is not on PATH.' >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo 'Docker Desktop is not running. Start it, wait for the engine, then rerun this script.' >&2
  exit 1
fi

"$script_dir/build-sd-probe-container.sh"

image_path="$project_dir/output/images/sd-probe/nest10-sd-probe.img"
hash_path="$image_path.sha256"

[ -f "$image_path" ] || { echo "Missing probe image: $image_path" >&2; exit 1; }
[ -f "$hash_path" ] || { echo "Missing probe checksum: $hash_path" >&2; exit 1; }

(
  cd "$(dirname -- "$image_path")"
  shasum -a 256 -c "$(basename -- "$hash_path")"
)

echo
echo 'Build complete. Connected external physical disks:'
diskutil list external physical
echo
echo 'No disk has been modified.'
echo 'Review the disk identifier, then run the guarded writer explicitly, for example:'
echo '  ./scripts/write-sd-probe-macos.sh /dev/disk5'
