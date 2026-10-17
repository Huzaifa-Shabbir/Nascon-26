"""Internal domain-event queue (Redis Streams). Not graded by script (§5.12)."""
from __future__ import annotations

import json
import logging

import redis

from app import config

log = logging.getLogger(__name__)
STREAM = "nascon:domain_events"

_redis: redis.Redis | None = None


def _client() -> redis.Redis:
    global _redis
    if _redis is None:
        _redis = redis.Redis.from_url(config.REDIS_URL, decode_responses=True)
    return _redis


def emit(event_type: str, payload: dict) -> None:
    try:
        _client().xadd(
            STREAM,
            {"event_type": event_type, "payload": json.dumps(payload, separators=(",", ":"))},
            maxlen=10_000,
            approximate=True,
        )
    except redis.RedisError:
        # Queue is best-effort for Part I; checkout must still succeed.
        log.exception("Failed to emit domain event %s", event_type)
