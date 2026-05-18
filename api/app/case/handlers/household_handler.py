from datetime import datetime
from zoneinfo import ZoneInfo


def handle_household_intent(intent):
    category = intent.get("category")

    if category != "bins":
        return None

    perth_now = datetime.now(
        ZoneInfo("Australia/Perth")
    )

    week_number = perth_now.isocalendar().week

    if week_number % 2 == 0:
        extra_bin = "yellow recycling"
    else:
        extra_bin = "green organics"

    return {
        "reply": (
            f"This week is red general waste "
            f"plus {extra_bin}."
        ),
        "intent": "bins_read",
    }