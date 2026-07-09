# CASE security hardening

This is the staged hardening path for the Green, desktop LLM bridge and future
phone access.

## Immediate LAN settings

In CASE Core add-on options:

```yaml
case_api_token: "<long random value>"
case_web_api_token: "<same long random value>"
case_cors_origins: "http://192.168.0.154:8080,http://homeassistant.local:8080"
case_web_api_base_url: "/api"
```

Generate a token locally:

```bash
openssl rand -hex 32
```

Restart CASE Core after saving.

## Desktop LLM bridge

Start with the bridge open while testing. Once stable, restrict it to the Green
and trusted admin devices in `env/desktop.env.example` or the Windows `.env`:

```text
CASE_LLM_ALLOWED_CLIENTS=192.168.0.154,192.168.0.160
```

The bridge keeps Ollama warm with:

```text
OLLAMA_KEEP_ALIVE=10m
OLLAMA_WARMUP_INTERVAL=300
```

Set `OLLAMA_WARMUP_INTERVAL=0` to disable warmup.

## HTTPS and remote phone access

The preferred path is:

```text
phone -> Tailscale/WireGuard -> HTTPS proxy -> CASE web port 8080 -> /api -> CASE API
```

Keep CASE on a private network path. Do not port-forward CASE directly from the
router.

See:

```text
docs/mobile-remote-access.md
```

## Re-private GitHub repos

Home Assistant can install from a private add-on repo only if it has credentials
for the Git repository and container image registry. The cleaner options are:

1. Keep only the add-on packaging repo public, with no secrets committed.
2. Make the repo private and configure Home Assistant/GHCR authentication.
3. Publish release images publicly while keeping the application source private.

For now, option 1 is the least brittle. Before making anything private, confirm
the Green can pull both images without an interactive login.

See:

```text
docs/private-repos-and-packages.md
```

The target remote path should preserve the same API token requirement and avoid
opening the desktop LLM bridge to the public internet.
