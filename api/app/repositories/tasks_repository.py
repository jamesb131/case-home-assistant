from datetime import datetime
from uuid import UUID

from app.db import get_connection


def get_tasks(include_completed: bool = False):
    conn = get_connection()
    cur = conn.cursor()

    if include_completed:
        cur.execute(
            """
            SELECT
                id,
                created_at,
                updated_at,
                title,
                description,
                assigned_to,
                due_date,
                status,
                priority,
                completed_at,
                source
            FROM household_tasks
            WHERE
                (
                    source != 'recurring'
                    OR visible_at <= (NOW() AT TIME ZONE 'Australia/Perth')
                )
            ORDER BY
                COALESCE(
                    due_date,
                    (NOW() AT TIME ZONE 'Australia/Perth') + INTERVAL '365 days'
                ),
                created_at;
            """
        )
    else:
        cur.execute(
            """
            SELECT
                id,
                created_at,
                updated_at,
                title,
                description,
                assigned_to,
                due_date,
                status,
                priority,
                completed_at,
                source
            FROM household_tasks
            WHERE
                status NOT IN ('completed', 'expired')
                AND (
                    source != 'recurring'
                    OR visible_at <= (NOW() AT TIME ZONE 'Australia/Perth')
                )
            ORDER BY
                COALESCE(
                    due_date,
                    (NOW() AT TIME ZONE 'Australia/Perth') + INTERVAL '365 days'
                ),
                created_at;
            """
        )

    rows = cur.fetchall()

    cur.close()
    conn.close()

    return [map_task(row) for row in rows]


def create_task(
    title: str,
    description: str = None,
    assigned_to: str = None,
    due_date: datetime = None,
    priority: str = "normal",
    source: str = "manual",
):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        INSERT INTO household_tasks (
            title,
            description,
            assigned_to,
            due_date,
            priority,
            source
        )
        VALUES (%s, %s, %s, %s, %s, %s)
        RETURNING id;
        """,
        (
            title,
            description,
            assigned_to,
            due_date,
            priority,
            source,
        ),
    )

    task_id = cur.fetchone()[0]

    conn.commit()

    cur.close()
    conn.close()

    return get_task(task_id)


def get_task(task_id):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT
            id,
            created_at,
            updated_at,
            title,
            description,
            assigned_to,
            due_date,
            status,
            priority,
            completed_at,
            source
        FROM household_tasks
        WHERE
            id = %s
            AND (
                source != 'recurring'
                OR visible_at <= (NOW() AT TIME ZONE 'Australia/Perth')
            )
        """,
        (str(task_id),),
    )

    row = cur.fetchone()

    cur.close()
    conn.close()

    if not row:
        return None

    return map_task(row)


def complete_task(task_id):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE household_tasks
        SET
            status = 'completed',
            completed_at = NOW(),
            updated_at = NOW()
        WHERE id = %s;
        """,
        (str(task_id),),
    )

    conn.commit()

    cur.close()
    conn.close()

    return get_task(task_id)


def reopen_task(task_id):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE household_tasks
        SET
            status = 'pending',
            completed_at = NULL,
            updated_at = NOW()
        WHERE id = %s;
        """,
        (str(task_id),),
    )

    conn.commit()

    cur.close()
    conn.close()

    return get_task(task_id)


def delete_task(task_id):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        DELETE FROM household_tasks
        WHERE id = %s;
        """,
        (str(task_id),),
    )

    conn.commit()

    cur.close()
    conn.close()

    return {"deleted": True, "id": str(task_id)}


def map_task(row):
    return {
        "id": str(row[0]),
        "created_at": serialise_datetime(row[1]),
        "updated_at": serialise_datetime(row[2]),
        "title": row[3],
        "description": row[4],
        "assigned_to": row[5],
        "due_date": serialise_datetime(row[6]),
        "status": row[7],
        "priority": row[8],
        "completed_at": serialise_datetime(row[9]),
        "source": row[10],
    }


def serialise_datetime(value):
    if not value:
        return None

    return value.isoformat()

def update_task(
    task_id,
    title=None,
    description=None,
    assigned_to=None,
    due_date=None,
    priority=None,
    status=None,
):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE household_tasks
        SET
            title = COALESCE(%s, title),
            description = %s,
            assigned_to = %s,
            due_date = %s,
            priority = COALESCE(%s, priority),
            status = COALESCE(%s, status),
            updated_at = NOW()
        WHERE id = %s;
        """,
        (
            title,
            description,
            assigned_to,
            due_date,
            priority,
            status,
            str(task_id),
        ),
    )

    conn.commit()

    cur.close()
    conn.close()

    return get_task(task_id)
