import os
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from google.auth.exceptions import RefreshError
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError


SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"]

GOOGLE_DIR = os.getenv("GOOGLE_DIR", "/app/app/google")
CREDENTIALS_PATH = os.path.join(GOOGLE_DIR, "credentials.json")
TOKEN_PATH = os.path.join(GOOGLE_DIR, "token.json")

CALENDAR_ID = os.getenv("GOOGLE_CALENDAR_ID", "primary")
PERTH_TZ = ZoneInfo("Australia/Perth")
_last_calendar_error = None


def get_calendar_service():
    global _last_calendar_error
    creds = None

    try:
        if os.path.exists(TOKEN_PATH):
            creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)

        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                try:
                    creds.refresh(Request())
                except RefreshError as exc:
                    clear_stale_token()
                    return calendar_unavailable(
                        f"Google calendar token could not be refreshed: {exc}"
                    )
            else:
                return calendar_unavailable(
                    "Google calendar is not authorised. Run auth_google_calendar.py."
                )

            os.makedirs(GOOGLE_DIR, exist_ok=True)

            with open(TOKEN_PATH, "w") as token:
                token.write(creds.to_json())

        _last_calendar_error = None
        return build("calendar", "v3", credentials=creds)

    except Exception as exc:
        return calendar_unavailable(f"Google calendar unavailable: {exc}")


def get_upcoming_events(days: int = 7, max_results: int = 20):
    service = get_calendar_service()

    if not service:
        return None

    now = datetime.now(PERTH_TZ)
    time_min = now.isoformat()
    time_max = (now + timedelta(days=days)).isoformat()

    try:
        result = (
            service.events()
            .list(
                calendarId=CALENDAR_ID,
                timeMin=time_min,
                timeMax=time_max,
                maxResults=max_results,
                singleEvents=True,
                orderBy="startTime",
            )
            .execute()
        )
    except HttpError as exc:
        calendar_unavailable(f"Google calendar API error: {exc}")
        return None
    except Exception as exc:
        calendar_unavailable(f"Google calendar read failed: {exc}")
        return None

    events = result.get("items", [])

    return [normalise_event(event) for event in events]


def get_calendar_error():
    return _last_calendar_error


def calendar_unavailable(message):
    global _last_calendar_error
    _last_calendar_error = message
    print(message)
    return None


def clear_stale_token():
    try:
        if os.path.exists(TOKEN_PATH):
            os.remove(TOKEN_PATH)
    except OSError as exc:
        print(f"Could not remove stale Google token: {exc}")


def normalise_event(event):
    start_raw = event.get("start", {}).get("dateTime") or event.get("start", {}).get("date")
    end_raw = event.get("end", {}).get("dateTime") or event.get("end", {}).get("date")

    is_all_day = "dateTime" not in event.get("start", {})

    return {
        "id": event.get("id"),
        "title": event.get("summary", "Untitled event"),
        "location": event.get("location"),
        "start": start_raw,
        "end": end_raw,
        "is_all_day": is_all_day,
        "calendar_id": CALENDAR_ID,
    }
