"""Standard error body (spec Section 5.2) and exception handlers."""
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str = "", details: dict | None = None):
        self.status = status
        self.code = code
        self.message = message or code
        self.details = details or {}


def error_response(status: int, code: str, message: str = "", details: dict | None = None, headers=None):
    body = {"error": {"code": code, "message": message or code, "details": details or {}}}
    return JSONResponse(status_code=status, content=body, headers=headers)


def validation_error(fields: list[str], message: str = "Request validation failed.") -> ApiError:
    return ApiError(400, "VALIDATION_ERROR", message, {"fields": fields})


def register_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError):
        return error_response(exc.status, exc.code, exc.message, exc.details)

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError):
        fields = []
        for err in exc.errors():
            loc = [str(p) for p in err.get("loc", []) if p != "body"]
            name = ".".join(loc) if loc else "body"
            if name not in fields:
                fields.append(name)
        return error_response(400, "VALIDATION_ERROR", "Request validation failed.", {"fields": fields})

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException):
        code = {404: "NOT_FOUND", 405: "METHOD_NOT_ALLOWED"}.get(exc.status_code, "HTTP_ERROR")
        return error_response(exc.status_code, code, str(exc.detail))

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception):
        # Spec forbids 5xx for bad input; this is a last-resort safety net.
        return error_response(500, "INTERNAL_ERROR", "Unexpected server error.")
