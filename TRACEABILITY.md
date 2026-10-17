# Traceability

Maps every requirement ID to its source files and automated tests.
Status: ✅ done · 🟡 partial · ⬜ not started.

| ID | Requirement | Source | Tests | Status |
|---|---|---|---|---|
| FR-1.1 | Multi-sport taxonomy, mystery sport, event-sourced scoring, signed compensations | `backend/app/sports.py`, `backend/app/scoring.py`, `backend/app/signing.py`, `backend/app/schema.sql` | `tests/test_sports.py`, `tests/test_scoring.py`, `tests/test_signing.py` | ✅ mystery sport + events + score projection |
| FR-1.2 | League & tournament setup | `backend/app/leagues.py` | `tests/test_scoring.py` (league fixture stream) | 🟡 register league + match streams; multi-division not done |
| FR-1.3 | Fixtures: round-robin, Swiss, single/double elimination; match state machine | `backend/app/fixtures/` | `tests/test_fixtures.py` | ✅ four formats via `/audit/v1/fixtures` (pure compute); match state machine still open |
| FR-1.4 | Standings, tie-breakers, H2H, qualification status | `backend/app/standings.py`, `backend/app/signing.py` (`lots_key`), `backend/app/scoring.py` (projections) | `tests/test_standings.py`, `tests/test_signing.py` | ✅ table + H2H + resolve + qualification from event logs |
| FR-2.1 | Club profiles & tenant isolation | `backend/app/rbac.py` (probe P6), `backend/app/mobile_api.py` | `tests/test_rbac.py`, `tests/test_mobile_api.py` | ✅ RBAC isolation + `GET /api/v1/clubs/{id}` |
| FR-2.2 | Roster, transfers, loans, audit trail | `backend/app/roster.py`, `backend/app/schema.sql` | `tests/test_roster.py` | ✅ setup + transfer/loan/release + history/loan_return |
| FR-2.3 | Merchandise store, mock gateway, PDF receipt | `backend/app/store.py`, `backend/app/payment.py`, `backend/app/receipts.py`, `backend/app/events_queue.py`, `backend/app/schema.sql` | `tests/test_store.py` | ✅ inventory + checkout + signed PDF |
| FR-5.1 | Five-tier RBAC | `backend/app/auth.py`, `backend/app/rbac.py` | `tests/test_rbac.py`, `tests/test_auth_jwt.py` | ✅ matrix + P1–P7 + negative boundaries |
| NFR-3 | Concurrency-safe inventory | `backend/app/store.py` | `tests/test_store.py` (`test_nfr3_twenty_buyers_one_unit`) | ✅ 20 buyers / 1 unit |
| NFR-4 | Offline tolerance (mobile + `/offline-sync`) | `backend/app/offline_sync.py`, `backend/app/schema.sql` | `tests/test_offline_sync.py` | ✅ `/audit/v1/offline-sync`; mobile cache/queue pending APK |
| NFR-5 | Security: rate limit, input validation, 413, JWT | `backend/app/auth.py`, `backend/app/rate_limit.py`, `backend/app/main.py`, `backend/app/errors.py` | `tests/test_auth_jwt.py`, `tests/test_rate_limit.py`, `tests/test_app_basics.py` | ✅ JWT + `/api/v1/*` rate limit + 413 |
| NFR-7 | Reproducible `docker compose up -d --build`; baseline seed; `/health`; `/audit/v1/reset` | `docker-compose.yml`, `backend/Dockerfile`, `backend/app/schema.sql`, `backend/app/seed.py`, `backend/app/reset.py` | `tests/test_reset.py` | 🟡 reset + seed done; not yet run on a clean Ubuntu machine |
