#!/bin/sh
set -eu

OPTIONS_FILE="/data/options.json"

option_value() {
    key="$1"
    fallback="$2"

    if [ -f "$OPTIONS_FILE" ]; then
        jq -r --arg key "$key" --arg fallback "$fallback" '.[$key] // $fallback' "$OPTIONS_FILE"
    else
        printf '%s\n' "$fallback"
    fi
}

export POSTGRES_USER="$(option_value postgres_user "${POSTGRES_USER:-case}")"
export POSTGRES_PASSWORD="$(option_value postgres_password "${POSTGRES_PASSWORD:-case}")"
export POSTGRES_DB="$(option_value postgres_db "${POSTGRES_DB:-case}")"
export PGDATA="${PGDATA:-/data/postgres}"

mkdir -p "$PGDATA"

exec docker-entrypoint.sh "$@"
