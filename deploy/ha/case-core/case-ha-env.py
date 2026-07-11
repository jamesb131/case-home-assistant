import json
import os
import shlex
from pathlib import Path


OPTIONS_PATH = Path("/data/options.json")

OPTION_ENV_MAP = {
    "postgres_host": "POSTGRES_HOST",
    "postgres_port": "POSTGRES_PORT",
    "postgres_user": "POSTGRES_USER",
    "postgres_password": "POSTGRES_PASSWORD",
    "postgres_db": "POSTGRES_DB",
    "google_calendar_id": "GOOGLE_CALENDAR_ID",
    "google_import_dir": "GOOGLE_IMPORT_DIR",
    "ollama_url": "OLLAMA_URL",
    "ollama_model": "OLLAMA_MODEL",
    "ollama_status_timeout": "OLLAMA_STATUS_TIMEOUT",
    "ollama_chat_timeout": "OLLAMA_CHAT_TIMEOUT",
    "case_cors_origins": "CASE_CORS_ORIGINS",
    "case_api_token": "CASE_API_TOKEN",
    "case_web_api_base_url": "CASE_WEB_API_BASE_URL",
    "case_web_api_token": "CASE_WEB_API_TOKEN",
    "log_interval": "LOG_INTERVAL",
    "weather_poll_interval": "WEATHER_POLL_INTERVAL",
    "calendar_poll_interval": "CALENDAR_POLL_INTERVAL",
    "bins_poll_interval": "BINS_POLL_INTERVAL",
    "status_poll_interval": "STATUS_POLL_INTERVAL",
    "retention_interval": "RETENTION_INTERVAL",
    "recurring_task_interval": "RECURRING_TASK_INTERVAL",
    "recurring_task_days_ahead": "RECURRING_TASK_DAYS_AHEAD",
    "energy_retention_days": "ENERGY_RETENTION_DAYS",
    "sigenergy_host": "SIGENERGY_HOST",
    "sigenergy_port": "SIGENERGY_PORT",
    "gaggimate_host": "GAGGIMATE_HOST",
    "gaggimate_ws_protocol": "GAGGIMATE_WS_PROTOCOL",
    "gaggimate_timeout": "GAGGIMATE_TIMEOUT",
    "gaggimate_poll_interval": "GAGGIMATE_POLL_INTERVAL",
}


def load_options():
    if not OPTIONS_PATH.exists():
        return {}

    with OPTIONS_PATH.open() as handle:
        return json.load(handle)


def emit_export(name, value):
    print(f"export {name}={shlex.quote(str(value))}")


def main():
    options = load_options()

    for option_key, env_name in OPTION_ENV_MAP.items():
        value = options.get(option_key)
        if value is None:
            continue
        emit_export(env_name, value)

    emit_export("GOOGLE_DIR", os.getenv("GOOGLE_DIR", "/data/google"))


if __name__ == "__main__":
    main()
