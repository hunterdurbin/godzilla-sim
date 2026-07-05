# Restructure STATE — single source of truth

**Read this first when resuming.** Then open the current phase file.
Update this file immediately on any deviation, and paste gate results here
BEFORE each commit.

## Current position

- **Status:** ✅ **COMPLETE** — all 10 phases done (2026-07-05), follow-ups resolved same day
- **Follow-up outcomes (user approved "do what makes sense"):**
  - `.editorconfig`: DONE — indent rules added (gd=tabs, py/sh=4-space,
    yml=2-space, final newline). Editor-applied on touched files only; no
    reformat sweep.
  - gdlint/gdformat config: SKIPPED — gdtoolkit is not installed here and
    nothing runs it in CI; a config would be dead weight. Revisit if the
    toolchain ever adopts it.
  - `RpcLogger`: DEMOTED — now a static class (`class_name RpcLogger extends
    Object`, static vars/funcs); autoload removed (10 remain). Zero call-site
    changes; harness PASS confirms the live RPC logging paths.
  - `TouchHelper`: KEPT as autoload deliberately — needs tree membership for
    `_input` touch/mouse tracking and the Android back-button notification.
    Rationale recorded in scripts/README.md.
  - 8a `_execute_rematch`: remains board-owned by design (unchanged).
- **Path flip in effect:** sim = `res://tests/sim/BotSimulationRunner.tscn`,
  harness = `./tests/harness/run_harness.sh` (old scenes/ locations retired)
- **Branch:** `feature/restructure`
- **Baseline commit (pre-restructure):** `7f9fe3ba52ad2943aa71c1b6140a9a8902061cc7`

## Baselines (captured 2026-07-05, Phase 0)

| Baseline | Value |
|---|---|
| Unit tests | **901/901 passed** (41 suites, 0 errors/failures) via `./tests/run_unit_tests.sh <godot>` |
| Sim | 50 games, `base_seed = 424242`, decks ESD01/ESD02 Starter, both HARD — full output in [`baselines/sim_baseline.txt`](baselines/sim_baseline.txt) (50 `[SimResult]` lines) |
| Sim determinism | **VERIFIED** — two identical runs produced byte-identical `[SimResult]` lines, so the sim diff is a valid gate |
| Harness | **PASS** — 3 games (seeds 1001–1003), files-with-desyncs=0, files-with-script-errors=0 |
| Godot binary | `/Users/hunterdurbin/Downloads/Godot.app/Contents/MacOS/Godot` (Godot 4.6; `godot` is a shell alias — use the full path in scripts) |
| Known noise | Unit-test and sim runs end with pre-existing `ObjectDB instances leaked` / `404 resources still in use` warnings — present at baseline, not caused by the restructure. gdUnit writes git-ignored `reports/report_N/` per run. |

Seed-pin procedure: edit `num_games = 50` / `base_seed = 424242` into the
BotSimulationRunner root node in the .tscn, run, then
`git checkout -- <the .tscn>`. **Never commit the pin.**
(Sim scene: `scenes/simulation/BotSimulationRunner.tscn` until Phase 2 moves
it to `tests/sim/BotSimulationRunner.tscn`.)

## Phase status

| Phase | Status | Commit | Gate results |
|---|---|---|---|
| 0 — plan docs + baselines | **done** | (this commit) | unit 901/901 · sim deterministic · harness PASS |
| 1 — cleanup | **done** | (phase-1 commit) | unit 901/901 · headless boot smoke clean · orphan grep: refs only internal to deleted files |
| 2 — test harnesses → tests/ | **done** | (phase-2 commit) | unit 901/901 · sim `[SimResult]` byte-identical · harness PASS (0 desync, 0 script error) · grep sweep zero hits |
| 3 — scripts/ re-slice | **done** | (phase-3 commit) | unit 901/901 · sim `[SimResult]` byte-identical · harness PASS · retired-path sweep zero hits · 16 READMEs added |
| 4 — scenes/ re-slice | **done** | (phase-4 commit) | unit 901/901 · sim byte-identical · harness PASS · sweep zero hits · headful driver loaded all 13 nav targets + rendered MainMenu/GameBoard screenshots |
| 5 — assets/ | **done** | (phase-5 commit) | unit 901/901 · sim byte-identical · harness PASS · sweep zero hits (incl. .import sidecars, null-safe for CJK names) · headful board render + sfx OK |
| 6 — split card_data.gd | **done** | (phase-6 commit) | CARD_TEMPLATES=388 pre & post · regenerated cards.csv byte-identical · unit 901/901 · sim byte-identical · harness PASS. card_database.gd 184 lines + 10 set files |
| 7 — split bot_player.gd (7a–7d) | **done** | 4 sub-commits | each sub-commit: unit 901/901 + sim byte-identical; phase-end harness PASS. bot_player 2,157→1,085 lines; helpers: scoring(9), zone_picker(7), invasion(8), selections(2) methods. Deviation: `_on_*` handler bodies stayed on BotPlayer whole (small, all contain awaits) — only pure sync decision methods moved |
| 8 — split game_board.gd (8a–8f) | **done** | 5 sub-commits (8b–8f) | per sub-commit: contract grep 61=61, unit 901/901, harness PASS; phase-end sim byte-identical + headful zoom/sound/layout/bug-report checks. game_board 3,274→~2,474 lines. Deviations: 8a skipped (rematch already in end_game_controller pre-restructure; `_execute_rematch` intentionally board-owned); adds `class_name GameBoard`. Headful checks found+fixed module-binding bugs: bare `$Path`/`add_child`/`reparent(self)`/`BugReport.build_body(self)` — see modules/README.md "Extraction lessons" |
| 9 — docs sweep + closeout | **done** | (phase-9 commit) | 31 subsystem READMEs verified present · root README + CLAUDE.md rewritten · global retired-path sweep clean (2 real stragglers fixed: verify-skill Options path, replay-README effectIcons path) · final gate: unit 901/901, harness PASS, sim byte-identical |

## Standing decisions

- Commit-per-phase on `feature/restructure`, message format
  `restructure(phase-N): <summary>` (user approved via plan).
- `scenes/Main.tscn` is approved for deletion in Phase 1 (4th orphan).
- `build/` untouched; `reports/` deleted in Phase 1.
- `scripts/effects/` and `tests/run_unit_tests.sh` are PATH-FROZEN
  (see conventions.md).
- Autoload count stays 11; demotion candidates (RpcLogger, TouchHelper) are
  future work, out of scope.

## Deviations / open issues

- 2026-07-05: Unit-test baseline is 901 cases (older project notes said 818 —
  the suite grew; 901 is authoritative).
- 2026-07-05 (Phase 2→3): the Phase-2 seed-pin revert (`git checkout --`)
  clobbered the UNSTAGED script-path fix in `tests/sim/BotSimulationRunner.tscn`,
  so Phase 2 committed a stale `res://scenes/simulation/…` reference (the
  .tscn has no `uid=` attribute to rescue it). Symptom: sim scene loaded
  scriptless and hung forever. Repaired in Phase 3. Rule added to
  conventions.md: `git add` path fixes BEFORE pinning the seed.
- 2026-07-05 (Phase 3): after out-of-editor moves, headless runs fail with
  `Could not find script for class "X"` until `<godot> --headless --path . --import`
  rebuilds the class-name cache. Added to conventions.md as a required
  post-move step.
- 2026-07-05 (Phase 3): two non-res:// parsers of card_data.gd found and
  fixed (`translations/generate_card_csv.py`, `scripts/tools/check_missing_cards.sh`)
  — both must be updated AGAIN in Phase 6 (noted in phase-6 file).
