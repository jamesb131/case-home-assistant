#!/usr/bin/env bash
set -euo pipefail

eval "$(python /usr/local/bin/case-ha-env.py)"

mkdir -p "${GOOGLE_DIR:-/data/google}" /run/nginx /var/log/nginx

import_google_auth() {
    import_dir="${GOOGLE_IMPORT_DIR:-/share/case/google}"
    google_dir="${GOOGLE_DIR:-/data/google}"

    if [ ! -d "$import_dir" ]; then
        echo "Google auth import directory not found: $import_dir"
        return
    fi

    mkdir -p "$google_dir"

    for filename in credentials.json token.json; do
        source_file="$import_dir/$filename"
        target_file="$google_dir/$filename"

        if [ -f "$source_file" ]; then
            cp -u "$source_file" "$target_file"
            chmod 600 "$target_file"
            echo "Google auth file available: $target_file"
        fi
    done
}

import_google_auth

python - <<'PY'
import json
import os

config = {
    "API_BASE": os.getenv("CASE_WEB_API_BASE_URL", ""),
    "API_TOKEN": os.getenv("CASE_WEB_API_TOKEN", ""),
}

with open("/usr/share/nginx/html/case-config.js", "w") as handle:
    handle.write("window.CASE_CONFIG = ")
    json.dump(config, handle)
    handle.write(";\n")
PY

wait_for_db() {
    python - <<'PY'
import os
import time

import psycopg2

deadline = time.time() + 90

while True:
    try:
        conn = psycopg2.connect(
            host=os.getenv("POSTGRES_HOST", "local-case-postgres"),
            port=os.getenv("POSTGRES_PORT", "5432"),
            dbname=os.getenv("POSTGRES_DB", "case"),
            user=os.getenv("POSTGRES_USER", "case"),
            password=os.getenv("POSTGRES_PASSWORD", "case"),
        )
        conn.close()
        print("Database is ready.")
        break
    except Exception as exc:
        if time.time() > deadline:
            raise
        print(f"Waiting for database: {exc}")
        time.sleep(3)
PY
}

wait_for_db
python -m app.migrations

uvicorn app.main:app --host 0.0.0.0 --port 8000 &
api_pid="$!"

python -m app.worker &
worker_pid="$!"

nginx -g "daemon off;" &
nginx_pid="$!"

term_handler() {
    kill "$api_pid" "$worker_pid" "$nginx_pid" 2>/dev/null || true
    wait "$api_pid" "$worker_pid" "$nginx_pid" 2>/dev/null || true
}

trap term_handler INT TERM

wait -n "$api_pid" "$worker_pid" "$nginx_pid"
term_handler
