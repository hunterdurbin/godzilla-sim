#!/usr/bin/env python3
"""Guard: no array literal reaches a typed-array parameter through a dynamic call.

GDScript converts an array literal to `Array[T]` only at a statically typed
call site. Through a dynamic call (a `Callable.bind(...)`, or a method called
on a Variant such as `session["effect_handler"].destroy_zones(p, [2])`) the
literal arrives as an untyped Array, Godot raises "does not have the same
element type as the expected typed array argument", the coroutine aborts and
whatever awaits it hangs forever (a gdUnit test STARTs and never finishes).

Flags, in scripts/ scenes/ tests/:
  <x>.<method>.bind(... [ ... ] ...)
  <x>[...].<method>(... [ ... ] ...)
where <method> is defined somewhere in scripts/ with an `Array[...]`
parameter and the array literal is a top-level argument. Fix: hoist a typed
local (`var handler: EffectHandler = s["effect_handler"]`, or
`var zones: Array[int] = [2]`), cast (`[2] as Array[int]`), or call inside
a lambda. No allowlist.

Usage: python3 scripts/tools/check_typed_array_dynamic_calls.py
"""
import os
import re
import sys

from gd_ratchet import ROOT, strip_comment

DEF_SCAN = ("scripts",)
USE_SCAN = ("scripts", "scenes", "tests")
SKIP_FILES = {"scripts/effects/trigger_map.gd"}  # generated

FUNC_RE = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)\s*\((.*?)\)\s*(?:->|:)")
BIND_RE = re.compile(r"\.(\w+)\.bind\(")
VARIANT_CALL_RE = re.compile(r"\]\.(\w+)\(")


def gd_files(dirs):
    for d in dirs:
        for dirpath, _, files in os.walk(os.path.join(ROOT, d)):
            for f in sorted(files):
                if f.endswith(".gd"):
                    path = os.path.relpath(os.path.join(dirpath, f), ROOT)
                    if path not in SKIP_FILES:
                        yield path


def split_top_level(args):
    """Split an argument string on commas outside brackets and strings."""
    parts, depth, quote, cur = [], 0, None, ""
    for i, ch in enumerate(args):
        if quote:
            cur += ch
            if ch == quote and args[i - 1] != "\\":
                quote = None
            continue
        if ch in "\"'":
            quote = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            parts.append(cur.strip())
            cur = ""
            continue
        cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts


def call_args(line, open_idx):
    """The text between the `(` at open_idx and its matching `)` (same line)."""
    depth, quote = 0, None
    for i in range(open_idx, len(line)):
        ch = line[i]
        if quote:
            if ch == quote and line[i - 1] != "\\":
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return line[open_idx + 1:i]
    return None  # call spans lines: not checked


def _untyped_literal(arg):
    """An array literal without an `as Array[...]` cast (a cast makes it typed)."""
    return arg.startswith("[") and not re.search(r"\bas\s+Array\[", arg)


def typed_array_methods(sources):
    names = set()
    for _, lines in sources:
        for line in lines:
            m = FUNC_RE.match(line)
            if m and any(re.search(r":\s*Array\[", p) for p in split_top_level(m.group(2))):
                names.add(m.group(1))
    return names


def violations(path, lines, typed):
    for i, line in enumerate(lines):
        for regex, kind in ((BIND_RE, "bind"), (VARIANT_CALL_RE, "Variant call")):
            for m in regex.finditer(line):
                if m.group(1) not in typed:
                    continue
                args = call_args(line, m.end() - 1)
                if args is not None and any(_untyped_literal(a) for a in split_top_level(args)):
                    yield "%s:%d  %s into %s()  ->  %s" % (path, i + 1, kind, m.group(1), line.strip())


def self_test():
    typed = typed_array_methods([("x", ["func destroy_zones(target: PlayerState, zones: Array[int]) -> void:"])])
    cases = {
        "await ct.run_effect(1, c, h.destroy_zones.bind(p, [2]))": True,
        'await s["effect_handler"].destroy_zones(p, [2])': True,
        "await handler.destroy_zones(p, [2])": False,  # static call: converted
        "await ct.run_effect(1, c, h.destroy_zones.bind(p, zones))": False,
        'await s["effect_handler"].destroy_zones(p, [2, 7] as Array[int])': False,  # cast: typed
        'h.other.bind(p, [2])': False,
    }
    bad = []
    for src, expect in cases.items():
        if bool(list(violations("x", [src], typed))) != expect:
            bad.append(src)
    for b in bad:
        print("SELF-TEST mismatch: " + b)
    return not bad


def main():
    if not self_test():
        return 1
    defs = [(p, [strip_comment(l.rstrip("\n")) for l in open(os.path.join(ROOT, p), encoding="utf-8")])
            for p in gd_files(DEF_SCAN)]
    typed = typed_array_methods(defs)
    found = []
    for path in gd_files(USE_SCAN):
        with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
            lines = [strip_comment(l.rstrip("\n")) for l in fh]
        found.extend(violations(path, lines, typed))
    for v in found:
        print("ARRAY LITERAL into typed-array param via dynamic call  " + v)
    if found:
        print("\nThe literal arrives untyped, the coroutine aborts and the caller hangs."
              " Hoist a typed local or call inside a lambda.")
        return 1
    print("typed-array dynamic calls: OK (%d typed-array methods)" % len(typed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
