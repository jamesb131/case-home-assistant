# Home Assistant app packaging

CASE will use Home Assistant apps/add-ons for the first Home Assistant Green
trial. The Green remains on Home Assistant OS; Supervisor manages the
containers.

## Repository layout

```text
repository.yaml
case_postgres/
  config.yaml
  README.md
  DOCS.md
  translations/en.yaml
case_core/
  config.yaml
  README.md
  DOCS.md
  translations/en.yaml
```

Home Assistant requires `repository.yaml` at the Git repository root.

The add-on definitions point at prebuilt images:

```text
ghcr.io/jamesb131/case-home-assistant/case-postgres:0.1.0
ghcr.io/jamesb131/case-home-assistant/case-core:0.1.0
```

The image Dockerfiles live in:

```text
deploy/ha/case-postgres/Dockerfile
deploy/ha/case-core/Dockerfile
```

Build them with:

```bash
scripts/build-ha-images.sh local
```

Build and push multi-arch images with:

```bash
scripts/build-ha-images.sh push
```

The image build pipeline is separate from HA installation. This avoids relying
on Home Assistant building images from the whole monorepo as a Docker context.

## First app split

- CASE Postgres: persistent database, data under `/data/postgres`, cold backups.
- CASE Core: API, worker, migrations and web UI in one app image.
- Desktop PC: Ollama only.

This keeps database persistence separate while avoiding too many moving parts in
the first Green trial.

## Internal networking

Home Assistant apps can talk over the internal app network by repository and
slug derived name. For this GitHub repository install, CASE Postgres is
reachable from CASE Core at:

```text
2e435b46-case-postgres:5432
```

Home Assistant generates internal DNS names as `{repo}-{slug}`. The repository
prefix for `https://github.com/jamesb131/case-home-assistant` is currently
`2e435b46`.

## Runtime behavior

CASE Core image:

1. Build the React web bundle and serve it with Nginx.
2. Run `python -m app.migrations` before starting API and worker.
3. Start `uvicorn app.main:app --host 0.0.0.0 --port 8000`.
4. Start `python -m app.worker`.
5. Translate HA app options from `/data/options.json` into CASE environment
   variables.
6. Keep Google auth files in `/data/google` and expose them to the app at
   `/app/app/google`.
7. Generate `/usr/share/nginx/html/case-config.js` from the web API options.

CASE Postgres image:

1. Run Postgres 15 for `aarch64` and `amd64`.
2. Store data under `/data/postgres`.
3. Translate HA app options into `POSTGRES_USER`, `POSTGRES_PASSWORD` and
   `POSTGRES_DB`.

## Security notes

- Do not commit Google `credentials.json` or `token.json`.
- Do not bake Google auth files into container images.
- Keep `CASE_API_TOKEN` empty for local smoke tests only.
- Set a real API token before any VPN, proxy or tunnel access.
