from fastapi import FastAPI, Request

from app import db
from app.errors import error_response, register_handlers

MAX_BODY_BYTES = 1024 * 1024

app = FastAPI(title="NaSCon '26 League Platform")
register_handlers(app)


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
    # TODO(reset stage): also require that baseline seed data exists (spec 5.4).
    if not db.db_reachable():
        return error_response(503, "UNAVAILABLE", "Database is not reachable.")
    return {"status": "ok"}


@app.get("/api/v1/ping")
def ping():
    # TODO(security stage): 100 req / rolling 10 s per client IP -> 429 (spec 5.13).
    return {"pong": True}
