from app.services.db import get_connection
from psycopg2.extras import Json


def insert_zigbee_meter_reading(snapshot):
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
                    INSERT INTO zigbee_meter_readings (
                        device_name,
                        topic,
                        payload_at,
                        state,
                        power_w,
                        energy_kwh,
                        voltage_v,
                        current_a,
                        linkquality,
                        raw_payload
                    )
                    VALUES (
                        %(device_name)s,
                        %(topic)s,
                        %(payload_at)s,
                        %(state)s,
                        %(power_w)s,
                        %(energy_kwh)s,
                        %(voltage_v)s,
                        %(current_a)s,
                        %(linkquality)s,
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


def get_latest_zigbee_meter_readings():
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
                    state,
                    power_w,
                    energy_kwh,
                    voltage_v,
                    current_a,
                    linkquality,
                    raw_payload
                FROM zigbee_meter_readings
                ORDER BY device_name, captured_at DESC
                """
            )
            return [map_reading(row) for row in cur.fetchall()]
    finally:
        conn.close()


def get_recent_zigbee_meter_readings(device_name, limit=120):
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
                    state,
                    power_w,
                    energy_kwh,
                    voltage_v,
                    current_a,
                    linkquality,
                    raw_payload
                FROM zigbee_meter_readings
                WHERE device_name = %s
                ORDER BY captured_at DESC
                LIMIT %s
                """,
                (device_name, limit),
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
        "state": row[5],
        "power_w": float(row[6]) if row[6] is not None else None,
        "energy_kwh": float(row[7]) if row[7] is not None else None,
        "voltage_v": float(row[8]) if row[8] is not None else None,
        "current_a": float(row[9]) if row[9] is not None else None,
        "linkquality": row[10],
        "raw_payload": row[11] or {},
    }
