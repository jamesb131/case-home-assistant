import json
import os
import threading
from datetime import datetime
from urllib.parse import urlparse
from uuid import uuid4

import paho.mqtt.client as mqtt


DEFAULT_ZIGBEE_METER_DEVICES = '{"PC power plug":"PC_power_plug","Fridge":"Fridge_Power_Sensor","Washing machine":"washing_machine_power_plug"}'
DEFAULT_ZIGBEE_ENVIRONMENT_DEVICES = '{"Fridge":"Fridge_Temp_Sensor"}'
MQTT_CONNECT_ERRORS = {
    1: "unacceptable protocol version",
    2: "identifier rejected",
    3: "server unavailable",
    4: "bad username or password",
    5: "not authorised",
}


class ZigbeeMqttUnavailable(Exception):
    pass


def get_zigbee_mqtt_config():
    parsed = urlparse(os.getenv("ZIGBEE_MQTT_SERVER", "mqtt://core-mosquitto:1883"))
    devices = parse_zigbee_devices(os.getenv("ZIGBEE_METER_DEVICES", DEFAULT_ZIGBEE_METER_DEVICES))
    environment_devices = parse_zigbee_devices(
        os.getenv("ZIGBEE_ENVIRONMENT_DEVICES", DEFAULT_ZIGBEE_ENVIRONMENT_DEVICES)
    )

    return {
        "host": parsed.hostname or "core-mosquitto",
        "port": parsed.port or 1883,
        "username": os.getenv("ZIGBEE_MQTT_USERNAME", "").strip(),
        "password": os.getenv("ZIGBEE_MQTT_PASSWORD", "").strip(),
        "base_topic": os.getenv("ZIGBEE_MQTT_BASE_TOPIC", "zigbee2mqtt").strip() or "zigbee2mqtt",
        "devices": devices,
        "environment_devices": environment_devices,
        "timeout_seconds": float(os.getenv("ZIGBEE_MQTT_TIMEOUT", "5")),
        "configured": bool(devices),
        "environment_configured": bool(environment_devices),
    }


def parse_zigbee_devices(raw):
    if not raw:
        return {}

    try:
        parsed = json.loads(raw)
    except ValueError:
        return {}

    if not isinstance(parsed, dict):
        return {}

    devices = {}
    for name, topic_name in parsed.items():
        clean_name = str(name).strip()
        clean_topic = str(topic_name).strip().strip("/")
        if clean_name and clean_topic:
            devices[clean_name] = clean_topic

    return devices


def get_meter_topic(config, topic_name):
    return f"{config['base_topic'].strip('/')}/{topic_name.strip('/')}"


def create_mqtt_client(client_id):
    try:
        return mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id=client_id)
    except AttributeError:
        return mqtt.Client(client_id=client_id)


def read_zigbee_device(device_name, topic_name, normalise_payload, request_state=True):
    config = get_zigbee_mqtt_config()
    topic = get_meter_topic(config, topic_name)
    payload_event = threading.Event()
    result = {}

    client = create_mqtt_client(client_id=f"case-zigbee-read-{uuid4().hex[:10]}")
    if config["username"]:
        client.username_pw_set(config["username"], config["password"] or None)

    def on_connect(client, userdata, flags, rc):
        if rc != 0:
            reason = MQTT_CONNECT_ERRORS.get(rc, "unknown error")
            hint = ""
            if rc in {4, 5}:
                hint = " Check zigbee_mqtt_username and zigbee_mqtt_password in CASE Core settings."
            result["error"] = f"MQTT connection failed with code {rc} ({reason}).{hint}"
            payload_event.set()
            return
        client.subscribe(topic)
        if request_state:
            client.publish(f"{topic}/get", json.dumps({"state": ""}), qos=0, retain=False)

    def on_message(client, userdata, message):
        try:
            payload = json.loads(message.payload.decode("utf-8"))
        except ValueError as exc:
            result["error"] = f"Invalid MQTT JSON payload: {exc}"
            payload_event.set()
            return

        result["payload"] = payload
        payload_event.set()

    client.on_connect = on_connect
    client.on_message = on_message

    try:
        client.connect(config["host"], config["port"], keepalive=15)
    except OSError as exc:
        raise ZigbeeMqttUnavailable(str(exc)) from exc

    client.loop_start()
    try:
        if not payload_event.wait(config["timeout_seconds"]):
            raise ZigbeeMqttUnavailable(f"No MQTT state received for {topic}.")
    finally:
        client.loop_stop()
        client.disconnect()

    if result.get("error"):
        raise ZigbeeMqttUnavailable(result["error"])

    return normalise_payload(device_name, topic, result.get("payload") or {})


def read_zigbee_meter(device_name, topic_name):
    return read_zigbee_device(device_name, topic_name, normalise_meter_payload)


def read_zigbee_environment(device_name, topic_name):
    return read_zigbee_device(
        device_name,
        topic_name,
        normalise_environment_payload,
        request_state=False,
    )


def publish_zigbee_meter_state(device_name, topic_name, state):
    config = get_zigbee_mqtt_config()
    topic = get_meter_topic(config, topic_name)
    set_topic = f"{topic}/set"
    payload = {"state": state.upper()}

    client = create_mqtt_client(client_id=f"case-zigbee-command-{uuid4().hex[:10]}")
    if config["username"]:
        client.username_pw_set(config["username"], config["password"] or None)

    try:
        client.connect(config["host"], config["port"], keepalive=15)
        client.loop_start()
        info = client.publish(set_topic, json.dumps(payload), qos=0, retain=False)
        info.wait_for_publish(timeout=5)
    except OSError as exc:
        raise ZigbeeMqttUnavailable(str(exc)) from exc
    finally:
        client.loop_stop()
        client.disconnect()

    return {
        "ok": True,
        "device_name": device_name,
        "topic": set_topic,
        "payload": payload,
    }


def normalise_meter_payload(device_name, topic, payload):
    payload_at = parse_payload_time(payload.get("last_seen"))

    return {
        "device_name": device_name,
        "topic": topic,
        "payload_at": payload_at,
        "state": payload.get("state"),
        "power_w": as_float(payload.get("power")),
        "energy_kwh": as_float(payload.get("energy")),
        "voltage_v": as_float(payload.get("voltage")),
        "current_a": as_float(payload.get("current")),
        "linkquality": as_int(payload.get("linkquality")),
        "raw_payload": payload,
    }


def normalise_environment_payload(device_name, topic, payload):
    payload_at = parse_payload_time(payload.get("last_seen"))

    return {
        "device_name": device_name,
        "topic": topic,
        "payload_at": payload_at,
        "temperature_c": as_float(payload.get("temperature")),
        "humidity_percent": as_float(payload.get("humidity")),
        "battery_percent": as_float(payload.get("battery")),
        "voltage_mv": as_float(payload.get("voltage")),
        "linkquality": as_int(payload.get("linkquality")),
        "air_quality": payload.get("air_quality") or payload.get("air_quality_index"),
        "co2_ppm": as_float(payload.get("co2")),
        "voc_index": as_float(payload.get("voc_index") or payload.get("voc")),
        "raw_payload": payload,
    }


def parse_payload_time(value):
    if not value:
        return None

    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def as_float(value):
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def as_int(value):
    try:
        return int(value) if value is not None else None
    except (TypeError, ValueError):
        return None
