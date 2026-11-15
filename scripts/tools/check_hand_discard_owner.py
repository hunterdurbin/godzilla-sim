#!/usr/bin/env python3
"""Only CardMover.discard_from_hand fires the discard-from-hand watchers.

Every discard from hand (the Gain Rage action, the invasion cost, an effect)
goes through CardMover.discard_from_hand(pid, cards, cause): it takes the
cards out of the hand, puts them in the discard pile, writes the effect log
line and submits every watcher in ONE standby batch (10.4.3)
(hunterdurbin/godzilla-sim-issue-tracker#35 row 22). Calling a dispatcher
discard entry point by hand skips the pile, the log line, the event or the
batch.

Flags a reference (call or Callable) under scripts/ or scenes/ to:
  trigger_hand_cards_discarded_batch  - outside card_mover.gd
  trigger_discard_from_hand           - anywhere (a test seam for one card's hook)
  trigger_hand_card_discarded         - anywhere (a test seam for the watchers)
trigger_dispatcher.gd defines them and may use them. Tests (tests/) may call
the seams to exercise one card's hook.

Usage: python3 scripts/tools/check_hand_discard_owner.py
"""
import os
import re
import sys

from gd_ratchet import ROOT, strip_comment

SCAN_DIRS = ("scripts", "scenes")
DISPATCHER = "scripts/effects/trigger_dispatcher.gd"
# Method -> files (besides the dispatcher) that may reference it.
ALLOWED = {
    "trigger_hand_cards_discarded_batch": {"scripts/effects/card_mover.gd"},
    "trigger_discard_from_hand": set(),
    "trigger_hand_card_discarded": set(),
}
REF_RE = re.compile(r"\.\s*(%s)\b" % "|".join(ALLOWED))


def gd_files():
    for d in SCAN_DIRS:
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, d)):
            for f in sorted(files):
                if f.endswith(".gd"):
                    yield os.path.relpath(os.path.join(dirpath, f), ROOT)


def violations(path, lines):
    if path == DISPATCHER:
        return
    for i, line in enumerate(lines, 1):
        for m in REF_RE.finditer(line):
            if path not in ALLOWED[m.group(1)]:
                yield "%s:%d  %s" % (path, i, line.strip())


def self_test():
    cases = {
        ("scripts/core/actions/play_actions.gd", "\tdispatcher.trigger_discard_from_hand(pid, card)"): True,
        ("scripts/core/actions/play_actions.gd", "\tdispatcher.trigger_hand_card_discarded(pid, card)"): True,
        ("scripts/core/actions/invasion_resolver.gd", "\tdispatcher.trigger_hand_cards_discarded_batch(pid, [card], c)"): True,
        ("scripts/effects/card_mover.gd", "\tdispatcher.trigger_discard_from_hand(pid, card)"): True,
        ("scripts/effects/card_mover.gd", "\tcheck_timing.run_effect(0, c, dispatcher.trigger_hand_card_discarded.bind(0, c))"): True,
        ("scripts/effects/card_mover.gd", "\tdispatcher.trigger_hand_cards_discarded_batch(pid, cards, cause)"): False,
        (DISPATCHER, "\tcheck_timing.submit(_collect_hand_card_discarded_entries(pid, c))"): False,
        (DISPATCHER, "func trigger_discard_from_hand(player_id: int, card_data: Dictionary) -> void:"): False,
        ("scripts/effects/card_mover.gd", "\tmover.discard_from_hand(pid, [card], cause)"): False,
        ("scripts/effects/card_mover.gd", strip_comment("x()  # dispatcher.trigger_discard_from_hand(0, c)")): False,
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
    allowed_files = {DISPATCHER} | set().union(*ALLOWED.values())
    stale = [p for p in sorted(allowed_files) if not os.path.exists(os.path.join(ROOT, p))]
    for v in found:
        print("DISCARD watchers fired outside discard_from_hand  " + v)
    for p in stale:
        print("ALLOWED entry no longer exists: " + p)
    if found:
        print("\nDiscard from hand through CardMover.discard_from_hand(player_id, cards, cause)"
              " (card scripts: select_hand_card / discard_hand_to); it submits every"
              " discard watcher in one batch.")
    if found or stale:
        return 1
    print("hand discard watchers: OK (only scripts/effects/card_mover.gd)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
