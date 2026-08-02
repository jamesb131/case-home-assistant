# Zigbee MQTT Devices

CASE reads Zigbee devices directly from Zigbee2MQTT over MQTT. This keeps the
device path local-first and avoids depending on Home Assistant entities for
metering and room sensor data.

## Current Devices

Power plug:

```text
PC_power_plug
Fridge_Power_Sensor
washing_machine_power_plug
```

They currently publish on:

```text
zigbee2mqtt/PC_power_plug
zigbee2mqtt/Fridge_Power_Sensor
zigbee2mqtt/washing_machine_power_plug
```

Example payload:

```json
{
  "current": 0.3,
  "last_seen": "2026-07-31T09:47:45.611Z",
  "linkquality": 72,
  "power": 63,
  "voltage": 237,
  "energy": null,
  "state": null
}
```

Fridge power payload:

```json
{
  "child_lock": "UNLOCK",
  "countdown": 0,
  "current": 0,
  "energy": 0,
  "last_seen": "2026-08-01T00:14:52.657Z",
  "linkquality": 36,
  "power": 0,
  "state": "OFF",
  "voltage": 240
}
```

Washing machine power payload:

```json
{
  "child_lock": "UNLOCK",
  "countdown": 0,
  "current": 0.09,
  "energy": 0,
  "indicator_mode": "off/on",
  "last_seen": "2026-08-01T00:24:14.675Z",
  "linkquality": 84,
  "power": 0,
  "power_outage_memory": "off",
  "state": "ON",
  "voltage": 241
}
```

Temperature and humidity sensor:

```text
Fridge_Temp_Sensor
Living_temp_sensor
Lounge_temp_sensor
JC_bedroom_temp_sensor
```

They publish on:

```text
zigbee2mqtt/Fridge_Temp_Sensor
zigbee2mqtt/Living_temp_sensor
zigbee2mqtt/Lounge_temp_sensor
zigbee2mqtt/JC_bedroom_temp_sensor
```

Example payload:

```json
{
  "battery": 100,
  "humidity": 66.6,
  "last_seen": "2026-07-31T09:54:20.226Z",
  "linkquality": 36,
  "temperature": 23.35,
  "voltage": 2900
}
```

Room sensor payload:

```json
{
  "battery": 100,
  "humidity": 49.4,
  "last_seen": "2026-08-02T00:09:08.971Z",
  "linkquality": 88,
  "temperature": 18.07,
  "voltage": 3000
}
```

## CASE Settings

CASE Core settings:

```text
zigbee_mqtt_server=mqtt://core-mosquitto:1883
zigbee_mqtt_username=<mosquitto username>
zigbee_mqtt_password=<mosquitto password>
zigbee_mqtt_base_topic=zigbee2mqtt
zigbee_meter_devices={"PC power plug":"PC_power_plug","Fridge":"Fridge_Power_Sensor","Washing machine":"washing_machine_power_plug"}
zigbee_meter_poll_interval=30
zigbee_environment_devices={"Fridge":"Fridge_Temp_Sensor","Living":"Living_temp_sensor","Lounge":"Lounge_temp_sensor","James & Chris":"JC_bedroom_temp_sensor"}
zigbee_environment_poll_interval=60
```

`zigbee_meter_devices` is a JSON map of display names to Zigbee2MQTT friendly
names. Add future power plugs here instead of adding new code:

```json
{
  "PC power plug": "PC_power_plug",
  "Fridge": "Fridge_Power_Sensor",
  "Washing machine": "washing_machine_power_plug",
  "Hot water": "hot_water_power_plug"
}
```

`zigbee_environment_devices` is the same pattern for temperature, humidity,
battery, link quality, CO2 and air-quality sensors:

```json
{
  "Fridge": "Fridge_Temp_Sensor",
  "Living": "Living_temp_sensor",
  "Lounge": "Lounge_temp_sensor",
  "James & Chris": "JC_bedroom_temp_sensor",
  "Leo": "leo_temp_sensor"
}
```

## API

```text
GET  /iot/zigbee/meters
POST /iot/zigbee/meters/refresh
GET  /iot/zigbee/meters/{device_name}/readings
POST /iot/zigbee/meters/command
GET  /iot/zigbee/environment
POST /iot/zigbee/environment/refresh
GET  /iot/zigbee/environment/{device_name}/readings
```

Command body:

```json
{
  "device_name": "PC power plug",
  "state": "ON"
}
```

Valid states are `ON`, `OFF`, and `TOGGLE`.
