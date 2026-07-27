import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from app.repositories.calendar_repository import create_calendar_event, get_upcoming_calendar_events
from app.repositories.tasks_repository import create_task


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
    raw = intent.get("raw_message") or intent.get("question") or ""

    if operation == "clarify":
        return {
            "reply": "Did you want me to create a calendar event, or just add a task?",
            "intent": "calendar_clarify",
            "confidence": intent.get("confidence", "medium"),
            "source": "calendar_handler",
        }

    if operation == "create":
        event = build_calendar_event_from_intent(intent)

        if not event.get("start"):
            return {
                "reply": "I can add that event, but I need a date and time first.",
                "intent": "calendar_create_clarify",
                "confidence": "medium",
                "source": "calendar_handler",
            }

        created = create_calendar_event(**event)
        task = create_related_task_from_text(raw)
        task_text = f" I also added task {task['title']}." if task else ""

        return {
            "reply": f"Added {format_created_event(created)}.{task_text}",
            "intent": "calendar_create",
            "confidence": intent.get("confidence", "high"),
            "source": "calendar_handler",
            "event": created,
            "task": task,
        }

    if operation != "read":
        return None

    timeframe = infer_timeframe(intent)
    target_date = infer_target_date(intent)
    days = days_to_fetch(timeframe, target_date)

    events = get_upcoming_calendar_events(days=days, max_results=30)

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

    if "tomorrow" in raw:
        return now + timedelta(days=1)

    if "today" in raw:
        return now

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


def build_calendar_event_from_intent(intent):
    raw = intent.get("raw_message") or intent.get("question") or ""
    parsed = parse_calendar_create_text(raw)
    marker_category = intent.get("category") if intent.get("category") in {"daycare", "kindy", "school_day"} else None
    title = (
        parsed.get("title")
        if parsed.get("date")
        else intent.get("title")
    ) or clean_calendar_title(raw) or "Untitled event"
    date_value = intent.get("date") or parsed.get("date")
    start_time = intent.get("time") or parsed.get("start_time")
    end_time = intent.get("end_time") or parsed.get("end_time")
    start = None
    end = None
    is_all_day = False

    if not date_value:
        target_date = infer_target_date(intent)
        if target_date:
            date_value = target_date.isoformat()

    if marker_category:
        title = normalise_child_marker_title(intent, title)
        start_time = None
        end_time = None

    if date_value:
        if start_time:
            start = datetime.fromisoformat(f"{date_value}T{start_time}:00").replace(tzinfo=PERTH_TZ).isoformat()
        else:
            start = date_value
            is_all_day = True

        if end_time and not is_all_day:
            end = datetime.fromisoformat(f"{date_value}T{end_time}:00").replace(tzinfo=PERTH_TZ).isoformat()

    return {
        "title": title,
        "start": start,
        "end": end,
        "is_all_day": is_all_day,
        "description": intent.get("description"),
        "location": intent.get("location") or parsed.get("location"),
        "category": intent.get("category"),
        "audience": intent.get("person"),
    }


def normalise_child_marker_title(intent, fallback_title):
    person = intent.get("person") or "Child"
    category = intent.get("category")

    if category == "daycare":
        return f"{person} daycare"

    if category == "kindy":
        return f"{person} kindy"

    if category == "school_day":
        return f"{person} school"

    return fallback_title


def parse_calendar_create_text(text):
    cleaned = re.sub(r"^\s*(add|create|make|book)\s+(an?\s+)?(calendar\s+)?(event|appointment)?\s*", "", text, flags=re.I)
    date_match = find_date(cleaned)

    if not date_match:
        return {"title": cleaned.strip(" .")}

    title = cleaned[:date_match.start()].strip(" -,.") or cleaned.strip(" .")
    tail = cleaned[date_match.end():]
    start_time, end_time = find_time_range(tail)
    location = find_location(tail)

    return {
        "title": title,
        "date": date_match.group("date"),
        "start_time": start_time,
        "end_time": end_time,
        "location": location,
    }


def find_date(text):
    months = {
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    }
    pattern = re.compile(
        r"\b(?P<month>" + "|".join(months.keys()) + r")\s+(?P<day>\d{1,2})(st|nd|rd|th)?\b",
        re.I,
    )
    match = pattern.search(text)

    if not match:
        return None

    now = datetime.now(PERTH_TZ)
    month = months[match.group("month").lower()]
    day = int(match.group("day"))
    year = now.year

    if (month, day) < (now.month, now.day):
        year += 1

    date_value = f"{year:04d}-{month:02d}-{day:02d}"

    return RegexDateMatch(match, date_value)


def find_time_range(text):
    times = re.findall(r"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b", text, flags=re.I)

    if not times:
        return None, None

    start_hour, start_minute, start_ampm = times[0]
    end_hour = end_minute = end_ampm = None

    if len(times) > 1:
        end_hour, end_minute, end_ampm = times[1]
        if not start_ampm and end_ampm:
            start_ampm = end_ampm

    return (
        normalise_time(start_hour, start_minute, start_ampm),
        normalise_time(end_hour, end_minute, end_ampm) if end_hour else None,
    )


def normalise_time(hour, minute, ampm):
    if hour is None:
        return None

    value = int(hour)
    minute_value = int(minute or 0)
    suffix = (ampm or "").lower()

    if suffix == "pm" and value < 12:
        value += 12
    elif suffix == "am" and value == 12:
        value = 0

    return f"{value:02d}:{minute_value:02d}"


def find_location(text):
    match = re.search(r"\bat\s+(.+?)(?:\.\s*also\b|\balso\s+add\s+task\b|$)", text, flags=re.I)

    if not match:
        return None

    location = match.group(1).strip(" .")
    location = re.sub(r"\bfrom\s+\d{1,2}(?::\d{2})?\s*(am|pm)?\b.*$", "", location, flags=re.I)
    location = re.sub(r"\btill\s+\d{1,2}(?::\d{2})?\s*(am|pm)?\b.*$", "", location, flags=re.I)
    return location.strip(" .") or None


def clean_calendar_title(text):
    cleaned = re.sub(r"^\s*(add|create|make|book)\s+(an?\s+)?(calendar\s+)?(event|appointment)?\s*", "", text, flags=re.I)
    cleaned = re.split(r"\b(today|tomorrow|jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec|january|february|march|april|june|july|august|september|october|november|december)\b", cleaned, maxsplit=1, flags=re.I)[0]
    return cleaned.strip(" -,.")


def format_created_event(event):
    if not event:
        return "the calendar event"

    return format_event(event)


def create_related_task_from_text(text):
    match = re.search(r"\balso\s+add\s+task\s+(?P<task>.+)$", text, flags=re.I)

    if not match:
        return None

    task_text = match.group("task").strip(" .")
    due_date = None
    date_match = find_date(task_text)

    if date_match:
        due_date = date_match.group("date")
        task_text = (
            task_text[:date_match.start()]
            + task_text[date_match.end():]
        ).strip(" ,.-")

    task_text = re.sub(r"\bdue\b", "", task_text, flags=re.I).strip(" ,.-")

    if not task_text:
        return None

    return create_task(
        title=task_text,
        due_date=due_date,
        assigned_to="James",
        source="case_voice",
    )


class RegexDateMatch:
    def __init__(self, match, date_value):
        self._match = match
        self._date = date_value

    def start(self):
        return self._match.start()

    def end(self):
        return self._match.end()

    def group(self, key):
        if key == "date":
            return self._date
        return self._match.group(key)
