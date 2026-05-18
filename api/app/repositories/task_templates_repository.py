from datetime import date, timedelta

from app.db import get_connection
from app.repositories.tasks_repository import get_task


def get_task_templates(active_only: bool = True):
    conn = get_connection()
    cur = conn.cursor()

    if active_only:
        cur.execute(
            """
            SELECT id, created_at, updated_at, title, description, assigned_to,
                   recurrence_type, day_of_week, day_of_month, start_date, end_date,
                   expires_after_days, priority, active, source, visible_day_offset,
                visible_time,
                due_day_offset,
                due_time
            FROM task_templates
            WHERE active = TRUE
            ORDER BY title;
            """
        )
    else:
        cur.execute(
            """
            SELECT id, created_at, updated_at, title, description, assigned_to,
                   recurrence_type, day_of_week, day_of_month, start_date, end_date,
                   expires_after_days, priority, active, source,visible_day_offset,
                    visible_time,
                    due_day_offset,
                    due_time
            FROM task_templates
            ORDER BY active DESC, title;
            """
        )

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return [map_template(row) for row in rows]


def create_task_template(
    title,
    description=None,
    assigned_to=None,
    recurrence_type="weekly",
    day_of_week=None,
    day_of_month=None,
    start_date=None,
    end_date=None,
    expires_after_days=None,
    priority="normal",
    visible_day_offset=0,
    visible_time=None,
    due_day_offset=0,
    due_time=None,
):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        INSERT INTO task_templates (
            title, description, assigned_to, recurrence_type,
            day_of_week, day_of_month, start_date, end_date,
            expires_after_days, priority, visible_day_offset,
            visible_time,
            due_day_offset,
            due_time
        )
        VALUES (%s, %s, %s, %s, %s, %s, COALESCE(%s, CURRENT_DATE), %s, %s, %s, %s, %s, %s, %s)
        RETURNING id;
        """,
        (
            title,
            description,
            assigned_to,
            recurrence_type,
            day_of_week,
            day_of_month,
            start_date,
            end_date,
            expires_after_days,
            priority,
            visible_day_offset,
            visible_time,
            due_day_offset,
            due_time
        ),
    )

    template_id = cur.fetchone()[0]
    conn.commit()

    cur.close()
    conn.close()

    return get_task_template(template_id)


def get_task_template(template_id):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT id, created_at, updated_at, title, description, assigned_to,
               recurrence_type, day_of_week, day_of_month, start_date, end_date,
               expires_after_days, priority, active, source,visible_day_offset,
                visible_time,
                due_day_offset,
                due_time
        FROM task_templates
        WHERE id = %s;
        """,
        (str(template_id),),
    )

    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row:
        return None

    return map_template(row)


def generate_recurring_tasks(days_ahead: int = 21):
    today = date.today()
    end = today + timedelta(days=days_ahead)

    templates = get_task_templates(active_only=True)
    created = []

    for template in templates:
        occurrence_dates = get_occurrence_dates(template, today, end)

        for occurrence_date in occurrence_dates:
            task = create_task_from_template(template, occurrence_date)

            if task:
                created.append(task)

    expire_old_generated_tasks()

    return {
        "created_count": len(created),
        "created": created,
    }


def get_occurrence_dates(template, start, end):
    recurrence_type = template["recurrence_type"]
    start_date = date.fromisoformat(template["start_date"])
    end_date = date.fromisoformat(template["end_date"]) if template["end_date"] else None

    effective_start = max(start, start_date)
    effective_end = min(end, end_date) if end_date else end

    results = []

    current = effective_start

    while current <= effective_end:
        if recurrence_type == "weekly":
            if template["day_of_week"] is not None and current.weekday() == template["day_of_week"]:
                results.append(current)

        elif recurrence_type == "fortnightly":
            if template["day_of_week"] is not None and current.weekday() == template["day_of_week"]:
                weeks_since_start = (current - start_date).days // 7
                if weeks_since_start % 2 == 0:
                    results.append(current)

        elif recurrence_type == "monthly":
            if template["day_of_month"] is not None and current.day == template["day_of_month"]:
                results.append(current)

        current += timedelta(days=1)

    return results


def create_task_from_template(template, occurrence_date):

    from datetime import datetime, time

    conn = get_connection()
    cur = conn.cursor()

    expires_at = None

    visible_at = None
    due_date = occurrence_date

    if template.get("visible_time"):
        visible_date = occurrence_date + timedelta(days=template.get("visible_day_offset") or 0)
        visible_at = datetime.combine(
            visible_date,
            time.fromisoformat(template["visible_time"])
        )

    if template.get("due_day_offset") is not None:
        due_date = occurrence_date + timedelta(days=template.get("due_day_offset") or 0)

    if template["expires_after_days"] is not None:
        expires_at = occurrence_date + timedelta(days=template["expires_after_days"])

    try:
        cur.execute(
            """
            INSERT INTO household_tasks (
                title,
                description,
                assigned_to,
                due_date,
                priority,
                source,
                recurring_template_id,
                occurrence_date,
                expires_at,
                visible_at
            )
            VALUES (%s, %s, %s, %s, %s, 'recurring', %s, %s, %s, %s)
            ON CONFLICT (recurring_template_id, occurrence_date)
            DO NOTHING
            RETURNING id;
            """,
            (
                template["title"],
                template["description"],
                template["assigned_to"],
                due_date,
                template["priority"],
                template["id"],
                occurrence_date,
                expires_at,
                visible_at
            ),
        )

        result = cur.fetchone()
        conn.commit()

        if not result:
          return None

        task_id = result[0]

    finally:
        cur.close()
        conn.close()

    return get_task(task_id)


def expire_old_generated_tasks():
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE household_tasks
        SET
            status = 'expired',
            expired_at = NOW(),
            updated_at = NOW()
        WHERE
            source = 'recurring'
            AND status = 'pending'
            AND expires_at IS NOT NULL
            AND expires_at < CURRENT_DATE;
        """
    )

    conn.commit()
    cur.close()
    conn.close()


def map_template(row):
    return {
        "id": str(row[0]),
        "created_at": serialise(row[1]),
        "updated_at": serialise(row[2]),
        "title": row[3],
        "description": row[4],
        "assigned_to": row[5],
        "recurrence_type": row[6],
        "day_of_week": row[7],
        "day_of_month": row[8],
        "start_date": serialise(row[9]),
        "end_date": serialise(row[10]),
        "expires_after_days": row[11],
        "priority": row[12],
        "active": row[13],
        "source": row[14],
        "visible_day_offset": row[15],
        "visible_time": serialise(row[16]),
        "due_day_offset": row[17],
        "due_time": serialise(row[18]),
    }


def serialise(value):
    if not value:
        return None
    return value.isoformat()