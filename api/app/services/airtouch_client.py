import asyncio
import os

from app.services.home_assistant_client import (
    HomeAssistantUnavailable,
    call_home_assistant_service,
    get_entity_state,
    get_home_assistant_config,
    parse_entity_map,
)


DEFAULT_ZONE_ENTITIES = {
    "Living": "climate.living",
    "James & Chris": "climate.james_chris",
    "Leo": "climate.leo",
    "Benny": "climate.benny",
    "Lounge": "climate.lounge",
    "Study": "climate.study",
    "Cinema": "climate.cinema",
    "Guest": "climate.guest",
}

AIRTOUCH_DIRECT_MODES = {
    "auto": "AUTO",
    "cool": "COOL",
    "heat": "HEAT",
    "dry": "DRY",
    "fan": "FAN",
    "fan_only": "FAN",
}


def get_airtouch_config():
    zones = parse_entity_map(os.getenv("AIRTOUCH_ZONE_ENTITIES", ""))
    backend = os.getenv("AIRTOUCH_BACKEND", "auto").strip().lower() or "auto"
    host = os.getenv("AIRTOUCH_HOST", "").strip()

    return {
        **get_home_assistant_config(),
        "backend": backend,
        "host": host,
        "ac_entity_id": os.getenv("AIRTOUCH_AC_ENTITY_ID", "climate.ac_0").strip(),
        "zone_entities": zones or DEFAULT_ZONE_ENTITIES,
    }


def get_airtouch_status():
    config = get_airtouch_config()

    if should_use_direct_airtouch(config):
        return get_direct_airtouch_status(config)

    return get_home_assistant_airtouch_status(config)


def should_use_direct_airtouch(config):
    backend = config.get("backend") or "auto"

    if backend == "direct":
        return True

    if backend == "home_assistant":
        return False

    return bool(config.get("host"))


def get_home_assistant_airtouch_status(config):
    if not config["configured"] or not config["ac_entity_id"]:
        return {
            "configured": False,
            "available": False,
            "backend": "home_assistant",
            "entity_id": config["ac_entity_id"],
            "state": "not_configured",
            "message": "Set HOME_ASSISTANT_URL, HOME_ASSISTANT_TOKEN and AIRTOUCH_AC_ENTITY_ID to enable AirTouch through Home Assistant.",
            "zones": [],
        }

    try:
        main_state = get_entity_state(config["ac_entity_id"])
    except HomeAssistantUnavailable as exc:
        return {
            "configured": True,
            "available": False,
            "backend": "home_assistant",
            "entity_id": config["ac_entity_id"],
            "state": "unavailable",
            "message": str(exc),
            "zones": [],
        }

    attributes = main_state.get("attributes") or {}
    zones = []

    for name, entity_id in config["zone_entities"].items():
        zones.append(read_zone_status(name, entity_id))

    raw_state = main_state.get("state") or "unknown"

    return {
        "configured": True,
        "available": raw_state not in ["unavailable", "unknown"],
        "backend": "home_assistant",
        "entity_id": config["ac_entity_id"],
        "friendly_name": attributes.get("friendly_name") or "AirTouch",
        "state": raw_state,
        "mode": raw_state,
        "target_temperature": attributes.get("temperature"),
        "current_temperature": attributes.get("current_temperature"),
        "fan_mode": attributes.get("fan_mode"),
        "hvac_modes": attributes.get("hvac_modes") or [],
        "fan_modes": attributes.get("fan_modes") or [],
        "zones": zones,
        "active_zone_count": len([zone for zone in zones if zone.get("on")]),
        "message": "AirTouch status loaded.",
    }


def get_direct_airtouch_status(config):
    if not config.get("host"):
        return {
            "configured": False,
            "available": False,
            "backend": "direct",
            "state": "not_configured",
            "message": "Set AIRTOUCH_HOST to enable direct AirTouch control.",
            "zones": [],
        }

    try:
        return run_airtouch_async(read_direct_airtouch_status(config))
    except Exception as exc:
        return {
            "configured": True,
            "available": False,
            "backend": "direct",
            "host": config.get("host"),
            "state": "unavailable",
            "message": f"Direct AirTouch connection failed: {exc}",
            "zones": [],
        }


async def read_direct_airtouch_status(config):
    async def read_status(airtouch, pyairtouch):
        aircon = first_air_conditioner(airtouch)
        zones = [format_direct_zone(zone) for zone in aircon.zones]
        power_state = enum_name(aircon.power_state)
        selected_mode = enum_name(aircon.selected_mode)
        active_mode = enum_name(aircon.active_mode)

        return {
            "configured": True,
            "available": True,
            "backend": "direct",
            "host": airtouch.host,
            "friendly_name": airtouch.name or "AirTouch",
            "state": "off" if power_state == "off" else selected_mode or active_mode or "unknown",
            "power_state": power_state,
            "mode": "off" if power_state == "off" else selected_mode or active_mode,
            "target_temperature": aircon.target_temperature,
            "current_temperature": aircon.current_temperature,
            "fan_mode": enum_name(aircon.selected_fan_speed),
            "zones": zones,
            "active_zone_count": len([zone for zone in zones if zone.get("on")]),
            "message": "AirTouch status loaded directly.",
        }

    return await with_direct_airtouch(config, read_status)


def format_direct_zone(zone):
    power_state = enum_name(zone.power_state)

    return {
        "name": zone.name,
        "available": True,
        "state": power_state or "unknown",
        "on": power_state not in ["off", "unknown", None],
        "target_temperature": zone.target_temperature,
        "current_temperature": zone.current_temperature,
        "damper": zone.current_damper_percentage,
        "control_method": enum_name(zone.control_method),
    }


def read_zone_status(name, entity_id):
    try:
        state = get_entity_state(entity_id)
    except HomeAssistantUnavailable as exc:
        return {
            "name": name,
            "entity_id": entity_id,
            "available": False,
            "state": "unavailable",
            "on": False,
            "error": str(exc),
        }

    attributes = state.get("attributes") or {}
    raw_state = state.get("state") or "unknown"

    return {
        "name": name,
        "entity_id": entity_id,
        "available": raw_state not in ["unavailable", "unknown"],
        "state": raw_state,
        "on": raw_state not in ["off", "unavailable", "unknown"],
        "target_temperature": attributes.get("temperature"),
        "current_temperature": attributes.get("current_temperature"),
        "fan_mode": attributes.get("fan_mode"),
        "control_method": attributes.get("control_method"),
    }


def run_airtouch_command(command, mode=None, zone=None):
    config = get_airtouch_config()

    if should_use_direct_airtouch(config):
        return run_direct_airtouch_command(config, command, mode=mode, zone=zone)

    return run_home_assistant_airtouch_command(command, mode=mode, zone=zone)


def run_home_assistant_airtouch_command(command, mode=None, zone=None):
    normalised = (command or "").strip().lower()

    if normalised == "set_mode":
        result = set_airtouch_mode(mode)
    elif normalised in ["turn_on", "on"]:
        result = call_airtouch_service("turn_on")
        normalised = "turn_on"
    elif normalised in ["turn_off", "off"]:
        result = call_airtouch_service("turn_off")
        normalised = "turn_off"
    elif normalised == "zone_on":
        result = set_airtouch_zone(zone, True)
    elif normalised == "zone_off":
        result = set_airtouch_zone(zone, False)
    elif normalised == "toggle_zone":
        result = toggle_airtouch_zone(zone)
    else:
        raise HomeAssistantUnavailable(
            "Unsupported AirTouch command. Use set_mode, turn_on, turn_off, zone_on, zone_off or toggle_zone."
        )

    return {
        "ok": True,
        "command": normalised,
        "mode": mode,
        "zone": zone,
        "backend": "home_assistant",
        "home_assistant_result": result,
        "status": get_airtouch_status(),
    }


def run_direct_airtouch_command(config, command, mode=None, zone=None):
    normalised = (command or "").strip().lower()

    try:
        result = run_airtouch_async(
            write_direct_airtouch_command(config, normalised, mode=mode, zone=zone)
        )
    except Exception as exc:
        raise HomeAssistantUnavailable(f"Direct AirTouch command failed: {exc}") from exc

    return {
        "ok": True,
        "command": result.get("command", normalised),
        "mode": mode,
        "zone": zone,
        "backend": "direct",
        "status": get_airtouch_status(),
    }


async def write_direct_airtouch_command(config, command, mode=None, zone=None):
    async def write_command(airtouch, pyairtouch):
        aircon = first_air_conditioner(airtouch)
        normalised_mode = (mode or "").strip().lower()

        if command == "set_mode":
            if normalised_mode == "off":
                await aircon.set_power(pyairtouch.AcPowerControl.TURN_OFF)
            else:
                enum_mode = lookup_enum(
                    pyairtouch.AcMode,
                    AIRTOUCH_DIRECT_MODES.get(normalised_mode, normalised_mode),
                    "AirTouch mode",
                )
                await aircon.set_mode(enum_mode, power_on=True)
        elif command in ["turn_on", "on"]:
            await aircon.set_power(pyairtouch.AcPowerControl.TURN_ON)
            command = "turn_on"
        elif command in ["turn_off", "off"]:
            await aircon.set_power(pyairtouch.AcPowerControl.TURN_OFF)
            command = "turn_off"
        elif command == "zone_on":
            await find_direct_zone(aircon, zone).set_power(pyairtouch.ZonePowerState.ON)
        elif command == "zone_off":
            await find_direct_zone(aircon, zone).set_power(pyairtouch.ZonePowerState.OFF)
        elif command == "toggle_zone":
            selected_zone = find_direct_zone(aircon, zone)
            selected_state = enum_name(selected_zone.power_state)
            next_state = (
                pyairtouch.ZonePowerState.ON
                if selected_state in ["off", "unknown", None]
                else pyairtouch.ZonePowerState.OFF
            )
            await selected_zone.set_power(next_state)
        else:
            raise HomeAssistantUnavailable(
                "Unsupported AirTouch command. Use set_mode, turn_on, turn_off, zone_on, zone_off or toggle_zone."
            )

        return {"command": command}

    return await with_direct_airtouch(config, write_command)


def set_airtouch_mode(mode):
    selected_mode = (mode or "").strip().lower()

    if selected_mode == "off":
        return call_airtouch_service("turn_off")

    if selected_mode not in ["cool", "heat", "fan_only", "dry", "auto"]:
        raise HomeAssistantUnavailable(
            "Unsupported AirTouch mode. Use off, cool, heat, fan_only, dry or auto."
        )

    config = get_airtouch_config()

    return call_home_assistant_service(
        "climate",
        "set_hvac_mode",
        {
            "entity_id": config["ac_entity_id"],
            "hvac_mode": selected_mode,
        },
    )


def call_airtouch_service(service):
    config = get_airtouch_config()

    if not config["ac_entity_id"]:
        raise HomeAssistantUnavailable("AIRTOUCH_AC_ENTITY_ID is not configured.")

    return call_home_assistant_service(
        "climate",
        service,
        {"entity_id": config["ac_entity_id"]},
    )


def set_airtouch_zone(zone, turn_on):
    entity_id = find_zone_entity(zone)

    return call_home_assistant_service(
        "climate",
        "turn_on" if turn_on else "turn_off",
        {"entity_id": entity_id},
    )


def toggle_airtouch_zone(zone):
    entity_id = find_zone_entity(zone)
    state = get_entity_state(entity_id)
    raw_state = state.get("state") or "unknown"

    return set_airtouch_zone(zone, raw_state in ["off", "unavailable", "unknown"])


def find_zone_entity(zone):
    zone_name = normalise_zone_name(zone)
    config = get_airtouch_config()

    for name, entity_id in config["zone_entities"].items():
        normalised_name = normalise_zone_name(name)

        if zone_name == normalised_name:
            return entity_id

    for name, entity_id in config["zone_entities"].items():
        normalised_name = normalise_zone_name(name)

        if zone_name in normalised_name or normalised_name in zone_name:
            return entity_id

    raise HomeAssistantUnavailable(f"No AirTouch zone named '{zone or ''}' is configured.")


def normalise_zone_name(value):
    return (value or "").strip().lower().replace("_", " ").replace("-", " ")


async def with_direct_airtouch(config, callback):
    try:
        import pyairtouch
    except ImportError as exc:
        raise HomeAssistantUnavailable(
            "pyairtouch is not installed. Rebuild CASE Core to enable direct AirTouch control."
        ) from exc

    discovered = await pyairtouch.discover(remote_host=config.get("host") or None)

    if not discovered:
        raise HomeAssistantUnavailable("No AirTouch controller was discovered.")

    airtouch = discovered[0]

    if not await airtouch.init():
        await airtouch.shutdown()
        raise HomeAssistantUnavailable("AirTouch initialisation failed.")

    try:
        return await callback(airtouch, pyairtouch)
    finally:
        await airtouch.shutdown()


def first_air_conditioner(airtouch):
    if not airtouch.air_conditioners:
        raise HomeAssistantUnavailable("AirTouch did not report any air conditioners.")

    return airtouch.air_conditioners[0]


def find_direct_zone(aircon, zone):
    zone_name = normalise_zone_name(zone)

    for candidate in aircon.zones:
        if normalise_zone_name(candidate.name) == zone_name:
            return candidate

    for candidate in aircon.zones:
        candidate_name = normalise_zone_name(candidate.name)
        if zone_name in candidate_name or candidate_name in zone_name:
            return candidate

    raise HomeAssistantUnavailable(f"No AirTouch zone named '{zone or ''}' was found.")


def lookup_enum(enum_class, value, label):
    enum_name_value = (value or "").strip().upper()

    try:
        return enum_class[enum_name_value]
    except KeyError as exc:
        raise HomeAssistantUnavailable(f"Unsupported {label}: {value}") from exc


def enum_name(value):
    if value is None:
        return None

    return value.name.lower()


def run_airtouch_async(coro):
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return asyncio.run(coro)

    raise HomeAssistantUnavailable("Direct AirTouch calls cannot run inside an active event loop.")
