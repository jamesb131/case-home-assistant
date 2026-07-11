from app.repositories.system_snapshots_repository import get_snapshot
from app.services.gaggimate_client import GaggimateUnavailable, change_mode
from app.services.home_assistant_client import HomeAssistantUnavailable
from app.services.roborock_client import run_roborock_command
from app.worker import poll_gaggimate_snapshot
from app.worker import poll_roborock_snapshot


COFFEE_ALIASES = ["coffee", "gaggia", "gaggimate", "espresso"]
ROBOROCK_ALIASES = ["vacuum", "roborock", "qrevo", "robot cleaner"]


def handle_iot_intent(intent):
    device = (intent.get("category") or "").lower()
    raw_message = (intent.get("raw_message") or intent.get("question") or "").lower()

    if device == "coffee" or any(alias in raw_message for alias in COFFEE_ALIASES):
        return handle_coffee_intent(intent)

    if device in ["roborock", "roborock_route", "vacuum"] or any(alias in raw_message for alias in ROBOROCK_ALIASES):
        return handle_roborock_intent(intent)

    return {
        "reply": "I can help with the coffee machine and Roborock vacuum at the moment.",
        "intent": "iot_not_supported",
        "confidence": intent.get("confidence", "medium"),
        "source": "iot_handler",
    }


def handle_coffee_intent(intent):
    operation = intent.get("operation")
    target_mode = normalise_coffee_mode(intent.get("target_page") or intent.get("title"))

    if operation == "update" and target_mode:
        return change_coffee_mode(target_mode, intent)

    if operation == "update" and (intent.get("category") == "coffee_refresh"):
        return refresh_coffee_status(intent)

    if target_mode:
        return change_coffee_mode(target_mode, intent)

    return read_coffee_status(intent)


def read_coffee_status(intent):
    snapshot = get_snapshot("iot.gaggimate")

    if not snapshot:
        snapshot = poll_gaggimate_snapshot()

    status = snapshot["payload"]["snapshot"]

    if not status.get("online"):
        error = status.get("error") or snapshot.get("error")
        reply = "The coffee machine looks offline."
        if error:
            reply += f" {error}"

        return {
            "reply": reply,
            "intent": "coffee_status",
            "confidence": intent.get("confidence", "medium"),
            "source": "iot_handler",
            "coffee": status,
        }

    mode = status.get("mode_label") or "unknown mode"
    profile = status.get("profile_label") or "no selected profile"
    temp = format_number(status.get("current_temp_c"))
    target = format_number(status.get("target_temp_c"))
    pressure = format_number(status.get("pressure_bar"), decimals=1)

    pieces = [f"The coffee machine is in {mode} mode"]

    if temp is not None:
        temp_text = f"at {temp} degrees"
        if target is not None:
            temp_text += f", targeting {target}"
        pieces.append(temp_text)

    pieces.append(f"with {profile}")

    if pressure is not None:
        pieces.append(f"and pressure around {pressure} bar")

    return {
        "reply": ", ".join(pieces) + ".",
        "intent": "coffee_status",
        "confidence": intent.get("confidence", "medium"),
        "source": "iot_handler",
        "coffee": status,
    }


def refresh_coffee_status(intent):
    snapshot = poll_gaggimate_snapshot()
    status = snapshot["payload"]["snapshot"]

    if status.get("online"):
        reply = f"Coffee machine refreshed. It is in {status.get('mode_label') or 'unknown'} mode."
    else:
        reply = "Coffee machine refreshed, but it looks offline."

    return {
        "reply": reply,
        "intent": "coffee_refresh",
        "confidence": intent.get("confidence", "medium"),
        "source": "iot_handler",
        "coffee": status,
        "ui_action": {
            "type": "refresh_data",
            "scope": "coffee",
        },
    }


def change_coffee_mode(mode, intent):
    try:
        result = change_mode(mode)
        return {
            "reply": f"Coffee machine set to {result['status']['mode_label']} mode.",
            "intent": "coffee_mode_update",
            "confidence": intent.get("confidence", "medium"),
            "source": "iot_handler",
            "coffee": result["status"],
            "ui_action": {
                "type": "refresh_data",
                "scope": "coffee",
            },
        }
    except GaggimateUnavailable as exc:
        return {
            "reply": f"I couldn't change the coffee machine mode. {exc}",
            "intent": "coffee_mode_update_failed",
            "confidence": intent.get("confidence", "medium"),
            "source": "iot_handler",
        }


def normalise_coffee_mode(value):
    if not value:
        return None

    lower = value.lower()

    if "standby" in lower or "idle" in lower or "off" in lower:
        return "standby"

    if "brew" in lower or "espresso" in lower or "coffee" in lower:
        return "brew"

    if "steam" in lower:
        return "steam"

    if "water" in lower or "hot water" in lower:
        return "water"

    return None


def handle_roborock_intent(intent):
    operation = intent.get("operation")
    command = normalise_roborock_command(intent)

    if operation == "update" and command:
        return update_roborock(command, intent)

    return read_roborock_status(intent)


def read_roborock_status(intent):
    snapshot = get_snapshot("iot.roborock")

    if not snapshot:
        snapshot = poll_roborock_snapshot()

    status = snapshot["payload"]["snapshot"]

    if not status.get("configured"):
        return {
            "reply": "Roborock is not configured yet. Add the Home Assistant URL, token and vacuum entity ID first.",
            "intent": "roborock_status_not_configured",
            "confidence": intent.get("confidence", "medium"),
            "source": "iot_handler",
            "roborock": status,
        }

    if not status.get("available"):
        return {
            "reply": f"Roborock looks unavailable. {status.get('message') or ''}".strip(),
            "intent": "roborock_status_unavailable",
            "confidence": intent.get("confidence", "medium"),
            "source": "iot_handler",
            "roborock": status,
        }

    battery = status.get("battery_level")
    pieces = [
        f"Roborock is {status.get('activity') or status.get('state') or 'online'}"
    ]

    if battery is not None:
        pieces.append(f"battery {battery} percent")

    if status.get("cleaning_progress") is not None:
        pieces.append(f"cleaning progress {status['cleaning_progress']} percent")

    if status.get("error"):
        pieces.append(f"error {status['error']}")

    return {
        "reply": ", ".join(pieces) + ".",
        "intent": "roborock_status",
        "confidence": intent.get("confidence", "medium"),
        "source": "iot_handler",
        "roborock": status,
    }


def update_roborock(command, intent):
    route = intent.get("title")

    try:
        result = run_roborock_command(command, route=route)
    except HomeAssistantUnavailable as exc:
        return {
            "reply": f"I couldn't control Roborock. {exc}",
            "intent": "roborock_update_failed",
            "confidence": intent.get("confidence", "medium"),
            "source": "iot_handler",
        }

    status = result.get("status") or {}

    if command == "run_route":
        reply = f"Roborock route {route} started."
    elif command == "dock":
        reply = "Roborock is returning to the dock."
    elif command == "pause":
        reply = "Roborock cleaning paused."
    else:
        reply = "Roborock cleaning started."

    return {
        "reply": reply,
        "intent": "roborock_update",
        "confidence": intent.get("confidence", "medium"),
        "source": "iot_handler",
        "roborock": status,
        "ui_action": {
            "type": "refresh_data",
            "scope": "roborock",
        },
    }


def normalise_roborock_command(intent):
    target = (intent.get("target_page") or "").lower()
    category = (intent.get("category") or "").lower()

    if category == "roborock_route" or intent.get("title"):
        return "run_route"

    if target in ["start", "pause", "dock"]:
        return target

    return None


def format_number(value, decimals=0):
    if value is None:
        return None

    return f"{float(value):.{decimals}f}"
