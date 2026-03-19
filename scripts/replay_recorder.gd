class_name ReplayRecorder
extends RefCounted

## Records per-turn state snapshots during gameplay for replay viewing.
## Attach to game_board.gd — connect turn_started and log_message signals.

var _replay: ReplayData
var _game_state: GameState
var _current_turn_logs: PackedStringArray = []


func start(game_state: GameState, seed_val: int, mode: String, bot_difficulty: String, deck_names: Array[String]) -> void:
	_game_state = game_state
	_replay = ReplayData.new()
	_replay.timestamp = Time.get_datetime_string_from_system(false, true).replace("T", " ")
	_replay.game_seed = seed_val
	_replay.mode = mode
	_replay.bot_difficulty = bot_difficulty
	_replay.deck_names = deck_names
	_replay.player_names = game_state.player_names.duplicate()


func on_turn_started(_player_id: int) -> void:
	# Flush previous turn's logs into its snapshot (if any)
	if not _replay.snapshots.is_empty() and not _current_turn_logs.is_empty():
		_replay.snapshots[-1]["log_lines"] = Array(_current_turn_logs)
		_current_turn_logs = []

	# Capture snapshot at this turn boundary
	var snap := {
		"turn_number": _game_state.turn_number,
		"current_player_id": _game_state.current_player_id,
		"phase": int(_game_state.current_phase),
		"players": [
			GameSerializer.serialize_player_state(_game_state.players[0]),
			GameSerializer.serialize_player_state(_game_state.players[1]),
		],
		"log_lines": [],
	}
	_replay.snapshots.append(snap)


func on_log_message(text: String) -> void:
	_current_turn_logs.append(text)


func finish(winner_id: int, reason: String, first_player_id: int) -> ReplayData:
	# Flush remaining logs into last snapshot
	if not _replay.snapshots.is_empty() and not _current_turn_logs.is_empty():
		_replay.snapshots[-1]["log_lines"] = Array(_current_turn_logs)
		_current_turn_logs = []

	# Capture a final snapshot showing end-of-game state
	var final_snap := {
		"turn_number": _game_state.turn_number,
		"current_player_id": _game_state.current_player_id,
		"phase": int(_game_state.current_phase),
		"players": [
			GameSerializer.serialize_player_state(_game_state.players[0]),
			GameSerializer.serialize_player_state(_game_state.players[1]),
		],
		"log_lines": [],
	}
	_replay.snapshots.append(final_snap)

	_replay.winner_id = winner_id
	_replay.win_reason = reason
	_replay.first_player_id = first_player_id
	_replay.total_turns = _game_state.turn_number
	_replay.player_names = _game_state.player_names.duplicate()
	return _replay


func save() -> String:
	var fname := "replay_%s.json" % _replay.timestamp.replace(" ", "_").replace(":", "").replace("-", "")
	var path := ReplayData.REPLAY_DIR + fname
	var err := ReplayData.save_to_file(_replay, path)
	if err != OK:
		push_warning("ReplayRecorder: Failed to save replay to %s (error %d)" % [path, err])
		return ""
	print("[Replay] Saved to %s (%d snapshots)" % [path, _replay.snapshots.size()])
	return path
