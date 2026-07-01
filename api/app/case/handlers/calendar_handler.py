from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from app.services.google_calendar_client import get_upcoming_events


PERTH_TZ = ZoneInfo("Australia/Perth")
WEEKDAYS = {
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}


def handle_calendar_intent(intent):
    operation = intent.get("operation")

    if operation == "clarify":
        return {
            "reply": "Did you want me to create a calendar event, or just add a task?",
            "intent": "calendar_clarify",
            "confidence": intent.get("confidence", "medium"),
            "source": "calendar_handler",
        }

    if operation == "create":
        title = intent.get("title") or "Untitled event"
        return {
            "reply": f"I captured '{title}', but calendar write support isn't connected yet.",
            "intent": "calendar_create",
            "confidence": intent.get("confidence", "medium"),
            "source": "calendar_handler",
        }

    if operation != "read":
        return None

    timeframe = infer_timeframe(intent)
    target_date = infer_target_date(intent)
    days = days_to_fetch(timeframe, target_date)

    events = get_upcoming_events(days=days, max_results=30)

    if events is None:
        return {
            "reply": "I couldn't access the calendar right now. It may need reconnecting.",
            "intent": "calendar_unavailable",
            "confidence": intent.get("confidence", "medium"),
            "source": "calendar_handler",
        }

    filtered = filter_events(events, timeframe, target_date)

    if not filtered:
        return {
            "reply": "Nothing obvious on the calendar for that period.",
            "intent": "calendar_read",
            "confidence": intent.get("confidence", "medium"),
            "source": "calendar_handler",
        }

    lines = [format_event(event) for event in filtered[:5]]

    return {
        "reply": "You have " + "; ".join(lines) + ".",
        "intent": "calendar_read",
        "confidence": intent.get("confidence", "medium"),
        "source": "calendar_handler",
    }


def infer_timeframe(intent):
    timeframe = intent.get("timeframe")
    if timeframe:
        return timeframe

    raw = (
        intent.get("question")
        or intent.get("raw_message")
        or ""
    ).lower()

    if "tomorrow" in raw:
        return "tomorrow"

    if "today" in raw:
        return "today"

    if "weekend" in raw:
        return "this_weekend"

    return "upcoming"


def days_to_fetch(timeframe, target_date=None):
    if target_date:
        today = datetime.now(PERTH_TZ).date()
        return max((target_date - today).days + 1, 1)

    if timeframe == "today":
        return 1
    if timeframe == "tomorrow":
        return 2
    if timeframe == "this_weekend":
        return 10
    return 10


def infer_target_date(intent):
    if intent.get("date"):
        return datetime.fromisoformat(intent["date"]).date()

    raw = (
        intent.get("question")
        or intent.get("raw_message")
        or ""
    ).lower()

    now = datetime.now(PERTH_TZ).date()

    for name, weekday in WEEKDAYS.items():
        if name not in raw:
            continue

        days_ahead = (weekday - now.weekday()) % 7

        if f"next {name}" in raw and days_ahead == 0:
            days_ahead = 7

        return now + timedelta(days=days_ahead)

    return None


def filter_events(events, timeframe, target_date=None):
    now = datetime.now(PERTH_TZ)

    if target_date:
        return [
            event for event in events
            if parse_event_date(event).date() == target_date
        ]

    if timeframe == "today":
        today = now.date()
        return [
            event for event in events
            if parse_event_date(event).date() == today
        ]

    if timeframe == "tomorrow":
        tomorrow = (now + timedelta(days=1)).date()
        return [
            event for event in events
            if parse_event_date(event).date() == tomorrow
        ]

    if timeframe == "this_weekend":
        return [
            event for event in events
            if parse_event_date(event).weekday() in [5, 6]
        ]

    return events


def parse_event_date(event):
    start = event.get("start")

    if not start:
        return datetime.now(PERTH_TZ)

    if len(start) == 10:
        return datetime.fromisoformat(start).replace(tzinfo=PERTH_TZ)

    value = datetime.fromisoformat(start)

    if value.tzinfo is None:
        return value.replace(tzinfo=PERTH_TZ)

    return value.astimezone(PERTH_TZ)


def format_event(event):
    start = parse_event_date(event)

    title = event.get("title") or "Untitled event"
    location = event.get("location")

    if event.get("is_all_day"):
        time_text = "all day"
    else:
        time_text = start.strftime("%-I:%M %p")

    if location:
        return f"{title} at {time_text}, {location}"

    return f"{title} at {time_text}"
