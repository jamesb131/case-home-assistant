import json
from datetime import date, datetime, timedelta, timezone

from psycopg2.extras import Json

from app.services.db import get_connection


def json_default(value):
    if isinstance(value, (datetime, date)):
        return value.isoformat()

    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def upsert_snapshot(key, payload, status="ok", ttl_seconds=None, error=None):
    expires_at = (
        datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds)
        if ttl_seconds
        else None
    )

    conn = get_connection()

    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO system_snapshots (
                        key,
                        captured_at,
                        expires_at,
                        status,
                        payload,
                        error
                    )
                    VALUES (%s, NOW(), %s, %s, %s, %s)
                    ON CONFLICT (key)
                    DO UPDATE SET
                        captured_at = EXCLUDED.captured_at,
                        expires_at = EXCLUDED.expires_at,
                        status = EXCLUDED.status,
                        payload = EXCLUDED.payload,
                        error = EXCLUDED.error
                    RETURNING key, captured_at, expires_at, status, payload, error
                    """,
                    (
                        key,
                        expires_at,
                        status,
                        Json(payload, dumps=lambda obj: json.dumps(obj, default=json_default)),
                        error,
                    ),
                )

                return row_to_snapshot(cur.fetchone())
    finally:
        conn.close()


def get_snapshot(key):
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT key, captured_at, expires_at, status, payload, error
                FROM system_snapshots
                WHERE key = %s
                """,
                (key,),
            )

            row = cur.fetchone()
            return row_to_snapshot(row) if row else None
    finally:
        conn.close()


def list_snapshots():
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT key, captured_at, expires_at, status, payload, error
                FROM system_snapshots
                ORDER BY key
                """
            )

            return [row_to_snapshot(row) for row in cur.fetchall()]
    finally:
        conn.close()


def record_heartbeat(service_name, status="ok", details=None):
    conn = get_connection()

    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO service_heartbeats (
                        service_name,
                        heartbeat_at,
                        status,
                        details
                    )
                    VALUES (%s, NOW(), %s, %s)
                    ON CONFLICT (service_name)
                    DO UPDATE SET
                        heartbeat_at = EXCLUDED.heartbeat_at,
                        status = EXCLUDED.status,
                        details = EXCLUDED.details
                    RETURNING service_name, heartbeat_at, status, details
                    """,
                    (
                        service_name,
                        status,
                        Json(details or {}, dumps=lambda obj: json.dumps(obj, default=json_default)),
                    ),
                )

                row = cur.fetchone()

                return {
                    "service_name": row[0],
                    "heartbeat_at": row[1].isoformat(),
                    "status": row[2],
                    "details": row[3],
                }
    finally:
        conn.close()


def get_heartbeat(service_name):
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT service_name, heartbeat_at, status, details
                FROM service_heartbeats
                WHERE service_name = %s
                """,
                (service_name,),
            )

            row = cur.fetchone()

            if not row:
                return None

            return {
                "service_name": row[0],
                "heartbeat_at": row[1].isoformat(),
                "status": row[2],
                "details": row[3],
            }
    finally:
        conn.close()


def list_heartbeats():
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT service_name, heartbeat_at, status, details
                FROM service_heartbeats
                ORDER BY service_name
                """
            )

            return [
                {
                    "service_name": row[0],
                    "heartbeat_at": row[1].isoformat(),
                    "status": row[2],
                    "details": row[3],
                }
                for row in cur.fetchall()
            ]
    finally:
        conn.close()


def row_to_snapshot(row):
    return {
        "key": row[0],
        "captured_at": row[1].isoformat(),
        "expires_at": row[2].isoformat() if row[2] else None,
        "status": row[3],
        "payload": row[4],
        "error": row[5],
    }
