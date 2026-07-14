# Restructure Conventions & Rules

Read this once before executing any phase. Phase files assume these rules.

## Target directory tree

The top-level split stays `scripts/` (logic) vs `scenes/` (presentation) —
Godot-idiomatic, and it maps onto the reference project's `src/` vs `scenes/`
layering. Both layers use the **same domain vocabulary**: core, cards,
effects, bot, session, server, net, replay, audio, board, deck, slots, menus,
lobby, deck_builder.

```
scripts/                     # LOGIC LAYER — no scene files
├── README.md                # domain map + autoload registry + layering rules
├── core/                    # unchanged (game_state, rules_engine, turn_manager, …)
├── cards/                   # ← from data/ (data/ dissolves)
│   ├── card_enums.gd
│   ├── card_database.gd     # slim autoload "CardData" (Phase 6 rename of card_data.gd)
│   ├── sets/                # card_set_ebp01.gd … card_set_system.gd (Phase 6)
│   ├── pools/               # bulkzilla_card_pool.gd, card_artwork_fix_pool.gd
│   └── deck_validator.gd, decklist_manager.gd, decklog_importer.gd, game_mode_validator.gd
├── effects/                 # PATH FROZEN — see below
├── bot/                     # bot_player.gd (+ Phase-7 split), bot_combo.gd, bot_combo_shin.gd, bot_config.gd
├── session/                 # unchanged
├── server/                  # unchanged (its test harness moves to tests/harness)
├── net/                     # network_manager.gd, game_server_peer.gd, relay_multiplayer_peer.gd, rpc_logger.gd, chat_filter.gd
├── replay/                  # replay_data.gd, replay_recorder.gd, game_serializer.gd, game_log.gd, game_log_export.gd
├── audio/                   # sfx_manager.gd, music_manager.gd
├── services/                # artwork_downloader.gd, stats_uploader.gd, update_checker.gd, touch_helper.gd
├── localization/            # loc.gd
├── settings/                # game_settings.gd
├── util/                    # bug_report.gd, fuzzy_match.gd
└── tools/                   # check_designer_contract.gd, check_missing_cards.sh

scenes/                      # PRESENTATION LAYER
├── README.md
├── board/                   # GameBoard, PlayerBoard, hud/, overlays/, modules/ (grows in Phase 8)
├── cards/                   # Card.tscn + CardManager.tscn (← scenes/managers/)
├── deck/, slots/            # unchanged
├── menus/                   # ← LoadingScreen (main scene), MainMenu, Options, Extras
├── lobby/                   # ← LanLobby, OnlineLobby, OnlinePlay, PublicLobby
├── deck_builder/            # ← DeckBuilder, DeckSelect, deck_list_view, deck_row, folder_picker_dialog, bot_pool_view
├── replay/                  # ← ReplayViewer
└── server/                  # ServerMain.tscn only

tests/                       # ALL test/dev harnesses (export presets exclude tests/*)
├── run_unit_tests.sh        # PATH FROZEN (CI depends on it)
├── unit/, fixtures/         # unchanged
├── harness/                 # ← scenes/server/tests/
├── sim/                     # ← scenes/simulation/
└── ui/                      # ← ChoicePanelGeometryTest (+ its script from scripts/tools/)

assets/                      # snake_case, domain-sliced
├── audio/{music,sfx}/  cards/backs/  effects/icons/  ui/{buttons,fonts}/
├── icons/                   # app icons + icons/android/ (← root icons/)
└── board/  patreon/  rage/  # unchanged

translations/                # stays at root (project.godot references .translation files)
docs/                        # cross-cutting docs only; subsystem docs live in-dir
comprehensive_rules/         # unchanged
build/                       # UNTOUCHED (1GB git-ignored export artifacts)
```

## Frozen paths (never move/rename these)

| Path | Why |
|---|---|
| `scripts/effects/**` | `card_data.gd` embeds 368 `"effect_script": "res://scripts/effects/…"` strings; generated `trigger_map.gd` embeds the same 368; EffectRegistry loads by these strings; the pre-commit hook and `generate_trigger_map.sh` reference this path. |
| `tests/run_unit_tests.sh` | `.github/workflows/release.yml` invokes it by path. |
| Autoload **names** (all 11) | Code accesses `CardData.`, `NetworkManager.`, etc. Paths may change (with project.godot updated); names never. |
| `@rpc` signatures | All 47 live in `scripts/session/multiplayer_sync.gd`. This restructure changes none of them. |

## Rules

1. **`.uid` twin rule**: every `git mv` of a `.gd`/`.tscn`/asset moves its
   `.uid` / `.import` sidecar in the same commit.
   **After any move phase, run `<godot> --headless --path . --import` once**
   — the global class_name cache in `.godot/` still points at old paths and
   headless runs will otherwise fail with
   `Could not find script for class "X"` (learned in Phase 3).
   **Seed-pin revert hazard**: `git checkout -- <tscn>` reverts to the INDEX
   — if you have unstaged path fixes in that .tscn, `git add` them BEFORE
   pinning the seed, or the checkout silently destroys them (bit us in
   Phase 2: the sim .tscn's script path fix was clobbered and committed
   stale; repaired in Phase 3).
2. **Byte-for-byte body moves**: god-file splits (Phases 6–8) move code
   verbatim. No refactoring, renaming, or "improvements" while moving —
   behavior diffs must stay attributable to structure alone.
3. **RNG order**: bot code paths must make global-RNG calls in an identical
   order (`seed()` is per-game in the sim). Verbatim moves + identical call
   order guarantee this; the seed-matched sim diff enforces it.
4. **`_board` duck-typed contract**: `scripts/session/multiplayer_sync.gd`
   (and session modules) call `_board._rpc_*` / `_board._on_*` / `_board._x`
   fields implemented by THREE boards: `scenes/board/game_board.gd`,
   `tests/harness/stub_client_board.gd` (pre-Phase-2:
   `scenes/server/tests/`), `scripts/server/headless_board.gd`. Any method
   the session layer calls must stay on game_board.gd (thin delegate is fine).
5. **Codegen safety**: NEVER run `scripts/effects/generate_trigger_map.sh`
   while any headless game/harness is running (it rewrites trigger_map.gd
   mid-load). This restructure should never need to run it at all.
6. **Commits**: one commit per phase (sub-commits in Phases 7/8), message
   `restructure(phase-N): <summary>`. Gate results go into STATE.md before
   the commit.

## The verification gate

Run after every phase (phase files note any additions/reductions). Godot
binary: `/Users/hunterdurbin/Downloads/Godot.app/Contents/MacOS/Godot`
(aliased to `godot` in the user's shell; use the full path in scripts).

```bash
GODOT=/Users/hunterdurbin/Downloads/Godot.app/Contents/MacOS/Godot
cd /Users/hunterdurbin/src/godot/example-tcg-game

# ① Unit tests — must match baseline count, 0 failures
./tests/run_unit_tests.sh "$GODOT"

# ② Seed-matched sim diff — [SimResult] lines must be byte-identical to baseline
#    FIRST: locally pin the seed (NEVER COMMIT THIS EDIT) in
#    tests/sim/BotSimulationRunner.tscn (pre-Phase-2: scenes/simulation/…):
#      num_games = 50
#      base_seed = 424242
"$GODOT" --headless --path . res://tests/sim/BotSimulationRunner.tscn > /tmp/sim_now.txt 2>&1
grep '\[SimResult\]' /tmp/sim_now.txt > /tmp/sim_now_results.txt
grep '\[SimResult\]' docs/restructure/baselines/sim_baseline.txt | diff - /tmp/sim_now_results.txt
#    → empty diff required. Then revert the .tscn pin: git checkout -- tests/sim/BotSimulationRunner.tscn

# ③ Multiplayer harness — no DESYNC / SCRIPT ERROR
./tests/harness/run_harness.sh 3 "$GODOT"     # pre-Phase-2: ./scenes/server/tests/run_harness.sh

# ④ Retired-path grep sweep — ZERO hits (build/ and .godot/ excluded)
grep -rn '<each retired path>' . \
  --include='*.gd' --include='*.tscn' --include='*.cfg' --include='*.sh' \
  --include='*.yml' --include='*.md' --include='project.godot' \
  --exclude-dir=build --exclude-dir=.godot --exclude-dir=.git
#    Also sweep .claude/ (settings.local.json, skills/) — plain grep, no --include filter.
```

Baseline values live in [STATE.md](STATE.md). Phases 4/5/8 additionally
require a headful run via the project's `verify` skill (or manual play):
scene-change paths and missing textures fail only at runtime.

## Known hazard checklist (consult per phase)

- Dynamically built paths: `sfx_manager.gd` / `music_manager.gd` build
  `"res://assets/…" + name` strings — greps for full literals miss these.
- `.tscn` `path=` fallbacks: Godot resolves by uid, but fix the textual
  `path="res://…"` in ext_resources anyway (grep catches them).
- `export_presets.cfg` references `res://icons/*.png` (Android) and
  `res://assets/icons/game_icon.png`.
- `.claude/skills/verify/SKILL.md` and `.claude/settings.local.json` embed
  project paths — include in sweeps.
- `githooks/pre-commit` runs trigger-map regeneration when `scripts/effects/`
  changes — no phase touches that tree, so it should never fire.
- gdUnit4 writes `reports/report_N/` on every run — git-ignored; ignore.
- The baseline unit-test run ends with a pre-existing
  `WARNING: ObjectDB instances leaked at exit` + `404 resources still in use`
  — present before the restructure; do not attribute to your changes.
