#!/usr/bin/env python3
"""Engine docstrings leave PlayerState `*_changed` signals unlisted.

CODING_STANDARDS.md § A primitive's docstring is its contract: a docstring
lists the GameEvents / EffectHandler signals a function emits, its triggers
and whether it prompts. PlayerState `*_changed` signals come from the
mutators it calls (scripts/core/README.md § Contracts: each mutator emits
immediately), so naming them restates the mutator and goes stale when the
mutator calls change. New docstrings copy their neighbours, so one listing
breeds more.

Flags an indented `##` docstring line in an engine module
(scripts/core/**, scripts/effects/*.gd) that names a PlayerState
`<area>_changed` signal. player_state.gd documents its own mutators and is
not scanned; class-level `##` comments (unindented) may explain the signal
layering.

Usage: python3 scripts/tools/check_docstring_signals.py
"""
import os
import re
import sys

from gd_ratchet import ROOT

CORE = os.path.join("scripts", "core")
EFFECTS = os.path.join("scripts", "effects")
SKIP = os.path.join(CORE, "player_state.gd")
DOCSTRING_RE = re.compile(r"^\s+##")
SIGNAL_RE = re.compile(
    r"\b(hand|zones|monster|rage|strategy_zones|deck|discard)_changed\b")


def engine_files():
    for dirpath, _dirs, names in os.walk(os.path.join(ROOT, CORE)):
        for f in sorted(names):
            if f.endswith(".gd"):
                yield os.path.relpath(os.path.join(dirpath, f), ROOT)
    for f in sorted(os.listdir(os.path.join(ROOT, EFFECTS))):
        if f.endswith(".gd"):
            yield os.path.join(EFFECTS, f)


def violations(path, lines):
    if path == SKIP:
        return
    for i, line in enumerate(lines, 1):
        if DOCSTRING_RE.match(line) and SIGNAL_RE.search(line):
            yield "%s:%d  %s" % (path, i, line.strip())


def self_test():
    eng = os.path.join(EFFECTS, "card_mover.gd")
    cases = {
        (eng, "\t## Emits deck_changed when any card was taken."): True,
        (eng, "\t## Signals: zones_changed, then discard_changed."): True,
        (eng, "\t## `monster_changed`, then GameEvents.monster_advanced."): True,
        (eng, "\t## Emits GameEvents.monster_advanced per step."): False,
        (eng, "\t## fire trigger_rage_changed for the rage abilities"): False,
        (eng, "\t## emits the same discard_reshuffled signal"): False,
        (eng, "\t## effect_stack_changed is published once per pass"): False,
        (eng, "## (hand_changed, zones_changed, ...) remain the state-diff layer."): False,
        (eng, "\tplayer.zones_changed.connect(_on_zones)"): False,
        (SKIP, "\t## Set rage; emits rage_changed(value)."): False,
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
    for path in engine_files():
        with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
            found.extend(violations(path, fh.read().splitlines()))
    for v in found:
        print("DOCSTRING lists a PlayerState signal  " + v)
    if found:
        print("\nPlayerState *_changed signals come from the mutators, so they go"
              " unlisted (CODING_STANDARDS.md § A primitive's docstring is its"
              " contract). List only GameEvents / EffectHandler signals.")
        return 1
    print("docstring signals: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
