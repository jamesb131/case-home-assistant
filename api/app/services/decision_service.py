from app.services.sigenergy_client import get_energy_snapshot
from app.services.decision_context import get_decision_context

def message(text, level="info"):
    return {
        "text": text,
        "level": level
    }


def get_decision_summary():
    state = get_energy_snapshot()
    context = get_decision_context()

    messages = []

    # Battery SoC logic
    if state.get("battery_usable_kwh", 0) <= 0.2:
        messages.append(message("Battery empty", "warning"))
    elif state.get("battery_usable_kwh", 0) <= 1.0:
        messages.append(message("Battery low", "warning"))

    # Dishwasher logic
    if state["grid_kw"] < -2.0:
        messages.append(message("Run dishwasher now (excess solar available)", "info"))
    elif state["battery_soc"] > 95 and state["solar_kw"] > 1:
        messages.append(message("Run dishwasher now (battery full)", "info"))

    # HWS logic
    if (
        context["is_early_morning"]
        and state["battery_soc"] < 30
        and state["solar_kw"] < 1
    ):
        messages.append(message("Delay hot water (battery low, solar not up yet)", "warning"))
    elif state["grid_kw"] < -2.0:
        messages.append(message("Hot water can run now (excess solar)", "info"))
    elif (
        context["is_late_solar_window"]
        and state["solar_kw"] < 2
        and state["battery_soc"] < 50
    ):
        messages.append(message("Avoid hot water now (solar fading, battery dropping)", "warning"))

    # EV logic
    if state["ev_charging"]:
        if state["grid_kw"] > 0.5:
            messages.append(message("EV is pulling from grid", "warning"))
        elif state["grid_kw"] < -1.0:
            messages.append(message("EV is charging on solar", "info"))
        else:
            messages.append(message("EV mostly on solar", "info"))

    # Default message
    if not messages:
        messages.append(message("All good. No actions needed.", "info"))

    return {
        "messages": messages,
        "state": state,
        "context": context
    }