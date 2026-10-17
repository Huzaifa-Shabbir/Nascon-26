"""Event-sourced scoring: POST /audit/v1/events + GET /audit/v1/score/{match_id} (§5.9).

Scores are always rebuilt from the append-only log. Compensations never mutate
prior rows; compensated events and compensations are neutral in the projection.
"""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

from fastapi import APIRouter, Body
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from app import db
from app.errors import ApiError, validation_error
from app.signing import canonical, sign

router = APIRouter()

ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,64}$")
EVENT_TYPES = {
    "match_init",
    "match_start",
    "score",
    "discipline",
    "tiebreak_winner",
    "match_end",
    "compensation",
}


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _request_hash(body: dict) -> str:
    return hashlib.sha256(canonical(body).encode("utf-8")).hexdigest()


def _normalize_body(body: dict) -> dict:
    return {
        "event_id": body.get("event_id"),
        "match_id": body.get("match_id"),
        "type": body.get("type"),
        "payload": body.get("payload"),
    }


def _load_sport(conn, sport_id: str) -> dict:
    row = conn.execute(
        text("SELECT sport_id, config FROM sports WHERE sport_id = :id"),
        {"id": sport_id},
    ).mappings().first()
    if row is None:
        raise ApiError(404, "SPORT_NOT_FOUND", f"Sport {sport_id} does not exist.",
                       {"sport_id": sport_id})
    cfg = row["config"]
    if isinstance(cfg, str):
        cfg = json.loads(cfg)
    return cfg


def _load_match(conn, match_id: str) -> dict | None:
    row = conn.execute(
        text(
            "SELECT match_id, sport_id, league_id, home_team_id, away_team_id "
            "FROM matches WHERE match_id = :id"
        ),
        {"id": match_id},
    ).mappings().first()
    return dict(row) if row else None


def _load_events(conn, match_id: str) -> list[dict]:
    rows = conn.execute(
        text(
            "SELECT event_id, type, payload, sequence, signature "
            "FROM match_events WHERE match_id = :id ORDER BY sequence"
        ),
        {"id": match_id},
    ).mappings().all()
    out = []
    for r in rows:
        payload = r["payload"]
        if isinstance(payload, str):
            payload = json.loads(payload)
        out.append(
            {
                "event_id": r["event_id"],
                "type": r["type"],
                "payload": payload,
                "sequence": r["sequence"],
                "signature": r["signature"],
            }
        )
    return out


def project_match(match: dict, events: list[dict], sport: dict) -> dict:
    """Rebuild status, scores, and outcome from the event log."""
    compensated_by: dict[str, str] = {}
    for ev in events:
        if ev["type"] == "compensation":
            target = ev["payload"].get("compensates")
            if target:
                compensated_by[target] = ev["event_id"]

    def active(ev: dict) -> bool:
        if ev["type"] == "compensation":
            return False
        return ev["event_id"] not in compensated_by

    home_id = match["home_team_id"]
    away_id = match["away_team_id"]
    model = sport.get("scoring_model")
    periods = sport.get("periods") or {}
    scoring_events = sport.get("scoring_events") or {}
    draw_allowed = bool(sport.get("draw_allowed"))

    scores = {home_id: 0, away_id: 0}
    fair_play = {home_id: 0, away_id: 0}
    wickets = {home_id: 0, away_id: 0}
    balls = {home_id: 0, away_id: 0}
    tiebreak_winner: str | None = None
    started = False
    ended = False

    for ev in events:
        if not active(ev):
            continue
        t = ev["type"]
        p = ev["payload"] or {}
        if t == "match_start":
            started = True
        elif t == "match_end":
            ended = True
        elif t == "score":
            team = p.get("team_id")
            et = p.get("event_type")
            cfg = scoring_events.get(et) or {}
            if model == "event":
                scores[team] = scores.get(team, 0) + int(cfg.get("points", 0))
            elif model == "innings":
                scores[team] = scores.get(team, 0) + int(cfg.get("runs", 0))
                if cfg.get("legal_ball"):
                    balls[team] = balls.get(team, 0) + 1
                if cfg.get("wicket"):
                    wickets[team] = wickets.get(team, 0) + 1
            elif model == "round":
                scores[team] = scores.get(team, 0) + int(cfg.get("rounds", 0))
        elif t == "discipline":
            team = p.get("team_id")
            fair_play[team] = fair_play.get(team, 0) + int(p.get("points", 0))
        elif t == "tiebreak_winner":
            tiebreak_winner = p.get("team_id")

    if ended:
        status = "completed"
    elif started:
        status = "in_progress"
    else:
        status = "upcoming"

    hs, aws = scores[home_id], scores[away_id]
    if status != "completed":
        outcome = "pending"
        winner_team_id = None
    elif hs > aws:
        outcome = "home_win"
        winner_team_id = home_id
    elif aws > hs:
        outcome = "away_win"
        winner_team_id = away_id
    elif tiebreak_winner:
        outcome = "home_win" if tiebreak_winner == home_id else "away_win"
        winner_team_id = tiebreak_winner
    elif draw_allowed:
        outcome = "draw"
        winner_team_id = None
    else:
        outcome = "undecided"
        winner_team_id = None

    def side(team_id: str) -> dict:
        if model == "innings":
            bpo = int(periods.get("balls_per_over") or 6)
            b = balls[team_id]
            overs = f"{b // bpo}.{b % bpo}"
            return {
                "team_id": team_id,
                "score": scores[team_id],
                "wickets": wickets[team_id],
                "balls": b,
                "overs": overs,
                "fair_play": fair_play[team_id],
            }
        return {
            "team_id": team_id,
            "score": scores[team_id],
            "wickets": None,
            "balls": None,
            "overs": None,
            "fair_play": fair_play[team_id],
        }

    event_views = []
    for ev in events:
        eid = ev["event_id"]
        event_views.append(
            {
                "sequence": ev["sequence"],
                "event_id": eid,
                "type": ev["type"],
                "payload": ev["payload"],
                "signature": ev["signature"],
                "compensated": eid in compensated_by,
                "compensated_by": compensated_by.get(eid),
            }
        )

    return {
        "match_id": match["match_id"],
        "sport_id": match["sport_id"],
        "league_id": match.get("league_id"),
        "status": status,
        "outcome": outcome,
        "winner_team_id": winner_team_id,
        "tiebreak_winner_team_id": tiebreak_winner,
        "home": side(home_id),
        "away": side(away_id),
        "version": len(events),
        "events": event_views,
        # Internal helpers for append-time checks (stripped before response).
        "_started": started,
        "_ended": ended,
        "_scores": scores,
        "_balls": balls,
        "_wickets": wickets,
        "_tiebreak": tiebreak_winner,
        "_compensated_by": compensated_by,
    }


def _public_score(proj: dict) -> dict:
    return {k: v for k, v in proj.items() if not k.startswith("_")}


def _innings_complete(sport: dict, balls: int, wickets: int) -> bool:
    periods = sport.get("periods") or {}
    innings = int(periods.get("innings_per_team") or 1)
    overs = int(periods.get("overs_per_innings") or 1)
    bpo = int(periods.get("balls_per_over") or 6)
    wickets_cap = int(periods.get("wickets_per_innings") or 10)
    max_balls = innings * overs * bpo
    max_wickets = innings * wickets_cap
    return balls >= max_balls or wickets >= max_wickets


def _series_decided(sport: dict, score: int) -> bool:
    best_of = int((sport.get("periods") or {}).get("best_of") or 1)
    return score >= (best_of + 1) // 2


@router.get("/audit/v1/score/{match_id}")
def get_score(match_id: str):
    with db.engine.connect() as conn:
        match = _load_match(conn, match_id)
        if match is None:
            raise ApiError(404, "MATCH_NOT_FOUND", f"Match {match_id} does not exist.",
                           {"match_id": match_id})
        sport = _load_sport(conn, match["sport_id"])
        events = _load_events(conn, match_id)
    return _public_score(project_match(match, events, sport))


@router.post("/audit/v1/events")
def append_event(body: dict | None = Body(default=None)):
    body = body if isinstance(body, dict) else {}
    normalized = _normalize_body(body)
    fields: list[str] = []

    event_id = normalized.get("event_id")
    match_id = normalized.get("match_id")
    etype = normalized.get("type")
    payload = normalized.get("payload")

    if not isinstance(event_id, str) or not event_id or not ID_RE.match(event_id):
        fields.append("event_id")
    if not isinstance(match_id, str) or not match_id or not ID_RE.match(match_id):
        fields.append("match_id")
    if not isinstance(etype, str) or etype not in EVENT_TYPES:
        fields.append("type")
    if not isinstance(payload, dict):
        fields.append("payload")
    if fields:
        raise validation_error(fields)

    assert isinstance(event_id, str)
    assert isinstance(match_id, str)
    assert isinstance(etype, str)
    assert isinstance(payload, dict)

    req_hash = _request_hash(normalized)

    # Global idempotency by event_id.
    with db.engine.connect() as conn:
        existing = conn.execute(
            text(
                "SELECT request_hash, response_body, match_id FROM match_events "
                "WHERE event_id = :id"
            ),
            {"id": event_id},
        ).mappings().first()
    if existing is not None:
        if existing["request_hash"] == req_hash:
            return JSONResponse(status_code=200, content=existing["response_body"])
        raise ApiError(
            409,
            "DUPLICATE_EVENT_ID",
            f"Event {event_id} already exists with a different body.",
            {"event_id": event_id},
        )

    # Validate payload shape early (400) before existence checks where possible.
    _validate_payload_shape(etype, payload)

    try:
        with db.engine.begin() as conn:
            # Serialize appends for this match.
            conn.execute(text("SELECT pg_advisory_xact_lock(hashtextextended(:m, 0))"),
                         {"m": match_id})

            # Re-check idempotency under lock.
            existing = conn.execute(
                text(
                    "SELECT request_hash, response_body FROM match_events WHERE event_id = :id"
                ),
                {"id": event_id},
            ).mappings().first()
            if existing is not None:
                if existing["request_hash"] == req_hash:
                    raise _Replay(existing["response_body"])
                raise ApiError(
                    409,
                    "DUPLICATE_EVENT_ID",
                    f"Event {event_id} already exists with a different body.",
                    {"event_id": event_id},
                )

            match = _load_match(conn, match_id)

            if etype == "match_init":
                if match is not None:
                    raise ApiError(
                        409, "MATCH_EXISTS", f"Match {match_id} already exists.",
                        {"match_id": match_id},
                    )
                sport_id = payload.get("sport_id")
                home = payload.get("home_team_id")
                away = payload.get("away_team_id")
                league_id = payload.get("league_id")
                sport = _load_sport(conn, sport_id)
                conn.execute(
                    text(
                        "INSERT INTO matches (match_id, sport_id, league_id, home_team_id, away_team_id) "
                        "VALUES (:mid, :sport, :lid, :home, :away)"
                    ),
                    {
                        "mid": match_id,
                        "sport": sport_id,
                        "lid": league_id,
                        "home": home,
                        "away": away,
                    },
                )
                match = {
                    "match_id": match_id,
                    "sport_id": sport_id,
                    "league_id": league_id,
                    "home_team_id": home,
                    "away_team_id": away,
                }
                events: list[dict] = []
            else:
                if match is None:
                    raise ApiError(
                        404, "MATCH_NOT_FOUND", f"Match {match_id} does not exist.",
                        {"match_id": match_id},
                    )
                sport = _load_sport(conn, match["sport_id"])
                events = _load_events(conn, match_id)

            proj = project_match(match, events, sport)
            _enforce_transition(etype, payload, match, sport, proj)

            signature = sign(event_id, payload)
            sequence = len(events) + 1
            response = {
                "event_id": event_id,
                "match_id": match_id,
                "type": etype,
                "sequence": sequence,
                "match_version": sequence,
                "signature": signature,
            }
            conn.execute(
                text(
                    "INSERT INTO match_events "
                    "(event_id, match_id, type, payload, sequence, signature, request_hash, response_body) "
                    "VALUES (:eid, :mid, :type, CAST(:payload AS JSONB), :seq, :sig, :hash, CAST(:resp AS JSONB))"
                ),
                {
                    "eid": event_id,
                    "mid": match_id,
                    "type": etype,
                    "payload": json.dumps(payload),
                    "seq": sequence,
                    "sig": signature,
                    "hash": req_hash,
                    "resp": json.dumps(response),
                },
            )
    except _Replay as replay:
        return JSONResponse(status_code=200, content=replay.response)
    except ApiError:
        raise
    except IntegrityError:
        with db.engine.connect() as conn:
            existing = conn.execute(
                text(
                    "SELECT request_hash, response_body FROM match_events WHERE event_id = :id"
                ),
                {"id": event_id},
            ).mappings().first()
        if existing and existing["request_hash"] == req_hash:
            return JSONResponse(status_code=200, content=existing["response_body"])
        raise ApiError(
            409,
            "DUPLICATE_EVENT_ID",
            f"Event {event_id} already exists with a different body.",
            {"event_id": event_id},
        )

    return JSONResponse(status_code=201, content=response)


class _Replay(Exception):
    def __init__(self, response: dict):
        self.response = response


def _validate_payload_shape(etype: str, payload: dict) -> None:
    if etype == "match_init":
        bad = []
        for f in ("sport_id", "home_team_id", "away_team_id"):
            v = payload.get(f)
            if not isinstance(v, str) or not v:
                bad.append(f"payload.{f}")
        if payload.get("home_team_id") == payload.get("away_team_id"):
            bad.append("payload.away_team_id")
        lid = payload.get("league_id")
        if lid is not None and (not isinstance(lid, str) or not lid):
            bad.append("payload.league_id")
        if bad:
            raise validation_error(bad)
    elif etype in ("match_start", "match_end"):
        pass  # empty / ignored extras
    elif etype == "score":
        bad = []
        if not isinstance(payload.get("team_id"), str) or not payload.get("team_id"):
            bad.append("payload.team_id")
        if not isinstance(payload.get("event_type"), str) or not payload.get("event_type"):
            bad.append("payload.event_type")
        if bad:
            raise validation_error(bad)
    elif etype == "discipline":
        bad = []
        if not isinstance(payload.get("team_id"), str) or not payload.get("team_id"):
            bad.append("payload.team_id")
        if not _is_int(payload.get("points")):
            bad.append("payload.points")
        if bad:
            raise validation_error(bad)
    elif etype == "tiebreak_winner":
        if not isinstance(payload.get("team_id"), str) or not payload.get("team_id"):
            raise validation_error(["payload.team_id"])
    elif etype == "compensation":
        bad = []
        if not isinstance(payload.get("compensates"), str) or not payload.get("compensates"):
            bad.append("payload.compensates")
        if "reason" not in payload or not isinstance(payload.get("reason"), str):
            bad.append("payload.reason")
        if bad:
            raise validation_error(bad)


def _enforce_transition(
    etype: str,
    payload: dict,
    match: dict,
    sport: dict,
    proj: dict,
) -> None:
    status = proj["status"]
    home, away = match["home_team_id"], match["away_team_id"]
    teams = {home, away}

    if etype == "match_init":
        return

    if etype == "match_start":
        if status != "upcoming":
            raise ApiError(409, "ILLEGAL_TRANSITION", "Match must be upcoming to start.")
        return

    if etype == "match_end":
        if status != "in_progress":
            raise ApiError(409, "ILLEGAL_TRANSITION", "Match must be in_progress to end.")
        hs = proj["_scores"][home]
        aws = proj["_scores"][away]
        tb = proj["_tiebreak"]
        if hs == aws and not sport.get("draw_allowed") and not tb:
            raise ApiError(409, "TIE_NOT_ALLOWED", "Level score with draw_allowed=false.")
        return

    if etype == "compensation":
        # Allowed any status after init (including completed). Match already exists.
        target_id = payload["compensates"]
        events = proj["events"]
        target = next((e for e in events if e["event_id"] == target_id), None)
        if target is None:
            raise ApiError(
                404, "EVENT_NOT_FOUND", f"Event {target_id} does not exist.",
                {"event_id": target_id},
            )
        if target["type"] not in ("score", "discipline", "tiebreak_winner"):
            raise ApiError(409, "INVALID_COMPENSATION", "Target type cannot be compensated.")
        if target["compensated"]:
            raise ApiError(409, "INVALID_COMPENSATION", "Event already compensated.")
        return

    # score / discipline / tiebreak require in_progress
    if status != "in_progress":
        raise ApiError(
            409,
            "MATCH_NOT_IN_PROGRESS",
            "Match must be in_progress for this event.",
        )

    team = payload.get("team_id")
    if team not in teams:
        raise validation_error(["payload.team_id"], "team_id must be home or away.")

    if etype == "score":
        et = payload.get("event_type")
        scoring_events = sport.get("scoring_events") or {}
        if et not in scoring_events:
            raise ApiError(
                400,
                "UNKNOWN_EVENT_TYPE",
                f"Event type {et} is not defined for this sport.",
                {"event_type": et},
            )
        model = sport.get("scoring_model")
        if model == "innings":
            b = proj["_balls"][team]
            w = proj["_wickets"][team]
            if _innings_complete(sport, b, w):
                raise ApiError(
                    409, "INNINGS_COMPLETE",
                    f"Innings complete for team {team}.",
                    {"team_id": team},
                )
        elif model == "round":
            if _series_decided(sport, proj["_scores"][team]):
                raise ApiError(
                    409, "SERIES_ALREADY_DECIDED",
                    "Series already decided.",
                )
    # discipline / tiebreak_winner: team already validated
