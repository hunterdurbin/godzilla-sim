# scripts/cards/ — card database & deck logic

## Files

| File | Role |
|---|---|
| `card_data.gd` | **Autoload `CardData`** — the card template database (~277 cards). Public surface: `CARD_TEMPLATES`, `get_card_by_id()`, `get_main_deck()`, `get_monster_deck()`, `get_esd01_main_deck()`, printing helpers. (Planned: per-set split into `sets/` — see `docs/restructure/phase-6-split-card-data.md`) |
| `card_enums.gd` | `CardEnums` — all card-related enums (colors, types, traits, …) |
| `deck_validator.gd` | `DeckValidator` — static deck-legality checks (50-card main, 4-monster rank 1–4, copy limits, ≤10 invade-2 cards, resonance); returns translation-key errors |
| `decklist_manager.gd` | **Autoload `DecklistManager`** — `.deck` files under `user://decklists/` (subfolders = folders), per-player deck selection, build/preview/validate |
| `decklog_importer.gd` | `DecklogImporter` — imports decks from Bushiroad Deck Log (EN/JP endpoints); strips `+`/`++` alt-art suffixes, prepends `E` |
| `game_mode_validator.gd` | `GameModeValidator` — game modes (rumble_west, rumble_east, no_rules, bulkzilla) and per-mode pool/restriction validation |
| `pools/bulkzilla_card_pool.gd` | `BulkzillaCardPool` — static allow-list spliced into the BULKZILLA format |
| `pools/card_artwork_fix_pool.gd` | `CardArtworkFixPool` — per-release artwork cache-invalidation entries consumed by `ArtworkDownloader.apply_fix_pool()` |

## Card Dictionary schema (the important keys)

Cards are plain Dictionaries, never Resources. Template keys include `id`
(base id, e.g. `EBP04-067`), `name`, `description`, `type`, `color`, `rank`,
`cp`, `traits`, `effect_script` (**`res://scripts/effects/…` — path-frozen**),
`*_by_printing` variants, and mode/printing metadata. In-game copies get
per-copy instance ids (`EBP04-067_0_3`) — compare with
`CardUtils.base_id(card)`.

Multiplayer JSON caveat: int enums arrive as floats on clients (deck-search
picks etc.) — re-map to the canonical dict by id, don't trust field types.

## Adding a card (checklist)

1. Add the template dict to `card_data.gd` (correct set array).
2. Write its effect script under `scripts/effects/<set>/` (see
   `scripts/effects/README.md`) and set `effect_script` in the template.
3. Regenerate trigger_map (pre-commit hook does it; never while a headless
   run is live).
4. Cover it in `tests/unit/effects/cards/` (smoke picks it up automatically;
   add cluster/bespoke coverage per `classification.md`).
5. If translated, add `CARD_<id>_NAME`/`_DESC` rows —
   `translations/generate_card_csv.py` regenerates `cards.csv` from
   card_data + JP source files.

## External parsers (update if card_data.gd layout changes)

- `translations/generate_card_csv.py` (regex-parses the template dicts)
- `scripts/tools/check_missing_cards.sh` (greps `"id":` lines; compares vs
  the live API)
