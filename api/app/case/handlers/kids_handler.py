def handle_kids_intent(intent):
    person = intent.get("person")
    timeframe = (
        intent.get("timeframe")
        or "today"
    )

    if person:
        return {
            "reply": (
                f"I understand you're asking "
                f"about {person}'s schedule for "
                f"{timeframe}, but the kids "
                f"schedule engine isn't wired yet."
            ),
            "intent": "kids_read",
        }

    return {
        "reply": (
            f"I understand you're asking "
            f"about the kids for {timeframe}, "
            f"but the schedule engine "
            f"isn't connected yet."
        ),
        "intent": "kids_read",
    }