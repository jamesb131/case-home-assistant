#!/usr/bin/env bash
set -euo pipefail

eval "$(python /usr/local/bin/case-ha-env.py)"

mkdir -p "${GOOGLE_DIR:-/data/google}" /run/nginx /var/log/nginx

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
