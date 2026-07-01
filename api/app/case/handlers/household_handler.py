from datetime import datetime, timedelta
from zoneinfo import ZoneInfo


PERTH_TZ = ZoneInfo("Australia/Perth")
PICKUP_WEEKDAY = 1  # Tuesday


def handle_household_intent(intent):
    category = intent.get("category")

    if category != "bins":
        return None

    now = datetime.now(PERTH_TZ)
    question = (
        intent.get("question")
        or intent.get("raw_message")
        or ""
    ).lower()
    target_date = infer_target_date(intent, now)
    schedule = get_bin_schedule(now)

    if target_date:
        return response_for_target_date(
            target_date=target_date,
            schedule=schedule,
            question=question,
            intent=intent,
        )

    return response(
        (
            f"This week is {describe_bins(schedule)}. "
            f"They go out {format_relative_night(schedule['put_out_date'], now)} "
            f"for {format_relative_morning(schedule['pickup_date'], now)} pickup."
        ),
        intent,
    )


def infer_target_date(intent, now):
    if intent.get("date"):
        return datetime.fromisoformat(intent["date"]).date()

    timeframe = intent.get("timeframe")
    question = (
        intent.get("question")
        or intent.get("raw_message")
        or ""
    ).lower()

    if timeframe == "today" or "today" in question or "tonight" in question:
        return now.date()

    if timeframe == "tomorrow" or "tomorrow" in question:
        return now.date() + timedelta(days=1)

    return None


def get_bin_schedule(now):
    today = now.date()
    days_until_pickup = (PICKUP_WEEKDAY - today.weekday()) % 7
    pickup_date = today + timedelta(days=days_until_pickup)
    put_out_date = pickup_date - timedelta(days=1)

    if today.weekday() == PICKUP_WEEKDAY and now.hour >= 12:
        pickup_date = pickup_date + timedelta(days=7)
        put_out_date = put_out_date + timedelta(days=7)

    extra_bin = get_extra_bin(pickup_date)

    return {
        "pickup_date": pickup_date,
        "put_out_date": put_out_date,
        "extra_bin": extra_bin,
    }


def get_extra_bin(pickup_date):
    week_number = pickup_date.isocalendar().week

    if week_number % 2 == 0:
        return "yellow recycling"

    return "green organics"


def response_for_target_date(target_date, schedule, question, intent):
    asks_collection = any(
        word in question
        for word in ["collect", "collected", "collection", "pickup", "picked up"]
    )

    if asks_collection and target_date == schedule["pickup_date"]:
        return response(
            (
                f"Yes. {describe_bins(schedule, capitalise=True)} are collected "
                f"{format_day(schedule['pickup_date'])} morning."
            ),
            intent,
        )

    if target_date == schedule["put_out_date"]:
        return response(
            (
                f"Yes. {describe_bins(schedule, capitalise=True)} go out "
                f"{format_day(schedule['put_out_date'])} night "
                f"for {format_day(schedule['pickup_date'])} morning pickup."
            ),
            intent,
        )

    if target_date == schedule["pickup_date"]:
        return response(
            (
                f"They're collected {format_day(schedule['pickup_date'])} morning, "
                f"so {describe_bins(schedule)} should go out "
                f"{format_day(schedule['put_out_date'])} night."
            ),
            intent,
        )

    return response(
        (
            f"No. The next bin night is {format_day(schedule['put_out_date'])} night: "
            f"{describe_bins(schedule)}."
        ),
        intent,
    )


def describe_bins(schedule, capitalise=False):
    text = f"red general waste plus {schedule['extra_bin']}"

    if capitalise:
        return text[0].upper() + text[1:]

    return text


def format_relative_night(day, now):
    today = now.date()

    if day == today:
        return "tonight"

    if day == today + timedelta(days=1):
        return "tomorrow night"

    return f"{day.strftime('%A')} night"


def format_relative_morning(day, now):
    today = now.date()

    if day == today:
        return "this morning"

    if day == today + timedelta(days=1):
        return "tomorrow morning"

    return f"{day.strftime('%A')} morning"


def format_day(day):
    return day.strftime("%A")


def response(reply, intent):
    return {
        "reply": reply,
        "intent": "bins_read",
        "confidence": intent.get("confidence", "medium"),
        "source": "household_handler",
    }
