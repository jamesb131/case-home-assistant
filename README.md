# CASE

Local-first household assistant for tasks, lists, recurring chores, energy insights, calendar/kids planning, and future smart home automation.

## Current stack

- React frontend
- FastAPI backend
- PostgreSQL
- Ollama/local LLM
- Docker Compose

## Local URLs

Run the production-style local stack with:

```bash
docker compose up --build -d
```

- Web UI: http://localhost:8080
- API: http://localhost:8000
- Vite dev UI, when running `npm run dev` in `web/`: http://localhost:5173

## Notes

Secrets are not committed. Copy `.env.example` to `.env` and add local values.

Google auth files such as `token.json` and `credentials.json` are local only and ignored by git.
