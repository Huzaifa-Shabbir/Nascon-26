"""Double-elimination bracket (spec §5.7 D)."""
from __future__ import annotations

import math

from app.errors import validation_error
from app.fixtures.single_elim import next_power_of_two, seed_order


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
    conditional=None,
    required=None,
) -> dict:
    m = {
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
    if conditional is not None:
        m["conditional"] = conditional
        m["required"] = required  # null until GF1 has a result
    return m


def generate(teams: list[str], params: dict) -> dict:
    bracket_reset = params.get("bracket_reset", False)
    if bracket_reset is None:
        bracket_reset = False
    if not isinstance(bracket_reset, bool):
        raise validation_error(["params.bracket_reset"])

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

    by_id: dict[str, dict] = {}
    winners_rounds: list[dict] = []
    losers_rounds: list[dict] = []

    # --- Winners bracket WR{r}M{i}: round r has B/2^r matches ---
    for r in range(1, k + 1):
        count = B // (2 ** r)
        ms = []
        for i in range(1, count + 1):
            mid = f"WR{r}M{i}"
            if r < k:
                dest_i = (i + 1) // 2
                slot = "home" if i % 2 == 1 else "away"
                winner_to = {"match_id": f"WR{r + 1}M{dest_i}", "slot": slot}
            else:
                winner_to = {"match_id": "GF1", "slot": "home"}
            # Loser routing (recommended):
            # WR1 losers → LR1 (pair adjacent: WR1M{2j-1} and WR1M{2j} → LR1M{j})
            # WRr (r>=2) losers → LR(2r-2)
            if r == 1:
                lr_i = (i + 1) // 2
                # odd WR1 index → home of LR1, even → away
                slot_l = "home" if i % 2 == 1 else "away"
                loser_to = {"match_id": f"LR1M{lr_i}", "slot": slot_l}
            else:
                lr_round = 2 * r - 2
                # Drop into the corresponding LR match; map by index.
                # For WR2 (2 matches) → LR2 (2 matches): WR2Mi → LR2Mi away (LB winner is home)
                # For WR final (1 match) → LR final away
                if count == B // (2 ** r):
                    lr_count = B // (2 ** (r))  # same count as WR round for r>=2 drops into LR(2r-2)
                # LR(2r-2) has B/2^r matches when 2r-2 = 2j and j=r-1 → B/2^(j+1)=B/2^r ✓
                lr_i = i
                loser_to = {"match_id": f"LR{lr_round}M{lr_i}", "slot": "away"}
            m = _match(mid, "winners", r, i, winner_to=winner_to, loser_to=loser_to)
            ms.append(m)
            by_id[mid] = m
        winners_rounds.append({"round": r, "matches": ms})

    # --- Losers bracket: rounds 1..2(k-1); rounds 2j-1 and 2j each have B/2^(j+1) ---
    lb_rounds = 2 * (k - 1)
    for lr in range(1, lb_rounds + 1):
        j = (lr + 1) // 2  # j such that rounds 2j-1 and 2j share count
        count = B // (2 ** (j + 1))
        ms = []
        for i in range(1, count + 1):
            mid = f"LR{lr}M{i}"
            if lr < lb_rounds:
                # Odd LR rounds (pure LB): winners go to next LR same index as home
                # Even LR rounds: winners go to next LR, pairing into fewer matches
                if lr % 2 == 1:
                    winner_to = {"match_id": f"LR{lr + 1}M{i}", "slot": "home"}
                else:
                    dest_i = (i + 1) // 2
                    slot = "home" if i % 2 == 1 else "away"
                    # After even round, next is odd with half the matches (when j increases)
                    next_count = B // (2 ** (((lr + 1) + 1) // 2 + 1))
                    if next_count < count:
                        winner_to = {"match_id": f"LR{lr + 1}M{dest_i}", "slot": slot}
                    else:
                        winner_to = {"match_id": f"LR{lr + 1}M{i}", "slot": "home"}
            else:
                winner_to = {"match_id": "GF1", "slot": "away"}
            m = _match(mid, "losers", lr, i, winner_to=winner_to, loser_to=None)
            ms.append(m)
            by_id[mid] = m
        losers_rounds.append({"round": lr, "matches": ms})

    # --- Grand final ---
    gf1 = _match(
        "GF1",
        "grand_final",
        1,
        1,
        winner_to={"match_id": "GF2", "slot": "home"} if bracket_reset else None,
        loser_to={"match_id": "GF2", "slot": "away"} if bracket_reset else None,
    )
    by_id["GF1"] = gf1
    grand_final = [gf1]
    gf2 = None
    if bracket_reset:
        gf2 = _match(
            "GF2",
            "grand_final",
            2,
            1,
            winner_to=None,
            loser_to=None,
            conditional=True,
            required=None,
        )
        by_id["GF2"] = gf2
        grand_final.append(gf2)

    # Place WR1 from single-elim seeding.
    wr1 = winners_rounds[0]["matches"]
    for i, m in enumerate(wr1, start=1):
        s1 = order[2 * i - 2]
        s2 = order[2 * i - 1]
        t1, t2 = team_for_seed(s1), team_for_seed(s2)
        if t1 is None and t2 is not None:
            m.update(bye=True, home=t2, away=None, home_seed=s2, winner=t2)
        elif t2 is None and t1 is not None:
            m.update(bye=True, home=t1, away=None, home_seed=s1, winner=t1)
        elif t1 is not None and t2 is not None:
            if s1 < s2:
                m.update(home=t1, away=t2, home_seed=s1, away_seed=s2)
            else:
                m.update(home=t2, away=t1, home_seed=s2, away_seed=s1)
        else:
            m.update(bye=True)

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

    def propagate():
        changed = True
        while changed:
            changed = False
            for m in list(by_id.values()):
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

    propagate()

    # Apply results.
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
    for _ in range(len(pending) + 10):
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
            place(m.get("winner_to"), winner, seed_of(m, winner))
            place(m.get("loser_to"), loser)
            del pending[mid]
            progressed = True
            # Update GF2.required when GF1 completes.
            if mid == "GF1" and gf2 is not None:
                # required true iff losers-bracket champion (GF1.away) won GF1
                gf2["required"] = winner == gf1.get("away")
        if not progressed:
            raise validation_error(["params.results"])

    # Propagate bye winners' losers into LB where applicable.
    for m in winners_rounds[0]["matches"]:
        if m.get("bye") and m.get("winner") and m.get("loser_to"):
            # Bye has no loser — LB slot stays empty / bye (not graded).
            pass

    return {
        "format": "double_elim",
        "bracket_size": B,
        "bracket_reset": bracket_reset,
        "winners": winners_rounds,
        "losers": losers_rounds,
        "grand_final": grand_final,
    }
