"""JWT issue/verify unit tests (no DB). Spec §5.13 security probes."""
import base64
import json
import time

import jwt
import pytest

from app import auth, config


def _b64(obj: dict) -> str:
    return base64.urlsafe_b64encode(json.dumps(obj, separators=(",", ":")).encode()).rstrip(b"=").decode()


def _demo_user(**overrides):
    base = {
        "user_id": "user-admin",
        "email": "admin@nascon.test",
        "role": "super_admin",
        "tenant_id": None,
        "league_id": None,
        "club_id": None,
        "player_id": None,
    }
    base.update(overrides)
    return base


def test_create_and_decode_roundtrip():
    token = auth.create_access_token(_demo_user())
    claims = auth.decode_token(token)
    assert claims["sub"] == "user-admin"
    assert claims["role"] == "super_admin"
    assert claims["exp"] - claims["iat"] >= 3600


def test_algorithm_is_hs256():
    token = auth.create_access_token(_demo_user())
    header = jwt.get_unverified_header(token)
    assert header["alg"] == "HS256"


def test_alg_none_rejected():
    payload = {
        "sub": "user-admin",
        "role": "super_admin",
        "exp": int(time.time()) + 3600,
    }
    token = f"{_b64({'alg': 'none', 'typ': 'JWT'})}.{_b64(payload)}."
    with pytest.raises(Exception) as ei:
        auth.decode_token(token)
    assert ei.value.status == 401
    assert ei.value.code == "UNAUTHENTICATED"


def test_tampered_signature_rejected():
    token = auth.create_access_token(_demo_user())
    parts = token.split(".")
    sig = parts[2]
    flipped = sig[:-1] + ("A" if not sig.endswith("A") else "B")
    bad = ".".join([parts[0], parts[1], flipped])
    with pytest.raises(Exception) as ei:
        auth.decode_token(bad)
    assert ei.value.status == 401
    assert ei.value.code == "UNAUTHENTICATED"


def test_expired_token_rejected():
    token = auth.create_access_token(_demo_user(), ttl_seconds=-5)
    with pytest.raises(Exception) as ei:
        auth.decode_token(token)
    assert ei.value.status == 401
    assert ei.value.code == "UNAUTHENTICATED"


def test_wrong_secret_rejected(monkeypatch):
    token = auth.create_access_token(_demo_user())
    monkeypatch.setattr(config, "JWT_SECRET", "other-secret-not-the-same")
    with pytest.raises(Exception) as ei:
        auth.decode_token(token)
    assert ei.value.status == 401


def test_malformed_token_rejected():
    with pytest.raises(Exception) as ei:
        auth.decode_token("not.a.jwt")
    assert ei.value.status == 401
    assert ei.value.code == "UNAUTHENTICATED"
