#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)

required='external.desc Config.in external.mk configs/nest10_bringup_defconfig configs/nest10_kiosk_defconfig board/nest10/linux.fragment board/nest10/genimage-vendor-chain.cfg board/nest10/genimage-standalone.cfg scripts/build.sh scripts/assemble-sd-image.sh README.md RESEARCH.md'
for relative in $required; do
  [ -f "$project_dir/$relative" ] || { echo "Missing required file: $relative" >&2; exit 1; }
done

for script in "$project_dir"/scripts/*.sh "$project_dir"/board/nest10/post-build.sh "$project_dir"/board/nest10/rootfs-overlay/etc/init.d/S*; do
  sh -n "$script"
done

if grep -REn --exclude=validate.sh 'fastboot[[:space:]]+(flash|erase|format|flashing unlock|oem unlock)|rkdeveloptool[[:space:]]+(wl|ef)|dd[[:space:]].*of=/dev/' \
  "$project_dir/scripts" "$project_dir/board" "$project_dir/Makefile" "$project_dir/Dockerfile.builder"; then
  echo 'Destructive device command found.' >&2
  exit 1
fi

if [ "${VALIDATE_BUILDROOT_CONFIGS:-no}" = yes ]; then
  "$project_dir/scripts/build.sh" --profile bringup --configure-only
  "$project_dir/scripts/build.sh" --profile kiosk --configure-only
fi

echo 'Static validation passed.'
echo 'Set VALIDATE_BUILDROOT_CONFIGS=yes on Linux to also resolve both Buildroot configurations.'
