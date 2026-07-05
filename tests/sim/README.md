# tests/sim/ — bot self-play simulation

Runs N bot-vs-bot games headlessly and prints per-game `[SimResult]` lines
plus summary stats. Two uses: bot-strength tuning, and **seed-matched
behavioral diffing** — proving a refactor changed no bot-visible behavior.

```bash
<godot> --headless --path . res://tests/sim/BotSimulationRunner.tscn
```

Scene exports (edit the root node in `BotSimulationRunner.tscn`):
`num_games` (default 200), `p1_difficulty`/`p2_difficulty` (default HARD),
`p1_deck_name`/`p2_deck_name` (default ESD01/ESD02 Starter), `base_seed`
(0 = random; game *i* seeds the global RNG with `base_seed + i`).

## Seed-matched behavioral diff

Determinism is verified: with a pinned seed, `[SimResult]` lines are
byte-identical across runs — so any diff is a real behavior change.

1. Locally edit the .tscn root node: `num_games = 50`, `base_seed = 424242`
   (**never commit this edit** — `git checkout -- tests/sim/BotSimulationRunner.tscn` after).
2. Run, capture: `... > /tmp/sim_now.txt 2>&1`
3. Diff against the committed baseline:
   ```bash
   grep '\[SimResult\]' docs/restructure/baselines/sim_baseline.txt > /tmp/a.txt
   grep '\[SimResult\]' /tmp/sim_now.txt > /tmp/b.txt
   diff /tmp/a.txt /tmp/b.txt   # empty = no behavior change
   ```
   (For branch-vs-branch comparisons, capture your own baseline on the base
   branch with the same seed instead.)

Caveats: bot code must consume the global RNG in identical order for diffs
to be meaningful (see `docs/restructure/conventions.md` → RNG rule). The
`ObjectDB instances leaked` warning at exit is pre-existing noise.
