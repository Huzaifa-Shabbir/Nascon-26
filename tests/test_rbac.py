"""RBAC matrix + P1–P7 permission boundary tests (spec §5.13)."""
import base64
import json
import time

import pytest
from fastapi.testclient import TestClient

from conftest import requires_db

pytestmark = requires_db

ROLES = ["super_admin", "league_organizer", "club_manager", "player", "viewer"]

# Expected matrix: A=200, D=403. Rows match the PDF table.
# (probe_key, path_builder) → {role: status} for the primary own/foreign cases.

CONTEXT_KEYS = [
    "tenant_id", "foreign_tenant_id", "own_league_id", "other_league_id", "foreign_league_id",
    "own_club_id", "other_club_id", "foreign_club_id",
    "own_player_id", "other_player_id", "foreign_player_id",
]


@pytest.fixture(scope="module")
def client():
    from app.main import app
    with TestClient(app) as c:
        c.post("/audit/v1/reset")
        yield c


@pytest.fixture(scope="module")
def matrix(client):
    r = client.post("/audit/v1/rbac-matrix")
    assert r.status_code == 200
    body = r.json()
    assert set(body["tokens"]) == set(ROLES)
    assert set(body["context"]) == set(CONTEXT_KEYS)
    return body


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _b64(obj: dict) -> str:
    return base64.urlsafe_b64encode(json.dumps(obj, separators=(",", ":")).encode()).rstrip(b"=").decode()


def test_rbac_matrix_tokens_are_valid_jwts(matrix):
    from app.auth import decode_token
    for role, token in matrix["tokens"].items():
        claims = decode_token(token)
        assert claims["role"] == role
        assert claims["exp"] - claims["iat"] >= 3600


def test_p1_tenants_only_super_admin(client, matrix):
    for role, token in matrix["tokens"].items():
        r = client.post("/audit/v1/rbac/tenants", headers=_auth(token), json={})
        assert r.status_code == (200 if role == "super_admin" else 403), role
        if r.status_code == 200:
            assert r.json() == {"authorized": True}
        else:
            assert r.json()["error"]["code"] == "FORBIDDEN"


@pytest.mark.parametrize("league_key, allowed_roles", [
    ("own_league_id", {"super_admin", "league_organizer"}),
    ("other_league_id", {"super_admin"}),
    ("foreign_league_id", {"super_admin"}),
])
def test_p2_league_fixtures(client, matrix, league_key, allowed_roles):
    league_id = matrix["context"][league_key]
    for role, token in matrix["tokens"].items():
        r = client.post(
            f"/audit/v1/rbac/leagues/{league_id}/fixtures",
            headers=_auth(token),
            json={},
        )
        expect = 200 if role in allowed_roles else 403
        assert r.status_code == expect, f"{role} {league_key}"
        if expect == 200:
            assert r.json() == {"authorized": True}
        else:
            assert r.json()["error"]["code"] == "FORBIDDEN"


@pytest.mark.parametrize("path_suffix", ["roster", "products"])
@pytest.mark.parametrize("club_key, allowed_roles", [
    ("own_club_id", {"super_admin", "club_manager"}),
    ("other_club_id", {"super_admin"}),
    ("foreign_club_id", {"super_admin"}),
])
def test_p3_p4_club_writes(client, matrix, path_suffix, club_key, allowed_roles):
    club_id = matrix["context"][club_key]
    for role, token in matrix["tokens"].items():
        r = client.post(
            f"/audit/v1/rbac/clubs/{club_id}/{path_suffix}",
            headers=_auth(token),
            json={},
        )
        expect = 200 if role in allowed_roles else 403
        assert r.status_code == expect, f"{role} {club_key} {path_suffix}"
        if expect == 403:
            assert r.json()["error"]["code"] == "FORBIDDEN"


@pytest.mark.parametrize("player_key, allowed_roles", [
    ("own_player_id", {"super_admin", "club_manager", "player"}),
    ("other_player_id", {"super_admin"}),
    ("foreign_player_id", {"super_admin"}),
])
def test_p5_patch_player(client, matrix, player_key, allowed_roles):
    player_id = matrix["context"][player_key]
    for role, token in matrix["tokens"].items():
        r = client.patch(
            f"/audit/v1/rbac/players/{player_id}",
            headers=_auth(token),
            json={},
        )
        expect = 200 if role in allowed_roles else 403
        assert r.status_code == expect, f"{role} {player_key}"
        if expect == 403:
            assert r.json()["error"]["code"] == "FORBIDDEN"


@pytest.mark.parametrize("club_key, allowed_roles", [
    ("own_club_id", set(ROLES)),
    ("other_club_id", set(ROLES)),
    ("foreign_club_id", {"super_admin"}),
])
def test_p6_get_club(client, matrix, club_key, allowed_roles):
    club_id = matrix["context"][club_key]
    for role, token in matrix["tokens"].items():
        r = client.get(f"/audit/v1/rbac/clubs/{club_id}", headers=_auth(token))
        expect = 200 if role in allowed_roles else 403
        assert r.status_code == expect, f"{role} {club_key}"
        if expect == 403:
            assert r.json()["error"]["code"] == "FORBIDDEN"


def test_p7_platform_config_only_super_admin(client, matrix):
    for role, token in matrix["tokens"].items():
        r = client.get("/audit/v1/rbac/platform/config", headers=_auth(token))
        assert r.status_code == (200 if role == "super_admin" else 403), role


def test_p7_missing_authorization_is_401(client):
    r = client.get("/audit/v1/rbac/platform/config")
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "UNAUTHENTICATED"


def test_malformed_bearer_header_is_401(client):
    r = client.get("/audit/v1/rbac/platform/config", headers={"Authorization": "Token abc"})
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "UNAUTHENTICATED"


def test_empty_bearer_token_is_401(client):
    r = client.get("/audit/v1/rbac/platform/config", headers={"Authorization": "Bearer "})
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "UNAUTHENTICATED"


def test_p7_alg_none_is_401(client, matrix):
    payload = {
        "sub": "user-admin",
        "role": "super_admin",
        "exp": int(time.time()) + 3600,
    }
    token = f"{_b64({'alg': 'none', 'typ': 'JWT'})}.{_b64(payload)}."
    r = client.get("/audit/v1/rbac/platform/config", headers=_auth(token))
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "UNAUTHENTICATED"


def test_p7_tampered_signature_is_401(client, matrix):
    token = matrix["tokens"]["super_admin"]
    parts = token.split(".")
    flipped = parts[2][:-1] + ("A" if not parts[2].endswith("A") else "B")
    bad = ".".join([parts[0], parts[1], flipped])
    r = client.get("/audit/v1/rbac/platform/config", headers=_auth(bad))
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "UNAUTHENTICATED"


def test_cross_tenant_club_read_is_403_not_404(client, matrix):
    """Non-super-admin foreign club → 403, never 404."""
    club_id = matrix["context"]["foreign_club_id"]
    for role in ("league_organizer", "club_manager", "player", "viewer"):
        r = client.get(
            f"/audit/v1/rbac/clubs/{club_id}",
            headers=_auth(matrix["tokens"][role]),
        )
        assert r.status_code == 403
        assert r.json()["error"]["code"] == "FORBIDDEN"


def test_login_demo_accounts(client):
    for email in (
        "admin@nascon.test",
        "organizer@nascon.test",
        "manager@nascon.test",
        "player@nascon.test",
        "viewer@nascon.test",
    ):
        r = client.post("/api/v1/auth/login", json={"email": email, "password": "Nascon@26"})
        assert r.status_code == 200, email
        body = r.json()
        assert body["token_type"] == "Bearer"
        assert body["access_token"]
        assert body["user"]["email"] == email
        # Login token must authorize a probe matching the role.
        role = body["user"]["role"]
        probe = client.get(
            "/audit/v1/rbac/platform/config",
            headers=_auth(body["access_token"]),
        )
        if role == "super_admin":
            assert probe.status_code == 200
        else:
            assert probe.status_code == 403


def test_login_bad_password_401(client):
    r = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@nascon.test", "password": "wrong"},
    )
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "UNAUTHENTICATED"


def test_login_validation_400(client):
    r = client.post("/api/v1/auth/login", json={"email": "admin@nascon.test"})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"
    assert "password" in r.json()["error"]["details"]["fields"]
