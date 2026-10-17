"""Standings table, H2H, tie-breaks, qualification (§5.10). Requires TEST_DATABASE_URL."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.signing import lots_key
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


def register_league(client, league_id, teams, fixtures, sport_id="football",
                    spots=2, points=None, tie_break_order=None, lots_seed=42):
    body = {
        "league_id": league_id,
        "sport_id": sport_id,
        "teams": teams,
        "fixtures": fixtures,
        "qualification": {"spots": spots},
        "lots_seed": lots_seed,
    }
    if points is not None:
        body["points"] = points
    if tie_break_order is not None:
        body["tie_break_order"] = tie_break_order
    r = client.post("/audit/v1/leagues", json=body)
    assert r.status_code == 201, r.text
    return r


def play_football(client, match_id, home, away, home_goals, away_goals, prefix):
    assert ev(
        client, event_id=f"{prefix}-start", match_id=match_id,
        type="match_start", payload={},
    ).status_code == 201
    n = 0
    for _ in range(home_goals):
        n += 1
        assert ev(
            client, event_id=f"{prefix}-hg{n}", match_id=match_id, type="score",
            payload={"team_id": home, "event_type": "goal"},
        ).status_code == 201
    for _ in range(away_goals):
        n += 1
        assert ev(
            client, event_id=f"{prefix}-ag{n}", match_id=match_id, type="score",
            payload={"team_id": away, "event_type": "goal"},
        ).status_code == 201
    assert ev(
        client, event_id=f"{prefix}-end", match_id=match_id,
        type="match_end", payload={},
    ).status_code == 201


def test_league_not_found(client):
    r = client.get("/audit/v1/standings/no-such-league")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "LEAGUE_NOT_FOUND"


def test_empty_table_all_remaining(client):
    register_league(
        client, "lg-1",
        teams=["t1", "t2", "t3"],
        fixtures=[
            {"match_id": "e-m1", "home": "t1", "away": "t2"},
            {"match_id": "e-m2", "home": "t1", "away": "t3"},
            {"match_id": "e-m3", "home": "t2", "away": "t3"},
        ],
        spots=2,
        lots_seed=42,
    )
    r = client.get("/audit/v1/standings/lg-1")
    assert r.status_code == 200
    body = r.json()
    assert body["league_id"] == "lg-1"
    assert body["sport_id"] == "football"
    assert body["qualification_spots"] == 2
    assert len(body["table"]) == 3
    # All 0 pts → draw_lots order: t1, t3, t2 (Appendix A vector)
    order = [row["team_id"] for row in body["table"]]
    assert order == ["t1", "t3", "t2"]
    for row in body["table"]:
        assert row["played"] == 0
        assert row["points"] == 0
        assert row["status"] == "still_possible"
        assert row["resolved_by"] in (None, "draw_lots")
    # Adjacent 0-pt teams separated by draw_lots
    assert body["table"][0]["resolved_by"] == "draw_lots"
    assert body["table"][1]["resolved_by"] == "draw_lots"
    assert body["table"][2]["resolved_by"] is None
    # h2h zeros for every ordered pair
    assert body["h2h"]["t1"]["t2"] == {"played": 0, "points": 0, "scored": 0, "conceded": 0}


def test_multiple_completed_matches_points_and_h2h(client):
    register_league(
        client, "lg-pts",
        teams=["a", "b", "c"],
        fixtures=[
            {"match_id": "p1", "home": "a", "away": "b"},
            {"match_id": "p2", "home": "a", "away": "c"},
            {"match_id": "p3", "home": "b", "away": "c"},
        ],
        spots=2,
    )
    play_football(client, "p1", "a", "b", 2, 1, "p1")
    play_football(client, "p2", "a", "c", 1, 0, "p2")
    # b vs c unfinished

    body = client.get("/audit/v1/standings/lg-pts").json()
    by = {row["team_id"]: row for row in body["table"]}
    assert by["a"]["rank"] == 1
    assert by["a"]["played"] == 2
    assert by["a"]["won"] == 2
    assert by["a"]["points"] == 6
    assert by["a"]["scored"] == 3
    assert by["a"]["conceded"] == 1
    assert by["a"]["diff"] == 2
    assert by["a"]["status"] == "clinched"  # max others cannot catch both spots? check
    # a has 6, remaining 0. b and c have 0 pts, 1 remaining each → max=3.
    # fewer than 2 others with max>=6 → clinched. Yes.
    assert by["b"]["played"] == 1
    assert by["b"]["lost"] == 1
    assert by["b"]["points"] == 0
    assert body["h2h"]["a"]["b"] == {"played": 1, "points": 3, "scored": 2, "conceded": 1}
    assert body["h2h"]["b"]["a"] == {"played": 1, "points": 0, "scored": 1, "conceded": 2}


def test_three_way_h2h_tiebreak(client):
    """Three teams equal on points; H2H mini-league breaks the tie (edge case #4)."""
    register_league(
        client, "lg-h2h",
        teams=["x", "y", "z"],
        fixtures=[
            {"match_id": "h1", "home": "x", "away": "y"},
            {"match_id": "h2", "home": "y", "away": "z"},
            {"match_id": "h3", "home": "z", "away": "x"},
        ],
        spots=1,
        # Force points tie: each wins one → 3 pts each
        tie_break_order=["h2h_points", "h2h_diff", "overall_diff", "scored", "fair_play", "draw_lots"],
    )
    play_football(client, "h1", "x", "y", 2, 0, "h1")  # x beat y
    play_football(client, "h2", "y", "z", 3, 0, "h2")  # y beat z
    play_football(client, "h3", "z", "x", 1, 0, "h3")  # z beat x
    # Each: W1 L1, 3 pts. H2H points also all 3. H2H diff:
    # x: scored 2+0=2, conceded 0+1=1, diff +1
    # y: scored 0+3=3, conceded 2+0=2, diff +1
    # z: scored 0+1=1, conceded 0+3=3, diff -2
    # So z last on h2h_diff; x and y still tied on h2h_diff=+1
    # Restart: h2h between x,y only → x beat y → x first
    body = client.get("/audit/v1/standings/lg-h2h").json()
    order = [row["team_id"] for row in body["table"]]
    assert order == ["x", "y", "z"]
    assert body["table"][0]["points"] == 3
    assert body["table"][0]["resolved_by"] == "h2h_points"
    assert body["table"][1]["resolved_by"] == "h2h_diff"
    assert body["table"][2]["resolved_by"] is None


def test_draw_lots_order_matches_appendix(client):
    keys = {t: lots_key(42, "lg-1", t) for t in ("t1", "t2", "t3")}
    assert sorted(keys, key=keys.get) == ["t1", "t3", "t2"]


def test_incomplete_match_not_counted(client):
    register_league(
        client, "lg-inc",
        teams=["a", "b"],
        fixtures=[{"match_id": "inc1", "home": "a", "away": "b"}],
        spots=1,
    )
    assert ev(
        client, event_id="inc-start", match_id="inc1", type="match_start", payload={},
    ).status_code == 201
    assert ev(
        client, event_id="inc-g", match_id="inc1", type="score",
        payload={"team_id": "a", "event_type": "goal"},
    ).status_code == 201
    # no match_end
    body = client.get("/audit/v1/standings/lg-inc").json()
    for row in body["table"]:
        assert row["played"] == 0
        assert row["points"] == 0


def test_qualification_eliminated(client):
    register_league(
        client, "lg-qual",
        teams=["a", "b", "c", "d"],
        fixtures=[
            {"match_id": "q1", "home": "a", "away": "b"},
            {"match_id": "q2", "home": "c", "away": "d"},
            # no more fixtures — season almost done
        ],
        spots=1,
    )
    play_football(client, "q1", "a", "b", 5, 0, "q1")
    play_football(client, "q2", "c", "d", 1, 0, "q2")
    body = client.get("/audit/v1/standings/lg-qual").json()
    by = {row["team_id"]: row for row in body["table"]}
    # a: 3 pts, remaining 0, max=3. Others with max>=3: only those with max>=3.
    # c has 3. b,d have 0. fewer than 1 other with max>=3? c has max=3 >= 3 → 1 other → not clinched
    # Wait: clinched if fewer than k=1 other teams have max>=pts(a)=3.
    # c has max=3 >= 3 → 1 other → NOT clinched → still_possible (tied on points potentially)
    assert by["a"]["points"] == 3
    assert by["c"]["points"] == 3
    # b: pts=0, max=0. Others with pts > 0: a and c (2) >= k=1 → eliminated
    assert by["b"]["status"] == "eliminated"
    assert by["d"]["status"] == "eliminated"


def test_innings_nrr_diff(client):
    """Innings sports use net run rate (3 dp) for overall diff."""
    register_league(
        client, "lg-nrr",
        teams=["c1", "c2"],
        fixtures=[{"match_id": "nrr1", "home": "c1", "away": "c2"}],
        sport_id="cricket",
        spots=1,
    )
    assert ev(
        client, event_id="nrr-s", match_id="nrr1", type="match_start", payload={},
    ).status_code == 201
    # c1: 12 runs off 6 legal balls (1.0 over) — two sixes + four dots
    for i, et in enumerate(["six", "six", "dot_ball", "dot_ball", "dot_ball", "dot_ball"]):
        assert ev(
            client, event_id=f"nrr-c1-{i}", match_id="nrr1", type="score",
            payload={"team_id": "c1", "event_type": et},
        ).status_code == 201
    # c2: 6 runs off 6 legal balls
    for i in range(6):
        assert ev(
            client, event_id=f"nrr-c2-{i}", match_id="nrr1", type="score",
            payload={"team_id": "c2", "event_type": "single"},
        ).status_code == 201
    assert ev(
        client, event_id="nrr-e", match_id="nrr1", type="match_end", payload={},
    ).status_code == 201

    body = client.get("/audit/v1/standings/lg-nrr").json()
    by = {row["team_id"]: row for row in body["table"]}
    # c1: 12/1 − 6/1 = 6.000; c2: 6/1 − 12/1 = -6.000
    assert by["c1"]["scored"] == 12
    assert by["c1"]["conceded"] == 6
    assert by["c1"]["diff"] == 6.0
    assert by["c2"]["diff"] == -6.0
    assert by["c1"]["rank"] == 1


def test_compensation_recomputes_standings(client):
    register_league(
        client, "lg-comp",
        teams=["a", "b"],
        fixtures=[{"match_id": "cm1", "home": "a", "away": "b"}],
        spots=1,
    )
    play_football(client, "cm1", "a", "b", 1, 0, "cm")
    before = client.get("/audit/v1/standings/lg-comp").json()
    assert before["table"][0]["team_id"] == "a"
    assert before["table"][0]["points"] == 3

    r = ev(
        client, event_id="cm-comp", match_id="cm1", type="compensation",
        payload={"compensates": "cm-hg1", "reason": "offside"},
    )
    assert r.status_code == 201
    after = client.get("/audit/v1/standings/lg-comp").json()
    # Goal wiped → draw 1-1? Actually home had 1, compensated → 0-0 draw
    by = {row["team_id"]: row for row in after["table"]}
    assert by["a"]["points"] == 1
    assert by["b"]["points"] == 1
    assert by["a"]["drawn"] == 1
