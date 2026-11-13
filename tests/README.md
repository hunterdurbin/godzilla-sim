# tests/ — all test & dev-harness code

Three tiers, all runnable headlessly. Godot binary below = your Godot 4.6
binary (e.g. `/Users/hunterdurbin/Downloads/Godot.app/Contents/MacOS/Godot`).

| Tier | Where | What it proves | Run |
|---|---|---|---|
| **Unit** (gdUnit4) | `unit/` + `fixtures/` | Core rules, effects, bot decisions — pure-logic correctness | `./tests/run_unit_tests.sh <godot> [path] [--verbose]` |
| **Harness** (integration) | `harness/` | Dedicated server + 2 headless clients stay in sync (no DESYNC / SCRIPT ERROR) | `./tests/harness/run_harness.sh 3 <godot>` |
| **Sim** (behavioral) | `sim/` | Bot-vs-bot self-play; seed-matched `[SimResult]` diffs detect behavior drift between branches | `./tests/sim/run_sim_diff.sh <godot> [base_ref] …` |

Plus `ui/` — one-off headful geometry/debug scenes (not part of any gate).

CI (`.github/workflows/tests.yml` on every PR and push to main, plus
`release.yml` on tags) runs `tests/run_unit_tests.sh`; do not move or rename
that script. It prints a digest (failure reports, SCRIPT/Parse errors,
summary) and the full-log path; pass a suite file as `[path]` for one suite.
It kills the headless run once gdUnit reports, so it never wedges.

## Layout

```
tests/
├── run_unit_tests.sh    # headless gdUnit4 runner (also used by CI)
├── unit/                # suites: core/, effects/ (+ effects/cards/), input/, …
├── fixtures/            # cards.gd (hand-built dicts), real_cards.gd, states
├── harness/             # multiplayer integration harness — see harness/README.md
├── sim/                 # bot self-play simulation — see sim/README.md
└── ui/                  # ChoicePanelGeometryTest.tscn + script
```

## Fixture policy

- **Core/rules tests** build card Dictionaries by hand via
  `fixtures/cards.gd` — no CardData dependency, so pure-logic suites run
  without the card database.
- **Per-card effect tests** use `fixtures/real_cards.gd`
  (`Real.instance(id)`) — real card dicts, never raw CardData templates.
  Cluster/bespoke membership ledger: `unit/effects/cards/classification.md`.
- Synthetic effects (no script file on disk):
  `handler.registry.register_for_test("test://name", effect, ["on_enter", …])`
  — see `unit/effects/test_check_timing.gd`.
- Player decisions in tests are scripted with `ScriptedPlayerInput`
  (`scripts/core/input/`) — queue answers, resolve synchronously.
- New/changed card effects require updated tests; the smoke suite fails if
  `scripts/effects/trigger_map.gd` is stale.

Each test run writes an HTML report to git-ignored `reports/report_N/`.
