# Phase 0 — Plan docs + baselines

**Goal:** make the restructure resumable by any agent (these docs) and capture
the behavioral baselines every later gate diffs against. No code moves.

## Steps

- [x] Create `docs/restructure/` (this directory): README.md, STATE.md,
      conventions.md, phase-0 … phase-9 files, `baselines/`.
- [x] Run baseline unit tests:
      `./tests/run_unit_tests.sh /Users/hunterdurbin/Downloads/Godot.app/Contents/MacOS/Godot`
      → record total case count + PASS in STATE.md.
- [x] Pin sim seed **locally** in `scenes/simulation/BotSimulationRunner.tscn`
      (`num_games = 50`, `base_seed = 424242`), run
      `Godot --headless --path . res://scenes/simulation/BotSimulationRunner.tscn`,
      save full output to `docs/restructure/baselines/sim_baseline.txt`
      (this file IS committed).
- [x] Re-run the sim identically and diff `[SimResult]` lines to prove the
      pinned seed is deterministic (empty diff required — otherwise the sim
      gate is void and STATE.md must say so).
- [x] Revert the .tscn seed pin (`git checkout -- scenes/simulation/BotSimulationRunner.tscn`)
      before committing.
- [x] Run baseline multiplayer harness:
      `./scenes/server/tests/run_harness.sh 3 <godot>` → no DESYNC / SCRIPT
      ERROR; record in STATE.md.
- [x] Record baseline commit SHA (`git rev-parse HEAD`) in STATE.md.
- [x] Commit: `restructure(phase-0): plan docs + baselines`.

## Done criteria

- All 13 plan files + `baselines/sim_baseline.txt` committed.
- STATE.md holds: unit-test count, sim seed/games + determinism verdict,
  harness verdict, baseline SHA.
- Working tree clean; `BotSimulationRunner.tscn` unmodified in the commit.
