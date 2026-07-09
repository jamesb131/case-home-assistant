PAGE_ALIASES = {
    "home": "Home",
    "dashboard": "Home",
    "main": "Home",
    "planner": "Planner",
    "calendar": "Planner",
    "events": "Planner",
    "kids": "Kids",
    "boys": "Kids",
    "children": "Kids",
    "lists": "Lists",
    "list": "Lists",
    "shopping": "Lists",
    "groceries": "Lists",
    "grocery": "Lists",
    "energy": "Home",
    "solar": "Home",
    "solar production": "Home",
    "battery": "Home",
    "weather": "Home",
    "security": "Security",
}


def handle_navigation_intent(intent):
    raw_target = (
        intent.get("target_page")
        or intent.get("category")
        or intent.get("title")
        or intent.get("question")
        or intent.get("raw_message")
        or ""
    )
    page = resolve_page(raw_target)

    if not page:
        return {
            "reply": "I can take you to Home, Planner, Kids, Lists, Weather or Security.",
            "intent": "navigation_clarify",
            "confidence": intent.get("confidence", "low"),
            "source": "navigation_handler",
        }

    return {
        "reply": f"Opening {page}.",
        "intent": "navigate",
        "confidence": intent.get("confidence", "medium"),
        "source": "navigation_handler",
        "ui_action": {
            "type": "navigate",
            "page": page,
        },
    }


def resolve_page(value):
    normalised = value.lower().strip()

    for alias, page in PAGE_ALIASES.items():
        if alias in normalised:
            return page

    return None
