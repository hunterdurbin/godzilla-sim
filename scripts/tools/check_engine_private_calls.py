#!/usr/bin/env python3
"""Ratchet: no new calls into the pure engine's private methods from other files.

A "private" method is a `func _name(` defined in scripts/core/ or
scripts/effects/. Calling one through another object (`x._name(`) couples the
caller to engine internals: when the engine changes that signature, the
caller breaks with a parse error that only a full-suite run reveals (e.g. the
board editor calling the old RuleActions._check_crush_for_player). Call or add a
public engine method instead.

Existing calls are grandfathered in engine_private_calls_allowlist.txt as
`<file>: <receiver>._<method>` keys, one line per occurrence (no line
numbers). The check fails on a call that is not allowlisted AND on an
allowlisted one that no longer occurs, so the list only shrinks
(gd_ratchet.py).

Usage: python3 scripts/tools/check_engine_private_calls.py [--update]
  --update  rewrite the allowlist from the current tree (review the diff:
            additions need a reason in the PR).
"""
import os
import re
import sys

import gd_ratchet
from gd_ratchet import ROOT, strip_comment
ENGINE_DIRS = ("scripts/core", "scripts/effects")
SCAN_DIRS = ("scripts", "scenes", "tests")
SKIP_FILES = {"scripts/effects/trigger_map.gd"}  # generated
ALLOWLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "engine_private_calls_allowlist.txt")

DEF_RE = re.compile(r"^(?:static\s+)?func\s+(_[a-z]\w*)\s*\(", re.M)
CALL_RE = re.compile(r"([A-Za-z_]\w*)(?:\[[^\]]*\])?\.(_[a-z]\w*)\s*\(")


def gd_files(dirs):
    for d in dirs:
        for dirpath, _, files in os.walk(os.path.join(ROOT, d)):
            for f in sorted(files):
                if f.endswith(".gd"):
                    path = os.path.relpath(os.path.join(dirpath, f), ROOT)
                    if path not in SKIP_FILES:
                        yield path


def engine_privates():
    defs = {}
    for path in gd_files(ENGINE_DIRS):
        with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
            for name in DEF_RE.findall(fh.read()):
                defs.setdefault(name, set()).add(path)
    return defs


def find_calls(defs):
    hits = gd_ratchet.Hits()
    for path in gd_files(SCAN_DIRS):
        with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                for recv, name in CALL_RE.findall(strip_comment(line)):
                    if recv in ("self", "super") or name not in defs or path in defs[name]:
                        continue
                    hits.add("%s: %s.%s" % (path, recv, name), "%s:%d" % (path, lineno))
    return hits


def main():
    return gd_ratchet.run(
        sys.argv, find_calls(engine_privates()), ALLOWLIST,
        header="Grandfathered calls into scripts/core + scripts/effects private methods.",
        name="check_engine_private_calls.py",
        new_label="NEW private engine call",
        hint="Call a public engine method instead (add one to the engine if missing).")


if __name__ == "__main__":
    sys.exit(main())
