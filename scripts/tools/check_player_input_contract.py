#!/usr/bin/env python3
"""Guard: every PlayerInput implementation and prompt handler matches the port.

PlayerInput (scripts/core/input/player_input.gd) is the engine's one decision
port. Changing a prompt's parameters touches every implementation, and two
kinds of drift fail silently or only at runtime:

1. An override whose parameter list differs from the base method. The engine
   awaits `input.<method>(...)` dynamically; a typed mismatch aborts the
   coroutine and whatever awaits it hangs. Checked: every PlayerInput
   subclass (transitively, inner test classes included) overrides each base
   method with the same parameter types and defaults (names may differ) and
   the same return type.
2. A handler connected to a SignalPlayerInput prompt signal that can't take
   the signal's argument count. Godot errors only when the signal fires, and
   some handlers (the real GameBoard's) run in no unit test or harness.
   Checked: handlers reached by `.<signal>.connect(<name>)`,
   `.<signal>.connect(func(...)`, and the `[pin.<signal>, <name>]` map form
   accept exactly the signal's arity (required <= N <= total). Connections
   through `.bind(` are skipped.

No allow-list. Built-in pattern self-test.

Usage: python3 scripts/tools/check_player_input_contract.py
"""
import os
import re
import sys

from gd_ratchet import ROOT, strip_comment

SCAN = ("scripts", "scenes", "tests")
BASE_FILE = "scripts/core/input/player_input.gd"
SIGNAL_FILE = "scripts/core/input/signal_player_input.gd"
SKIP_FILES = {"scripts/effects/trigger_map.gd"}  # generated

CLASS_NAME_RE = re.compile(r"^class_name\s+(\w+)")
TOP_EXTENDS_RE = re.compile(r"^extends\s+(\w+)")
INNER_CLASS_RE = re.compile(r"^class\s+(\w+)(?:\s+extends\s+(\w+))?\s*:")
INNER_EXTENDS_RE = re.compile(r"^\s+extends\s+(\w+)")
FUNC_START_RE = re.compile(r"^(\s*)(?:static\s+)?func\s+(\w+)\s*\(")
SIGNAL_RE = re.compile(r"^signal\s+(\w+)\s*\((.*)\)")
CONNECT_RE = re.compile(r"\.(\w+)\.connect\(")
MAP_RE = re.compile(r"\[\s*\w+\.(\w+)\s*,\s*(\w+)\s*\]")


def gd_files():
    for d in SCAN:
        for dirpath, _, files in os.walk(os.path.join(ROOT, d)):
            for f in sorted(files):
                if f.endswith(".gd"):
                    path = os.path.relpath(os.path.join(dirpath, f), ROOT)
                    if path not in SKIP_FILES:
                        yield path


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
        return [strip_comment(l.rstrip("\n")) for l in fh]


def split_top_level(args):
    """Split on commas outside brackets and strings."""
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


def paren_body(text, open_idx):
    """(inside, rest) for the `(` at open_idx; None if unbalanced."""
    depth, quote = 0, None
    for i in range(open_idx, len(text)):
        ch = text[i]
        if quote:
            if ch == quote and text[i - 1] != "\\":
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return text[open_idx + 1:i], text[i + 1:]
    return None


def parse_params(inside):
    """[(type, default)] per parameter — names dropped, whitespace normalised."""
    out = []
    for p in split_top_level(inside):
        default = None
        if "=" in p:
            p, default = p.split("=", 1)
            p = p.rstrip(":").strip()
            default = re.sub(r"\s+", "", default)
        ptype = p.split(":", 1)[1].strip() if ":" in p else ""
        out.append((re.sub(r"\s+", "", ptype), default))
    return out


def return_type(rest):
    m = re.match(r"\s*->\s*([^:]+):", rest)
    return re.sub(r"\s+", "", m.group(1)) if m else ""


def functions(lines):
    """Yield (indent, name, params, return_type, line_no) — signatures may
    span lines."""
    i = 0
    while i < len(lines):
        m = FUNC_START_RE.match(lines[i])
        if not m:
            i += 1
            continue
        text, j = lines[i], i
        while paren_body(text, text.index("(", m.end() - 1)) is None and j + 1 < len(lines):
            j += 1
            text += " " + lines[j].strip()
        body = paren_body(text, text.index("(", m.end() - 1))
        if body:
            yield len(m.group(1)), m.group(2), parse_params(body[0]), return_type(body[1]), i + 1
        i = j + 1


def classes(path, lines):
    """{class_key: (parent, {method: (params, ret, line)})} for the file's
    top-level script and its inner classes. Top-level key: its class_name or
    the path."""
    top_key, top_parent = path, None
    for l in lines:
        if m := CLASS_NAME_RE.match(l):
            top_key = m.group(1)
        if m := TOP_EXTENDS_RE.match(l):
            top_parent = m.group(1)
    out = {top_key: [top_parent, {}]}
    inner_at = {}  # line index -> inner class key
    for idx, l in enumerate(lines):
        if m := INNER_CLASS_RE.match(l):
            parent = m.group(2)
            if parent is None and idx + 1 < len(lines):
                # `class X:` then an indented `extends Y` (blank/doc lines skipped)
                for nxt in lines[idx + 1:idx + 4]:
                    if em := INNER_EXTENDS_RE.match(nxt):
                        parent = em.group(1)
                        break
            out[m.group(1)] = [parent, {}]
            inner_at[idx] = m.group(1)
    current = top_key
    owners = []
    for idx, l in enumerate(lines):
        if idx in inner_at:
            current = inner_at[idx]
        elif l and not l[0].isspace() and not l.startswith("class "):
            current = top_key
        owners.append(current)
    for indent, name, params, ret, line_no in functions(lines):
        owner = owners[line_no - 1]
        if (owner == top_key and indent == 0) or (owner != top_key and indent > 0):
            out[owner][1][name] = (params, ret, line_no)
    return out


def family(all_classes):
    """Keys of every class that (transitively) extends PlayerInput."""
    members = {"PlayerInput"}
    changed = True
    while changed:
        changed = False
        for key, (parent, _) in all_classes.items():
            if parent in members and key not in members:
                members.add(key)
                changed = True
    members.discard("PlayerInput")
    return members


def override_violations(all_classes, file_of):
    base = all_classes["PlayerInput"][1]
    for key in sorted(family(all_classes)):
        for name, (params, ret, line_no) in all_classes[key][1].items():
            if name not in base:
                continue
            b_params, b_ret, _ = base[name]
            if params != b_params or ret != b_ret:
                yield "%s:%d  %s.%s(%s) -> %s  !=  PlayerInput.%s(%s) -> %s" % (
                    file_of[key], line_no, key, name, fmt(params), ret or "?",
                    name, fmt(b_params), b_ret or "?")


def fmt(params):
    return ", ".join(t + ("=" + d if d is not None else "") for t, d in params)


def prompt_signals(lines):
    return {m.group(1): len(split_top_level(m.group(2))) for l in lines if (m := SIGNAL_RE.match(l))}


def arity_ok(params, n):
    required = sum(1 for _, d in params if d is None)
    return required <= n <= len(params)


def handler_violations(path, lines, signals, defs_by_name):
    """Connections in one file whose handler can't take the signal's args."""
    for idx, l in enumerate(lines):
        targets = []
        for m in CONNECT_RE.finditer(l):
            sig = m.group(1)
            if sig not in signals:
                continue
            body = paren_body(l, m.end() - 1)
            arg = body[0].strip() if body else l[m.end():].strip()
            if ".bind(" in arg:
                continue
            if arg.startswith("func"):
                lam = paren_body(arg, arg.index("("))
                if lam:
                    targets.append((sig, "<lambda>", [(path, idx + 1, parse_params(lam[0]))]))
                continue
            targets.append((sig, arg, None))
        for m in MAP_RE.finditer(l):
            if m.group(1) in signals:
                targets.append((m.group(1), m.group(2), None))
        for sig, arg, defs in targets:
            name = arg.split(".")[-1].strip()
            if defs is None:
                defs = defs_by_name.get(name, [])
                if "." not in arg:  # bare name: this file's method
                    defs = [d for d in defs if d[0] == path] or defs
            for d_path, d_line, params in defs:
                if not arity_ok(params, signals[sig]):
                    # Keyed by the definition so main() reports it once.
                    yield (d_path, d_line, sig), "%s:%d  %s takes %d-%d args but %s sends %d  (connected at %s:%d)" % (
                        d_path, d_line, name, sum(1 for _, d in params if d is None), len(params),
                        sig, signals[sig], path, idx + 1)


def self_test():
    sig = prompt_signals(["signal zone_target_requested(a: int, b: Array[int], c: bool, d: int)"])
    defs = {"_on_zone": [("x", 1, parse_params("a: int, b: Array[int], c: bool, d: int = -1"))],
            "_on_short": [("x", 2, parse_params("a: int, b: Array[int], c: bool"))]}
    handler_cases = {
        "pin.zone_target_requested.connect(_on_zone)": False,
        "pin.zone_target_requested.connect(bot._on_short)": True,
        "pin.zone_target_requested.connect(_on_short.bind(1))": False,
        "pin.zone_target_requested.connect(func(_a: int, _b: Array[int], _c: bool) -> void:": True,
        '"zone": [pin.zone_target_requested, _on_short],': True,
        "other_requested.connect(_on_short)": False,
    }
    base = classes("b.gd", ["class_name PlayerInput", "func pick(_p: int, zones: Array[int], _s: bool = false) -> int:", "\treturn 0"])
    sub = classes("s.gd", ["extends PlayerInput", "", "class Inner extends PlayerInput:",
                           "\tfunc pick(p: int, zones: Array, s: bool = false) -> int:", "\t\treturn 0",
                           "", "func pick(p: int,", "\t\tzones: Array[int], s: bool = false) -> int:", "\treturn 0"])
    all_classes = {**base, **sub}
    files = {k: "f" for k in all_classes}
    over = list(override_violations(all_classes, files))
    bad = []
    for src, expect in handler_cases.items():
        if bool(list(handler_violations("x", [src], sig, defs))) != expect:
            bad.append(src)
    if len(over) != 1 or "Inner.pick" not in over[0]:
        bad.append("override detection: %r" % over)
    for b in bad:
        print("SELF-TEST FAILED: " + b)
    return not bad


def main():
    if not self_test():
        return 1
    files = {p: read(p) for p in gd_files()}
    all_classes, file_of, defs_by_name = {}, {}, {}
    for path, lines in files.items():
        for key, val in classes(path, lines).items():
            all_classes[key] = val
            file_of[key] = path
        for _, name, params, _, line_no in functions(lines):
            defs_by_name.setdefault(name, []).append((path, line_no, params))
    signals = prompt_signals(files[SIGNAL_FILE])
    found = list(override_violations(all_classes, file_of))
    seen = set()
    for path, lines in files.items():
        for key, msg in handler_violations(path, lines, signals, defs_by_name):
            if key not in seen:
                seen.add(key)
                found.append(msg)
    for v in found:
        print("PLAYER INPUT CONTRACT  " + v)
    if found:
        print("check_player_input_contract.py: %d violation(s) — match the base "
              "signature in %s / the signal in %s" % (len(found), BASE_FILE, SIGNAL_FILE))
        return 1
    print("check_player_input_contract.py: OK (%d implementations, %d prompt signals)"
          % (len(family(all_classes)), len(signals)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
