#!/usr/bin/env python3
"""Every tracked GDScript file has its tracked `.uid` beside it.

Godot 4 gives each script a `<file>.gd.uid` that scenes and resources
reference by uid. A `.gd` file committed without it leaves the `.uid`
regenerated, untracked, in every checkout: noise in `git status`, and a
`git stash -u` that then refuses to pop ("already exists").

Flags each `git ls-files` `.gd` path whose `.gd.uid` is not tracked too,
except where Godot does not import: a path with a dot-directory (`.claude/`,
`.github/`) or under a folder holding a `.gdignore`. Fix: `git add` the
`.uid` (open the project or run `./tests/import.sh <godot>` if it is missing).

Usage: python3 scripts/tools/check_gd_uid_pairs.py
"""
import os
import subprocess
import sys

from gd_ratchet import ROOT


def tracked_files():
    out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"], capture_output=True, check=True)
    return [p for p in out.stdout.decode("utf-8").split("\0") if p]


def godot_ignored(path, gdignore_dirs):
    parts = path.split("/")
    if any(part.startswith(".") for part in parts[:-1]):
        return True
    return any(path.startswith(d + "/") for d in gdignore_dirs)


def missing_uids(files):
    tracked = set(files)
    gdignore_dirs = [os.path.dirname(p) for p in files if os.path.basename(p) == ".gdignore"]
    return [p for p in files
            if p.endswith(".gd") and p + ".uid" not in tracked
            and not godot_ignored(p, gdignore_dirs)]


def self_test():
    files = [
        "scripts/a.gd", "scripts/a.gd.uid",
        "scripts/b.gd",
        ".claude/skills/verify/driver.gd",
        "docs/.gdignore", "docs/tool.gd",
        "addons/x/.gdignore", "addons/x/y/z.gd",
        "addons/xy/z.gd", "addons/xy/z.gd.uid",
    ]
    got = missing_uids(files)
    if got != ["scripts/b.gd"]:
        print("SELF-TEST mismatch: %s" % got)
        return False
    return True


def main():
    if not self_test():
        return 1
    missing = missing_uids(tracked_files())
    for p in missing:
        print("UID not tracked  %s.uid" % p)
    if missing:
        print("\nCommit each script's .uid with it (`git add <file>.gd.uid`).")
        return 1
    print("gd uid pairs: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
