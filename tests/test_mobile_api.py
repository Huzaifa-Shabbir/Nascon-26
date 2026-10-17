"""Mobile read APIs, including tenant isolation (FR-2.1, FR-5.1, spec 5.13). Requires TEST_DATABASE_URL."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from conftest import requires_db

pytestmark = requires_db

ROLES = ["super_admin", "league_organizer", "club_manager", "player", "viewer"]
TENANT_ROLES = ROLES[1:]
ROUTES = ["/api/v1/leagues", "/api/v1/matches", "/api/v1/catalogue", "/api/v1/clubs/club-alpha-1"]


@pytest.fixture(scope="module")
def client():
    from app.main import app
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def _reset(client):
    assert client.post("/audit/v1/reset").status_code == 200


@pytest.fixture()
def auth(client):
    tokens = client.post("/audit/v1/rbac-matrix").json()["tokens"]
    return {role: {"Authorization": f"Bearer {tok}"} for role, tok in tokens.items()}


def _init_match(client, match_id, league_id):
    r = client.post("/audit/v1/events", json={
        "event_id": f"init-{match_id}", "match_id": match_id, "type": "match_init",
        "payload": {"sport_id": "football", "home_team_id": "t1", "away_team_id": "t2", "league_id": league_id}})
    assert r.status_code == 201


def test_list_leagues(client, auth):
    r = client.get("/api/v1/leagues", headers=auth["viewer"])
    assert r.status_code == 200
    ids = {x["league_id"] for x in r.json()["leagues"]}
    assert "league-alpha-1" in ids


def test_club_profile(client, auth):
    r = client.get("/api/v1/clubs/club-alpha-1", headers=auth["viewer"])
    assert r.status_code == 200
    body = r.json()
    assert body["name"] == "Alpha United"
    assert body["tenant"]["branding"]["primary_color"] == "#0B5FFF"
    assert any(p["player_id"] == "player-alpha-1" for p in body["players"])


def test_club_not_found(client, auth):
    r = client.get("/api/v1/clubs/nope", headers=auth["viewer"])
    assert r.status_code == 404


def test_catalogue(client, auth):
    r = client.get("/api/v1/catalogue", params={"tenant_id": "tenant-alpha"}, headers=auth["viewer"])
    assert r.status_code == 200
    products = r.json()["products"]
    assert products[0]["product_id"] == "prod-jersey-001"
    assert len(products[0]["variants"]) == 2


def test_matches_empty_then_populated(client, auth):
    r = client.get("/api/v1/matches", headers=auth["viewer"])
    assert r.status_code == 200
    assert r.json()["matches"] == []
    _init_match(client, "mx", "league-alpha-1")
    r2 = client.get("/api/v1/matches", params={"league_id": "league-alpha-1"}, headers=auth["viewer"])
    assert len(r2.json()["matches"]) == 1
    assert r2.json()["matches"][0]["status"] == "upcoming"


# ---- authentication -------------------------------------------------------

@pytest.mark.parametrize("path", ROUTES)
def test_unauthenticated_is_401(client, path):
    r = client.get(path)
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "UNAUTHENTICATED"


@pytest.mark.parametrize("path", ROUTES)
def test_tampered_token_is_401(client, auth, path):
    good = auth["viewer"]["Authorization"]
    r = client.get(path, headers={"Authorization": good[:-2] + ("AA" if not good.endswith("AA") else "BB")})
    assert r.status_code == 401


def test_auth_checked_before_existence(client):
    assert client.get("/api/v1/clubs/nope").status_code == 401
    assert client.get("/api/v1/matches", params={"league_id": "nope"}).status_code == 401


# ---- same-tenant access ---------------------------------------------------

@pytest.mark.parametrize("role", TENANT_ROLES)
def test_tenant_roles_see_only_own_tenant(client, auth, role):
    _init_match(client, "m-alpha", "league-alpha-1")
    _init_match(client, "m-beta", "league-beta-1")
    h = auth[role]
    leagues = client.get("/api/v1/leagues", headers=h).json()["leagues"]
    assert {x["league_id"] for x in leagues} == {"league-alpha-1", "league-alpha-2"}
    assert {x["tenant_id"] for x in leagues} == {"tenant-alpha"}
    matches = client.get("/api/v1/matches", headers=h).json()["matches"]
    assert [m["match_id"] for m in matches] == ["m-alpha"]
    products = client.get("/api/v1/catalogue", headers=h).json()["products"]
    assert {p["tenant_id"] for p in products} == {"tenant-alpha"}
    for club in ("club-alpha-1", "club-alpha-2"):
        assert client.get(f"/api/v1/clubs/{club}", headers=h).status_code == 200


# ---- cross-tenant access --------------------------------------------------

@pytest.mark.parametrize("role", TENANT_ROLES)
def test_foreign_club_is_403_not_404(client, auth, role):
    r = client.get("/api/v1/clubs/club-beta-1", headers=auth[role])
    assert r.status_code == 403
    assert r.json()["error"]["code"] == "FORBIDDEN"


@pytest.mark.parametrize("role", TENANT_ROLES)
def test_foreign_league_matches_is_403(client, auth, role):
    _init_match(client, "m-beta", "league-beta-1")
    r = client.get("/api/v1/matches", params={"league_id": "league-beta-1"}, headers=auth[role])
    assert r.status_code == 403
    assert r.json()["error"]["code"] == "FORBIDDEN"


@pytest.mark.parametrize("role", TENANT_ROLES)
def test_foreign_catalogue_filter_is_403(client, auth, role):
    r = client.get("/api/v1/catalogue", params={"tenant_id": "tenant-beta"}, headers=auth[role])
    assert r.status_code == 403


def test_unknown_league_filter_is_404(client, auth):
    r = client.get("/api/v1/matches", params={"league_id": "nope"}, headers=auth["viewer"])
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "LEAGUE_NOT_FOUND"


def test_tenantless_audit_league_hidden_from_tenant_roles(client, auth):
    r = client.post("/audit/v1/leagues", json={
        "league_id": "lg-audit", "sport_id": "football", "teams": ["a", "b"],
        "fixtures": [{"match_id": "ma", "home": "a", "away": "b"}], "qualification": {"spots": 1}})
    assert r.status_code == 201
    viewer_leagues = {x["league_id"] for x in client.get("/api/v1/leagues", headers=auth["viewer"]).json()["leagues"]}
    assert "lg-audit" not in viewer_leagues
    assert client.get("/api/v1/matches", headers=auth["viewer"]).json()["matches"] == []
    assert client.get("/api/v1/matches", params={"league_id": "lg-audit"}, headers=auth["viewer"]).status_code == 403


# ---- super admin ----------------------------------------------------------

def test_super_admin_reads_platform_wide(client, auth):
    _init_match(client, "m-alpha", "league-alpha-1")
    _init_match(client, "m-beta", "league-beta-1")
    h = auth["super_admin"]
    leagues = {x["league_id"] for x in client.get("/api/v1/leagues", headers=h).json()["leagues"]}
    assert {"league-alpha-1", "league-alpha-2", "league-beta-1"} <= leagues
    matches = {m["match_id"] for m in client.get("/api/v1/matches", headers=h).json()["matches"]}
    assert {"m-alpha", "m-beta"} <= matches
    assert client.get("/api/v1/clubs/club-beta-1", headers=h).status_code == 200
    assert client.get("/api/v1/matches", params={"league_id": "league-beta-1"}, headers=h).status_code == 200
    beta = client.get("/api/v1/catalogue", params={"tenant_id": "tenant-beta"}, headers=h)
    assert beta.status_code == 200 and beta.json()["products"] == []
    alpha = client.get("/api/v1/catalogue", headers=h).json()["products"]
    assert [p["product_id"] for p in alpha] == ["prod-jersey-001"]
