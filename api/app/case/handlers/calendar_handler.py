def handle_calendar_intent(intent):
    operation = intent.get("operation")

    if operation == "clarify":
        return {
            "reply": (
                "Did you want me to create "
                "a calendar event or a task?"
            ),
            "intent": "calendar_clarify",
        }

    if operation == "read":
        timeframe = (
            intent.get("timeframe")
            or "today"
        )

        return {
            "reply": (
                f"I understand you want "
                f"calendar events for {timeframe}, "
                f"but calendar integration "
                f"isn't wired yet."
            ),
            "intent": "calendar_read",
        }

    if operation == "create":
        title = intent.get("title") or "Untitled event"

        return {
            "reply": (
                f"I've captured the event "
                f"'{title}', but Google Calendar "
                f"write support isn't connected yet."
            ),
            "intent": "calendar_create",
        }

    return None