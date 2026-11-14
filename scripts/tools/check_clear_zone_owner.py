#!/usr/bin/env python3
"""Only LeaveZone (and EnterZone's moves) empties a battle zone.

Every way a battle card leaves its zone (Destroy, a replacement to the deck
bottom, an effect returning it to the hand or deck, the 11.4 illegal-card
cleanup) goes through scripts/effects/leave_zone.gd: it routes the cards under
it to the discard pile, makes a token disappear (9.1.4.2) and submits the
card's on_leave_play (10.6.4). A hand-written `player.clear_zone(i)` skips the
leave-play trigger (hunterdurbin/godzilla-sim-issue-tracker#31). Call `leave_zone.leave(...)` instead, or an
EnterZone move (`move_stack` / `move_under`) when the card stays in a zone.

Flags a `.clear_zone(` call anywhere under scripts/ or scenes/ outside the
ALLOWED files below (hunterdurbin/godzilla-sim-issue-tracker#35 row 11). PlayerState defines it; tests (tests/) may
call it to build fixtures.

Usage: python3 scripts/tools/check_clear_zone_owner.py
"""
import os
import re
import sys

from gd_ratchet import ROOT, strip_comment

SCAN_DIRS = ("scripts", "scenes")
# Files that may empty a zone, each with the reason.
ALLOWED = {
    "scripts/effects/leave_zone.gd": "the Leave operation",
    "scripts/effects/enter_zone.gd": "Moves between zones (the card stays in play)",
}
CALL_RE = re.compile(r"\.\s*clear_zone\s*\(")


def gd_files():
    for d in SCAN_DIRS:
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, d)):
            for f in sorted(files):
                if f.endswith(".gd"):
                    yield os.path.relpath(os.path.join(dirpath, f), ROOT)


def violations(path, lines):
    if path in ALLOWED:
        return
    for i, line in enumerate(lines, 1):
        if CALL_RE.search(line):
            yield "%s:%d  %s" % (path, i, line.strip())


def self_test():
    cases = {
        ("scripts/effects/destruction_engine.gd", "\tvar stack: Array = target.clear_zone(zone_idx)"): True,
        ("scripts/effects/check_timing.gd", "\t\t\tvar stack: Array = player.clear_zone(i)"): True,
        ("scripts/effects/card_mover.gd", "\tgame_state.players[0].clear_zone (3)"): True,
        ("scripts/effects/leave_zone.gd", "\tvar stack: Array = player.clear_zone(zone_idx)"): False,
        ("scripts/effects/enter_zone.gd", "\tvar stack: Array = player.clear_zone(from_zone)"): False,
        ("scripts/core/player_state.gd", "func clear_zone(i: int) -> Array:"): False,
        ("scripts/core/player_state.gd", "func clear_strategy_zone(i: int) -> Dictionary:"): False,
        ("scripts/effects/card_mover.gd", "\tplayer.clear_strategy_zone(strat_idx)"): False,
        ("scripts/effects/card_mover.gd", strip_comment("x()  # p.clear_zone(4)")): False,
    }
    bad = [src for (path, src), expect in cases.items()
           if bool(list(violations(path, [src]))) != expect]
    for b in bad:
        print("SELF-TEST mismatch: " + b)
    return not bad


def main():
    if not self_test():
        return 1
    found = []
    for path in gd_files():
        with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
            lines = [strip_comment(l.rstrip("\n")) for l in fh]
        found.extend(violations(path, lines))
    stale = [p for p in ALLOWED if not os.path.exists(os.path.join(ROOT, p))]
    for v in found:
        print("ZONE emptied outside LeaveZone  " + v)
    for p in stale:
        print("ALLOWED entry no longer exists: " + p)
    if found:
        print("\nTake the card out through LeaveZone (scripts/effects/leave_zone.gd:"
              " leave(player_id, zone_idx, destination)), or an EnterZone move"
              " (move_stack / move_under) when it stays in a zone.")
    if found or stale:
        return 1
    print("clear_zone callers: OK (only %s)" % ", ".join(sorted(ALLOWED)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
