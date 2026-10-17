"""POST /audit/v1/fixtures — pure computation, stores nothing (spec §5.7)."""
from __future__ import annotations

import re
from typing import Any

from fastapi import APIRouter, Body

from app.errors import validation_error
from app.fixtures import double_elim, round_robin, single_elim, swiss

router = APIRouter()

ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,64}$")
FORMATS = {
    "round_robin": (2, 40),
    "swiss": (2, 64),
    "single_elim": (2, 128),
    "double_elim": (3, 128),
}



def _validate_teams(teams: Any, lo: int, hi: int) -> list[str]:
    fields: list[str] = []
    if not isinstance(teams, list):
        raise validation_error(["teams"])
    if not (lo <= len(teams) <= hi):
        raise validation_error(["teams"], f"Team count must be between {lo} and {hi}.")
    seen: set[str] = set()
    out: list[str] = []
    for i, t in enumerate(teams):
        if not isinstance(t, str) or not t or not ID_RE.match(t):
            fields.append(f"teams.{i}")
            continue
        if t in seen:
            fields.append(f"teams.{i}")
            continue
        seen.add(t)
        out.append(t)
    if fields:
        raise validation_error(fields)
    return out


@router.post("/audit/v1/fixtures")
def generate_fixtures(body: dict | None = Body(default=None)):
    body = body if isinstance(body, dict) else {}
    fmt = body.get("format")
    if not isinstance(fmt, str) or fmt not in FORMATS:
        raise validation_error(["format"], "Unsupported or missing tournament format.")
    lo, hi = FORMATS[fmt]
    teams = _validate_teams(body.get("teams"), lo, hi)
    params = body.get("params")
    if params is None:
        params = {}
    elif not isinstance(params, dict):
        raise validation_error(["params"])

    if fmt == "round_robin":
        return round_robin.generate(teams, params)
    if fmt == "swiss":
        return swiss.generate(teams, params)
    if fmt == "single_elim":
        return single_elim.generate(teams, params)
    if fmt == "double_elim":
        return double_elim.generate(teams, params)
    raise validation_error(["format"])
