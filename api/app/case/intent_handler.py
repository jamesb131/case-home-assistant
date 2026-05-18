from app.case.handlers.tasks_handler import (
    handle_task_intent,
)

from app.case.handlers.lists_handler import (
    handle_list_intent,
)

from app.case.handlers.energy_handler import (
    handle_energy_intent,
)

from app.case.handlers.weather_handler import (
    handle_weather_intent,
)

from app.case.handlers.calendar_handler import (
    handle_calendar_intent,
)

from app.case.handlers.kids_handler import (
    handle_kids_intent,
)

from app.case.handlers.household_handler import (
    handle_household_intent,
)


def handle_case_intent(intent):
    domain = intent.get("domain")

    if intent.get("clarification_needed"):
        return {
            "reply": intent.get(
                "clarification_question"
            )
            or "Sorry, could you clarify that?",
            "intent": "clarify",
        }

    if domain == "tasks":
        return handle_task_intent(intent)

    if domain == "lists":
        return handle_list_intent(intent)

    if domain == "energy":
        return handle_energy_intent(intent)
    
    if domain == "weather":
        return handle_weather_intent(intent)

    if domain == "calendar":
        return handle_calendar_intent(intent)

    if domain == "kids":
        return handle_kids_intent(intent)

    if domain == "household":
        return handle_household_intent(intent)

    return {
        "reply": (
            "I understand what you're asking, "
            "but that capability isn't wired in yet."
        ),
        "intent": "not_implemented",
    }