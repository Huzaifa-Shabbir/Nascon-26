"""Round-robin fixtures via the circle method (spec §5.7 A)."""
from __future__ import annotations

from app.errors import validation_error

BYE = object()  # sentinel for odd-n bye slot


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _circle_leg(teams: list[str]) -> list[dict]:
    """One leg of circle-method fixtures. Returns list of round dicts (1-based round within leg)."""
    odd = len(teams) % 2 == 1
    # Working circle: real teams + optional bye sentinel so length is even.
    circle: list = list(teams) + ([BYE] if odd else [])
    m = len(circle)  # even
    rounds_in_leg = m - 1
    rounds: list[dict] = []
    home_count = {t: 0 for t in teams}
    away_count = {t: 0 for t in teams}

    for _r in range(rounds_in_leg):
        matches = []
        byes: list[str] = []
        idx = 1
        for i in range(m // 2):
            a = circle[i]
            b = circle[m - 1 - i]
            if a is BYE:
                byes.append(b)
                continue
            if b is BYE:
                byes.append(a)
                continue
            # Assign home to the side with fewer homes so far (|H−A|≤1 per team).
            if home_count[a] < home_count[b] or (
                home_count[a] == home_count[b] and away_count[a] >= away_count[b]
            ):
                home, away = a, b
            else:
                home, away = b, a
            home_count[home] += 1
            away_count[away] += 1
            matches.append(
                {
                    "match_id": None,
                    "leg": None,
                    "home": home,
                    "away": away,
                    "status": "scheduled",
                    "awarded_to": None,
                    "_idx": idx,
                }
            )
            idx += 1
        rounds.append({"_local": _r + 1, "matches": matches, "byes": byes})
        # Rotate: keep index 0 fixed, move last to position 1.
        circle = [circle[0]] + [circle[-1]] + circle[1:-1]

    return rounds


def generate(teams: list[str], params: dict) -> dict:
    legs = params.get("legs", 1)
    if legs is None:
        legs = 1
    if not _is_int(legs) or legs not in (1, 2):
        raise validation_error(["params.legs"])

    withdrawals = params.get("withdrawals", [])
    if withdrawals is None:
        withdrawals = []
    if not isinstance(withdrawals, list):
        raise validation_error(["params.withdrawals"])

    policy = params.get("withdrawal_policy", "forfeit_remaining")
    if policy is None:
        policy = "forfeit_remaining"
    if policy not in ("forfeit_remaining", "void_all"):
        raise validation_error(["params.withdrawal_policy"])

    n = len(teams)
    rounds_per_leg = n if n % 2 == 1 else n - 1
    round_count = rounds_per_leg * legs

    # Validate withdrawals against known teams and round range.
    team_set = set(teams)
    withdrawn: list[dict] = []
    for i, w in enumerate(withdrawals):
        if not isinstance(w, dict):
            raise validation_error([f"params.withdrawals.{i}"])
        tid = w.get("team_id")
        after = w.get("after_round")
        if not isinstance(tid, str) or tid not in team_set:
            raise validation_error([f"params.withdrawals.{i}.team_id"])
        if not _is_int(after) or after < 0 or after > round_count:
            raise validation_error([f"params.withdrawals.{i}.after_round"])
        withdrawn.append({"team_id": tid, "after_round": after})

    # Build legs.
    all_rounds: list[dict] = []
    global_round = 0
    for leg in range(1, legs + 1):
        leg_rounds = _circle_leg(teams)
        if leg == 2:
            # Reverse home/away so every ordered pair occurs once across two legs.
            for rd in leg_rounds:
                for m in rd["matches"]:
                    m["home"], m["away"] = m["away"], m["home"]
        for rd in leg_rounds:
            global_round += 1
            matches = []
            for m in rd["matches"]:
                matches.append(
                    {
                        "match_id": f"RR-L{leg}-R{global_round}-M{m['_idx']}",
                        "leg": leg,
                        "home": m["home"],
                        "away": m["away"],
                        "status": "scheduled",
                        "awarded_to": None,
                    }
                )
            all_rounds.append(
                {
                    "round": global_round,
                    "matches": matches,
                    "byes": list(rd["byes"]),
                }
            )

    # Apply withdrawals.
    withdrawn_map = {w["team_id"]: w["after_round"] for w in withdrawn}

    def is_withdrawn_for(team_id: str, round_no: int) -> bool:
        if team_id not in withdrawn_map:
            return False
        after = withdrawn_map[team_id]
        if policy == "void_all":
            return True
        # forfeit_remaining: withdrawn after after_round
        return round_no > after

    summary = {"total": 0, "scheduled": 0, "forfeit": 0, "voided": 0}
    for rd in all_rounds:
        for m in rd["matches"]:
            summary["total"] += 1
            h_out = is_withdrawn_for(m["home"], rd["round"])
            a_out = is_withdrawn_for(m["away"], rd["round"])
            if h_out and a_out:
                m["status"] = "voided"
                m["awarded_to"] = None
                summary["voided"] += 1
            elif policy == "void_all" and (h_out or a_out):
                m["status"] = "voided"
                m["awarded_to"] = None
                summary["voided"] += 1
            elif h_out or a_out:
                # forfeit_remaining
                m["status"] = "forfeit"
                m["awarded_to"] = m["away"] if h_out else m["home"]
                summary["forfeit"] += 1
            else:
                summary["scheduled"] += 1

    return {
        "format": "round_robin",
        "legs": legs,
        "team_count": n,
        "round_count": round_count,
        "rounds": all_rounds,
        "summary": summary,
    }
