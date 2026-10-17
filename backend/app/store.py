"""Checkout and inventory (spec §5.12 / NFR-3).

/audit/v1/* needs no auth (except RBAC probes). Stock is reserved atomically
with UPDATE … WHERE stock >= q inside a single transaction so concurrent
buyers cannot oversell.
"""
from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone

from fastapi import APIRouter, Body
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from app import db, events_queue, payment, receipts
from app.errors import ApiError, validation_error
from app.signing import canonical, sign

router = APIRouter()

ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,64}$")


class _IdempotentReplay(Exception):
    def __init__(self, response: dict):
        self.response = response


def _utcnow_z() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _request_fingerprint(body: dict) -> str:
    return hashlib.sha256(canonical(body).encode("utf-8")).hexdigest()


def _normalize_checkout_body(body: dict) -> dict:
    return {
        "order_id": body.get("order_id"),
        "customer_id": body.get("customer_id"),
        "items": body.get("items"),
        "discount_code": body.get("discount_code"),
        "payment": body.get("payment"),
    }


def _load_order(conn, order_id: str):
    return conn.execute(
        text("SELECT request_hash, response_body FROM orders WHERE order_id = :id"),
        {"id": order_id},
    ).mappings().first()


@router.get("/audit/v1/inventory/{variant_id}")
def get_inventory(variant_id: str):
    with db.engine.connect() as conn:
        row = conn.execute(
            text("SELECT variant_id, stock, reserved FROM variants WHERE variant_id = :id"),
            {"id": variant_id},
        ).mappings().first()
    if row is None:
        raise ApiError(
            404,
            "VARIANT_NOT_FOUND",
            f"Variant {variant_id} does not exist.",
            {"variant_id": variant_id},
        )
    return {"variant_id": row["variant_id"], "stock": row["stock"], "reserved": row["reserved"]}


@router.post("/audit/v1/checkout")
def checkout(body: dict | None = Body(default=None)):
    body = body if isinstance(body, dict) else {}
    normalized = _normalize_checkout_body(body)
    fields: list[str] = []

    order_id = normalized.get("order_id")
    if not isinstance(order_id, str) or not order_id or not ID_RE.match(order_id):
        fields.append("order_id")

    customer_id = normalized.get("customer_id")
    if not isinstance(customer_id, str) or not customer_id:
        fields.append("customer_id")

    items = normalized.get("items")
    if not isinstance(items, list) or not (1 <= len(items) <= 10):
        fields.append("items")
    else:
        seen: set[str] = set()
        for i, item in enumerate(items):
            if not isinstance(item, dict):
                fields.append(f"items.{i}")
                continue
            vid = item.get("variant_id")
            qty = item.get("quantity")
            if not isinstance(vid, str) or not vid or not ID_RE.match(vid):
                fields.append(f"items.{i}.variant_id")
            elif vid in seen:
                fields.append(f"items.{i}.variant_id")
            else:
                seen.add(vid)
            if not _is_int(qty) or qty < 1 or qty > 10:
                fields.append(f"items.{i}.quantity")

    discount_code = normalized.get("discount_code")
    if discount_code is not None and not isinstance(discount_code, str):
        fields.append("discount_code")

    pay = normalized.get("payment")
    if not isinstance(pay, dict):
        fields.append("payment")
    else:
        token = pay.get("token")
        if not isinstance(token, str) or not token:
            fields.append("payment.token")

    if fields:
        uniq: list[str] = []
        for f in fields:
            if f not in uniq:
                uniq.append(f)
        raise validation_error(uniq)

    assert isinstance(order_id, str)
    assert isinstance(customer_id, str)
    assert isinstance(items, list)
    assert isinstance(pay, dict)
    token = pay["token"]
    if token not in ("tok_success", "tok_declined", "tok_capture_fail"):
        raise validation_error(["payment.token"], "Unknown payment token.")

    req_hash = _request_fingerprint(normalized)

    with db.engine.connect() as conn:
        existing = _load_order(conn, order_id)
    if existing is not None:
        if existing["request_hash"] == req_hash:
            return JSONResponse(status_code=200, content=existing["response_body"])
        raise ApiError(
            409,
            "DUPLICATE_ORDER_ID",
            f"Order {order_id} already exists with a different body.",
            {"order_id": order_id},
        )

    # Validate → variants exist (404) → discount code (400).
    variant_ids = [it["variant_id"] for it in items]
    with db.engine.connect() as conn:
        rows = conn.execute(
            text("SELECT variant_id, price_minor FROM variants WHERE variant_id = ANY(:ids)"),
            {"ids": variant_ids},
        ).mappings().all()
    found = {r["variant_id"]: r for r in rows}
    for vid in variant_ids:
        if vid not in found:
            raise ApiError(
                404,
                "VARIANT_NOT_FOUND",
                f"Variant {vid} does not exist.",
                {"variant_id": vid},
            )

    percent = 0
    if discount_code is not None:
        with db.engine.connect() as conn:
            row = conn.execute(
                text("SELECT percent FROM discount_codes WHERE code = :c"),
                {"c": discount_code},
            ).mappings().first()
        if row is None:
            raise ApiError(
                400,
                "INVALID_DISCOUNT_CODE",
                f"Discount code {discount_code} is not valid.",
                {"discount_code": discount_code},
            )
        percent = int(row["percent"])

    priced_items = [
        {
            "variant_id": it["variant_id"],
            "quantity": it["quantity"],
            "unit_price_minor": int(found[it["variant_id"]]["price_minor"]),
        }
        for it in items
    ]
    subtotal_minor = sum(p["unit_price_minor"] * p["quantity"] for p in priced_items)
    discount_minor = (subtotal_minor * percent) // 100 if percent else 0
    total_minor = subtotal_minor - discount_minor

    response: dict | None = None
    try:
        with db.engine.begin() as conn:
            # Serialize checkouts that share an order_id (idempotent replay race).
            conn.execute(
                text("SELECT pg_advisory_xact_lock(hashtextextended(:oid, 0))"),
                {"oid": order_id},
            )
            existing = _load_order(conn, order_id)
            if existing is not None:
                if existing["request_hash"] == req_hash:
                    response = existing["response_body"]
                    # Marker: replay inside txn — return 200 below without re-charging.
                    raise _IdempotentReplay(response)
                raise ApiError(
                    409,
                    "DUPLICATE_ORDER_ID",
                    f"Order {order_id} already exists with a different body.",
                    {"order_id": order_id},
                )

            for vid in sorted(set(variant_ids)):
                conn.execute(
                    text("SELECT variant_id FROM variants WHERE variant_id = :id FOR UPDATE"),
                    {"id": vid},
                )

            for it in items:
                vid, qty = it["variant_id"], it["quantity"]
                result = conn.execute(
                    text(
                        "UPDATE variants SET stock = stock - :q, reserved = reserved + :q "
                        "WHERE variant_id = :id AND stock >= :q"
                    ),
                    {"id": vid, "q": qty},
                )
                if result.rowcount != 1:
                    raise ApiError(
                        409,
                        "OUT_OF_STOCK",
                        f"Variant {vid} has no stock left.",
                        {"variant_id": vid},
                    )

            pay_result = payment.charge(token, order_id)
            if not pay_result.ok:
                code = pay_result.error_code or "PAYMENT_DECLINED"
                raise ApiError(402, code, f"Payment failed: {code}.")

            for it in items:
                conn.execute(
                    text(
                        "UPDATE variants SET reserved = reserved - :q "
                        "WHERE variant_id = :id AND reserved >= :q"
                    ),
                    {"id": it["variant_id"], "q": it["quantity"]},
                )

            paid_at = _utcnow_z()
            receipt_payload = {
                "order_id": order_id,
                "customer_id": customer_id,
                "items": priced_items,
                "subtotal_minor": subtotal_minor,
                "discount_minor": discount_minor,
                "total_minor": total_minor,
                "currency": "PKR",
                "paid_at": paid_at,
            }
            signature = sign(order_id, receipt_payload)
            pdf_b64 = receipts.pdf_base64(
                order_id=order_id,
                total_minor=total_minor,
                customer_id=customer_id,
            )

            response = {
                "order_id": order_id,
                "status": "paid",
                "currency": "PKR",
                "items": priced_items,
                "subtotal_minor": subtotal_minor,
                "discount_minor": discount_minor,
                "total_minor": total_minor,
                "payment": {
                    "authorization_id": pay_result.authorization_id,
                    "capture_id": pay_result.capture_id,
                    "state": pay_result.state,
                },
                "receipt": {
                    "payload": receipt_payload,
                    "signature": signature,
                    "pdf_base64": pdf_b64,
                },
            }

            conn.execute(
                text(
                    "INSERT INTO orders (order_id, request_hash, request_body, response_body, status) "
                    "VALUES (:id, :hash, CAST(:req AS JSONB), CAST(:resp AS JSONB), :status)"
                ),
                {
                    "id": order_id,
                    "hash": req_hash,
                    "req": json.dumps(normalized),
                    "resp": json.dumps(response),
                    "status": "paid",
                },
            )
            conn.execute(
                text(
                    "INSERT INTO domain_events (event_type, payload) "
                    "VALUES (:t, CAST(:p AS JSONB))"
                ),
                {
                    "t": "order.status_changed",
                    "p": json.dumps(
                        {"order_id": order_id, "status": "paid", "from_status": "pending"}
                    ),
                },
            )
    except _IdempotentReplay as replay:
        return JSONResponse(status_code=200, content=replay.response)
    except ApiError:
        raise
    except IntegrityError:
        with db.engine.connect() as conn:
            existing = _load_order(conn, order_id)
        if existing is None:
            raise
        if existing["request_hash"] == req_hash:
            return JSONResponse(status_code=200, content=existing["response_body"])
        raise ApiError(
            409,
            "DUPLICATE_ORDER_ID",
            f"Order {order_id} already exists with a different body.",
            {"order_id": order_id},
        )

    assert response is not None
    events_queue.emit(
        "order.status_changed",
        {"order_id": order_id, "status": "paid", "from_status": "pending"},
    )
    return JSONResponse(status_code=201, content=response)
