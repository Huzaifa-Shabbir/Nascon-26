# Architecture Decision Records

## ADR-1: Single FastAPI service + PostgreSQL + Redis
**Decision:** One Python 3.12 FastAPI service holds all domain logic. PostgreSQL
16 is the system of record and Redis 7 provides rate limiting and the domain
event queue (Redis Streams).

**Why:** It is the smallest stack that meets the contract. It builds quickly
(10-minute limit) and starts quickly (`/health` within 120 s). There are no
microservices to coordinate.

## ADR-2: Synchronous SQLAlchemy Core with psycopg 3
**Decision:** Endpoints are plain `def` functions that FastAPI runs in a
threadpool. SQL is explicit.

**Why:** Concurrency-critical paths such as checkout rely on row locks and
atomic `UPDATE ... WHERE stock >= q` statements, which are easy to read and
reason about in explicit SQL.

## ADR-3: Sports are data, not code
**Decision:** Each sport's rules (scoring model, scoring events, periods,
overtime, tie-break order, roster limits) are stored as JSON. The scoring and
standings engines dispatch only on `scoring_model` (`event`, `innings`,
`round`) and never on a sport or event name.

**Why:** Mystery sports must work without code changes, and hard-coded sport
logic costs 8 points.

## ADR-4: Event sourcing for match scores
**Decision:** Match events are an append-only table. Scores are recomputed from
the log on each read. A correction appends a signed `compensation` event and
never updates or deletes rows.

**Why:** This is required by FR-1.1 and §5.9. Standings are also recomputed
from the logs on every call (§5.10).

## ADR-5: Custom HS256 JWT for auth; RBAC policy matrix in code
**Decision:** We issue our own JWTs. One policy function decides each role,
scope and tenant check. Bad, expired or `alg:none` tokens get 401. Role or
tenant violations get 403.

**Why:** It is approved in §7 and simpler than running Keycloak.

## ADR-6: Mock payment gateway inside the API
**Decision:** The behaviour of the `tok_success`, `tok_declined` and
`tok_capture_fail` tokens lives in an in-process module.

**Why:** §1.1 requires a mock gateway that we build ourselves.

## ADR-7: Receipt PDFs with ReportLab
**Decision:** Receipt PDFs are generated server-side with ReportLab, a pure
Python library with no system packages.

**Why:** PDF libraries are allowed (§7). ReportLab keeps the Docker build small
and fast, and its text is extractable.
