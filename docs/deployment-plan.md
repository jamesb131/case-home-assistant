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
- `worker`: always-on polling/logging process using `python -m app.worker`
- `db`: PostgreSQL
- `web`: Vite/React during development, static build later
- `ollama`: external service, likely on the desktop PC

Future split:

- `case-core-api`
- `case-worker`
- `case-web`
- `case-llm-gateway`

## Local-network behavior

The frontend reads `VITE_API_BASE_URL` when provided. Without it, it uses the current browser hostname with port `8000`.

Examples:

```text
http://localhost:8000
http://case.local:8000
http://homeassistant.local:8000
```

The API CORS policy is still development-open and should be tightened before wider LAN use.

## LLM availability

CASE should expose LLM status separately from API status.

When Ollama is unavailable:

- voice/assistant controls should show unavailable
- deterministic tasks/lists/energy/calendar UI should still work
- the API should not return 500 for normal household operations

## Deployment approach

Short term:

- develop on the local machine
- push to GitHub
- pull/rebuild on the target device manually or with a small script

Long term:

- build container images from GitHub
- deploy tagged images to the Green
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

## Near-term technical steps

1. Add proper database migrations/schema setup.
2. Add `/health` checks for API, DB, calendar, Sigenergy and Ollama.
3. Tighten CORS for LAN origins.
4. Move weather/calendar sync and recurring task generation into `case-worker`.
5. Add frontend display for LLM unavailable.
6. Package for the Green using a controlled compose/add-on approach.
