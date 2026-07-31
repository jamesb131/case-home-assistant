from app.services.db import get_connection
from psycopg2.extras import Json


def insert_zigbee_environment_reading(snapshot):
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
                    INSERT INTO zigbee_environment_readings (
                        device_name,
                        topic,
                        payload_at,
                        temperature_c,
                        humidity_percent,
                        battery_percent,
                        voltage_mv,
                        linkquality,
                        air_quality,
                        co2_ppm,
                        voc_index,
                        raw_payload
                    )
                    VALUES (
                        %(device_name)s,
                        %(topic)s,
                        %(payload_at)s,
                        %(temperature_c)s,
                        %(humidity_percent)s,
                        %(battery_percent)s,
                        %(voltage_mv)s,
                        %(linkquality)s,
                        %(air_quality)s,
                        %(co2_ppm)s,
                        %(voc_index)s,
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


def get_latest_zigbee_environment_readings():
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT DISTINCT ON (device_name)
                    id,
                    captured_at,
                    device_name,
                    topic,
                    payload_at,
                    temperature_c,
                    humidity_percent,
                    battery_percent,
                    voltage_mv,
                    linkquality,
                    air_quality,
                    co2_ppm,
                    voc_index,
                    raw_payload
                FROM zigbee_environment_readings
                ORDER BY device_name, captured_at DESC
                """
            )
            return [map_reading(row) for row in cur.fetchall()]
    finally:
        conn.close()


def get_recent_zigbee_environment_readings(device_name, hours=12, limit=180):
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    id,
                    captured_at,
                    device_name,
                    topic,
                    payload_at,
                    temperature_c,
                    humidity_percent,
                    battery_percent,
                    voltage_mv,
                    linkquality,
                    air_quality,
                    co2_ppm,
                    voc_index,
                    raw_payload
                FROM zigbee_environment_readings
                WHERE device_name = %s
                    AND captured_at >= now() - (%s || ' hours')::interval
                ORDER BY captured_at DESC
                LIMIT %s
                """,
                (device_name, hours, limit),
            )
            return [map_reading(row) for row in cur.fetchall()]
    finally:
        conn.close()


def map_reading(row):
    return {
        "id": row[0],
        "captured_at": row[1].isoformat(),
        "device_name": row[2],
        "topic": row[3],
        "payload_at": row[4].isoformat() if row[4] else None,
        "temperature_c": float(row[5]) if row[5] is not None else None,
        "humidity_percent": float(row[6]) if row[6] is not None else None,
        "battery_percent": float(row[7]) if row[7] is not None else None,
        "voltage_mv": float(row[8]) if row[8] is not None else None,
        "linkquality": row[9],
        "air_quality": row[10],
        "co2_ppm": float(row[11]) if row[11] is not None else None,
        "voc_index": float(row[12]) if row[12] is not None else None,
        "raw_payload": row[13] or {},
    }
