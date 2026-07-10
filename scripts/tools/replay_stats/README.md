# scripts/tools/replay_stats/ — replay-analysis tuning loop

Turns replay JSONs into per-turn / per-phase (early/mid/late) tempo,
threat-swing, and card-advantage reports, designed for an AI agent to read
and propose `BotConfig` weight adjustments for the KAIJU planner.

## Run

```bash
<godot> --headless --path . res://scripts/tools/replay_stats/ReplayStats.tscn \
    -- --in user://replays/sim --out user://replay_reports --tag kaiju_v1
```

- `--in` — a replay JSON file or a directory of them. Defaults to
  `user://replays/sim/` (the sim runner's output; live-match replays under
  `user://replays/<version>/recent/` work too — same format).
- `--out` / `--tag` — writes `report_<tag>.json` + `report_<tag>.md`.

It is a scene-run tool (not `--script`) because rehydrating card ids needs
the `CardData` autoload.

## The tuning loop

1. Record self-play data: set `record_replays = true` on the
   `BotSimulationRunner` scene root (with a pinned `base_seed`) and run a
   KAIJU-vs-HARD batch.
2. Run this tool over `user://replays/sim/`.
3. Read `report_<tag>.json`: `aggregate.per_phase.<phase>.<metric>.
   winner_minus_loser` says what winners did more of, per phase; each entry
   in `signals[]` (ranked by |delta|) lists `suggested_knobs` — BotConfig
   paths from the static `knob_map` (e.g. `kaiju_eval_weights.mid.board_cp`).
4. Adjust `kaiju_eval_weights` in `scripts/bot/bot_config.gd`, re-run the
   sim, compare `win_rate` between reports (tag them differently).

## Files

- `replay_metrics.gd` — **ReplayMetrics**, pure static analysis (card lookup
  via injected Callable; unit tests run without autoloads). Game phases use
  `KaijuEvaluator.phase_key` — the same latched high-water-mark definition
  the planner tunes against, so measured stats and weights agree on phase.
- `replay_stats.gd` + `ReplayStats.tscn` — the CLI shell.

Counter events (`counter_succeeded`/`counter_failed` tokens) carry
effect-inclusive `total_cp`/`threat` breakdowns — the only place in a replay
where fully-modified values are available without re-running the engine.
