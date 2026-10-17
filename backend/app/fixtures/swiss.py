"""Swiss-system pairing for one round (spec §5.7 B)."""
from __future__ import annotations

import math
from typing import Any

from app.errors import ApiError, validation_error


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _seed_index(teams: list[str], team_id: str) -> int:
    return teams.index(team_id)


def _compute_standings(teams: list[str], history: list[dict]) -> list[dict]:
    scores = {t: 0.0 for t in teams}
    opponents: dict[str, list[str]] = {t: [] for t in teams}
    byes_had: set[str] = set()

    for entry in history:
        bye = entry.get("bye")
        if bye is not None:
            if bye not in scores:
                raise validation_error(["params.history"])
            scores[bye] += 1.0
            byes_had.add(bye)
        for m in entry.get("matches") or []:
            home, away = m["home"], m["away"]
            result = m["result"]
            opponents[home].append(away)
            opponents[away].append(home)
            if result == "home":
                scores[home] += 1.0
            elif result == "away":
                scores[away] += 1.0
            elif result == "draw":
                scores[home] += 0.5
                scores[away] += 0.5

    buchholz = {
        t: sum(scores[o] for o in opponents[t]) for t in teams
    }

    ordered = sorted(
        teams,
        key=lambda t: (-scores[t], -buchholz[t], _seed_index(teams, t)),
    )
    standings = []
    for rank, t in enumerate(ordered, start=1):
        standings.append(
            {
                "rank": rank,
                "team_id": t,
                "score": scores[t],
                "buchholz": buchholz[t],
            }
        )
    return standings, scores, byes_had, _played_pairs(history)


def _played_pairs(history: list[dict]) -> set[frozenset[str]]:
    pairs: set[frozenset[str]] = set()
    for entry in history:
        for m in entry.get("matches") or []:
            pairs.add(frozenset((m["home"], m["away"])))
    return pairs


def _round1(teams: list[str]) -> tuple[list[dict], str | None]:
    n = len(teams)
    m = n // 2
    bye = teams[-1] if n % 2 == 1 else None
    pairings = []
    for i in range(m):
        # seeds are 1-indexed: seed i+1 vs seed i+1+m; lower seed home
        a = teams[i]          # seed i+1
        b = teams[i + m]      # seed i+1+m
        home, away = a, b     # lower seed number = earlier index
        pairings.append(
            {
                "match_id": f"SW-R1-M{i + 1}",
                "home": home,
                "away": away,
            }
        )
    return pairings, bye


def _min_diff_pairing(
    candidates: list[str],
    scores: dict[str, float],
    played: set[frozenset[str]],
) -> list[tuple[str, str]] | None:
    """Backtracking: pairing that minimises Σ|score diff| with no rematches."""
    n = len(candidates)
    if n == 0:
        return []
    if n % 2 == 1:
        return None

    best: list[tuple[str, str]] | None = None
    best_cost = float("inf")

    def score_diff(a: str, b: str) -> float:
        return abs(scores[a] - scores[b])

    def bt(remaining: list[str], pairs: list[tuple[str, str]], cost: float):
        nonlocal best, best_cost
        if cost >= best_cost:
            return
        if not remaining:
            best = list(pairs)
            best_cost = cost
            return
        a = remaining[0]
        rest = remaining[1:]
        for i, b in enumerate(rest):
            if frozenset((a, b)) in played:
                continue
            bt(rest[:i] + rest[i + 1 :], pairs + [(a, b)], cost + score_diff(a, b))

    bt(candidates, [], 0.0)
    return best


def _pair_round(
    teams: list[str],
    standings: list[dict],
    scores: dict[str, float],
    byes_had: set[str],
    played: set[frozenset[str]],
    round_no: int,
) -> tuple[list[dict], str | None]:
    n = len(teams)
    odd = n % 2 == 1
    # Ranked worst-first for bye candidates: lowest score, then lowest seed (largest index).
    ranked = [s["team_id"] for s in standings]
    # standings already best-first; reverse for lowest-ranked first, with seed tie-break
    # Spec: lowest-scoring that has not had a bye; tie → lowest seed (largest index).
    bye_order = sorted(
        teams,
        key=lambda t: (scores[t], -_seed_index(teams, t)),
    )

    if not odd:
        pairing = _min_diff_pairing(list(ranked), scores, played)
        if pairing is None:
            raise ApiError(
                409,
                "NO_VALID_PAIRING",
                f"No rematch-free pairing for round {round_no}.",
                {"round": round_no},
            )
        pairings = [
            {"match_id": f"SW-R{round_no}-M{i + 1}", "home": a, "away": b}
            for i, (a, b) in enumerate(pairing)
        ]
        return pairings, None

    # Try bye candidates in order until the rest can be paired.
    for bye_team in bye_order:
        if bye_team in byes_had:
            continue
        remaining = [t for t in ranked if t != bye_team]
        pairing = _min_diff_pairing(remaining, scores, played)
        if pairing is not None:
            pairings = [
                {"match_id": f"SW-R{round_no}-M{i + 1}", "home": a, "away": b}
                for i, (a, b) in enumerate(pairing)
            ]
            return pairings, bye_team

    raise ApiError(
        409,
        "NO_VALID_PAIRING",
        f"No rematch-free pairing for round {round_no}.",
        {"round": round_no},
    )


def generate(teams: list[str], params: dict) -> dict:
    n = len(teams)
    default_total = max(1, math.ceil(math.log2(n))) if n > 1 else 1
    total_rounds = params.get("total_rounds", default_total)
    if total_rounds is None:
        total_rounds = default_total
    if not _is_int(total_rounds) or total_rounds < 1 or total_rounds > n - 1:
        raise validation_error(["params.total_rounds"])

    round_no = params.get("round", 1)
    if round_no is None:
        round_no = 1
    if not _is_int(round_no) or round_no < 1 or round_no > total_rounds:
        raise validation_error(["params.round"])

    history = params.get("history", [])
    if history is None:
        history = []
    if not isinstance(history, list):
        raise validation_error(["params.history"])
    if len(history) != round_no - 1:
        raise validation_error(["params.history"], "history must contain exactly rounds 1..round-1.")

    # Validate history entries lightly.
    team_set = set(teams)
    for i, entry in enumerate(history):
        if not isinstance(entry, dict):
            raise validation_error([f"params.history.{i}"])
        if entry.get("round") != i + 1:
            raise validation_error([f"params.history.{i}.round"])
        bye = entry.get("bye")
        if bye is not None and bye not in team_set:
            raise validation_error([f"params.history.{i}.bye"])
        matches = entry.get("matches")
        if not isinstance(matches, list):
            raise validation_error([f"params.history.{i}.matches"])
        for j, m in enumerate(matches):
            if not isinstance(m, dict):
                raise validation_error([f"params.history.{i}.matches.{j}"])
            if m.get("home") not in team_set or m.get("away") not in team_set:
                raise validation_error([f"params.history.{i}.matches.{j}"])
            if m.get("result") not in ("home", "away", "draw"):
                raise validation_error([f"params.history.{i}.matches.{j}.result"])

    standings, scores, byes_had, played = _compute_standings(teams, history)

    if round_no == 1:
        pairings, bye = _round1(teams)
    else:
        pairings, bye = _pair_round(teams, standings, scores, byes_had, played, round_no)

    return {
        "format": "swiss",
        "round": round_no,
        "total_rounds": total_rounds,
        "pairings": pairings,
        "bye": bye,
        "standings": standings,
    }
