#!/usr/bin/env python3
"""Only RageMover changes Rage during a match.

Every Rage change goes through scripts/effects/rage_mover.gd: `increase`
emits GameEvents.rage_gained, writes the log line and submits the Rage
abilities (one per point for "increase" watchers, Q381); `decrease` asks the
prevention effects with the reducer (EBP03-004) and leaves the RAGE markers
claiming abilities take (EBP04-089); `reset` is the start phase. A
hand-written `player.set_rage(...)` skips all of that
(hunterdurbin/godzilla-sim-issue-tracker#35 row 18). Card scripts call
EffectHandler.gain_rage / reduce_rage; engine code calls rage_mover.

Flags a `set_rage(` call anywhere under scripts/ or scenes/ outside the
ALLOWED files below. PlayerState defines it; tests (tests/) may call it to
build fixtures. State restore (state_codec, game_serializer, max-counter
analysis) assigns the field directly and is not a Rage change in play.

Usage: python3 scripts/tools/check_rage_writers.py
"""
import os
import re
import sys

from gd_ratchet import ROOT, strip_comment

SCAN_DIRS = ("scripts", "scenes")
# Files that may set Rage, each with the reason.
ALLOWED = {
    "scripts/effects/rage_mover.gd": "the Rage operations",
    "scripts/core/match_factory.gd": "match setup (Rage starts at 0)",
    "scripts/tools/board_editor.gd": "the F4 board editor dev tool (free-form)",
    "scripts/core/player_state.gd": "defines the mutator",
}
CALL_RE = re.compile(r"\bset_rage\s*\(")


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
        ("scripts/effects/effect_handler.gd", "\tplayer.set_rage(player.rage + amount)"): True,
        ("scripts/core/actions/play_actions.gd", "\tplayer.set_rage (player.rage + 1)"): True,
        ("scripts/effects/ebp01/ebp01_066.gd", "\tctx.owner.set_rage(ctx.owner.rage + 2)"): True,
        ("scenes/board/foo.gd", "\t_editor.set_rage(0, 3)"): True,
        ("scripts/effects/rage_mover.gd", "\tplayer.set_rage(new_rage)"): False,
        ("scripts/core/match_factory.gd", "\t\tplayer.set_rage(0)"): False,
        ("scripts/tools/board_editor.gd", "\tset_rage(pid, _player(pid).rage + delta)"): False,
        ("scripts/effects/effect_handler.gd", "\trage_mover.increase(player_id, 1, RageMover.Cause.EFFECT)"): False,
        ("scripts/effects/effect_handler.gd", "\tvar r := player.rage"): False,
        ("scripts/effects/card_mover.gd", strip_comment("x()  # p.set_rage(4)")): False,
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
        print("RAGE set outside RageMover  " + v)
    for p in stale:
        print("ALLOWED entry no longer exists: " + p)
    if found:
        print("\nChange Rage through RageMover (scripts/effects/rage_mover.gd:"
              " increase / decrease / reset); card scripts call"
              " EffectHandler.gain_rage / reduce_rage.")
    if found or stale:
        return 1
    print("set_rage callers: OK (only %s)" % ", ".join(sorted(ALLOWED)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
