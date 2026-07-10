from app.services.db import get_connection
from psycopg2.extras import Json


def insert_gaggimate_reading(snapshot):
    values = {
        **snapshot,
        "raw_payload": Json(snapshot.get("raw_payload") or {}),
    }
    conn = get_connection()

    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO gaggimate_readings (
                        host,
                        online,
                        current_temp_c,
                        target_temp_c,
                        pressure_bar,
                        flow_ml_s,
                        target_pressure_bar,
                        mode,
                        mode_label,
                        profile_label,
                        pressure_capable,
                        dimming_capable,
                        error,
                        raw_payload
                    )
                    VALUES (
                        %(host)s,
                        %(online)s,
                        %(current_temp_c)s,
                        %(target_temp_c)s,
                        %(pressure_bar)s,
                        %(flow_ml_s)s,
                        %(target_pressure_bar)s,
                        %(mode)s,
                        %(mode_label)s,
                        %(profile_label)s,
                        %(pressure_capable)s,
                        %(dimming_capable)s,
                        %(error)s,
                        %(raw_payload)s
                    )
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


def get_recent_gaggimate_readings(limit=120):
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    id,
                    captured_at,
                    host,
                    online,
                    current_temp_c,
                    target_temp_c,
                    pressure_bar,
                    flow_ml_s,
                    target_pressure_bar,
                    mode,
                    mode_label,
                    profile_label,
                    pressure_capable,
                    dimming_capable,
                    error
                FROM gaggimate_readings
                ORDER BY captured_at DESC
                LIMIT %s
                """,
                (limit,),
            )

            return [map_reading(row) for row in cur.fetchall()]
    finally:
        conn.close()


def map_reading(row):
    return {
        "id": row[0],
        "captured_at": row[1].isoformat(),
        "host": row[2],
        "online": row[3],
        "current_temp_c": row[4],
        "target_temp_c": row[5],
        "pressure_bar": row[6],
        "flow_ml_s": row[7],
        "target_pressure_bar": row[8],
        "mode": row[9],
        "mode_label": row[10],
        "profile_label": row[11],
        "pressure_capable": row[12],
        "dimming_capable": row[13],
        "error": row[14],
    }
