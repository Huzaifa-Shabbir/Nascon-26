from pathlib import Path

from sqlalchemy import create_engine, text

from app import config

engine = create_engine(config.DATABASE_URL, pool_pre_ping=True, pool_size=20, max_overflow=20)

# Advisory lock that serialises schema setup and /reset across uvicorn workers.
SCHEMA_LOCK_KEY = 261017
SCHEMA_SQL = Path(__file__).with_name("schema.sql").read_text(encoding="utf-8")


def apply_schema(conn) -> None:
    """Create missing tables. Holds the advisory lock until the caller's transaction ends."""
    conn.execute(text("SELECT pg_advisory_xact_lock(:k)"), {"k": SCHEMA_LOCK_KEY})
    for stmt in SCHEMA_SQL.split(";"):
        if stmt.strip():
            conn.execute(text(stmt))
