#!/usr/bin/env python3
"""Guard: every engine site that starts a card ability announces it.

The bot sim's [SimEffects] counts (and run_sim_diff.sh's UNEXERCISED verdict)
come from GameEvents.effect_resolving, emitted by
EffectHandler.note_effect_resolving. An engine module that awaits a card hook
(`await <x>effect.on_*(` / `apply_*(`, or a standby `callback.call()`) without
calling note_effect_resolving just before it makes that card read 0 in every
sim diff, with no hint why.

Scans the engine modules (scripts/effects/*.gd). A direct site must have
`note_effect_resolving(` within the LOOKBACK lines above it, in the same
function. Calls inside a lambda (`:= func(...)`) are exempt: those bodies run
as standby callbacks, which standby_resolver.gd announces when it resolves
the entry. Sync hooks (no `await`: replacement queries such as
on_would_be_destroyed) are not ability resolutions and are not flagged.
No allowlist.

Usage: python3 scripts/tools/check_effect_resolution_notes.py
"""
import glob
import os
import re
import sys

from gd_ratchet import EFFECTS_DIR, ROOT, strip_comment

LOOKBACK = 4
INVOKE_RE = re.compile(r"\bawait\s+(?:[A-Za-z_]\w*\.)*(?:\w*effect\.(?:on_\w+|apply_\w+)|callback\.call)\s*\(")
TOP_FUNC_RE = re.compile(r"^(?:static\s+)?func\s+\w+\s*\(")
LAMBDA_RE = re.compile(r"\bfunc\s*\(")


def indent(line):
    return len(line) - len(line.lstrip("\t "))


def in_lambda(lines, idx):
    """True when lines[idx] sits in a lambda body rather than directly in a
    top-level func: walk up to the nearest less-indented line opening a func."""
    depth = indent(lines[idx])
    for j in range(idx - 1, -1, -1):
        line = lines[j]
        if not line.strip() or indent(line) >= depth:
            continue
        if TOP_FUNC_RE.match(line):
            return False
        if LAMBDA_RE.search(line):
            return True
        depth = indent(line)
    return False


def violations(path, lines):
    for i, line in enumerate(lines):
        if not INVOKE_RE.search(line) or in_lambda(lines, i):
            continue
        window = lines[max(0, i - LOOKBACK):i]
        if not any("note_effect_resolving(" in w for w in window):
            yield "%s:%d  ->  %s" % (path, i + 1, line.strip())


def self_test():
    direct_bad = ["func f() -> void:", "\tawait effect.on_enter(ctx)"]
    direct_ok = ["func f() -> void:", "\th.note_effect_resolving(pid, card)",
                 "\t@warning_ignore(\"redundant_await\")", "\tawait effect.on_enter(ctx)"]
    lam = ["func f() -> void:", "\tvar cb := func():", "\t\tawait effect.on_revenge(ctx)"]
    sync = ["func f() -> void:", "\tif effect.on_would_be_destroyed(ctx):"]
    bad = [] if list(violations("x", direct_bad)) else ["direct site not flagged"]
    for name, src in (("noted site", direct_ok), ("lambda", lam), ("sync hook", sync)):
        if list(violations("x", src)):
            bad.append("%s flagged" % name)
    for b in bad:
        print("SELF-TEST mismatch: " + b)
    return not bad


def main():
    if not self_test():
        return 1
    found = []
    sites = 0
    for path in sorted(glob.glob(os.path.join(EFFECTS_DIR, "*.gd"))):
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as fh:
            lines = [strip_comment(l.rstrip("\n")) for l in fh]
        sites += sum(1 for i, l in enumerate(lines) if INVOKE_RE.search(l) and not in_lambda(lines, i))
        found.extend(violations(rel, lines))
    for v in found:
        print("UNANNOUNCED effect resolution  " + v)
    if found:
        print("\nCall h.note_effect_resolving(player_id, card) right before starting the card's"
              " ability (it feeds GameEvents.effect_resolving / the sim's [SimEffects] counts).")
        return 1
    print("effect resolution notes: OK (%d direct sites)" % sites)
    return 0


if __name__ == "__main__":
    sys.exit(main())
