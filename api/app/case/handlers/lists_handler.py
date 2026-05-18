from app.repositories.lists_repository import (
    add_list_item,
    get_lists,
)


def normalise(text: str):
    return text.strip().lower()


def find_list_by_name(list_name: str):
    lists = get_lists()

    aliases = {
        "shopping": "groceries",
        "grocery": "groceries",
    }

    wanted = aliases.get(
        normalise(list_name),
        normalise(list_name),
    )

    for household_list in lists:
        if normalise(household_list["name"]) == wanted:
            return household_list

    return None


def handle_list_intent(intent):
    operation = intent.get("operation")

    household_list = find_list_by_name(
        intent.get("list_name") or "Groceries"
    )

    if not household_list:
        return {
            "reply": "I couldn't find that list.",
            "intent": "clarify",
        }

    if operation == "create":
        items = intent.get("items") or []

        for item in items:
            add_list_item(
                household_list["id"],
                item,
            )

        return {
            "reply": (
                f"Added {', '.join(items)} "
                f"to {household_list['name']}."
            ),
            "intent": "list_command",
            "source": "lists_handler",
        }

    if operation == "read":
        items = household_list.get("items", [])

        if not items:
            return {
                "reply": (
                    f"{household_list['name']} is empty."
                ),
                "intent": "query_lists",
            }

        item_names = [
            item["text"]
            for item in items[:8]
        ]

        return {
            "reply": (
                f"{household_list['name']} has "
                + ", ".join(item_names)
            ),
            "intent": "query_lists",
        }

    return None