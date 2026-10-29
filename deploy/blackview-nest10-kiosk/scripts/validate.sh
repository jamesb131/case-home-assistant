#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)

required='external.desc Config.in external.mk configs/nest10_bringup_defconfig configs/nest10_kiosk_defconfig board/nest10/linux.fragment board/nest10/genimage-sd-probe.cfg board/nest10/genimage-vendor-chain.cfg board/nest10/genimage-standalone.cfg sd-probe/boot.cmd sd-probe/case-probe/input.txt sd-probe/NEST_PROBE_VISIBLE/README.txt sd-probe/README.txt recovery-probe/README.txt scripts/build-sd-probe.sh scripts/build-sd-probe-container.sh scripts/prepare-sd-probe-macos.sh scripts/write-sd-probe-macos.sh scripts/Build-SdProbe.ps1 scripts/build-recovery-signature-probe.sh scripts/build-recovery-signature-probe-container.sh scripts/copy-recovery-probe-macos.sh scripts/build-bootrom-sram-probe.sh scripts/build-bootrom-sram-probe-container.sh scripts/write-bootrom-sram-probe-macos.sh scripts/build.sh scripts/assemble-sd-image.sh README.md RESEARCH.md SD-PROBE.md RECOVERY-PROBE.md BOOTROM-PROBE.md FIRMWARE-REQUEST.md'
required="$required scripts/probe-adups-fota.py"
for relative in $required; do
  [ -f "$project_dir/$relative" ] || { echo "Missing required file: $relative" >&2; exit 1; }
done

for script in "$project_dir"/scripts/*.sh "$project_dir"/board/nest10/post-build.sh "$project_dir"/board/nest10/rootfs-overlay/etc/init.d/S*; do
  sh -n "$script"
done

if grep -REn --exclude=validate.sh 'fastboot[[:space:]]+(flash|erase|format|flashing unlock|oem unlock)|rkdeveloptool[[:space:]]+(wl|ef)|dd[[:space:]].*of=/dev/|mmc[[:space:]]+(write|erase)|saveenv' \
  "$project_dir/scripts" "$project_dir/board" "$project_dir/sd-probe/boot.cmd" "$project_dir/Makefile" "$project_dir"/Dockerfile.*; then
  echo 'Destructive device command found.' >&2
  exit 1
fi

if grep -En 'idbloader|u-boot\.(itb|bin)|Image|\.dtb|rootfs' "$project_dir/board/nest10/genimage-sd-probe.cfg" "$project_dir/sd-probe/boot.cmd"; then
  echo 'The stage-one SD probe must not contain a loader, kernel, DTB or root filesystem.' >&2
  exit 1
fi

unexpected_recovery_files=$(find "$project_dir/recovery-probe" -type f ! -name README.txt -print)
if [ -n "$unexpected_recovery_files" ]; then
  echo 'The Recovery signature probe source may contain only README.txt.' >&2
  printf '%s\n' "$unexpected_recovery_files" >&2
  exit 1
fi

mac_writer="$project_dir/scripts/write-sd-probe-macos.sh"
for marker in 'diskutil list external physical' 'OSInternal' 'ERASE \$disk_name' 'sudo cmp -n'; do
  grep -q "$marker" "$mac_writer" || {
    echo "macOS writer safety marker is missing: $marker" >&2
    exit 1
  }
done

bootrom_writer="$project_dir/scripts/write-bootrom-sram-probe-macos.sh"
for marker in 'diskutil list external physical' 'PartitionMapPartitionOffset' 'VolumeName' 'bs=512 seek=64' 'bs=512 skip=64 count=8'; do
  grep -q "$marker" "$bootrom_writer" || {
    echo "BootROM writer safety marker is missing: $marker" >&2
    exit 1
  }
done

if [ "${VALIDATE_BUILDROOT_CONFIGS:-no}" = yes ]; then
  "$project_dir/scripts/build.sh" --profile bringup --configure-only
  "$project_dir/scripts/build.sh" --profile kiosk --configure-only
fi

echo 'Static validation passed.'
echo 'Set VALIDATE_BUILDROOT_CONFIGS=yes on Linux to also resolve both Buildroot configurations.'
