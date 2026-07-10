from app.case.handlers.tasks_handler import handle_task_intent
from app.case.handlers.lists_handler import handle_list_intent
from app.case.handlers.energy_handler import handle_energy_intent
from app.case.handlers.weather_handler import handle_weather_intent
from app.case.handlers.calendar_handler import handle_calendar_intent
from app.case.handlers.kids_handler import handle_kids_intent
from app.case.handlers.household_handler import handle_household_intent
from app.case.handlers.features_handler import handle_features_intent
from app.case.handlers.iot_handler import handle_iot_intent
from app.case.handlers.navigation_handler import handle_navigation_intent
from app.case.handlers.refresh_handler import handle_refresh_intent


def handle_case_intent(intent):
    domain = intent.get("domain")
    operation = intent.get("operation")

    if intent.get("clarification_needed") or operation == "clarify":
        return {
            "reply": intent.get("clarification_question")
            or "Sorry, can you clarify what you want me to do?",
            "intent": "clarify",
            "confidence": intent.get("confidence", "low"),
            "source": "intent_handler",
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

    if domain == "features":
        return handle_features_intent(intent)

    if domain == "iot":
        return handle_iot_intent(intent)

    if domain == "navigation":
        return handle_navigation_intent(intent)

    if domain == "refresh":
        return handle_refresh_intent(intent)

    if domain == "time":
        from datetime import datetime
        from zoneinfo import ZoneInfo

        now = datetime.now(ZoneInfo("Australia/Perth"))

        return {
            "reply": f"It's {now.strftime('%-I:%M %p')}.",
            "intent": "query_time",
            "confidence": intent.get("confidence", "medium"),
            "source": "intent_handler",
        }

    if domain == "birthdays":
        return {
            "reply": "I understand the birthday question, but birthdays are not wired in yet.",
            "intent": "birthdays_read",
            "confidence": intent.get("confidence", "medium"),
            "source": "intent_handler",
        }

    return {
        "reply": "I understood the request, but that handler is not wired in yet.",
        "intent": "not_implemented",
        "confidence": intent.get("confidence", "medium"),
        "source": "intent_handler",
    }
