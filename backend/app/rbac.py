"""Five-tier RBAC probes and policy matrix (spec §5.13).

Probe routes only authorize: allowed → 200 {"authorized":true};
denied → 403 FORBIDDEN; bad/missing token → 401 UNAUTHENTICATED.
Cross-tenant access by a non-super-admin is always 403, never 404.
"""
from __future__ import annotations

from fastapi import APIRouter, Request
from sqlalchemy import text

from app import auth, db
from app.errors import ApiError

router = APIRouter()

RBAC_CONTEXT = {
    "tenant_id": "tenant-alpha",
    "foreign_tenant_id": "tenant-beta",
    "own_league_id": "league-alpha-1",
    "other_league_id": "league-alpha-2",
    "foreign_league_id": "league-beta-1",
    "own_club_id": "club-alpha-1",
    "other_club_id": "club-alpha-2",
    "foreign_club_id": "club-beta-1",
    "own_player_id": "player-alpha-1",
    "other_player_id": "player-alpha-2",
    "foreign_player_id": "player-beta-1",
}


def _ok():
    return {"authorized": True}


def _forbid(message: str = "Not permitted for this role or tenant.") -> None:
    raise ApiError(403, "FORBIDDEN", message)


def _league(league_id: str) -> dict | None:
    with db.engine.connect() as conn:
        row = conn.execute(
            text("SELECT league_id, tenant_id FROM leagues WHERE league_id = :id"),
            {"id": league_id},
        ).mappings().first()
    return dict(row) if row else None


def _club(club_id: str) -> dict | None:
    with db.engine.connect() as conn:
        row = conn.execute(
            text("SELECT club_id, tenant_id FROM clubs WHERE club_id = :id"),
            {"id": club_id},
        ).mappings().first()
    return dict(row) if row else None


def _player(player_id: str) -> dict | None:
    with db.engine.connect() as conn:
        row = conn.execute(
            text(
                "SELECT player_id, tenant_id, club_id FROM players WHERE player_id = :id"
            ),
            {"id": player_id},
        ).mappings().first()
    return dict(row) if row else None


def authorize_create_tenant(user: dict) -> bool:
    return user["role"] == "super_admin"


def authorize_league_fixtures(user: dict, league_id: str) -> bool:
    if user["role"] == "super_admin":
        return True
    if user["role"] == "league_organizer":
        return user.get("league_id") == league_id
    return False


def authorize_club_write(user: dict, club_id: str) -> bool:
    """P3 roster / P4 products: super_admin or manager of that club."""
    if user["role"] == "super_admin":
        return True
    if user["role"] == "club_manager":
        return user.get("club_id") == club_id
    return False


def authorize_player_patch(user: dict, player: dict) -> bool:
    role = user["role"]
    if role == "super_admin":
        return True
    if role == "club_manager":
        return user.get("club_id") is not None and player.get("club_id") == user.get("club_id")
    if role == "player":
        return user.get("player_id") == player.get("player_id")
    return False


def authorize_club_read(user: dict, club: dict) -> bool:
    if user["role"] == "super_admin":
        return True
    # All other seeded roles may read clubs in their own tenant only.
    return user.get("tenant_id") is not None and user.get("tenant_id") == club.get("tenant_id")


def authorize_platform_config(user: dict) -> bool:
    return user["role"] == "super_admin"


def _ensure_exists(row: dict | None, code: str, message: str) -> dict:
    if row is None:
        raise ApiError(404, code, message)
    return row


@router.post("/audit/v1/rbac-matrix")
def rbac_matrix():
    tokens = auth.issue_role_tokens()
    return {"tokens": tokens, "context": dict(RBAC_CONTEXT)}


@router.post("/audit/v1/rbac/tenants")
def p1_create_tenant(request: Request):
    user = auth.require_user(request)
    if not authorize_create_tenant(user):
        _forbid()
    return _ok()


@router.post("/audit/v1/rbac/leagues/{league_id}/fixtures")
def p2_league_fixtures(league_id: str, request: Request):
    user = auth.require_user(request)
    league = _ensure_exists(_league(league_id), "LEAGUE_NOT_FOUND", f"League {league_id} does not exist.")
    if user["role"] != "super_admin":
        # Cross-tenant → 403 even before ownership nuance.
        if user.get("tenant_id") != league.get("tenant_id"):
            _forbid("Cross-tenant access is forbidden.")
        if not authorize_league_fixtures(user, league_id):
            _forbid()
    return _ok()


@router.post("/audit/v1/rbac/clubs/{club_id}/roster")
def p3_club_roster(club_id: str, request: Request):
    return _club_write_probe(club_id, request)


@router.post("/audit/v1/rbac/clubs/{club_id}/products")
def p4_club_products(club_id: str, request: Request):
    return _club_write_probe(club_id, request)


def _club_write_probe(club_id: str, request: Request):
    user = auth.require_user(request)
    club = _ensure_exists(_club(club_id), "CLUB_NOT_FOUND", f"Club {club_id} does not exist.")
    if user["role"] != "super_admin":
        if user.get("tenant_id") != club.get("tenant_id"):
            _forbid("Cross-tenant access is forbidden.")
        if not authorize_club_write(user, club_id):
            _forbid()
    return _ok()


@router.patch("/audit/v1/rbac/players/{player_id}")
def p5_patch_player(player_id: str, request: Request):
    user = auth.require_user(request)
    player = _ensure_exists(
        _player(player_id), "PLAYER_NOT_FOUND", f"Player {player_id} does not exist."
    )
    if user["role"] != "super_admin":
        if user.get("tenant_id") != player.get("tenant_id"):
            _forbid("Cross-tenant access is forbidden.")
        if not authorize_player_patch(user, player):
            _forbid()
    return _ok()


@router.get("/audit/v1/rbac/clubs/{club_id}")
def p6_get_club(club_id: str, request: Request):
    user = auth.require_user(request)
    club = _ensure_exists(_club(club_id), "CLUB_NOT_FOUND", f"Club {club_id} does not exist.")
    if not authorize_club_read(user, club):
        # Foreign tenant club for non-super-admin → always 403.
        _forbid("Cross-tenant access is forbidden.")
    return _ok()


@router.get("/audit/v1/rbac/platform/config")
def p7_platform_config(request: Request):
    user = auth.require_user(request)
    if not authorize_platform_config(user):
        _forbid()
    return _ok()
