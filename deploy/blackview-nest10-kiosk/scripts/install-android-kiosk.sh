#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
apk="$project_dir/artifacts/android-kiosk/case-kiosk.apk"
url=${1:-https://case.local/}

[ -f "$apk" ] || { echo "Build the APK first with scripts/build-android-kiosk.sh" >&2; exit 1; }
adb get-state >/dev/null
adb install -r "$apk"
adb shell am force-stop com.casehome.kiosk
adb shell am start -n com.casehome.kiosk/.MainActivity --es url "$url"

cat <<EOF
CASE Kiosk launched for testing at:
  $url

The existing Blackview launcher is unchanged. After visual verification, run:
  $script_dir/enable-android-kiosk.sh
EOF
