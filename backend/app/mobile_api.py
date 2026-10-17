"""Production read APIs for the Flutter app (not graded audit wrappers)."""
from __future__ import annotations

import json

from fastapi import APIRouter, Query
from sqlalchemy import text

from app import db
from app.errors import ApiError
from app.scoring import _load_events, _load_sport, project_match

router = APIRouter()


def _cfg(raw):
    if isinstance(raw, str):
        return json.loads(raw)
    return dict(raw or {})


@router.get("/api/v1/leagues")
def list_leagues():
    with db.engine.connect() as conn:
        rows = conn.execute(
            text(
                "SELECT league_id, tenant_id, sport_id, name, config FROM leagues "
                "ORDER BY league_id"
            )
        ).mappings().all()
    out = []
    for r in rows:
        cfg = _cfg(r["config"])
        out.append({
            "league_id": r["league_id"],
            "tenant_id": r["tenant_id"],
            "sport_id": r["sport_id"],
            "name": r["name"],
            "team_count": len(cfg.get("teams") or []),
            "fixture_count": len(cfg.get("fixtures") or []),
        })
    return {"leagues": out}


@router.get("/api/v1/matches")
def list_matches(league_id: str | None = Query(default=None)):
    with db.engine.connect() as conn:
        if league_id:
            rows = conn.execute(
                text(
                    "SELECT match_id, sport_id, league_id, home_team_id, away_team_id "
                    "FROM matches WHERE league_id = :lid ORDER BY match_id"
                ),
                {"lid": league_id},
            ).mappings().all()
        else:
            rows = conn.execute(
                text(
                    "SELECT match_id, sport_id, league_id, home_team_id, away_team_id "
                    "FROM matches ORDER BY match_id"
                )
            ).mappings().all()

        matches = []
        for r in rows:
            match = dict(r)
            sport = _load_sport(conn, match["sport_id"])
            events = _load_events(conn, match["match_id"])
            proj = project_match(match, events, sport)
            matches.append({
                "match_id": match["match_id"],
                "sport_id": match["sport_id"],
                "league_id": match.get("league_id"),
                "home_team_id": match["home_team_id"],
                "away_team_id": match["away_team_id"],
                "status": proj["status"],
                "outcome": proj["outcome"],
                "home_score": proj["home"]["score"],
                "away_score": proj["away"]["score"],
                "version": proj["version"],
            })
    return {"matches": matches}


@router.get("/api/v1/clubs/{club_id}")
def get_club(club_id: str):
    with db.engine.connect() as conn:
        club = conn.execute(
            text(
                "SELECT club_id, tenant_id, name, profile FROM clubs WHERE club_id = :id"
            ),
            {"id": club_id},
        ).mappings().first()
        if club is None:
            raise ApiError(404, "NOT_FOUND", f"Club {club_id} does not exist.",
                           {"club_id": club_id})
        players = conn.execute(
            text(
                "SELECT player_id, name, position FROM players "
                "WHERE club_id = :id ORDER BY player_id"
            ),
            {"id": club_id},
        ).mappings().all()
        tenant = conn.execute(
            text("SELECT tenant_id, name, branding FROM tenants WHERE tenant_id = :id"),
            {"id": club["tenant_id"]},
        ).mappings().first()
    profile = _cfg(club["profile"])
    branding = _cfg(tenant["branding"]) if tenant else {}
    return {
        "club_id": club["club_id"],
        "tenant_id": club["tenant_id"],
        "name": club["name"],
        "profile": profile,
        "players": [dict(p) for p in players],
        "tenant": {
            "tenant_id": tenant["tenant_id"] if tenant else club["tenant_id"],
            "name": tenant["name"] if tenant else None,
            "branding": branding,
        },
    }


@router.get("/api/v1/catalogue")
def catalogue(tenant_id: str | None = Query(default=None)):
    with db.engine.connect() as conn:
        if tenant_id:
            products = conn.execute(
                text(
                    "SELECT product_id, tenant_id, club_id, name, category "
                    "FROM products WHERE tenant_id = :t ORDER BY product_id"
                ),
                {"t": tenant_id},
            ).mappings().all()
        else:
            products = conn.execute(
                text(
                    "SELECT product_id, tenant_id, club_id, name, category "
                    "FROM products ORDER BY product_id"
                )
            ).mappings().all()
        out = []
        for p in products:
            variants = conn.execute(
                text(
                    "SELECT variant_id, product_id, attributes, price_minor, currency, stock, reserved "
                    "FROM variants WHERE product_id = :id ORDER BY variant_id"
                ),
                {"id": p["product_id"]},
            ).mappings().all()
            out.append({
                "product_id": p["product_id"],
                "tenant_id": p["tenant_id"],
                "club_id": p["club_id"],
                "name": p["name"],
                "category": p["category"],
                "variants": [
                    {
                        "variant_id": v["variant_id"],
                        "attributes": _cfg(v["attributes"]),
                        "price_minor": v["price_minor"],
                        "currency": v["currency"],
                        "stock": v["stock"],
                        "reserved": v["reserved"],
                    }
                    for v in variants
                ],
            })
    return {"products": out}
