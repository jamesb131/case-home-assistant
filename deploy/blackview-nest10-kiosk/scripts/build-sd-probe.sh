#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
source_dir="$project_dir/sd-probe"
work_dir="$project_dir/output/sd-probe-work"
input_dir="$work_dir/input"
root_dir="$work_dir/root"
tmp_dir="$work_dir/tmp"
output_dir="$project_dir/output/images/sd-probe"
image_path="$output_dir/nest10-sd-probe.img"

for command in mkimage genimage sha256sum dd cmp mdir mtype; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command is unavailable: $command" >&2
    exit 1
  }
done

rm -rf "$work_dir" "$output_dir"
mkdir -p "$input_dir/boot" "$input_dir/case-probe" "$input_dir/NEST_PROBE_VISIBLE" "$root_dir" "$tmp_dir" "$output_dir"

mkimage \
  -A arm64 \
  -O linux \
  -T script \
  -C none \
  -n "CASE NEST10 SD scan probe" \
  -d "$source_dir/boot.cmd" \
  "$input_dir/boot.scr.uimg"

cp "$input_dir/boot.scr.uimg" "$input_dir/boot.scr"
cp "$input_dir/boot.scr.uimg" "$input_dir/boot/boot.scr.uimg"
cp "$input_dir/boot.scr.uimg" "$input_dir/boot/boot.scr"
cp "$source_dir/case-probe/input.txt" "$input_dir/case-probe/input.txt"
cp "$source_dir/NEST_PROBE_VISIBLE/README.txt" "$input_dir/NEST_PROBE_VISIBLE/README.txt"
cp "$source_dir/README.txt" "$input_dir/README.txt"

genimage \
  --rootpath "$root_dir" \
  --tmppath "$tmp_dir" \
  --inputpath "$input_dir" \
  --outputpath "$output_dir" \
  --config "$project_dir/board/nest10/genimage-sd-probe.cfg"

[ -f "$image_path" ] || {
  echo "Probe image was not produced: $image_path" >&2
  exit 1
}

# MBR data is confined to the first sector and the FAT partition starts at
# 1 MiB. Verify the entire intervening gap is empty. This includes Rockchip's
# conventional first-stage loader offset at sector 64 (32 KiB).
zero_file="$work_dir/zero-prepartition-gap.bin"
probe_window="$work_dir/image-prepartition-gap.bin"
dd if=/dev/zero of="$zero_file" bs=512 count=2047 status=none
dd if="$image_path" of="$probe_window" bs=512 skip=1 count=2047 status=none
if ! cmp -s "$zero_file" "$probe_window"; then
  echo "Safety check failed: the pre-partition gap contains unexpected data." >&2
  exit 1
fi

mkimage -l "$input_dir/boot.scr.uimg" >/dev/null
mdir -i "$image_path@@1048576" :: > "$work_dir/fat-root.txt"
mtype -i "$image_path@@1048576" ::/case-probe/input.txt > "$work_dir/extracted-input.txt"
if ! cmp -s "$source_dir/case-probe/input.txt" "$work_dir/extracted-input.txt"; then
  echo "Safety check failed: the guarded probe input was not packed correctly." >&2
  exit 1
fi

(
  cd "$output_dir"
  sha256sum "$(basename -- "$image_path")" > "$(basename -- "$image_path").sha256"
)

echo "Built non-destructive SD scan probe:"
echo "  $image_path"
echo "  $image_path.sha256"
echo "Verified: the complete MBR-to-FAT gap, including the 32 KiB Rockchip loader offset, is empty."
echo "This script creates an image file only; it never writes a removable disk."
