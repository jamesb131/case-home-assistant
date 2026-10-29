#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
work_dir="$project_dir/output/recovery-signature-probe-work"
output_dir="$project_dir/output/recovery-signature-probe"
download_dir="$work_dir/aosp"
unsigned_zip="$work_dir/nest10-recovery-signature-probe-unsigned.zip"
signed_zip="$output_dir/NEST10-AOSP-TESTKEY-SIGNATURE-PROBE.zip"

signapk_url='https://android.googlesource.com/platform/build/+/refs/tags/android-6.0.1_r81/tools/signapk/SignApk.java?format=TEXT'
certificate_url='https://android.googlesource.com/platform/build/+/refs/tags/android-11.0.0_r48/target/product/security/testkey.x509.pem?format=TEXT'
private_key_url='https://android.googlesource.com/platform/build/+/refs/tags/android-11.0.0_r48/target/product/security/testkey.pk8?format=TEXT'

signapk_sha256='90b533f6a7da8592e76188c0122c7d52129a8e68b3f7525a35b73003e03ea60c'
certificate_sha256='a4384ba815b9499a5ce349b4e33c1755278873fe2eac150a068823f526e6dbde'
private_key_sha256='495675d32e89a149d5abe191f4e9c0e218b9068714e9b53a7c91e164a0741a23'

rm -rf "$work_dir" "$output_dir"
mkdir -p "$download_dir" "$work_dir/classes" "$work_dir/package" "$output_dir"

download_base64() {
  url=$1
  destination=$2
  expected_hash=$3

  curl -fsSL "$url" | base64 -d > "$destination"
  printf '%s  %s\n' "$expected_hash" "$destination" | sha256sum -c -
}

download_base64 "$signapk_url" "$download_dir/SignApk.java" "$signapk_sha256"
download_base64 "$certificate_url" "$download_dir/testkey.x509.pem" "$certificate_sha256"
download_base64 "$private_key_url" "$download_dir/testkey.pk8" "$private_key_sha256"

classpath='/usr/share/java/bcprov.jar:/usr/share/java/bcpkix.jar:/usr/share/java/bcutil.jar'
javac -cp "$classpath" -d "$work_dir/classes" "$download_dir/SignApk.java"

cp "$project_dir/recovery-probe/README.txt" "$work_dir/package/README.txt"
(
  cd "$work_dir/package"
  zip -X -q "$unsigned_zip" README.txt
)

java -cp "$work_dir/classes:$classpath" com.android.signapk.SignApk -w \
  "$download_dir/testkey.x509.pem" \
  "$download_dir/testkey.pk8" \
  "$unsigned_zip" \
  "$signed_zip"

entries_file="$work_dir/signed-entries.txt"
unzip -Z1 "$signed_zip" | tee "$entries_file"

if grep -Eiq '(^|/)(update-binary|updater-script|payload\.bin|payload_properties\.txt)$|\.(img|bin|dtb|dtbo|itb)$' "$entries_file"; then
  echo 'Refusing recovery probe containing an executable payload or boot artifact.' >&2
  exit 1
fi

for required_entry in README.txt META-INF/MANIFEST.MF META-INF/CERT.SF META-INF/CERT.RSA META-INF/com/android/otacert; do
  grep -Fxq "$required_entry" "$entries_file" || {
    echo "Signed recovery probe is missing: $required_entry" >&2
    exit 1
  }
done

python3 - "$signed_zip" <<'PY'
import pathlib
import struct
import sys

package = pathlib.Path(sys.argv[1])
data = package.read_bytes()
if len(data) < 6:
    raise SystemExit("Signed package is too small")

signature_start, marker, comment_size = struct.unpack("<HHH", data[-6:])
if marker != 0xFFFF:
    raise SystemExit("Signed package lacks the Android whole-file signature marker")
if comment_size < signature_start or comment_size + 22 > len(data):
    raise SystemExit("Signed package has an invalid whole-file signature footer")

print(f"Android whole-file signature footer: signature={signature_start} bytes, comment={comment_size} bytes")
PY

sha256sum "$signed_zip" > "$signed_zip.sha256"
cat > "$output_dir/CONTENTS-AUDIT.txt" <<EOF
Package: $(basename "$signed_zip")
Purpose: AOSP test-key trust probe for stock Android Recovery
Executable updater: absent
Updater script: absent
Payload: absent
Partition images: absent
Kernel/DTB/bootloader: absent

Archive entries:
$(cat "$entries_file")
EOF

echo
echo "Recovery signature probe built: $signed_zip"
cat "$signed_zip.sha256"
echo 'The package is intentionally expected to fail after signature verification.'
