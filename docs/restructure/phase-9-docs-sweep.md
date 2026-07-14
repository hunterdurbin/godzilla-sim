# Phase 9 — Documentation sweep + closeout

**Goal:** every subsystem directory has its README; root README.md and
CLAUDE.md reflect the new reality; final verification; STATE.md closed out.

## Full documentation checklist (~30 files)

Earlier phases write docs for the trees they touch; this phase writes
whatever is still missing and rewrites the roots. Content specs:

| File | Content | Written in |
|---|---|---|
| `README.md` (rewrite) | Overview, target tree one-line-per-dir, README index, run/test/server commands | 9 |
| `CLAUDE.md` (rewrite) | Purge unfilled template boilerplate (card-design/assets placeholder sections); real architecture; updated commands (`./tests/harness/run_harness.sh`, `res://tests/sim/BotSimulationRunner.tscn`); doc index | 9 |
| `scripts/README.md` | Domain map; **autoload registry table (11: name → path → responsibility)**; layering rules (core/effects never import scenes) | 3 |
| `scripts/core/README.md` | GameState/RulesEngine/TurnManager/MatchFactory/GameEvents; actions/ resolver map; PlayerInput port + ScriptedPlayerInput test seam | 3 |
| `scripts/effects/README.md` | Facade API; per-set index with counts; codegen rules (never run generate_trigger_map.sh during headless runs; METHODS list; smoke staleness gate) | 3 |
| `scripts/cards/README.md` | Card Dictionary schema (incl. effect_script, *_by_printing); set-file layout; "add a card" checklist | 3, finalized 6 |
| `scripts/bot/README.md` | Decision pipeline; file map; sim-diff procedure | 3, finalized 7 |
| `scripts/session/README.md` | GameSession ownership; MultiplayerSync sole @rpc surface; `_board` contract (3 impls) | 3 |
| `scripts/server/README.md` | ServerMain → ConnectionManager → GameRoom → HeadlessBoard topology; deploy pointer | 3 |
| `scripts/net/README.md` | Peer types; NetworkManager scene-change API; RpcLogger; chat filter | 3 |
| `scripts/replay/README.md` | Replay format; recorder lifecycle; serializer save format; log export | 3 |
| `scripts/audio/README.md` | SfxManager/MusicManager API; asset locations; adding a sound | 3 |
| `scripts/services/README.md` | ArtworkDownloader cache (user://); StatsUploader endpoints/opt-out; UpdateChecker; TouchHelper | 3 |
| `scripts/localization/README.md` | loc.gd API; workflow: translations/*.csv + sources → generate_card_csv.py → .translation | 3 |
| `scripts/settings/README.md`, `scripts/util/README.md`, `scripts/tools/README.md` | One-line inventory per file; when to run tools | 3 |
| `scenes/README.md` | Presentation map; FooBar.tscn ↔ foo_bar.gd convention; domain parity table | 4 |
| `scenes/board/README.md` | Board anatomy; forwarding-property idiom; absorbs docs/game-board-architecture.md | 4 |
| `scenes/board/modules/README.md` | Per-module inventory; "add a module" recipe; which _board._x fields each reads | 4, finalized 8 |
| `scenes/board/overlays/README.md` | Overlay inventory + conventions | 4 |
| `scenes/menus/README.md`, `scenes/lobby/README.md`, `scenes/deck_builder/README.md` | Screen-flow diagrams (NetworkManager.change_scene edges) | 4 |
| `tests/README.md`, `tests/harness/README.md`, `tests/sim/README.md` | Three-tier strategy; runner commands; diff procedures | 2 |
| `assets/README.md` | Domain buckets; snake_case rule; icon inventory | 5 |
| `translations/README.md` | CSV → .translation workflow | 3 |
| `docs/README.md` | Index of docs/ incl. graphs regeneration | 5 |
| `comprehensive_rules/README.md` | What the PDF is; how engine rule refs (e.g. 10.4.3) map to it | 3 |

## Steps

- [x] Audit: `find . -name README.md -not -path './build/*' -not -path './.godot/*' -not -path './addons/*'`
      vs the table; write the missing ones.
- [x] Rewrite root `README.md` and `CLAUDE.md`.
- [ ] ~~Optional~~ SKIPPED (needs user sign-off): `.editorconfig` GDScript
      indent rules (tabs) + gdlint config — recorded as a follow-up in
      STATE.md.
- [x] Final full gate.
- [x] Global retired-path grep (all must be zero outside docs/restructure/):
      `res://scenes/ui/`, `res://scenes/managers/`, `res://scenes/simulation/`,
      `scenes/server/tests`, `res://data/`, `res://icons/`, `cardBacks`,
      `effectIcons`, `card_data.gd`, every Phase-3 moved filename at its old
      `res://scripts/<name>.gd` path.
- [x] Close out STATE.md: all phases done, final gate results, final SHA.
- [x] Commit: `restructure(phase-9): documentation sweep + closeout`.
