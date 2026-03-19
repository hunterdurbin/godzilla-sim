class_name ReplayRecorder
extends RefCounted

## Records state snapshots during gameplay for replay viewing.
## Captures a snapshot on every board state change (debounced per-frame)
## so the viewer can step through each interaction.
## Boundary snapshots are captured synchronously when a sub-phase starts,
## before any effects modify state. Only boundary snapshots allow "Play From Here".
##
## Runs on the host side only. In multiplayer, the host sends the finished
## replay to the client via RPC at game end so both players get a full copy.

var _replay: ReplayData
var _game_state: GameState
var _pending_logs: PackedStringArray = []
var _snapshot_pending: bool = false  # Debounce flag — at most one snapshot per frame
var _scene_tree: SceneTree  # Needed for deferred frame callback


func start(game_state: GameState, seed_val: int, mode: String, bot_difficulty: String, deck_names: Array[String], scene_tree: SceneTree) -> void:
	_game_state = game_state
	_scene_tree = scene_tree
	_replay = ReplayData.new()
	_replay.game_version = ProjectSettings.get_setting("application/config/version", "")
	_replay.timestamp = Time.get_datetime_string_from_system(false, true).replace("T", " ")
	_replay.game_seed = seed_val
	_replay.mode = mode
	_replay.bot_difficulty = bot_difficulty
	_replay.deck_names = deck_names
	_replay.player_names = game_state.player_names.duplicate()


func on_state_changed() -> void:
	## Called from game_board._on_state_changed(). Debounces to one snapshot per
	## frame so a single game action that fires multiple signals (hand_changed +
	## deck_changed, etc.) produces only one snapshot.
	if _snapshot_pending:
		return
	_snapshot_pending = true
	_scene_tree.process_frame.connect(_capture_snapshot, CONNECT_ONE_SHOT)


func on_log_message(text: String) -> void:
	_pending_logs.append(text)


func on_phase_boundary(_sub_index: int) -> void:
	## Capture an immediate boundary snapshot when a sub-phase starts,
	## before any effects run. These are the only snapshots that allow
	## "Play From Here" since there are no pending effects in the queue.
	_do_capture(true)


func _capture_snapshot() -> void:
	_snapshot_pending = false
	_do_capture(false)


func _do_capture(is_boundary: bool) -> void:
	var snap := {
		"turn_number": _game_state.turn_number,
		"current_player_id": _game_state.current_player_id,
		"phase": int(_game_state.current_phase),
		"sub_phase": _game_state.current_sub_phase,
		"is_boundary": is_boundary,
		"players": [
			GameSerializer.serialize_player_state(_game_state.players[0]),
			GameSerializer.serialize_player_state(_game_state.players[1]),
		],
		"log_lines": Array(_pending_logs),
	}
	_pending_logs = []
	_replay.snapshots.append(snap)


func finish(winner_id: int, reason: String, first_player_id: int) -> ReplayData:
	# Flush any pending snapshot
	if _snapshot_pending:
		_snapshot_pending = false
		_capture_snapshot()

	# Capture a final snapshot with any remaining logs
	_do_capture(false)

	_replay.winner_id = winner_id
	_replay.win_reason = reason
	_replay.first_player_id = first_player_id
	_replay.total_turns = _game_state.turn_number
	_replay.player_names = _game_state.player_names.duplicate()
	return _replay


func save() -> String:
	var ver := ReplayData._get_game_version()
	var fname := "replay_%s.json" % _replay.timestamp.replace(" ", "_").replace(":", "").replace("-", "")
	var path := ReplayData.get_version_recent_dir(ver) + fname
	var err := ReplayData.save_to_file(_replay, path)
	if err != OK:
		push_warning("ReplayRecorder: Failed to save replay to %s (error %d)" % [path, err])
		return ""
	print("[Replay] Saved to %s (%d snapshots)" % [path, _replay.snapshots.size()])
	ReplayData.prune_recent(ver)
	return path
