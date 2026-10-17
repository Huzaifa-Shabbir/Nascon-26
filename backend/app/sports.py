"""POST /audit/v1/sports — mystery sport from JSON (spec §5.6)."""
from __future__ import annotations

import json
import re

from fastapi import APIRouter, Body
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app import db
from app.errors import ApiError, validation_error

router = APIRouter()

SPORT_ID_RE = re.compile(r"^[a-z0-9_-]{2,40}$")
EVENT_KEY_RE = re.compile(r"^[a-z0-9_]{1,40}$")
MODELS = {"event", "innings", "round"}
OVERTIME_POLICIES = {"none", "extra_time", "shootout", "golden_score", "super_over"}
TIE_TOKENS = ["h2h_points", "h2h_diff", "overall_diff", "scored", "fair_play", "draw_lots"]
TIE_SET = set(TIE_TOKENS)


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _is_bool(v) -> bool:
    return isinstance(v, bool)


@router.post("/audit/v1/sports")
def create_sport(body: dict | None = Body(default=None)):
    body = body if isinstance(body, dict) else {}
    fields: list[str] = []

    sport_id = body.get("sport_id")
    name = body.get("name")
    scoring_model = body.get("scoring_model")
    periods = body.get("periods")
    scoring_events = body.get("scoring_events")
    draw_allowed = body.get("draw_allowed")
    overtime = body.get("overtime")
    roster = body.get("roster")
    tie_break_order = body.get("tie_break_order")

    if not isinstance(sport_id, str) or not SPORT_ID_RE.match(sport_id):
        fields.append("sport_id")
    if not isinstance(name, str) or not (1 <= len(name) <= 80):
        fields.append("name")
    if scoring_model not in MODELS:
        fields.append("scoring_model")
    if not isinstance(periods, dict):
        fields.append("periods")
    if not isinstance(scoring_events, dict) or len(scoring_events) < 1:
        fields.append("scoring_events")
    if not _is_bool(draw_allowed):
        fields.append("draw_allowed")
    if not isinstance(overtime, dict):
        fields.append("overtime")
    if not isinstance(roster, dict):
        fields.append("roster")

    if fields:
        raise validation_error(_uniq(fields))

    assert isinstance(periods, dict)
    assert isinstance(scoring_events, dict)
    assert isinstance(overtime, dict)
    assert isinstance(roster, dict)

    # periods by model
    if scoring_model == "event":
        if not _is_int(periods.get("count")) or periods["count"] < 1:
            fields.append("periods.count")
        if not _is_int(periods.get("duration_minutes")) or periods["duration_minutes"] < 1:
            fields.append("periods.duration_minutes")
    elif scoring_model == "innings":
        for k in ("innings_per_team", "overs_per_innings", "balls_per_over", "wickets_per_innings"):
            if not _is_int(periods.get(k)) or periods[k] < 1:
                fields.append(f"periods.{k}")
    else:  # round
        bo = periods.get("best_of")
        if not _is_int(bo) or bo < 1 or bo % 2 == 0:
            fields.append("periods.best_of")

    # scoring_events
    for key, val in scoring_events.items():
        if not isinstance(key, str) or not EVENT_KEY_RE.match(key):
            fields.append(f"scoring_events.{key}")
            continue
        if not isinstance(val, dict):
            fields.append(f"scoring_events.{key}")
            continue
        if scoring_model == "event":
            if not _is_int(val.get("points")) or val["points"] < 1:
                fields.append(f"scoring_events.{key}.points")
        elif scoring_model == "innings":
            if not _is_int(val.get("runs")) or val["runs"] < 0:
                fields.append(f"scoring_events.{key}.runs")
            if not _is_bool(val.get("legal_ball")):
                fields.append(f"scoring_events.{key}.legal_ball")
            if not _is_bool(val.get("wicket")):
                fields.append(f"scoring_events.{key}.wicket")
        else:
            if not _is_int(val.get("rounds")) or val["rounds"] < 1:
                fields.append(f"scoring_events.{key}.rounds")

    # overtime
    policy = overtime.get("policy")
    if policy not in OVERTIME_POLICIES:
        fields.append("overtime.policy")
    if "duration_minutes" in overtime:
        dm = overtime.get("duration_minutes")
        if not _is_int(dm) or dm < 0:
            fields.append("overtime.duration_minutes")

    # roster
    mn = roster.get("min_squad_size")
    mx = roster.get("max_squad_size")
    rp = roster.get("required_positions")
    if not _is_int(mn) or mn < 1:
        fields.append("roster.min_squad_size")
    if not _is_int(mx) or mx < 1:
        fields.append("roster.max_squad_size")
    if _is_int(mn) and _is_int(mx) and mn > mx:
        fields.append("roster.min_squad_size")
    if not isinstance(rp, dict):
        fields.append("roster.required_positions")
    else:
        for pos, cnt in rp.items():
            if not isinstance(pos, str) or not _is_int(cnt) or cnt < 0:
                fields.append(f"roster.required_positions.{pos}")

    # tie_break_order
    if tie_break_order is None:
        order = list(TIE_TOKENS)
    elif not isinstance(tie_break_order, list):
        fields.append("tie_break_order")
        order = []
    else:
        order = []
        seen = set()
        for i, tok in enumerate(tie_break_order):
            if tok not in TIE_SET or tok in seen:
                fields.append(f"tie_break_order.{i}")
            else:
                seen.add(tok)
                order.append(tok)
        # draw_lots always last even if omitted
        order = [t for t in order if t != "draw_lots"] + ["draw_lots"]

    if fields:
        raise validation_error(_uniq(fields))

    config = {
        "sport_id": sport_id,
        "name": name,
        "scoring_model": scoring_model,
        "periods": periods,
        "scoring_events": scoring_events,
        "draw_allowed": draw_allowed,
        "overtime": overtime,
        "tie_break_order": order,
        "roster": {
            "min_squad_size": mn,
            "max_squad_size": mx,
            "required_positions": rp,
        },
    }

    with db.engine.begin() as conn:
        exists = conn.execute(
            text("SELECT 1 FROM sports WHERE sport_id = :id"), {"id": sport_id}
        ).first()
        if exists:
            raise ApiError(409, "SPORT_EXISTS", f"Sport {sport_id} already exists.",
                           {"sport_id": sport_id})
        conn.execute(
            text("INSERT INTO sports (sport_id, config) VALUES (:id, CAST(:cfg AS JSONB))"),
            {"id": sport_id, "cfg": json.dumps(config)},
        )

    return JSONResponse(
        status_code=201,
        content={"sport_id": sport_id, "status": "created", "config": config},
    )


def _uniq(fields: list[str]) -> list[str]:
    out = []
    for f in fields:
        if f not in out:
            out.append(f)
    return out
