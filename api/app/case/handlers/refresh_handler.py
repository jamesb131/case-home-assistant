from app.services.refresh_service import refresh_data


def handle_refresh_intent(intent):
    scope = intent.get("category") or "all"
    result = refresh_data(scope)

    if result["ok"]:
        reply = refresh_success_reply(result["targets"])
    elif result["ok_count"] > 0:
        reply = (
            f"Refreshed {result['ok_count']} of {len(result['targets'])} data sources. "
            "Some sources reported errors."
        )
    else:
        reply = "I tried to refresh the data, but every source reported an error."

    return {
        "reply": reply,
        "intent": "refresh_data",
        "confidence": intent.get("confidence", "medium"),
        "source": "refresh_handler",
        "refresh": result,
        "ui_action": {
            "type": "refresh_data",
            "scope": scope,
        },
    }


def refresh_success_reply(targets):
    if targets == ["calendar"]:
        return "Calendar events refreshed."

    if targets == ["energy"]:
        return "Energy data refreshed."

    if targets == ["weather"]:
        return "Weather data refreshed."

    if targets == ["bins"]:
        return "Bin schedule refreshed."

    return "All CASE data sources refreshed."
