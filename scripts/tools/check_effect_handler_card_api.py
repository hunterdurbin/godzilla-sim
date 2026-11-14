#!/usr/bin/env python3
"""Ratchet + guards: EffectHandler is exactly the card-script interface.

EffectHandler (scripts/effects/effect_handler.gd) is the interface the
per-card scripts (scripts/effects/<set>/*.gd) call. The engine modules hold
direct references to each other (wired in EffectHandler.setup), and core /
UI / bot / test code calls those modules (`effect_handler.queries`,
`.dispatcher`, `.check_timing`, ...) rather than the facade. Two rules:

1. Ratchet: every public EffectHandler method has a card-script caller. A
   facade method no card script calls is dead weight on the card-facing
   interface: delete it and call the module instead.
2. Guard: card scripts never reach past the facade into a module
   (`ctx.effect_handler.queries.x(...)`); they call the facade primitive.
   No allow-list.
3. Guard: every `effect_handler.<name>` / `["effect_handler"].<name>` under
   scripts/, scenes/ and tests/ names a real EffectHandler member (method,
   signal, var, or an Object built-in in OBJECT_MEMBERS). Through an
   untyped receiver a call to a removed or misspelled method still compiles
   and only fails when the line runs. No allow-list.

A method counts as called only through a handler receiver (comments
stripped):
  - `effect_handler.<name>` (`ctx.effect_handler`, or a parameter of that
    name) and `EffectHandler.<name>` (static);
  - a local or parameter that holds the handler in the same file: typed
    `: EffectHandler`, or assigned `= ctx.effect_handler` / `:=`.
A same-named method on another object (`ctx.owner.<name>`) does not count.
Lifecycle methods called by the match owner (EXEMPT below) are not
card-facing and need no caller.

Methods still pending removal are grandfathered in
effect_handler_card_api_allowlist.txt as
`scripts/effects/effect_handler.gd: func <name>` keys. Rule 1 fails on a
public method with no card caller that is not allowlisted AND on an
allowlisted one that has a caller or no longer exists, so the list only
shrinks (gd_ratchet.py).

Usage: python3 scripts/tools/check_effect_handler_card_api.py [--update]
  --update  rewrite the allowlist from the current tree (review the diff:
            additions need a reason in the PR).
"""
import os
import re
import sys

import gd_ratchet
from gd_ratchet import ROOT

FACADE = "scripts/effects/effect_handler.gd"
ALLOWLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "effect_handler_card_api_allowlist.txt")

# Lifecycle, called by the match owner (MatchFactory / TurnManager), not cards.
EXEMPT = {"setup", "teardown"}

# Receivers that are always the handler.
HANDLER_RECEIVERS = {"effect_handler", "EffectHandler"}
# The EffectHandler members holding the engine modules (see setup).
MODULE_RECEIVERS = {"registry", "check_timing", "dispatcher", "destruction",
                    "mover", "monster_mover", "enter_zone", "queries"}

DEF_RE = re.compile(r"^(?:static\s+)?func\s+([a-z]\w*)\s*\(", re.M)
MEMBER_RE = re.compile(r"^(?:(?:static\s+)?func|signal|var)\s+(\w+)", re.M)
# Object / RefCounted members reachable on any EffectHandler.
OBJECT_MEMBERS = {"new", "connect", "disconnect", "is_connected", "emit_signal", "get", "set",
                  "call", "callv", "has_method", "has_signal", "get_script", "get_class", "is_class",
                  "free", "reference", "unreference", "get_reference_count"}
MEMBER_ACCESS_RE = re.compile(r"(?:\beffect_handler|\[\"effect_handler\"\])\.([A-Za-z_]\w*)")
SCAN_DIRS = ("scripts", "scenes", "tests")
SKIP_FILES = {"scripts/effects/trigger_map.gd"}  # generated
# `name: EffectHandler` (var or parameter) or `name [: T] = / := ctx.effect_handler`
# (the alias ends there — not `ctx.effect_handler.foo(...)`).
ALIAS_RE = re.compile(r"\b([A-Za-z_]\w*)\s*:\s*EffectHandler\b"
                      r"|\b([A-Za-z_]\w*)\s*(?::\s*\w+\s*)?:?=\s*\w+\.effect_handler\b(?!\s*\.)")
# Lookahead pairing so each link of a chain (`ctx.effect_handler.used`) gets
# its own receiver.
CALL_RE = re.compile(r"\b([A-Za-z_]\w*)(?=\.([a-z]\w*)\b)")
MODULE_REACH_RE = re.compile(r"\beffect_handler\.(%s)\b" % "|".join(sorted(MODULE_RECEIVERS)))


def public_methods(src):
    return [m for m in DEF_RE.findall(src) if m not in EXEMPT]


def handler_receivers(text):
    """The handler receivers in one card script: the fixed names plus the
    file's aliases."""
    recvs = set(HANDLER_RECEIVERS)
    for typed, assigned in ALIAS_RE.findall(text):
        recvs.add(typed or assigned)
    return recvs


def card_called_names(card_texts):
    """Names accessed as `<handler receiver>.<name>` in the card scripts."""
    called = set()
    for text in card_texts:
        recvs = handler_receivers(text)
        for recv, name in CALL_RE.findall(text):
            if recv in recvs:
                called.add(name)
    return called


def find_uncalled(facade_src, card_texts):
    called = card_called_names(card_texts)
    hits = gd_ratchet.Hits()
    for name in public_methods(facade_src):
        if name not in called:
            hits.add("%s: func %s" % (FACADE, name), FACADE)
    return hits


def find_module_reach(cards):
    """(path:line, code) for each card-script access to an engine module."""
    out = []
    for path, text in cards:
        for lineno, line in enumerate(text.split("\n"), 1):
            m = MODULE_REACH_RE.search(line)
            if m:
                out.append(("%s:%d" % (path, lineno), "effect_handler.%s" % m.group(1)))
    return out


def facade_members(facade_src):
    return set(MEMBER_RE.findall(facade_src)) | OBJECT_MEMBERS


def find_unknown_members(members, files):
    """(path:line, name) for each `effect_handler.<name>` naming no member."""
    out = []
    for path, lines in files:
        for lineno, line in enumerate(lines, 1):
            for name in MEMBER_ACCESS_RE.findall(line):
                if name not in members:
                    out.append(("%s:%d" % (path, lineno), name))
    return out


def gd_files():
    for d in SCAN_DIRS:
        for dirpath, _, names in os.walk(os.path.join(ROOT, d)):
            for f in sorted(names):
                if f.endswith(".gd"):
                    path = os.path.relpath(os.path.join(dirpath, f), ROOT)
                    if path not in SKIP_FILES:
                        yield path


def _strip(text):
    return "\n".join(gd_ratchet.strip_comment(l) for l in text.split("\n"))


def self_test():
    facade = ("func setup() -> void:\nfunc used(a) -> void:\nfunc unused() -> void:\nfunc _private() -> void:\n"
              "static func s_used() -> void:\nfunc via_module() -> void:\nfunc via_other() -> void:\n"
              "func via_typed() -> void:\nfunc via_assigned() -> void:\nfunc via_param() -> void:\n")
    cards = [
        "ctx.effect_handler.used(1)\n",
        "var f := EffectHandler.s_used\n# ctx.effect_handler.unused()\n",
        "ctx.effect_handler.queries.via_module()\n",
        "ctx.owner.via_other()\n",
        "var handler: EffectHandler = ctx.effect_handler\nhandler.via_typed()\n",
        "var eh := ctx.effect_handler\neh.via_assigned()\nvar n := ctx.effect_handler.used(1)\nn.unused()\n",
        "func bot(o, eff: EffectHandler) -> bool:\n\treturn eff.via_param()\n",
    ]
    cards = [_strip(t) for t in cards]
    got = set(find_uncalled(facade, cards).count)
    want = {"%s: func %s" % (FACADE, n) for n in ("unused", "via_module", "via_other")}
    assert got == want, "self-test: got %s, want %s" % (sorted(got), sorted(want))
    reach = find_module_reach([("c.gd", cards[2]), ("d.gd", cards[0])])
    assert reach == [("c.gd:1", "effect_handler.queries")], "self-test: module reach got %s" % reach
    members = facade_members("signal log_message(t)\nvar queries: EffectQueries\nfunc used() -> void:\n")
    unknown = find_unknown_members(members, [("u.gd", [
        "_bot.effect_handler.gone(1)", "s[\"effect_handler\"].used()", "effect_handler.queries.x()",
        "effect_handler.log_message.emit(t)", "my_effect_handler.gone()", "effect_handler.call(\"used\")"])])
    assert unknown == [("u.gd:1", "gone")], "self-test: unknown members got %s" % unknown


def main():
    self_test()
    with open(os.path.join(ROOT, FACADE), encoding="utf-8") as fh:
        facade_src = fh.read()
    cards = [(p, "\n".join(gd_ratchet.read_lines(p))) for p in gd_ratchet.card_scripts()]

    reach = find_module_reach(cards)
    for where, code in reach:
        print("%-36s  %s  (%s)" % ("Card script reaches an engine module", code, where))
    if reach and "--update" not in sys.argv:
        print("\nCard scripts call the EffectHandler primitive, never a module behind it "
              "(add a facade delegate if the card needs one).\n")

    unknown = find_unknown_members(facade_members(facade_src),
                                   [(p, gd_ratchet.read_lines(p)) for p in gd_files()])
    for where, name in unknown:
        print("%-36s  effect_handler.%s  (%s)" % ("No such EffectHandler member", name, where))
    if unknown:
        print("\nCall the engine module that owns it (effect_handler.queries / .dispatcher / "
              ".check_timing / ...), or fix the name.\n")

    status = gd_ratchet.run(
        sys.argv, find_uncalled(facade_src, [t for _, t in cards]), ALLOWLIST,
        header="Public EffectHandler methods with no card-script caller, pending removal.",
        name="check_effect_handler_card_api.py",
        new_label="NEW non-card EffectHandler method",
        hint="EffectHandler is the card-script interface: call the engine module "
             "(effect_handler.queries / .dispatcher / .check_timing / ...) instead of "
             "adding a facade method no card script calls.")
    return 1 if reach or unknown else status


if __name__ == "__main__":
    sys.exit(main())
