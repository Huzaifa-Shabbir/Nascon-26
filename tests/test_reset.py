import json

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from conftest import requires_db

pytestmark = requires_db

SEED_TABLES = ["app_meta", "tenants", "sports", "leagues", "clubs", "players", "users",
               "products", "variants", "discount_codes"]


@pytest.fixture(scope="module")
def client():
    from app.main import app
    with TestClient(app) as c:
        yield c


def snapshot():
    from app import db
    with db.engine.connect() as conn:
        return {t: [dict(r._mapping) for r in conn.execute(text(f"SELECT * FROM {t} ORDER BY 1"))]
                for t in SEED_TABLES}


def test_reset_default_response_matches_spec(client):
    r = client.post("/audit/v1/reset")
    assert r.status_code == 200
    assert r.json() == {
        "status": "reset_complete",
        "seed": 42,
        "sports": ["football", "basketball", "cricket", "esports"],
        "tenants": ["tenant-alpha", "tenant-beta"],
        "stock": {"var-jersey-001-M": 1, "var-jersey-001-L": 5},
    }


def test_reset_twice_leaves_identical_state(client):
    client.post("/audit/v1/reset", json={})
    first = snapshot()
    client.post("/audit/v1/reset", json={})
    assert snapshot() == first


def test_seed_ids_exist(client):
    client.post("/audit/v1/reset")
    s = snapshot()
    ids = lambda t, k: {r[k] for r in s[t]}
    assert ids("tenants", "tenant_id") == {"tenant-alpha", "tenant-beta"}
    assert ids("leagues", "league_id") == {"league-alpha-1", "league-alpha-2", "league-beta-1"}
    assert ids("clubs", "club_id") == {"club-alpha-1", "club-alpha-2", "club-beta-1"}
    assert {(r["player_id"], r["club_id"]) for r in s["players"]} == {
        ("player-alpha-1", "club-alpha-1"), ("player-alpha-2", "club-alpha-2"), ("player-beta-1", "club-beta-1")}
    assert ids("users", "email") == {f"{n}@nascon.test" for n in ("admin", "organizer", "manager", "player", "viewer")}
    assert {(r["variant_id"], r["price_minor"], r["currency"]) for r in s["variants"]} == {
        ("var-jersey-001-M", 450000, "PKR"), ("var-jersey-001-L", 450000, "PKR")}
    assert ids("discount_codes", "code") == {"WELCOME10"}


def test_demo_passwords_verify(client):
    from app.passwords import verify_password
    client.post("/audit/v1/reset")
    assert all(verify_password("Nascon@26", u["password_hash"]) for u in snapshot()["users"])


def test_seeded_sports_are_stored_as_spec_config(client):
    client.post("/audit/v1/reset")
    configs = {r["sport_id"]: r["config"] for r in snapshot()["sports"]}
    assert set(configs["basketball"]["scoring_events"]) == {"free_throw", "two_pointer", "three_pointer"}
    assert configs["cricket"]["periods"]["balls_per_over"] == 6
    assert configs["esports"]["periods"] == {"best_of": 3}
    assert configs["football"]["roster"]["required_positions"] == {"gk": 1}


def test_reset_custom_seed_and_partial_stock(client):
    r = client.post("/audit/v1/reset", json={"seed": 7, "stock": {"var-jersey-001-M": 3}})
    assert r.status_code == 200
    assert r.json()["seed"] == 7
    assert r.json()["stock"] == {"var-jersey-001-M": 3, "var-jersey-001-L": 5}
    s = snapshot()
    assert s["app_meta"] == [{"key": "lots_seed", "value": 7}]
    assert {v["variant_id"]: (v["stock"], v["reserved"]) for v in s["variants"]} == {
        "var-jersey-001-M": (3, 0), "var-jersey-001-L": (5, 0)}


def test_reset_wipes_non_baseline_rows(client):
    from app import db
    client.post("/audit/v1/reset")
    with db.engine.begin() as conn:
        conn.execute(text("INSERT INTO sports (sport_id, config) VALUES ('kabaddi', CAST(:c AS JSONB))"),
                     {"c": json.dumps({"sport_id": "kabaddi"})})
    client.post("/audit/v1/reset")
    assert "kabaddi" not in {r["sport_id"] for r in snapshot()["sports"]}


@pytest.mark.parametrize("body, fields", [
    ({"seed": "42"}, ["seed"]),
    ({"seed": True}, ["seed"]),
    ({"stock": [1]}, ["stock"]),
    ({"stock": {"var-jersey-001-M": -1}}, ["stock.var-jersey-001-M"]),
    ({"stock": {"var-jersey-001-L": 1.5}}, ["stock.var-jersey-001-L"]),
])
def test_reset_validation_errors(client, body, fields):
    r = client.post("/audit/v1/reset", json=body)
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"
    assert r.json()["error"]["details"]["fields"] == fields


def test_reset_malformed_json_is_400(client):
    r = client.post("/audit/v1/reset", content=b"{not json", headers={"Content-Type": "application/json"})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


def test_reset_unknown_variant_is_404(client):
    r = client.post("/audit/v1/reset", json={"stock": {"var-nope": 1}})
    assert r.status_code == 404
    assert r.json()["error"] == {"code": "VARIANT_NOT_FOUND", "message": "Variant var-nope does not exist.",
                                 "details": {"variant_id": "var-nope"}}


def test_health_requires_seed(client):
    from app import db
    client.post("/audit/v1/reset")
    assert client.get("/health").json() == {"status": "ok"}
    with db.engine.begin() as conn:
        conn.execute(text("DELETE FROM users"))
    r = client.get("/health")
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "UNAVAILABLE"
    client.post("/audit/v1/reset")
    assert client.get("/health").status_code == 200
