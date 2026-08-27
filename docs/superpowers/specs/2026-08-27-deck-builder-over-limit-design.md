# Deck builder: over-fill then shave down

**Source:** Discord request "Allow deck list to go beyond 50 cards/10 2-steps"
(Tuscancow, 2026-08-22) — users like to add more cards than allowed, then
shave the deck down to legal. Don't cut them off while adding. (Follow-up
direction from Hunter: saving an illegal deck is fine too — deck-select
already surfaces validation errors when picking a deck for a match.)

## Design

- `_add_to_main_deck` no longer enforces the 50-card main-deck total or the
  10 Step-2 cap. The per-card copy cap (4, or 50 for `unlimited_copies`)
  stays — over-adding copies of one card isn't part of the shave-down
  workflow, and the pool badges grey out at max.
- Deck stats: main-deck count turns red when over 50 (green at exactly 50,
  yellow below), matching the existing red Step-2 over-limit color. The
  validation panel already lists the over-limit errors via `DeckValidator`.
- Save is untouched: illegal decks (over- or under-limit) save normally.
  Deck-select / lobby flows already flag invalid decks via
  `DecklistManager.validate_decklist` / `is_decklist_valid_for_mode`.
- Side fix: `_move_monster_to_main` used to silently drop a monster moved
  into a full main deck (remove succeeded, add was refused). With the
  add-time cap gone, the card lands in the main deck instead.

## Not doing

- No hard ceiling above 50 — the copy cap bounds growth naturally.
- No save gating at all — legality is a deck-select-time concern.

## Tests

`tests/unit/test_deck_builder_limits.gd` — overflow past 50, Step-2 past
10, copy cap still enforced, over-limit deck saves and then reports
validation errors via `DecklistManager.validate_decklist`. Runtime smoke:
`tests/ui/DeckBuilderPadNavTest.tscn` (known pre-existing param-row
failure only).
