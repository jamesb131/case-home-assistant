SUPPORTED_DOMAINS = [
    "tasks",
    "lists",
    "calendar",
    "weather",
    "energy",
    "kids",
    "birthdays",
    "household",
    "time",
    "general",
]

SUPPORTED_OPERATIONS = [
    "create",
    "read",
    "update",
    "delete",
    "complete",
    "summarise",
    "clarify",
]

SUPPORTED_ENERGY_METRICS = [
    "solar_kw",
    "battery_soc",
    "battery_flow",
    "grid_import_export",
    "house_load",
    "summary",
]

SUPPORTED_CONFIDENCE = [
    "high",
    "medium",
    "low",
]

SUPPORTED_PEOPLE = [
    "James",
    "Chris",
    "Leo",
    "Benny",
]

SUPPORTED_TIMEFRAMES = [
    "today",
    "tomorrow",
    "this_week",
    "this_weekend",
    "next_week",
    "upcoming",
]

DEFAULT_INTENT = {
    "domain": "general",
    "operation": "clarify",
    "confidence": "low",
    "clarification_needed": True,
    "clarification_question": "Sorry, could you rephrase that?",
}


def validate_case_intent(intent):
    if not isinstance(intent, dict):
        return DEFAULT_INTENT.copy()

    normalised = dict(intent)

    normalise_null_strings(normalised)

    if normalised.get("domain") not in SUPPORTED_DOMAINS:
        return clarify_intent(
            normalised,
            "Sorry, I couldn't work out what part of CASE that belongs to.",
        )

    if normalised.get("operation") not in SUPPORTED_OPERATIONS:
        return clarify_intent(
            normalised,
            "Sorry, I couldn't work out what you wanted me to do.",
        )

    confidence = normalised.get("confidence")
    if confidence not in SUPPORTED_CONFIDENCE:
        normalised["confidence"] = "medium"

    if normalised.get("metric") and normalised.get("metric") not in SUPPORTED_ENERGY_METRICS:
        normalised["metric"] = None

    if normalised.get("assigned_to") not in SUPPORTED_PEOPLE:
        normalised["assigned_to"] = None

    if normalised.get("person") not in SUPPORTED_PEOPLE:
        normalised["person"] = None

    if normalised.get("timeframe") not in SUPPORTED_TIMEFRAMES:
        normalised["timeframe"] = None

    if not isinstance(normalised.get("items"), list):
        normalised["items"] = []
    else:
        normalised["items"] = [
            item.strip()
            for item in normalised["items"]
            if isinstance(item, str) and item.strip()
        ]

    for key in [
        "title",
        "list_name",
        "question",
        "location",
        "category",
        "clarification_question",
    ]:
        value = normalised.get(key)
        if value is not None and not isinstance(value, str):
            normalised[key] = None

    return normalised


def normalise_null_strings(intent):
    for key, value in list(intent.items()):
        if isinstance(value, str) and value.strip().lower() in ["", "null", "none"]:
            intent[key] = None


def clarify_intent(intent, question):
    return {
        **intent,
        "domain": "general",
        "operation": "clarify",
        "confidence": "low",
        "clarification_needed": True,
        "clarification_question": question,
    }
