"""Roster setup, transfer/loan/release, and history (§5.11)."""
from __future__ import annotations

import hashlib
import json
import re
from datetime import date, datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Body, Query
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.engine import Connection

from app import db
from app.errors import ApiError, validation_error
from app.signing import canonical

router = APIRouter()

ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,64}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ROLES = {"captain", "vice_captain", "starter", "substitute"}
TRANSFER_TYPES = {"transfer", "loan", "release"}


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _parse_date(s: str) -> date:
    return date.fromisoformat(s)


def _today() -> date:
    return datetime.now(timezone.utc).date()


def _now_ts() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _cfg(raw) -> dict:
    if isinstance(raw, str):
        return json.loads(raw)
    return dict(raw or {})


def _request_hash(body: dict) -> str:
    return hashlib.sha256(canonical(body).encode("utf-8")).hexdigest()


def _audit_view(row: dict) -> dict:
    return {
        "audit_id": row["audit_id"],
        "action": row["action"],
        "player_id": row["player_id"],
        "league_id": row["league_id"],
        "from_squad_id": row["from_squad_id"],
        "to_squad_id": row["to_squad_id"],
        "effective_date": row["effective_date"],
        "state": row["state"],
        "who": row["who"],
        "when": row["when_ts"],
        "why": row["why"],
    }


def _next_audit_id(conn: Connection) -> str:
    n = conn.execute(text("SELECT COUNT(*) FROM roster_audit")).scalar() or 0
    return f"au-{n + 1:04d}"


def _load_sport_roster(conn: Connection, sport_id: str) -> dict:
    row = conn.execute(
        text("SELECT config FROM sports WHERE sport_id = :id"), {"id": sport_id}
    ).scalar()
    if row is None:
        raise ApiError(404, "SPORT_NOT_FOUND", f"Sport {sport_id} does not exist.",
                       {"sport_id": sport_id})
    cfg = _cfg(row)
    return cfg.get("roster") or {}


# ---- setup ----

@router.post("/audit/v1/roster/setup")
def roster_setup(body: dict | None = Body(default=None)):
    body = body if isinstance(body, dict) else {}
    league = body.get("league")
    squads = body.get("squads")
    players = body.get("players")
    live = body.get("matches_in_progress")
    fields: list[str] = []

    if not isinstance(league, dict):
        fields.append("league")
    if not isinstance(squads, list):
        fields.append("squads")
    if not isinstance(players, list):
        fields.append("players")
    if live is None:
        live = []
    elif not isinstance(live, list):
        fields.append("matches_in_progress")
    if fields:
        raise validation_error(fields)

    assert isinstance(league, dict)
    assert isinstance(squads, list)
    assert isinstance(players, list)
    assert isinstance(live, list)

    lid = league.get("league_id")
    tenant_id = league.get("tenant_id")
    sport_id = league.get("sport_id")
    window = league.get("transfer_window")
    if not isinstance(lid, str) or not lid or not ID_RE.match(lid):
        fields.append("league.league_id")
    if not isinstance(tenant_id, str) or not tenant_id:
        fields.append("league.tenant_id")
    if not isinstance(sport_id, str) or not sport_id:
        fields.append("league.sport_id")
    if not isinstance(window, dict):
        fields.append("league.transfer_window")
    else:
        op, cl = window.get("open"), window.get("close")
        if not isinstance(op, str) or not DATE_RE.match(op):
            fields.append("league.transfer_window.open")
        if not isinstance(cl, str) or not DATE_RE.match(cl):
            fields.append("league.transfer_window.close")
        elif isinstance(op, str) and DATE_RE.match(op) and _parse_date(cl) < _parse_date(op):
            fields.append("league.transfer_window.close")

    max_squad = league.get("max_squad_size")
    req_pos = league.get("required_positions")
    if max_squad is not None and not _is_int(max_squad):
        fields.append("league.max_squad_size")
    if req_pos is not None and not isinstance(req_pos, dict):
        fields.append("league.required_positions")

    squad_ids: set[str] = set()
    for i, sq in enumerate(squads):
        if not isinstance(sq, dict):
            fields.append(f"squads.{i}")
            continue
        sid = sq.get("squad_id")
        if not isinstance(sid, str) or not sid or not ID_RE.match(sid) or sid in squad_ids:
            fields.append(f"squads.{i}.squad_id")
        else:
            squad_ids.add(sid)
        for key in ("club_id", "tenant_id", "name"):
            if not isinstance(sq.get(key), str) or not sq.get(key):
                fields.append(f"squads.{i}.{key}")

    player_ids: set[str] = set()
    for i, pl in enumerate(players):
        if not isinstance(pl, dict):
            fields.append(f"players.{i}")
            continue
        pid = pl.get("player_id")
        if not isinstance(pid, str) or not pid or not ID_RE.match(pid) or pid in player_ids:
            fields.append(f"players.{i}.player_id")
        else:
            player_ids.add(pid)
        if not isinstance(pl.get("name"), str) or not pl.get("name"):
            fields.append(f"players.{i}.name")
        if not isinstance(pl.get("position"), str) or not pl.get("position"):
            fields.append(f"players.{i}.position")
        sq = pl.get("squad_id")
        if not isinstance(sq, str) or sq not in squad_ids:
            fields.append(f"players.{i}.squad_id")
        role = pl.get("role")
        if role not in ROLES:
            fields.append(f"players.{i}.role")

    for i, m in enumerate(live):
        if not isinstance(m, dict):
            fields.append(f"matches_in_progress.{i}")
            continue
        if not isinstance(m.get("match_id"), str) or not m.get("match_id"):
            fields.append(f"matches_in_progress.{i}.match_id")
        if m.get("home_squad_id") not in squad_ids:
            fields.append(f"matches_in_progress.{i}.home_squad_id")
        if m.get("away_squad_id") not in squad_ids:
            fields.append(f"matches_in_progress.{i}.away_squad_id")

    if fields:
        uniq = []
        for f in fields:
            if f not in uniq:
                uniq.append(f)
        raise validation_error(uniq)

    assert isinstance(lid, str)
    assert isinstance(tenant_id, str)
    assert isinstance(sport_id, str)

    with db.engine.begin() as conn:
        sport_roster = _load_sport_roster(conn, sport_id)
        if max_squad is None:
            max_squad = int(sport_roster.get("max_squad_size") or 25)
        if req_pos is None:
            req_pos = dict(sport_roster.get("required_positions") or {})

        # Replace this league's roster state (cascade deletes children).
        conn.execute(text("DELETE FROM roster_audit WHERE league_id = :id"), {"id": lid})
        conn.execute(text("DELETE FROM roster_leagues WHERE league_id = :id"), {"id": lid})

        conn.execute(
            text(
                "INSERT INTO roster_leagues "
                "(league_id, tenant_id, sport_id, transfer_window, max_squad_size, required_positions) "
                "VALUES (:id, :tid, :sid, CAST(:tw AS JSONB), :mx, CAST(:rp AS JSONB))"
            ),
            {
                "id": lid,
                "tid": tenant_id,
                "sid": sport_id,
                "tw": json.dumps({"open": window["open"], "close": window["close"]}),
                "mx": max_squad,
                "rp": json.dumps(req_pos),
            },
        )
        for sq in squads:
            conn.execute(
                text(
                    "INSERT INTO roster_squads (squad_id, league_id, club_id, tenant_id, name) "
                    "VALUES (:sid, :lid, :cid, :tid, :name)"
                ),
                {
                    "sid": sq["squad_id"],
                    "lid": lid,
                    "cid": sq["club_id"],
                    "tid": sq["tenant_id"],
                    "name": sq["name"],
                },
            )
        counts = {s: 0 for s in squad_ids}
        for pl in players:
            conn.execute(
                text(
                    "INSERT INTO roster_players "
                    "(player_id, league_id, name, position, squad_id, parent_squad_id, role, "
                    "registration_type, start_date, loan_end_date, initial_squad_id) "
                    "VALUES (:pid, :lid, :name, :pos, :sq, NULL, :role, NULL, NULL, NULL, :sq)"
                ),
                {
                    "pid": pl["player_id"],
                    "lid": lid,
                    "name": pl["name"],
                    "pos": pl["position"],
                    "sq": pl["squad_id"],
                    "role": pl["role"],
                },
            )
            counts[pl["squad_id"]] += 1
        for m in live:
            conn.execute(
                text(
                    "INSERT INTO roster_live_matches "
                    "(league_id, match_id, home_squad_id, away_squad_id) "
                    "VALUES (:lid, :mid, :home, :away)"
                ),
                {
                    "lid": lid,
                    "mid": m["match_id"],
                    "home": m["home_squad_id"],
                    "away": m["away_squad_id"],
                },
            )

    return JSONResponse(
        status_code=201,
        content={
            "league_id": lid,
            "status": "configured",
            "squad_counts": counts,
        },
    )


# ---- transfer ----

def _normalize_transfer(body: dict) -> dict:
    return {
        "request_id": body.get("request_id"),
        "league_id": body.get("league_id"),
        "player_id": body.get("player_id"),
        "type": body.get("type"),
        "from_squad_id": body.get("from_squad_id"),
        "to_squad_id": body.get("to_squad_id"),
        "effective_date": body.get("effective_date"),
        "loan_end_date": body.get("loan_end_date"),
        "reason": body.get("reason"),
        "requested_by": body.get("requested_by"),
    }


def _squad_count(conn: Connection, league_id: str, squad_id: str) -> int:
    return int(
        conn.execute(
            text(
                "SELECT COUNT(*) FROM roster_players "
                "WHERE league_id = :lid AND squad_id = :sid"
            ),
            {"lid": league_id, "sid": squad_id},
        ).scalar()
        or 0
    )


def _position_count(conn: Connection, league_id: str, squad_id: str, position: str) -> int:
    return int(
        conn.execute(
            text(
                "SELECT COUNT(*) FROM roster_players "
                "WHERE league_id = :lid AND squad_id = :sid AND position = :pos"
            ),
            {"lid": league_id, "sid": squad_id, "pos": position},
        ).scalar()
        or 0
    )


def _blocking_match(conn: Connection, league_id: str, squad_id: str | None) -> str | None:
    if not squad_id:
        return None
    row = conn.execute(
        text(
            "SELECT match_id FROM roster_live_matches "
            "WHERE league_id = :lid AND (home_squad_id = :sid OR away_squad_id = :sid) "
            "LIMIT 1"
        ),
        {"lid": league_id, "sid": squad_id},
    ).first()
    return row[0] if row else None


@router.post("/audit/v1/roster/transfer")
def roster_transfer(body: dict | None = Body(default=None)):
    body = body if isinstance(body, dict) else {}
    norm = _normalize_transfer(body)
    fields: list[str] = []

    rid = norm.get("request_id")
    lid = norm.get("league_id")
    pid = norm.get("player_id")
    typ = norm.get("type")
    from_sq = norm.get("from_squad_id")
    to_sq = norm.get("to_squad_id")
    eff = norm.get("effective_date")
    loan_end = norm.get("loan_end_date")
    reason = norm.get("reason")
    who = norm.get("requested_by")

    # 1. Schema validation
    if not isinstance(rid, str) or not rid or not ID_RE.match(rid):
        fields.append("request_id")
    if not isinstance(lid, str) or not lid:
        fields.append("league_id")
    if not isinstance(pid, str) or not pid:
        fields.append("player_id")
    if typ not in TRANSFER_TYPES:
        fields.append("type")
    if not isinstance(from_sq, str) or not from_sq:
        fields.append("from_squad_id")
    if typ == "release":
        if to_sq is not None:
            fields.append("to_squad_id")
    else:
        if not isinstance(to_sq, str) or not to_sq:
            fields.append("to_squad_id")
    if not isinstance(eff, str) or not DATE_RE.match(eff):
        fields.append("effective_date")
    if typ == "loan":
        if not isinstance(loan_end, str) or not DATE_RE.match(loan_end):
            fields.append("loan_end_date")
        elif isinstance(eff, str) and DATE_RE.match(eff) and not (
            _parse_date(loan_end) > _parse_date(eff)
        ):
            fields.append("loan_end_date")
    else:
        if loan_end is not None:
            fields.append("loan_end_date")
    if not isinstance(reason, str):
        fields.append("reason")
    if not isinstance(who, str) or not who:
        fields.append("requested_by")
    if fields:
        uniq = []
        for f in fields:
            if f not in uniq:
                uniq.append(f)
        raise validation_error(uniq)

    assert isinstance(rid, str)
    assert isinstance(lid, str)
    assert isinstance(pid, str)
    assert isinstance(typ, str)
    assert isinstance(from_sq, str)
    assert isinstance(eff, str)
    assert isinstance(reason, str)
    assert isinstance(who, str)

    req_hash = _request_hash(norm)

    with db.engine.begin() as conn:
        existing = conn.execute(
            text(
                "SELECT request_hash, response_body FROM roster_requests WHERE request_id = :id"
            ),
            {"id": rid},
        ).mappings().first()
        if existing:
            if existing["request_hash"] != req_hash:
                raise ApiError(
                    409, "DUPLICATE_REQUEST_ID",
                    f"request_id {rid} was used with a different body.",
                    {"request_id": rid},
                )
            stored = existing["response_body"]
            if isinstance(stored, str):
                stored = json.loads(stored)
            return JSONResponse(status_code=200, content=stored)

        # 2. Existence
        league = conn.execute(
            text(
                "SELECT league_id, tenant_id, transfer_window, max_squad_size, required_positions "
                "FROM roster_leagues WHERE league_id = :id"
            ),
            {"id": lid},
        ).mappings().first()
        if league is None:
            raise ApiError(404, "LEAGUE_NOT_FOUND", f"League {lid} does not exist.",
                           {"league_id": lid})

        player = conn.execute(
            text(
                "SELECT * FROM roster_players WHERE league_id = :lid AND player_id = :pid"
            ),
            {"lid": lid, "pid": pid},
        ).mappings().first()
        if player is None:
            raise ApiError(404, "PLAYER_NOT_FOUND", f"Player {pid} does not exist.",
                           {"player_id": pid})

        from_row = conn.execute(
            text(
                "SELECT * FROM roster_squads WHERE league_id = :lid AND squad_id = :sid"
            ),
            {"lid": lid, "sid": from_sq},
        ).mappings().first()
        if from_row is None:
            raise ApiError(404, "SQUAD_NOT_FOUND", f"Squad {from_sq} does not exist.",
                           {"squad_id": from_sq})

        to_row = None
        if typ != "release":
            assert isinstance(to_sq, str)
            to_row = conn.execute(
                text(
                    "SELECT * FROM roster_squads WHERE league_id = :lid AND squad_id = :sid"
                ),
                {"lid": lid, "sid": to_sq},
            ).mappings().first()
            if to_row is None:
                raise ApiError(404, "SQUAD_NOT_FOUND", f"Squad {to_sq} does not exist.",
                               {"squad_id": to_sq})

        # 3. Cross-tenant
        league_tenant = league["tenant_id"]
        if from_row["tenant_id"] != league_tenant:
            raise ApiError(409, "CROSS_TENANT_TRANSFER", "Squad tenant mismatch.")
        if to_row is not None and to_row["tenant_id"] != league_tenant:
            raise ApiError(409, "CROSS_TENANT_TRANSFER", "Squad tenant mismatch.")

        # 4. Current squad
        if player["squad_id"] != from_sq:
            raise ApiError(409, "NOT_IN_SQUAD", "Player is not in from_squad_id.")

        # 5. Transfer window (release exempt)
        tw = _cfg(league["transfer_window"])
        if typ in ("transfer", "loan"):
            open_d = _parse_date(tw["open"])
            close_d = _parse_date(tw["close"])
            eff_d = _parse_date(eff)
            if eff_d < open_d or eff_d > close_d:
                raise ApiError(
                    409, "TRANSFER_WINDOW_CLOSED",
                    "effective_date is outside the transfer window.",
                )

        # 6. On loan
        if player["parent_squad_id"] is not None or player["registration_type"] == "loan":
            raise ApiError(409, "PLAYER_ON_LOAN", "Player is currently on loan.")

        # 7. Squad full
        if typ in ("transfer", "loan"):
            assert isinstance(to_sq, str)
            dest_count = _squad_count(conn, lid, to_sq)
            if dest_count + 1 > int(league["max_squad_size"]):
                raise ApiError(409, "SQUAD_FULL", "Destination squad is full.")

        # 8. Min position on from squad after departure
        req = _cfg(league["required_positions"])
        pos = player["position"]
        need = int(req.get(pos, 0) or 0)
        if need > 0:
            have = _position_count(conn, lid, from_sq, pos)
            if have - 1 < need:
                raise ApiError(
                    409, "MIN_POSITION_VIOLATION",
                    f"Squad would drop below required {pos} count.",
                )

        # Effects
        blocking = _blocking_match(conn, lid, from_sq)
        state = "deferred_until_match_end" if blocking else "active"

        new_squad = None if typ == "release" else to_sq
        parent = from_sq if typ == "loan" else None
        new_role = "substitute" if typ != "release" else player["role"]
        reg_type = typ if typ != "release" else None
        loan_end_val = loan_end if typ == "loan" else None

        if typ == "release":
            conn.execute(
                text(
                    "UPDATE roster_players SET squad_id = NULL, parent_squad_id = NULL, "
                    "role = :role, registration_type = NULL, start_date = :sd, "
                    "loan_end_date = NULL WHERE league_id = :lid AND player_id = :pid"
                ),
                {"role": player["role"], "sd": eff, "lid": lid, "pid": pid},
            )
        elif typ == "loan":
            conn.execute(
                text(
                    "UPDATE roster_players SET squad_id = :sq, parent_squad_id = :parent, "
                    "role = 'substitute', registration_type = 'loan', start_date = :sd, "
                    "loan_end_date = :led WHERE league_id = :lid AND player_id = :pid"
                ),
                {
                    "sq": to_sq, "parent": from_sq, "sd": eff, "led": loan_end,
                    "lid": lid, "pid": pid,
                },
            )
        else:  # transfer
            conn.execute(
                text(
                    "UPDATE roster_players SET squad_id = :sq, parent_squad_id = NULL, "
                    "role = 'substitute', registration_type = 'transfer', start_date = :sd, "
                    "loan_end_date = NULL WHERE league_id = :lid AND player_id = :pid"
                ),
                {"sq": to_sq, "sd": eff, "lid": lid, "pid": pid},
            )

        audit_id = _next_audit_id(conn)
        seq = int(
            conn.execute(
                text("SELECT COALESCE(MAX(sequence), 0) + 1 FROM roster_audit WHERE player_id = :pid"),
                {"pid": pid},
            ).scalar()
        )
        when_ts = _now_ts()
        conn.execute(
            text(
                "INSERT INTO roster_audit "
                "(audit_id, player_id, league_id, action, from_squad_id, to_squad_id, "
                "effective_date, state, who, when_ts, why, sequence) "
                "VALUES (:aid, :pid, :lid, :act, :frm, :to, :eff, :st, :who, :when, :why, :seq)"
            ),
            {
                "aid": audit_id,
                "pid": pid,
                "lid": lid,
                "act": typ,
                "frm": from_sq,
                "to": new_squad,
                "eff": eff,
                "st": state,
                "who": who,
                "when": when_ts,
                "why": reason,
                "seq": seq,
            },
        )

        registration = None
        if typ != "release":
            registration = {
                "player_id": pid,
                "league_id": lid,
                "squad_id": new_squad,
                "parent_squad_id": parent,
                "registration_type": reg_type,
                "start_date": eff,
                "loan_end_date": loan_end_val,
                "role": "substitute",
            }

        audit_entry = {
            "audit_id": audit_id,
            "action": typ,
            "player_id": pid,
            "league_id": lid,
            "from_squad_id": from_sq,
            "to_squad_id": new_squad,
            "effective_date": eff,
            "state": state,
            "who": who,
            "when": when_ts,
            "why": reason,
        }
        response = {
            "request_id": rid,
            "status": "accepted",
            "state": state,
            "blocking_match_id": blocking,
            "registration": registration,
            "audit_entry": audit_entry,
        }
        conn.execute(
            text(
                "INSERT INTO roster_requests (request_id, request_hash, response_body) "
                "VALUES (:id, :hash, CAST(:body AS JSONB))"
            ),
            {"id": rid, "hash": req_hash, "body": json.dumps(response)},
        )
        return JSONResponse(status_code=201, content=response)


# ---- history ----

def _ensure_loan_returns(conn: Connection, player_id: str, as_of: date) -> None:
    """Write a single loan_return when as_of is after loan_end_date."""
    rows = conn.execute(
        text(
            "SELECT * FROM roster_players WHERE player_id = :pid AND registration_type = 'loan' "
            "AND loan_end_date IS NOT NULL AND parent_squad_id IS NOT NULL"
        ),
        {"pid": player_id},
    ).mappings().all()
    for pl in rows:
        end = _parse_date(pl["loan_end_date"])
        return_date = end + timedelta(days=1)
        if as_of < return_date:
            continue
        # Already returned?
        exists = conn.execute(
            text(
                "SELECT 1 FROM roster_audit WHERE player_id = :pid AND league_id = :lid "
                "AND action = 'loan_return' AND effective_date = :eff"
            ),
            {"pid": player_id, "lid": pl["league_id"], "eff": return_date.isoformat()},
        ).first()
        if exists:
            continue
        parent = pl["parent_squad_id"]
        conn.execute(
            text(
                "UPDATE roster_players SET squad_id = :sq, parent_squad_id = NULL, "
                "role = 'substitute', registration_type = 'loan_return', "
                "loan_end_date = NULL, start_date = :sd "
                "WHERE league_id = :lid AND player_id = :pid"
            ),
            {
                "sq": parent,
                "sd": return_date.isoformat(),
                "lid": pl["league_id"],
                "pid": player_id,
            },
        )
        audit_id = _next_audit_id(conn)
        seq = int(
            conn.execute(
                text(
                    "SELECT COALESCE(MAX(sequence), 0) + 1 FROM roster_audit WHERE player_id = :pid"
                ),
                {"pid": player_id},
            ).scalar()
        )
        conn.execute(
            text(
                "INSERT INTO roster_audit "
                "(audit_id, player_id, league_id, action, from_squad_id, to_squad_id, "
                "effective_date, state, who, when_ts, why, sequence) "
                "VALUES (:aid, :pid, :lid, 'loan_return', :frm, :to, :eff, 'active', "
                "'system', :when, 'Automatic loan return', :seq)"
            ),
            {
                "aid": audit_id,
                "pid": player_id,
                "lid": pl["league_id"],
                "frm": pl["squad_id"],
                "to": parent,
                "eff": return_date.isoformat(),
                "when": _now_ts(),
                "seq": seq,
            },
        )


def _squad_as_of(conn: Connection, player: dict, as_of: date) -> tuple[str | None, str | None]:
    """Reconstruct (current_squad_id, parent_squad_id) on as_of from initial + audit."""
    squad = player["initial_squad_id"]
    parent = None
    rows = conn.execute(
        text(
            "SELECT * FROM roster_audit WHERE player_id = :pid AND league_id = :lid "
            "AND effective_date <= :asof ORDER BY sequence"
        ),
        {
            "pid": player["player_id"],
            "lid": player["league_id"],
            "asof": as_of.isoformat(),
        },
    ).mappings().all()
    for r in rows:
        act = r["action"]
        if act == "release":
            squad = None
            parent = None
        elif act == "loan":
            squad = r["to_squad_id"]
            parent = r["from_squad_id"]
        elif act in ("transfer", "loan_return"):
            squad = r["to_squad_id"]
            parent = None
    return squad, parent


@router.get("/audit/v1/roster/history/{player_id}")
def roster_history(
    player_id: str,
    as_of: str | None = Query(default=None),
):
    if as_of is None:
        as_of_d = _today()
        as_of_s = as_of_d.isoformat()
    else:
        if not DATE_RE.match(as_of):
            raise validation_error(["as_of"])
        as_of_d = _parse_date(as_of)
        as_of_s = as_of

    with db.engine.begin() as conn:
        player = conn.execute(
            text(
                "SELECT * FROM roster_players WHERE player_id = :pid ORDER BY league_id LIMIT 1"
            ),
            {"pid": player_id},
        ).mappings().first()
        if player is None:
            raise ApiError(
                404, "PLAYER_NOT_FOUND", f"Player {player_id} does not exist.",
                {"player_id": player_id},
            )

        _ensure_loan_returns(conn, player_id, as_of_d)
        # Reload after possible loan_return mutation
        player = conn.execute(
            text(
                "SELECT * FROM roster_players WHERE player_id = :pid AND league_id = :lid"
            ),
            {"pid": player_id, "lid": player["league_id"]},
        ).mappings().first()

        cur_sq, parent = _squad_as_of(conn, dict(player), as_of_d)
        rows = conn.execute(
            text(
                "SELECT * FROM roster_audit WHERE player_id = :pid AND league_id = :lid "
                "AND effective_date <= :asof ORDER BY sequence"
            ),
            {
                "pid": player_id,
                "lid": player["league_id"],
                "asof": as_of_s,
            },
        ).mappings().all()

        return {
            "player_id": player_id,
            "as_of": as_of_s,
            "league_id": player["league_id"],
            "current_squad_id": cur_sq,
            "parent_squad_id": parent,
            "history": [_audit_view(dict(r)) for r in rows],
        }
