#!/usr/bin/env bash
# Runs all unit tests with per-module line coverage.
# Usage: ./run_tests.sh   (needs: pip install -r backend/requirements-dev.txt)
#
# DB and Redis tests truncate data, so they only run against disposable services.
# If TEST_DATABASE_URL / TEST_REDIS_URL are not set and Docker is available, this
# script starts throwaway Postgres 16 / Redis 7 containers on free localhost ports
# and removes them on exit. Without either, those tests are skipped.
set -euo pipefail
cd "$(dirname "$0")"

PG_CID=""
REDIS_CID=""
cleanup() {
  if [ -n "$PG_CID" ]; then docker rm -f "$PG_CID" >/dev/null 2>&1 || true; fi
  if [ -n "$REDIS_CID" ]; then docker rm -f "$REDIS_CID" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

host_port() { docker port "$1" "$2" | head -n 1 | sed 's/.*://'; }

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  if [ -z "${TEST_DATABASE_URL:-}" ]; then
    PG_CID=$(docker run -d --rm -e POSTGRES_USER=t -e POSTGRES_PASSWORD=t -e POSTGRES_DB=t \
      -p 127.0.0.1::5432 postgres:16-alpine)
    # TCP readiness only succeeds once initdb has finished and the real server is up.
    for _ in $(seq 1 60); do
      docker exec "$PG_CID" pg_isready -h 127.0.0.1 -U t -d t >/dev/null 2>&1 && break
      sleep 1
    done
    export TEST_DATABASE_URL="postgresql://t:t@127.0.0.1:$(host_port "$PG_CID" 5432/tcp)/t"
  fi
  if [ -z "${TEST_REDIS_URL:-}" ]; then
    REDIS_CID=$(docker run -d --rm -p 127.0.0.1::6379 redis:7-alpine)
    for _ in $(seq 1 30); do
      docker exec "$REDIS_CID" redis-cli ping >/dev/null 2>&1 && break
      sleep 1
    done
    export TEST_REDIS_URL="redis://127.0.0.1:$(host_port "$REDIS_CID" 6379/tcp)/0"
  fi
fi

python -m pytest tests --cov=backend/app --cov-report=term-missing "$@"
