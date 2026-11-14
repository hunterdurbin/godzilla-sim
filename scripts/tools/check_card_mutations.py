#!/usr/bin/env python3
"""Card scripts express intent; PlayerState mutators change state.

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

  change signals:
      `hand_changed.emit(` and the other PlayerState signals -- the
      PlayerState mutators emit them (tracker #23)

Engine scope (scripts/core/**, scripts/effects/*.gd) -- a ratchet with
engine_player_state_writes_allowlist.txt. The engine changes a player's
areas only through PlayerState mutators (push_zone_card, add_to_discard,
set_current_monster, set_rage, ...), each of which emits its *_changed
signal immediately. Flagged: writes to the collections above plus
monster_stack / strategy_zone_stacks, `zones[...]` writes, `rage` /
`current_monster` assignment, and PlayerState signal emits. Exempt:
player_state.gd (the mutators). monster_zone is check_monster_zone_writers.py's
(MonsterMover moves through PlayerState.set_monster_zone).

Reads (`.size()`, iteration, indexing, `.duplicate()`, comparisons) are fine.

Usage: python3 scripts/tools/check_card_mutations.py [--update]
"""
import glob
import os
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

# --- PlayerState change signals (emitted only by its mutators) ---
SIGNALS = ("hand_changed", "zones_changed", "monster_changed", "rage_changed",
           "strategy_zones_changed", "deck_changed", "discard_changed",
           "discard_reshuffled")
EMIT_RE = re.compile(r"\b(?:%s)\s*\.\s*emit\s*\(" % "|".join(SIGNALS))

# --- engine scope ---
ENGINE_COLLECTIONS = COLLECTIONS + ("monster_stack", "strategy_zone_stacks")
ENGINE_COLL = "(?:%s)" % "|".join(ENGINE_COLLECTIONS)
ENGINE_DOTTED_WRITE_RE = re.compile(r"\.\s*%s\b%s" % (ENGINE_COLL, WRITE_TAIL))
ENGINE_ALIAS_RE = re.compile(r"^\s*var\s+([A-Za-z_]\w*)\s*(?::\s*[\w\[\]]*\s*)?:?=\s*(?:[A-Za-z_]\w*\.)+%s\s*$" % ENGINE_COLL)
ENGINE_RULES = {
    "zones[...] write": ZONE_RULES["zones[...] write"],
    "rage / current_monster assignment": re.compile(r"\.\s*(?:rage|current_monster)\s*" + ASSIGN),
    "change-signal emit": EMIT_RE,
}
ENGINE_EXEMPT = ("scripts/core/player_state.gd",)
ALLOWLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "engine_player_state_writes_allowlist.txt")


def zone_violations(lines):
    for lineno, line in enumerate(lines, 1):
        for label, rx in ZONE_RULES.items():
            if rx.search(line):
                yield lineno, label, line.strip()


def collection_writes(lines, dotted_re=DOTTED_WRITE_RE, alias_decl_re=ALIAS_RE):
    aliases = {m.group(1) for l in lines for m in [alias_decl_re.search(l)] if m}
    alias_re = None
    if aliases:
        alias_re = re.compile(r"(?<![\w.])(?:%s)\b%s" % ("|".join(sorted(aliases)), WRITE_TAIL))
    for lineno, line in enumerate(lines, 1):
        if dotted_re.search(line) or (alias_re and alias_re.search(line)):
            yield lineno, line.strip()


def emits(lines):
    for lineno, line in enumerate(lines, 1):
        if EMIT_RE.search(line):
            yield lineno, line.strip()


def engine_scripts():
    """Engine files: scripts/core/** and the scripts/effects/*.gd modules."""
    paths = glob.glob(os.path.join(gd_ratchet.ROOT, "scripts", "core", "**", "*.gd"), recursive=True)
    paths += glob.glob(os.path.join(gd_ratchet.EFFECTS_DIR, "*.gd"))
    for p in sorted(paths):
        rel = os.path.relpath(p, gd_ratchet.ROOT)
        if rel not in ENGINE_EXEMPT:
            yield rel


def engine_violations(lines):
    for lineno, line in enumerate(lines, 1):
        for label, rx in ENGINE_RULES.items():
            if rx.search(line):
                yield lineno, label, line.strip()
    for lineno, code in collection_writes(lines, ENGINE_DOTTED_WRITE_RE, ENGINE_ALIAS_RE):
        yield lineno, "collection write", code


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
    emit_bad = [
        "ctx.owner.monster_changed.emit()",
        "player.rage_changed.emit(player.rage)",
        "target.zones_changed.emit()",
        "p.discard_reshuffled.emit(cards)",
    ]
    emit_ok = [
        "h.events.effect_stack_changed.emit(rows)",
        "sub_phase_changed.emit(0)",
        "player.hand_changed.connect(_on_state_changed)",
    ]
    failures += [s for s in emit_bad if not list(emits([s]))]
    failures += [s for s in emit_ok if list(emits([s]))]
    engine_bad = [
        "player.zones[a] = stack_b",
        "player.zones[i].append(card)",
        "player.rage += 1",
        "opponent.current_monster = m",
        "player.monster_stack.push_front(old)",
        "player.strategy_zone_stacks[i] = []",
        "player.strategy_zones[i] = {}",
        "var card: Dictionary = player.hand.pop_at(i)",
        "player.discard_pile.append(card)",
        "player.hand_changed.emit()",
    ]
    engine_ok = [
        "player.push_zone_card(i, card)",
        "var stack: Array = player.clear_zone(i)",
        "CardMover.banish_or_discard(player, stack)",
        "var old_rage: int = player.rage",
        "if player.rage >= 2 and player.current_monster != {}:",
        "player.set_rage(player.rage + 1)",
        "for card in player.monster_stack:",
        "var top := player.zones[i][0]",
    ]
    failures += [s for s in engine_bad if not list(engine_violations([s]))]
    failures += [s for s in engine_ok if list(engine_violations([s]))]
    for s in failures:
        print("SELF-TEST mismatch: %s" % s)
    return not failures


def card_main():
    violations = []
    for path in gd_ratchet.card_scripts():
        lines = gd_ratchet.read_lines(path)
        for lineno, label, code in zone_violations(lines):
            violations.append("%s:%d  %s  ->  %s" % (path, lineno, label, code))
        for lineno, code in collection_writes(lines):
            violations.append("%s:%d  collection write  ->  %s" % (path, lineno, code))
        for lineno, code in emits(lines):
            violations.append("%s:%d  change-signal emit  ->  %s" % (path, lineno, code))
    for v in violations:
        print("CARD MUTATION  " + v)
    if violations:
        print("\nCard scripts mutate state only through EffectHandler primitives (table:"
              " scripts/effects/README.md § Per-card scripts). Add the missing primitive to"
              " the engine instead.")
        return 1
    print("card mutations: OK")
    return 0


def engine_main(argv):
    hits = gd_ratchet.Hits()
    for path in engine_scripts():
        for lineno, label, code in engine_violations(gd_ratchet.read_lines(path)):
            hits.add("%s: %s" % (path, code), "%s:%d %s" % (path, lineno, label))
    return gd_ratchet.run(
        argv, hits, ALLOWLIST,
        "Engine writes to PlayerState state that bypass its mutators.",
        "check_card_mutations.py (engine scope)", "NEW engine PlayerState write",
        "Engine code changes a player's areas through PlayerState mutators, which emit"
        " their *_changed signal (scripts/core/player_state.gd § Mutators). Add the"
        " missing mutator instead of writing the field or emitting by hand.")


def main():
    if not self_test():
        return 1
    status = card_main() if "--update" not in sys.argv else 0
    return engine_main(sys.argv) or status

if __name__ == "__main__":
    sys.exit(main())
