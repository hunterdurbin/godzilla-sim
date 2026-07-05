# Restructure STATE — single source of truth

**Read this first when resuming.** Then open the current phase file.
Update this file immediately on any deviation, and paste gate results here
BEFORE each commit.

## Current position

- **Current phase:** 1 (Phase 0 complete)
- **Next action:** execute `phase-1-cleanup.md`
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
| 1 — cleanup | pending | | |
| 2 — test harnesses → tests/ | pending | | |
| 3 — scripts/ re-slice | pending | | |
| 4 — scenes/ re-slice | pending | | |
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
- (none else yet)
