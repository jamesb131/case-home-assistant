#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
profile=kiosk
mode=vendor-chain

usage() {
  cat <<'EOF'
Usage: scripts/assemble-sd-image.sh [--profile bringup|kiosk] [--mode vendor-chain|standalone]

Creates an image file under output/images. It never writes to a block device.
Exact board artifacts and their confirmed hashes are mandatory.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) profile=${2:?missing profile}; shift 2 ;;
    --mode) mode=${2:?missing mode}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$profile" in bringup|kiosk) ;; *) echo "Invalid profile: $profile" >&2; exit 2 ;; esac
case "$mode" in vendor-chain|standalone) ;; *) echo "Invalid mode: $mode" >&2; exit 2 ;; esac

images_dir="$project_dir/output/$profile/images"
host_dir="$project_dir/output/$profile/host"
artifact_dir="$project_dir/artifacts"
confirmation="$artifact_dir/artifacts.local.env"
staging="$project_dir/output/image-staging-$profile-$mode"
output_dir="$project_dir/output/images/$profile-$mode"

[ -r "$confirmation" ] || { echo "Missing $confirmation; copy the example and record reviewed hashes." >&2; exit 1; }
read_setting() {
  key=$1
  sed -n "s/^${key}=//p" "$confirmation" | head -n 1
}
artifacts_confirmed=$(read_setting NEST10_ARTIFACTS_CONFIRMED)
dtb_sha256=$(read_setting NEST10_DTB_SHA256)
idbloader_sha256=$(read_setting NEST10_IDBLOADER_SHA256)
uboot_sha256=$(read_setting NEST10_UBOOT_SHA256)
[ "$artifacts_confirmed" = yes ] || { echo 'Board artifact provenance has not been confirmed.' >&2; exit 1; }

hash_file() {
  expected=$1
  file=$2
  [ -f "$file" ] || { echo "Missing exact-board artifact: $file" >&2; exit 1; }
  [ -n "$expected" ] && [ "$expected" != replace-me ] || { echo "Missing expected hash for $file" >&2; exit 1; }
  printf '%s  %s\n' "$expected" "$file" | sha256sum -c -
}

hash_file "$dtb_sha256" "$artifact_dir/nest10.dtb"
[ "$(od -An -tx1 -N4 "$artifact_dir/nest10.dtb" | tr -d ' \n')" = d00dfeed ] || {
  echo 'nest10.dtb does not have a flattened-device-tree header.' >&2
  exit 1
}
if [ "$mode" = standalone ]; then
  hash_file "$idbloader_sha256" "$artifact_dir/idbloader.img"
  hash_file "$uboot_sha256" "$artifact_dir/u-boot.itb"
fi

for file in Image rootfs.ext4; do
  [ -s "$images_dir/$file" ] || { echo "Missing build output: $images_dir/$file" >&2; exit 1; }
done
[ -x "$host_dir/bin/genimage" ] || { echo 'Missing host genimage; run the Buildroot build first.' >&2; exit 1; }

rm -rf "$staging" "$output_dir"
mkdir -p "$staging/input/extlinux" "$staging/root" "$staging/tmp" "$output_dir"
cp "$images_dir/Image" "$images_dir/rootfs.ext4" "$staging/input/"
cp "$artifact_dir/nest10.dtb" "$staging/input/"
cp "$project_dir/board/nest10/extlinux.conf" "$staging/input/extlinux/"
cp "$project_dir/board/nest10/rootfs-overlay/etc/case-kiosk.env.example" "$staging/input/"
if [ "$mode" = standalone ]; then
  cp "$artifact_dir/idbloader.img" "$artifact_dir/u-boot.itb" "$staging/input/"
fi

"$host_dir/bin/genimage" \
  --rootpath "$staging/root" \
  --tmppath "$staging/tmp" \
  --inputpath "$staging/input" \
  --outputpath "$output_dir" \
  --config "$project_dir/board/nest10/genimage-$mode.cfg"

image="$output_dir/nest10-$mode.img"
[ -s "$image" ] || { echo "Image was not created: $image" >&2; exit 1; }
sha256sum "$image" >"$image.sha256"
echo "Created image file only: $image"
echo 'Use a trusted imaging application to write it to a removable SD card after checking the device twice.'
