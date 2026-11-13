# tests/sim/ — bot self-play simulation

Runs N bot-vs-bot games headlessly and prints per-game `[SimResult]` lines
plus summary stats. Two uses: bot-strength tuning, and **seed-matched
behavioral diffing** — proving a refactor changed no bot-visible behavior.

```bash
<godot> --headless --path . res://tests/sim/BotSimulationRunner.tscn
```

Scene exports (overridable per run with `-- --games= --seed= --p1= --p2= --deck1= --deck2=`):
`num_games` (default 200), `p1_difficulty`/`p2_difficulty` (default HARD),
`p1_deck_name`/`p2_deck_name` (default ESD01/ESD02 Starter), `base_seed`
(0 = random; game *i* seeds the global RNG with `base_seed + i`).

## Seed-matched behavioral diff

Determinism is verified: with a pinned seed, `[SimResult]` lines are
byte-identical across runs — so any diff is a real behavior change.

```bash
./tests/sim/run_sim_diff.sh <godot> [base_ref=main] [games=50] [p1=HARD] [p2=HARD] \
    [deck1="ESD01 Starter"] [deck2="ESD02 Starter"] [seed=424242]
```

It runs the working tree and a detached, imported worktree of `base_ref`
in parallel (the base gets this tree's `bot_simulation_runner.gd`, so both
run the same harness) and reports differing `[SimResult]` lines, P1 wins,
SCRIPT ERROR counts and `[Kaiju] … plan DIVERGED` counts. Exit 0 = identical.
Decks resolve from the user decklists dir; for rules-engine changes pick a
deck that exercises them (e.g. "King Ghidorah" carries 3 <Revenge> cards).

**KAIJU replay parity**: run with a KAIJU side and compare `kaiju_diverged`
— the planner's cached plan stopped matching the live game. It must not rise
above the base.

Ad hoc runs take the same args after `--` (they override the scene exports):
`<godot> --headless --path . res://tests/sim/BotSimulationRunner.tscn -- --games=20 --seed=7 --p2=KAIJU --deck2="King Ghidorah"`

Caveats: bot code must consume the global RNG in identical order for diffs
to be meaningful (see `docs/restructure/conventions.md` → RNG rule). The
`ObjectDB instances leaked` warning at exit is pre-existing noise.
