# Phase 2 — Consolidate test harnesses under tests/

**Goal:** all test/dev harness code lives under `tests/` (currently spread
across 4 locations). Bonus: export presets exclude `tests/*`, so dev scenes
stop shipping in builds.

## Moves (git mv, always with `.uid` twins)

- [ ] `git mv scenes/server/tests tests/harness`
      (run_harness.sh, run_concurrency.sh, HeadlessTestClient.tscn,
      headless_test_client.gd, stub_client_board.gd, RealClientSmoke.tscn,
      real_client_smoke.gd, BranchRpcSpike.tscn, branch_rpc_spike.gd,
      spike_sync.gd, …)
- [ ] `git mv scenes/simulation tests/sim`
      (BotSimulationRunner.tscn, bot_simulation_runner.gd)
- [ ] `mkdir tests/ui` then
      `git mv scenes/board/tests/ChoicePanelGeometryTest.tscn tests/ui/` and
      `git mv scripts/tools/choice_panel_geometry_test.gd{,.uid} tests/ui/`;
      remove now-empty `scenes/board/tests/`.

## Path-literal fixes (grep each; the known ones)

- [ ] `tests/harness/run_harness.sh` + `run_concurrency.sh`: scene-path args
      and usage comments (`scenes/server/tests/…` → `tests/harness/…`;
      `scenes/server/ServerMain.tscn` is unchanged).
- [ ] `tests/harness/headless_test_client.gd`:
      `preload("res://scenes/server/tests/stub_client_board.gd")` →
      `res://tests/harness/stub_client_board.gd`.
- [ ] `tests/harness/branch_rpc_spike.gd`: spike_sync preload + doc comments.
- [ ] `tests/harness/real_client_smoke.gd`: comments.
- [ ] `tests/sim/bot_simulation_runner.gd`: usage comment (line ~4).
- [ ] `tests/ui/ChoicePanelGeometryTest.tscn`: ext_resource `path=` fallback
      to the moved script.
- [ ] Docs/config referencing old paths: `CLAUDE.md`,
      `.claude/skills/verify/SKILL.md`, `.claude/settings.local.json`
      (permission patterns), any `docs/*.md`.

## Grep sweep (zero hits required)

```bash
grep -rn 'scenes/server/tests\|scenes/simulation\|scenes/board/tests\|choice_panel_geometry_test' . \
  --include='*.gd' --include='*.tscn' --include='*.cfg' --include='*.sh' \
  --include='*.yml' --include='*.md' --include='project.godot' \
  --exclude-dir=build --exclude-dir=.godot --exclude-dir=.git \
  --exclude-dir=restructure
grep -rn 'scenes/server/tests\|scenes/simulation' .claude/
```

## Docs to write this phase

- `tests/README.md` — three-tier strategy (unit / harness / sim), fixtures
  policy (real_cards vs hand-built dicts), all runner commands.
- `tests/harness/README.md` — run_harness.sh / run_concurrency.sh usage,
  DESYNC / SCRIPT-ERROR grep contract, ports, log locations.
- `tests/sim/README.md` — seed-matched behavioral-diff procedure (pin
  base_seed locally, capture `[SimResult]`, diff vs
  docs/restructure/baselines/sim_baseline.txt).

## Gate (full — note the NEW paths)

- Unit tests at baseline count.
- Sim: `res://tests/sim/BotSimulationRunner.tscn` (pin seed locally first) —
  `[SimResult]` byte-identical to baseline; revert pin.
- Harness: `./tests/harness/run_harness.sh 3 <godot>` — no DESYNC / SCRIPT
  ERROR.
- Grep sweep above → zero hits.
- Update conventions.md gate snippets are already written for post-Phase-2
  paths; STATE.md notes the path flip.

## Commit

`restructure(phase-2): consolidate test harnesses under tests/`
