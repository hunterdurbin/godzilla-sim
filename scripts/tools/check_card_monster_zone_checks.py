#!/usr/bin/env python3
"""Ratchet: per-card effect scripts don't re-implement play-zone legality.

Rule 5.11.1.1 (an effect can't play a card into its master's monster zone)
is enforced by the engine's play primitives, and card scripts ask
`EffectHandler.can_play_in_zone` / `CardEffect.get_effect_play_zones` for
legal zones (scripts/effects/README.md: card scripts express intent; the
engine enforces the rules). A card script that compares a zone INDEX to its
monster's zone index (`i != owner.monster_zone - 1`, or via a variable
assigned from `monster_zone - 1`) is re-deriving that rule by hand.

Comparisons against literal zone NUMBERS (`monster_zone == 8`) are card-text
conditions ("if your monster is in zone 3") and are not flagged.

Scans per-card scripts only: scripts/effects/<set>/*.gd. Existing hits are
grandfathered in card_monster_zone_checks_allowlist.txt as
`<file>: <code line>` keys, one line per occurrence (no line numbers). The
check fails on a hit that is not allowlisted AND on an allowlisted one that
no longer occurs, so the list only shrinks (gd_ratchet.py).

Usage: python3 scripts/tools/check_card_monster_zone_checks.py [--update]
  --update  rewrite the allowlist from the current tree (review the diff:
            additions need a reason in the PR).
"""
import os
import re
import sys

import gd_ratchet
ALLOWLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "card_monster_zone_checks_allowlist.txt")

MONSTER_IDX_EXPR = r"(?:[A-Za-z_]\w*\.)*monster_zone\s*-\s*1\b"
ALIAS_RE = re.compile(r"\bvar\s+([A-Za-z_]\w*)\s*(?::\s*\w+\s*)?:?=\s*" + MONSTER_IDX_EXPR)


def comparison_re(aliases):
    operand = MONSTER_IDX_EXPR
    if aliases:
        operand = r"(?:%s|\b(?:%s)\b)" % (MONSTER_IDX_EXPR, "|".join(sorted(aliases)))
    return re.compile(r"(?:[!=]=\s*%s)|(?:%s\s*[!=]=)" % (operand, operand))


def find_checks():
    hits = gd_ratchet.Hits()
    for path in gd_ratchet.card_scripts():
        lines = gd_ratchet.read_lines(path)
        aliases = {m.group(1) for l in lines for m in [ALIAS_RE.search(l)] if m}
        cmp_re = comparison_re(aliases)
        for lineno, line in enumerate(lines, 1):
            if cmp_re.search(line):
                hits.add("%s: %s" % (path, line.strip()), "%s:%d" % (path, lineno))
    return hits


def main():
    return gd_ratchet.run(
        sys.argv, find_checks(), ALLOWLIST,
        header="Grandfathered monster-zone index checks in per-card scripts.",
        name="check_card_monster_zone_checks.py",
        new_label="NEW monster-zone check",
        hint="Ask the engine for legal zones instead: EffectHandler.can_play_in_zone /"
             " CardEffect.get_effect_play_zones; the play primitives refuse the"
             " monster's zone (5.11.1.1).")


if __name__ == "__main__":
    sys.exit(main())
