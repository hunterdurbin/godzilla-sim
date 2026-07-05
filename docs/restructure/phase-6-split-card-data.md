# Phase 6 — Split god file #1: card_data.gd (~4,800 lines)

**Goal:** the monolithic card database becomes 10 per-set data files behind an
unchanged autoload surface. Lowest-risk split — do it first.

## Verified preconditions (from planning; re-verify cheaply)

- The per-set arrays (`EBP01_CARDS` … `SYSTEM_CARDS`) are **private**: no file
  outside card_data.gd references them
  (`grep -rn 'EBP01_CARDS\|SYSTEM_CARDS' --include='*.gd' | grep -v card_data`).
- External consumers use only `CardData.CARD_TEMPLATES`, `get_card_by_id`,
  `get_main_deck`, `get_monster_deck`, `get_esd01_main_deck`, printing
  helpers → **zero caller changes**.
- The `"effect_script": "res://scripts/effects/…"` strings inside the arrays
  must survive **byte-for-byte** (trigger_map.gd parity).

## Target decomposition (all in `scripts/cards/`, post-Phase-3 location)

- [ ] `sets/card_set_ebp01.gd` … `sets/card_set_ebp04.gd`,
      `sets/card_set_epr.gd`, `sets/card_set_esd01.gd`,
      `sets/card_set_esd02.gd`, `sets/card_set_esc01.gd`,
      `sets/card_set_efc01.gd`, `sets/card_set_system.gd` — each:

      ```gdscript
      extends RefCounted
      ## <SET> card definitions. Data only — no logic.

      static func cards() -> Array[Dictionary]:
          return [ …array literal moved verbatim from card_data.gd… ]
      ```

      (Statics avoid autoload-order issues; CardEnums references inside the
      literals keep working via class_name. Adjust set list to whatever
      arrays actually exist in the file — enumerate them first with
      `grep -n '^const .*_CARDS' card_data.gd`.)
- [ ] `card_database.gd` — rename of the remaining card_data.gd. Keeps:
      `CARD_TEMPLATES`, `_build_card_templates()` now iterating
      `const _SETS := [preload("sets/card_set_ebp01.gd"), …]`, every existing
      public method. Rewire `get_esd01_main_deck`'s direct array reference to
      the set class. **Autoload NAME stays `CardData`.**
- [ ] `project.godot`: `CardData="*res://scripts/cards/card_database.gd"`.
- [ ] `tests/fixtures/real_cards.gd` keeps working via the autoload — verify,
      don't touch.

## Invariants to check

- [ ] `CARD_TEMPLATES.size()` identical pre/post (print it in a scratch run
      before and after, or add a temporary assertion in a scratch script —
      do not commit scratch).
- [ ] Effect smoke suite passes (it loads every card + effect script and
      fails on trigger_map staleness).
- [ ] `grep -rn 'card_data.gd' --exclude-dir=docs` → zero hits (uid sidecar
      renamed too).

## External parsers of card_data.gd (found in Phase 3 — MUST update here)

- `translations/generate_card_csv.py` — `CARD_DATA_GD = REPO / "scripts" / "cards" / "card_data.gd"`
  regex-parses the card dicts. After the split, point it at
  `scripts/cards/sets/*.gd` (glob all set files) and verify
  `python3 translations/generate_card_csv.py` still parses the same card count.
- `scripts/tools/check_missing_cards.sh` — `CARD_DATA="$(dirname "$0")/../cards/card_data.gd"`
  greps `"id":` lines. Point it at the sets dir (e.g. `grep -h '"id":' ../cards/sets/*.gd`).

## Gate (full) + Commit

Standard gate. Commit:
`restructure(phase-6): split card database into per-set data files`
