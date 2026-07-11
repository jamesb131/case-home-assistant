from datetime import datetime, timezone

from app.repositories.system_snapshots_repository import (
    get_heartbeat,
    get_snapshot,
    list_snapshots,
)
from app.services.db import get_connection
from app.services.google_calendar_client import get_calendar_error, get_calendar_service
from app.services.ollama_client import get_ollama_status


def get_system_status():
    snapshots = {snapshot["key"]: snapshot for snapshot in list_snapshots()}

    return {
        "api": {
            "status": "ok",
        },
        "db": get_db_status(),
        "worker": get_worker_status(),
        "llm": get_ollama_status(),
        "calendar": get_calendar_status(snapshots.get("calendar.upcoming")),
        "weather": get_snapshot_status(snapshots.get("weather.summary")),
        "sigenergy": get_snapshot_status(snapshots.get("energy.latest")),
        "bins": get_snapshot_status(snapshots.get("household.bins")),
        "recurring_tasks": get_snapshot_status(snapshots.get("tasks.recurring")),
        "gaggimate": get_snapshot_status(snapshots.get("iot.gaggimate")),
        "roborock": get_snapshot_status(snapshots.get("iot.roborock")),
        "news": get_snapshot_status(snapshots.get("news.latest")),
        "snapshots": snapshots,
    }


def get_db_status():
    try:
        conn = get_connection()

        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
        finally:
            conn.close()

        return {"status": "ok"}
    except Exception as exc:
        return {
            "status": "error",
            "error": str(exc),
        }


def get_worker_status():
    heartbeat = get_heartbeat("worker")

    if not heartbeat:
        return {
            "status": "unknown",
            "message": "No worker heartbeat recorded yet.",
        }

    heartbeat_at = datetime.fromisoformat(heartbeat["heartbeat_at"])

    if heartbeat_at.tzinfo is None:
        heartbeat_at = heartbeat_at.replace(tzinfo=timezone.utc)

    age_seconds = (datetime.now(timezone.utc) - heartbeat_at).total_seconds()
    status = "ok" if age_seconds <= 180 else "stale"

    return {
        **heartbeat,
        "status": status if heartbeat["status"] == "ok" else heartbeat["status"],
        "age_seconds": round(age_seconds),
    }


def get_calendar_status(snapshot):
    service = get_calendar_service()

    if not service:
        return {
            "status": "error",
            "calendar_available": False,
            "error": get_calendar_error(),
            "snapshot": get_snapshot_status(snapshot),
        }

    return {
        "status": "ok",
        "calendar_available": True,
        "snapshot": get_snapshot_status(snapshot),
    }


def get_snapshot_status(snapshot):
    if not snapshot:
        return {
            "status": "unknown",
            "message": "No snapshot recorded yet.",
        }

    captured_at = datetime.fromisoformat(snapshot["captured_at"])

    if captured_at.tzinfo is None:
        captured_at = captured_at.replace(tzinfo=timezone.utc)

    age_seconds = (datetime.now(timezone.utc) - captured_at).total_seconds()

    status = snapshot["status"]

    if snapshot["expires_at"]:
        expires_at = datetime.fromisoformat(snapshot["expires_at"])

        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)

        if datetime.now(timezone.utc) > expires_at and status == "ok":
            status = "stale"

    return {
        "status": status,
        "captured_at": snapshot["captured_at"],
        "expires_at": snapshot["expires_at"],
        "age_seconds": round(age_seconds),
        "error": snapshot["error"],
    }
