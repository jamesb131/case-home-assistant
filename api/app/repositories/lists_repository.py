from app.db import get_connection


def get_lists():
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT id, name, list_type, is_primary, sort_order, created_at, updated_at
        FROM household_lists
        ORDER BY is_primary DESC, sort_order, name;
        """
    )

    lists = [map_list(row) for row in cur.fetchall()]

    for list_item in lists:
        cur.execute(
            """
            SELECT id, list_id, text, quantity, notes, status, sort_order, created_at, updated_at, completed_at
            FROM household_list_items
            WHERE list_id = %s
              AND status != 'completed'
            ORDER BY sort_order, created_at;
            """,
            (list_item["id"],),
        )

        list_item["items"] = [map_item(row) for row in cur.fetchall()]

    cur.close()
    conn.close()

    return lists


def create_list(name, list_type="general", is_primary=False):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        INSERT INTO household_lists (name, list_type, is_primary)
        VALUES (%s, %s, %s)
        RETURNING id;
        """,
        (name, list_type, is_primary),
    )

    list_id = cur.fetchone()[0]
    conn.commit()

    cur.close()
    conn.close()

    return get_list(list_id)


def get_list(list_id):
    lists = get_lists()
    return next((list_item for list_item in lists if list_item["id"] == str(list_id)), None)


def add_list_item(list_id, text, quantity=None, notes=None):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        INSERT INTO household_list_items (list_id, text, quantity, notes)
        VALUES (%s, %s, %s, %s)
        RETURNING id;
        """,
        (str(list_id), text, quantity, notes),
    )

    item_id = cur.fetchone()[0]
    conn.commit()

    cur.close()
    conn.close()

    return get_list_item(item_id)


def complete_list_item(item_id):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE household_list_items
        SET status = 'completed',
            completed_at = NOW(),
            updated_at = NOW()
        WHERE id = %s;
        """,
        (str(item_id),),
    )

    conn.commit()
    cur.close()
    conn.close()

    return {"completed": True, "id": str(item_id)}


def delete_list_item(item_id):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        DELETE FROM household_list_items
        WHERE id = %s;
        """,
        (str(item_id),),
    )

    conn.commit()
    cur.close()
    conn.close()

    return {"deleted": True, "id": str(item_id)}


def get_list_item(item_id):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT id, list_id, text, quantity, notes, status, sort_order, created_at, updated_at, completed_at
        FROM household_list_items
        WHERE id = %s;
        """,
        (str(item_id),),
    )

    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row:
        return None

    return map_item(row)


def map_list(row):
    return {
        "id": str(row[0]),
        "name": row[1],
        "list_type": row[2],
        "is_primary": row[3],
        "sort_order": row[4],
        "created_at": serialise(row[5]),
        "updated_at": serialise(row[6]),
        "items": [],
    }


def map_item(row):
    return {
        "id": str(row[0]),
        "list_id": str(row[1]),
        "text": row[2],
        "quantity": row[3],
        "notes": row[4],
        "status": row[5],
        "sort_order": row[6],
        "created_at": serialise(row[7]),
        "updated_at": serialise(row[8]),
        "completed_at": serialise(row[9]),
    }


def serialise(value):
    if not value:
        return None
    return value.isoformat()