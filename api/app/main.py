from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.services.db import get_connection

import threading
import time

from app.services.sigenergy_client import get_energy_snapshot
from app.services.decision_service import get_decision_summary
from app.services.energy_repository import insert_energy_reading

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # dev only
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

@app.get("/energy/current")
def energy_current():
    return get_energy_snapshot()

@app.get("/decisions/summary")
def decisions_summary():
    return get_decision_summary()

@app.post("/energy/log-now")
def log_energy_now():
    snapshot = get_energy_snapshot()
    result = insert_energy_reading(snapshot)

    return {
        "logged": True,
        "result": result,
        "snapshot": snapshot,
    }

def energy_logger_loop():
    while True:
        try:
            snapshot = get_energy_snapshot()
            insert_energy_reading(snapshot)
            print("Logged energy snapshot")
        except Exception as e:
            print(f"Logging error: {e}")

        time.sleep(5)  # every 5 seconds

@app.on_event("startup")
def start_background_logger():
    thread = threading.Thread(target=energy_logger_loop, daemon=True)
    thread.start()

@app.get("/energy/recent")
def get_recent_energy():
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    captured_at,
                    solar_kw,
                    battery_soc,
                    grid_kw,
                    house_load_kw
                FROM energy_readings
                WHERE captured_at > NOW() - INTERVAL '24 hours'
                ORDER BY captured_at ASC
            """)

            rows = cur.fetchall()

            return [
                {
                    "time": r[0].isoformat(),
                    "solar_kw": r[1],
                    "battery_soc": r[2],
                    "grid_kw": r[3],
                    "house_load_kw": r[4],
                }
                for r in rows
            ]

    finally:
        conn.close()