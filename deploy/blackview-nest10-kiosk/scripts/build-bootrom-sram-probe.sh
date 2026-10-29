#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
work_dir="$project_dir/output/bootrom-sram-probe-work"
output_dir="$project_dir/output/bootrom-sram-probe"
payload="$work_dir/spin.bin"
image="$output_dir/nest10-bootrom-sram-probe.img"
expected="$work_dir/expected-entry.bin"
actual="$work_dir/actual-entry.bin"

for command in mkimage sha256sum dd cmp od; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command is unavailable: $command" >&2
    exit 1
  }
done

rm -rf "$work_dir" "$output_dir"
mkdir -p "$work_dir" "$output_dir"

# Rockchip reserves the first four payload bytes for its RK33 tag. The sole
# instruction after that tag is AArch64 `b .` (0x14000000, little-endian), an
# infinite loop which requires no stack, DRAM, peripherals or storage access.
dd if=/dev/zero of="$payload" bs=4 count=1 status=none
printf '\000\000\000\024' >> "$payload"

mkimage -n px30 -T rksd -d "$payload" "$image"

image_size=$(stat -c '%s' "$image")
[ "$image_size" -eq 4096 ] || {
  echo "Unexpected Rockchip probe size: $image_size bytes" >&2
  exit 1
}

printf 'RK33\000\000\000\024' > "$expected"
dd if="$image" of="$actual" bs=1 skip=2048 count=8 status=none
cmp "$expected" "$actual"

# Everything after the eight-byte entry sequence must be zero padding. This
# proves the loaded payload contains no additional executable logic.
tail_file="$work_dir/payload-tail.bin"
zero_file="$work_dir/zero-tail.bin"
dd if="$image" of="$tail_file" bs=1 skip=2056 status=none
dd if=/dev/zero of="$zero_file" bs=1 count=2040 status=none
cmp "$zero_file" "$tail_file"

(
  cd "$output_dir"
  sha256sum "$(basename -- "$image")" > "$(basename -- "$image").sha256"
)

cat > "$output_dir/CONTENTS-AUDIT.txt" <<EOF
Probe: $(basename "$image")
Image size: 4096 bytes
Rockchip format: px30 RK33 SD/MMC first stage
Card offset: sector 64 / byte 32768
BootROM SRAM base: 0xff0e1000
Entry: 0xff0e1004
Entry instruction: 0x14000000 / AArch64 b .
Payload behavior: infinite loop
Stack use: none
DRAM initialization: none
Peripheral access: none
Storage reads: none
Storage writes: none
Internal flash access: none

Entry bytes at image offset 2048:
$(od -An -tx1 -j 2048 -N 8 "$image" | tr -s ' ' | sed 's/^ //')
EOF

echo "Built SRAM-only Rockchip BootROM probe: $image"
cat "$image.sha256"
echo 'Verified: the only payload instruction is an infinite loop.'
