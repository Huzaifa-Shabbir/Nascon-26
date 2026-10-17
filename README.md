# NaSCon '26 — Multi-Sport League & Club Operations Platform

Backend: Python 3.12 + FastAPI, PostgreSQL 16, Redis 7 (Docker Compose).
Mobile: Flutter (Android), in `mobile/`. Release APK: `mobile/release/app-release.apk`.

## Run the backend (graded path)

```bash
DAY1_SALT=<team-salt> docker compose up -d --build
curl http://localhost:8080/health      # -> {"status":"ok"}
```

On Windows PowerShell with Docker Desktop:

```powershell
$env:DAY1_SALT = '<team-salt>'; docker compose up -d --build
curl.exe http://localhost:8080/health
```

The API is on host port **8080**. The audit interface is under `/audit/v1/*`.

## Local development (without Docker)

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\pip install -r requirements-dev.txt
copy ..\.env.example ..\.env    # then fill in DAY1_SALT, DATABASE_URL, REDIS_URL
.\.venv\Scripts\python -m uvicorn app.main:app --port 8080 --reload
```

Point `DATABASE_URL`/`REDIS_URL` at your own local Postgres and Redis. Use a
database you can lose: `/audit/v1/reset` wipes everything in the target DB.

## Tests

```bash
./run_tests.sh          # pytest + per-module coverage
```

DB- and Redis-backed tests **truncate data**, so they only run against
disposable services. With Docker available, `./run_tests.sh` starts throwaway
Postgres 16 and Redis 7 containers on free localhost ports and removes them on
exit. To reuse your own disposable services instead:

```bash
TEST_DATABASE_URL=postgresql://t:t@localhost:55432/t TEST_REDIS_URL=redis://localhost:56379/0 ./run_tests.sh
```

Without Docker or those variables, the DB/Redis tests are skipped.

## Demo accounts

All passwords: `Nascon@26`.

| Role | Email |
|---|---|
| Platform Super-Admin | admin@nascon.test |
| League Organizer (league-alpha-1) | organizer@nascon.test |
| Club Manager (club-alpha-1) | manager@nascon.test |
| Player (player-alpha-1) | player@nascon.test |
| General Viewer | viewer@nascon.test |

## Mobile app

Set the server address in the app's settings: `http://10.0.2.2:8080` on the
emulator, or `http://<laptop-LAN-IP>:8080` on a phone.

## Repository map

| Path | Purpose |
|---|---|
| `docker-compose.yml` | API + Postgres + Redis |
| `backend/app/` | API source |
| `tests/`, `run_tests.sh` | Unit tests |
| `COVERAGE.json` | Declared line coverage per backend area |
| `TRACEABILITY.md` | FR/NFR → source + tests |
| `ADR.md` | Architecture decisions |
| `mobile/` | Flutter app |
