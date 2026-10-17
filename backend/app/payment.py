"""In-process mock payment gateway (ADR-6 / spec §5.12)."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class PaymentResult:
    ok: bool
    error_code: str | None = None
    authorization_id: str | None = None
    capture_id: str | None = None
    state: str | None = None


def charge(token: str, order_id: str) -> PaymentResult:
    if token == "tok_success":
        return PaymentResult(
            ok=True,
            authorization_id=f"auth_{order_id}",
            capture_id=f"cap_{order_id}",
            state="captured",
        )
    if token == "tok_declined":
        return PaymentResult(ok=False, error_code="PAYMENT_DECLINED")
    if token == "tok_capture_fail":
        return PaymentResult(ok=False, error_code="PAYMENT_CAPTURE_FAILED")
    return PaymentResult(ok=False, error_code="VALIDATION_ERROR")
