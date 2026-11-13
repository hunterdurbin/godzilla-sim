#!/usr/bin/env python3
"""List the cards whose effect script overrides a CardEffect hook, with their text.

Answers "which cards does this engine change affect, and what do they say?",
e.g. before changing when a hook fires, or when a rules question depends on
the cards' exact wording. Each card is printed with its id, name, effect script,
description and the qa.txt rulings that name it (Q-numbers).

Usage: python3 scripts/tools/cards_with_hook.py <hook> [<hook> ...]
  <hook>  a CardEffect virtual, e.g. on_battle_card_played, can_be_destroyed
          (see scripts/effects/card_effect.gd for the full list)
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SETS_DIR = os.path.join(ROOT, "scripts", "cards", "sets")
QA = os.path.join(ROOT, "comprehensive_rules", "qa.txt")

FIELD = re.compile(r'^\s*"(id|name|effect_script|description)":\s*"((?:[^"\\]|\\.)*)"', re.M)


def load_cards() -> list[dict]:
    """Parse every set file into dicts holding id/name/effect_script/description."""
    cards: list[dict] = []
    for fname in sorted(os.listdir(SETS_DIR)):
        if not (fname.startswith("card_set_") and fname.endswith(".gd")):
            continue
        with open(os.path.join(SETS_DIR, fname), encoding="utf-8") as f:
            text = f.read()
        current: dict = {}
        for m in FIELD.finditer(text):
            key, value = m.group(1), m.group(2)
            if key == "id":
                if current:
                    cards.append(current)
                current = {}
            current[key] = value.replace("\\n", "\n    ").replace('\\"', '"')
        if current:
            cards.append(current)
    return cards


def load_rulings() -> dict[str, list[str]]:
    """Map card id -> Q-numbers of the qa.txt rulings that tag it."""
    rulings: dict[str, list[str]] = {}
    if not os.path.exists(QA):
        return rulings
    with open(QA, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^(Q\d+) ", line)
            if not m:
                continue
            for card_id in re.findall(r"\[([A-Z0-9]+-\d+) :", line):
                rulings.setdefault(card_id, []).append(m.group(1))
    return rulings


def overrides(script_res_path: str, hook: str) -> bool:
    path = os.path.join(ROOT, script_res_path.removeprefix("res://"))
    if not os.path.exists(path):
        return False
    with open(path, encoding="utf-8") as f:
        return re.search(rf"^func {re.escape(hook)}\(", f.read(), re.M) is not None


def main() -> int:
    hooks = sys.argv[1:]
    if not hooks or hooks[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if hooks else 2
    cards = load_cards()
    rulings = load_rulings()
    for hook in hooks:
        hits = [c for c in cards if c.get("effect_script") and overrides(c["effect_script"], hook)]
        print(f"== {hook}: {len(hits)} card(s)")
        for c in hits:
            qs = rulings.get(c["id"], [])
            print(f"{c['id']}  {c.get('name', '?')}  ({c['effect_script'].removeprefix('res://')})")
            print(f"    {c.get('description', '(no description)')}")
            print(f"    rulings: {', '.join(qs) if qs else 'none'}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
