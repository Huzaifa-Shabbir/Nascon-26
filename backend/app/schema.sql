-- Base schema. Applied idempotently at startup and before every /audit/v1/reset.
-- Statements are split on semicolons, so keep them out of comments and literals.
-- /reset truncates every table in this schema, so new tables are wiped automatically.

CREATE TABLE IF NOT EXISTS app_meta (
    key   TEXT PRIMARY KEY,
    value JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS tenants (
    tenant_id TEXT PRIMARY KEY,
    name      TEXT NOT NULL,
    branding  JSONB NOT NULL DEFAULT '{}'
);

-- config holds the full spec 5.6 sport document (seeded and mystery sports alike).
CREATE TABLE IF NOT EXISTS sports (
    sport_id TEXT PRIMARY KEY,
    config   JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS leagues (
    league_id TEXT PRIMARY KEY,
    tenant_id TEXT,
    sport_id  TEXT,
    name      TEXT,
    config    JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS clubs (
    club_id   TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    name      TEXT NOT NULL,
    profile   JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS players (
    player_id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    club_id   TEXT,
    name      TEXT NOT NULL,
    position  TEXT
);

CREATE TABLE IF NOT EXISTS users (
    user_id       TEXT PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL,
    tenant_id     TEXT,
    league_id     TEXT,
    club_id       TEXT,
    player_id     TEXT
);

CREATE TABLE IF NOT EXISTS products (
    product_id TEXT PRIMARY KEY,
    tenant_id  TEXT NOT NULL,
    club_id    TEXT,
    name       TEXT NOT NULL,
    category   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS variants (
    variant_id  TEXT PRIMARY KEY,
    product_id  TEXT NOT NULL,
    attributes  JSONB NOT NULL DEFAULT '{}',
    price_minor BIGINT NOT NULL,
    currency    TEXT NOT NULL DEFAULT 'PKR',
    stock       INTEGER NOT NULL CHECK (stock >= 0),
    reserved    INTEGER NOT NULL DEFAULT 0 CHECK (reserved >= 0)
);

CREATE TABLE IF NOT EXISTS discount_codes (
    code    TEXT PRIMARY KEY,
    percent INTEGER NOT NULL
);

-- Completed checkouts for idempotent replay (spec 5.12).
CREATE TABLE IF NOT EXISTS orders (
    order_id      TEXT PRIMARY KEY,
    request_hash  TEXT NOT NULL,
    request_body  JSONB NOT NULL,
    response_body JSONB NOT NULL,
    status        TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Optional durable mirror of domain events also published to Redis Streams.
CREATE TABLE IF NOT EXISTS domain_events (
    event_id   BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    payload    JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Match streams (league fixtures or match_init). Status/outcome are derived from the log.
CREATE TABLE IF NOT EXISTS matches (
    match_id      TEXT PRIMARY KEY,
    sport_id      TEXT NOT NULL,
    league_id     TEXT,
    home_team_id  TEXT NOT NULL,
    away_team_id  TEXT NOT NULL
);

-- Append-only signed event log (spec §5.9). Never update/delete rows for corrections.
CREATE TABLE IF NOT EXISTS match_events (
    event_id      TEXT PRIMARY KEY,
    match_id      TEXT NOT NULL REFERENCES matches (match_id),
    type          TEXT NOT NULL,
    payload       JSONB NOT NULL,
    sequence      INTEGER NOT NULL,
    signature     TEXT NOT NULL,
    request_hash  TEXT NOT NULL,
    response_body JSONB NOT NULL,
    UNIQUE (match_id, sequence)
);

CREATE INDEX IF NOT EXISTS match_events_match_seq ON match_events (match_id, sequence);
