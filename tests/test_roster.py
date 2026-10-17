"""Roster setup / transfer / history (§5.11). Requires TEST_DATABASE_URL."""
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


def setup_basic(client, max_squad_size=3, req=None, live=None, extra_players=None):
    players = [
        {"player_id": "p1", "name": "Ali", "position": "gk", "squad_id": "sq-a", "role": "captain"},
        {"player_id": "p2", "name": "Bilal", "position": "df", "squad_id": "sq-a", "role": "starter"},
    ]
    if extra_players:
        players.extend(extra_players)
    body = {
        "league": {
            "league_id": "lg-r1",
            "tenant_id": "tenant-alpha",
            "sport_id": "football",
            "transfer_window": {"open": "2026-09-01", "close": "2026-09-30"},
            "max_squad_size": max_squad_size,
            "required_positions": req if req is not None else {"gk": 1},
        },
        "squads": [
            {"squad_id": "sq-a", "club_id": "club-a", "tenant_id": "tenant-alpha", "name": "A"},
            {"squad_id": "sq-b", "club_id": "club-b", "tenant_id": "tenant-alpha", "name": "B"},
        ],
        "players": players,
        "matches_in_progress": live or [],
    }
    r = client.post("/audit/v1/roster/setup", json=body)
    assert r.status_code == 201, r.text
    return r.json()


def transfer(client, **overrides):
    body = {
        "request_id": "tr-001",
        "league_id": "lg-r1",
        "player_id": "p2",
        "type": "transfer",
        "from_squad_id": "sq-a",
        "to_squad_id": "sq-b",
        "effective_date": "2026-09-30",
        "loan_end_date": None,
        "reason": "Tactical move",
        "requested_by": "user-77",
    }
    body.update(overrides)
    return client.post("/audit/v1/roster/transfer", json=body)


def test_setup_success_and_replace(client):
    body = setup_basic(client)
    assert body["league_id"] == "lg-r1"
    assert body["status"] == "configured"
    assert body["squad_counts"] == {"sq-a": 2, "sq-b": 0}
    # Replace clears prior players
    r = client.post(
        "/audit/v1/roster/setup",
        json={
            "league": {
                "league_id": "lg-r1",
                "tenant_id": "tenant-alpha",
                "sport_id": "football",
                "transfer_window": {"open": "2026-09-01", "close": "2026-09-30"},
                "max_squad_size": 5,
                "required_positions": {},
            },
            "squads": [
                {"squad_id": "sq-a", "club_id": "club-a", "tenant_id": "tenant-alpha", "name": "A"},
            ],
            "players": [
                {"player_id": "p9", "name": "X", "position": "mf", "squad_id": "sq-a", "role": "starter"},
            ],
            "matches_in_progress": [],
        },
    )
    assert r.status_code == 201
    assert r.json()["squad_counts"] == {"sq-a": 1}


def test_setup_duplicate_player_id(client):
    r = client.post(
        "/audit/v1/roster/setup",
        json={
            "league": {
                "league_id": "lg-dup",
                "tenant_id": "tenant-alpha",
                "sport_id": "football",
                "transfer_window": {"open": "2026-09-01", "close": "2026-09-30"},
            },
            "squads": [
                {"squad_id": "sq-a", "club_id": "c", "tenant_id": "tenant-alpha", "name": "A"},
            ],
            "players": [
                {"player_id": "p1", "name": "A", "position": "gk", "squad_id": "sq-a", "role": "captain"},
                {"player_id": "p1", "name": "B", "position": "df", "squad_id": "sq-a", "role": "starter"},
            ],
            "matches_in_progress": [],
        },
    )
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


def test_transfer_success(client):
    setup_basic(client)
    r = transfer(client)
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "accepted"
    assert body["state"] == "active"
    assert body["blocking_match_id"] is None
    assert body["registration"]["squad_id"] == "sq-b"
    assert body["registration"]["role"] == "substitute"
    assert body["registration"]["registration_type"] == "transfer"
    assert body["audit_entry"]["action"] == "transfer"
    assert body["audit_entry"]["who"] == "user-77"


def test_transfer_idempotent_replay(client):
    setup_basic(client)
    r1 = transfer(client)
    assert r1.status_code == 201
    r2 = transfer(client)
    assert r2.status_code == 200
    assert r2.json() == r1.json()


def test_validation_missing_fields(client):
    setup_basic(client)
    r = transfer(client, effective_date="not-a-date")
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


def test_league_player_squad_not_found(client):
    setup_basic(client)
    r = transfer(client, league_id="no-lg")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "LEAGUE_NOT_FOUND"
    r = transfer(client, player_id="no-p", request_id="tr-nf1")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "PLAYER_NOT_FOUND"
    r = transfer(client, to_squad_id="no-sq", request_id="tr-nf2")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "SQUAD_NOT_FOUND"


def test_cross_tenant(client):
    client.post(
        "/audit/v1/roster/setup",
        json={
            "league": {
                "league_id": "lg-x",
                "tenant_id": "tenant-alpha",
                "sport_id": "football",
                "transfer_window": {"open": "2026-09-01", "close": "2026-09-30"},
                "max_squad_size": 5,
                "required_positions": {},
            },
            "squads": [
                {"squad_id": "sq-a", "club_id": "c1", "tenant_id": "tenant-alpha", "name": "A"},
                {"squad_id": "sq-b", "club_id": "c2", "tenant_id": "tenant-beta", "name": "B"},
            ],
            "players": [
                {"player_id": "px", "name": "X", "position": "mf", "squad_id": "sq-a", "role": "starter"},
            ],
            "matches_in_progress": [],
        },
    )
    r = transfer(
        client, league_id="lg-x", player_id="px", from_squad_id="sq-a",
        to_squad_id="sq-b", request_id="tr-x",
    )
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "CROSS_TENANT_TRANSFER"


def test_not_in_squad(client):
    setup_basic(client)
    r = transfer(client, from_squad_id="sq-b", to_squad_id="sq-a", request_id="tr-nis")
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "NOT_IN_SQUAD"


def test_transfer_window_closed(client):
    setup_basic(client)
    r = transfer(client, effective_date="2026-10-01", request_id="tr-win")
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "TRANSFER_WINDOW_CLOSED"
    # Release allowed any date
    r2 = transfer(
        client, type="release", to_squad_id=None, effective_date="2026-12-01",
        request_id="tr-rel", loan_end_date=None,
    )
    assert r2.status_code == 201
    assert r2.json()["registration"] is None


def test_squad_full(client):
    setup_basic(
        client,
        max_squad_size=1,
        req={},
        extra_players=[
            {"player_id": "p3", "name": "C", "position": "mf", "squad_id": "sq-b", "role": "starter"},
        ],
    )
    # sq-b already has 1; max=1 → transfer of p2 fails
    r = transfer(client, request_id="tr-full")
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "SQUAD_FULL"


def test_min_position_violation(client):
    setup_basic(client, req={"gk": 1})
    r = transfer(
        client, player_id="p1", from_squad_id="sq-a", to_squad_id="sq-b",
        request_id="tr-pos",
    )
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "MIN_POSITION_VIOLATION"


def test_player_on_loan_blocks(client):
    setup_basic(client, req={})
    r = transfer(
        client, type="loan", to_squad_id="sq-b", loan_end_date="2026-10-15",
        request_id="tr-loan",
    )
    assert r.status_code == 201
    r2 = transfer(
        client, player_id="p2", from_squad_id="sq-b", to_squad_id="sq-a",
        request_id="tr-loan2", type="transfer", loan_end_date=None,
    )
    assert r2.status_code == 409
    assert r2.json()["error"]["code"] == "PLAYER_ON_LOAN"


def test_deferred_in_progress_match(client):
    setup_basic(
        client,
        req={},
        live=[{"match_id": "m-live", "home_squad_id": "sq-a", "away_squad_id": "sq-b"}],
    )
    r = transfer(client, request_id="tr-def")
    assert r.status_code == 201
    assert r.json()["state"] == "deferred_until_match_end"
    assert r.json()["blocking_match_id"] == "m-live"


def test_loan_return_in_history(client):
    setup_basic(client, req={})
    assert transfer(
        client, type="loan", to_squad_id="sq-b", loan_end_date="2026-10-15",
        request_id="tr-lr",
    ).status_code == 201

    # Before return date — still on borrower
    h = client.get("/audit/v1/roster/history/p2", params={"as_of": "2026-10-15"})
    assert h.status_code == 200
    body = h.json()
    assert body["current_squad_id"] == "sq-b"
    assert body["parent_squad_id"] == "sq-a"
    assert all(e["action"] != "loan_return" for e in body["history"])

    # Day after loan_end → automatic loan_return written once
    h2 = client.get("/audit/v1/roster/history/p2", params={"as_of": "2026-10-16"})
    assert h2.status_code == 200
    body2 = h2.json()
    assert body2["current_squad_id"] == "sq-a"
    assert body2["parent_squad_id"] is None
    actions = [e["action"] for e in body2["history"]]
    assert actions.count("loan_return") == 1
    assert body2["history"][-1]["who"] == "system"

    # Repeat does not duplicate
    h3 = client.get("/audit/v1/roster/history/p2", params={"as_of": "2026-10-16"})
    assert [e["action"] for e in h3.json()["history"]].count("loan_return") == 1


def test_history_unknown_player(client):
    r = client.get("/audit/v1/roster/history/no-such")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "PLAYER_NOT_FOUND"
