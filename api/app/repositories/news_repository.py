from app.services.db import get_connection


def row_to_news_item(row):
    return {
        "id": row[0],
        "feed_name": row[1],
        "title": row[2],
        "url": row[3],
        "description": row[4],
        "published_at": row[5].isoformat() if row[5] else None,
        "summary": row[6],
        "summary_status": row[7],
        "summary_error": row[8],
        "created_at": row[9].isoformat() if row[9] else None,
        "updated_at": row[10].isoformat() if row[10] else None,
    }


def get_news_item_by_url(url):
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    id,
                    feed_name,
                    title,
                    url,
                    description,
                    published_at,
                    summary,
                    summary_status,
                    summary_error,
                    created_at,
                    updated_at
                FROM news_items
                WHERE url = %s
                """,
                (url,),
            )

            row = cur.fetchone()
            return row_to_news_item(row) if row else None
    finally:
        conn.close()


def upsert_news_item(item):
    conn = get_connection()

    summary = item.get("summary")
    summary_status = item.get("summary_status") or "pending"
    summary_error = item.get("summary_error")

    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO news_items (
                        feed_name,
                        title,
                        url,
                        description,
                        published_at,
                        summary,
                        summary_status,
                        summary_error
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (url)
                    DO UPDATE SET
                        feed_name = EXCLUDED.feed_name,
                        title = EXCLUDED.title,
                        description = EXCLUDED.description,
                        published_at = EXCLUDED.published_at,
                        summary = COALESCE(EXCLUDED.summary, news_items.summary),
                        summary_status = CASE
                            WHEN EXCLUDED.summary IS NOT NULL THEN EXCLUDED.summary_status
                            WHEN news_items.summary IS NOT NULL THEN news_items.summary_status
                            ELSE EXCLUDED.summary_status
                        END,
                        summary_error = CASE
                            WHEN EXCLUDED.summary IS NOT NULL THEN EXCLUDED.summary_error
                            WHEN news_items.summary IS NOT NULL THEN news_items.summary_error
                            ELSE EXCLUDED.summary_error
                        END,
                        updated_at = NOW()
                    RETURNING
                        id,
                        feed_name,
                        title,
                        url,
                        description,
                        published_at,
                        summary,
                        summary_status,
                        summary_error,
                        created_at,
                        updated_at
                    """,
                    (
                        item["feed_name"],
                        item["title"],
                        item["url"],
                        item.get("description"),
                        item.get("published_at"),
                        summary,
                        summary_status,
                        summary_error,
                    ),
                )

                return row_to_news_item(cur.fetchone())
    finally:
        conn.close()


def get_latest_news(limit=20):
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    id,
                    feed_name,
                    title,
                    url,
                    description,
                    published_at,
                    summary,
                    summary_status,
                    summary_error,
                    created_at,
                    updated_at
                FROM news_items
                ORDER BY published_at DESC NULLS LAST, created_at DESC
                LIMIT %s
                """,
                (limit,),
            )

            return [row_to_news_item(row) for row in cur.fetchall()]
    finally:
        conn.close()


def get_news_counts():
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    COUNT(*) AS item_count,
                    COUNT(*) FILTER (WHERE summary IS NOT NULL) AS summary_count,
                    COUNT(*) FILTER (WHERE summary_status = 'unavailable') AS unavailable_count,
                    MAX(updated_at) AS refreshed_at
                FROM news_items
                """
            )

            row = cur.fetchone()

            return {
                "item_count": row[0],
                "summary_count": row[1],
                "unavailable_count": row[2],
                "refreshed_at": row[3].isoformat() if row[3] else None,
            }
    finally:
        conn.close()
