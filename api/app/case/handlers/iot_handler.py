from app.repositories.system_snapshots_repository import get_snapshot
from app.services.gaggimate_client import GaggimateUnavailable, change_mode
from app.worker import poll_gaggimate_snapshot


COFFEE_ALIASES = ["coffee", "gaggia", "gaggimate", "espresso"]


def handle_iot_intent(intent):
    device = (intent.get("category") or "").lower()
    raw_message = (intent.get("raw_message") or intent.get("question") or "").lower()

    if device == "coffee" or any(alias in raw_message for alias in COFFEE_ALIASES):
        return handle_coffee_intent(intent)

    return {
        "reply": "I can help with the coffee machine at the moment.",
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


def format_number(value, decimals=0):
    if value is None:
        return None

    return f"{float(value):.{decimals}f}"
