# scripts/tools/ — dev & CI check scripts

Not shipped features — run these during development.

| File | What it checks | Run |
|---|---|---|
| `check_designer_contract.gd` | A GameBoard scene satisfies the multiplayer scene contract: root named `GameBoard`, `GameSession` child containing `MultiplayerSync` (required) + `EffectUIRouter` (warning if absent). Exit 0 = pass. | `<godot> --headless --quit --script scripts/tools/check_designer_contract.gd -- res://scenes/board/GameBoard.tscn` (or `-- --all` to scan `scenes/board/`) |
| `check_engine_private_calls.py` | Ratchet: no new `x._method(` calls into private methods defined in `scripts/core/` or `scripts/effects/` from other files (call a public engine method instead). Grandfathered keys live in `engine_private_calls_allowlist.txt`; new OR stale keys fail. Runs in CI (`tests.yml`) and the pre-commit hook. | `python3 scripts/tools/check_engine_private_calls.py` |
| `check_card_monster_zone_checks.py` | Ratchet: per-card scripts (`scripts/effects/<set>/`) don't compare a zone index to the monster's zone index (`monster_zone - 1` or a variable assigned from it) — play-zone legality (5.11.1.1) belongs to the engine. Literal zone-number conditions (`monster_zone == 8`) aren't flagged. Grandfathered keys live in `card_monster_zone_checks_allowlist.txt`; new OR stale keys fail. Runs in CI (`tests.yml`) and the pre-commit hook. | `python3 scripts/tools/check_card_monster_zone_checks.py` |
| `check_missing_cards.sh` | Diffs card ids in `scripts/cards/sets/card_set_*.gd` against the live API (`https://api.godzillatcg.com/cards`), reporting missing cards grouped by set. Needs `curl` + `python3`. | `./scripts/tools/check_missing_cards.sh` |

Runtime debug tooling (shipped in debug builds, inert elsewhere):

| File | Role |
|---|---|
| `board_editor.gd` | `BoardEditor` — free-form match-state mutation engine behind the F4 board editor overlay (`scenes/board/overlays/board_editor_overlay.gd`). No rules validation by design; keeps structural invariants (unique `_ed_` instance ids, CardEffect registration for fielded cards, PlayerState signal emission per touched container). Unit suite: `tests/unit/test_board_editor.gd` |

Related codegen (lives with its target, not here):
`scripts/effects/generate_trigger_map.sh` — regenerates trigger_map.gd;
see `scripts/effects/README.md` for its safety rules.
