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


GOOGLE_SOURCE_NAME = "Google Calendar"
GOOGLE_SOURCE_TYPE = "google"


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
