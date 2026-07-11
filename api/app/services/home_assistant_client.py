import json
import os

import requests


class HomeAssistantUnavailable(Exception):
    pass


def get_home_assistant_config():
    url = os.getenv("HOME_ASSISTANT_URL", "").strip().rstrip("/")
    token = os.getenv("HOME_ASSISTANT_TOKEN", "").strip()

    return {
        "url": url,
        "token": token,
        "configured": bool(url and token),
    }


def get_home_assistant_headers():
    config = get_home_assistant_config()

    if not config["configured"]:
        raise HomeAssistantUnavailable(
            "Home Assistant URL or token is not configured."
        )

    return {
        "Authorization": f"Bearer {config['token']}",
        "Content-Type": "application/json",
    }


def get_entity_state(entity_id):
    config = get_home_assistant_config()
    headers = get_home_assistant_headers()

    try:
        response = requests.get(
            f"{config['url']}/api/states/{entity_id}",
            headers=headers,
            timeout=8,
        )
        response.raise_for_status()
        return response.json()
    except requests.RequestException as exc:
        raise HomeAssistantUnavailable(str(exc)) from exc
    except ValueError as exc:
        raise HomeAssistantUnavailable(
            f"Home Assistant returned invalid JSON: {exc}"
        ) from exc


def call_home_assistant_service(domain, service, payload):
    config = get_home_assistant_config()
    headers = get_home_assistant_headers()

    try:
        response = requests.post(
            f"{config['url']}/api/services/{domain}/{service}",
            headers=headers,
            json=payload,
            timeout=12,
        )
        response.raise_for_status()
        return response.json()
    except requests.RequestException as exc:
        raise HomeAssistantUnavailable(str(exc)) from exc
    except ValueError:
        return []


def parse_entity_map(value):
    if not value:
        return {}

    try:
        parsed = json.loads(value)
    except ValueError:
        return {}

    if not isinstance(parsed, dict):
        return {}

    return {
        str(name).strip(): str(entity_id).strip()
        for name, entity_id in parsed.items()
        if str(name).strip() and str(entity_id).strip()
    }
