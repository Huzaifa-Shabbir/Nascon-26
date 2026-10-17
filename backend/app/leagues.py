"""POST /audit/v1/leagues — register a league and create upcoming match streams (§5.8).

Each fixture becomes a match row consumed by /events and /score. Needed so scoring
can run against league-backed streams as well as match_init.
"""
from __future__ import annotations

import json
import re

from fastapi import APIRouter, Body
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app import db
from app.errors import ApiError, validation_error

router = APIRouter()

ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,64}$")
TIE_TOKENS = {"h2h_points", "h2h_diff", "overall_diff", "scored", "fair_play", "draw_lots"}


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


@router.post("/audit/v1/leagues")
def register_league(body: dict | None = Body(default=None)):
    body = body if isinstance(body, dict) else {}
    fields: list[str] = []

    league_id = body.get("league_id")
    sport_id = body.get("sport_id")
    teams = body.get("teams")
    fixtures = body.get("fixtures")
    qualification = body.get("qualification")

    if not isinstance(league_id, str) or not league_id or not ID_RE.match(league_id):
        fields.append("league_id")
    if not isinstance(sport_id, str) or not sport_id:
        fields.append("sport_id")
    if not isinstance(teams, list) or not (2 <= len(teams) <= 40):
        fields.append("teams")
    else:
        seen = set()
        for i, t in enumerate(teams):
            if not isinstance(t, str) or not t or not ID_RE.match(t) or t in seen:
                fields.append(f"teams.{i}")
            else:
                seen.add(t)
    if not isinstance(fixtures, list):
        fields.append("fixtures")
    if not isinstance(qualification, dict) or not _is_int(qualification.get("spots")):
        fields.append("qualification.spots")

    points = body.get("points")
    if points is None:
        points = {"win": 3, "draw": 1, "loss": 0}
    elif not isinstance(points, dict):
        fields.append("points")
    else:
        for k in ("win", "draw", "loss"):
            if k in points and not _is_int(points[k]):
                fields.append(f"points.{k}")
        points = {
            "win": points.get("win", 3),
            "draw": points.get("draw", 1),
            "loss": points.get("loss", 0),
        }

    tie_break_order = body.get("tie_break_order")
    lots_seed = body.get("lots_seed")

    if fields:
        uniq = []
        for f in fields:
            if f not in uniq:
                uniq.append(f)
        raise validation_error(uniq)

    assert isinstance(league_id, str)
    assert isinstance(sport_id, str)
    assert isinstance(teams, list)
    assert isinstance(fixtures, list)
    spots = qualification["spots"]
    if spots < 1 or spots > len(teams):
        raise validation_error(["qualification.spots"])

    team_set = set(teams)
    fixture_ids: set[str] = set()
    normalized_fixtures = []
    for i, fx in enumerate(fixtures):
        if not isinstance(fx, dict):
            raise validation_error([f"fixtures.{i}"])
        mid = fx.get("match_id")
        home = fx.get("home")
        away = fx.get("away")
        if not isinstance(mid, str) or not mid or not ID_RE.match(mid):
            raise validation_error([f"fixtures.{i}.match_id"])
        if mid in fixture_ids:
            raise validation_error([f"fixtures.{i}.match_id"])
        fixture_ids.add(mid)
        if (not isinstance(home, str) or not isinstance(away, str)
                or home not in team_set or away not in team_set or home == away):
            raise validation_error([f"fixtures.{i}"])
        normalized_fixtures.append({"match_id": mid, "home": home, "away": away})

    with db.engine.connect() as conn:
        sport = conn.execute(
            text("SELECT sport_id, config FROM sports WHERE sport_id = :id"),
            {"id": sport_id},
        ).mappings().first()
    if sport is None:
        raise ApiError(404, "SPORT_NOT_FOUND", f"Sport {sport_id} does not exist.",
                       {"sport_id": sport_id})

    sport_cfg = sport["config"]
    if isinstance(sport_cfg, str):
        sport_cfg = json.loads(sport_cfg)

    if tie_break_order is None:
        tie_break_order = list(sport_cfg.get("tie_break_order") or [
            "h2h_points", "h2h_diff", "overall_diff", "scored", "fair_play", "draw_lots"
        ])
    elif not isinstance(tie_break_order, list) or any(
        t not in TIE_TOKENS for t in tie_break_order
    ) or len(tie_break_order) != len(set(tie_break_order)):
        raise validation_error(["tie_break_order"])

    if lots_seed is None:
        with db.engine.connect() as conn:
            row = conn.execute(
                text("SELECT value FROM app_meta WHERE key = 'lots_seed'")
            ).scalar()
        lots_seed = int(row) if row is not None else 42
    elif not _is_int(lots_seed):
        raise validation_error(["lots_seed"])

    config = {
        "teams": teams,
        "fixtures": normalized_fixtures,
        "points": points,
        "tie_break_order": tie_break_order,
        "qualification": {"spots": spots},
        "lots_seed": lots_seed,
    }

    try:
        with db.engine.begin() as conn:
            exists = conn.execute(
                text("SELECT 1 FROM leagues WHERE league_id = :id"), {"id": league_id}
            ).first()
            if exists:
                raise ApiError(409, "LEAGUE_EXISTS", f"League {league_id} already exists.",
                               {"league_id": league_id})

            for fx in normalized_fixtures:
                if conn.execute(
                    text("SELECT 1 FROM matches WHERE match_id = :id"),
                    {"id": fx["match_id"]},
                ).first():
                    raise ApiError(
                        409, "MATCH_EXISTS", f"Match {fx['match_id']} already exists.",
                        {"match_id": fx["match_id"]},
                    )

            conn.execute(
                text(
                    "INSERT INTO leagues (league_id, tenant_id, sport_id, name, config) "
                    "VALUES (:id, NULL, :sport, :name, CAST(:cfg AS JSONB))"
                ),
                {
                    "id": league_id,
                    "sport": sport_id,
                    "name": league_id,
                    "cfg": json.dumps(config),
                },
            )
            for fx in normalized_fixtures:
                conn.execute(
                    text(
                        "INSERT INTO matches (match_id, sport_id, league_id, home_team_id, away_team_id) "
                        "VALUES (:mid, :sport, :lid, :home, :away)"
                    ),
                    {
                        "mid": fx["match_id"],
                        "sport": sport_id,
                        "lid": league_id,
                        "home": fx["home"],
                        "away": fx["away"],
                    },
                )
    except ApiError:
        raise

    return JSONResponse(
        status_code=201,
        content={
            "league_id": league_id,
            "status": "created",
            "team_count": len(teams),
            "fixture_count": len(normalized_fixtures),
        },
    )
