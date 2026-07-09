#!/bin/sh
set -eu

OPTIONS_FILE="/data/options.json"

option() {
    key="$1"
    default="$2"

    if [ -f "$OPTIONS_FILE" ]; then
        value="$(jq -r --arg key "$key" --arg default "$default" '.[$key] // $default' "$OPTIONS_FILE")"
    else
        value="$default"
    fi

    printf '%s' "$value"
}

DOMAIN="$(option domain case.home.arpa)"
UPSTREAM_HOST="$(option upstream_host 192.168.0.154)"
UPSTREAM_PORT="$(option upstream_port 8080)"
CERTIFICATE_PATH="$(option certificate_path /ssl/case-home-arpa.crt)"
PRIVATE_KEY_PATH="$(option private_key_path /ssl/case-home-arpa.key)"

if [ ! -f "$CERTIFICATE_PATH" ]; then
    echo "Certificate file not found: $CERTIFICATE_PATH" >&2
    exit 1
fi

if [ ! -f "$PRIVATE_KEY_PATH" ]; then
    echo "Private key file not found: $PRIVATE_KEY_PATH" >&2
    exit 1
fi

cat > /etc/nginx/conf.d/default.conf <<EOF
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate ${CERTIFICATE_PATH};
    ssl_certificate_key ${PRIVATE_KEY_PATH};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    client_max_body_size 20m;

    location /health {
        access_log off;
        return 200 "ok\\n";
    }

    location / {
        proxy_pass http://${UPSTREAM_HOST}:${UPSTREAM_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

echo "Starting CASE HTTPS proxy for https://${DOMAIN} -> http://${UPSTREAM_HOST}:${UPSTREAM_PORT}"
exec nginx -g "daemon off;"
