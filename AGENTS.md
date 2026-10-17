# AGENTS.md — NaSCon '26 App Dev, Part I

This file is for AI coding agents (Claude Code, Codex, Cursor, etc.) and for the
humans working in this repo.

**We are building a Multi-Sport League & Club Operations Platform**, with:
- a backend: REST API, realtime layer, event-sourced scoring, job queue, RBAC;
- an offline-tolerant Android app.

The binding contract is `NaSCon 26 App Dev Part 1-1.pdf` in the repo root. If
this file and the PDF disagree, **the PDF wins**. Python grading scripts compare
field names, status codes and error codes **literally**.

## 0. Deadlines (PKT, UTC+5) — Day 1, Sat 17 Oct 2026

| When | What |
|---|---|
| **before 11:15** | Repo is **public** and its URL is registered at the venue desk. |
| 10:45–11:45, 11:45–12:45, 12:45–13:45, 13:45–14:45 | Push ≥1 commit in **every** window. Each missed window costs −2. |
| **before 13:00** | Last time to raise contract questions **in writing**. |
| 15:00 | Part I locks. |
| **15:05:00** | Final push. The grader checks out the last commit pushed at or before this time. |
| from 15:15 | 10-minute judging slot at the desk. Backend must be running and the APK installed. |

Day 2 (18 Oct) sprint runs 10:15–14:00, pushes close 14:05. No pushes between
Day 1 15:05 and Day 2 10:15. The Part II scope is released at 10:15 on Day 2.

Commit small and often. Never leave `main` broken near a window boundary.

## 1. Hard rules / penalties

- **`DAY1_SALT` comes only from the environment at startup.** Never hard-code or
  commit it. `docker-compose.yml` must forward `DAY1_SALT: ${DAY1_SALT}`.
- **Never commit secrets.** No real salt, passwords, keys or populated `.env`
  files. Only `.env.example` with placeholders.
- **No hard-coded sport logic (−8).** Domain code must never branch on a sport
  name or an event name (`"football"`, `"goal"`, `"wicket"`, …). Everything comes
  from the sport config stored as data. Seeded sports use the same schema as
  mystery sports.
- **No managed BaaS (−10).** No Firebase, Supabase, Amplify, etc. Everything is
  self-hosted via Docker Compose. Payments go through **our own mock gateway**.
- **No third-party fixture-generation libraries.** Write round-robin, Swiss,
  single-elim and double-elim ourselves. Web frameworks, ORMs, JWT libraries
  and PDF libraries are fine.
- **Reproducible stack (−10).** On a clean Ubuntu 22.04 machine (4 vCPU, 8 GB,
  Docker 24+, Compose v2), `DAY1_SALT=<salt> docker compose up -d --build` must:
  - finish building within **10 min**;
  - have `GET /health` return 200 within **120 s**;
  - need no manual steps, no pre-created volumes, and nothing installed on the
    host but Docker;
  - keep running with **no Internet** once built.
- **Nothing may depend on another machine.** Everything runs from our own
  `docker compose up`, and services reach each other by compose service name only.

## 2. Required repo layout

```
docker-compose.yml        # whole backend; API on host port 8080
.env.example              # every env var, placeholders only
README.md                 # run instructions + the 5 demo accounts
TRACEABILITY.md           # every FR/NFR id -> source files + tests
tests/  run_tests.sh      # one script runs all unit tests
COVERAGE.json             # {"fixtures":..,"scoring":..,"standings":..,"store":..,"roster":..,"rbac":..}
backend/                  # API service source
mobile/                   # app source
mobile/release/app-release.apk   # built APK, committed
```

- Keep `COVERAGE.json` honest. Judges may run `./run_tests.sh`, and a claim more
  than 2 points too high voids that area's bonus.
- Each backend area scores `0.9·P·(passed/total) + 0.1·P·[coverage ≥ 85%]`.

## 3. Stack (approved list, §7)

| Concern | Choice |
|---|---|
| API | Python 3.12 + FastAPI (or another framework). The image is already cached. |
| DB | PostgreSQL 16 |
| Cache / rate limit / queue | Redis 7. Use Redis Streams for domain events; RabbitMQ/NATS also allowed. |
| Object store | MinIO, for receipt PDFs if stored. Optional. |
| Auth | Custom JWT (HS256). Reject `alg:none`, tampered and expired tokens. |
| PDF | WeasyPrint / wkhtmltopdf / Puppeteer, or any PDF library. Text must be extractable. |
| Tests | pytest |
| Mobile | Android APK (Flutter). Local DB via SQLite/Hive. Tokens in Keystore via `flutter_secure_storage`. |

**Not needed for Part I:** LiveKit, MediaMTX, ntfy, Prometheus/Grafana and
Selenium are decoys. Realtime updates use the API's own WebSocket/SSE. Do not add
services that slow down build or startup.

## 4. Global API conventions (§5.2)

- Base URL `http://localhost:8080`. JSON UTF-8 in and out.
- `/audit/v1/*` needs no auth, except the RBAC probe routes.
- **Ids:** 1–64 chars from `[A-Za-z0-9_.:-]`, never containing `|`, case-sensitive.
  Store and return grader-chosen ids verbatim.
- **Timestamps** are `YYYY-MM-DDTHH:MM:SSZ` (UTC). **Dates** are `YYYY-MM-DD`.
- **Money** is an integer in minor units (paisa). Currency is always `"PKR"`.
- Ignore unknown fields. A missing required field or a wrong type → 400.
- **Validation order:** 400 schema → 404 missing referenced id → 409 business
  rule (402 for payment). The first failing step wins.
- **Idempotency:** a request with a client id (`event_id`, `order_id`,
  `request_id`, `action_id`) that is replayed identically returns the stored
  result with **200** and changes nothing. The same id with a different body →
  409 `DUPLICATE_*`.
- **Rate limits:** `/audit/v1/*` and `/health` are exempt; the grader may send
  200 req/s. `/api/v1/*` allows 100 requests per rolling 10 s per client IP.
  Over the limit → 429 `RATE_LIMITED` with a `Retry-After` header.
- **Timing:** each request must finish in under 5 s. `/reset` must finish in
  under 10 s. The 20-checkout burst must complete in under 10 s.
- **Body size:** over 1 MB → 413 `PAYLOAD_TOO_LARGE`.
- **Never return a 5xx.** SQL-injection and `<script>` strings are plain data.
- **Error body for every non-2xx:**
  ```json
  {"error":{"code":"UPPER_SNAKE","message":"free text","details":{}}}
  ```
  For `VALIDATION_ERROR`, `details.fields` is an array of bad field names.
- **Codes:** 201 means first create/apply, 200 means read or replay. 401 =
  missing or bad token, 403 = role or tenant boundary. Cross-tenant access is
  always 403, never 404.

## 5. Signature recipe (§5.3, Appendix A) — must match byte-for-byte

```python
import hmac, hashlib, json
def canonical(obj): return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
def sign(salt, id_, payload_obj):
    msg = (id_ + "|" + canonical(payload_obj)).encode("utf-8")
    return hmac.new(salt.encode("utf-8"), msg, hashlib.sha256).hexdigest()
def lots_key(seed, league_id, team_id):
    return hashlib.sha256(f"{seed}|{league_id}|{team_id}".encode("utf-8")).hexdigest()
```

- **Events:** `id = event_id`, and the payload is the request's `payload`.
- **Receipts:** `id = order_id`, and the payload is `receipt.payload` exactly as
  returned.
- **Test vector 1:** salt `demo-salt`, id `evt-1`, payload
  `{"team_id":"t1","event_type":"goal"}` →
  `972a8b558690b19121cc5bea84978f85e8eb15a3735018db36616bab1d7ec501`.
- **Test vector 2:** seed 42, league `lg-1`. The `lots_key` values are
  `t1 0613…3293`, `t2 e3e3…5dd9`, `t3 c8f2…7028`, so the order is t1, t3, t2.
- Put both vectors in unit tests.

## 6. Endpoint index and must-know rules

| Route | Key rules |
|---|---|
| `GET /health` | 200 `{"status":"ok"}` only when the DB is reachable **and** seed data exists. |
| `POST /audit/v1/reset` | Body `{seed?=42, stock?={var-jersey-001-M:1, var-jersey-001-L:5}}`. Wipes all state and reseeds identically on every call. Returns `{status:"reset_complete", seed, sports[4], tenants[2], stock}`. |
| `POST /audit/v1/sports` | Mystery sport from JSON. Validation in §5.6: `sport_id` matches `^[a-z0-9_-]{2,40}$`; duplicate → 409 `SPORT_EXISTS`. Usable immediately by events, leagues, standings and fixtures. |
| `POST /audit/v1/fixtures` | Pure computation, stores nothing. Formats: `round_robin`, `swiss`, `single_elim`, `double_elim`. |
| `POST /audit/v1/leagues` | Registers teams, fixtures, points, tie-break order, `qualification.spots` and `lots_seed`. Each fixture becomes an `upcoming` match stream. |
| `POST /audit/v1/events` | Append-only signed log. Types: `match_init`, `match_start`, `score`, `discipline`, `tiebreak_winner`, `match_end`, `compensation`. |
| `GET /audit/v1/score/{match_id}` | Projection **rebuilt from the log on every read**. Never use mutable counters as the source of truth. |
| `GET /audit/v1/standings/{league_id}` | Recomputed from scratch on every call: table, h2h, qualification status, `resolved_by`. |
| `POST /audit/v1/roster/setup` | Re-sending the same `league_id` replaces that league's roster state. |
| `POST /audit/v1/roster/transfer` | transfer, loan or release. Rule checks run in the **exact order** of §5.11. |
| `GET /audit/v1/roster/history/{player_id}?as_of=` | Append-only audit. The automatic `loan_return` entry is written once. |
| `POST /audit/v1/checkout` | Concurrency-safe purchase, mock gateway, signed receipt and PDF. |
| `GET /audit/v1/inventory/{variant_id}` | `{variant_id, stock, reserved}` |
| `POST /audit/v1/rbac-matrix` | Returns JWTs for all 5 roles plus the context ids. |
| `/audit/v1/rbac/*` (P1–P7) | Authorization only. Allowed → 200 `{"authorized":true}`. Denied → 403 `FORBIDDEN`. Bad token → 401 `UNAUTHENTICATED`. |
| `GET /api/v1/ping` | `{"pong":true}` and rate-limited. |
| `POST /audit/v1/offline-sync` | Replays queued mobile actions (§5.14). Always 200 overall. |

### Fixtures (§5.7) — exact parts

**Round-robin**
- Circle method. Matches per round = floor(n/2). Rounds per leg = n−1 for even
  n, n for odd n. For odd n there is exactly one bye per team per leg.
- `match_id` is `RR-L{leg}-R{round}-M{i}`. Round numbers are global, so leg 2
  continues after leg 1.
- Home/away difference is at most 1 per team per leg. With `legs=2`, every
  ordered pair occurs once.
- **Withdrawals:**
  - `forfeit_remaining`: rounds after `after_round` get status `forfeit` with
    `awarded_to` set to the opponent.
  - `void_all`: every fixture of that team is `voided` with `awarded_to:null`.
  - If both teams in a fixture withdrew, it is voided.
  - Fixtures are never removed from the list.

**Swiss**
- Scoring: win 1, draw 0.5, bye 1. Buchholz = sum of the opponents' current
  scores; a bye adds 0.
- Round 1 is exact: m = floor(n/2), seed i plays seed i+m, and the lower seed is
  home. For odd n, the last seed gets the bye.
- Rounds 2 and later:
  - The bye goes to the lowest-ranked team that has not had one yet.
  - There are no rematches.
  - The pairing must **minimise the total |score difference|**. Use
    backtracking, because greedy pairing fails.
  - If no valid pairing exists → 409 `NO_VALID_PAIRING` with `details.round`.

**Single elimination**
- B = next power of two ≥ n. Seed order is built recursively, e.g.
  `order(8)=[1,8,4,5,2,7,3,6]`.
- Round-1 match i takes entries 2i−1 and 2i, and the lower seed is home.
- A missing seed means `bye:true`, `away:null`, and the winner is propagated
  immediately.
- Ids are `R{r}M{i}`. The winner goes to `R{r+1}M{ceil(i/2)}`: slot `home` if
  i is odd, `away` if i is even.
- An optional `TP` match for third place takes the semifinal losers.

**Double elimination**
- Same seeding as single elimination.
- Ids:
  - Winners bracket: `WR{r}M{i}`.
  - Losers bracket: `LR{r}M{i}`. There are 2(k−1) losers rounds, rounds 2j−1
    and 2j each have B/2^(j+1) matches, for B−2 in total.
  - Grand final: `GF1`, plus `GF2` only when `bracket_reset:true`.
- `GF2.conditional` is true. `GF2.required` stays null until GF1 has a result.
  It then becomes true only if the losers-bracket champion (`GF1.away`) won GF1.

### Events and scoring (§5.9)

- **Scoring model limits:**
  - innings: once a team's legal balls or wickets reach the configured caps,
    further score events → 409 `INNINGS_COMPLETE`.
  - round: once a team has `(best_of+1)/2` wins → 409 `SERIES_ALREADY_DECIDED`.
- **Compensation:**
  - It may target only a `score`, `discipline` or `tiebreak_winner` event in the
    same match.
  - Unknown target → 404 `EVENT_NOT_FOUND`. Already compensated, wrong type or
    other match → 409 `INVALID_COMPENSATION`.
  - The compensated event and the compensation itself are both neutral in the
    projection.
- **`match_end`:** a level score with `draw_allowed:false` and no active
  `tiebreak_winner` → 409 `TIE_NOT_ALLOWED`.
- **Event response fields:**
  - `sequence` is the 1-based position in the log; every event type counts.
  - `match_version` is the event count after the append.
- **`outcome`** is one of `pending`, `home_win`, `away_win`, `draw`,
  `undecided`.
- **Innings output:** `overs` is the string `"{balls div bpo}.{balls mod bpo}"`.
  `wickets`, `balls` and `overs` are null for non-innings sports.

### Standings (§5.10) — ordering is exact

1. Sort by points, best first. Tied teams form a group.
2. `resolve(group)` walks the `tie_break_order` criteria and always ends with
   `draw_lots`. At the first criterion that splits the group, resolve each
   sub-group of size > 1 recursively **from the first criterion**.
3. `h2h_*` uses only completed matches among the current group (a mini-league).
   Higher is better for every criterion.
4. `draw_lots` sorts ascending by `lots_key`.
5. Only `completed` matches with outcome ≠ `undecided` count as played.

For innings sports, `diff` is net run rate rounded to 3 dp. An all-out innings
counts as the full overs.

Qualification uses points only. With W = win points and k = spots:

    max(T) = pts(T) + W × remaining(T)

- **clinched** if fewer than k other teams have max(X) ≥ pts(T). This is checked
  first.
- **eliminated** if at least k other teams have pts(X) > max(T).
- Otherwise **still_possible**.

### Roster (§5.11)

**Check order (first failure wins):**
1. 400 validation
2. 404 `LEAGUE_NOT_FOUND`, `PLAYER_NOT_FOUND` or `SQUAD_NOT_FOUND`
3. `CROSS_TENANT_TRANSFER`
4. `NOT_IN_SQUAD`
5. `TRANSFER_WINDOW_CLOSED` (window dates are inclusive; release is allowed any
   time)
6. `PLAYER_ON_LOAN`
7. `SQUAD_FULL`
8. `MIN_POSITION_VIOLATION`

**Effects:**
- **transfer:** the player's role becomes `substitute`.
- **loan:** the player counts toward the borrower's squad. An automatic
  `loan_return` (who = `"system"`) is recorded the day after `loan_end_date`,
  evaluated against `as_of`.
- **In-progress match:** the request is still accepted, with
  `state:"deferred_until_match_end"` and `blocking_match_id` set.

### Checkout (§5.12) — NFR-3

The grader fires 20 parallel buyers at stock 1. Expected result: exactly one
201, nineteen 409 `OUT_OF_STOCK`, then `stock=0` and `reserved=0`.

**Reserving stock:** use an atomic DB statement, such as
`UPDATE … SET stock = stock - q WHERE stock >= q` or `SELECT … FOR UPDATE`,
inside one transaction.

**Mock payment tokens:**
- `tok_success`
- `tok_declined` → release the reservation and return 402 `PAYMENT_DECLINED`.
- `tok_capture_fail` → release the reservation and return 402
  `PAYMENT_CAPTURE_FAILED`.

**Discounts:** `WELCOME10` is the only valid code, with
`discount = floor(subtotal × 10 / 100)`. Any other code → 400
`INVALID_DISCOUNT_CODE`.

**Receipt:**
- The response includes the signed `receipt.payload` and `pdf_base64`.
- The PDF starts with `%PDF`, and its extracted text contains the `order_id` and
  `PKR 4500.00` (two decimals, no thousands separator).
- Every order status change emits a domain event to the internal queue.

### RBAC (§5.13)

**Roles:** `super_admin`, `league_organizer`, `club_manager`, `player`,
`viewer`. All except super_admin belong to tenant-alpha.

**Who owns what:**
- The organizer owns `league-alpha-1`.
- The manager owns `club-alpha-1`.
- The player is `player-alpha-1`.

**Probe matrix (A = allowed):**
- **P1** `POST rbac/tenants`: super admin only.
- **P2** `POST rbac/leagues/{id}/fixtures`: super admin, plus the organizer on
  its own league.
- **P3/P4** `POST rbac/clubs/{id}/roster` and `/products`: super admin, plus the
  manager on its own club.
- **P5** `PATCH rbac/players/{id}`: super admin; the manager for its own club's
  players; the player for itself.
- **P6** `GET rbac/clubs/{id}`: all roles for tenant-alpha clubs. For foreign
  clubs, super admin only.
- **P7** `GET rbac/platform/config`: super admin only.

Authorization is evaluated before anything else in the request.

### Offline sync (§5.14)

- Actions are `score_event` (payload = `/events` body) or `roster_transfer`
  (payload = `/roster/transfer` body).
- Process them sorted by `queued_at` (ties keep array order) against the
  evolving state. Return results in request order.

| Situation | status | resolution | error_code |
|---|---|---|---|
| Rules allow it and `base_version` == current | `applied` | `appended` | null |
| Rules allow it but `base_version` < current | `applied` | `rebased_append` | null |
| Already processed (`device_id`, `action_id`), or same `event_id` with same payload | `duplicate` | `skipped_duplicate` | null |
| A domain rule rejects it | `rejected` | `server_wins` | that rule's code |
| `base_version` > current | `rejected` | `server_wins` | `INVALID_BASE_VERSION` |
| Referenced id unknown | `rejected` | `server_wins` | `*_NOT_FOUND` |

- The version is the match's event count for score events and the player's
  audit-entry count for roster transfers.
- Each result includes `processed_order`, `server_version`, and `signature`
  (applied score events only).
- The response ends with a `summary`.

## 7. Seed data (`/reset` and startup — exact ids)

- **Tenants:** `tenant-alpha` ("Alpha Sports"), `tenant-beta` ("Beta Athletics").
- **Leagues:** `league-alpha-1` and `league-alpha-2` (alpha), `league-beta-1`
  (beta).
- **Clubs:** `club-alpha-1`, `club-alpha-2`, `club-beta-1`.
- **Players:** `player-alpha-1` (club-alpha-1), `player-alpha-2` (club-alpha-2),
  `player-beta-1` (club-beta-1).
- **Store:** `prod-jersey-001` (alpha) with variants `var-jersey-001-M` and
  `var-jersey-001-L`, each priced `450000` PKR minor. Discount code `WELCOME10`.
- **Sports:** `football`, `basketball`, `cricket`, `esports`, stored as plain
  data. The configs are in the table on p.8 of the PDF.

**Demo users** (password `Nascon@26` for all):

| Email | Role |
|---|---|
| `admin@nascon.test` | super admin |
| `organizer@nascon.test` | league organizer |
| `manager@nascon.test` | club manager |
| `player@nascon.test` | player |
| `viewer@nascon.test` | viewer |

## 8. Mobile app (§8) — 14 of the 50 points

**Delivery:**
- Commit the APK at `mobile/release/app-release.apk`. It must install on
  Android 10 (API 29) or newer.
- The server URL must be configurable in the app: `10.0.2.2:8080` on the
  emulator, the laptop's LAN IP on a phone.
- Store tokens securely (Keystore).

**Screens:**
- Login: email + password, then a role-aware home screen.
- Fixtures.
- Match detail: live score via WS/SSE, event timeline, pinned product.
- Standings, including qualification status.
- Club profile.
- Store: variants, cart, mock checkout, view the receipt.
- Roster management (manager): add, transfer, loan, release.
- Scoring entry (organizer): score event and compensation.
- Sync status: an always-visible online / offline / syncing indicator plus the
  pending queue.

**Offline desk check:**
1. Fixtures, standings and a club profile open from the local DB in airplane
   mode.
2. One scoring action and one roster action are queued in the §5.14 format.
   They show as pending and survive a force-close.
3. When the network returns, the app syncs and shows per-action results with
   plain-language reasons.

**UI/HCI (10 pts):**
- Consistent theme with the tenant logo and colors.
- Loading states, success messages and confirmation before risky actions.
- No raw error codes.
- Tap targets of at least 48 dp. Meaning is never shown by color alone.
- Helpful empty states.
- Nothing overflows at 360×640 or after rotation.
- Each role sees only what it can use.

## 9. Pre-submission checklist (Appendix C)

- [ ] `DAY1_SALT=x docker compose up -d --build` on a clean machine, and
  `/health` is 200 in under 2 min.
- [ ] Two `/reset` calls in a row leave identical data, and all seed ids and
  demo accounts exist.
- [ ] Response JSON is compared character by character with the PDF examples.
- [ ] Both Appendix A test vectors pass.
- [ ] 20 parallel checkouts give 1×201 and 19×409, then stock 0 and reserved 0.
- [ ] `/audit/v1/*` is not rate-limited; `/api/v1/ping` is.
- [ ] `COVERAGE.json`, `TRACEABILITY.md`, `README.md`, `.env.example` and the APK
  are committed.
- [ ] Last push before 15:05:00.
