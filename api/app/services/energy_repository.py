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


def refresh_energy_daily_rollups(days_back=14):
    conn = get_connection()

    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    WITH readings AS (
                        SELECT
                            (captured_at AT TIME ZONE 'Australia/Perth')::date AS day,
                            captured_at,
                            solar_kw,
                            grid_kw,
                            house_load_kw,
                            battery_soc,
                            LEAD(captured_at) OVER (
                                PARTITION BY (captured_at AT TIME ZONE 'Australia/Perth')::date
                                ORDER BY captured_at
                            ) AS next_at
                        FROM energy_readings
                        WHERE captured_at >= NOW() - (%s || ' days')::interval
                    ),
                    rollups AS (
                        SELECT
                            day,
                            COALESCE(SUM(
                                GREATEST(solar_kw, 0)
                                * EXTRACT(EPOCH FROM (next_at - captured_at)) / 3600
                            ) FILTER (WHERE next_at IS NOT NULL), 0) AS solar_kwh,
                            COALESCE(SUM(
                                GREATEST(grid_kw, 0)
                                * EXTRACT(EPOCH FROM (next_at - captured_at)) / 3600
                            ) FILTER (WHERE next_at IS NOT NULL), 0) AS grid_import_kwh,
                            COALESCE(SUM(
                                GREATEST(-grid_kw, 0)
                                * EXTRACT(EPOCH FROM (next_at - captured_at)) / 3600
                            ) FILTER (WHERE next_at IS NOT NULL), 0) AS grid_export_kwh,
                            COALESCE(SUM(
                                GREATEST(house_load_kw, 0)
                                * EXTRACT(EPOCH FROM (next_at - captured_at)) / 3600
                            ) FILTER (WHERE next_at IS NOT NULL), 0) AS house_load_kwh,
                            MIN(battery_soc) AS battery_soc_min,
                            MAX(battery_soc) AS battery_soc_max,
                            COUNT(*) AS reading_count
                        FROM readings
                        GROUP BY day
                    )
                    INSERT INTO energy_daily_rollups (
                        day,
                        solar_kwh,
                        grid_import_kwh,
                        grid_export_kwh,
                        house_load_kwh,
                        battery_soc_min,
                        battery_soc_max,
                        reading_count,
                        updated_at
                    )
                    SELECT
                        day,
                        solar_kwh,
                        grid_import_kwh,
                        grid_export_kwh,
                        house_load_kwh,
                        battery_soc_min,
                        battery_soc_max,
                        reading_count,
                        NOW()
                    FROM rollups
                    ON CONFLICT (day)
                    DO UPDATE SET
                        solar_kwh = EXCLUDED.solar_kwh,
                        grid_import_kwh = EXCLUDED.grid_import_kwh,
                        grid_export_kwh = EXCLUDED.grid_export_kwh,
                        house_load_kwh = EXCLUDED.house_load_kwh,
                        battery_soc_min = EXCLUDED.battery_soc_min,
                        battery_soc_max = EXCLUDED.battery_soc_max,
                        reading_count = EXCLUDED.reading_count,
                        updated_at = EXCLUDED.updated_at
                    RETURNING day
                    """,
                    (days_back,),
                )

                return [row[0].isoformat() for row in cur.fetchall()]
    finally:
        conn.close()


def prune_energy_readings(retention_days=30):
    conn = get_connection()

    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    DELETE FROM energy_readings
                    WHERE captured_at < NOW() - (%s || ' days')::interval
                    """,
                    (retention_days,),
                )

                return cur.rowcount
    finally:
        conn.close()
