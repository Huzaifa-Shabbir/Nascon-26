"""POST /audit/v1/reset (spec 5.5)."""
from fastapi import APIRouter, Body

from app import db, seed
from app.errors import ApiError, validation_error

router = APIRouter()


def _is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


@router.post("/audit/v1/reset")
def reset(body: dict | None = Body(default=None)):
    body = body or {}
    fields = []

    lots_seed = body.get("seed")
    if lots_seed is None:
        lots_seed = seed.DEFAULT_SEED
    elif not _is_int(lots_seed):
        fields.append("seed")

    stock = body.get("stock")
    if stock is None:
        stock = {}
    elif not isinstance(stock, dict):
        fields.append("stock")
    else:
        fields += [f"stock.{k}" for k, v in stock.items() if not _is_int(v) or v < 0]

    if fields:
        raise validation_error(fields)

    known = {v["variant_id"] for v in seed.VARIANTS}
    for variant_id in stock:
        if variant_id not in known:
            raise ApiError(404, "VARIANT_NOT_FOUND", f"Variant {variant_id} does not exist.",
                           {"variant_id": variant_id})

    with db.engine.begin() as conn:
        return seed.reset_state(conn, lots_seed, stock)
