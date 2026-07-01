import os
import time

from app.services.energy_repository import insert_energy_reading
from app.services.sigenergy_client import get_energy_snapshot


LOG_INTERVAL_SECONDS = int(os.getenv("LOG_INTERVAL", "30"))


def log_energy_snapshot():
    snapshot = get_energy_snapshot()
    result = insert_energy_reading(snapshot)

    return {
        "result": result,
        "snapshot": snapshot,
    }


def energy_logger_loop():
    print(f"CASE worker logging energy every {LOG_INTERVAL_SECONDS}s")

    while True:
        try:
            log_energy_snapshot()
            print("Logged energy snapshot")
        except Exception as exc:
            print(f"Energy logging error: {exc}")

        time.sleep(LOG_INTERVAL_SECONDS)


def main():
    energy_logger_loop()


if __name__ == "__main__":
    main()
