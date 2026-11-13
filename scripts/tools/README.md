# scripts/tools/ — dev & CI check scripts

Not shipped features — run these during development.

The `check_*.py` ratchets share `gd_ratchet.py`: allow-list keys are
`<file>: <code>` (no line numbers), one line per occurrence, and a check
fails on a NEW hit and on a STALE allow-list line, so the lists only shrink.
`--update` rewrites a list from the tree; additions need a reason in the PR.

| File | What it checks | Run |
|---|---|---|
| `check_designer_contract.gd` | A GameBoard scene satisfies the multiplayer scene contract: root named `GameBoard`, `GameSession` child containing `MultiplayerSync` (required) + `EffectUIRouter` (warning if absent). Exit 0 = pass. | `<godot> --headless --quit --script scripts/tools/check_designer_contract.gd -- res://scenes/board/GameBoard.tscn` (or `-- --all` to scan `scenes/board/`) |
| `check_engine_private_calls.py` | Ratchet: no new `x._method(` calls into private methods defined in `scripts/core/` or `scripts/effects/` from other files (call a public engine method instead). Grandfathered occurrences live in `engine_private_calls_allowlist.txt`. Runs in CI (`tests.yml`) and the pre-commit hook. | `python3 scripts/tools/check_engine_private_calls.py` |
| `check_card_monster_zone_checks.py` | Ratchet: per-card scripts (`scripts/effects/<set>/`) don't compare a zone index to the monster's zone index (`monster_zone - 1` or a variable assigned from it) — play-zone legality (5.11.1.1) belongs to the engine. Literal zone-number conditions (`monster_zone == 8`) aren't flagged. Grandfathered occurrences live in `card_monster_zone_checks_allowlist.txt`. Runs in CI (`tests.yml`) and the pre-commit hook. | `python3 scripts/tools/check_card_monster_zone_checks.py` |
| `check_card_mutations.py` | Guard: per-card scripts (`scripts/effects/<set>/`) mutate state only through EffectHandler primitives — no zone / monster-position mutation (`clear_zone(`, `push_zone_card(`, `banish_or_discard(`, `monster_zone` assignment, `zones[...]` writes) and no writes to `hand` / `discard_pile` / `main_deck` / `monster_deck` / `strategy_zones` (reassignment, index assignment, mutating Array method, also through a local alias). Reads are fine. No allow-list. Built-in pattern self-test. Runs in CI (`tests.yml`) and the pre-commit hook. | `python3 scripts/tools/check_card_mutations.py` |
| `check_effect_resolution_notes.py` | Guard: every engine site (`scripts/effects/*.gd`) that awaits a card hook (`effect.on_*(` / `apply_*(` / standby `callback.call()`) calls `note_effect_resolving` just before — it feeds `GameEvents.effect_resolving`, i.e. the bot sim's `[SimEffects]` counts and `run_sim_diff.sh`'s UNEXERCISED verdict. Lambda bodies (standby callbacks, announced by the resolver) and sync replacement hooks are exempt. No allow-list. Runs in CI (`tests.yml`) and the pre-commit hook. | `python3 scripts/tools/check_effect_resolution_notes.py` |
| `check_card_unawaited_coroutines.py` | Guard: per-card scripts call every engine coroutine with `await` (an un-awaited call returns immediately, so the card runs on mid-move). The coroutine set is derived from `effect_handler.gd` / `effect_context.gd` (functions containing `await`). No allow-list. Runs in CI (`tests.yml`) and the pre-commit hook. | `python3 scripts/tools/check_card_unawaited_coroutines.py` |
| `check_missing_cards.sh` | Diffs card ids in `scripts/cards/sets/card_set_*.gd` against the live API (`https://api.godzillatcg.com/cards`), reporting missing cards grouped by set. Needs `curl` + `python3`. | `./scripts/tools/check_missing_cards.sh` |

Runtime debug tooling (shipped in debug builds, inert elsewhere):

| File | Role |
|---|---|
| `board_editor.gd` | `BoardEditor` — free-form match-state mutation engine behind the F4 board editor overlay (`scenes/board/overlays/board_editor_overlay.gd`). No rules validation by design; keeps structural invariants (unique `_ed_` instance ids, CardEffect registration for fielded cards, PlayerState signal emission per touched container). Unit suite: `tests/unit/test_board_editor.gd` |

Related codegen (lives with its target, not here):
`scripts/effects/generate_trigger_map.sh` — regenerates trigger_map.gd;
see `scripts/effects/README.md` for its safety rules.
