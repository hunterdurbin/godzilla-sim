#!/usr/bin/env python3
"""Tracker tickets are cited fully qualified in the code repo.

In this repo a bare `#N` means a code-repo PR; a tracker ticket needs the
full `hunterdurbin/godzilla-sim-issue-tracker#N` (docs/agents/issue-tracker.md
§ Referencing code). Inside the tracker, a grilling decision is cited as
`#35 row 3`, and that form leaks into code comments, where it reads as a PR.

Flags the two forms that always mean a tracker ticket: `#N row M` (a
decision-table row) and `tracker #N`, when `#N` is not already qualified
(`owner/repo#N`). Scans .gd / .py / .sh / .md files under scripts/, scenes/,
tests/ and githooks/. Write
`hunterdurbin/godzilla-sim-issue-tracker#35 row 3` instead.
(Commit messages get a warning from githooks/commit-msg.)

Usage: python3 scripts/tools/check_tracker_refs.py
"""
import os
import re
import sys

from gd_ratchet import ROOT

SCAN_DIRS = ("scripts", "scenes", "tests", "githooks")
EXTENSIONS = (".gd", ".py", ".sh", ".md")
SELF = os.path.join("scripts", "tools", "check_tracker_refs.py")
# `#N` not glued to a word/path before it (owner/repo#N is qualified).
BARE = r"(?<![\w./-])#\d+"
REF_RE = re.compile(BARE + r" rows? \d+|\btracker " + BARE)


def files():
    for d in SCAN_DIRS:
        for dirpath, dirs, names in os.walk(os.path.join(ROOT, d)):
            dirs[:] = [x for x in dirs if x != "__pycache__"]
            for f in sorted(names):
                path = os.path.relpath(os.path.join(dirpath, f), ROOT)
                if (f.endswith(EXTENSIONS) or d == "githooks") and path != SELF:
                    yield path


def violations(path, lines):
    for i, line in enumerate(lines, 1):
        if REF_RE.search(line):
            yield "%s:%d  %s" % (path, i, line.strip())


def self_test():
    cases = {
        "\t# #35 row 3: submit only marks the stack changed": True,
        "## (#35 rows 9-13)": True,
        "# --- Mutators emit immediately (tracker #23) ---": True,
        "handle StandbyEntry arrays (tracker #35 row 2).": True,
        "\t# hunterdurbin/godzilla-sim-issue-tracker#35 row 3: submit": False,
        "(tracker hunterdurbin/godzilla-sim-issue-tracker#23)": False,
        "\t# Merged in #240.": False,
        "\tvar row := rows[3]  # row 3": False,
        "\tcolor = \"#335 row\"": False,
    }
    bad = [src for src, expect in cases.items()
           if bool(list(violations("x.gd", [src]))) != expect]
    for b in bad:
        print("SELF-TEST mismatch: " + b)
    return not bad


def main():
    if not self_test():
        return 1
    found = []
    for path in files():
        with open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as fh:
            found.extend(violations(path, fh.read().splitlines()))
    for v in found:
        print("BARE tracker ref  " + v)
    if found:
        print("\nA bare #N means a code-repo PR here. Write the tracker ticket as"
              " hunterdurbin/godzilla-sim-issue-tracker#N (docs/agents/issue-tracker.md).")
        return 1
    print("tracker refs: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
