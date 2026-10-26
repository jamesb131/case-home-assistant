#!/bin/sh
set -eu

target_dir="$1"

mkdir -p "$target_dir/boot" "$target_dir/var/lib/case-kiosk" "$target_dir/var/log"
chmod 0755 "$target_dir/etc/init.d/S35case-network" "$target_dir/etc/init.d/S99case-kiosk"
