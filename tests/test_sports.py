"""POST /audit/v1/sports (§5.6) + mystery sport scoring."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from conftest import requires_db

pytestmark = requires_db

KABADDI = {
    "sport_id": "kabaddi",
    "name": "Kabaddi",
    "scoring_model": "event",
    "periods": {"count": 2, "duration_minutes": 20},
    "scoring_events": {
        "raid_point": {"points": 1},
        "tackle_point": {"points": 1},
        "all_out": {"points": 2},
    },
    "draw_allowed": False,
    "overtime": {"policy": "golden_score", "duration_minutes": 5},
    "tie_break_order": [
        "h2h_points", "h2h_diff", "overall_diff", "scored", "fair_play", "draw_lots"
    ],
    "roster": {
        "min_squad_size": 7,
        "max_squad_size": 12,
        "required_positions": {"raider": 2, "defender": 3},
    },
}


@pytest.fixture(scope="module")
def client():
    from app.main import app
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def _reset(client):
    assert client.post("/audit/v1/reset").status_code == 200


def test_create_kabaddi_success(client):
    r = client.post("/audit/v1/sports", json=KABADDI)
    assert r.status_code == 201
    body = r.json()
    assert body["sport_id"] == "kabaddi"
    assert body["status"] == "created"
    assert body["config"]["scoring_model"] == "event"
    assert body["config"]["scoring_events"]["all_out"]["points"] == 2
    assert body["config"]["tie_break_order"][-1] == "draw_lots"


def test_duplicate_sport_id(client):
    assert client.post("/audit/v1/sports", json=KABADDI).status_code == 201
    r = client.post("/audit/v1/sports", json=KABADDI)
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "SPORT_EXISTS"


def test_duplicate_seeded_sport(client):
    body = {**KABADDI, "sport_id": "football", "name": "Other"}
    r = client.post("/audit/v1/sports", json=body)
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "SPORT_EXISTS"


def test_invalid_sport_id(client):
    body = {**KABADDI, "sport_id": "Bad ID!"}
    r = client.post("/audit/v1/sports", json=body)
    assert r.status_code == 400
    assert "sport_id" in r.json()["error"]["details"]["fields"]


def test_missing_required_fields(client):
    r = client.post("/audit/v1/sports", json={"sport_id": "x"})
    assert r.status_code == 400
    fields = r.json()["error"]["details"]["fields"]
    assert "name" in fields
    assert "scoring_model" in fields


def test_invalid_event_points(client):
    body = {**KABADDI, "sport_id": "badpts",
            "scoring_events": {"raid_point": {"points": 0}}}
    r = client.post("/audit/v1/sports", json=body)
    assert r.status_code == 400
    assert any("points" in f for f in r.json()["error"]["details"]["fields"])


def test_innings_and_round_models(client):
    innings = {
        "sport_id": "mini-bat",
        "name": "Mini Bat",
        "scoring_model": "innings",
        "periods": {
            "innings_per_team": 1, "overs_per_innings": 2,
            "balls_per_over": 6, "wickets_per_innings": 3,
        },
        "scoring_events": {
            "hit": {"runs": 1, "legal_ball": True, "wicket": False},
            "out": {"runs": 0, "legal_ball": True, "wicket": True},
        },
        "draw_allowed": True,
        "overtime": {"policy": "super_over"},
        "roster": {"min_squad_size": 5, "max_squad_size": 8, "required_positions": {}},
    }
    assert client.post("/audit/v1/sports", json=innings).status_code == 201

    round_sport = {
        "sport_id": "maps",
        "name": "Maps",
        "scoring_model": "round",
        "periods": {"best_of": 5},
        "scoring_events": {"map_win": {"rounds": 1}},
        "draw_allowed": False,
        "overtime": {"policy": "none"},
        "roster": {"min_squad_size": 2, "max_squad_size": 5, "required_positions": {}},
    }
    assert client.post("/audit/v1/sports", json=round_sport).status_code == 201

    # even best_of invalid
    bad = {**round_sport, "sport_id": "maps2", "periods": {"best_of": 4}}
    assert client.post("/audit/v1/sports", json=bad).status_code == 400


def test_draw_lots_appended_when_omitted(client):
    body = {**KABADDI, "sport_id": "kabaddi2"}
    del body["tie_break_order"]
    r = client.post("/audit/v1/sports", json=body)
    assert r.status_code == 201
    assert r.json()["config"]["tie_break_order"][-1] == "draw_lots"


def test_score_match_with_mystery_sport(client):
    assert client.post("/audit/v1/sports", json=KABADDI).status_code == 201
    assert client.post(
        "/audit/v1/events",
        json={
            "event_id": "ki",
            "match_id": "kab-m1",
            "type": "match_init",
            "payload": {
                "sport_id": "kabaddi",
                "home_team_id": "a",
                "away_team_id": "b",
            },
        },
    ).status_code == 201
    assert client.post(
        "/audit/v1/events",
        json={"event_id": "ks", "match_id": "kab-m1", "type": "match_start", "payload": {}},
    ).status_code == 201
    r = client.post(
        "/audit/v1/events",
        json={
            "event_id": "kg",
            "match_id": "kab-m1",
            "type": "score",
            "payload": {"team_id": "a", "event_type": "all_out"},
        },
    )
    assert r.status_code == 201
    s = client.get("/audit/v1/score/kab-m1").json()
    assert s["sport_id"] == "kabaddi"
    assert s["home"]["score"] == 2
    # unknown event type for this sport
    bad = client.post(
        "/audit/v1/events",
        json={
            "event_id": "kg2",
            "match_id": "kab-m1",
            "type": "score",
            "payload": {"team_id": "a", "event_type": "goal"},
        },
    )
    assert bad.status_code == 400
    assert bad.json()["error"]["code"] == "UNKNOWN_EVENT_TYPE"
