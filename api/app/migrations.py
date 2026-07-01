from pathlib import Path

from app.db import get_connection


MIGRATIONS_DIR = Path(__file__).resolve().parent / "db" / "migrations"


def ensure_schema_migrations(cur):
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version TEXT PRIMARY KEY,
            applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
        """
    )


def get_applied_versions(cur):
    cur.execute("SELECT version FROM schema_migrations;")
    return {row[0] for row in cur.fetchall()}


def migration_files():
    return sorted(MIGRATIONS_DIR.glob("*.sql"))


def run_migrations():
    conn = get_connection()
    applied = []

    try:
        with conn:
            with conn.cursor() as cur:
                ensure_schema_migrations(cur)
                applied_versions = get_applied_versions(cur)

                for path in migration_files():
                    version = path.stem

                    if version in applied_versions:
                        continue

                    print(f"Applying migration {version}")
                    cur.execute(path.read_text())
                    cur.execute(
                        "INSERT INTO schema_migrations (version) VALUES (%s);",
                        (version,),
                    )
                    applied.append(version)

    finally:
        conn.close()

    if applied:
        print(f"Applied migrations: {', '.join(applied)}")
    else:
        print("No pending migrations.")

    return applied


def main():
    run_migrations()


if __name__ == "__main__":
    main()
