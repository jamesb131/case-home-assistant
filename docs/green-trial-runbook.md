# Home Assistant Green trial runbook

This is the first local-network trial path for running CASE core on the always-on
Home Assistant Green while the desktop PC remains the optional Ollama host.

The Green is currently treated as a Home Assistant OS appliance. Do not plan on
running this repo's raw Docker Compose stack directly on the Green host while it
is on Home Assistant OS. The first supported trial path is to package CASE as
Home Assistant apps/add-ons and let Supervisor manage the containers.

## Target shape

- Green/core device: HA-managed CASE app/add-on containers for DB, API, worker and web
- Desktop PC: Ollama only
- Development Mac: edits, commits and pushes

First-trial packaging split:

- CASE Postgres app: persistent database, stored under HA-managed `/data`
- CASE Core app: API, worker, migrations and web UI

## Ports and URLs

- CASE web UI: `http://case.local:8080`
- CASE API: `http://case.local:8000`
- API health: `http://case.local:8000/health`
- System status: `http://case.local:8000/system/status`
- CASE Postgres internal hostname: `2e435b46-case-postgres`
- Desktop CASE LLM bridge: `http://desktop-pc.local:11435`
- Desktop Ollama on the Windows host: `http://host.docker.internal:11434`

Google calendar auth files should be uploaded to:

```text
/share/case/google/credentials.json
/share/case/google/token.json
```

If the Home Assistant share is mounted on your Mac, run the helper with an
export directory and it will copy both files for you:

```bash
cd /Users/jamesbaverstock/Documents/repos/Case/api
python3 auth_google_calendar.py --export-dir /Volumes/share/case/google
```

If hostnames are not ready yet, use the device IP addresses for the first trial.

On HA OS, the web UI may also be exposed through HA app `webui` or ingress once
the app wrapper exists. Direct LAN ports are acceptable for the first smoke test.

## Pre-flight

1. Confirm the Green is reachable at `http://192.168.0.154:8123` or `http://homeassistant.local:8123`.
2. Confirm the Green remains on Home Assistant OS and has Supervisor available.
3. Confirm persistent app data will live under HA-managed `/data` storage.
4. Confirm the desktop PC can run Ollama and is reachable from the Green.
5. Confirm the shared Google calendar ID is correct.
6. Keep NVR/video storage outside CASE.
7. Keep a Home Assistant backup before installing experimental CASE apps.

## Desktop PC

Install and start Ollama, then pull the configured model:

```bash
ollama pull llama3.1:8b
```

Run the CASE LLM bridge container from this repo:

```bash
docker compose --env-file env/desktop.env.example -f deploy/desktop-llm/docker-compose.yml up -d --build
```

The bridge must listen on the LAN. The expected CASE URL is:

```text
http://desktop-pc.local:11435/api/chat
```

From another device on the LAN, verify:

```bash
curl http://desktop-pc.local:11435/health
curl http://desktop-pc.local:11435/api/tags
```

If the desktop is off, CASE should still run and the UI should show assistant/voice unavailable.

## Green/core setup

The Home Assistant app/add-on scaffold lives in:

```text
repository.yaml
case_postgres/
case_core/
```

Packaging details and image requirements live in:

```text
docs/home-assistant-addon-packaging.md
```

Buildable image definitions live in:

```text
deploy/ha/
```

Build local smoke-test images with:

```bash
scripts/build-ha-images.sh local
```

Build and push multi-arch images for the Green with:

```bash
scripts/build-ha-images.sh push
```

The raw Compose flow below is retained for local development and future generic
Linux hosts only.

Clone the repo on a generic Linux host:

```bash
git clone https://github.com/jamesb131/case-home-assistant.git
cd case-home-assistant
```

Create the Green environment file:

```bash
cp env/green.env.example .env
```

Edit `.env` and confirm:

```text
POSTGRES_PASSWORD=...
GOOGLE_CALENDAR_ID=...
OLLAMA_URL=http://desktop-pc.local:11435/api/chat
CASE_CORS_ORIGINS=http://case.local:8080,http://homeassistant.local:8080
CASE_WEB_API_BASE_URL=http://case.local:8000
ENERGY_RETENTION_DAYS=0
```

Copy Google auth files into:

```text
api/app/google/
```

Expected local-only files:

```text
api/app/google/credentials.json
api/app/google/token.json
```

Do not commit those files.

## Start CASE on a generic Linux host

Run:

```bash
docker compose -f docker-compose.yml -f docker-compose.green.yml up --build -d
```

Do not run this directly on the Home Assistant Green while it remains on HA OS.
For the Green, install/start the CASE HA app/add-on once the wrapper exists.

Check services:

```bash
docker compose ps
```

Expected services:

```text
case-db
case-api
case-worker
case-web
```

## Verify

API health:

```bash
curl http://case.local:8000/health
```

System status:

```bash
curl http://case.local:8000/system/status
```

Open the web UI:

```text
http://case.local:8080
```

Check the UI System section:

- API: `ok`
- DB: `ok`
- Worker: `ok`
- Weather: `ok`
- Energy: `ok`
- Recurring: `ok`
- LLM: `ok` when the desktop is on, offline/unavailable when it is off

## Calendar check

The worker caches calendar events in `calendar.upcoming`.

Force a manual refresh if needed:

```bash
docker compose exec api python -c "from app.worker import poll_calendar_snapshot; print(poll_calendar_snapshot())"
```

Then verify:

```bash
curl http://case.local:8000/calendar/upcoming
```

## Backup

Run a manual Postgres backup:

```bash
scripts/db-backup.sh
```

Backups are written to:

```text
backups/
```

Copy backups off the Green before relying on it as the source of truth.

## Update

From a generic Linux core host:

```bash
git pull
docker compose -f docker-compose.yml -f docker-compose.green.yml up --build -d
```

For Home Assistant Green, update through the CASE HA app/add-on image/version
once packaging exists. Avoid live Git working trees on the appliance.

## Rollback on a generic Linux host

Find the previous known-good commit:

```bash
git log --oneline -5
```

Check it out:

```bash
git checkout <commit>
docker compose -f docker-compose.yml -f docker-compose.green.yml up --build -d
```

Return to `main` later with:

```bash
git checkout main
git pull
```

## Stop on a generic Linux host

Stop services without deleting data:

```bash
docker compose -f docker-compose.yml -f docker-compose.green.yml stop
```

Do not remove Docker volumes unless you intentionally want to delete the database.
