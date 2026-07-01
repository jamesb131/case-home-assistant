import os
from urllib.parse import urlparse, urlunparse

import requests


OLLAMA_URL = os.getenv(
    "OLLAMA_URL",
    "http://host.docker.internal:11434/api/chat"
)

OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:8b")


class OllamaUnavailable(Exception):
    pass


def get_ollama_tags_url():
    parsed = urlparse(OLLAMA_URL)
    path = parsed.path

    if path.endswith("/api/chat"):
        path = path[:-len("/api/chat")] + "/api/tags"
    else:
        path = "/api/tags"

    return urlunparse(parsed._replace(path=path, params="", query="", fragment=""))


def get_ollama_status(timeout=2):
    try:
        response = requests.get(get_ollama_tags_url(), timeout=timeout)
        response.raise_for_status()
        data = response.json()
    except requests.RequestException as exc:
        return {
            "available": False,
            "model": OLLAMA_MODEL,
            "url": OLLAMA_URL,
            "message": f"Ollama is unavailable: {exc}",
        }
    except ValueError as exc:
        return {
            "available": False,
            "model": OLLAMA_MODEL,
            "url": OLLAMA_URL,
            "message": f"Ollama returned invalid status JSON: {exc}",
        }

    models = [
        model.get("name")
        for model in data.get("models", [])
        if model.get("name")
    ]
    model_present = OLLAMA_MODEL in models

    return {
        "available": model_present,
        "service_available": True,
        "model": OLLAMA_MODEL,
        "url": OLLAMA_URL,
        "models": models,
        "model_present": model_present,
        "message": (
            "Ollama is available."
            if model_present
            else f"Ollama is running but {OLLAMA_MODEL} is not installed."
        ),
    }


def ask_ollama(system_prompt: str, user_prompt: str):
    try:
        response = requests.post(
            OLLAMA_URL,
            json={
                "model": OLLAMA_MODEL,
                "stream": False,
                "messages": [
                    {
                        "role": "system",
                        "content": system_prompt,
                    },
                    {
                        "role": "user",
                        "content": user_prompt,
                    },
                ],
            },
            timeout=60,
        )

        response.raise_for_status()
    except requests.RequestException as exc:
        raise OllamaUnavailable(str(exc)) from exc

    data = response.json()
    return data["message"]["content"]
