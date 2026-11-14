#!/usr/bin/env python3
"""Ratchet: every public EffectHandler method has a card-script caller.

EffectHandler (scripts/effects/effect_handler.gd) is the interface the
per-card scripts (scripts/effects/<set>/*.gd) call. The engine modules hold
direct references to each other (wired in EffectHandler.setup), and core /
UI / bot / test code calls those modules (`effect_handler.queries`,
`.dispatcher`, `.check_timing`, ...) rather than the facade. So a public
facade method that no card script calls is dead weight on the card-facing
interface: delete it and call the module instead.

A method counts as called when a card script contains `.<name>` (comments
stripped) on any receiver except an engine module (`queries.<name>`,
`dispatcher.<name>`, ...): a card reaching past the facade into a module
doesn't keep the facade's same-named delegate alive. A same-named method on
some other object (e.g. a PlayerState) still counts. Lifecycle methods
called by the match owner (EXEMPT below) are not card-facing and need no
caller.

Methods still pending removal are grandfathered in
effect_handler_card_api_allowlist.txt as
`scripts/effects/effect_handler.gd: func <name>` keys. The check fails on a
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

DEF_RE = re.compile(r"^(?:static\s+)?func\s+([a-z]\w*)\s*\(", re.M)


def public_methods(src):
    return [m for m in DEF_RE.findall(src) if m not in EXEMPT]


# The EffectHandler members holding the engine modules (see setup).
MODULE_RECEIVERS = {"registry", "check_timing", "dispatcher", "destruction",
                    "mover", "monster_mover", "enter_zone", "queries"}
CALL_RE = re.compile(r"\.([a-z]\w*)\b")
RECV_RE = re.compile(r"(\w*)$")


def card_called_names(card_texts):
    """Names accessed as `<recv>.<name>`, skipping module receivers; each
    `.name` in a chain (`ctx.effect_handler.queries.x`) is paired with the
    word right before it."""
    called = set()
    for text in card_texts:
        for m in CALL_RE.finditer(text):
            recv = RECV_RE.search(text, 0, m.start()).group(1)
            if recv not in MODULE_RECEIVERS:
                called.add(m.group(1))
    return called


def find_uncalled(facade_src, card_texts):
    called = card_called_names(card_texts)
    hits = gd_ratchet.Hits()
    for name in public_methods(facade_src):
        if name not in called:
            hits.add("%s: func %s" % (FACADE, name), FACADE)
    return hits


def self_test():
    facade = ("func setup() -> void:\nfunc used(a) -> void:\nfunc unused() -> void:\nfunc _private() -> void:\n"
              "static func s_used() -> void:\nfunc via_module() -> void:\n")
    cards = ["ctx.effect_handler.used(1)\n", "var f := EffectHandler.s_used\n# ctx.effect_handler.unused()\n",
             "ctx.effect_handler.queries.via_module()\n"]
    cards = ["\n".join(gd_ratchet.strip_comment(l) for l in t.split("\n")) for t in cards]
    got = set(find_uncalled(facade, cards).count)
    want = {"%s: func unused" % FACADE, "%s: func via_module" % FACADE}
    assert got == want, "self-test: got %s, want %s" % (sorted(got), sorted(want))


def main():
    self_test()
    with open(os.path.join(ROOT, FACADE), encoding="utf-8") as fh:
        facade_src = fh.read()
    card_texts = ["\n".join(gd_ratchet.read_lines(p)) for p in gd_ratchet.card_scripts()]
    return gd_ratchet.run(
        sys.argv, find_uncalled(facade_src, card_texts), ALLOWLIST,
        header="Public EffectHandler methods with no card-script caller, pending removal.",
        name="check_effect_handler_card_api.py",
        new_label="NEW non-card EffectHandler method",
        hint="EffectHandler is the card-script interface: call the engine module "
             "(effect_handler.queries / .dispatcher / .check_timing / ...) instead of "
             "adding a facade method no card script calls.")


if __name__ == "__main__":
    sys.exit(main())
