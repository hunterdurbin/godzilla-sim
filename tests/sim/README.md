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
    [deck1="ESD01 Starter"] [deck2="ESD02 Starter"] [seed=424242] \
    [--pair "deckA|deckB"]...
```

It runs the working tree and a detached, imported worktree of `base_ref`
in parallel (the base gets this tree's `bot_simulation_runner.gd`, so both
run the same harness) and reports differing `[SimResult]` lines, P1 wins,
SCRIPT ERROR counts and `[Kaiju] … plan DIVERGED` counts. Exit 0 = identical;
the last line, `STATUS: <n> (…)`, repeats the verdict so it survives a `| grep`.
`--pair` (repeatable) runs several deck pairs against one base import —
use it instead of separate invocations; deck1/deck2 are then ignored.

**Decks.** A deck is a decklist name (the user's decklists dir) or
`@<path>` to a `.deck` file — relative paths resolve against this repo, so
the base worktree reads the same file. For rules-engine changes pick decks
that exercise them (e.g. "King Ghidorah" carries 3 <Revenge> cards). For
card-script changes, `./tests/sim/decks_with_cards.sh <card_id>...` ranks
the user's decklists and the committed coverage decks by how many of those
cards they run, and ends with `NOT IN ANY DECK: …` for cards nothing plays.
For those, add a coverage deck to `tests/sim/decks/` (`cov_*.deck`, a
`#` header saying which cards it covers and what the opponent must do) —
never a throwaway in the user's decklists dir.

**Coverage.** An identical diff on decks that never draw the changed cards
proves only "no regression", not the new behaviour — so the diff measures
it: the runner ends with a `[SimEffects] <card_id>=<n> …` line (abilities
that started resolving, live games only, via `GameEvents.effect_resolving`;
`scripts/tools/check_effect_resolution_notes.py` keeps every engine site
announcing), and `run_sim_diff.sh` prints base → head counts per pair (and
a total) for every card script that differs from `base_ref`. A changed card
whose head total is 0 is **UNEXERCISED** and the script exits 2 (when
otherwise clean): add a pair that plays it. Passive-only cards (modifiers,
replacement queries) never resolve and always read 0; a base older than the
event shows `?`.

**KAIJU replay parity**: run with a KAIJU side and compare `kaiju_diverged`
— the planner's cached plan stopped matching the live game. It must not rise
above the base.

Ad hoc runs take the same args after `--` (they override the scene exports):
`<godot> --headless --path . res://tests/sim/BotSimulationRunner.tscn -- --games=20 --seed=7 --p2=KAIJU --deck2="King Ghidorah"`

Caveats: bot code must consume the global RNG in identical order for diffs
to be meaningful (see `docs/restructure/conventions.md` → RNG rule). The
`ObjectDB instances leaked` warning at exit is pre-existing noise.
