from app.repositories.zigbee_meter_repository import (
    get_latest_zigbee_meter_readings,
    get_recent_zigbee_meter_readings,
    insert_zigbee_meter_reading,
)
from app.services.zigbee_mqtt_client import (
    ZigbeeMqttUnavailable,
    get_zigbee_mqtt_config,
    publish_zigbee_meter_state,
    read_zigbee_meter,
)


def poll_zigbee_meters():
    config = get_zigbee_mqtt_config()
    readings = []
    errors = []

    for device_name, topic_name in config["devices"].items():
        try:
            snapshot = read_zigbee_meter(device_name, topic_name)
            insert_result = insert_zigbee_meter_reading(snapshot)
            readings.append(
                {
                    **snapshot,
                    "inserted": insert_result,
                }
            )
        except ZigbeeMqttUnavailable as exc:
            errors.append(
                {
                    "device_name": device_name,
                    "topic_name": topic_name,
                    "error": str(exc),
                }
            )

    return {
        "ok": not errors,
        "configured": config["configured"],
        "devices": list(config["devices"].keys()),
        "readings": readings,
        "errors": errors,
    }


def get_zigbee_meter_status():
    config = get_zigbee_mqtt_config()
    readings = get_latest_zigbee_meter_readings()

    return {
        "configured": config["configured"],
        "devices": list(config["devices"].keys()),
        "readings": readings,
    }


def get_zigbee_meter_history(device_name, limit=120):
    return {
        "device_name": device_name,
        "readings": get_recent_zigbee_meter_readings(device_name, limit=limit),
    }


def set_zigbee_meter_state(device_name, state):
    config = get_zigbee_mqtt_config()
    topic_name = config["devices"].get(device_name)

    if not topic_name:
        raise ZigbeeMqttUnavailable(f"Zigbee meter device is not configured: {device_name}")

    normalised = state.strip().upper()
    if normalised not in {"ON", "OFF", "TOGGLE"}:
        raise ZigbeeMqttUnavailable("Zigbee meter state must be ON, OFF or TOGGLE.")

    return publish_zigbee_meter_state(device_name, topic_name, normalised)
