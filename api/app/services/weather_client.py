import requests
from datetime import datetime

LAT = -31.6464516
LON = 115.6868939


def get_weather_summary():
    url = "https://api.open-meteo.com/v1/forecast"

    params = {
        "latitude": LAT,
        "longitude": LON,
        "current": [
            "temperature_2m",
            "apparent_temperature",
            "cloud_cover",
            "wind_speed_10m",
            "wind_direction_10m",
        ],
        "hourly": [
            "temperature_2m",
            "cloud_cover",
            "shortwave_radiation",
            "precipitation_probability",
            "wind_speed_10m",
        ],
        "daily": [
            "temperature_2m_max",
            "temperature_2m_min",
            "precipitation_probability_max",
            "sunrise",
            "sunset",
        ],
        "forecast_days": 7,
        "timezone": "Australia/Perth",
    }

    res = requests.get(url, params=params, timeout=10)
    res.raise_for_status()

    data = res.json()

    hourly = []
    for i, time_value in enumerate(data["hourly"]["time"]):
        hourly.append({
            "time": time_value,
            "temperature": data["hourly"]["temperature_2m"][i],
            "cloudcover": data["hourly"]["cloud_cover"][i],
            "radiation": data["hourly"]["shortwave_radiation"][i],
            "precipitation_probability": data["hourly"]["precipitation_probability"][i],
            "wind_speed": data["hourly"]["wind_speed_10m"][i],
        })

    daily = []
    for i, date_value in enumerate(data["daily"]["time"]):
        day_hours = [
            h for h in hourly
            if datetime.fromisoformat(h["time"]).date() == datetime.fromisoformat(date_value).date()
        ]

        temp_profile = [
            {
                "hour": datetime.fromisoformat(h["time"]).hour,
                "temperature": h["temperature"],
                "radiation": h["radiation"],
            }
            for h in day_hours
            if datetime.fromisoformat(h["time"]).hour in [6, 9, 12, 15, 18]
        ]

        avg_wind = (
            sum(h["wind_speed"] for h in day_hours) / len(day_hours)
            if day_hours else None
        )

        daily.append({
            "date": date_value,
            "temp_max": data["daily"]["temperature_2m_max"][i],
            "temp_min": data["daily"]["temperature_2m_min"][i],
            "rain_probability": data["daily"]["precipitation_probability_max"][i],
            "sunrise": data["daily"]["sunrise"][i],
            "sunset": data["daily"]["sunset"][i],
            "temp_profile": temp_profile,
            "avg_wind": avg_wind,
        })

    today = daily[0]

    return {
        "current": data["current"],
        "today": today,
        "daily": daily,
        "hourly": hourly,
        "sunrise": today["sunrise"],
        "sunset": today["sunset"],
        "solar_bands": calculate_solar_bands(hourly, today["sunrise"], today["sunset"]),
        "daily_solar_outlook": calculate_daily_solar_outlook(hourly, daily),
    }


def calculate_solar_bands(hourly, sunrise, sunset):
    now = datetime.now()
    sunrise_dt = datetime.fromisoformat(sunrise)
    sunset_dt = datetime.fromisoformat(sunset)

    bands = {"morning": [], "midday": [], "afternoon": []}

    for h in hourly:
        t = datetime.fromisoformat(h["time"])

        if t.date() != now.date():
            continue
        if t < sunrise_dt or t > sunset_dt:
            continue
        if t < now:
            continue

        if t.hour < 11:
            bands["morning"].append(h)
        elif t.hour < 14:
            bands["midday"].append(h)
        else:
            bands["afternoon"].append(h)

    return [
        {"name": name, "quality": score_radiation(values)}
        for name, values in bands.items()
        if values
    ]


def calculate_daily_solar_outlook(hourly, daily):
    outlook = []

    for day in daily[:5]:
        day_date = datetime.fromisoformat(day["date"]).date()
        sunrise_dt = datetime.fromisoformat(day["sunrise"])
        sunset_dt = datetime.fromisoformat(day["sunset"])

        values = [
            h for h in hourly
            if datetime.fromisoformat(h["time"]).date() == day_date
            and sunrise_dt <= datetime.fromisoformat(h["time"]) <= sunset_dt
        ]

        outlook.append({
            "date": day["date"],
            "quality": score_radiation(values),
        })

    return outlook


def score_radiation(values):
    if not values:
        return "unknown"

    avg_rad = sum(v["radiation"] for v in values) / len(values)

    if avg_rad > 600:
        return "excellent"
    if avg_rad > 400:
        return "strong"
    if avg_rad > 200:
        return "moderate"
    return "low"