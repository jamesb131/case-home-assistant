import os

from app.services.home_assistant_client import (
    HomeAssistantUnavailable,
    call_home_assistant_service,
    get_entity_state,
    get_home_assistant_config,
    parse_entity_map,
)


def get_roborock_config():
    route_entities = parse_entity_map(os.getenv("ROBOROCK_ROUTE_ENTITIES", ""))

    return {
        **get_home_assistant_config(),
        "vacuum_entity_id": os.getenv("ROBOROCK_VACUUM_ENTITY_ID", "").strip(),
        "battery_entity_id": os.getenv("ROBOROCK_BATTERY_ENTITY_ID", "").strip(),
        "route_entities": route_entities,
    }


def get_roborock_status():
    config = get_roborock_config()

    if not config["configured"] or not config["vacuum_entity_id"]:
        return {
            "configured": False,
            "available": False,
            "entity_id": config["vacuum_entity_id"],
            "state": "not_configured",
            "message": (
                "Set HOME_ASSISTANT_URL, HOME_ASSISTANT_TOKEN and "
                "ROBOROCK_VACUUM_ENTITY_ID to enable Roborock."
            ),
            "routes": sorted(config["route_entities"].keys()),
        }

    try:
        state = get_entity_state(config["vacuum_entity_id"])
    except HomeAssistantUnavailable as exc:
        return {
            "configured": True,
            "available": False,
            "entity_id": config["vacuum_entity_id"],
            "state": "unavailable",
            "message": str(exc),
            "routes": sorted(config["route_entities"].keys()),
        }

    attributes = state.get("attributes") or {}
    raw_state = state.get("state") or "unknown"
    battery = attributes.get("battery_level")

    if battery is None and config["battery_entity_id"]:
        battery = read_roborock_battery_entity(config["battery_entity_id"])

    activity = attributes.get("status") or attributes.get("state") or raw_state
    error = attributes.get("error") or attributes.get("error_code")

    return {
        "configured": True,
        "available": raw_state not in ["unavailable", "unknown"],
        "entity_id": config["vacuum_entity_id"],
        "battery_entity_id": config["battery_entity_id"],
        "friendly_name": attributes.get("friendly_name") or "Roborock",
        "state": raw_state,
        "activity": activity,
        "battery_level": battery,
        "fan_speed": attributes.get("fan_speed"),
        "error": error,
        "dock_state": infer_dock_state(raw_state, attributes),
        "cleaned_area": attributes.get("cleaned_area"),
        "cleaning_time": attributes.get("cleaning_time"),
        "cleaning_progress": attributes.get("cleaning_progress"),
        "routes": sorted(config["route_entities"].keys()),
        "message": "Roborock status loaded.",
    }


def read_roborock_battery_entity(entity_id):
    try:
        state = get_entity_state(entity_id)
    except HomeAssistantUnavailable:
        return None

    raw_value = state.get("state")

    try:
        return round(float(raw_value), 1)
    except (TypeError, ValueError):
        return None


def run_roborock_command(command, route=None):
    normalised = (command or "").strip().lower()

    if normalised == "start":
        result = call_vacuum_service("start")
    elif normalised == "pause":
        result = call_vacuum_service("pause")
    elif normalised in ["dock", "return_to_base", "return"]:
        result = call_vacuum_service("return_to_base")
        normalised = "dock"
    elif normalised == "run_route":
        result = run_roborock_route(route)
    else:
        raise HomeAssistantUnavailable(
            "Unsupported Roborock command. Use start, pause, dock or run_route."
        )

    return {
        "ok": True,
        "command": normalised,
        "route": route,
        "home_assistant_result": result,
        "status": get_roborock_status(),
    }


def call_vacuum_service(service):
    config = get_roborock_config()

    if not config["vacuum_entity_id"]:
        raise HomeAssistantUnavailable("ROBOROCK_VACUUM_ENTITY_ID is not configured.")

    return call_home_assistant_service(
        "vacuum",
        service,
        {"entity_id": config["vacuum_entity_id"]},
    )


def run_roborock_route(route):
    config = get_roborock_config()
    route_name = normalise_route_name(route)
    entity_id = find_route_entity(route_name, config["route_entities"])

    if not entity_id:
        raise HomeAssistantUnavailable(
            f"No Roborock route named '{route or ''}' is configured."
        )

    domain = entity_id.split(".", 1)[0]

    if domain == "script":
        service = "turn_on"
    elif domain == "button":
        service = "press"
    elif domain == "scene":
        service = "turn_on"
    else:
        raise HomeAssistantUnavailable(
            f"Route '{route}' uses unsupported entity type '{domain}'."
        )

    return call_home_assistant_service(domain, service, {"entity_id": entity_id})


def normalise_route_name(value):
    return (value or "").strip().lower().replace("_", " ").replace("-", " ")


def find_route_entity(route, route_entities):
    if not route:
        return None

    for name, entity_id in route_entities.items():
        if normalise_route_name(name) == route:
            return entity_id

    for name, entity_id in route_entities.items():
        normalised_name = normalise_route_name(name)
        if route in normalised_name or normalised_name in route:
            return entity_id

    return None


def infer_dock_state(state, attributes):
    lower_state = (state or "").lower()

    if lower_state in ["docked", "charging"]:
        return "docked"

    if lower_state in ["returning", "returning_to_dock"]:
        return "returning"

    if attributes.get("battery_level") == 100 and lower_state == "idle":
        return "probably_docked"

    return lower_state
