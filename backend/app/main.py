from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from starlette.concurrency import run_in_threadpool

from app import auth, rbac, reset, seed, store
from app.errors import error_response, register_handlers
from app.rate_limit import RateLimitMiddleware

MAX_BODY_BYTES = 1024 * 1024


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Create the schema and seed the baseline (spec 5.4/5.5). Non-fatal: /health retries.
    await run_in_threadpool(seed.ensure_ready)
    yield


app = FastAPI(title="NaSCon '26 League Platform", lifespan=lifespan)
register_handlers(app)
app.add_middleware(RateLimitMiddleware)
app.include_router(reset.router)
app.include_router(auth.router)
app.include_router(rbac.router)
app.include_router(store.router)


@app.middleware("http")
async def limit_body_size(request: Request, call_next):
    # Spec 5.2: bodies over 1 MB -> 413 PAYLOAD_TOO_LARGE.
    length = request.headers.get("content-length")
    if length and length.isdigit() and int(length) > MAX_BODY_BYTES:
        return error_response(413, "PAYLOAD_TOO_LARGE", "Request body exceeds 1 MB.")
    if request.method in ("POST", "PUT", "PATCH"):
        body = await request.body()
        if len(body) > MAX_BODY_BYTES:
            return error_response(413, "PAYLOAD_TOO_LARGE", "Request body exceeds 1 MB.")
    return await call_next(request)


@app.get("/health")
def health():
    # Spec 5.4: 200 only when the DB is reachable and the baseline is seeded.
    if not seed.baseline_present():
        return error_response(503, "UNAVAILABLE", "Database is not reachable or not seeded.")
    return {"status": "ok"}


@app.get("/api/v1/ping")
def ping():
    # Rate-limited by RateLimitMiddleware (100 req / rolling 10 s per client IP).
    return {"pong": True}
