# CASE desktop LLM bridge

This runs on the Windows PC. It is optional infrastructure for CASE: if the PC
is off, the Green should keep running and the UI should show the assistant/voice
as unavailable.

The bridge exposes an Ollama-compatible API to the LAN and proxies requests to a
local Ollama install on the Windows host.

## Windows setup

1. Install Ollama for Windows.
2. Pull the configured model:

```powershell
ollama pull llama3.1:8b
```

3. Install Docker Desktop and enable Linux containers.
4. From this repo, start the bridge:

```powershell
docker compose --env-file env/desktop.env.example -f deploy/desktop-llm/docker-compose.yml up -d --build
```

5. Allow inbound TCP port `11435` through Windows Firewall if prompted.

From another device on the LAN, verify:

```bash
curl http://desktop-pc.local:11435/health
curl http://desktop-pc.local:11435/api/tags
curl -X POST http://desktop-pc.local:11435/llm/warmup
```

Point CASE Core on the Green at:

```text
OLLAMA_URL=http://desktop-pc.local:11435/api/chat
```

If hostnames are not resolving yet, use the desktop PC IP address.

## Configuration

Copy `env/desktop.env.example` to `.env` in the repo root, pass it with
`--env-file`, or set these environment variables directly:

```text
OLLAMA_BASE_URL=http://host.docker.internal:11434
OLLAMA_MODEL=llama3.1:8b
OLLAMA_STATUS_TIMEOUT=2
OLLAMA_CHAT_TIMEOUT=60
OLLAMA_KEEP_ALIVE=10m
OLLAMA_WARMUP_INTERVAL=300
CASE_LLM_ALLOWED_CLIENTS=
```

`host.docker.internal` lets the Linux container reach Ollama running directly on
Windows.

`OLLAMA_WARMUP_INTERVAL` keeps the model loaded by making a tiny local
generation request every few minutes. Set it to `0` to disable this.

`CASE_LLM_ALLOWED_CLIENTS` is an optional comma-separated IP allow-list. Leave it
empty while testing. Once the Green is stable, set it to the Green IP plus any
trusted admin device that needs direct diagnostics.
