#!/usr/bin/env python3
"""Is Godot's class-name cache current with the scripts on disk?

Headless runs resolve `class_name` identifiers through
.godot/global_script_class_cache.cfg, which only an import (the editor, or
tests/import.sh) rewrites. A script added, moved or renamed outside the
editor leaves it stale, and the next headless run fails with a misleading
`Identifier "X" not declared in the current scope` parse error.

Compares every `class_name X` declared in a .gd file under the project
(addons included, .godot and hidden dirs skipped) with the cache's
(class, path) pairs. Stale = a declared class missing from the cache, at a
different path, or a cached class whose file no longer declares it.

Exit 0 = current; 1 = stale (or no cache yet) — run tests/import.sh.
tests/run_unit_tests.sh calls this and imports
automatically when it fails.

Usage: python3 scripts/tools/check_class_cache.py [--quiet]
"""
import os
import re
import sys

from gd_ratchet import ROOT

CACHE = os.path.join(ROOT, ".godot", "global_script_class_cache.cfg")
CLASS_NAME_RE = re.compile(r"^\s*(?:@\w+\s+)*class_name\s+(\w+)")
CACHE_CLASS_RE = re.compile(r'^"class": &"(\w+)",?$')
CACHE_PATH_RE = re.compile(r'^"path": "res://([^"]+)",?$')


def declared_classes(root):
    """{class: repo-relative path} for every `class_name` in a .gd file."""
    found = {}
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for f in sorted(files):
            if not f.endswith(".gd"):
                continue
            path = os.path.join(dirpath, f)
            with open(path, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    m = CLASS_NAME_RE.match(line)
                    if m:
                        found[m.group(1)] = os.path.relpath(path, root).replace(os.sep, "/")
                        break
    return found


def cached_classes(text):
    """{class: path} from the cache file's text (one key per line)."""
    found, cls = {}, None
    for line in text.splitlines():
        line = line.strip()
        m = CACHE_CLASS_RE.match(line)
        if m:
            cls = m.group(1)
            continue
        m = CACHE_PATH_RE.match(line)
        if m and cls:
            found[cls] = m.group(1)
            cls = None
    return found


def differences(declared, cached):
    out = []
    for cls, path in sorted(declared.items()):
        if cls not in cached:
            out.append("not cached: %s (%s)" % (cls, path))
        elif cached[cls] != path:
            out.append("moved: %s cached at %s, declared in %s" % (cls, cached[cls], path))
    for cls, path in sorted(cached.items()):
        if cls not in declared:
            out.append("gone: %s (cached at %s)" % (cls, path))
    return out


def self_test():
    cache = '\n'.join([
        'list=[{', '"base": &"RefCounted",', '"class": &"Kept",', '"icon": "",',
        '"path": "res://a/kept.gd"', '}, {', '"class": &"Moved",',
        '"path": "res://old/moved.gd"', '}, {', '"class": &"Gone",',
        '"path": "res://gone.gd"', '}]'])
    cached = cached_classes(cache)
    declared = {"Kept": "a/kept.gd", "Moved": "new/moved.gd", "Added": "added.gd"}
    got = differences(declared, cached)
    want = ["not cached: Added (added.gd)",
            "moved: Moved cached at old/moved.gd, declared in new/moved.gd",
            "gone: Gone (cached at gone.gd)"]
    ok = got == want and differences({"Kept": "a/kept.gd"}, {"Kept": "a/kept.gd"}) == []
    for line in ("class_name Foo", "@tool class_name Foo", "class_name Foo extends Bar",
                 "@tool\tclass_name Foo"):
        m = CLASS_NAME_RE.match(line)
        ok = ok and m is not None and m.group(1) == "Foo"
    ok = ok and CLASS_NAME_RE.match("# class_name Foo") is None
    if not ok:
        print("SELF-TEST failed: %s" % got)
    return ok


def main():
    if not self_test():
        return 1
    quiet = "--quiet" in sys.argv[1:]
    if not os.path.exists(CACHE):
        print("class-name cache: missing (%s) — run tests/import.sh" % os.path.relpath(CACHE, ROOT))
        return 1
    with open(CACHE, encoding="utf-8") as fh:
        diff = differences(declared_classes(ROOT), cached_classes(fh.read()))
    if diff:
        shown = diff if not quiet else diff[:5]
        print("class-name cache: STALE — run tests/import.sh")
        for d in shown:
            print("  " + d)
        if len(shown) < len(diff):
            print("  … %d more" % (len(diff) - len(shown)))
        return 1
    if not quiet:
        print("class-name cache: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
