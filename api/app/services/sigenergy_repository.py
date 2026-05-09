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