#!/usr/bin/env python3
"""Ratchet: no new GDScript compile warnings.

Godot only prints GDScript warnings when a script compiles in debug mode, so
no pure-text check sees them and they pile up unnoticed. This check runs
dump_gdscript_warnings.gd (headless, `-d`: compiles every .gd under scripts/,
scenes/ and tests/) and collects each `WARNING: <message>` whose location is
`GDScript::reload (res://<file>:<line>)`.

Exempt: UNUSED_PARAMETER on `test_parameters` in tests/ — gdUnit4 reads
parameterized-test cases from a parameter with exactly that name, so it can
never be prefixed with _ (GDUNIT_TEST_PARAMETERS_RE).

Keys are `<file>: <message>` (no line numbers), grandfathered in
gdscript_warnings_allowlist.txt, one line per occurrence. The check fails on
a NEW warning AND on a STALE allowlist line, so the list only shrinks
(gd_ratchet.py). A SCRIPT ERROR in the dump also fails it.

Usage:
  python3 scripts/tools/check_gdscript_warnings.py <godot> [--update]
      <godot> defaults to $GODOT_BIN. --update rewrites the allowlist from the
      dump (review the diff: additions need a reason in the PR).
  python3 scripts/tools/check_gdscript_warnings.py --log <file> --new-only
      Parse an existing Godot log (e.g. the gdUnit run's) and print only NEW
      warnings; always exits 0. A partial log can't prove an entry stale.
"""
import os
import re
import subprocess
import sys
import tempfile
import time

import gd_ratchet
from gd_ratchet import ROOT

ALLOWLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gdscript_warnings_allowlist.txt")
DUMP_SCRIPT = "scripts/tools/dump_gdscript_warnings.gd"
DONE_MARKER = "DUMP_GDSCRIPT_WARNINGS_DONE"
TIMEOUT = int(os.environ.get("GDSCRIPT_WARNINGS_TIMEOUT", "300"))

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
WARNING_RE = re.compile(r"^WARNING: (.*)$")
LOCATION_RE = re.compile(r"^\s*at: GDScript::reload \(res://(.+):(\d+)\)")
GDUNIT_TEST_PARAMETERS_RE = re.compile(r'^The parameter "test_parameters" is never used in the function "test_\w+\(\)"')


def exempt(path, message):
    """gdUnit4's parameterized-test convention: see the module docstring."""
    return path.startswith("tests/") and GDUNIT_TEST_PARAMETERS_RE.match(message) is not None


def parse(lines):
    """(Hits of compile warnings, count of SCRIPT ERROR lines)."""
    hits = gd_ratchet.Hits()
    errors = 0
    for i, line in enumerate(lines):
        if line.startswith("SCRIPT ERROR"):
            errors += 1
        m = WARNING_RE.match(line)
        if not m or i + 1 >= len(lines):
            continue
        loc = LOCATION_RE.match(lines[i + 1])
        if loc and not exempt(loc.group(1), m.group(1).strip()):
            # (runtime push_warning()s have other locations: not ours)
            hits.add("%s: %s" % (loc.group(1), m.group(1).strip()), "%s:%s" % loc.groups())
    return hits, errors


def read_log(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return [ANSI_RE.sub("", l.rstrip("\n")) for l in fh]


def run_dump(godot):
    """Run the dumper and return its log lines. Polls for the done marker and
    kills the process: headless Godot can hang at exit after the work."""
    fd, log_path = tempfile.mkstemp(prefix="gd_warnings_", suffix=".log")
    with os.fdopen(fd, "w") as log:
        proc = subprocess.Popen(
            [godot, "--headless", "--path", ROOT, "-d", "--script", DUMP_SCRIPT],
            stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        start = time.time()
        while True:
            time.sleep(1)
            lines = read_log(log_path)
            text = "\n".join(lines)
            if DONE_MARKER in text:
                break
            if "handle_crash" in text or "debug>" in text or proc.poll() is not None:
                print("check_gdscript_warnings.py: the dump did not finish; log: " + log_path)
                proc.kill()
                sys.exit(1)
            if time.time() - start > TIMEOUT:
                print("check_gdscript_warnings.py: TIMEOUT after %ds; log: %s" % (TIMEOUT, log_path))
                proc.kill()
                sys.exit(1)
        proc.kill()
    os.remove(log_path)
    return lines


def new_only(lines):
    hits, _ = parse(lines)
    new = hits.count - gd_ratchet.read_allowlist(ALLOWLIST)
    for key in sorted(new):
        print("NEW GDScript warning  %s  (%s)" % (key, ", ".join(hits.where[key])))
    return 0


def main(argv):
    if "--log" in argv:
        i = argv.index("--log")
        # A partial log can't prove an allowlist entry stale, so --log only
        # reports NEW warnings (never the full ratchet or --update).
        if i + 1 >= len(argv) or "--new-only" not in argv or "--update" in argv:
            print("usage: check_gdscript_warnings.py --log <file> --new-only")
            return 2
        return new_only(read_log(argv[i + 1]))
    else:
        positional = [a for a in argv[1:] if not a.startswith("--")]
        godot = positional[0] if positional else os.environ.get("GODOT_BIN", "")
        if not godot:
            print("usage: check_gdscript_warnings.py <godot> [--update]  (or set GODOT_BIN)")
            return 2
        lines = run_dump(godot)

    hits, errors = parse(lines)
    if errors:
        print("SCRIPT ERROR x%d while compiling project scripts (rerun the dump to see them)" % errors)
        return 1
    return gd_ratchet.run(
        argv, hits, ALLOWLIST,
        header="Grandfathered GDScript compile warnings (<file>: <message>).",
        name="check_gdscript_warnings.py",
        new_label="NEW GDScript warning",
        hint="Fix the warning (prefix an unused name with _, rename a shadowing one,"
             " drop a needless await); allowlist it only with a reason in the PR.")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
