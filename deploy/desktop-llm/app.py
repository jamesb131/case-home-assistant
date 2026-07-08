import os
import threading
import time
from urllib.parse import urljoin

import requests
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse


OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://host.docker.internal:11434").rstrip("/")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:8b")
OLLAMA_STATUS_TIMEOUT = float(os.getenv("OLLAMA_STATUS_TIMEOUT", "2"))
OLLAMA_CHAT_TIMEOUT = float(os.getenv("OLLAMA_CHAT_TIMEOUT", "60"))
OLLAMA_KEEP_ALIVE = os.getenv("OLLAMA_KEEP_ALIVE", "10m")
OLLAMA_WARMUP_INTERVAL = int(os.getenv("OLLAMA_WARMUP_INTERVAL", "300"))
CASE_LLM_ALLOWED_CLIENTS = {
    client.strip()
    for client in os.getenv("CASE_LLM_ALLOWED_CLIENTS", "").split(",")
    if client.strip()
}

last_warmup = {
    "ok": None,
    "checked_at": None,
    "message": "Warmup has not run yet.",
}

app = FastAPI(title="CASE LLM bridge")


def ollama_url(path):
    return urljoin(f"{OLLAMA_BASE_URL}/", path.lstrip("/"))


def get_tags():
    response = requests.get(
        ollama_url("/api/tags"),
        timeout=OLLAMA_STATUS_TIMEOUT,
    )
    response.raise_for_status()
    return response.json()


def model_names(tags):
    return [
        model.get("name")
        for model in tags.get("models", [])
        if model.get("name")
    ]


def llm_status():
    try:
        tags = get_tags()
    except requests.RequestException as exc:
        return {
            "available": False,
            "service_available": False,
            "model": OLLAMA_MODEL,
            "ollama_base_url": OLLAMA_BASE_URL,
            "message": f"Ollama is unavailable: {exc}",
        }

    models = model_names(tags)
    model_present = OLLAMA_MODEL in models

    return {
        "available": model_present,
        "service_available": True,
        "model": OLLAMA_MODEL,
        "ollama_base_url": OLLAMA_BASE_URL,
        "models": models,
        "model_present": model_present,
        "message": (
            "Ollama is available."
            if model_present
            else f"Ollama is running but {OLLAMA_MODEL} is not installed."
        ),
        "keep_alive": OLLAMA_KEEP_ALIVE,
        "warmup": last_warmup,
        "allowed_clients": sorted(CASE_LLM_ALLOWED_CLIENTS),
    }


def warm_ollama():
    try:
        response = requests.post(
            ollama_url("/api/generate"),
            json={
                "model": OLLAMA_MODEL,
                "prompt": "Reply with ok.",
                "stream": False,
                "keep_alive": OLLAMA_KEEP_ALIVE,
                "options": {
                    "num_predict": 1,
                },
            },
            timeout=OLLAMA_CHAT_TIMEOUT,
        )
        response.raise_for_status()
    except requests.RequestException as exc:
        last_warmup.update({
            "ok": False,
            "checked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "message": str(exc),
        })
        return False

    last_warmup.update({
        "ok": True,
        "checked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "message": "Ollama model warmed successfully.",
    })
    return True


def warmup_loop():
    if OLLAMA_WARMUP_INTERVAL <= 0:
        return

    while True:
        warm_ollama()
        time.sleep(OLLAMA_WARMUP_INTERVAL)


@app.on_event("startup")
def start_warmup_loop():
    threading.Thread(target=warmup_loop, daemon=True).start()


@app.middleware("http")
async def restrict_clients(request: Request, call_next):
    if not CASE_LLM_ALLOWED_CLIENTS:
        return await call_next(request)

    client_host = request.client.host if request.client else None

    if client_host not in CASE_LLM_ALLOWED_CLIENTS:
        return JSONResponse(
            content={"error": "CASE LLM bridge client is not allowed."},
            status_code=403,
        )

    return await call_next(request)


@app.get("/health")
def health():
    status = llm_status()
    return {
        "status": "ok" if status["available"] else "unavailable",
        "llm": status,
    }


@app.get("/llm/status")
def status():
    return llm_status()


@app.post("/llm/warmup")
def warmup():
    ok = warm_ollama()

    return {
        "ok": ok,
        "warmup": last_warmup,
    }


@app.get("/api/tags")
def tags():
    status = llm_status()

    if not status["service_available"]:
        return Response(
            content='{"models":[]}',
            media_type="application/json",
            status_code=503,
        )

    return get_tags()


async def proxy_request(path, request: Request):
    body = await request.body()
    timeout = (
        OLLAMA_CHAT_TIMEOUT
        if path in {"api/chat", "api/generate"}
        else OLLAMA_STATUS_TIMEOUT
    )
    headers = {}
    content_type = request.headers.get("content-type")

    if content_type:
        headers["content-type"] = content_type

    try:
        upstream = requests.request(
            request.method,
            ollama_url(path),
            params=dict(request.query_params),
            data=body,
            headers=headers,
            timeout=timeout,
        )
    except requests.RequestException as exc:
        return JSONResponse(
            content={"error": f"Ollama is unavailable: {exc}"},
            status_code=503,
        )
    except Exception as exc:
        return JSONResponse(
            content={"error": f"CASE LLM bridge failed: {type(exc).__name__}: {exc}"},
            status_code=502,
        )

    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        media_type="application/json",
    )


@app.api_route("/api/chat", methods=["POST"])
async def chat(request: Request):
    return await proxy_request("api/chat", request)


@app.api_route("/api/generate", methods=["POST"])
async def generate(request: Request):
    return await proxy_request("api/generate", request)
