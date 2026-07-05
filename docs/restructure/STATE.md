# Restructure STATE — single source of truth

**Read this first when resuming.** Then open the current phase file.
Update this file immediately on any deviation, and paste gate results here
BEFORE each commit.

## Current position

- **Current phase:** 5 (Phases 0–4 complete)
- **Next action:** execute `phase-5-assets.md`
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
| 5 — assets/ | pending | | |
| 6 — split card_data.gd | pending | | |
| 7 — split bot_player.gd (7a–7d) | pending | | |
| 8 — split game_board.gd (8a–8f) | pending | | |
| 9 — docs sweep + closeout | pending | | |

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
