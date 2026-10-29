#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
app_dir="$project_dir/android-kiosk"
output_dir="$project_dir/artifacts/android-kiosk"
image="reactivecircus/android-sdk-30:latest"

mkdir -p "$output_dir"

docker run --rm --platform linux/amd64 \
  -v "$app_dir:/src:ro" \
  -v "$output_dir:/output" \
  "$image" bash -eu -c '
sdk="$ANDROID_SDK_ROOT"
tools="$sdk/build-tools/$ANDROID_BUILD_TOOLS_VERSION"
work=/tmp/case-kiosk
rm -rf "$work"
mkdir -p "$work/classes" "$work/dex"

"$tools/aapt" package -f \
  -M /src/AndroidManifest.xml \
  -S /src/res \
  -I "$sdk/platforms/android-30/android.jar" \
  -F "$work/unsigned.apk"

javac -source 8 -target 8 -Xlint:deprecation \
  -classpath "$sdk/platforms/android-30/android.jar" \
  -d "$work/classes" \
  $(find /src/src -name "*.java" -print)

"$tools/d8" --min-api 23 --lib "$sdk/platforms/android-30/android.jar" \
  --output "$work/dex" \
  $(find "$work/classes" -name "*.class" -print)
(cd "$work/dex" && "$tools/aapt" add "$work/unsigned.apk" classes.dex >/dev/null)
"$tools/zipalign" -f 4 "$work/unsigned.apk" "$work/aligned.apk"

keystore=/output/case-kiosk.keystore
if [ ! -f "$keystore" ]; then
  keytool -genkeypair -noprompt \
    -keystore "$keystore" -storepass case-kiosk -keypass case-kiosk \
    -alias case-kiosk -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=CASE Kiosk, OU=Local, O=CASE, L=Perth, C=AU"
fi

"$tools/apksigner" sign \
  --ks "$keystore" --ks-pass pass:case-kiosk --key-pass pass:case-kiosk \
  --out /output/case-kiosk.apk "$work/aligned.apk"
"$tools/apksigner" verify --verbose /output/case-kiosk.apk
'

shasum -a 256 "$output_dir/case-kiosk.apk" > "$output_dir/case-kiosk.apk.sha256"
echo "Built $output_dir/case-kiosk.apk"
