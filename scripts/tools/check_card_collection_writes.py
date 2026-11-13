#!/usr/bin/env python3
"""Ratchet: per-card effect scripts don't write player card collections.

Card scripts express intent; the engine enforces rules (scripts/effects/README.md
§ Per-card scripts). A card script that edits a player's hand, discard pile,
main deck, monster deck or strategy zones by hand skips what the EffectHandler
primitives do: logging, hand_changed / discard_changed / deck_changed signals,
and triggers such as on_card_returned_from_discard or discard-from-hand
watchers. Use a primitive (add_card_to_hand(s), return_discard_to_hand,
discard_cards, discard_hand_to, take_hand_card, search_deck / search_discard,
put_card_on_top/bottom_of_deck, place_cards_under_monster, ...) or add one.

Flagged, on a dotted access (`x.hand`) or a local alias of one
(`var d := ctx.owner.discard_pile`):
  - reassignment            `ctx.owner.hand = []`, `x.main_deck += cards`
  - index assignment        `ctx.owner.strategy_zones[2] = {}`
  - mutating Array methods  append, insert, pop_at, erase, shuffle, resize, ...
Reads (`.size()`, iteration, indexing, `.duplicate()`) are fine.

Scans per-card scripts only: scripts/effects/<set>/*.gd (the engine modules in
scripts/effects/*.gd ARE the engine). Existing hits are grandfathered in
card_collection_writes_allowlist.txt as `<file>: <code line>` keys, one line
per occurrence (no line numbers). The check fails on a hit that is not
allowlisted AND on an allowlisted occurrence that no longer exists, so the
list only shrinks.

Usage: python3 scripts/tools/check_card_collection_writes.py [--update]
  --update  rewrite the allowlist from the current tree (review the diff:
            additions need a reason in the PR).
"""
import collections
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
EFFECTS_DIR = os.path.join(ROOT, "scripts", "effects")
ALLOWLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "card_collection_writes_allowlist.txt")

COLLECTIONS = ("hand", "discard_pile", "main_deck", "monster_deck", "strategy_zones")
MUTATORS = (
    "append", "append_array", "push_front", "push_back", "insert",
    "pop_front", "pop_back", "pop_at", "remove_at", "erase", "clear",
    "resize", "fill", "assign", "reverse", "sort", "sort_custom", "shuffle",
)

COLL = "(?:%s)" % "|".join(COLLECTIONS)
# What follows the collection expression to make it a write.
WRITE_TAIL = (
    r"\s*(?:"
    r"[-+*/]?=(?!=)"                      # reassignment / compound assignment
    r"|\[[^\]]*\]\s*[-+*/]?=(?!=)"        # index assignment
    r"|\.\s*(?:%s)\s*\("                  # mutating method call
    r")" % "|".join(MUTATORS)
)
DOTTED_WRITE_RE = re.compile(r"\.\s*%s\b%s" % (COLL, WRITE_TAIL))
# `var d := ctx.owner.discard_pile` (the whole statement is the collection,
# so a `.duplicate()` copy is not an alias).
ALIAS_RE = re.compile(r"^\s*var\s+([A-Za-z_]\w*)\s*(?::\s*[\w\[\]]*\s*)?:?=\s*(?:[A-Za-z_]\w*\.)+%s\s*$" % COLL)


def card_scripts():
    for entry in sorted(os.listdir(EFFECTS_DIR)):
        set_dir = os.path.join(EFFECTS_DIR, entry)
        if not os.path.isdir(set_dir):
            continue
        for f in sorted(os.listdir(set_dir)):
            if f.endswith(".gd"):
                yield os.path.relpath(os.path.join(set_dir, f), ROOT)


def strip_comment(line):
    # Drop a trailing `# ...` that is outside a string literal.
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote and line[i - 1] != "\\":
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            return line[:i]
    return line


def find_writes(path, lines):
    """Yield (lineno, code) for every collection write in one script."""
    aliases = {m.group(1) for l in lines for m in [ALIAS_RE.search(l)] if m}
    alias_re = None
    if aliases:
        alias_re = re.compile(r"(?<![\w.])(?:%s)\b%s" % ("|".join(sorted(aliases)), WRITE_TAIL))
    for lineno, line in enumerate(lines, 1):
        if DOTTED_WRITE_RE.search(line) or (alias_re and alias_re.search(line)):
            yield lineno, line.strip()


def scan():
    found = collections.Counter()  # key -> occurrences
    where = collections.defaultdict(list)  # key -> ["path:line", ...]
    for path in card_scripts():
        with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
            lines = [strip_comment(l.rstrip("\n")) for l in fh]
        for lineno, code in find_writes(path, lines):
            key = "%s: %s" % (path, code)
            found[key] += 1
            where[key].append("%s:%d" % (path, lineno))
    return found, where


def read_allowlist():
    allowed = collections.Counter()
    if os.path.exists(ALLOWLIST):
        with open(ALLOWLIST, encoding="utf-8") as fh:
            for l in fh:
                l = l.strip()
                if l and not l.startswith("#"):
                    allowed[l] += 1
    return allowed


def self_test():
    """Pattern sanity: catches the forms we ban, ignores reads."""
    bad = [
        "ctx.owner.hand.append(found)",
        "ctx.opponent.discard_pile.pop_at(i)",
        "ctx.owner.main_deck.shuffle()",
        "ctx.owner.strategy_zones[2] = {}",
        "ctx.owner.strategy_zones.resize(3)",
        "player.monster_deck.erase(placed)",
        "ctx.owner.hand = []",
        "p.main_deck += cards",
    ]
    ok = [
        "for card in ctx.owner.hand:",
        "if ctx.owner.discard_pile.size() > 0:",
        "var top: Dictionary = ctx.owner.main_deck[0]",
        "if ctx.owner.strategy_zones[2] == {}:",
        "var pool := ctx.owner.discard_pile.duplicate()",
        "ctx.owner.monster_stack.append(card)",
        "var hand_count := ctx.owner.hand.size()",
    ]
    failures = [s for s in bad if not list(find_writes("x", [s]))]
    failures += [s for s in ok if list(find_writes("x", [s]))]
    alias_src = ["var pile := ctx.owner.discard_pile", "pile.pop_back()"]
    if not list(find_writes("x", alias_src)):
        failures.append(" / ".join(alias_src))
    for s in failures:
        print("SELF-TEST mismatch: %s" % s)
    return not failures


def main():
    if not self_test():
        return 1
    found, where = scan()
    if "--update" in sys.argv:
        with open(ALLOWLIST, "w", encoding="utf-8") as fh:
            fh.write("# Grandfathered player-collection writes in per-card scripts (one line per occurrence).\n")
            fh.write("# Generated by check_card_collection_writes.py --update; only ever shrink it.\n")
            for key in sorted(found):
                for _ in range(found[key]):
                    fh.write(key + "\n")
        print("Wrote %d entries to %s" % (sum(found.values()), os.path.relpath(ALLOWLIST, ROOT)))
        return 0

    allowed = read_allowlist()
    new = found - allowed
    stale = allowed - found
    for key in sorted(new):
        print("NEW collection write     %s  (%s)" % (key, ", ".join(where[key])))
    for key in sorted(stale):
        print("STALE allowlist entry    %s  (remove %d line(s) from the allowlist)" % (key, stale[key]))
    if new:
        print("\nCard scripts express intent; route hand/discard/deck/strategy-zone changes"
              " through an EffectHandler primitive (add_card_to_hand, discard_cards,"
              " return_discard_to_hand, put_card_on_top_of_deck, ...) or add one to the engine.")
    if new or stale:
        return 1
    print("card collection writes: OK (%d grandfathered)" % sum(allowed.values()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
