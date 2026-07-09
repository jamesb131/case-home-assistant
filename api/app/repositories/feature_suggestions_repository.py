from app.services.db import get_connection


def create_feature_suggestion(title, description=None, source="case_voice"):
    conn = get_connection()

    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO feature_suggestions (title, description, source)
                    VALUES (%s, %s, %s)
                    RETURNING id, created_at, updated_at, title, description, source, status;
                    """,
                    (title, description, source),
                )

                return map_suggestion(cur.fetchone())
    finally:
        conn.close()


def get_feature_suggestions(status=None, limit=25):
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            if status:
                cur.execute(
                    """
                    SELECT id, created_at, updated_at, title, description, source, status
                    FROM feature_suggestions
                    WHERE status = %s
                    ORDER BY created_at DESC
                    LIMIT %s;
                    """,
                    (status, limit),
                )
            else:
                cur.execute(
                    """
                    SELECT id, created_at, updated_at, title, description, source, status
                    FROM feature_suggestions
                    ORDER BY created_at DESC
                    LIMIT %s;
                    """,
                    (limit,),
                )

            return [map_suggestion(row) for row in cur.fetchall()]
    finally:
        conn.close()


def map_suggestion(row):
    return {
        "id": str(row[0]),
        "created_at": row[1].isoformat(),
        "updated_at": row[2].isoformat(),
        "title": row[3],
        "description": row[4],
        "source": row[5],
        "status": row[6],
    }
