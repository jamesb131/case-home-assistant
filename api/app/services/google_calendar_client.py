import os
import shutil
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from google.auth.exceptions import RefreshError
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError


SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"]

GOOGLE_DIR = os.getenv("GOOGLE_DIR", "/app/app/google")
GOOGLE_IMPORT_DIR = os.getenv("GOOGLE_IMPORT_DIR")
CREDENTIALS_PATH = os.path.join(GOOGLE_DIR, "credentials.json")
TOKEN_PATH = os.path.join(GOOGLE_DIR, "token.json")

CALENDAR_ID = os.getenv("GOOGLE_CALENDAR_ID", "primary")
PERTH_TZ = ZoneInfo("Australia/Perth")
_last_calendar_error = None


def get_calendar_service():
    global _last_calendar_error
    creds = None

    try:
        ensure_google_auth_files()

        if os.path.exists(TOKEN_PATH):
            creds = load_credentials()

        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                try:
                    creds.refresh(Request())
                except RefreshError as exc:
                    clear_stale_token()
                    ensure_google_auth_files()
                    retry_result = retry_imported_token_refresh()

                    if retry_result:
                        creds = retry_result
                    else:
                        return calendar_unavailable(
                            f"Google calendar token could not be refreshed: {exc}"
                        )
            else:
                return calendar_unavailable(
                    "Google calendar is not authorised. Run auth_google_calendar.py."
                )

            save_token(creds)

        _last_calendar_error = None
        return build("calendar", "v3", credentials=creds)

    except Exception as exc:
        return calendar_unavailable(f"Google calendar unavailable: {exc}")


def retry_imported_token_refresh():
    if not os.path.exists(TOKEN_PATH):
        return None

    try:
        creds = load_credentials()

        if not creds or creds.valid:
            return creds

        if creds.expired and creds.refresh_token:
            creds.refresh(Request())
            save_token(creds)
            return creds
    except RefreshError as exc:
        calendar_unavailable(
            f"Google calendar imported token could not be refreshed: {exc}"
        )
    except Exception as exc:
        calendar_unavailable(f"Google calendar imported token failed: {exc}")

    return None


def get_calendar_auth_status():
    ensure_google_auth_files()

    status = {
        "google_dir": GOOGLE_DIR,
        "google_import_dir": GOOGLE_IMPORT_DIR,
        "credentials_path": CREDENTIALS_PATH,
        "token_path": TOKEN_PATH,
        "credentials_exists": os.path.exists(CREDENTIALS_PATH),
        "token_exists": os.path.exists(TOKEN_PATH),
        "import_credentials_exists": False,
        "import_token_exists": False,
        "last_error": get_calendar_error(),
    }

    if GOOGLE_IMPORT_DIR:
        status["import_credentials_exists"] = os.path.exists(
            os.path.join(GOOGLE_IMPORT_DIR, "credentials.json")
        )
        status["import_token_exists"] = os.path.exists(
            os.path.join(GOOGLE_IMPORT_DIR, "token.json")
        )

    if not status["token_exists"]:
        return {
            **status,
            "available": False,
            "token_valid": False,
            "message": "Google token file is missing.",
        }

    try:
        creds = load_credentials()

        return {
            **status,
            "available": bool(creds and creds.valid),
            "token_valid": bool(creds and creds.valid),
            "token_expired": bool(creds and creds.expired),
            "has_refresh_token": bool(creds and creds.refresh_token),
            "message": (
                "Google token is valid."
                if creds and creds.valid
                else "Google token exists but is not currently valid."
            ),
        }
    except Exception as exc:
        return {
            **status,
            "available": False,
            "token_valid": False,
            "message": f"Google token could not be read: {exc}",
        }


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


def load_credentials():
    try:
        return Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)
    except Exception as exc:
        quarantine_token(f"Could not read Google token: {exc}")
        ensure_google_auth_files()

        if os.path.exists(TOKEN_PATH):
            return Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)

        raise


def ensure_google_auth_files():
    if not GOOGLE_IMPORT_DIR or not os.path.isdir(GOOGLE_IMPORT_DIR):
        return

    os.makedirs(GOOGLE_DIR, exist_ok=True)

    for filename in ("credentials.json", "token.json"):
        source_path = os.path.join(GOOGLE_IMPORT_DIR, filename)
        target_path = os.path.join(GOOGLE_DIR, filename)

        if not os.path.exists(source_path) or os.path.exists(target_path):
            continue

        shutil.copy2(source_path, target_path)
        os.chmod(target_path, 0o600)
        print(f"Imported Google auth file: {target_path}")


def save_token(creds):
    token_json = creds.to_json()
    write_file_atomic(TOKEN_PATH, token_json)

    if GOOGLE_IMPORT_DIR and os.path.isdir(GOOGLE_IMPORT_DIR):
        import_token_path = os.path.join(GOOGLE_IMPORT_DIR, "token.json")

        try:
            write_file_atomic(import_token_path, token_json)
        except OSError as exc:
            print(f"Could not update Google token backup: {exc}")


def write_file_atomic(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temp_path = f"{path}.tmp"

    with open(temp_path, "w") as handle:
        handle.write(content)

    os.chmod(temp_path, 0o600)
    os.replace(temp_path, path)


def quarantine_token(reason):
    print(reason)

    if not os.path.exists(TOKEN_PATH):
        return

    failed_path = f"{TOKEN_PATH}.invalid"

    try:
        os.replace(TOKEN_PATH, failed_path)
    except OSError as exc:
        print(f"Could not quarantine Google token: {exc}")


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
