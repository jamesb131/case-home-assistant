from datetime import datetime
from zoneinfo import ZoneInfo

PERTH_TZ = ZoneInfo("Australia/Perth")


def get_decision_context():
    now = datetime.now(PERTH_TZ)
    hour = now.hour

    # Temporary V1 time bands.
    # Later, replace solar_window_start/end with sunrise/sunset-based logic.
    is_early_morning = 4 <= hour < 8
    is_morning_ramp = 8 <= hour < 10
    is_core_solar_window = 10 <= hour < 15
    is_late_solar_window = 15 <= hour < 17
    is_evening = hour >= 17 or hour < 4

    return {
        "now": now.isoformat(),
        "hour": hour,
        "is_early_morning": is_early_morning,
        "is_morning_ramp": is_morning_ramp,
        "is_core_solar_window": is_core_solar_window,
        "is_late_solar_window": is_late_solar_window,
        "is_evening": is_evening,

        # Future placeholders from weather API:
        "sunrise": None,
        "sunset": None,
        "solar_window_start": None,
        "solar_window_end": None,
        "solar_forecast_quality": None,
    }