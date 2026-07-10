from app.worker import (
    log_energy_snapshot,
    poll_bins_snapshot,
    poll_calendar_snapshot,
    poll_gaggimate_snapshot,
    poll_recurring_tasks,
    poll_weather_snapshot,
    poll_worker_status,
)


REFRESH_JOBS = {
    "energy": log_energy_snapshot,
    "weather": poll_weather_snapshot,
    "calendar": poll_calendar_snapshot,
    "events": poll_calendar_snapshot,
    "bins": poll_bins_snapshot,
    "status": poll_worker_status,
    "recurring_tasks": poll_recurring_tasks,
    "gaggimate": poll_gaggimate_snapshot,
    "coffee": poll_gaggimate_snapshot,
}

REFRESH_ALIASES = {
    "all": ["energy", "weather", "calendar", "bins", "status", "recurring_tasks", "gaggimate"],
    "everything": ["energy", "weather", "calendar", "bins", "status", "recurring_tasks", "gaggimate"],
    "data": ["energy", "weather", "calendar", "bins", "status", "recurring_tasks", "gaggimate"],
    "events": ["calendar"],
    "calendar": ["calendar"],
    "solar": ["energy"],
    "sigenergy": ["energy"],
    "power": ["energy"],
    "energy": ["energy"],
    "weather": ["weather"],
    "bins": ["bins"],
    "tasks": ["recurring_tasks"],
    "recurring": ["recurring_tasks"],
    "coffee": ["gaggimate"],
    "gaggia": ["gaggimate"],
    "gaggimate": ["gaggimate"],
}


def refresh_data(scope="all"):
    targets = resolve_refresh_targets(scope)
    results = {}

    for target in targets:
        job = REFRESH_JOBS[target]

        try:
            results[target] = {
                "status": "ok",
                "result": job(),
            }
        except Exception as exc:
            results[target] = {
                "status": "error",
                "error": str(exc),
            }

    ok_count = sum(1 for result in results.values() if result["status"] == "ok")

    return {
        "scope": scope,
        "targets": targets,
        "ok": ok_count == len(targets),
        "ok_count": ok_count,
        "error_count": len(targets) - ok_count,
        "results": results,
    }


def resolve_refresh_targets(scope):
    normalised = (scope or "all").strip().lower().replace("-", "_")
    return REFRESH_ALIASES.get(normalised, REFRESH_ALIASES["all"])
