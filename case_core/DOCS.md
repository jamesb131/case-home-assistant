# CASE Core

## First-trial shape

CASE Core is the HA-managed wrapper for:

- FastAPI API on port 8000
- React/Nginx web UI on port 80, exposed as host port 8080
- worker polling process
- migrations before API/worker startup

The app image is expected to be built and published separately as:

```text
ghcr.io/jamesb131/case-home-assistant/case-core:0.1.0
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

Copy `credentials.json` and `token.json` there through the add-on data/share
path before relying on calendar reads.

## Desktop LLM

Set `ollama_url` to the desktop PC endpoint:

```text
http://desktop-pc.local:11434/api/chat
```

CASE should continue to run when the desktop is off; the UI should show
assistant/voice unavailable.
