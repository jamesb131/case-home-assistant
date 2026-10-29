#!/bin/sh
set -eu

if [ "$(uname -s)" != Darwin ]; then
  echo 'This writer is for macOS.' >&2
  exit 1
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 /dev/diskN [--yes]" >&2
  exit 1
fi

target=$1
assume_yes=${2:-}
[ -z "$assume_yes" ] || [ "$assume_yes" = --yes ] || {
  echo 'The optional second argument may only be --yes.' >&2
  exit 1
}

case "$target" in
  /dev/disk[0-9]|/dev/disk[0-9][0-9]) ;;
  *) echo "Refusing target that is not a whole macOS disk: $target" >&2; exit 1 ;;
esac

disk_name=${target#/dev/}
partition="/dev/${disk_name}s1"
raw_target="/dev/r${disk_name}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
image="$project_dir/output/bootrom-sram-probe/nest10-bootrom-sram-probe.img"
hash_file="$image.sha256"
audit_file="$project_dir/output/bootrom-sram-probe/CONTENTS-AUDIT.txt"
disk_plist=$(mktemp -t nest10-bootrom-disk.XXXXXX)
partition_plist=$(mktemp -t nest10-bootrom-partition.XXXXXX)
readback=$(mktemp -t nest10-bootrom-readback.XXXXXX)
trap 'rm -f "$disk_plist" "$partition_plist" "$readback"' EXIT HUP INT TERM

[ -f "$image" ] || { echo "Missing BootROM probe: $image" >&2; exit 1; }
[ -f "$hash_file" ] || { echo "Missing probe checksum: $hash_file" >&2; exit 1; }
[ -f "$audit_file" ] || { echo "Missing probe audit: $audit_file" >&2; exit 1; }
[ -c "$raw_target" ] || { echo "Raw disk device is unavailable: $raw_target" >&2; exit 1; }

external_disks=$(diskutil list external physical | sed -n 's#^\(/dev/disk[0-9][0-9]*\).*$#\1#p')
printf '%s\n' "$external_disks" | grep -Fqx "$target" || {
  echo "Refusing disk that macOS does not report as external and physical: $target" >&2
  exit 1
}

diskutil list -plist "$target" > "$disk_plist"
diskutil info -plist "$partition" > "$partition_plist"
whole_disk=$(plutil -extract WholeDisks.0 raw -o - "$disk_plist")
internal=$(plutil -extract AllDisksAndPartitions.0.OSInternal raw -o - "$disk_plist")
disk_size=$(plutil -extract AllDisksAndPartitions.0.Size raw -o - "$disk_plist")
parent=$(plutil -extract ParentWholeDisk raw -o - "$partition_plist")
partition_offset=$(plutil -extract PartitionMapPartitionOffset raw -o - "$partition_plist")
volume_name=$(plutil -extract VolumeName raw -o - "$partition_plist")
mount_point=$(plutil -extract MountPoint raw -o - "$partition_plist")

[ "$whole_disk" = "$disk_name" ] && [ "$parent" = "$disk_name" ] || {
  echo "Unexpected disk or partition relationship for $target" >&2
  exit 1
}
[ "$internal" = false ] || { echo "Refusing internal disk: $target" >&2; exit 1; }
[ "$disk_size" -ge 1073741824 ] && [ "$disk_size" -le 137438953472 ] || {
  echo "Refusing unexpected target capacity: $disk_size bytes" >&2
  exit 1
}
[ "$partition_offset" -ge 1048576 ] || {
  echo "FAT partition begins too early: $partition_offset bytes" >&2
  exit 1
}
[ "$volume_name" = NEST_PROBE ] || {
  echo "Refusing volume not labelled NEST_PROBE: $volume_name" >&2
  exit 1
}
[ -f "$mount_point/README.txt" ] && [ -d "$mount_point/NEST_PROBE_VISIBLE" ] || {
  echo 'NEST probe filesystem markers are missing.' >&2
  exit 1
}

image_size=$(stat -f '%z' "$image")
[ "$image_size" -eq 4096 ] || { echo "Unexpected probe size: $image_size" >&2; exit 1; }
(
  cd "$(dirname -- "$image")"
  shasum -a 256 -c "$(basename -- "$hash_file")"
)

cp "$audit_file" "$mount_point/BOOTROM-SRAM-PROBE.txt"
sync

echo
echo 'RAW SD PROBE REVIEW'
echo "Probe:  $image ($image_size bytes)"
echo "Target: $target ($disk_size bytes)"
echo 'Write:  sectors 64-71 / bytes 32768-36863 only'
echo "FAT:    begins at byte $partition_offset and will not be overwritten"
diskutil list "$target"

if [ "$assume_yes" != --yes ]; then
  echo
  printf 'Type exactly "PROBE %s" to continue: ' "$disk_name"
  IFS= read -r confirmation
  [ "$confirmation" = "PROBE $disk_name" ] || {
    echo 'Confirmation did not match. Nothing was changed.'
    exit 1
  }
fi

diskutil unmountDisk "$target"
echo "Writing 4 KiB SRAM probe at sector 64 on $raw_target..."
sudo dd if="$image" of="$raw_target" bs=512 seek=64 conv=notrunc
sync
sudo dd if="$raw_target" of="$readback" bs=512 skip=64 count=8
sudo chmod 644 "$readback"

echo 'Comparing readback of sectors 64-71...'
cmp "$image" "$readback"

diskutil eject "$target"
echo 'BootROM SRAM probe written, verified and ejected.'
echo 'Card removal restores the original internal boot path.'
