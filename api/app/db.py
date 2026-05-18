import os
import psycopg2


def get_connection():
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "db"),
        port=os.getenv("POSTGRES_PORT", "5432"),
        dbname=os.getenv("POSTGRES_DB", "case"),
        user=os.getenv("POSTGRES_USER", "case"),
        password=os.getenv("POSTGRES_PASSWORD", "case"),
    )
