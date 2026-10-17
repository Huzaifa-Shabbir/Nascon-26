"""Offline sync §5.14. Requires TEST_DATABASE_URL."""
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


def _init_match(client, match_id="m1"):
    assert client.post(
        "/audit/v1/events",
        json={
            "event_id": f"init-{match_id}",
            "match_id": match_id,
            "type": "match_init",
            "payload": {
                "sport_id": "football",
                "home_team_id": "t1",
                "away_team_id": "t2",
            },
        },
    ).status_code == 201
    assert client.post(
        "/audit/v1/events",
        json={
            "event_id": f"start-{match_id}",
            "match_id": match_id,
            "type": "match_start",
            "payload": {},
        },
    ).status_code == 201


def _setup_roster(client):
    assert client.post(
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
                {"squad_id": "sq-b", "club_id": "club-b", "tenant_id": "tenant-alpha", "name": "B"},
            ],
            "players": [
                {"player_id": "p1", "name": "Ali", "position": "gk", "squad_id": "sq-a", "role": "captain"},
                {"player_id": "p2", "name": "Bilal", "position": "df", "squad_id": "sq-a", "role": "starter"},
            ],
            "matches_in_progress": [],
        },
    ).status_code == 201


def test_envelope_validation(client):
    r = client.post("/audit/v1/offline-sync", json={"device_id": "d1", "actions": []})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


def test_score_event_applied_and_rebase(client):
    _init_match(client)
    # version after init+start = 2
    body = {
        "device_id": "dev-1",
        "actions": [
            {
                "action_id": "a1",
                "type": "score_event",
                "queued_at": "2026-10-17T11:00:00Z",
                "base_version": 2,
                "payload": {
                    "event_id": "evt-9",
                    "match_id": "m1",
                    "type": "score",
                    "payload": {"team_id": "t1", "event_type": "goal"},
                },
            }
        ],
    }
    r = client.post("/audit/v1/offline-sync", json=body)
    assert r.status_code == 200
    res = r.json()["results"][0]
    assert res["status"] == "applied"
    assert res["resolution"] == "appended"
    assert res["signature"]
    assert res["server_version"] == 3
    assert r.json()["summary"] == {"applied": 1, "rejected": 0, "duplicate": 0}

    # Stale base → rebased_append
    body2 = {
        "device_id": "dev-1",
        "actions": [
            {
                "action_id": "a2",
                "type": "score_event",
                "queued_at": "2026-10-17T11:01:00Z",
                "base_version": 2,
                "payload": {
                    "event_id": "evt-10",
                    "match_id": "m1",
                    "type": "score",
                    "payload": {"team_id": "t2", "event_type": "goal"},
                },
            }
        ],
    }
    r2 = client.post("/audit/v1/offline-sync", json=body2)
    assert r2.json()["results"][0]["resolution"] == "rebased_append"
    assert r2.json()["results"][0]["status"] == "applied"


def test_duplicate_action_and_full_replay(client):
    _init_match(client)
    body = {
        "device_id": "dev-2",
        "actions": [
            {
                "action_id": "a1",
                "type": "score_event",
                "queued_at": "2026-10-17T11:00:00Z",
                "base_version": 2,
                "payload": {
                    "event_id": "evt-dup",
                    "match_id": "m1",
                    "type": "score",
                    "payload": {"team_id": "t1", "event_type": "goal"},
                },
            }
        ],
    }
    assert client.post("/audit/v1/offline-sync", json=body).json()["results"][0]["status"] == "applied"
    again = client.post("/audit/v1/offline-sync", json=body).json()
    assert again["results"][0]["status"] == "duplicate"
    assert again["results"][0]["resolution"] == "skipped_duplicate"
    assert again["summary"]["duplicate"] == 1


def test_invalid_base_version(client):
    _init_match(client)
    r = client.post(
        "/audit/v1/offline-sync",
        json={
            "device_id": "dev-3",
            "actions": [
                {
                    "action_id": "a1",
                    "type": "score_event",
                    "queued_at": "2026-10-17T11:00:00Z",
                    "base_version": 99,
                    "payload": {
                        "event_id": "evt-bad",
                        "match_id": "m1",
                        "type": "score",
                        "payload": {"team_id": "t1", "event_type": "goal"},
                    },
                }
            ],
        },
    )
    assert r.status_code == 200
    assert r.json()["results"][0]["status"] == "rejected"
    assert r.json()["results"][0]["error_code"] == "INVALID_BASE_VERSION"


def test_match_not_in_progress_rejected(client):
    # upcoming only (no start)
    assert client.post(
        "/audit/v1/events",
        json={
            "event_id": "init-m2",
            "match_id": "m2",
            "type": "match_init",
            "payload": {
                "sport_id": "football",
                "home_team_id": "t1",
                "away_team_id": "t2",
            },
        },
    ).status_code == 201
    r = client.post(
        "/audit/v1/offline-sync",
        json={
            "device_id": "dev-4",
            "actions": [
                {
                    "action_id": "a1",
                    "type": "score_event",
                    "queued_at": "2026-10-17T11:00:00Z",
                    "base_version": 1,
                    "payload": {
                        "event_id": "evt-early",
                        "match_id": "m2",
                        "type": "score",
                        "payload": {"team_id": "t1", "event_type": "goal"},
                    },
                }
            ],
        },
    )
    assert r.json()["results"][0]["error_code"] == "MATCH_NOT_IN_PROGRESS"


def test_roster_transfer_via_sync(client):
    _setup_roster(client)
    r = client.post(
        "/audit/v1/offline-sync",
        json={
            "device_id": "dev-5",
            "actions": [
                {
                    "action_id": "a-roster",
                    "type": "roster_transfer",
                    "queued_at": "2026-10-17T11:01:00Z",
                    "base_version": 0,
                    "payload": {
                        "request_id": "tr-off-1",
                        "league_id": "lg-r1",
                        "player_id": "p2",
                        "type": "transfer",
                        "from_squad_id": "sq-a",
                        "to_squad_id": "sq-b",
                        "effective_date": "2026-09-30",
                        "loan_end_date": None,
                        "reason": "Offline move",
                        "requested_by": "user-77",
                    },
                }
            ],
        },
    )
    assert r.status_code == 200
    assert r.json()["results"][0]["status"] == "applied"
    assert r.json()["results"][0]["server_version"] == 1


def test_ordering_by_queued_at(client):
    _init_match(client)
    r = client.post(
        "/audit/v1/offline-sync",
        json={
            "device_id": "dev-ord",
            "actions": [
                {
                    "action_id": "later",
                    "type": "score_event",
                    "queued_at": "2026-10-17T12:00:00Z",
                    "base_version": 2,
                    "payload": {
                        "event_id": "evt-later",
                        "match_id": "m1",
                        "type": "score",
                        "payload": {"team_id": "t1", "event_type": "goal"},
                    },
                },
                {
                    "action_id": "earlier",
                    "type": "score_event",
                    "queued_at": "2026-10-17T11:00:00Z",
                    "base_version": 2,
                    "payload": {
                        "event_id": "evt-earlier",
                        "match_id": "m1",
                        "type": "score",
                        "payload": {"team_id": "t2", "event_type": "goal"},
                    },
                },
            ],
        },
    )
    results = r.json()["results"]
    # Request order preserved in results array
    assert results[0]["action_id"] == "later"
    assert results[1]["action_id"] == "earlier"
    # Processing order: earlier first
    assert results[1]["processed_order"] == 1
    assert results[0]["processed_order"] == 2
