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
For card-script changes, `./tests/sim/decks_with_cards.sh <card_id>...` ranks
the decklists by how many of those cards they run — pass the top names as
deck1/deck2. An identical diff on decks that never draw the changed cards
proves only "no regression", not the new behaviour — so the diff measures it:
the runner ends with a `[SimEffects] <card_id>=<n> …` line (abilities that
started resolving, live games only, via `GameEvents.effect_resolving`), and
`run_sim_diff.sh` prints base → head counts for every card script that
differs from `base_ref`. A changed card at 0 on this tree is **UNEXERCISED**
and the script exits 2 (when otherwise clean): re-run on decks that play it.
Passive-only cards (modifiers, replacement queries) never resolve and always
read 0; a base older than the event shows `?`.

**KAIJU replay parity**: run with a KAIJU side and compare `kaiju_diverged`
— the planner's cached plan stopped matching the live game. It must not rise
above the base.

Ad hoc runs take the same args after `--` (they override the scene exports):
`<godot> --headless --path . res://tests/sim/BotSimulationRunner.tscn -- --games=20 --seed=7 --p2=KAIJU --deck2="King Ghidorah"`

Caveats: bot code must consume the global RNG in identical order for diffs
to be meaningful (see `docs/restructure/conventions.md` → RNG rule). The
`ObjectDB instances leaked` warning at exit is pre-existing noise.
