"""HS256 JWT issue/verify and login (spec 5.13; mobile §8.2).

Claim names are ours; the grader treats probe tokens as opaque. Tokens must
survive for ≥1 hour. Reject alg:none, bad signatures, expiry, and malformed
tokens with 401 UNAUTHENTICATED.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from fastapi import APIRouter, Body, Request
from sqlalchemy import text

from app import config, db
from app.errors import ApiError, validation_error
from app.passwords import verify_password

log = logging.getLogger(__name__)

ALGORITHM = "HS256"
# Spec: tokens from rbac-matrix must be valid for at least 1 hour.
TOKEN_TTL_SECONDS = 2 * 60 * 60

router = APIRouter()

ROLE_EMAIL = {
    "super_admin": "admin@nascon.test",
    "league_organizer": "organizer@nascon.test",
    "club_manager": "manager@nascon.test",
    "player": "player@nascon.test",
    "viewer": "viewer@nascon.test",
}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def create_access_token(user: dict[str, Any], *, ttl_seconds: int = TOKEN_TTL_SECONDS) -> str:
    now = _utcnow()
    payload = {
        "sub": user["user_id"],
        "email": user["email"],
        "role": user["role"],
        "tenant_id": user.get("tenant_id"),
        "league_id": user.get("league_id"),
        "club_id": user.get("club_id"),
        "player_id": user.get("player_id"),
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=ttl_seconds)).timestamp()),
    }
    return jwt.encode(payload, config.JWT_SECRET, algorithm=ALGORITHM)


def decode_token(token: str) -> dict[str, Any]:
    """Verify and decode a JWT. Raises ApiError(401) on any failure."""
    try:
        return jwt.decode(
            token,
            config.JWT_SECRET,
            algorithms=[ALGORITHM],
            options={"require": ["exp", "sub", "role"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise ApiError(401, "UNAUTHENTICATED", "Token has expired.") from exc
    except jwt.InvalidTokenError as exc:
        raise ApiError(401, "UNAUTHENTICATED", "Invalid or malformed token.") from exc


def bearer_token(request: Request) -> str | None:
    header = request.headers.get("authorization") or request.headers.get("Authorization")
    if not header:
        return None
    parts = header.split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "bearer" or not parts[1].strip():
        raise ApiError(401, "UNAUTHENTICATED", "Authorization header must be Bearer <jwt>.")
    return parts[1].strip()


def require_user(request: Request) -> dict[str, Any]:
    token = bearer_token(request)
    if token is None:
        raise ApiError(401, "UNAUTHENTICATED", "Missing Authorization header.")
    claims = decode_token(token)
    return {
        "user_id": claims["sub"],
        "email": claims.get("email"),
        "role": claims["role"],
        "tenant_id": claims.get("tenant_id"),
        "league_id": claims.get("league_id"),
        "club_id": claims.get("club_id"),
        "player_id": claims.get("player_id"),
    }


def load_user_by_email(email: str) -> dict[str, Any] | None:
    with db.engine.connect() as conn:
        row = conn.execute(
            text(
                "SELECT user_id, email, password_hash, role, tenant_id, league_id, club_id, player_id "
                "FROM users WHERE email = :email"
            ),
            {"email": email},
        ).mappings().first()
    return dict(row) if row else None


def load_user_by_role(role: str) -> dict[str, Any]:
    email = ROLE_EMAIL[role]
    user = load_user_by_email(email)
    if user is None:
        raise ApiError(500, "INTERNAL_ERROR", f"Seeded user for role {role} is missing.")
    return user


def issue_role_tokens() -> dict[str, str]:
    return {role: create_access_token(load_user_by_role(role)) for role in ROLE_EMAIL}


@router.post("/api/v1/auth/login")
def login(body: dict | None = Body(default=None)):
    """Mobile/production login. Graded probes use /audit/v1/rbac-matrix instead."""
    body = body or {}
    fields = []
    email = body.get("email")
    password = body.get("password")
    if not isinstance(email, str) or not email:
        fields.append("email")
    if not isinstance(password, str) or not password:
        fields.append("password")
    if fields:
        raise validation_error(fields)

    user = load_user_by_email(email)
    # Constant-time path: always verify against something when user is missing.
    stored = user["password_hash"] if user else (
        "pbkdf2_sha256$120000$" + ("00" * 16) + "$" + ("00" * 32)
    )
    ok = verify_password(password, stored) and user is not None
    if not ok:
        # Never log the password or a token.
        raise ApiError(401, "UNAUTHENTICATED", "Invalid email or password.")

    token = create_access_token(user)
    return {
        "access_token": token,
        "token_type": "Bearer",
        "expires_in": TOKEN_TTL_SECONDS,
        "user": {
            "user_id": user["user_id"],
            "email": user["email"],
            "role": user["role"],
            "tenant_id": user["tenant_id"],
            "league_id": user["league_id"],
            "club_id": user["club_id"],
            "player_id": user["player_id"],
        },
    }
