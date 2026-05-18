from app.services.weather_client import (
    get_weather_summary,
)


def handle_weather_intent(intent):
    weather = get_weather_summary()

    timeframe = intent.get("timeframe")

    if timeframe == "tomorrow":
        return {
            "reply": (
                f"Tomorrow will be "
                f"{weather.get('tomorrow_summary', 'nice weather')}."
            ),
            "intent": "weather_read",
        }

    return {
        "reply": (
            f"Currently it's "
            f"{weather.get('summary', 'fine outside')}."
        ),
        "intent": "weather_read",
    }