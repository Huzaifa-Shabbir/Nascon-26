# Traceability

Maps every requirement ID to its source files and automated tests.
Status: ✅ done · 🟡 partial · ⬜ not started.

| ID | Requirement | Source | Tests | Status |
|---|---|---|---|---|
| FR-1.1 | Multi-sport taxonomy, mystery sport, event-sourced scoring, signed compensations | `backend/app/signing.py` | `tests/test_signing.py` | 🟡 signatures only |
| FR-1.2 | League & tournament setup | — | — | ⬜ |
| FR-1.3 | Fixtures: round-robin, Swiss, single/double elimination; match state machine | — | — | ⬜ |
| FR-1.4 | Standings, tie-breakers, H2H, qualification status | `backend/app/signing.py` (`lots_key`) | `tests/test_signing.py` | 🟡 draw-of-lots key only |
| FR-2.1 | Club profiles & tenant isolation | — | — | ⬜ |
| FR-2.2 | Roster, transfers, loans, audit trail | — | — | ⬜ |
| FR-2.3 | Merchandise store, mock gateway, PDF receipt | — | — | ⬜ |
| FR-5.1 | Five-tier RBAC | — | — | ⬜ |
| NFR-3 | Concurrency-safe inventory | — | — | ⬜ |
| NFR-4 | Offline tolerance (mobile + `/offline-sync`) | — | — | ⬜ |
| NFR-5 | Security: rate limit, input validation, 413, JWT | `backend/app/main.py`, `backend/app/errors.py` | `tests/test_app_basics.py` | 🟡 413 + error body |
| NFR-7 | Reproducible `docker compose up -d --build` | `docker-compose.yml`, `backend/Dockerfile` | — | 🟡 not yet run on clean machine |
