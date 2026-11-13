#!/usr/bin/env python3
"""Per-card effect scripts express intent; the engine mutates state.

A card script that edits game state by hand skips what the EffectHandler
primitives apply: overload, replacement effects, leave-play, Revenge/standby,
logging, change signals, and triggers such as on_card_returned_from_discard or
discard-from-hand watchers. Use a primitive (scripts/effects/README.md
§ Per-card scripts has the table) or add one to the engine.

Flagged in per-card scripts only (scripts/effects/<set>/*.gd), with no
allowlist -- the tree is clean; add the missing primitive instead:

  zone / monster position:
      clear_zone( / push_zone_card( / banish_or_discard( calls,
      `monster_zone` assignment, `zones[...]` writes
  player collections:
      writes to hand / discard_pile / main_deck / monster_deck /
      strategy_zones (reassignment, index assignment, mutating Array
      method), also through a local alias (`var d := ctx.owner.discard_pile`)

Reads (`.size()`, iteration, indexing, `.duplicate()`, comparisons) are fine.

Usage: python3 scripts/tools/check_card_mutations.py
"""
import re
import sys

import gd_ratchet


MUTATORS = (
    "append", "append_array", "push_front", "push_back", "insert",
    "pop_front", "pop_back", "pop_at", "remove_at", "erase", "clear",
    "resize", "fill", "assign", "reverse", "sort", "sort_custom", "shuffle",
)
MUTATOR_CALL = r"\.\s*(?:%s)\s*\(" % "|".join(MUTATORS)
ASSIGN = r"[-+*/]?=(?!=)"

# --- zone / monster position ---
ZONE_RULES = {
    "clear_zone(": re.compile(r"\bclear_zone\s*\("),
    "push_zone_card(": re.compile(r"\bpush_zone_card\s*\("),
    "banish_or_discard(": re.compile(r"\bbanish_or_discard\s*\("),
    "monster_zone assignment": re.compile(r"\bmonster_zone\s*" + ASSIGN),
    "zones[...] write": re.compile(r"\bzones\s*\[[^\]]*\]\s*(?:%s|%s)" % (ASSIGN, MUTATOR_CALL)),
}

# --- player collections ---
COLLECTIONS = ("hand", "discard_pile", "main_deck", "monster_deck", "strategy_zones")
COLL = "(?:%s)" % "|".join(COLLECTIONS)
WRITE_TAIL = r"\s*(?:%s|\[[^\]]*\]\s*%s|%s)" % (ASSIGN, ASSIGN, MUTATOR_CALL)
DOTTED_WRITE_RE = re.compile(r"\.\s*%s\b%s" % (COLL, WRITE_TAIL))
# `var d := ctx.owner.discard_pile` (the whole statement is the collection, so
# a `.duplicate()` copy is not an alias).
ALIAS_RE = re.compile(r"^\s*var\s+([A-Za-z_]\w*)\s*(?::\s*[\w\[\]]*\s*)?:?=\s*(?:[A-Za-z_]\w*\.)+%s\s*$" % COLL)


def zone_violations(lines):
    for lineno, line in enumerate(lines, 1):
        for label, rx in ZONE_RULES.items():
            if rx.search(line):
                yield lineno, label, line.strip()


def collection_writes(lines):
    aliases = {m.group(1) for l in lines for m in [ALIAS_RE.search(l)] if m}
    alias_re = None
    if aliases:
        alias_re = re.compile(r"(?<![\w.])(?:%s)\b%s" % ("|".join(sorted(aliases)), WRITE_TAIL))
    for lineno, line in enumerate(lines, 1):
        if DOTTED_WRITE_RE.search(line) or (alias_re and alias_re.search(line)):
            yield lineno, line.strip()


def self_test():
    """Pattern sanity: catches the forms we ban, ignores reads and comments."""
    zone_bad = [
        "var s := ctx.owner.clear_zone(3)",
        "ctx.owner.push_zone_card(2, card)",
        "EffectHandler.banish_or_discard(ctx.owner, s)",
        "ctx.owner.monster_zone = 4",
        "ctx.owner.monster_zone += 1",
        "ctx.owner.zones[dest] = stack",
        "ctx.owner.zones[i].append(card)",
    ]
    zone_ok = [
        "var idx: int = ctx.owner.monster_zone - 1",
        "if ctx.owner.monster_zone == 4:",
        "if ctx.owner.monster_zone >= 4 and ctx.owner.monster_zone != 8:",
        "var top := ctx.owner.zones[2][0]",
        "if ctx.owner.zones[i] == []:",
        gd_ratchet.strip_comment("# ctx.owner.clear_zone(3) is forbidden"),
        "var n := ctx.owner.get_zone_stack(zone_idx).size()",
        "ctx.owner.strategy_zones[2] = {}",  # a collection write, not a zone one
    ]
    coll_bad = [
        "ctx.owner.hand.append(found)",
        "ctx.opponent.discard_pile.pop_at(i)",
        "ctx.owner.main_deck.shuffle()",
        "ctx.owner.strategy_zones[2] = {}",
        "ctx.owner.strategy_zones.resize(3)",
        "player.monster_deck.erase(placed)",
        "ctx.owner.hand = []",
        "p.main_deck += cards",
    ]
    coll_ok = [
        "for card in ctx.owner.hand:",
        "if ctx.owner.discard_pile.size() > 0:",
        "var top: Dictionary = ctx.owner.main_deck[0]",
        "if ctx.owner.strategy_zones[2] == {}:",
        "var pool := ctx.owner.discard_pile.duplicate()",
        "ctx.owner.monster_stack.append(card)",
        "var hand_count := ctx.owner.hand.size()",
    ]
    failures = [s for s in zone_bad if not list(zone_violations([s]))]
    failures += [s for s in zone_ok if list(zone_violations([s]))]
    failures += [s for s in coll_bad if not list(collection_writes([s]))]
    failures += [s for s in coll_ok if list(collection_writes([s]))]
    alias_src = ["var pile := ctx.owner.discard_pile", "pile.pop_back()"]
    if not list(collection_writes(alias_src)):
        failures.append(" / ".join(alias_src))
    for s in failures:
        print("SELF-TEST mismatch: %s" % s)
    return not failures


def main():
    if not self_test():
        return 1
    violations = []
    for path in gd_ratchet.card_scripts():
        lines = gd_ratchet.read_lines(path)
        for lineno, label, code in zone_violations(lines):
            violations.append("%s:%d  %s  ->  %s" % (path, lineno, label, code))
        for lineno, code in collection_writes(lines):
            violations.append("%s:%d  collection write  ->  %s" % (path, lineno, code))
    for v in violations:
        print("CARD MUTATION  " + v)
    if violations:
        print("\nCard scripts mutate state only through EffectHandler primitives (table:"
              " scripts/effects/README.md § Per-card scripts). Add the missing primitive to"
              " the engine instead.")
        return 1
    print("card mutations: OK")
    return 0

if __name__ == "__main__":
    sys.exit(main())
