"""Regression: malformed values must be 400, never 5xx (spec 5.2, 5.13 input validation).

Each case below returned 500 before the fix (wrong JSON type reaching a set
lookup, or a YYYY-MM-DD string that is not a real calendar date).
"""
import copy

import pytest
from fastapi.testclient import TestClient

from conftest import requires_db

pytestmark = requires_db

SPORT = {"sport_id": "fz", "name": "F", "scoring_model": "event", "periods": {"count": 1, "duration_minutes": 1},
         "scoring_events": {"a": {"points": 1}}, "draw_allowed": True, "overtime": {"policy": "none"},
         "roster": {"min_squad_size": 1, "max_squad_size": 2, "required_positions": {}}}
LEAGUE = {"league_id": "lf", "sport_id": "football", "teams": ["a", "b"],
          "fixtures": [{"match_id": "mf", "home": "a", "away": "b"}], "qualification": {"spots": 1}}
SETUP = {"league": {"league_id": "lr", "tenant_id": "tenant-alpha", "sport_id": "football",
                    "transfer_window": {"open": "2026-09-01", "close": "2026-09-30"}},
         "squads": [{"squad_id": "s1", "club_id": "c1", "tenant_id": "tenant-alpha", "name": "S1"},
                    {"squad_id": "s2", "club_id": "c2", "tenant_id": "tenant-alpha", "name": "S2"}],
         "players": [{"player_id": "pz", "name": "P", "position": "df", "squad_id": "s1", "role": "starter"}],
         "matches_in_progress": []}
TRANSFER = {"request_id": "rz", "league_id": "lr", "player_id": "pz", "type": "transfer", "from_squad_id": "s1",
            "to_squad_id": "s2", "effective_date": "2026-09-10", "loan_end_date": None, "reason": "r", "requested_by": "u"}
SYNC = {"device_id": "d", "actions": [{"action_id": "a", "type": "score_event", "queued_at": "2026-10-17T11:00:00Z",
        "base_version": 0, "payload": {"event_id": "eo", "match_id": "mf", "type": "score",
                                        "payload": {"team_id": "a", "event_type": "goal"}}}]}


@pytest.fixture(scope="module")
def client():
    from app.main import app
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def _baseline(client):
    assert client.post("/audit/v1/reset").status_code == 200
    assert client.post("/audit/v1/leagues", json=LEAGUE).status_code == 201
    assert client.post("/audit/v1/roster/setup", json=SETUP).status_code == 201


def _with(base, path, value):
    body = copy.deepcopy(base)
    cur = body
    for key in path[:-1]:
        cur = cur[key]
    cur[path[-1]] = value
    return body


@pytest.mark.parametrize("route, base, path, value, field", [
    ("/audit/v1/sports", SPORT, ("scoring_model",), [], "scoring_model"),
    ("/audit/v1/sports", SPORT, ("overtime", "policy"), [], "overtime.policy"),
    ("/audit/v1/leagues", {**LEAGUE, "league_id": "lg2", "fixtures": [{"match_id": "m2", "home": "a", "away": "b"}]},
     ("fixtures", 0, "home"), [], "fixtures.0"),
    ("/audit/v1/leagues", {**LEAGUE, "league_id": "lg2", "fixtures": [{"match_id": "m2", "home": "a", "away": "b"}]},
     ("fixtures", 0, "away"), {}, "fixtures.0"),
    ("/audit/v1/roster/setup", SETUP, ("league", "transfer_window", "open"), "2026-13-45", "league.transfer_window.open"),
    ("/audit/v1/roster/setup", SETUP, ("league", "transfer_window", "close"), "2026-02-30", "league.transfer_window.close"),
    ("/audit/v1/roster/setup", SETUP, ("players", 0, "role"), [], "players.0.role"),
    ("/audit/v1/roster/transfer", TRANSFER, ("type",), [], "type"),
    ("/audit/v1/roster/transfer", TRANSFER, ("effective_date",), "2026-13-45", "effective_date"),
    ("/audit/v1/roster/transfer", {**TRANSFER, "type": "loan"}, ("loan_end_date",), "2026-09-31", "loan_end_date"),
    ("/audit/v1/offline-sync", SYNC, ("actions", 0, "type"), [], "actions.0.type"),
])
def test_bad_value_is_400_not_500(client, route, base, path, value, field):
    r = client.post(route, json=_with(base, path, value))
    assert r.status_code == 400, r.text
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"
    assert field in r.json()["error"]["details"]["fields"]


@pytest.mark.parametrize("as_of", ["2026-13-45", "2026-02-30", "x"])
def test_history_invalid_as_of_is_400(client, as_of):
    r = client.get(f"/audit/v1/roster/history/pz?as_of={as_of}")
    assert r.status_code == 400
    assert r.json()["error"]["details"]["fields"] == ["as_of"]


def test_real_dates_still_accepted(client):
    r = client.post("/audit/v1/roster/transfer", json={**TRANSFER, "effective_date": "2026-09-30"})
    assert r.status_code == 201, r.text
    assert client.get("/audit/v1/roster/history/pz?as_of=2026-12-31").status_code == 200
