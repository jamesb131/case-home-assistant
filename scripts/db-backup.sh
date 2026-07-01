#!/usr/bin/env bash
set -euo pipefail

backup_dir="${BACKUP_DIR:-backups}"
database="${POSTGRES_DB:-case}"
user="${POSTGRES_USER:-case}"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_file="${backup_dir}/case-${timestamp}.dump"

mkdir -p "${backup_dir}"

docker compose exec -T db pg_dump \
  -U "${user}" \
  -d "${database}" \
  -Fc \
  -f "/tmp/case-${timestamp}.dump"

docker compose cp "db:/tmp/case-${timestamp}.dump" "${backup_file}"

echo "Wrote ${backup_file}"
