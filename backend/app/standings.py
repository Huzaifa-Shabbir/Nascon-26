"""GET /audit/v1/standings/{league_id} — recomputed from event logs (§5.10).

No mutable counters: every call projects each league match from the append-only
log via scoring.project_match, then ranks with the exact tie-break algorithm.
"""
from __future__ import annotations

import json
from typing import Any

from fastapi import APIRouter
from sqlalchemy import text

from app import db
from app.errors import ApiError
from app.scoring import _load_events, _load_sport, project_match
from app.signing import lots_key

router = APIRouter()


def _cfg(raw) -> dict:
    if isinstance(raw, str):
        return json.loads(raw)
    return dict(raw or {})


def _overs_faced(balls: int, wickets: int, sport: dict) -> float:
    """Legal overs faced for NRR. All-out innings count as full overs_per_innings."""
    periods = sport.get("periods") or {}
    bpo = int(periods.get("balls_per_over") or 6)
    max_w = int(periods.get("wickets_per_innings") or 10)
    full = float(periods.get("overs_per_innings") or 1)
    if wickets >= max_w:
        return full
    return balls / bpo if bpo else 0.0


def _nrr(scored: int, conceded: int, overs_for: float, overs_against: float) -> float:
    rf = (scored / overs_for) if overs_for > 0 else 0.0
    ra = (conceded / overs_against) if overs_against > 0 else 0.0
    return round(rf - ra, 3)


def _empty_row(team_id: str) -> dict[str, Any]:
    return {
        "team_id": team_id,
        "played": 0,
        "won": 0,
        "drawn": 0,
        "lost": 0,
        "scored": 0,
        "conceded": 0,
        "diff": 0,
        "points": 0,
        "fair_play": 0,
        # innings accumulators (internal)
        "_balls_for": 0,
        "_wickets_for": 0,
        "_balls_against": 0,
        "_wickets_against": 0,
    }


def _apply_result(
    row: dict,
    scored: int,
    conceded: int,
    outcome_for: str,
    pts_cfg: dict,
    fair_play: int,
    balls_for: int = 0,
    wickets_for: int = 0,
    balls_against: int = 0,
    wickets_against: int = 0,
) -> None:
    row["played"] += 1
    row["scored"] += scored
    row["conceded"] += conceded
    row["fair_play"] += fair_play
    row["_balls_for"] += balls_for
    row["_wickets_for"] += wickets_for
    row["_balls_against"] += balls_against
    row["_wickets_against"] += wickets_against
    if outcome_for == "win":
        row["won"] += 1
        row["points"] += int(pts_cfg.get("win", 3))
    elif outcome_for == "draw":
        row["drawn"] += 1
        row["points"] += int(pts_cfg.get("draw", 1))
    else:
        row["lost"] += 1
        row["points"] += int(pts_cfg.get("loss", 0))


def _finalize_diff(row: dict, model: str, sport: dict) -> None:
    if model == "innings":
        of = _overs_faced(row["_balls_for"], row["_wickets_for"], sport)
        oa = _overs_faced(row["_balls_against"], row["_wickets_against"], sport)
        row["diff"] = _nrr(row["scored"], row["conceded"], of, oa)
    else:
        # event and round: scored − conceded (goals / points / map differential)
        row["diff"] = row["scored"] - row["conceded"]


def _h2h_cell() -> dict:
    return {"played": 0, "points": 0, "scored": 0, "conceded": 0}


def _criteria_list(order: list[str] | None) -> list[str]:
    base = list(order or [
        "h2h_points", "h2h_diff", "overall_diff", "scored", "fair_play", "draw_lots"
    ])
    if "draw_lots" in base:
        base = [c for c in base if c != "draw_lots"]
    base.append("draw_lots")
    return base


def _group_match_stats(
    team: str,
    group: set[str],
    played_matches: list[dict],
    pts_cfg: dict,
    model: str,
    sport: dict,
) -> dict:
    """Mini-league aggregates for `team` vs other members of `group` only."""
    row = _empty_row(team)
    for m in played_matches:
        home, away = m["home"], m["away"]
        if home not in group or away not in group:
            continue
        if team not in (home, away):
            continue
        if team == home:
            scored, conceded = m["home_score"], m["away_score"]
            fp = m["home_fp"]
            bf, wf = m["home_balls"], m["home_wickets"]
            ba, wa = m["away_balls"], m["away_wickets"]
            side = "home"
        else:
            scored, conceded = m["away_score"], m["home_score"]
            fp = m["away_fp"]
            bf, wf = m["away_balls"], m["away_wickets"]
            ba, wa = m["home_balls"], m["home_wickets"]
            side = "away"
        if m["outcome"] == "draw":
            of = "draw"
        elif m["outcome"] == "home_win":
            of = "win" if side == "home" else "loss"
        else:  # away_win
            of = "win" if side == "away" else "loss"
        _apply_result(
            row, scored, conceded, of, pts_cfg, fp,
            bf, wf, ba, wa,
        )
    _finalize_diff(row, model, sport)
    return row


def _criterion_value(
    criterion: str,
    team: str,
    group: list[str],
    overall: dict[str, dict],
    played_matches: list[dict],
    pts_cfg: dict,
    model: str,
    sport: dict,
    league_id: str,
    lots_seed: int,
) -> Any:
    if criterion == "h2h_points":
        return _group_match_stats(
            team, set(group), played_matches, pts_cfg, model, sport
        )["points"]
    if criterion == "h2h_diff":
        return _group_match_stats(
            team, set(group), played_matches, pts_cfg, model, sport
        )["diff"]
    if criterion == "overall_diff":
        return overall[team]["diff"]
    if criterion == "scored":
        return overall[team]["scored"]
    if criterion == "fair_play":
        return overall[team]["fair_play"]
    if criterion == "draw_lots":
        # Ascending lots_key = best first → invert for "higher is better" sort key
        # by using negative... actually we sort best-first with reverse=True on
        # numeric criteria. For lots, lower key is better, so return -ord or use
        # a special path. Use the hex string with reverse sort disabled.
        return lots_key(lots_seed, league_id, team)
    return 0


def _resolve(
    group: list[str],
    criteria: list[str],
    overall: dict[str, dict],
    played_matches: list[dict],
    pts_cfg: dict,
    model: str,
    sport: dict,
    league_id: str,
    lots_seed: int,
) -> list[str]:
    """Return team_ids best-first. Restarts from first criterion after each split."""
    if len(group) <= 1:
        return list(group)

    for crit in criteria:
        values = {
            t: _criterion_value(
                crit, t, group, overall, played_matches, pts_cfg,
                model, sport, league_id, lots_seed,
            )
            for t in group
        }
        distinct = set(values.values())
        if len(distinct) == 1:
            continue

        # Split into sub-groups by value, best first.
        if crit == "draw_lots":
            # Ascending hex = best first
            ordered_vals = sorted(distinct)
        else:
            ordered_vals = sorted(distinct, reverse=True)

        result: list[str] = []
        for v in ordered_vals:
            sub = [t for t in group if values[t] == v]
            if len(sub) == 1:
                result.extend(sub)
            else:
                # Restart from the *first* criterion on each sub-group
                result.extend(
                    _resolve(
                        sub, criteria, overall, played_matches, pts_cfg,
                        model, sport, league_id, lots_seed,
                    )
                )
        return result

    # All criteria equal (should not happen once draw_lots is present)
    return list(group)


def _separating_criterion(
    higher: str,
    lower: str,
    tied_group: list[str],
    criteria: list[str],
    overall: dict[str, dict],
    played_matches: list[dict],
    pts_cfg: dict,
    model: str,
    sport: dict,
    league_id: str,
    lots_seed: int,
) -> str | None:
    """Criterion that placed `higher` above `lower` within a points-tied group."""
    group = list(tied_group)
    while len(group) > 1:
        for crit in criteria:
            values = {
                t: _criterion_value(
                    crit, t, group, overall, played_matches, pts_cfg,
                    model, sport, league_id, lots_seed,
                )
                for t in group
            }
            if len(set(values.values())) == 1:
                continue
            if values[higher] != values[lower]:
                return crit
            # Same sub-group — restart from first criterion
            group = [t for t in group if values[t] == values[higher]]
            break
        else:
            return None
    return None


def compute_standings(
    league_id: str,
    sport_id: str,
    sport: dict,
    league_cfg: dict,
    match_projections: list[tuple[dict, dict]],
) -> dict:
    """Pure standings computation from already-projected matches.

    match_projections: list of (match_row, projection) for this league.
    """
    teams: list[str] = list(league_cfg.get("teams") or [])
    fixtures: list[dict] = list(league_cfg.get("fixtures") or [])
    pts_cfg = league_cfg.get("points") or {"win": 3, "draw": 1, "loss": 0}
    criteria = _criteria_list(league_cfg.get("tie_break_order"))
    spots = int((league_cfg.get("qualification") or {}).get("spots") or 1)
    lots_seed = int(league_cfg.get("lots_seed") or 42)
    model = sport.get("scoring_model") or "event"

    overall = {t: _empty_row(t) for t in teams}
    h2h = {a: {b: _h2h_cell() for b in teams if b != a} for a in teams}

    played_matches: list[dict] = []
    played_ids: set[str] = set()

    for match, proj in match_projections:
        if proj["status"] != "completed" or proj["outcome"] == "undecided":
            continue
        home = match["home_team_id"]
        away = match["away_team_id"]
        if home not in overall or away not in overall:
            continue

        hs = int(proj["home"]["score"])
        aws = int(proj["away"]["score"])
        hfp = int(proj["home"].get("fair_play") or 0)
        afp = int(proj["away"].get("fair_play") or 0)
        hb = int(proj["home"].get("balls") or 0)
        ab = int(proj["away"].get("balls") or 0)
        hw = int(proj["home"].get("wickets") or 0)
        aw = int(proj["away"].get("wickets") or 0)
        outcome = proj["outcome"]

        played_ids.add(match["match_id"])
        played_matches.append({
            "match_id": match["match_id"],
            "home": home,
            "away": away,
            "home_score": hs,
            "away_score": aws,
            "home_fp": hfp,
            "away_fp": afp,
            "home_balls": hb,
            "away_balls": ab,
            "home_wickets": hw,
            "away_wickets": aw,
            "outcome": outcome,
        })

        # overall rows
        if outcome == "draw":
            _apply_result(overall[home], hs, aws, "draw", pts_cfg, hfp, hb, hw, ab, aw)
            _apply_result(overall[away], aws, hs, "draw", pts_cfg, afp, ab, aw, hb, hw)
        elif outcome == "home_win":
            _apply_result(overall[home], hs, aws, "win", pts_cfg, hfp, hb, hw, ab, aw)
            _apply_result(overall[away], aws, hs, "loss", pts_cfg, afp, ab, aw, hb, hw)
        else:  # away_win
            _apply_result(overall[home], hs, aws, "loss", pts_cfg, hfp, hb, hw, ab, aw)
            _apply_result(overall[away], aws, hs, "win", pts_cfg, afp, ab, aw, hb, hw)

        # h2h ordered pairs
        cell_ha = h2h[home][away]
        cell_ah = h2h[away][home]
        cell_ha["played"] += 1
        cell_ah["played"] += 1
        cell_ha["scored"] += hs
        cell_ha["conceded"] += aws
        cell_ah["scored"] += aws
        cell_ah["conceded"] += hs
        if outcome == "draw":
            cell_ha["points"] += int(pts_cfg.get("draw", 1))
            cell_ah["points"] += int(pts_cfg.get("draw", 1))
        elif outcome == "home_win":
            cell_ha["points"] += int(pts_cfg.get("win", 3))
            cell_ah["points"] += int(pts_cfg.get("loss", 0))
        else:
            cell_ha["points"] += int(pts_cfg.get("loss", 0))
            cell_ah["points"] += int(pts_cfg.get("win", 3))

    for t in teams:
        _finalize_diff(overall[t], model, sport)

    # Remaining fixtures per team (not yet a counted played result)
    remaining = {t: 0 for t in teams}
    for fx in fixtures:
        mid = fx.get("match_id")
        if mid in played_ids:
            continue
        home, away = fx.get("home"), fx.get("away")
        if home in remaining:
            remaining[home] += 1
        if away in remaining:
            remaining[away] += 1

    # Rank: group by points, resolve ties
    by_pts: dict[int, list[str]] = {}
    for t in teams:
        by_pts.setdefault(overall[t]["points"], []).append(t)

    ranked: list[str] = []
    for pts in sorted(by_pts.keys(), reverse=True):
        group = by_pts[pts]
        if len(group) == 1:
            ranked.extend(group)
        else:
            ranked.extend(
                _resolve(
                    group, criteria, overall, played_matches, pts_cfg,
                    model, sport, league_id, lots_seed,
                )
            )

    # resolved_by relative to next team with same points
    resolved_by: dict[str, str | None] = {t: None for t in teams}
    for i, t in enumerate(ranked):
        if i + 1 >= len(ranked):
            break
        nxt = ranked[i + 1]
        if overall[t]["points"] != overall[nxt]["points"]:
            continue
        tied = [x for x in ranked if overall[x]["points"] == overall[t]["points"]]
        resolved_by[t] = _separating_criterion(
            t, nxt, tied, criteria, overall, played_matches, pts_cfg,
            model, sport, league_id, lots_seed,
        )

    # Qualification (points only)
    W = int(pts_cfg.get("win", 3))
    k = spots
    max_pts = {t: overall[t]["points"] + W * remaining[t] for t in teams}
    status: dict[str, str] = {}
    for t in teams:
        pts_t = overall[t]["points"]
        others = [x for x in teams if x != t]
        if sum(1 for x in others if max_pts[x] >= pts_t) < k:
            status[t] = "clinched"
        elif sum(1 for x in others if overall[x]["points"] > max_pts[t]) >= k:
            status[t] = "eliminated"
        else:
            status[t] = "still_possible"

    table = []
    for rank, t in enumerate(ranked, start=1):
        row = overall[t]
        table.append({
            "rank": rank,
            "team_id": t,
            "played": row["played"],
            "won": row["won"],
            "drawn": row["drawn"],
            "lost": row["lost"],
            "scored": row["scored"],
            "conceded": row["conceded"],
            "diff": row["diff"],
            "points": row["points"],
            "fair_play": row["fair_play"],
            "status": status[t],
            "resolved_by": resolved_by[t],
        })

    return {
        "league_id": league_id,
        "sport_id": sport_id,
        "qualification_spots": spots,
        "table": table,
        "h2h": h2h,
    }


@router.get("/audit/v1/standings/{league_id}")
def get_standings(league_id: str):
    with db.engine.connect() as conn:
        league = conn.execute(
            text(
                "SELECT league_id, sport_id, config FROM leagues WHERE league_id = :id"
            ),
            {"id": league_id},
        ).mappings().first()
        if league is None:
            raise ApiError(
                404, "LEAGUE_NOT_FOUND", f"League {league_id} does not exist.",
                {"league_id": league_id},
            )

        sport_id = league["sport_id"]
        sport = _load_sport(conn, sport_id)
        league_cfg = _cfg(league["config"])

        rows = conn.execute(
            text(
                "SELECT match_id, sport_id, league_id, home_team_id, away_team_id "
                "FROM matches WHERE league_id = :id"
            ),
            {"id": league_id},
        ).mappings().all()

        projections: list[tuple[dict, dict]] = []
        for r in rows:
            match = dict(r)
            events = _load_events(conn, match["match_id"])
            projections.append((match, project_match(match, events, sport)))

    return compute_standings(
        league_id, sport_id, sport, league_cfg, projections,
    )
