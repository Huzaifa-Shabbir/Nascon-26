"""POST /audit/v1/offline-sync — replay queued mobile actions (§5.14).

Always HTTP 200 for a valid envelope; per-action conflicts are in results.
"""
from __future__ import annotations

import json
from typing import Any

from fastapi import APIRouter, Body
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app import db
from app.errors import ApiError, validation_error
from app.roster import roster_transfer
from app.scoring import append_event, _request_hash, _normalize_body

router = APIRouter()

ACTION_TYPES = {"score_event", "roster_transfer"}


def _json_content(resp) -> tuple[int, dict]:
    if isinstance(resp, JSONResponse):
        body = resp.body
        if isinstance(body, (bytes, bytearray)):
            data = json.loads(body.decode("utf-8"))
        else:
            data = json.loads(body)
        return resp.status_code, data
    if isinstance(resp, dict):
        return 200, resp
    return 200, dict(resp)


def _match_version(match_id: str) -> int | None:
    with db.engine.connect() as conn:
        exists = conn.execute(
            text("SELECT 1 FROM matches WHERE match_id = :id"), {"id": match_id}
        ).first()
        if not exists:
            return None
        n = conn.execute(
            text("SELECT COUNT(*) FROM match_events WHERE match_id = :id"),
            {"id": match_id},
        ).scalar()
        return int(n or 0)


def _player_audit_version(player_id: str) -> int | None:
    with db.engine.connect() as conn:
        # Player known if in any roster scenario
        pl = conn.execute(
            text("SELECT 1 FROM roster_players WHERE player_id = :pid LIMIT 1"),
            {"pid": player_id},
        ).first()
        if not pl:
            return None
        n = conn.execute(
            text("SELECT COUNT(*) FROM roster_audit WHERE player_id = :pid"),
            {"pid": player_id},
        ).scalar()
        return int(n or 0)


def _load_prior(device_id: str, action_id: str) -> dict | None:
    with db.engine.connect() as conn:
        row = conn.execute(
            text(
                "SELECT result_body FROM offline_actions "
                "WHERE device_id = :d AND action_id = :a"
            ),
            {"d": device_id, "a": action_id},
        ).scalar()
    if row is None:
        return None
    return json.loads(row) if isinstance(row, str) else dict(row)


def _store_result(device_id: str, action_id: str, result: dict) -> None:
    with db.engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO offline_actions (device_id, action_id, result_body) "
                "VALUES (:d, :a, CAST(:b AS JSONB)) "
                "ON CONFLICT (device_id, action_id) DO NOTHING"
            ),
            {"d": device_id, "a": action_id, "b": json.dumps(result)},
        )


def _event_idempotent_duplicate(payload: dict) -> bool | None:
    """True if same event_id+body exists; False if conflict; None if new."""
    norm = _normalize_body(payload)
    eid = norm.get("event_id")
    if not isinstance(eid, str):
        return None
    req_hash = _request_hash(norm)
    with db.engine.connect() as conn:
        row = conn.execute(
            text(
                "SELECT request_hash FROM match_events WHERE event_id = :id"
            ),
            {"id": eid},
        ).mappings().first()
    if row is None:
        return None
    return row["request_hash"] == req_hash


def _process_score(action: dict, base_version: int) -> dict:
    payload = action["payload"]
    match_id = payload.get("match_id") if isinstance(payload, dict) else None

    # Identical event already stored → duplicate (before version checks matters for re-sync)
    dup = _event_idempotent_duplicate(payload) if isinstance(payload, dict) else None
    if dup is True:
        ver = _match_version(match_id) if isinstance(match_id, str) else 0
        return {
            "status": "duplicate",
            "resolution": "skipped_duplicate",
            "error_code": None,
            "server_version": ver or 0,
            "signature": None,
        }
    if dup is False:
        ver = _match_version(match_id) if isinstance(match_id, str) else 0
        return {
            "status": "rejected",
            "resolution": "server_wins",
            "error_code": "DUPLICATE_EVENT_ID",
            "server_version": ver or 0,
            "signature": None,
        }

    if not isinstance(match_id, str):
        return {
            "status": "rejected",
            "resolution": "server_wins",
            "error_code": "VALIDATION_ERROR",
            "server_version": 0,
            "signature": None,
        }

    current = _match_version(match_id)
    if current is None:
        return {
            "status": "rejected",
            "resolution": "server_wins",
            "error_code": "MATCH_NOT_FOUND",
            "server_version": 0,
            "signature": None,
        }

    if base_version > current:
        return {
            "status": "rejected",
            "resolution": "server_wins",
            "error_code": "INVALID_BASE_VERSION",
            "server_version": current,
            "signature": None,
        }

    try:
        resp = append_event(payload)
        code, body = _json_content(resp)
    except ApiError as e:
        return {
            "status": "rejected",
            "resolution": "server_wins",
            "error_code": e.code,
            "server_version": _match_version(match_id) or current,
            "signature": None,
        }

    if code == 200:
        # Replay of identical event through append_event
        return {
            "status": "duplicate",
            "resolution": "skipped_duplicate",
            "error_code": None,
            "server_version": body.get("match_version", current),
            "signature": None,
        }

    new_ver = body.get("match_version", current + 1)
    resolution = "appended" if base_version == current else "rebased_append"
    return {
        "status": "applied",
        "resolution": resolution,
        "error_code": None,
        "server_version": new_ver,
        "signature": body.get("signature"),
    }


def _process_roster(action: dict, base_version: int) -> dict:
    payload = action["payload"]
    if not isinstance(payload, dict):
        return {
            "status": "rejected",
            "resolution": "server_wins",
            "error_code": "VALIDATION_ERROR",
            "server_version": 0,
            "signature": None,
        }
    player_id = payload.get("player_id")
    if not isinstance(player_id, str):
        return {
            "status": "rejected",
            "resolution": "server_wins",
            "error_code": "VALIDATION_ERROR",
            "server_version": 0,
            "signature": None,
        }

    current = _player_audit_version(player_id)
    if current is None:
        return {
            "status": "rejected",
            "resolution": "server_wins",
            "error_code": "PLAYER_NOT_FOUND",
            "server_version": 0,
            "signature": None,
        }

    if base_version > current:
        return {
            "status": "rejected",
            "resolution": "server_wins",
            "error_code": "INVALID_BASE_VERSION",
            "server_version": current,
            "signature": None,
        }

    # Idempotent request_id already accepted → treat as duplicate
    rid = payload.get("request_id")
    if isinstance(rid, str):
        with db.engine.connect() as conn:
            prev = conn.execute(
                text("SELECT 1 FROM roster_requests WHERE request_id = :id"),
                {"id": rid},
            ).first()
        if prev:
            return {
                "status": "duplicate",
                "resolution": "skipped_duplicate",
                "error_code": None,
                "server_version": current,
                "signature": None,
            }

    try:
        resp = roster_transfer(payload)
        code, _body = _json_content(resp)
    except ApiError as e:
        return {
            "status": "rejected",
            "resolution": "server_wins",
            "error_code": e.code,
            "server_version": _player_audit_version(player_id) or current,
            "signature": None,
        }

    new_ver = _player_audit_version(player_id) or current
    if code == 200:
        return {
            "status": "duplicate",
            "resolution": "skipped_duplicate",
            "error_code": None,
            "server_version": new_ver,
            "signature": None,
        }

    resolution = "appended" if base_version == current else "rebased_append"
    return {
        "status": "applied",
        "resolution": resolution,
        "error_code": None,
        "server_version": new_ver,
        "signature": None,
    }


@router.post("/audit/v1/offline-sync")
def offline_sync(body: dict | None = Body(default=None)):
    body = body if isinstance(body, dict) else {}
    device_id = body.get("device_id")
    actions = body.get("actions")
    fields: list[str] = []
    if not isinstance(device_id, str) or not device_id:
        fields.append("device_id")
    if not isinstance(actions, list) or not (1 <= len(actions) <= 100):
        fields.append("actions")
    if fields:
        raise validation_error(fields)

    assert isinstance(device_id, str)
    assert isinstance(actions, list)

    # Validate each action shape lightly; bad types → 400 envelope
    for i, act in enumerate(actions):
        if not isinstance(act, dict):
            raise validation_error([f"actions.{i}"])
        if not isinstance(act.get("action_id"), str) or not act.get("action_id"):
            raise validation_error([f"actions.{i}.action_id"])
        if not isinstance(act.get("type"), str) or act.get("type") not in ACTION_TYPES:
            raise validation_error([f"actions.{i}.type"])
        if not isinstance(act.get("queued_at"), str) or not act.get("queued_at"):
            raise validation_error([f"actions.{i}.queued_at"])
        if not isinstance(act.get("base_version"), int) or isinstance(act.get("base_version"), bool):
            raise validation_error([f"actions.{i}.base_version"])
        if not isinstance(act.get("payload"), dict):
            raise validation_error([f"actions.{i}.payload"])

    # Sort by queued_at, ties keep array order (stable sort with original index)
    indexed = list(enumerate(actions))
    indexed.sort(key=lambda pair: (pair[1]["queued_at"], pair[0]))

    # Map action_id → result; also track processing order
    by_id: dict[str, dict] = {}
    processed_order = 0

    for _orig_i, act in indexed:
        processed_order += 1
        aid = act["action_id"]

        prior = _load_prior(device_id, aid)
        if prior is not None:
            result = {
                "action_id": aid,
                "status": "duplicate",
                "resolution": "skipped_duplicate",
                "error_code": None,
                "processed_order": processed_order,
                "server_version": prior.get("server_version", 0),
                "signature": None,
            }
            by_id[aid] = result
            continue

        base = act["base_version"]
        if act["type"] == "score_event":
            core = _process_score(act, base)
        else:
            core = _process_roster(act, base)

        result = {
            "action_id": aid,
            "processed_order": processed_order,
            **core,
        }
        # Persist only terminal outcomes so re-send is duplicate
        _store_result(device_id, aid, result)
        by_id[aid] = result

    # Results in request order
    results = []
    for act in actions:
        results.append(by_id[act["action_id"]])

    summary = {
        "applied": sum(1 for r in results if r["status"] == "applied"),
        "rejected": sum(1 for r in results if r["status"] == "rejected"),
        "duplicate": sum(1 for r in results if r["status"] == "duplicate"),
    }
    return {
        "device_id": device_id,
        "results": results,
        "summary": summary,
    }
