# CASE Core

## First-trial shape

CASE Core is the HA-managed wrapper for:

- FastAPI API on port 8000
- React/Nginx web UI on port 80, exposed as host port 8080
- worker polling process
- migrations before API/worker startup

The app image is expected to be built and published separately as:

```text
ghcr.io/jamesb131/case-home-assistant/case-core:<config version>
```

## Database

Install and start CASE Postgres first. For this GitHub repository install, the
internal database hostname is:

```text
2e435b46-case-postgres
```

Home Assistant generates internal hostnames as `{repo}-{slug}`. The repository
prefix for `https://github.com/jamesb131/case-home-assistant` is currently
`2e435b46`.

## Google calendar auth

The CASE image should map persistent Google auth data to:

```text
/data/google
```

At runtime the image should expose that directory to the application as:

```text
/app/app/google
```

Upload Google auth files to the Home Assistant share path:

```text
/share/case/google/credentials.json
/share/case/google/token.json
```

If the Home Assistant `share` folder is mounted on your Mac, the auth helper can
create and export the files in one run:

```bash
cd api
python3 auth_google_calendar.py --export-dir /Volumes/share/case/google
```

You can use any mounted path that maps to `/share/case/google` on Home
Assistant.

On startup, CASE Core imports those files into:

```text
/data/google
```

The default import directory is configurable with `google_import_dir`.

## Desktop LLM

Set `ollama_url` to the desktop PC LLM bridge endpoint:

```text
http://desktop-pc.local:11435/api/chat
```

CASE should continue to run when the desktop is off; the UI should show
assistant/voice unavailable.
