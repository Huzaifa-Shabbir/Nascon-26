"""Store inventory + checkout (spec §5.12 / NFR-3). Requires TEST_DATABASE_URL."""
from __future__ import annotations

import base64
import io
from concurrent.futures import ThreadPoolExecutor, as_completed

import pytest
from fastapi.testclient import TestClient
from pypdf import PdfReader

from conftest import requires_db

pytestmark = requires_db

VARIANT_M = "var-jersey-001-M"
VARIANT_L = "var-jersey-001-L"


@pytest.fixture(scope="module")
def client():
    from app.main import app
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def _reset_stock(client):
    # Isolated: every test starts from a known disposable DB state via /reset.
    r = client.post("/audit/v1/reset", json={"seed": 42, "stock": {VARIANT_M: 1, VARIANT_L: 5}})
    assert r.status_code == 200


def _checkout(client, order_id="ord-001", variant_id=VARIANT_M, qty=1, token="tok_success",
              discount_code=None, customer_id="cust-001", **extra):
    body = {
        "order_id": order_id,
        "customer_id": customer_id,
        "items": [{"variant_id": variant_id, "quantity": qty}],
        "discount_code": discount_code,
        "payment": {"token": token},
        **extra,
    }
    return client.post("/audit/v1/checkout", json=body), body


def test_inventory_seeded_stock(client):
    r = client.get(f"/audit/v1/inventory/{VARIANT_M}")
    assert r.status_code == 200
    assert r.json() == {"variant_id": VARIANT_M, "stock": 1, "reserved": 0}


def test_inventory_missing_variant(client):
    r = client.get("/audit/v1/inventory/var-nope")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "VARIANT_NOT_FOUND"
    assert r.json()["error"]["details"]["variant_id"] == "var-nope"


def test_checkout_success_receipt_and_pdf(client):
    r, body = _checkout(client, order_id="ord-ok-1")
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["order_id"] == "ord-ok-1"
    assert data["status"] == "paid"
    assert data["currency"] == "PKR"
    assert data["items"] == [
        {"variant_id": VARIANT_M, "quantity": 1, "unit_price_minor": 450000}
    ]
    assert data["subtotal_minor"] == 450000
    assert data["discount_minor"] == 0
    assert data["total_minor"] == 450000
    assert data["payment"]["state"] == "captured"

    payload = data["receipt"]["payload"]
    assert payload["order_id"] == "ord-ok-1"
    assert payload["customer_id"] == "cust-001"
    assert payload["total_minor"] == 450000
    assert payload["currency"] == "PKR"
    assert payload["paid_at"].endswith("Z")

    from app.signing import sign
    assert data["receipt"]["signature"] == sign("ord-ok-1", payload)

    pdf_bytes = base64.b64decode(data["receipt"]["pdf_base64"])
    assert pdf_bytes.startswith(b"%PDF")
    text = "".join(page.extract_text() or "" for page in PdfReader(io.BytesIO(pdf_bytes)).pages)
    assert "ord-ok-1" in text
    assert "PKR 4500.00" in text

    inv = client.get(f"/audit/v1/inventory/{VARIANT_M}").json()
    assert inv == {"variant_id": VARIANT_M, "stock": 0, "reserved": 0}


def test_checkout_welcome10_discount(client):
    client.post("/audit/v1/reset", json={"stock": {VARIANT_M: 2}})
    r, _ = _checkout(client, order_id="ord-disc", discount_code="WELCOME10")
    assert r.status_code == 201
    data = r.json()
    assert data["subtotal_minor"] == 450000
    assert data["discount_minor"] == 45000  # floor(450000 * 10 / 100)
    assert data["total_minor"] == 405000
    pdf_bytes = base64.b64decode(data["receipt"]["pdf_base64"])
    text = "".join(page.extract_text() or "" for page in PdfReader(io.BytesIO(pdf_bytes)).pages)
    assert "PKR 4050.00" in text


def test_checkout_invalid_discount(client):
    r, _ = _checkout(client, order_id="ord-bad-disc", discount_code="NOPE")
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "INVALID_DISCOUNT_CODE"


def test_checkout_validation_errors(client):
    r = client.post("/audit/v1/checkout", json={})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"
    fields = r.json()["error"]["details"]["fields"]
    assert "order_id" in fields
    assert "customer_id" in fields
    assert "items" in fields
    assert "payment" in fields


def test_checkout_missing_variant(client):
    r, _ = _checkout(client, order_id="ord-miss", variant_id="var-missing")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "VARIANT_NOT_FOUND"


def test_checkout_out_of_stock(client):
    r1, _ = _checkout(client, order_id="ord-a")
    assert r1.status_code == 201
    r2, _ = _checkout(client, order_id="ord-b")
    assert r2.status_code == 409
    assert r2.json()["error"] == {
        "code": "OUT_OF_STOCK",
        "message": f"Variant {VARIANT_M} has no stock left.",
        "details": {"variant_id": VARIANT_M},
    }


def test_payment_declined_rolls_back_stock(client):
    before = client.get(f"/audit/v1/inventory/{VARIANT_M}").json()
    r, _ = _checkout(client, order_id="ord-dec", token="tok_declined")
    assert r.status_code == 402
    assert r.json()["error"]["code"] == "PAYMENT_DECLINED"
    after = client.get(f"/audit/v1/inventory/{VARIANT_M}").json()
    assert after == before
    # Stock must still be purchasable.
    ok, _ = _checkout(client, order_id="ord-after-decline")
    assert ok.status_code == 201


def test_payment_capture_fail_rolls_back_stock(client):
    before = client.get(f"/audit/v1/inventory/{VARIANT_M}").json()
    r, _ = _checkout(client, order_id="ord-cap", token="tok_capture_fail")
    assert r.status_code == 402
    assert r.json()["error"]["code"] == "PAYMENT_CAPTURE_FAILED"
    assert client.get(f"/audit/v1/inventory/{VARIANT_M}").json() == before


def test_idempotent_replay_returns_200(client):
    r1, body = _checkout(client, order_id="ord-idem")
    assert r1.status_code == 201
    r2 = client.post("/audit/v1/checkout", json=body)
    assert r2.status_code == 200
    assert r2.json()["order_id"] == "ord-idem"
    # No second stock deduction.
    assert client.get(f"/audit/v1/inventory/{VARIANT_M}").json()["stock"] == 0


def test_duplicate_order_id_different_body(client):
    r1, _ = _checkout(client, order_id="ord-dup", customer_id="cust-1")
    assert r1.status_code == 201
    # Idempotency check runs before stock; different body with same id → 409.
    r2, _ = _checkout(client, order_id="ord-dup", customer_id="cust-2")
    assert r2.status_code == 409
    assert r2.json()["error"]["code"] == "DUPLICATE_ORDER_ID"


def test_checkout_no_auth_required(client):
    """Spec §5.2: /audit/v1/* needs no Authorization except RBAC probes."""
    r, _ = _checkout(client, order_id="ord-noauth")
    assert r.status_code == 201


def test_nfr3_twenty_buyers_one_unit(client):
    """NFR-3: 20 parallel buyers, stock=1 → exactly one 201 and nineteen 409."""
    client.post("/audit/v1/reset", json={"stock": {VARIANT_M: 1, VARIANT_L: 5}})

    def buy(i: int):
        return client.post(
            "/audit/v1/checkout",
            json={
                "order_id": f"ord-burst-{i}",
                "customer_id": f"cust-{i}",
                "items": [{"variant_id": VARIANT_M, "quantity": 1}],
                "discount_code": None,
                "payment": {"token": "tok_success"},
            },
        ).status_code

    with ThreadPoolExecutor(max_workers=20) as pool:
        codes = list(pool.map(buy, range(20)))

    assert codes.count(201) == 1, codes
    assert codes.count(409) == 19, codes
    inv = client.get(f"/audit/v1/inventory/{VARIANT_M}").json()
    assert inv["stock"] == 0
    assert inv["reserved"] == 0
    assert inv["stock"] >= 0


def test_script_injection_customer_id_is_plain_data(client):
    nasty = "x'; DROP TABLE variants;--"
    r, _ = _checkout(client, order_id="ord-sql", customer_id=nasty)
    assert r.status_code == 201
    assert r.json()["receipt"]["payload"]["customer_id"] == nasty
    # Table still exists.
    assert client.get(f"/audit/v1/inventory/{VARIANT_L}").status_code == 200
