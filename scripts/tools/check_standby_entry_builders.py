#!/usr/bin/env python3
"""Only the trigger dispatcher builds StandbyEntry objects and submits them.

A triggered ability enters standby (10.6.2) through a private
`_collect_*_entries` function in scripts/effects/trigger_dispatcher.gd: that
one place applies the TRIGGER_FILTERS gates, builds the EffectContext and
attaches the `still_applies` gate (10.6.3). Engine operations report what
happened through the dispatcher's `trigger_*` functions, which submit the
entries to CheckTiming; a missing trigger is added to the dispatcher.

Flags `StandbyEntry.new(` and `check_timing.submit(` anywhere under scripts/
outside the dispatcher: operations report through `trigger_*` and never
handle StandbyEntry arrays (tracker #35 row 2).
Tests (tests/) may build entries directly. No allow-list -- the tree is clean.

Usage: python3 scripts/tools/check_standby_entry_builders.py
"""
import os
import re
import sys

from gd_ratchet import ROOT, strip_comment

SCAN_DIR = "scripts"
BUILDER = os.path.join("scripts", "effects", "trigger_dispatcher.gd")
NEW_RE = re.compile(r"\bStandbyEntry\s*\.\s*new\s*\(")
SUBMIT_RE = re.compile(r"\bcheck_timing\s*\.\s*submit\s*\(")


def gd_files():
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, SCAN_DIR)):
        for f in sorted(files):
            if f.endswith(".gd"):
                yield os.path.relpath(os.path.join(dirpath, f), ROOT)


def violations(path, lines):
    if path == BUILDER:
        return
    for i, line in enumerate(lines, 1):
        if NEW_RE.search(line) or SUBMIT_RE.search(line):
            yield "%s:%d  %s" % (path, i, line.strip())


def self_test():
    cases = {
        ("scripts/effects/destruction_engine.gd", "\treturn [StandbyEntry.new(pid, card, cb)]"): True,
        ("scripts/effects/check_timing.gd", "var e := StandbyEntry .new(pid, card, cb)"): True,
        (BUILDER, "\tentries.append(StandbyEntry.new(pid, card, cb))"): False,
        ("scripts/effects/check_timing.gd", "var e: StandbyEntry = entries[0]"): False,
        ("scripts/effects/check_timing.gd", strip_comment("x()  # never StandbyEntry.new( here")): False,
        ("scripts/core/actions/invasion_resolver.gd", "\t\tcheck_timing.submit(deferred)"): True,
        ("scripts/effects/destruction_engine.gd", "\th.check_timing .submit(out.entries)"): True,
        (BUILDER, "\tcheck_timing.submit(_collect_x_entries(pid))"): False,
        ("scripts/effects/monster_mover.gd", "\tdispatcher.trigger_monster_advance(pid, a, b)"): False,
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
    for v in found:
        print("STANDBY ENTRY built or submitted outside the dispatcher  " + v)
    if found:
        print("\nAdd a trigger_* function (backed by a private _collect_*_entries)"
              " to scripts/effects/trigger_dispatcher.gd and call that instead.")
        return 1
    print("standby entry builders/submitters: OK (only %s)" % BUILDER)
    return 0


if __name__ == "__main__":
    sys.exit(main())
