from app.services.sigenergy_client import get_energy_snapshot


def handle_energy_intent(intent):
    energy = get_energy_snapshot()

    metric = intent.get("metric") or "summary"

    solar_kw = energy.get("solar_kw") or 0
    house_load_kw = energy.get("house_load_kw") or 0
    grid_kw = energy.get("grid_kw") or 0
    battery_soc = energy.get("battery_soc") or 0
    battery_kw = energy.get("battery_kw") or 0

    exporting = grid_kw < -0.2
    importing = grid_kw > 0.2

    if metric == "battery_soc":
        return response(
            f"The battery is at {battery_soc:.0f} percent.",
            intent,
        )

    if metric == "solar_kw":
        return response(
            f"We're producing {solar_kw:.2f} kilowatts of solar.",
            intent,
        )

    if metric == "house_load":
        return response(
            f"The house is using {house_load_kw:.2f} kilowatts.",
            intent,
        )

    if metric == "battery_flow":
        if battery_kw > 0.1:
            text = f"The battery is charging at {battery_kw:.2f} kilowatts."
        elif battery_kw < -0.1:
            text = f"The battery is discharging at {abs(battery_kw):.2f} kilowatts."
        else:
            text = "The battery is basically idle."

        return response(text, intent)

    if metric == "grid_import_export":
        if exporting:
            text = f"We're exporting {abs(grid_kw):.2f} kilowatts to the grid."
        elif importing:
            text = f"We're importing {grid_kw:.2f} kilowatts from the grid."
        else:
            text = "We're basically neutral on the grid right now."

        return response(text, intent)

    return response(
        build_energy_advice(
            solar_kw=solar_kw,
            house_load_kw=house_load_kw,
            grid_kw=grid_kw,
            battery_soc=battery_soc,
            battery_kw=battery_kw,
        ),
        intent,
    )


def build_energy_advice(
    solar_kw,
    house_load_kw,
    grid_kw,
    battery_soc,
    battery_kw,
):
    exporting = grid_kw < -0.5
    importing = grid_kw > 0.5

    if exporting and battery_soc >= 80:
        return (
            f"Good time to use power. We're making {solar_kw:.2f} kilowatts, "
            f"exporting {abs(grid_kw):.2f} kilowatts, and the battery is at "
            f"{battery_soc:.0f} percent."
        )

    if exporting:
        return (
            f"Pretty good time. We're exporting {abs(grid_kw):.2f} kilowatts "
            f"and the battery is at {battery_soc:.0f} percent."
        )

    if importing and battery_soc < 35:
        return (
            f"Not ideal right now. We're importing {grid_kw:.2f} kilowatts "
            f"and the battery is only at {battery_soc:.0f} percent."
        )

    if importing:
        return (
            f"You can, but we'd be using some grid power. We're importing "
            f"{grid_kw:.2f} kilowatts and the battery is at {battery_soc:.0f} percent."
        )

    return (
        f"Looks fairly balanced. Solar is {solar_kw:.2f} kilowatts, "
        f"house load is {house_load_kw:.2f} kilowatts, and the battery is "
        f"{battery_soc:.0f} percent."
    )


def response(reply, intent):
    return {
        "reply": reply,
        "intent": "query_energy",
        "confidence": intent.get("confidence", "medium"),
        "source": "energy_handler",
    }