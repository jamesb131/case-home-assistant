#!/usr/bin/env bash
set -euo pipefail

SERVE=false
PORT="${CASE_CERT_SERVER_PORT:-8765}"

if [[ "${1:-}" == "--serve" ]]; then
  SERVE=true
  shift
fi

CERT_IN="${1:-/Users/jamesbaverstock/Downloads/case-local-ca.crt}"
OUT_DIR="${2:-/Users/jamesbaverstock/Downloads}"

if [[ ! -f "${CERT_IN}" ]]; then
  echo "Certificate not found: ${CERT_IN}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

CERT_NAME="$(basename "${CERT_IN}")"
CERT_STEM="${CERT_NAME%.*}"
CER_OUT="${OUT_DIR}/${CERT_STEM}.cer"
PROFILE_OUT="${OUT_DIR}/${CERT_STEM}.mobileconfig"

SUBJECT="$(openssl x509 -in "${CERT_IN}" -noout -subject | sed 's/^subject=//')"
FINGERPRINT="$(openssl x509 -in "${CERT_IN}" -noout -fingerprint -sha256 | sed 's/^sha256 Fingerprint=//')"

openssl x509 -in "${CERT_IN}" -outform der -out "${CER_OUT}"

CERT_PAYLOAD="$(base64 < "${CER_OUT}" | tr -d '\n')"
PROFILE_UUID="$(uuidgen)"
CERT_UUID="$(uuidgen)"

cat > "${PROFILE_OUT}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadCertificateFileName</key>
      <string>${CERT_STEM}.cer</string>
      <key>PayloadContent</key>
      <data>${CERT_PAYLOAD}</data>
      <key>PayloadDescription</key>
      <string>Installs the CASE local HTTPS root certificate.</string>
      <key>PayloadDisplayName</key>
      <string>CASE Local CA</string>
      <key>PayloadIdentifier</key>
      <string>au.case.local.ca</string>
      <key>PayloadType</key>
      <string>com.apple.security.root</string>
      <key>PayloadUUID</key>
      <string>${CERT_UUID}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDescription</key>
  <string>Trust profile for CASE local HTTPS on case.home.arpa.</string>
  <key>PayloadDisplayName</key>
  <string>CASE Local HTTPS Certificate</string>
  <key>PayloadIdentifier</key>
  <string>au.case.local.https</string>
  <key>PayloadOrganization</key>
  <string>CASE</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>${PROFILE_UUID}</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
EOF

echo "Created:"
echo "  ${CER_OUT}"
echo "  ${PROFILE_OUT}"
echo
echo "Certificate subject: ${SUBJECT}"
echo "SHA-256 fingerprint: ${FINGERPRINT}"
echo
if [[ "${SERVE}" != "true" ]]; then
  echo "AirDrop, email, or serve the .mobileconfig file to the iPad, then install it from Settings."
  echo "To serve it with the iOS profile MIME type, run:"
  echo "  $0 --serve"
  exit 0
fi

MAC_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
if [[ -z "${MAC_IP}" ]]; then
  MAC_IP="$(ipconfig getifaddr en1 2>/dev/null || true)"
fi

echo "Serving ${OUT_DIR} on port ${PORT}."
if [[ -n "${MAC_IP}" ]]; then
  echo "On the iPad, open:"
  echo "  http://${MAC_IP}:${PORT}/$(basename "${PROFILE_OUT}")"
fi
echo "Press Ctrl-C when the iPad has downloaded the profile."

cd "${OUT_DIR}"
python3 - "${PORT}" <<'PY'
import functools
import http.server
import socketserver
import sys

port = int(sys.argv[1])

class ProfileHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".mobileconfig": "application/x-apple-aspen-config",
        ".cer": "application/pkix-cert",
        ".crt": "application/x-x509-ca-cert",
    }

handler = functools.partial(ProfileHandler)
with socketserver.TCPServer(("", port), handler) as httpd:
    httpd.serve_forever()
PY
