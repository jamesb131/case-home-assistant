from app.services.db import get_connection


def insert_raw_register(
    device_id,
    register_address,
    register_count,
    register_type,
    raw_registers,
    decoded_value=None,
    unit=None,
    label=None,
):
    conn = get_connection()

    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO sigenergy_raw_registers (
                        device_id,
                        register_address,
                        register_count,
                        register_type,
                        raw_registers,
                        decoded_value,
                        unit,
                        label
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        device_id,
                        register_address,
                        register_count,
                        register_type,
                        raw_registers,
                        decoded_value,
                        unit,
                        label,
                    ),
                )
    finally:
        conn.close()


def insert_raw_registers(readings):
    if not readings:
        return

    conn = get_connection()

    try:
        with conn:
            with conn.cursor() as cur:
                cur.executemany(
                    """
                    INSERT INTO sigenergy_raw_registers (
                        device_id,
                        register_address,
                        register_count,
                        register_type,
                        raw_registers,
                        decoded_value,
                        unit,
                        label
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    [
                        (
                            reading["device_id"],
                            reading["register_address"],
                            reading["register_count"],
                            reading["register_type"],
                            reading["raw_registers"],
                            reading.get("decoded_value"),
                            reading.get("unit"),
                            reading.get("label"),
                        )
                        for reading in readings
                    ],
                )
    finally:
        conn.close()


def get_register_changes(minutes=30, limit=40):
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    device_id,
                    register_address,
                    register_count,
                    register_type,
                    COALESCE(label, '') AS label,
                    COALESCE(unit, '') AS unit,
                    MIN(decoded_value) AS min_value,
                    MAX(decoded_value) AS max_value,
                    AVG(decoded_value) AS avg_value,
                    COUNT(*) AS sample_count,
                    MIN(captured_at) AS first_seen,
                    MAX(captured_at) AS last_seen
                FROM sigenergy_raw_registers
                WHERE captured_at >= NOW() - (%s || ' minutes')::interval
                    AND decoded_value IS NOT NULL
                GROUP BY
                    device_id,
                    register_address,
                    register_count,
                    register_type,
                    COALESCE(label, ''),
                    COALESCE(unit, '')
                HAVING COUNT(*) >= 2
                    AND MAX(decoded_value) IS DISTINCT FROM MIN(decoded_value)
                ORDER BY ABS(MAX(decoded_value) - MIN(decoded_value)) DESC
                LIMIT %s
                """,
                (minutes, limit),
            )

            return [
                {
                    "device_id": row[0],
                    "register_address": row[1],
                    "register_count": row[2],
                    "register_type": row[3],
                    "label": row[4] or None,
                    "unit": row[5] or None,
                    "min_value": float(row[6]),
                    "max_value": float(row[7]),
                    "avg_value": float(row[8]),
                    "delta": float(row[7] - row[6]),
                    "sample_count": row[9],
                    "first_seen": row[10].isoformat(),
                    "last_seen": row[11].isoformat(),
                }
                for row in cur.fetchall()
            ]
    finally:
        conn.close()
