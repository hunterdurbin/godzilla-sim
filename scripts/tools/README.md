# scripts/tools/ — dev & CI check scripts

Not shipped features — run these during development.

| File | What it checks | Run |
|---|---|---|
| `check_designer_contract.gd` | A GameBoard scene satisfies the multiplayer scene contract: root named `GameBoard`, `GameSession` child containing `MultiplayerSync` (required) + `EffectUIRouter` (warning if absent). Exit 0 = pass. | `<godot> --headless --quit --script scripts/tools/check_designer_contract.gd -- res://scenes/board/GameBoard.tscn` (or `-- --all` to scan `scenes/board/`) |
| `check_missing_cards.sh` | Diffs card ids in `scripts/cards/sets/card_set_*.gd` against the live API (`https://api.godzillatcg.com/cards`), reporting missing cards grouped by set. Needs `curl` + `python3`. | `./scripts/tools/check_missing_cards.sh` |

Runtime debug tooling (shipped in debug builds, inert elsewhere):

| File | Role |
|---|---|
| `board_editor.gd` | `BoardEditor` — free-form match-state mutation engine behind the F4 board editor overlay (`scenes/board/overlays/board_editor_overlay.gd`). No rules validation by design; keeps structural invariants (unique `_ed_` instance ids, CardEffect registration for fielded cards, PlayerState signal emission per touched container). Unit suite: `tests/unit/test_board_editor.gd` |

Related codegen (lives with its target, not here):
`scripts/effects/generate_trigger_map.sh` — regenerates trigger_map.gd;
see `scripts/effects/README.md` for its safety rules.
