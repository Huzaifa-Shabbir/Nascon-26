"""Runtime configuration, read from environment variables only."""
import os
from pathlib import Path

from dotenv import load_dotenv

# Local dev convenience: load the repo-root .env if it exists. In Docker the
# variables come from docker-compose.yml and this is a no-op.
load_dotenv(Path(__file__).resolve().parents[2] / ".env", override=False)

DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql+psycopg://nascon:nascon@localhost:5432/nascon"
)
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")

# Required by the spec (Section 1.2). Never hard-code or commit a real value.
DAY1_SALT = os.environ.get("DAY1_SALT", "")

# Signing key for our own JWTs. Not part of the graded contract.
JWT_SECRET = os.environ.get("JWT_SECRET", "dev-only-change-me")
