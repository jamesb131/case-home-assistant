from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from app.db import get_connection


PERTH_TZ = ZoneInfo("Australia/Perth")


def ensure_calendar_source(
    name,
    source_type,
    external_id,
    url=None,
    config=None,
    refresh_interval_seconds=1800,
):
    conn = get_connection()

    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO calendar_sources (
                        name,
                        source_type,
                        external_id,
                        url,
                        config,
                        refresh_interval_seconds
                    )
                    VALUES (%s, %s, %s, %s, %s::jsonb, %s)
                    ON CONFLICT (source_type, external_id)
                    DO UPDATE SET
                        name = EXCLUDED.name,
                        url = EXCLUDED.url,
                        config = calendar_sources.config || EXCLUDED.config,
                        refresh_interval_seconds = EXCLUDED.refresh_interval_seconds,
                        updated_at = NOW()
                    RETURNING id;
                    """,
                    (
                        name,
                        source_type,
                        external_id,
                        url,
                        json_dumps(config or {}),
                        refresh_interval_seconds,
                    ),
                )
                source_id = cur.fetchone()[0]

    finally:
        conn.close()

    return str(source_id)


def upsert_calendar_events(source_id, events):
    now = datetime.now(PERTH_TZ)
    conn = get_connection()
    count = 0

    try:
        with conn:
            with conn.cursor() as cur:
                for event in events:
                    start_at, start_date = parse_event_start(event)
                    end_at, end_date = parse_event_end(event)

                    cur.execute(
                        """
                        INSERT INTO calendar_events (
                            source_id,
                            external_id,
                            title,
                            description,
                            location,
                            start_at,
                            end_at,
                            start_date,
                            end_date,
                            is_all_day,
                            category,
                            audience,
                            url,
                            source_payload,
                            first_seen_at,
                            last_seen_at,
                            updated_at,
                            cancelled
                        )
                        VALUES (
                            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb, %s, %s, NOW(), FALSE
                        )
                        ON CONFLICT (source_id, external_id)
                        DO UPDATE SET
                            title = EXCLUDED.title,
                            description = EXCLUDED.description,
                            location = EXCLUDED.location,
                            start_at = EXCLUDED.start_at,
                            end_at = EXCLUDED.end_at,
                            start_date = EXCLUDED.start_date,
                            end_date = EXCLUDED.end_date,
                            is_all_day = EXCLUDED.is_all_day,
                            category = EXCLUDED.category,
                            audience = EXCLUDED.audience,
                            url = EXCLUDED.url,
                            source_payload = EXCLUDED.source_payload,
                            last_seen_at = EXCLUDED.last_seen_at,
                            updated_at = NOW(),
                            cancelled = FALSE;
                        """,
                        (
                            source_id,
                            event["id"],
                            event.get("title") or "Untitled event",
                            event.get("description"),
                            event.get("location"),
                            start_at,
                            end_at,
                            start_date,
                            end_date,
                            bool(event.get("is_all_day")),
                            event.get("category"),
                            event.get("audience"),
                            event.get("url"),
                            json_dumps(event),
                            now,
                            now,
                        ),
                    )
                    count += 1

                cur.execute(
                    """
                    UPDATE calendar_sources
                    SET
                        last_synced_at = NOW(),
                        last_success_at = NOW(),
                        last_error = NULL,
                        updated_at = NOW()
                    WHERE id = %s;
                    """,
                    (source_id,),
                )

    finally:
        conn.close()

    return count


def mark_calendar_source_error(source_id, error):
    conn = get_connection()

    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE calendar_sources
                    SET
                        last_synced_at = NOW(),
                        last_error = %s,
                        updated_at = NOW()
                    WHERE id = %s;
                    """,
                    (error, source_id),
                )
    finally:
        conn.close()


def get_upcoming_calendar_events(days=30, max_results=50, start_date=None):
    start_day = start_date or datetime.now(PERTH_TZ).date()
    end_day = start_day + timedelta(days=days)
    start_at = datetime.combine(start_day, time.min, tzinfo=PERTH_TZ)
    end_at = start_at + timedelta(days=days)
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    e.id,
                    e.external_id,
                    e.title,
                    e.description,
                    e.location,
                    e.start_at,
                    e.end_at,
                    e.start_date,
                    e.end_date,
                    e.is_all_day,
                    e.category,
                    e.audience,
                    e.url,
                    e.last_seen_at,
                    s.id,
                    s.name,
                    s.source_type,
                    s.external_id,
                    s.last_error
                FROM calendar_events e
                JOIN calendar_sources s ON s.id = e.source_id
                WHERE
                    e.cancelled = FALSE
                    AND s.enabled = TRUE
                    AND (
                        (e.is_all_day = TRUE AND e.start_date >= %s AND e.start_date < %s)
                        OR
                        (e.is_all_day = FALSE AND e.start_at >= %s AND e.start_at < %s)
                    )
                ORDER BY COALESCE(e.start_at, e.start_date::timestamptz), e.title
                LIMIT %s;
                """,
                (start_day, end_day, start_at, end_at, max_results),
            )
            rows = cur.fetchall()

    finally:
        conn.close()

    return [map_event(row) for row in rows]


def get_calendar_sources():
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    id,
                    name,
                    source_type,
                    external_id,
                    url,
                    enabled,
                    refresh_interval_seconds,
                    last_synced_at,
                    last_success_at,
                    last_error,
                    updated_at
                FROM calendar_sources
                ORDER BY name;
                """
            )
            rows = cur.fetchall()

    finally:
        conn.close()

    return [map_source(row) for row in rows]


def map_event(row):
    is_all_day = bool(row[9])
    start = row[7].isoformat() if is_all_day and row[7] else serialise(row[5])
    end = row[8].isoformat() if is_all_day and row[8] else serialise(row[6])

    return {
        "id": str(row[0]),
        "external_id": row[1],
        "title": row[2],
        "description": row[3],
        "location": row[4],
        "start": start,
        "end": end,
        "is_all_day": is_all_day,
        "category": row[10],
        "audience": row[11],
        "url": row[12],
        "last_seen_at": serialise(row[13]),
        "source": {
            "id": str(row[14]),
            "name": row[15],
            "type": row[16],
            "external_id": row[17],
            "last_error": row[18],
        },
        "calendar_id": row[17],
    }


def map_source(row):
    return {
        "id": str(row[0]),
        "name": row[1],
        "source_type": row[2],
        "external_id": row[3],
        "url": row[4],
        "enabled": row[5],
        "refresh_interval_seconds": row[6],
        "last_synced_at": serialise(row[7]),
        "last_success_at": serialise(row[8]),
        "last_error": row[9],
        "updated_at": serialise(row[10]),
    }


def parse_event_start(event):
    return parse_event_time(event.get("start"), bool(event.get("is_all_day")))


def parse_event_end(event):
    return parse_event_time(event.get("end"), bool(event.get("is_all_day")))


def parse_event_time(value, is_all_day):
    if not value:
        return None, None

    if is_all_day:
        parsed_date = date.fromisoformat(value[:10])
        return None, parsed_date

    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if not parsed.tzinfo:
        parsed = parsed.replace(tzinfo=PERTH_TZ)

    return parsed, parsed.astimezone(PERTH_TZ).date()


def json_dumps(value):
    import json

    return json.dumps(value)


def serialise(value):
    if not value:
        return None

    return value.isoformat()
