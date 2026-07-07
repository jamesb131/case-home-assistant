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
```

`host.docker.internal` lets the Linux container reach Ollama running directly on
Windows.
