from app.repositories.zigbee_environment_repository import (
    get_latest_zigbee_environment_readings,
    get_recent_zigbee_environment_readings,
    insert_zigbee_environment_reading,
)
from app.services.zigbee_mqtt_client import (
    ZigbeeMqttUnavailable,
    get_zigbee_mqtt_config,
    read_zigbee_environment,
)


def poll_zigbee_environment():
    config = get_zigbee_mqtt_config()
    readings = []
    errors = []

    for device_name, topic_name in config["environment_devices"].items():
        try:
            snapshot = read_zigbee_environment(device_name, topic_name)
            insert_result = insert_zigbee_environment_reading(snapshot)
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
        "configured": config["environment_configured"],
        "devices": list(config["environment_devices"].keys()),
        "readings": readings,
        "errors": errors,
    }


def get_zigbee_environment_status():
    config = get_zigbee_mqtt_config()
    readings = get_latest_zigbee_environment_readings()

    return {
        "configured": config["environment_configured"],
        "devices": list(config["environment_devices"].keys()),
        "readings": readings,
    }


def get_zigbee_environment_history(device_name, hours=12, limit=180):
    return {
        "device_name": device_name,
        "hours": hours,
        "readings": get_recent_zigbee_environment_readings(
            device_name,
            hours=hours,
            limit=limit,
        ),
    }
