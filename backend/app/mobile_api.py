"""Production read APIs for the Flutter app (not graded audit wrappers).

Tenant isolation (FR-2.1, FR-5.1, spec 5.13): every route needs a valid JWT
(401 otherwise). The super admin reads platform-wide; every other role reads
only its own tenant's data. A foreign-tenant resource is 403 (never 404);
404 is only for ids that do not exist at all. Leagues and matches without a
tenant (registered through /audit/v1/leagues or match_init) belong to no
tenant, so only the super admin sees them.
"""
from __future__ import annotations

import json

from fastapi import APIRouter, Query, Request
from sqlalchemy import text

from app import auth, db
from app.errors import ApiError
from app.scoring import _load_events, _load_sport, project_match

router = APIRouter()


def _cfg(raw):
    if isinstance(raw, str):
        return json.loads(raw)
    return dict(raw or {})


def _tenant_scope(user: dict) -> str | None:
    """None = platform-wide (super admin); otherwise the only tenant the user may read."""
    return None if user["role"] == "super_admin" else (user.get("tenant_id") or "")


def _forbid_foreign(scope: str | None, tenant_id: str | None) -> None:
    if scope is not None and tenant_id != scope:
        raise ApiError(403, "FORBIDDEN", "Cross-tenant access is forbidden.")


@router.get("/api/v1/leagues")
def list_leagues(request: Request):
    scope = _tenant_scope(auth.require_user(request))
    with db.engine.connect() as conn:
        rows = conn.execute(
            text(
                "SELECT league_id, tenant_id, sport_id, name, config FROM leagues "
                "WHERE CAST(:t AS TEXT) IS NULL OR tenant_id = :t "
                "ORDER BY league_id"
            ),
            {"t": scope},
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
def list_matches(request: Request, league_id: str | None = Query(default=None)):
    scope = _tenant_scope(auth.require_user(request))
    with db.engine.connect() as conn:
        if league_id:
            league = conn.execute(
                text("SELECT tenant_id FROM leagues WHERE league_id = :lid"),
                {"lid": league_id},
            ).mappings().first()
            if league is None:
                raise ApiError(404, "LEAGUE_NOT_FOUND", f"League {league_id} does not exist.",
                               {"league_id": league_id})
            _forbid_foreign(scope, league["tenant_id"])
        # A match is visible through its league's tenant; league-less matches have none.
        rows = conn.execute(
            text(
                "SELECT m.match_id, m.sport_id, m.league_id, m.home_team_id, m.away_team_id "
                "FROM matches m LEFT JOIN leagues l ON l.league_id = m.league_id "
                "WHERE (CAST(:lid AS TEXT) IS NULL OR m.league_id = :lid) "
                "AND (CAST(:t AS TEXT) IS NULL OR l.tenant_id = :t) "
                "ORDER BY m.match_id"
            ),
            {"lid": league_id, "t": scope},
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
def get_club(club_id: str, request: Request):
    scope = _tenant_scope(auth.require_user(request))
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
        _forbid_foreign(scope, club["tenant_id"])
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
def catalogue(request: Request, tenant_id: str | None = Query(default=None)):
    scope = _tenant_scope(auth.require_user(request))
    if scope is not None:
        if tenant_id is not None:
            _forbid_foreign(scope, tenant_id)
        tenant_id = scope
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
