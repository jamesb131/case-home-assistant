from app.services.sigenergy_client import (
    get_energy_snapshot,
)


def handle_energy_intent(intent):
    energy = get_energy_snapshot()

    metric = intent.get("metric")

    if metric == "battery_soc":
        return {
            "reply": (
                f"The battery is at "
                f"{energy['battery_soc']:.0f} percent."
            ),
            "intent": "query_energy",
        }

    if metric == "solar_kw":
        return {
            "reply": (
                f"We're producing "
                f"{energy['solar_kw']:.2f} kilowatts "
                f"of solar."
            ),
            "intent": "query_energy",
        }

    if metric == "grid_import_export":
        grid = energy.get("grid_kw") or 0

        if grid < 0:
            return {
                "reply": (
                    f"We're exporting "
                    f"{abs(grid):.2f} kilowatts."
                ),
                "intent": "query_energy",
            }

        return {
            "reply": (
                f"We're importing "
                f"{grid:.2f} kilowatts."
            ),
            "intent": "query_energy",
        }

    return {
        "reply": (
            f"Solar is {energy['solar_kw']:.2f} "
            f"kilowatts and the battery is at "
            f"{energy['battery_soc']:.0f} percent."
        ),
        "intent": "query_energy",
    }