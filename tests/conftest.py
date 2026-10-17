import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

# DB tests TRUNCATE everything, so they only run against an explicitly named,
# disposable database, never the DATABASE_URL from a developer's .env.
TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL")
if TEST_DATABASE_URL:
    os.environ["DATABASE_URL"] = TEST_DATABASE_URL

TEST_REDIS_URL = os.environ.get("TEST_REDIS_URL")
if TEST_REDIS_URL:
    os.environ["REDIS_URL"] = TEST_REDIS_URL

requires_db = pytest.mark.skipif(not TEST_DATABASE_URL, reason="set TEST_DATABASE_URL to run DB tests")
requires_redis = pytest.mark.skipif(not TEST_REDIS_URL, reason="set TEST_REDIS_URL to run rate-limit tests")


def pytest_configure(config):
    config.addinivalue_line("markers", "slow: tests that sleep for the real rate-limit window")