"""Mobile read APIs. Requires TEST_DATABASE_URL."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from conftest import requires_db

pytestmark = requires_db


@pytest.fixture(scope="module")
def client():
    from app.main import app
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def _reset(client):
    assert client.post("/audit/v1/reset").status_code == 200


def test_list_leagues(client):
    r = client.get("/api/v1/leagues")
    assert r.status_code == 200
    ids = {x["league_id"] for x in r.json()["leagues"]}
    assert "league-alpha-1" in ids


def test_club_profile(client):
    r = client.get("/api/v1/clubs/club-alpha-1")
    assert r.status_code == 200
    body = r.json()
    assert body["name"] == "Alpha United"
    assert body["tenant"]["branding"]["primary_color"] == "#0B5FFF"
    assert any(p["player_id"] == "player-alpha-1" for p in body["players"])


def test_club_not_found(client):
    r = client.get("/api/v1/clubs/nope")
    assert r.status_code == 404


def test_catalogue(client):
    r = client.get("/api/v1/catalogue", params={"tenant_id": "tenant-alpha"})
    assert r.status_code == 200
    products = r.json()["products"]
    assert products[0]["product_id"] == "prod-jersey-001"
    assert len(products[0]["variants"]) == 2


def test_matches_empty_then_populated(client):
    r = client.get("/api/v1/matches")
    assert r.status_code == 200
    assert r.json()["matches"] == []
    client.post(
        "/audit/v1/events",
        json={
            "event_id": "init-x",
            "match_id": "mx",
            "type": "match_init",
            "payload": {
                "sport_id": "football",
                "home_team_id": "t1",
                "away_team_id": "t2",
                "league_id": "league-alpha-1",
            },
        },
    )
    r2 = client.get("/api/v1/matches", params={"league_id": "league-alpha-1"})
    assert len(r2.json()["matches"]) == 1
    assert r2.json()["matches"][0]["status"] == "upcoming"
