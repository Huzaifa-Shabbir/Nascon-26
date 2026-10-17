"""Event-sourced scoring tests (spec §5.9). Requires TEST_DATABASE_URL."""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from app.signing import sign
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


def ev(client, **kwargs):
    return client.post("/audit/v1/events", json=kwargs)


def init_match(client, match_id="m1", sport_id="football", home="t1", away="t2",
               event_id=None, league_id=None):
    payload = {"sport_id": sport_id, "home_team_id": home, "away_team_id": away}
    if league_id is not None:
        payload["league_id"] = league_id
    return ev(
        client,
        event_id=event_id or f"init-{match_id}",
        match_id=match_id,
        type="match_init",
        payload=payload,
    )


def start(client, match_id="m1", event_id="start-1"):
    return ev(client, event_id=event_id, match_id=match_id, type="match_start", payload={})


def score(client, match_id, event_id, team_id, event_type):
    return ev(
        client,
        event_id=event_id,
        match_id=match_id,
        type="score",
        payload={"team_id": team_id, "event_type": event_type},
    )


def end(client, match_id="m1", event_id="end-1"):
    return ev(client, event_id=event_id, match_id=match_id, type="match_end", payload={})


# ---- happy path football ----

def test_football_match_flow_and_score(client):
    assert init_match(client).status_code == 201
    assert start(client).status_code == 201
    r1 = score(client, "m1", "evt-1", "t1", "goal")
    assert r1.status_code == 201
    body = r1.json()
    assert body["sequence"] == 3
    assert body["match_version"] == 3
    assert body["signature"] == sign("evt-1", {"team_id": "t1", "event_type": "goal"})

    score(client, "m1", "evt-2", "t1", "goal")
    score(client, "m1", "evt-3", "t2", "goal")
    assert end(client).status_code == 201

    s = client.get("/audit/v1/score/m1").json()
    assert s["status"] == "completed"
    assert s["outcome"] == "home_win"
    assert s["winner_team_id"] == "t1"
    assert s["home"]["score"] == 2
    assert s["away"]["score"] == 1
    assert s["home"]["wickets"] is None
    assert s["version"] == 6
    assert len(s["events"]) == 6
    assert s["events"][0]["type"] == "match_init"
    assert s["events"][0]["compensated"] is False


def test_score_unknown_match(client):
    r = client.get("/audit/v1/score/nope")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "MATCH_NOT_FOUND"


def test_event_missing_match_not_init(client):
    r = start(client, match_id="ghost", event_id="s1")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "MATCH_NOT_FOUND"


def test_match_init_duplicate_match(client):
    assert init_match(client).status_code == 201
    r = init_match(client, event_id="init-m1-b")
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "MATCH_EXISTS"


def test_match_init_unknown_sport(client):
    r = init_match(client, sport_id="nope-sport")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "SPORT_NOT_FOUND"


def test_illegal_start_twice(client):
    init_match(client)
    start(client)
    r = start(client, event_id="start-2")
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "ILLEGAL_TRANSITION"


def test_score_requires_in_progress(client):
    init_match(client)
    r = score(client, "m1", "e1", "t1", "goal")
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "MATCH_NOT_IN_PROGRESS"


def test_unknown_event_type(client):
    init_match(client)
    start(client)
    r = score(client, "m1", "e1", "t1", "hat_trick")
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "UNKNOWN_EVENT_TYPE"


def test_invalid_team_id(client):
    init_match(client)
    start(client)
    r = score(client, "m1", "e1", "t99", "goal")
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


def test_idempotent_replay(client):
    init_match(client)
    start(client)
    body = {
        "event_id": "evt-idem",
        "match_id": "m1",
        "type": "score",
        "payload": {"team_id": "t1", "event_type": "goal"},
    }
    r1 = client.post("/audit/v1/events", json=body)
    r2 = client.post("/audit/v1/events", json=body)
    assert r1.status_code == 201
    assert r2.status_code == 200
    assert r1.json() == r2.json()
    assert client.get("/audit/v1/score/m1").json()["home"]["score"] == 1


def test_duplicate_event_id_different_body(client):
    init_match(client)
    start(client)
    score(client, "m1", "evt-dup", "t1", "goal")
    r = score(client, "m1", "evt-dup", "t2", "goal")
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "DUPLICATE_EVENT_ID"


def test_compensation_neutralizes_score(client):
    init_match(client)
    start(client)
    score(client, "m1", "evt-g1", "t1", "goal")
    score(client, "m1", "evt-g2", "t1", "goal")
    r = ev(
        client,
        event_id="evt-comp",
        match_id="m1",
        type="compensation",
        payload={"compensates": "evt-g1", "reason": "offside"},
    )
    assert r.status_code == 201
    s = client.get("/audit/v1/score/m1").json()
    assert s["home"]["score"] == 1
    g1 = next(e for e in s["events"] if e["event_id"] == "evt-g1")
    assert g1["compensated"] is True
    assert g1["compensated_by"] == "evt-comp"


def test_invalid_compensation(client):
    init_match(client)
    start(client)
    score(client, "m1", "evt-g1", "t1", "goal")
    ev(client, event_id="c1", match_id="m1", type="compensation",
       payload={"compensates": "evt-g1", "reason": "x"})
    r = ev(client, event_id="c2", match_id="m1", type="compensation",
           payload={"compensates": "evt-g1", "reason": "again"})
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "INVALID_COMPENSATION"


def test_compensation_unknown_target(client):
    init_match(client)
    r = ev(client, event_id="c1", match_id="m1", type="compensation",
           payload={"compensates": "missing", "reason": "x"})
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "EVENT_NOT_FOUND"


def test_tie_not_allowed_basketball(client):
    init_match(client, match_id="mb", sport_id="basketball", home="a", away="b")
    start(client, "mb", "s-b")
    score(client, "mb", "e1", "a", "two_pointer")
    score(client, "mb", "e2", "b", "two_pointer")
    r = end(client, "mb", "end-b")
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "TIE_NOT_ALLOWED"


def test_tiebreak_allows_end(client):
    init_match(client, match_id="mb", sport_id="basketball", home="a", away="b")
    start(client, "mb", "s-b")
    score(client, "mb", "e1", "a", "free_throw")
    score(client, "mb", "e2", "b", "free_throw")
    ev(client, event_id="tb", match_id="mb", type="tiebreak_winner", payload={"team_id": "a"})
    assert end(client, "mb", "end-b").status_code == 201
    s = client.get("/audit/v1/score/mb").json()
    assert s["outcome"] == "home_win"
    assert s["winner_team_id"] == "a"
    assert s["tiebreak_winner_team_id"] == "a"


def test_discipline_fair_play(client):
    init_match(client)
    start(client)
    ev(client, event_id="d1", match_id="m1", type="discipline",
       payload={"team_id": "t2", "points": -1})
    s = client.get("/audit/v1/score/m1").json()
    assert s["away"]["fair_play"] == -1
    assert s["home"]["fair_play"] == 0


def test_draw_allowed_football(client):
    init_match(client)
    start(client)
    score(client, "m1", "e1", "t1", "goal")
    score(client, "m1", "e2", "t2", "goal")
    assert end(client).status_code == 201
    s = client.get("/audit/v1/score/m1").json()
    assert s["outcome"] == "draw"
    assert s["winner_team_id"] is None


def test_cricket_innings_and_overs(client):
    init_match(client, match_id="c1", sport_id="cricket", home="a", away="b")
    start(client, "c1", "sc")
    # 2 legal balls + a four
    score(client, "c1", "e1", "a", "dot_ball")
    score(client, "c1", "e2", "a", "single")
    score(client, "c1", "e3", "a", "four")
    s = client.get("/audit/v1/score/c1").json()
    assert s["home"]["score"] == 5  # 0+1+4
    assert s["home"]["balls"] == 3
    assert s["home"]["overs"] == "0.3"
    assert s["home"]["wickets"] == 0


def test_cricket_innings_complete(client):
    # Tiny: use seeded cricket but complete via many wickets — 10 wickets per innings
    init_match(client, match_id="c2", sport_id="cricket", home="a", away="b")
    start(client, "c2", "sc2")
    for i in range(10):
        assert score(client, "c2", f"w{i}", "a", "wicket").status_code == 201
    r = score(client, "c2", "w-extra", "a", "single")
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "INNINGS_COMPLETE"


def test_esports_series_decided(client):
    init_match(client, match_id="e1", sport_id="esports", home="a", away="b")
    start(client, "e1", "se")
    # best_of 3 → need 2 round wins
    assert score(client, "e1", "r1", "a", "round_win").status_code == 201
    assert score(client, "e1", "r2", "a", "round_win").status_code == 201
    r = score(client, "e1", "r3", "a", "round_win")
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "SERIES_ALREADY_DECIDED"


def test_league_fixture_creates_match_stream(client):
    r = client.post(
        "/audit/v1/leagues",
        json={
            "league_id": "lg-score-1",
            "sport_id": "football",
            "teams": ["t1", "t2", "t3", "t4"],
            "fixtures": [{"match_id": "fx-1", "home": "t1", "away": "t2"}],
            "qualification": {"spots": 2},
        },
    )
    assert r.status_code == 201
    # Stream exists without match_init
    assert start(client, "fx-1", "sfx").status_code == 201
    assert score(client, "fx-1", "g1", "t1", "goal").status_code == 201
    s = client.get("/audit/v1/score/fx-1").json()
    assert s["league_id"] == "lg-score-1"
    assert s["home"]["score"] == 1
    assert s["status"] == "in_progress"


def test_compensation_after_match_end(client):
    init_match(client)
    start(client)
    score(client, "m1", "g1", "t1", "goal")
    end(client)
    r = ev(client, event_id="c-late", match_id="m1", type="compensation",
           payload={"compensates": "g1", "reason": "VAR"})
    assert r.status_code == 201
    s = client.get("/audit/v1/score/m1").json()
    assert s["status"] == "completed"
    assert s["home"]["score"] == 0
    assert s["outcome"] == "draw"


def test_validation_missing_fields(client):
    r = client.post("/audit/v1/events", json={})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


def test_concurrent_score_appends(client):
    init_match(client, match_id="mc")
    start(client, "mc", "smc")

    def go(i):
        return score(client, "mc", f"cg{i}", "t1", "goal").status_code

    with ThreadPoolExecutor(max_workers=8) as pool:
        codes = list(pool.map(go, range(8)))
    assert codes.count(201) == 8
    s = client.get("/audit/v1/score/mc").json()
    assert s["home"]["score"] == 8
    assert s["version"] == 10  # init+start+8
