import os
import requests


OLLAMA_URL = os.getenv(
    "OLLAMA_URL",
    "http://host.docker.internal:11434/api/chat"
)

OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:8b")


def ask_ollama(system_prompt: str, user_prompt: str):
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

    data = response.json()
    return data["message"]["content"]