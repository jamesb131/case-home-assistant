# Green trial runbook

This is the first local-network trial path for running CASE core on the always-on Green/core device while the desktop PC remains the optional Ollama host.

## Target shape

- Green/core device: `db`, `migrate`, `api`, `worker`, `web`
- Desktop PC: Ollama only
- Development Mac: edits, commits and pushes

## Ports and URLs

- CASE web UI: `http://case.local:8080`
- CASE API: `http://case.local:8000`
- API health: `http://case.local:8000/health`
- System status: `http://case.local:8000/system/status`
- Desktop Ollama: `http://desktop-pc.local:11434`

If hostnames are not ready yet, use the device IP addresses for the first trial.

## Pre-flight

1. Confirm the Green/core device can run Docker and Docker Compose or the supported equivalent.
2. Confirm persistent storage is available for the Postgres Docker volume.
3. Confirm the desktop PC can run Ollama and is reachable from the Green.
4. Confirm the shared Google calendar ID is correct.
5. Keep NVR/video storage outside CASE.

## Desktop PC

Install and start Ollama, then pull the configured model:

```bash
ollama pull llama3.1:8b
```

The desktop must listen on the LAN. The expected CASE URL is:

```text
http://desktop-pc.local:11434/api/chat
```

From another device on the LAN, verify:

```bash
curl http://desktop-pc.local:11434/api/tags
```

If the desktop is off, CASE should still run and the UI should show assistant/voice unavailable.

## Green/core setup

Clone the repo:

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
OLLAMA_URL=http://desktop-pc.local:11434/api/chat
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

## Start CASE

Run:

```bash
docker compose -f docker-compose.yml -f docker-compose.green.yml up --build -d
```

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

From the Green/core device:

```bash
git pull
docker compose -f docker-compose.yml -f docker-compose.green.yml up --build -d
```

## Rollback

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

## Stop

Stop services without deleting data:

```bash
docker compose -f docker-compose.yml -f docker-compose.green.yml stop
```

Do not remove Docker volumes unless you intentionally want to delete the database.
