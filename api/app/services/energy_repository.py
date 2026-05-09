from app.services.db import get_connection


ENERGY_COLUMNS = [
    "solar_kw",
    "inverter_pv_kw",
    "inverter_temp_c",

    "battery_soc",
    "battery_soh",
    "battery_kw",
    "battery_usable_kwh",
    "battery_capacity_kwh",

    "grid_kw",
    "grid_a_kw",
    "grid_b_kw",
    "grid_c_kw",
    "grid_connected",
    "grid_supplying_house",
    "grid_exporting",

    "house_load_kw",

    "ems_work_mode",
    "grid_sensor_status",
    "on_off_grid_status",
    "plant_running_state",
]


def insert_energy_reading(snapshot):
    values = [snapshot.get(column) for column in ENERGY_COLUMNS]

    columns_sql = ", ".join(ENERGY_COLUMNS)
    placeholders_sql = ", ".join(["%s"] * len(ENERGY_COLUMNS))

    conn = get_connection()

    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    f"""
                    INSERT INTO energy_readings ({columns_sql})
                    VALUES ({placeholders_sql})
                    RETURNING id, captured_at
                    """,
                    values,
                )

                row = cur.fetchone()

                return {
                    "id": row[0],
                    "captured_at": row[1].isoformat(),
                }
    finally:
        conn.close()