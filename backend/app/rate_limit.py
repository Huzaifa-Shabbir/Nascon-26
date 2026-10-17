"""Per-IP rate limit for /api/v1/* (spec §5.2 / §5.13).

100 requests per rolling 10-second window. Over the limit → 429 RATE_LIMITED
with a Retry-After header. /audit/v1/* and /health are exempt. Uses Redis so
the limit is shared across uvicorn workers.
"""
from __future__ import annotations

import logging
import time
import uuid

import redis
from starlette.types import ASGIApp, Receive, Scope, Send

from app import config
from app.errors import error_response

log = logging.getLogger(__name__)

WINDOW_SECONDS = 10
MAX_REQUESTS = 100
KEY_PREFIX = "rl:api:v1:"

# Atomic sliding-window check: add only when under the limit.
_LUA_SLIDING = """
local key = KEYS[1]
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])
local member = ARGV[4]
redis.call('ZREMRANGEBYSCORE', key, 0, now - window)
local count = redis.call('ZCARD', key)
if count >= limit then
  local oldest = redis.call('ZRANGE', key, 0, 0, 'WITHSCORES')
  redis.call('EXPIRE', key, window + 1)
  local retry = window
  if oldest[2] ~= nil then
    retry = math.ceil(tonumber(oldest[2]) + window - now)
    if retry < 1 then retry = 1 end
  end
  return {0, retry}
end
redis.call('ZADD', key, now, member)
redis.call('EXPIRE', key, window + 1)
return {1, 0}
"""

_redis: redis.Redis | None = None
_script = None


def get_redis() -> redis.Redis:
    global _redis, _script
    if _redis is None:
        _redis = redis.Redis.from_url(config.REDIS_URL, decode_responses=True)
        _script = _redis.register_script(_LUA_SLIDING)
    return _redis


def reset_redis_client() -> None:
    """Test helper: drop the cached client so REDIS_URL changes take effect."""
    global _redis, _script
    if _redis is not None:
        try:
            _redis.close()
        except Exception:
            pass
        _redis = None
        _script = None


def client_ip(scope: Scope) -> str:
    headers = {k.decode("latin-1").lower(): v.decode("latin-1") for k, v in scope.get("headers", [])}
    forwarded = headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip() or "unknown"
    client = scope.get("client")
    if client and client[0]:
        return client[0]
    return "unknown"


def check_rate_limit(ip: str, *, now: float | None = None) -> tuple[bool, int]:
    """Return (allowed, retry_after_seconds)."""
    now = time.time() if now is None else now
    key = KEY_PREFIX + ip
    member = f"{now}:{uuid.uuid4().hex}"
    get_redis()
    allowed, retry_after = _script(
        keys=[key],
        args=[str(now), str(WINDOW_SECONDS), str(MAX_REQUESTS), member],
    )
    return bool(int(allowed)), int(retry_after)


def clear_limits_for_ip(ip: str) -> None:
    """Test helper."""
    get_redis().delete(KEY_PREFIX + ip)


class RateLimitMiddleware:
    """ASGI middleware: enforce the /api/v1/* rolling window."""

    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        path = scope.get("path") or ""
        if not path.startswith("/api/v1/"):
            await self.app(scope, receive, send)
            return

        ip = client_ip(scope)
        try:
            allowed, retry_after = check_rate_limit(ip)
        except redis.RedisError:
            # Redis is required in compose; fail open so other graded routes stay up.
            log.exception("Rate limiter Redis error; allowing request")
            await self.app(scope, receive, send)
            return

        if allowed:
            await self.app(scope, receive, send)
            return

        response = error_response(
            429,
            "RATE_LIMITED",
            "Too many requests. Retry after the window resets.",
            headers={"Retry-After": str(retry_after)},
        )
        await response(scope, receive, send)
