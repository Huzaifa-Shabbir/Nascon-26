from sqlalchemy import create_engine, text

from app import config

engine = create_engine(config.DATABASE_URL, pool_pre_ping=True, pool_size=20, max_overflow=20)


def db_reachable() -> bool:
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False
