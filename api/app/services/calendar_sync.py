import os
import re

from app.repositories.calendar_repository import (
    ensure_calendar_source,
    get_upcoming_calendar_events,
    mark_calendar_source_error,
    upsert_calendar_events,
)
from app.services.google_calendar_client import (
    CALENDAR_ID,
    get_calendar_error,
    get_upcoming_events,
)
from app.services.ics_calendar_client import fetch_ics_events


GOOGLE_SOURCE_NAME = "Google Calendar"
GOOGLE_SOURCE_TYPE = "google"
ICS_SOURCE_TYPE = "ics"


def sync_google_calendar(days=60, max_results=100):
    source_id = ensure_calendar_source(
        name=GOOGLE_SOURCE_NAME,
        source_type=GOOGLE_SOURCE_TYPE,
        external_id=CALENDAR_ID,
        config={"calendar_id": CALENDAR_ID},
        refresh_interval_seconds=1800,
    )
    events = get_upcoming_events(days=days, max_results=max_results)

    if events is None:
        error = get_calendar_error() or "Google calendar sync failed."
        mark_calendar_source_error(source_id, error)
        return {
            "source_id": source_id,
            "calendar_available": False,
            "synced_count": 0,
            "error": error,
            "events": get_upcoming_calendar_events(days=30, max_results=50),
        }

    synced_count = upsert_calendar_events(source_id, events)

    return {
        "source_id": source_id,
        "calendar_available": True,
        "synced_count": synced_count,
        "error": None,
        "events": get_upcoming_calendar_events(days=30, max_results=50),
    }


def sync_configured_ics_calendars():
    feeds = parse_calendar_feeds(os.getenv("SCHOOL_CALENDAR_FEEDS", ""))
    results = []
    primary_audience = os.getenv("SCHOOL_CALENDAR_PRIMARY_AUDIENCE", "Leo").strip() or "Leo"

    for feed in feeds:
        source_id = ensure_calendar_source(
            name=feed["name"],
            source_type=ICS_SOURCE_TYPE,
            external_id=feed["url"],
            url=feed["url"],
            config={"feed_name": feed["name"]},
            refresh_interval_seconds=int(os.getenv("SCHOOL_CALENDAR_REFRESH_INTERVAL_SECONDS", "1800")),
        )

        try:
            events = fetch_ics_events(feed["url"])
            events = prepare_school_review_events(events, primary_audience=feed.get("audience") or primary_audience)
            synced_count = upsert_calendar_events(source_id, events)
            results.append({
                "source_id": source_id,
                "name": feed["name"],
                "synced_count": synced_count,
                "error": None,
            })
        except Exception as exc:
            error = f"ICS calendar sync failed: {exc}"
            mark_calendar_source_error(source_id, error)
            results.append({
                "source_id": source_id,
                "name": feed["name"],
                "synced_count": 0,
                "error": error,
            })

    return results


def prepare_school_review_events(events, primary_audience="Leo"):
    return [prepare_school_review_event(event, primary_audience=primary_audience) for event in events]


def prepare_school_review_event(event, primary_audience="Leo"):
    review_status, review_reason = classify_school_event_for_review(event.get("title") or "")
    return {
        **event,
        "category": event.get("category") or "school",
        "audience": event.get("audience") or primary_audience,
        "review_status": review_status,
        "review_reason": review_reason,
    }


def classify_school_event_for_review(title):
    lower = title.lower()
    excluded_topics = [
        ("REA", r"\brea\b"),
        ("Confirmation", r"\bconfirmation\b"),
        ("Year 1 liturgy", r"\byear\s*1\s+liturgy\b|\byr\s*1\s+liturgy\b"),
    ]
    non_leo_years = [
        r"\byear\s*3\b", r"\byr\s*3\b",
        r"\byear\s*4\b", r"\byr\s*4\b",
        r"\byear\s*5\b", r"\byr\s*5\b",
        r"\byear\s*6\b", r"\byr\s*6\b",
        r"\by[3-6]\b",
        r"\b3\s*-\s*6\b",
        r"\byears\s*3\s*-\s*6\b",
    ]
    early_years = [
        r"\bkindy\b",
        r"\bpre[-\s]?kindy\b",
        r"\bpre[-\s]?primary\b",
        r"\bpp\b",
    ]

    for label, pattern in excluded_topics:
        if re_search(pattern, lower):
            return "ignored", f"{label} event excluded from Leo's school calendar."

    if any(re_search(pattern, lower) for pattern in non_leo_years):
        return "ignored", "Looks like it applies to Year 3-6, not Leo."

    if any(re_search(pattern, lower) for pattern in early_years):
        return "ignored", "Looks like it applies to Kindy or Pre-Primary, not Leo."

    return "approved", "General St Francis school calendar event."


def re_search(pattern, text):
    return re.search(pattern, text, flags=re.I)


def sync_all_calendars(days=60, max_results=100):
    google_result = sync_google_calendar(days=days, max_results=max_results)
    ics_results = sync_configured_ics_calendars()
    ics_errors = [result["error"] for result in ics_results if result.get("error")]
    successful_ics_count = sum(1 for result in ics_results if not result.get("error"))
    events = get_upcoming_calendar_events(days=30, max_results=50)

    return {
        "source_id": google_result["source_id"],
        "calendar_available": google_result["calendar_available"] or successful_ics_count > 0,
        "google": google_result,
        "ics": ics_results,
        "synced_count": google_result["synced_count"] + sum(result["synced_count"] for result in ics_results),
        "error": "; ".join([error for error in [google_result.get("error"), *ics_errors] if error]) or None,
        "events": events,
    }


def parse_calendar_feeds(value):
    feeds = []

    for part in [item.strip() for item in value.split(",") if item.strip()]:
        if "|" in part:
            bits = [bit.strip() for bit in part.split("|")]
            name = bits[0] if len(bits) > 0 else "School Calendar"
            url = bits[1] if len(bits) > 1 else ""
            audience = bits[2] if len(bits) > 2 else None
        else:
            name, url = "School Calendar", part
            audience = None

        if url.strip():
            feeds.append({
                "name": name.strip() or "School Calendar",
                "url": url.strip(),
                "audience": audience.strip() if audience else None,
            })

    return feeds
