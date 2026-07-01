import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.services.db import get_connection
from app.services.ollama_client import get_ollama_status

from pydantic import BaseModel
from app.services.case_assistant import ask_case

from app.services.google_calendar_client import get_upcoming_events
from app.services.google_calendar_client import get_calendar_service
from app.services.google_calendar_client import get_calendar_error

from app.routers.lists_router import router as lists_router

from app.services.sigenergy_client import get_energy_snapshot
from app.services.decision_service import get_decision_summary
from app.worker import log_energy_snapshot

from app.routers.task_templates_router import router as task_templates_router

from app.routers.tasks_router import router as tasks_router

cors_origins = [
    origin.strip()
    for origin in os.getenv("CASE_CORS_ORIGINS", "*").split(",")
    if origin.strip()
]

app = FastAPI()

app.include_router(lists_router)

app.include_router(task_templates_router)

app.include_router(tasks_router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def root():
    return {"message": "CASE is online"}

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/assistant/status")
def assistant_status():
    llm = get_ollama_status()

    return {
        "available": llm["available"],
        "voice_available": llm["available"],
        "llm": llm,
    }

@app.get("/llm/status")
def llm_status():
    return get_ollama_status()

@app.get("/energy/current")
def energy_current():
    return get_energy_snapshot()

@app.get("/decisions/summary")
def decisions_summary():
    return get_decision_summary()

@app.post("/energy/log-now")
def log_energy_now():
    logged = log_energy_snapshot()

    return {
        "logged": True,
        "result": logged["result"],
        "snapshot": logged["snapshot"],
    }

@app.get("/energy/recent")
def get_recent_energy():
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute("""
                WITH bucketed AS (
                    SELECT
                        date_bin('5 minutes', captured_at, TIMESTAMPTZ '2000-01-01') AS bucket,
                        AVG(solar_kw) AS solar_kw,
                        AVG(house_load_kw) AS house_load_kw,
                        AVG(grid_kw) AS grid_kw,
                        AVG(battery_soc) AS battery_soc,
                        MAX(house_load_kw) AS house_load_kw_max
                    FROM energy_readings
                    WHERE captured_at >= date_trunc('day', NOW() AT TIME ZONE 'Australia/Perth') AT TIME ZONE 'Australia/Perth'
                    GROUP BY bucket
                )
                SELECT
                    bucket,
                    solar_kw,
                    house_load_kw,
                    -house_load_kw AS consumption_kw,
                    grid_kw,
                    solar_kw - house_load_kw AS net_kw,
                    battery_soc,
                    house_load_kw_max
                FROM bucketed
                ORDER BY bucket ASC;
            """)

            rows = cur.fetchall()

            return [
                {
                    "time": r[0].isoformat(),
                    "solar_kw": float(r[1] or 0),
                    "house_load_kw": float(r[2] or 0),
                    "consumption_kw": float(r[3] or 0),
                    "grid_kw": float(r[4] or 0),
                    "net_kw": float(r[5] or 0),
                    "battery_soc": float(r[6] or 0),
                    "house_load_kw_max": float(r[7] or 0),
                }
                for r in rows
            ]

    finally:
        conn.close()

from app.services.weather_client import get_weather_summary

@app.get("/weather/summary")
def weather_summary():
    return get_weather_summary()

@app.get("/energy/today-summary")
def get_energy_today_summary():
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute("""
                WITH readings AS (
                    SELECT
                        captured_at,
                        grid_kw,
                        LEAD(captured_at) OVER (ORDER BY captured_at) AS next_at
                    FROM energy_readings
                    WHERE captured_at >= date_trunc('day', NOW() AT TIME ZONE 'Australia/Perth') AT TIME ZONE 'Australia/Perth'
                )
                SELECT
                    COALESCE(SUM(
                        CASE
                            WHEN grid_kw > 0 AND next_at IS NOT NULL
                            THEN grid_kw * EXTRACT(EPOCH FROM (next_at - captured_at)) / 3600
                            ELSE 0
                        END
                    ), 0) AS grid_import_kwh
                FROM readings;
            """)

            row = cur.fetchone()

            return {
                "grid_import_kwh": round(float(row[0]), 2)
            }

    finally:
        conn.close()

class CaseAskRequest(BaseModel):
    message: str

@app.post("/case/ask")
def case_ask(request: CaseAskRequest):
    return ask_case(request.message)

@app.get("/calendar/upcoming")
def calendar_upcoming():
    events = get_upcoming_events(days=30, max_results=50)

    if events is None:
        return {
            "events": [],
            "calendar_available": False,
            "error": get_calendar_error(),
        }

    return {
        "events": events,
        "calendar_available": True,
    }

@app.get("/calendar/list")
def calendar_list():
    service = get_calendar_service()

    if not service:
        return {
            "calendars": [],
            "calendar_available": False,
            "error": get_calendar_error(),
        }

    try:
        result = service.calendarList().list().execute()
    except Exception as exc:
        return {
            "calendars": [],
            "calendar_available": False,
            "error": f"Google calendar list failed: {exc}",
        }

    return {
        "calendar_available": True,
        "calendars": [
            {
                "id": calendar.get("id"),
                "summary": calendar.get("summary"),
                "primary": calendar.get("primary", False),
            }
            for calendar in result.get("items", [])
        ]
    }
