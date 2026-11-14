#!/usr/bin/env python3
"""Only the monster-movement module moves a monster.

Every monster move in a match (advance, retreat, teleport, counter retreat,
the starting zone) goes through scripts/effects/monster_mover.gd: it runs
Crush per step through CheckTiming, collects the advance / <When invading>
entries and decides victory through invasion (5.13.1.1.2). A hand-written
`x.monster_zone = ...` skips all of that. Call a MonsterMover operation
instead (or add one).

Flags a `.monster_zone` assignment (`=`, `+=`, `-=`, ...) anywhere under
scripts/ or scenes/ outside MonsterMover and the ALLOWED files below, which
write it outside play. Tests (tests/) may set it directly to build fixtures.

Usage: python3 scripts/tools/check_monster_zone_writers.py
"""
import os
import re
import sys

from gd_ratchet import ROOT, strip_comment

SCAN_DIRS = ("scripts", "scenes")
MOVER = os.path.join("scripts", "effects", "monster_mover.gd")
# Files that write monster_zone outside play, each with the reason.
ALLOWED = {
    "scripts/session/state_codec.gd": "state restore (network sync)",
    "scripts/replay/game_serializer.gd": "state restore (save / replay)",
    "scripts/deck_analysis/max_counter_state.gd": "builds a hypothetical state",
    "scripts/bot/bot_combo_shin.gd": "bot planning: temporary write, restored",
    "scenes/board/modules/first_player_ui.gd": "preview state, not the match",
    "scripts/tools/board_editor.gd": "F4 board editor dev tool",
}
WRITE_RE = re.compile(r"\.monster_zone\s*[-+*/]?=(?!=)")


def gd_files():
    for d in SCAN_DIRS:
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, d)):
            for f in sorted(files):
                if f.endswith(".gd"):
                    yield os.path.relpath(os.path.join(dirpath, f), ROOT)


def violations(path, lines):
    if path == MOVER or path in ALLOWED:
        return
    for i, line in enumerate(lines, 1):
        if WRITE_RE.search(line):
            yield "%s:%d  %s" % (path, i, line.strip())


def self_test():
    cases = {
        ("scripts/core/actions/phase_actions.gd", "\tplayer.monster_zone += 1"): True,
        ("scripts/core/actions/invasion_resolver.gd", "\tplayer.monster_zone = 9"): True,
        ("scripts/core/actions/counter_resolver.gd", "\ttarget.monster_zone -= 1"): True,
        ("scripts/core/match_factory.gd", "\tstate.players[0].monster_zone = 1"): True,
        (MOVER, "\tplayer.monster_zone += 1"): False,
        ("scripts/session/state_codec.gd", "\tps.monster_zone = 3"): False,
        ("scripts/core/rules_engine.gd", "\tif player.monster_zone == 8:"): False,
        ("scripts/core/rules_engine.gd", "\tif player.monster_zone >= 6:"): False,
        ("scripts/core/rules_engine.gd", "\tif player.monster_zone != z:"): False,
        ("scripts/core/rules_engine.gd", "\tvar monster_zone := 3"): False,
        ("scripts/core/rules_engine.gd", strip_comment("x()  # p.monster_zone = 4")): False,
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
        print("MONSTER ZONE written outside MonsterMover  " + v)
    for p in stale:
        print("ALLOWED entry no longer exists: " + p)
    if found:
        print("\nMove the monster through a MonsterMover operation"
              " (scripts/effects/monster_mover.gd): advance / advance_to_zone /"
              " retreat_to_zone / teleport / counter_retreat / place_at_start.")
    if found or stale:
        return 1
    print("monster zone writers: OK (only %s, plus %d allowed outside-play files)"
          % (MOVER, len(ALLOWED)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
