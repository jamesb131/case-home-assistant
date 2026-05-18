import os
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build


SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"]

GOOGLE_DIR = "/app/app/google"
CREDENTIALS_PATH = os.path.join(GOOGLE_DIR, "credentials.json")
TOKEN_PATH = os.path.join(GOOGLE_DIR, "token.json")

CALENDAR_ID = os.getenv("GOOGLE_CALENDAR_ID", "primary")
PERTH_TZ = ZoneInfo("Australia/Perth")


def get_calendar_service():
    creds = None

    if os.path.exists(TOKEN_PATH):
        creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(
                CREDENTIALS_PATH,
                SCOPES,
            )
            creds = flow.run_local_server(
                host="127.0.0.1",
                bind_addr="0.0.0.0",
                port=8085,
                open_browser=False,
                timeout_seconds=300,
            )

        os.makedirs(GOOGLE_DIR, exist_ok=True)

        with open(TOKEN_PATH, "w") as token:
            token.write(creds.to_json())

    return build("calendar", "v3", credentials=creds)


def get_upcoming_events(days: int = 7, max_results: int = 20):
    service = get_calendar_service()

    now = datetime.now(PERTH_TZ)
    time_min = now.isoformat()
    time_max = (now + timedelta(days=days)).isoformat()

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

    events = result.get("items", [])

    return [normalise_event(event) for event in events]


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