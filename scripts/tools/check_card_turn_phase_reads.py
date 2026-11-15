#!/usr/bin/env python3
"""Card scripts read the turn and phase through their EffectContext.

`EffectQueries.begin_counter_view(pid)` evaluates passive queries as of that
player's counter phase: every EffectContext it builds reports that turn and
phase (`ctx.turn_player_id`, `ctx.phase`), which `ctx.is_own_turn()`,
`ctx.is_opponent_turn()` and `ctx.is_turn()` read. RulesEngine.counter_numbers
and the board's CP/threat labels rely on it
(hunterdurbin/godzilla-sim-issue-tracker#42). A card script that reads
`game_state.current_player_id` or `game_state.current_phase` itself sees the
live turn instead and silently breaks that view.

Flags, in the per-card scripts (scripts/effects/<set>/*.gd), every
`.current_player_id` or `.current_phase` access, whatever the receiver (a
`var gs := ctx.game_state` alias included). In scripts/effects/effect_queries.gd
it flags the same reads outside `_view_phase` / `_view_turn_player_id`, the
two helpers that apply the view — so in_counter_view's contract ("every turn
and phase this module reads") holds.

Usage: python3 scripts/tools/check_card_turn_phase_reads.py
"""
import re
import sys

from gd_ratchet import card_scripts, read_lines

READ_RE = re.compile(r"\.\s*(current_player_id|current_phase)\b")
FUNC_RE = re.compile(r"^(?:static\s+)?func\s+(\w+)")
QUERIES = "scripts/effects/effect_queries.gd"
VIEW_HELPERS = {"_view_phase", "_view_turn_player_id"}


def violations(path, lines, allowed_funcs=frozenset()):
    func = None
    for i, line in enumerate(lines, 1):
        m = FUNC_RE.match(line)
        if m:
            func = m.group(1)
        code = line.split("#", 1)[0]
        if READ_RE.search(code) and func not in allowed_funcs:
            yield "%s:%d  %s" % (path, i, line.strip())


def self_test():
    p = "scripts/effects/ebp02/ebp02_029.gd"
    cases = {
        "\tif ctx.game_state.current_phase < CardEnums.GamePhase.COUNTER:": True,
        "\tif ctx.game_state.current_player_id == ctx.owner.player_id:": True,
        "\tvar gs := ctx.game_state\n\tif gs.current_phase == 2:": True,
        "\tif ctx.phase < CardEnums.GamePhase.COUNTER:": False,
        "\tif ctx.is_own_turn():": False,
        "\t# ctx.game_state.current_phase is live; use ctx.phase": False,
        "\tvar n: int = ctx.game_state.turn_number": False,
    }
    bad = [src for src, expect in cases.items()
           if bool(list(violations(p, src.split("\n")))) != expect]
    q_cases = {
        "func _view_phase() -> int:\n\treturn game_state.current_phase": False,
        "func _view_turn_player_id() -> int:\n\treturn game_state.current_player_id": False,
        "func _passes_filter(w: int) -> bool:\n\treturn game_state.current_player_id == w": True,
    }
    bad += [src for src, expect in q_cases.items()
            if bool(list(violations(QUERIES, src.split("\n"), VIEW_HELPERS))) != expect]
    for b in bad:
        print("SELF-TEST mismatch: " + b)
    return not bad


def main():
    if not self_test():
        return 1
    found = []
    scripts = 0
    for path in card_scripts():
        scripts += 1
        found.extend(violations(path, read_lines(path)))
    found.extend(violations(QUERIES, read_lines(QUERIES), VIEW_HELPERS))
    for v in found:
        print("card script reads the live turn/phase  " + v)
    if found:
        print("\nRead the turn and phase through the context (ctx.is_own_turn(),"
              " ctx.is_turn(pid), ctx.phase) — in effect_queries.gd through"
              " _view_phase() / _view_turn_player_id() — so"
              " EffectQueries.in_counter_view applies"
              " (hunterdurbin/godzilla-sim-issue-tracker#42).")
        return 1
    print("card turn/phase reads: OK (%d card scripts read them through ctx;"
          " effect_queries.gd only in its view helpers)" % scripts)
    return 0


if __name__ == "__main__":
    sys.exit(main())
