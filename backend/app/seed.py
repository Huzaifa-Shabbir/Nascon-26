"""Baseline data (spec 5.5) and the reset routine.

Seeded sports are plain data in the same schema as POST /audit/v1/sports (5.6);
nothing here or elsewhere may branch on a sport or event name.
"""
import hashlib
import json
import logging

from sqlalchemy import text

from app import db
from app.passwords import hash_password

log = logging.getLogger(__name__)

DEFAULT_SEED = 42
DEFAULT_STOCK = {"var-jersey-001-M": 1, "var-jersey-001-L": 5}
DEMO_PASSWORD = "Nascon@26"
TIE_BREAK_ORDER = ["h2h_points", "h2h_diff", "overall_diff", "scored", "fair_play", "draw_lots"]

SPORTS = [
    {
        "sport_id": "football", "name": "Football", "scoring_model": "event",
        "periods": {"count": 2, "duration_minutes": 45},
        "scoring_events": {"goal": {"points": 1}},
        "draw_allowed": True,
        "overtime": {"policy": "none"},
        "tie_break_order": TIE_BREAK_ORDER,
        "roster": {"min_squad_size": 11, "max_squad_size": 25, "required_positions": {"gk": 1}},
    },
    {
        "sport_id": "basketball", "name": "Basketball", "scoring_model": "event",
        "periods": {"count": 4, "duration_minutes": 12},
        "scoring_events": {"free_throw": {"points": 1}, "two_pointer": {"points": 2},
                           "three_pointer": {"points": 3}},
        "draw_allowed": False,
        "overtime": {"policy": "extra_time", "duration_minutes": 5},
        "tie_break_order": TIE_BREAK_ORDER,
        "roster": {"min_squad_size": 5, "max_squad_size": 15, "required_positions": {}},
    },
    {
        "sport_id": "cricket", "name": "Cricket", "scoring_model": "innings",
        "periods": {"innings_per_team": 1, "overs_per_innings": 20, "balls_per_over": 6,
                    "wickets_per_innings": 10},
        "scoring_events": {
            "dot_ball": {"runs": 0, "legal_ball": True, "wicket": False},
            "single": {"runs": 1, "legal_ball": True, "wicket": False},
            "two": {"runs": 2, "legal_ball": True, "wicket": False},
            "four": {"runs": 4, "legal_ball": True, "wicket": False},
            "six": {"runs": 6, "legal_ball": True, "wicket": False},
            "wide": {"runs": 1, "legal_ball": False, "wicket": False},
            "no_ball": {"runs": 1, "legal_ball": False, "wicket": False},
            "wicket": {"runs": 0, "legal_ball": True, "wicket": True},
        },
        "draw_allowed": True,
        "overtime": {"policy": "super_over"},
        "tie_break_order": TIE_BREAK_ORDER,
        "roster": {"min_squad_size": 11, "max_squad_size": 18, "required_positions": {"wicketkeeper": 1}},
    },
    {
        "sport_id": "esports", "name": "Esports", "scoring_model": "round",
        "periods": {"best_of": 3},
        "scoring_events": {"round_win": {"rounds": 1}},
        "draw_allowed": False,
        "overtime": {"policy": "none"},
        "tie_break_order": TIE_BREAK_ORDER,
        "roster": {"min_squad_size": 5, "max_squad_size": 8, "required_positions": {}},
    },
]

TENANTS = [
    {"tenant_id": "tenant-alpha", "name": "Alpha Sports",
     "branding": {"logo_url": "/static/tenant-alpha.png", "primary_color": "#0B5FFF", "secondary_color": "#FFB800"}},
    {"tenant_id": "tenant-beta", "name": "Beta Athletics",
     "branding": {"logo_url": "/static/tenant-beta.png", "primary_color": "#0F8A4B", "secondary_color": "#1D1D1F"}},
]

LEAGUES = [
    {"league_id": "league-alpha-1", "tenant_id": "tenant-alpha", "sport_id": "football", "name": "Alpha Premier League"},
    {"league_id": "league-alpha-2", "tenant_id": "tenant-alpha", "sport_id": "basketball", "name": "Alpha Hoops League"},
    {"league_id": "league-beta-1", "tenant_id": "tenant-beta", "sport_id": "football", "name": "Beta Championship"},
]

CLUBS = [
    {"club_id": "club-alpha-1", "tenant_id": "tenant-alpha", "name": "Alpha United",
     "profile": {"home_venue": {"name": "Alpha Arena", "lat": 33.6844, "lng": 73.0479},
                 "social": {"x": "@alphaunited", "instagram": "@alphaunited"},
                 "staff": {"coach": "Imran Khalid", "manager": "Sara Malik", "physio": "Omar Riaz"}}},
    {"club_id": "club-alpha-2", "tenant_id": "tenant-alpha", "name": "Alpha Rovers",
     "profile": {"home_venue": {"name": "Rovers Ground", "lat": 33.7380, "lng": 73.0844},
                 "social": {"x": "@alpharovers"},
                 "staff": {"coach": "Hina Aslam", "manager": "Bilal Ahmed", "physio": "Ayesha Noor"}}},
    {"club_id": "club-beta-1", "tenant_id": "tenant-beta", "name": "Beta City",
     "profile": {"home_venue": {"name": "Beta Stadium", "lat": 31.5204, "lng": 74.3587},
                 "social": {"x": "@betacity"},
                 "staff": {"coach": "Faisal Raza", "manager": "Nida Shah", "physio": "Usman Tariq"}}},
]

PLAYERS = [
    {"player_id": "player-alpha-1", "tenant_id": "tenant-alpha", "club_id": "club-alpha-1",
     "name": "Ali Hassan", "position": "gk"},
    {"player_id": "player-alpha-2", "tenant_id": "tenant-alpha", "club_id": "club-alpha-2",
     "name": "Hamza Iqbal", "position": "df"},
    {"player_id": "player-beta-1", "tenant_id": "tenant-beta", "club_id": "club-beta-1",
     "name": "Zain Abbas", "position": "fw"},
]

USERS = [
    {"user_id": "user-admin", "email": "admin@nascon.test", "role": "super_admin",
     "tenant_id": None, "league_id": None, "club_id": None, "player_id": None},
    {"user_id": "user-organizer", "email": "organizer@nascon.test", "role": "league_organizer",
     "tenant_id": "tenant-alpha", "league_id": "league-alpha-1", "club_id": None, "player_id": None},
    {"user_id": "user-manager", "email": "manager@nascon.test", "role": "club_manager",
     "tenant_id": "tenant-alpha", "league_id": None, "club_id": "club-alpha-1", "player_id": None},
    {"user_id": "user-player", "email": "player@nascon.test", "role": "player",
     "tenant_id": "tenant-alpha", "league_id": None, "club_id": "club-alpha-1", "player_id": "player-alpha-1"},
    {"user_id": "user-viewer", "email": "viewer@nascon.test", "role": "viewer",
     "tenant_id": "tenant-alpha", "league_id": None, "club_id": None, "player_id": None},
]

PRODUCTS = [
    {"product_id": "prod-jersey-001", "tenant_id": "tenant-alpha", "club_id": "club-alpha-1",
     "name": "Alpha United Home Jersey", "category": "apparel"},
]

VARIANTS = [
    {"variant_id": "var-jersey-001-M", "product_id": "prod-jersey-001", "attributes": {"size": "M"},
     "price_minor": 450000},
    {"variant_id": "var-jersey-001-L", "product_id": "prod-jersey-001", "attributes": {"size": "L"},
     "price_minor": 450000},
]

DISCOUNT_CODES = [{"code": "WELCOME10", "percent": 10}]

_password_hashes: dict[str, str] = {}
_ready = False


def _demo_hash(email: str) -> str:
    # Salt derived from the email so that every reset writes identical rows.
    if email not in _password_hashes:
        salt = hashlib.sha256(f"nascon-demo|{email}".encode("utf-8")).digest()[:16]
        _password_hashes[email] = hash_password(DEMO_PASSWORD, salt)
    return _password_hashes[email]


def _insert(conn, table: str, rows: list[dict], json_cols: tuple[str, ...] = ()) -> None:
    cols = list(rows[0])
    values = ", ".join(f"CAST(:{c} AS JSONB)" if c in json_cols else f":{c}" for c in cols)
    stmt = text(f"INSERT INTO {table} ({', '.join(cols)}) VALUES ({values})")
    conn.execute(stmt, [{c: json.dumps(r[c]) if c in json_cols else r[c] for c in cols} for r in rows])


def reset_state(conn, seed: int = DEFAULT_SEED, stock: dict | None = None) -> dict:
    """Wipe every table and recreate the baseline. Runs inside the caller's transaction."""
    stock = {**DEFAULT_STOCK, **(stock or {})}
    db.apply_schema(conn)
    tables = conn.execute(
        text("SELECT tablename FROM pg_tables WHERE schemaname = current_schema()")
    ).scalars().all()
    conn.execute(text("TRUNCATE " + ", ".join(f'"{t}"' for t in tables) + " RESTART IDENTITY CASCADE"))

    _insert(conn, "app_meta", [{"key": "lots_seed", "value": seed}], json_cols=("value",))
    _insert(conn, "tenants", TENANTS, json_cols=("branding",))
    _insert(conn, "sports", [{"sport_id": s["sport_id"], "config": s} for s in SPORTS], json_cols=("config",))
    _insert(conn, "leagues", [{**lg, "config": {}} for lg in LEAGUES], json_cols=("config",))
    _insert(conn, "clubs", CLUBS, json_cols=("profile",))
    _insert(conn, "players", PLAYERS)
    _insert(conn, "users", [{**u, "password_hash": _demo_hash(u["email"])} for u in USERS])
    _insert(conn, "products", PRODUCTS)
    _insert(conn, "variants", [{**v, "stock": stock[v["variant_id"]], "reserved": 0} for v in VARIANTS],
            json_cols=("attributes",))
    _insert(conn, "discount_codes", DISCOUNT_CODES)

    return {
        "status": "reset_complete",
        "seed": seed,
        "sports": [s["sport_id"] for s in SPORTS],
        "tenants": [t["tenant_id"] for t in TENANTS],
        "stock": {v["variant_id"]: stock[v["variant_id"]] for v in VARIANTS},
    }


def ensure_ready() -> bool:
    """Create the schema and seed the baseline on first start. Safe to call repeatedly."""
    global _ready
    if _ready:
        return True
    try:
        with db.engine.begin() as conn:
            db.apply_schema(conn)
            if not conn.execute(text("SELECT EXISTS (SELECT 1 FROM tenants)")).scalar():
                reset_state(conn)
        _ready = True
    except Exception:
        log.exception("Database initialisation failed; will retry on the next health check.")
    return _ready


def baseline_present() -> bool:
    """True when the DB is reachable and the seed tenants and demo users exist."""
    if not ensure_ready():
        return False
    try:
        with db.engine.connect() as conn:
            tenants = conn.execute(
                text("SELECT count(*) FROM tenants WHERE tenant_id IN ('tenant-alpha', 'tenant-beta')")
            ).scalar()
            users = conn.execute(text("SELECT count(*) FROM users")).scalar()
        return tenants == len(TENANTS) and users >= len(USERS)
    except Exception:
        return False
