from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from app.services.weather_client import get_weather_summary


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


def handle_weather_intent(intent):
    try:
        weather = get_weather_summary()
    except Exception:
        return {
            "reply": "I couldn't get the weather right now.",
            "intent": "weather_unavailable",
            "confidence": intent.get("confidence", "medium"),
            "source": "weather_handler",
        }

    timeframe = intent.get("timeframe")
    date = intent.get("date")
    question = (
        intent.get("question")
        or intent.get("raw_message")
        or ""
    ).lower()

    if not timeframe and not date:
        if "tomorrow" in question:
            timeframe = "tomorrow"
        elif "today" in question:
            timeframe = "today"
        elif "weekend" in question:
            timeframe = "this_weekend"

    daily = weather.get("daily", [])
    target_day = None

    if date:
        target_date = datetime.fromisoformat(date).date()
        target_day = find_day(daily, target_date)

    elif timeframe == "tomorrow":
        target_date = datetime.now(PERTH_TZ).date() + timedelta(days=1)
        target_day = find_day(daily, target_date)

    elif timeframe == "today":
        target_date = datetime.now(PERTH_TZ).date()
        target_day = find_day(daily, target_date)

    elif timeframe == "this_weekend":
        weekend_days = find_weekend_days(daily)

        if weekend_days:
            return {
                "reply": describe_weekend(weekend_days),
                "intent": "weather_read",
                "confidence": intent.get("confidence", "medium"),
                "source": "weather_handler",
            }

    if target_day is None and timeframe not in ["today", "tomorrow", "this_weekend"]:
        target_date = infer_named_weekday(question)

        if target_date:
            target_day = find_day(daily, target_date)

    if target_day:
        label_timeframe = timeframe

        if timeframe == "upcoming":
            label_timeframe = None

        return {
            "reply": describe_day(target_day, label_timeframe),
            "intent": "weather_read",
            "confidence": intent.get("confidence", "medium"),
            "source": "weather_handler",
        }

    current = weather.get("current", {})

    temp = current.get("temperature_2m")
    cloud = current.get("cloud_cover")
    wind = current.get("wind_speed_10m")

    if temp is None:
        return {
            "reply": "I found the weather data, but couldn't read the current temperature properly.",
            "intent": "weather_read",
            "confidence": intent.get("confidence", "medium"),
            "source": "weather_handler",
        }

    return {
        "reply": (
            f"Right now it's {temp:.0f} degrees, "
            f"cloud cover is {cloud or 0} percent, "
            f"and wind is {(wind or 0):.0f} kilometres an hour."
        ),
        "intent": "weather_read",
        "confidence": intent.get("confidence", "medium"),
        "source": "weather_handler",
    }


def find_day(daily, target_date):
    for day in daily:
        day_date = datetime.fromisoformat(day["date"]).date()

        if day_date == target_date:
            return day

    return None


def infer_named_weekday(question):
    today = datetime.now(PERTH_TZ).date()

    for name, weekday in WEEKDAYS.items():
        if name not in question:
            continue

        days_ahead = (weekday - today.weekday()) % 7

        if f"next {name}" in question and days_ahead == 0:
            days_ahead = 7

        return today + timedelta(days=days_ahead)

    return None


def find_weekend_days(daily):
    today = datetime.now(PERTH_TZ).date()
    days_until_saturday = (5 - today.weekday()) % 7
    saturday = today + timedelta(days=days_until_saturday)
    sunday = saturday + timedelta(days=1)

    return [
        day for day in daily
        if datetime.fromisoformat(day["date"]).date() in [saturday, sunday]
    ]


def describe_day(day, timeframe=None):
    if timeframe:
        label = timeframe.replace("_", " ")
    else:
        label = datetime.fromisoformat(day["date"]).strftime("%A")

    high = day.get("temp_max")
    low = day.get("temp_min")
    rain = day.get("rain_probability", 0)

    if rain >= 50:
        rain_text = "a decent chance of rain"
    elif rain >= 20:
        rain_text = "a small chance of rain"
    else:
        rain_text = "not much rain expected"

    return (
        f"{label.capitalize()} looks like {high:.0f} degrees max, "
        f"{low:.0f} overnight, with {rain_text}."
    )


def describe_weekend(days):
    summaries = [
        describe_day(day)
        for day in days
    ]

    if len(summaries) == 1:
        return summaries[0]

    return " ".join(summaries)
