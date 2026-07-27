from datetime import date, datetime
from zoneinfo import ZoneInfo

import requests


PERTH_TZ = ZoneInfo("Australia/Perth")


def fetch_ics_events(url, timeout=12):
    response = requests.get(url, timeout=timeout)
    response.raise_for_status()
    return parse_ics_events(response.text)


def parse_ics_events(text):
    lines = unfold_ics_lines(text)
    events = []
    current = None

    for line in lines:
        if line == "BEGIN:VEVENT":
            current = {}
            continue

        if line == "END:VEVENT":
            if current:
                event = normalise_ics_event(current)
                if event:
                    events.append(event)
            current = None
            continue

        if current is None or ":" not in line:
            continue

        name, value = line.split(":", 1)
        prop, params = parse_property_name(name)
        current[prop] = {
            "value": decode_ics_text(value),
            "params": params,
        }

    return events


def unfold_ics_lines(text):
    unfolded = []

    for raw_line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if not raw_line:
            continue

        if raw_line.startswith((" ", "\t")) and unfolded:
            unfolded[-1] += raw_line[1:]
        else:
            unfolded.append(raw_line.strip())

    return unfolded


def parse_property_name(name):
    parts = name.split(";")
    prop = parts[0].upper()
    params = {}

    for part in parts[1:]:
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        params[key.upper()] = value

    return prop, params


def normalise_ics_event(item):
    uid = get_ics_value(item, "UID")
    title = get_ics_value(item, "SUMMARY")
    start_value = item.get("DTSTART")

    if not uid or not title or not start_value:
        return None

    start, is_all_day = parse_ics_datetime(
        start_value["value"],
        start_value.get("params", {}),
    )
    end = None

    if item.get("DTEND"):
        end, _ = parse_ics_datetime(
            item["DTEND"]["value"],
            item["DTEND"].get("params", {}),
        )

    return {
        "id": uid,
        "title": title,
        "description": get_ics_value(item, "DESCRIPTION"),
        "location": get_ics_value(item, "LOCATION"),
        "start": start,
        "end": end,
        "is_all_day": is_all_day,
        "category": "school" if looks_like_school_event(title) else None,
        "audience": infer_school_audience(title),
        "url": get_ics_value(item, "URL"),
    }


def parse_ics_datetime(value, params):
    if params.get("VALUE") == "DATE" or len(value) == 8:
        parsed = date(
            int(value[0:4]),
            int(value[4:6]),
            int(value[6:8]),
        )
        return parsed.isoformat(), True

    cleaned = value.rstrip("Z")
    parsed = datetime.strptime(cleaned, "%Y%m%dT%H%M%S")

    if value.endswith("Z"):
        parsed = parsed.replace(tzinfo=ZoneInfo("UTC")).astimezone(PERTH_TZ)
    else:
        timezone_name = params.get("TZID")
        timezone = ZoneInfo(timezone_name) if timezone_name else PERTH_TZ
        parsed = parsed.replace(tzinfo=timezone).astimezone(PERTH_TZ)

    return parsed.isoformat(), False


def get_ics_value(item, key):
    value = item.get(key)
    return value.get("value") if value else None


def decode_ics_text(value):
    return (
        value
        .replace("\\n", "\n")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\")
    )


def looks_like_school_event(title):
    lower = title.lower()
    return any(
        word in lower
        for word in ["school", "assembly", "term", "pupil", "student", "year", "book week"]
    )


def infer_school_audience(title):
    lower = title.lower()

    if "year 2" in lower or "yr 2" in lower:
        return "Leo"

    if "kindy" in lower or "pre-primary" in lower:
        return "Benny"

    return None
