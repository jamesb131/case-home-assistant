import json
import os
import uuid

from websocket import WebSocketTimeoutException, create_connection


GAGGIMATE_HOST = os.getenv("GAGGIMATE_HOST", "192.168.0.116")
GAGGIMATE_WS_PROTOCOL = os.getenv("GAGGIMATE_WS_PROTOCOL", "ws")
GAGGIMATE_TIMEOUT_SECONDS = float(os.getenv("GAGGIMATE_TIMEOUT", "3"))

MODE_LABELS = {
    0: "Standby",
    1: "Brew",
    2: "Steam",
    3: "Water",
    4: "Grind",
}

CONTROL_MODES = {
    "standby": 0,
    "brew": 1,
    "steam": 2,
    "water": 3,
}


class GaggimateUnavailable(RuntimeError):
    pass


def get_gaggimate_url():
    host = os.getenv("GAGGIMATE_HOST", GAGGIMATE_HOST).strip()
    protocol = os.getenv("GAGGIMATE_WS_PROTOCOL", GAGGIMATE_WS_PROTOCOL).strip() or "ws"
    return f"{protocol}://{host}/ws"


def get_gaggimate_host():
    return os.getenv("GAGGIMATE_HOST", GAGGIMATE_HOST).strip()


def get_gaggimate_status():
    message = wait_for_message(lambda payload: payload.get("tp") == "evt:status")
    return normalise_status(message)


def list_profiles():
    rid = str(uuid.uuid4())

    def send_request(ws):
        ws.send(json.dumps({"tp": "req:profiles:list", "rid": rid}))

    message = wait_for_message(
        lambda payload: (
            payload.get("tp") == "res:profiles:list"
            and payload.get("rid") == rid
        ),
        send_request=send_request,
    )

    if message.get("error"):
        raise GaggimateUnavailable(message["error"])

    return message.get("profiles") or []


def select_profile(profile_id):
    rid = str(uuid.uuid4())

    def send_request(ws):
        ws.send(
            json.dumps(
                {
                    "tp": "req:profiles:select",
                    "rid": rid,
                    "id": profile_id,
                }
            )
        )

    message = wait_for_message(
        lambda payload: (
            payload.get("tp") == "res:profiles:select"
            and payload.get("rid") == rid
        ),
        send_request=send_request,
    )

    if message.get("error"):
        raise GaggimateUnavailable(message["error"])

    return {"selected": True, "profile_id": profile_id}


def change_mode(mode):
    mode_key = str(mode or "").strip().lower()

    if mode_key not in CONTROL_MODES:
        raise GaggimateUnavailable(f"Unsupported GaggiMate mode: {mode}")

    mode_id = CONTROL_MODES[mode_key]

    def send_request(ws):
        ws.send(json.dumps({"tp": "req:change-mode", "mode": mode_id}))

    message = wait_for_message(
        lambda payload: payload.get("tp") == "evt:status" and payload.get("m") == mode_id,
        send_request=send_request,
    )

    return {
        "changed": True,
        "mode": mode_key,
        "mode_id": mode_id,
        "status": normalise_status(message),
    }


def wait_for_message(predicate, send_request=None):
    def read(ws):
        if send_request:
            send_request(ws)

        while True:
            raw = ws.recv()
            payload = json.loads(raw)

            if predicate(payload):
                return payload

    return with_gaggimate_socket(read)


def with_gaggimate_socket(callback):
    timeout = float(os.getenv("GAGGIMATE_TIMEOUT", str(GAGGIMATE_TIMEOUT_SECONDS)))
    url = get_gaggimate_url()

    try:
        ws = create_connection(url, timeout=timeout)
    except Exception as exc:
        raise GaggimateUnavailable(f"Could not connect to GaggiMate at {url}: {exc}") from exc

    try:
        return callback(ws)
    except WebSocketTimeoutException as exc:
        raise GaggimateUnavailable(f"GaggiMate did not respond within {timeout:g}s") from exc
    finally:
        ws.close()


def normalise_status(payload):
    mode = payload.get("m")

    return {
        "host": get_gaggimate_host(),
        "online": True,
        "current_temp_c": number_or_none(payload.get("ct")),
        "target_temp_c": number_or_none(payload.get("tt")),
        "pressure_bar": number_or_none(payload.get("pr")),
        "flow_ml_s": number_or_none(payload.get("fl")),
        "target_pressure_bar": number_or_none(payload.get("pt")),
        "mode": mode,
        "mode_label": MODE_LABELS.get(mode, f"Mode {mode}" if mode is not None else None),
        "profile_label": payload.get("p"),
        "pressure_capable": payload.get("cp"),
        "dimming_capable": payload.get("cd"),
        "error": None,
        "raw_payload": payload,
    }


def offline_status(error):
    return {
        "host": get_gaggimate_host(),
        "online": False,
        "current_temp_c": None,
        "target_temp_c": None,
        "pressure_bar": None,
        "flow_ml_s": None,
        "target_pressure_bar": None,
        "mode": None,
        "mode_label": "Offline",
        "profile_label": None,
        "pressure_capable": None,
        "dimming_capable": None,
        "error": str(error),
        "raw_payload": {"error": str(error)},
    }


def number_or_none(value):
    if value is None:
        return None

    try:
        return float(value)
    except (TypeError, ValueError):
        return None
