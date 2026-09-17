import os
from urllib.parse import urljoin

import requests


class ShellyEnergyUnavailable(Exception):
    pass


def get_shelly_config():
    return {
        "host": os.getenv("SHELLY_EM_HOST", "192.168.0.4").strip(),
        "timeout": float(os.getenv("SHELLY_EM_TIMEOUT", "3")),
        "hot_water_id": int(os.getenv("SHELLY_HOT_WATER_CHANNEL", "0")),
        "oven_id": int(os.getenv("SHELLY_OVEN_CHANNEL", "1")),
    }


def read_shelly_em():
    config = get_shelly_config()
    if not config["host"]:
        return {"hot_water_kw": None, "oven_kw": None, "available": False}

    values = {}
    try:
        for channel_name, channel_id in (("hot_water_kw", config["hot_water_id"]), ("oven_kw", config["oven_id"])):
            response = requests.get(
                urljoin(f"http://{config['host']}/", f"rpc/EM1.GetStatus?id={channel_id}"),
                timeout=config["timeout"],
            )
            response.raise_for_status()
            payload = response.json()
            values[channel_name] = max(0.0, float(payload.get("act_power") or 0)) / 1000
    except (OSError, ValueError, TypeError, requests.RequestException) as exc:
        raise ShellyEnergyUnavailable(f"Shelly EM unavailable at {config['host']}: {exc}") from exc

    return {**values, "available": True, "host": config["host"]}
