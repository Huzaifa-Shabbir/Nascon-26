"""Single-elimination bracket (spec §5.7 C). Exact seeding."""
from __future__ import annotations

import math

from app.errors import validation_error


def seed_order(bracket_size: int) -> list[int]:
    """Recursive seed placement. order(8) = [1, 8, 4, 5, 2, 7, 3, 6]."""
    if bracket_size == 2:
        return [1, 2]
    half = seed_order(bracket_size // 2)
    out: list[int] = []
    for s in half:
        out.append(s)
        out.append(bracket_size + 1 - s)
    return out


def next_power_of_two(n: int) -> int:
    p = 1
    while p < n:
        p *= 2
    return p

def _match(
    match_id: str,
    bracket: str,
    round_no: int,
    index: int,
    *,
    home=None,
    away=None,
    home_seed=None,
    away_seed=None,
    bye: bool = False,
    winner=None,
    loser=None,
    winner_to=None,
    loser_to=None,
) -> dict:
    return {
        "match_id": match_id,
        "bracket": bracket,
        "round": round_no,
        "index": index,
        "home": home,
        "away": away,
        "home_seed": home_seed,
        "away_seed": away_seed,
        "bye": bye,
        "winner": winner,
        "loser": loser,
        "winner_to": winner_to,
        "loser_to": loser_to,
    }


def generate(teams: list[str], params: dict) -> dict:
    third = params.get("third_place_match", False)
    if third is None:
        third = False
    if not isinstance(third, bool):
        raise validation_error(["params.third_place_match"])

    results = params.get("results", [])
    if results is None:
        results = []
    if not isinstance(results, list):
        raise validation_error(["params.results"])

    n = len(teams)
    B = next_power_of_two(n)
    k = int(math.log2(B))
    order = seed_order(B)

    def team_for_seed(seed: int) -> str | None:
        return None if seed > n else teams[seed - 1]

    rounds: list[dict] = []
    by_id: dict[str, dict] = {}

    for r in range(1, k + 1):
        count = B // (2 ** r)
        round_matches = []
        for i in range(1, count + 1):
            mid = f"R{r}M{i}"
            if r < k:
                dest_i = (i + 1) // 2
                slot = "home" if i % 2 == 1 else "away"
                winner_to = {"match_id": f"R{r + 1}M{dest_i}", "slot": slot}
            else:
                winner_to = None
            m = _match(mid, "main", r, i, winner_to=winner_to)
            round_matches.append(m)
            by_id[mid] = m
        rounds.append({"round": r, "matches": round_matches})

    # Round-1 placement from seed order.
    for i, m in enumerate(rounds[0]["matches"], start=1):
        s1 = order[2 * i - 2]
        s2 = order[2 * i - 1]
        t1, t2 = team_for_seed(s1), team_for_seed(s2)
        if t1 is None and t2 is not None:
            m.update(bye=True, home=t2, away=None, home_seed=s2, away_seed=None, winner=t2)
        elif t2 is None and t1 is not None:
            m.update(bye=True, home=t1, away=None, home_seed=s1, away_seed=None, winner=t1)
        elif t1 is not None and t2 is not None:
            if s1 < s2:
                m.update(home=t1, away=t2, home_seed=s1, away_seed=s2, bye=False)
            else:
                m.update(home=t2, away=t1, home_seed=s2, away_seed=s1, bye=False)
        else:
            m.update(bye=True, home=None, away=None)

    tp = None
    if third and k >= 2:
        tp = _match("TP", "third_place", k, 1)
        sf = rounds[k - 2]["matches"]
        if len(sf) >= 2:
            sf[0]["loser_to"] = {"match_id": "TP", "slot": "home"}
            sf[1]["loser_to"] = {"match_id": "TP", "slot": "away"}
        by_id["TP"] = tp

    def place(ref: dict | None, team: str | None, seed: int | None = None) -> None:
        if not ref or team is None:
            return
        dest = by_id.get(ref["match_id"])
        if dest is None:
            return
        if ref["slot"] == "home":
            dest["home"] = team
            if seed is not None:
                dest["home_seed"] = seed
        else:
            dest["away"] = team
            if seed is not None:
                dest["away_seed"] = seed

    def seed_of(m: dict, team: str) -> int | None:
        if team == m.get("home"):
            return m.get("home_seed")
        if team == m.get("away"):
            return m.get("away_seed")
        return None

    # Propagate bye winners into later slots.
    changed = True
    while changed:
        changed = False
        for m in by_id.values():
            if not (m.get("bye") and m.get("winner") and m.get("winner_to")):
                continue
            dest = by_id.get(m["winner_to"]["match_id"])
            if dest is None:
                continue
            slot = m["winner_to"]["slot"]
            if slot == "home" and dest["home"] is None:
                dest["home"] = m["winner"]
                dest["home_seed"] = m.get("home_seed")
                changed = True
            elif slot == "away" and dest["away"] is None:
                dest["away"] = m["winner"]
                dest["away_seed"] = m.get("home_seed")
                changed = True

    # Validate and index results.
    result_map: dict[str, str] = {}
    for i, item in enumerate(results):
        if not isinstance(item, dict):
            raise validation_error([f"params.results.{i}"])
        mid = item.get("match_id")
        winner = item.get("winner")
        if not isinstance(mid, str) or mid not in by_id:
            raise validation_error([f"params.results.{i}.match_id"])
        if not isinstance(winner, str):
            raise validation_error([f"params.results.{i}.winner"])
        result_map[mid] = winner

    pending = dict(result_map)
    for _ in range(len(pending) + 5):
        if not pending:
            break
        progressed = False
        for mid, winner in list(pending.items()):
            m = by_id[mid]
            parts = {m["home"], m["away"]} - {None}
            if m["home"] is not None and m["away"] is not None and winner not in parts:
                raise validation_error(["params.results"])
            if winner not in parts:
                continue
            loser = None if m["bye"] else (m["away"] if winner == m["home"] else m["home"])
            m["winner"] = winner
            m["loser"] = loser
            place(m["winner_to"], winner, seed_of(m, winner))
            place(m["loser_to"], loser)
            del pending[mid]
            progressed = True
        if not progressed:
            raise validation_error(["params.results"])

    out_rounds = [{"round": rd["round"], "matches": rd["matches"]} for rd in rounds]
    if tp is not None:
        out_rounds.append({"round": k, "matches": [tp]})

    return {"format": "single_elim", "bracket_size": B, "rounds": out_rounds}
