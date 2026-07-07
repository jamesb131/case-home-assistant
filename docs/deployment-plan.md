# CASE deployment plan

CASE is moving toward a split local-first deployment.

## Target devices

### Always-on Home Assistant Green

Runs in the network rack, wired to Ethernet, available 24/7.

Responsibilities:

- PostgreSQL database
- CASE API
- CASE worker
- energy polling and logging
- weather polling/cache
- calendar health checks/sync
- recurring task generation
- future birthday reminder generation
- Home Assistant integration point
- Zigbee/Thread, garage door, HWS, local weather station and other household devices

The Green should be the source of truth for household state. It should not depend on the desktop PC for ordinary dashboards, lists, tasks, energy history, or automations.

Current constraint: the Green is a Home Assistant OS appliance, not a generic
Linux server. It has Docker under Supervisor control, but the supported path is
Home Assistant apps/add-ons rather than running this repo's raw Docker Compose
stack directly on the host. Keep the device recoverable and package CASE into
HA-managed containers for the first Green deployment.

### Desktop PC

Runs only when available.

Responsibilities:

- Ollama/local LLM inference
- future heavier speech-to-text and text-to-speech
- future larger local models

The desktop is an accelerator, not the source of truth. When it is offline, CASE should show that voice/LLM features are unavailable while the rest of the app continues to work.

### Development machine

Used for local development, testing and Git pushes.

Responsibilities:

- edit code
- run local Docker Compose
- run frontend dev server
- push to GitHub
- build/deploy later via tagged images or controlled update scripts

## Service shape

Current first split:

- `api`: FastAPI request/response service
- `worker`: always-on polling/logging/snapshot process using `python -m app.worker`
- `db`: PostgreSQL
- `web`: production React static bundle served by Nginx
- `ollama`: external service, likely on the desktop PC

Future split:

- `case-core-api`
- `case-worker`
- `case-web`
- `case-llm-gateway`

## Local-network behavior

The frontend reads runtime `CASE_WEB_API_BASE_URL` in the static web container, or `VITE_API_BASE_URL` during Vite development. Without either, it uses the current browser hostname with port `8000`.

Examples:

```text
http://localhost:8080       # production web container
http://localhost:5173       # Vite development server
http://localhost:8000
http://case.local:8000
http://homeassistant.local:8000
```

The production web UI runs on port `8080` and talks to the API on port `8000`.

For a generic Linux core host, use the Green-like Compose override file:

```bash
docker compose -f docker-compose.yml -f docker-compose.green.yml up -d
```

This is appropriate for a future mini PC, NUC-style machine, Raspberry Pi, or
other normal Linux Docker host. It is not the first path for the Home Assistant
Green while it remains on Home Assistant OS.

For the first Green/core trial, follow:

```text
docs/green-trial-runbook.md
```

For Home Assistant Green, package CASE as HA apps/add-ons. The target shape is:

- CASE Postgres app/add-on with persistent database data
- CASE API/worker/web app/add-on containers built for `aarch64`
- desktop Ollama URL configured as an optional external dependency
- UI exposed through HA app `webui`/ingress or direct LAN ports during the first
  trial

Keep device-specific values in app options or `.env`-style config, especially:

```text
CASE_CORS_ORIGINS=http://case.local:8080,http://homeassistant.local:8080
CASE_WEB_API_BASE_URL=http://case.local:8000
OLLAMA_URL=http://desktop-pc.local:11434/api/chat
```

## LLM availability

CASE should expose LLM status separately from API status.

When Ollama is unavailable:

- voice/assistant controls should show unavailable
- deterministic tasks/lists/energy/calendar UI should still work
- the API should not return 500 for normal household operations

The API exposes:

```text
GET /assistant/status
GET /llm/status
GET /system/status
```

For a split LAN deployment, set the Green's `OLLAMA_URL` to the desktop PC's Ollama endpoint:

```text
OLLAMA_URL=http://desktop-pc.local:11434/api/chat
```

If the desktop is asleep or off, the dashboard should keep working and the Ask CASE/voice controls should show unavailable.

## Worker snapshots

The worker now polls and stores local Postgres snapshots in `system_snapshots`.

Current snapshot keys:

```text
energy.latest
weather.summary
calendar.upcoming
household.bins
tasks.recurring
retention.energy
```

The API reads cached weather, calendar and current-energy state first, then falls back to live calls if the worker has not warmed up yet. This is the pattern to follow for future Zigbee sensors, garage doors, HWS controllers and local weather stations.

Polling intervals are controlled by:

```text
LOG_INTERVAL=30
WEATHER_POLL_INTERVAL=900
CALENDAR_POLL_INTERVAL=900
BINS_POLL_INTERVAL=3600
STATUS_POLL_INTERVAL=60
RETENTION_INTERVAL=86400
RECURRING_TASK_INTERVAL=3600
RECURRING_TASK_DAYS_AHEAD=21
ENERGY_RETENTION_DAYS=0
```

## Deployment approach

Short term:

- develop on the local machine
- push to GitHub
- build/test a Home Assistant app/add-on wrapper for the Green
- use raw Compose only on local development and future generic Linux hosts
- use `env/local.env.example`, `env/green.env.example` and `env/desktop.env.example` as starting points

Long term:

- build container images from GitHub
- deploy tagged `aarch64` images to the Green through HA apps/add-ons
- keep local secrets and device-specific config outside Git
- keep database files on persistent storage managed by the target device

Avoid treating live Git working trees on appliances as the long-term deployment mechanism. Container images are safer and easier to roll back.

## Database migrations

CASE uses lightweight versioned SQL migrations in:

```text
api/app/db/migrations/
```

Run migrations with:

```bash
docker compose run --rm migrate
```

The migration service runs `python -m app.migrations`. In Compose, `api` and `worker` depend on the migration service completing successfully. This keeps a fresh Green database reproducible and lets existing databases receive additive schema changes safely.

## Data retention

The Green has limited local storage. Do not store video there. NVR storage remains separate.

For sensor and energy data:

- keep high-frequency raw data for a bounded period
- roll up daily/monthly summaries for long-term history
- add retention jobs to `case-worker`

Energy rollups are stored in `energy_daily_rollups`. The worker refreshes recent rollups automatically. Raw reading pruning is disabled when `ENERGY_RETENTION_DAYS=0`; set it above zero only after backup/retention expectations are settled.

Run a manual Postgres backup with:

```bash
scripts/db-backup.sh
```

The script writes timestamped dumps under `backups/`, which is ignored by Git.

## Remote smartphone access

Do not expose FastAPI directly to the public internet.

Preferred options:

- Tailscale or WireGuard VPN for phone access to the private LAN.
- Home Assistant/Nabu Casa proxy path if CASE becomes an HA add-on or supervised adjacent service.
- Cloudflare Tunnel only with authentication in front of CASE.

Preparation already in place:

- frontend API base URL is configurable with `VITE_API_BASE_URL`
- static web API base URL is configurable with `CASE_WEB_API_BASE_URL`
- API CORS origins are configurable with `CASE_CORS_ORIGINS`
- optional token auth can be enabled with `CASE_API_TOKEN`
- frontend can send that token with `VITE_CASE_API_TOKEN`
- static web can send that token with `CASE_WEB_API_TOKEN`

Leave `CASE_API_TOKEN` unset for local development. Set it before using a VPN hostname, reverse proxy or tunnel.

## Near-term technical steps

1. Scaffold the CASE HA app/add-on structure and document DB lifecycle.
2. Add buildable `aarch64` images for CASE Core and CASE Postgres.
3. Build/test `aarch64` images locally or via CI.
4. Install the CASE app/add-on on the Green and verify API, worker, web, DB persistence and desktop Ollama availability.
5. Add sensor/device-specific snapshot tables only where generic snapshots stop being enough.
6. Add a proper authenticated remote-access path after choosing VPN/proxy approach.
