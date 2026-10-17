from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_ping():
    r = client.get("/api/v1/ping")
    assert r.status_code == 200
    assert r.json() == {"pong": True}


def test_payload_too_large():
    r = client.post("/audit/v1/sports", content=b"x" * (1024 * 1024 + 1),
                    headers={"Content-Type": "application/json"})
    assert r.status_code == 413
    assert r.json()["error"]["code"] == "PAYLOAD_TOO_LARGE"


def test_unknown_route_uses_error_body():
    r = client.get("/does-not-exist")
    assert r.status_code == 404
    body = r.json()["error"]
    assert set(body) == {"code", "message", "details"}
