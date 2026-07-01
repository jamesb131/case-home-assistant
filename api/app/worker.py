import os
import time
from datetime import datetime
from zoneinfo import ZoneInfo

from app.case.handlers.household_handler import describe_bins, get_bin_schedule
from app.repositories.system_snapshots_repository import (
    record_heartbeat,
    upsert_snapshot,
)
from app.repositories.task_templates_repository import generate_recurring_tasks
from app.services.energy_repository import (
    insert_energy_reading,
    prune_energy_readings,
    refresh_energy_daily_rollups,
)
from app.services.google_calendar_client import get_calendar_error, get_upcoming_events
from app.services.sigenergy_client import get_energy_snapshot
from app.services.weather_client import get_weather_summary


LOG_INTERVAL_SECONDS = int(os.getenv("LOG_INTERVAL", "30"))
WEATHER_INTERVAL_SECONDS = int(os.getenv("WEATHER_POLL_INTERVAL", "900"))
CALENDAR_INTERVAL_SECONDS = int(os.getenv("CALENDAR_POLL_INTERVAL", "900"))
BINS_INTERVAL_SECONDS = int(os.getenv("BINS_POLL_INTERVAL", "3600"))
STATUS_INTERVAL_SECONDS = int(os.getenv("STATUS_POLL_INTERVAL", "60"))
RETENTION_INTERVAL_SECONDS = int(os.getenv("RETENTION_INTERVAL", "86400"))
RECURRING_TASK_INTERVAL_SECONDS = int(os.getenv("RECURRING_TASK_INTERVAL", "3600"))
RECURRING_TASK_DAYS_AHEAD = int(os.getenv("RECURRING_TASK_DAYS_AHEAD", "21"))
ENERGY_RETENTION_DAYS = int(os.getenv("ENERGY_RETENTION_DAYS", "0"))
PERTH_TZ = ZoneInfo("Australia/Perth")


def log_energy_snapshot():
    snapshot = get_energy_snapshot()
    result = insert_energy_reading(snapshot)
    upsert_snapshot(
        "energy.latest",
        {
            "snapshot": snapshot,
            "inserted": result,
        },
        ttl_seconds=max(LOG_INTERVAL_SECONDS * 4, 120),
    )

    return {
        "result": result,
        "snapshot": snapshot,
    }


def poll_weather_snapshot():
    summary = get_weather_summary()
    return upsert_snapshot(
        "weather.summary",
        summary,
        ttl_seconds=WEATHER_INTERVAL_SECONDS * 3,
    )


def poll_calendar_snapshot():
    events = get_upcoming_events(days=30, max_results=50)

    if events is None:
        return upsert_snapshot(
            "calendar.upcoming",
            {
                "events": [],
                "calendar_available": False,
            },
            status="error",
            ttl_seconds=CALENDAR_INTERVAL_SECONDS,
            error=get_calendar_error(),
        )

    return upsert_snapshot(
        "calendar.upcoming",
        {
            "events": events,
            "calendar_available": True,
        },
        ttl_seconds=CALENDAR_INTERVAL_SECONDS * 3,
    )


def poll_bins_snapshot():
    now = datetime.now(PERTH_TZ)
    schedule = get_bin_schedule(now)

    return upsert_snapshot(
        "household.bins",
        {
            "pickup_date": schedule["pickup_date"].isoformat(),
            "put_out_date": schedule["put_out_date"].isoformat(),
            "extra_bin": schedule["extra_bin"],
            "description": describe_bins(schedule),
        },
        ttl_seconds=BINS_INTERVAL_SECONDS * 3,
    )


def poll_worker_status():
    return record_heartbeat(
        "worker",
        details={
            "energy_interval_seconds": LOG_INTERVAL_SECONDS,
            "weather_interval_seconds": WEATHER_INTERVAL_SECONDS,
            "calendar_interval_seconds": CALENDAR_INTERVAL_SECONDS,
            "bins_interval_seconds": BINS_INTERVAL_SECONDS,
            "recurring_task_interval_seconds": RECURRING_TASK_INTERVAL_SECONDS,
            "recurring_task_days_ahead": RECURRING_TASK_DAYS_AHEAD,
        },
    )


def poll_recurring_tasks():
    result = generate_recurring_tasks(days_ahead=RECURRING_TASK_DAYS_AHEAD)

    return upsert_snapshot(
        "tasks.recurring",
        {
            "days_ahead": RECURRING_TASK_DAYS_AHEAD,
            "created_count": result["created_count"],
            "created_task_ids": [
                task["id"]
                for task in result["created"]
            ],
        },
        ttl_seconds=RECURRING_TASK_INTERVAL_SECONDS * 3,
    )


def run_retention_jobs():
    rollup_days_back = (
        max(14, ENERGY_RETENTION_DAYS + 7)
        if ENERGY_RETENTION_DAYS > 0
        else 14
    )
    rolled_up_days = refresh_energy_daily_rollups(days_back=rollup_days_back)
    deleted_readings = (
        prune_energy_readings(ENERGY_RETENTION_DAYS)
        if ENERGY_RETENTION_DAYS > 0
        else 0
    )

    return upsert_snapshot(
        "retention.energy",
        {
            "rolled_up_days": rolled_up_days,
            "deleted_readings": deleted_readings,
            "energy_retention_days": ENERGY_RETENTION_DAYS,
            "pruning_enabled": ENERGY_RETENTION_DAYS > 0,
            "rollup_days_back": rollup_days_back,
        },
        ttl_seconds=RETENTION_INTERVAL_SECONDS * 2,
    )


def run_job(name, job):
    try:
        result = job()
        print(f"{name} ok")
        return result
    except Exception as exc:
        print(f"{name} error: {exc}")
        upsert_snapshot(
            f"job.{name}",
            {},
            status="error",
            ttl_seconds=300,
            error=str(exc),
        )
        return None


def worker_loop():
    print("CASE worker started")

    jobs = [
        {
            "name": "energy",
            "interval": LOG_INTERVAL_SECONDS,
            "job": log_energy_snapshot,
            "next_run": 0,
        },
        {
            "name": "weather",
            "interval": WEATHER_INTERVAL_SECONDS,
            "job": poll_weather_snapshot,
            "next_run": 0,
        },
        {
            "name": "calendar",
            "interval": CALENDAR_INTERVAL_SECONDS,
            "job": poll_calendar_snapshot,
            "next_run": 0,
        },
        {
            "name": "bins",
            "interval": BINS_INTERVAL_SECONDS,
            "job": poll_bins_snapshot,
            "next_run": 0,
        },
        {
            "name": "status",
            "interval": STATUS_INTERVAL_SECONDS,
            "job": poll_worker_status,
            "next_run": 0,
        },
        {
            "name": "recurring_tasks",
            "interval": RECURRING_TASK_INTERVAL_SECONDS,
            "job": poll_recurring_tasks,
            "next_run": 0,
        },
        {
            "name": "retention",
            "interval": RETENTION_INTERVAL_SECONDS,
            "job": run_retention_jobs,
            "next_run": 0,
        },
    ]

    while True:
        now = time.monotonic()

        for job in jobs:
            if now < job["next_run"]:
                continue

            run_job(job["name"], job["job"])
            job["next_run"] = now + job["interval"]

        time.sleep(1)


def main():
    worker_loop()


if __name__ == "__main__":
    main()
