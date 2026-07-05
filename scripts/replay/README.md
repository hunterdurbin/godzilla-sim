# scripts/replay/ — replays, saves, game log

The match-record domain: recording games, saving/loading state, and the
structured log both features share.

| File | Role |
|---|---|
| `replay_data.gd` | `ReplayData` — replay model + disk manager: per-turn full-state snapshots + log tokens under `user://replays/<version>/recent|favorites/` (max 50 recent, favorites exempt); `save_to_file`/`load_from_file`/`list_replays`/`toggle_favorite`; static `pending_replay` hands off to the viewer (`scenes/replay/ReplayViewer.tscn`) |
| `replay_recorder.gd` | `ReplayRecorder` — host-side capture: debounced per-frame snapshots + synchronous phase-boundary snapshots; `start()` → `finish(winner…)` → `save()` |
| `game_serializer.gd` | `GameSerializer` — (de)serializes PlayerState/GameState to card-ID dicts, shared by replays AND the save/load feature (`user://saves/<version>/…`, same recent/favorites scheme); `card_to_id`/`id_to_card` via `CardData.get_card_by_id()`; static `pending_load` handoff |
| `game_log.gd` | `GameLog` — structured log tokens (static constructors like `played_battle`, `invaded`, `counter_succeeded`) + locale-aware BBCode `render()` so each client renders the shared log in its own language; also chat BBCode. Loads effect icons from `res://assets/effects/icons/<en\|ja>/…` |
| `game_log_export.gd` | `GameLogExport.export_log()` — dumps the log as plain text to `user://game_logs/game_log_<timestamp>.txt` |

Design note: the log is transmitted as token Dictionaries, not rendered
strings — rendering happens client-side per locale. When adding a log event,
add a token constructor here and a `STR_LOG_*` key in
`translations/strings.csv`.
