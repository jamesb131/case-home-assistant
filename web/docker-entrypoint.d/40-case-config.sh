#!/bin/sh
set -eu

escape_js() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

api_base="$(escape_js "${CASE_WEB_API_BASE_URL:-}")"
api_token="$(escape_js "${CASE_WEB_API_TOKEN:-}")"

cat > /usr/share/nginx/html/case-config.js <<EOF
window.CASE_CONFIG = {
  API_BASE: "${api_base}",
  API_TOKEN: "${api_token}"
};
EOF
