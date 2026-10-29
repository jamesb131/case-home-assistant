#!/bin/sh
set -eu

if [ "$(uname -s)" != Darwin ]; then
  echo 'This writer is for macOS.' >&2
  exit 1
fi

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /dev/diskN" >&2
  echo 'Pass a whole external disk explicitly. Partition identifiers are rejected.' >&2
  exit 1
fi

target=$1
case "$target" in
  /dev/disk[0-9]|/dev/disk[0-9][0-9]) ;;
  *) echo "Refusing target that is not a whole macOS disk: $target" >&2; exit 1 ;;
esac

disk_name=${target#/dev/}
raw_target="/dev/r${disk_name}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
image_path="$project_dir/output/images/sd-probe/nest10-sd-probe.img"
hash_path="$image_path.sha256"
plist_path=$(mktemp -t nest10-sd-probe.XXXXXX)
trap 'rm -f "$plist_path"' EXIT HUP INT TERM

[ -f "$image_path" ] || { echo "Missing probe image: $image_path" >&2; exit 1; }
[ -f "$hash_path" ] || { echo "Missing probe checksum: $hash_path" >&2; exit 1; }
[ -c "$raw_target" ] || { echo "Raw disk device is unavailable: $raw_target" >&2; exit 1; }

external_disks=$(diskutil list external physical | sed -n 's#^\(/dev/disk[0-9][0-9]*\).*$#\1#p')
if ! printf '%s\n' "$external_disks" | grep -Fqx "$target"; then
  echo "Refusing disk that macOS does not report as external and physical: $target" >&2
  exit 1
fi

diskutil list -plist "$target" > "$plist_path"
whole_disk=$(plutil -extract WholeDisks.0 raw -o - "$plist_path")
internal=$(plutil -extract AllDisksAndPartitions.0.OSInternal raw -o - "$plist_path")
disk_size=$(plutil -extract AllDisksAndPartitions.0.Size raw -o - "$plist_path")

[ "$whole_disk" = "$disk_name" ] || {
  echo "Refusing partition or unexpected disk metadata: $target" >&2
  exit 1
}
[ "$internal" = false ] || {
  echo "Refusing internal disk: $target" >&2
  exit 1
}

# The connected test card is 31.9 GB. Refuse tiny devices and disks larger than
# 128 GiB so a normal external SSD is less likely to be selected accidentally.
[ "$disk_size" -ge 1073741824 ] && [ "$disk_size" -le 137438953472 ] || {
  echo "Refusing unexpected target capacity: $disk_size bytes" >&2
  exit 1
}

image_size=$(stat -f '%z' "$image_path")
[ "$image_size" -gt 1048576 ] && [ "$image_size" -lt 536870912 ] || {
  echo "Refusing unexpected probe image size: $image_size bytes" >&2
  exit 1
}

(
  cd "$(dirname -- "$image_path")"
  shasum -a 256 -c "$(basename -- "$hash_path")"
)

echo
echo 'DESTRUCTIVE TARGET REVIEW'
echo "Image:  $image_path ($image_size bytes)"
echo "Target: $target ($disk_size bytes)"
diskutil list "$target"
echo
echo 'Every existing partition and file on the target will be overwritten.'
printf 'Type exactly "ERASE %s" to continue: ' "$disk_name"
IFS= read -r confirmation
[ "$confirmation" = "ERASE $disk_name" ] || {
  echo 'Confirmation did not match. Nothing was changed.'
  exit 1
}

diskutil unmountDisk "$target"
echo "Writing probe image to $raw_target..."
sudo dd if="$image_path" of="$raw_target" bs=4m
sync

echo 'Performing byte-for-byte readback verification...'
sudo cmp -n "$image_size" "$image_path" "$raw_target"

diskutil eject "$target"
echo
echo 'SD probe written, verified and ejected successfully.'
echo 'Remove and reinsert it to inspect NEST_PROBE before using it in the NEST 10.'
