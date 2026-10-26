#!/bin/sh
set -eu

buildroot_version=2026.08.1
buildroot_sha256=34fb7bea8a213ffde39cc02e61703391560f26e0850f03138c722d0b09880f2b

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
cache_dir="$project_dir/.cache"
archive="$cache_dir/buildroot-$buildroot_version.tar.xz"
source_dir="$cache_dir/buildroot-$buildroot_version"
profile=kiosk
configure_only=no
jobs=${JOBS:-}

usage() {
  cat <<'EOF'
Usage: scripts/build.sh [--profile bringup|kiosk] [--configure-only] [--jobs N]

Builds the root filesystem and kernel only. It does not assemble or write an SD
image, and it does not supply a board device tree or bootloader.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) profile=${2:?missing profile}; shift 2 ;;
    --configure-only) configure_only=yes; shift ;;
    --jobs) jobs=${2:?missing job count}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$profile" in bringup|kiosk) ;; *) echo "Invalid profile: $profile" >&2; exit 2 ;; esac
[ "$(uname -s)" = Linux ] || {
  echo 'Buildroot must be built on Linux. Use WSL2, a Linux VM, or scripts/build-container.sh.' >&2
  exit 1
}

for tool in curl make sha256sum tar; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing required tool: $tool" >&2; exit 1; }
done

mkdir -p "$cache_dir" "$project_dir/output/$profile"
if [ ! -f "$archive" ]; then
  curl -fL --retry 3 -o "$archive" "https://buildroot.org/downloads/buildroot-$buildroot_version.tar.xz"
fi
printf '%s  %s\n' "$buildroot_sha256" "$archive" | sha256sum -c -

if [ ! -f "$source_dir/Makefile" ]; then
  rm -rf "$source_dir"
  tar -C "$cache_dir" -xf "$archive"
fi

output_dir="$project_dir/output/$profile"
make -C "$source_dir" O="$output_dir" BR2_EXTERNAL="$project_dir" "nest10_${profile}_defconfig"
make -C "$source_dir" O="$output_dir" BR2_EXTERNAL="$project_dir" olddefconfig

require_selected() {
  symbol=$1
  grep -q "^${symbol}=y$" "$output_dir/.config" || {
    echo "Buildroot did not select required option: $symbol" >&2
    exit 1
  }
}
require_selected BR2_LINUX_KERNEL
require_selected BR2_TARGET_ROOTFS_EXT2
require_selected BR2_PACKAGE_WPA_SUPPLICANT
if [ "$profile" = kiosk ]; then
  require_selected BR2_PACKAGE_MESA3D_GALLIUM_DRIVER_PANFROST
  require_selected BR2_PACKAGE_WPEWEBKIT
  require_selected BR2_PACKAGE_COG_PLATFORM_DRM
  if grep -q '^BR2_PACKAGE_COG_PLATFORM_FDO=y$' "$output_dir/.config"; then
    echo 'Unexpected Cog Wayland backend selected; the kiosk is intended to use direct DRM.' >&2
    exit 1
  fi
fi

if [ "$configure_only" = yes ]; then
  echo "Configured $profile at $output_dir"
  exit 0
fi

if [ -z "$jobs" ]; then
  jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')
fi
make -C "$source_dir" O="$output_dir" BR2_EXTERNAL="$project_dir" -j"$jobs"
echo "Built $profile at $output_dir"
