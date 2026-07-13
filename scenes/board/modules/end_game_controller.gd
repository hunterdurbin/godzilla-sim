class_name EndGameController
extends Node

## Game-end concern: the end panel, concede, rematch negotiation (request /
## deck change / execute / decline RPbodies), stats upload, and the
## client-side replay save. Binds tm.game_ended on session_started
## (idempotent, rematch-safe).
##
## The board-wide rematch RESET (_execute_rematch) stays on game_board.gd —
## it touches selection/drag/overlay state owned by clusters that extract in
## later steps — and is invoked from here.

var _board: Node
var _session: GameSession

var rematch_requested: bool = false
var opponent_rematch_requested: bool = false
var rematch_deck_select: VBoxContainer = null
var rematch_deck_changed: bool = false
var rematch_deck_name: String = ""
var stats_uploaded: bool = false

const REASON_DISCONNECT := "STR_LOG_REASON_OPPONENT_DISCONNECTED"


## A disconnect-reason game end with the opponent still absent means nobody is
## on the other side to accept a rematch — the button would hang at "Waiting".
## When the opponent later reconnects, ReconnectController re-sends game-ended
## with opponent_connected true and the rematch button comes back (its own
## re-show path also runs).
func _rematch_possible(reason_key: String) -> bool:
	return reason_key != REASON_DISCONNECT or NetworkManager.opponent_connected


## Rematch-button + deck-select state shared by the host and client
## game-ended paths.
func _show_rematch_controls(reason_key: String) -> void:
	if _rematch_possible(reason_key):
		_board.btn_rematch.visible = true
		_board.btn_rematch.disabled = false
		_board.btn_rematch.text = tr("STR_GB_REMATCH")
		populate_rematch_deck_select()
	else:
		_board._game_ended_by_disconnect = true
		_board.btn_rematch.visible = false
		rematch_deck_select.visible = false


func _ready() -> void:
	_board = get_parent()
	var session_node := _board.get_node_or_null("GameSession")
	if session_node == null:
		push_error("[EndGameController] No GameSession sibling.")
		return
	_session = session_node
	_session.session_started.connect(_bind_session)


func _bind_session() -> void:
	var tm: TurnManager = _session.turn_manager
	if tm == null:
		return # Client peer: game end arrives via _rpc_receive_game_ended
	if not tm.game_ended.is_connected(on_game_ended):
		tm.game_ended.connect(on_game_ended)


func on_game_ended(winner_id: int, reason_key: String) -> void:
	SfxManager.play("game_win" if winner_id == _board.local_player_id else "game_lose")
	_board._action_pending = false
	_board._game_ended_by_disconnect = false
	_board.hide_ability_banner()
	# Defensive: hide reconnect overlay if game ends normally
	if _board._waiting_for_reconnect:
		_board._waiting_for_reconnect = false
		if _board._reconnect_overlay:
			_board._reconnect_overlay.visible = false
	rematch_requested = false
	opponent_rematch_requested = false
	_board.end_game_panel.visible = true
	var win_label: Label = _board.end_game_panel.get_node_or_null("VBox/WinLabel")
	if win_label:
		var reason_text := GameLog.render_reason(reason_key)
		win_label.text = tr("STR_GB_WINS_FMT").replace("{NAME}", _session.turn_manager.game_state.player_names[winner_id]) + "\n" + reason_text
	_show_rematch_controls(reason_key)
	_board._disable_all_buttons()
	if _board.is_multiplayer_game and NetworkManager.is_host():
		# Flush any buffered logs before game end
		if not _board._pending_log_tokens.is_empty():
			_board._broadcast_state()
			_board._flush_broadcast()
		RpcLogger.log_send("receive_game_ended", 4 + reason_key.length())
		_board._sync._rpc_receive_game_ended.rpc(winner_id, reason_key)
	# Save replay (host)
	if _session.replay_recorder:
		_session.replay_recorder.finish(winner_id, reason_key, _board._first_player_id)
		_session.replay_recorder.save()
		# Send replay to client so they get a complete copy
		if _board.is_multiplayer_game and NetworkManager.is_host():
			var replay_json := JSON.stringify(_session.replay_recorder._replay.to_dict())
			var compressed := replay_json.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
			print("[Replay] Sending replay to client (%d bytes compressed)" % compressed.size())
			_board._sync._rpc_receive_replay.rpc(compressed)
	RpcLogger.print_summary()
	upload_stats(winner_id, reason_key, false)


# --- Concede ---

func on_concede_pressed() -> void:
	var loser_id: int = _board.local_player_id
	var winner_id := 1 - loser_id
	if _board.is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("concede", 0)
		_board._sync._rpc_concede.rpc_id(NetworkManager.host_peer_id)
	elif _session.turn_manager:
		_session.turn_manager._on_game_over(winner_id, GameLog.concede_reason_key(loser_id))


func rpc_concede() -> void:
	RpcLogger.log_receive("concede", 0)
	if not NetworkManager.is_host() or not _session.turn_manager:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var loser_id := 1 if sender_id != 1 else 0
	var winner_id := 1 - loser_id
	_session.turn_manager._on_game_over(winner_id, GameLog.concede_reason_key(loser_id))


# --- Rematch deck select ---

func setup_rematch_deck_select() -> void:
	var scene := preload("res://scenes/deck_builder/DeckSelect.tscn")
	rematch_deck_select = scene.instantiate()
	rematch_deck_select.persist_key = "rematch_deck"
	# Add as direct child of game board, positioned below Save Game button
	_board.add_child(rematch_deck_select)
	var y_pos := 130.0
	if _board._sys_menu._save_game_button:
		y_pos = _board._sys_menu._save_game_button.position.y + _board._sys_menu._save_game_button.custom_minimum_size.y + 4
	rematch_deck_select.position = Vector2(10, y_pos)
	rematch_deck_select.set_header_visible(false)
	rematch_deck_select.visible = false
	rematch_deck_select.deck_selected.connect(_on_rematch_deck_selected)


func populate_rematch_deck_select() -> void:
	rematch_deck_changed = false
	rematch_deck_name = ""
	rematch_deck_select.set_disabled(false)

	var current_deck := DecklistManager.get_player_deck_name(_board.local_player_id)
	var all_decks := DecklistManager.get_all_decklists()
	var valid_set: Dictionary = {}
	var skip_validation: bool = not _board.is_multiplayer_game
	for deck_name in all_decks:
		if skip_validation:
			valid_set[deck_name] = true
			continue
		var data := DecklistManager.load_decklist(deck_name)
		if data.is_empty():
			continue
		var errors := GameModeValidator.validate(
			NetworkManager.game_mode,
			data.get("monster", []),
			data.get("main", []),
		)
		if errors.is_empty():
			valid_set[deck_name] = true

	if valid_set.size() <= 1:
		rematch_deck_select.visible = false
		return

	rematch_deck_select.set_filter(func(deck_name): return valid_set.has(deck_name))
	rematch_deck_select.refresh()
	if valid_set.has(current_deck):
		rematch_deck_select.select_deck(current_deck)
	rematch_deck_select.visible = true


func _on_rematch_deck_selected(deck_name: String) -> void:
	var current_deck := DecklistManager.get_player_deck_name(_board.local_player_id)
	rematch_deck_changed = deck_name != current_deck
	rematch_deck_name = deck_name


# --- Rematch negotiation ---

func on_rematch_pressed() -> void:
	if _board._game_ended_by_disconnect:
		return

	# Apply local deck change before rematch
	if rematch_deck_changed and not rematch_deck_name.is_empty():
		DecklistManager.select_deck_for_player(_board.local_player_id, rematch_deck_name)

	rematch_requested = true

	if not _board.is_multiplayer_game:
		_board._execute_rematch()
		return

	# Multiplayer: notify opponent, wait for them
	_board.btn_rematch.disabled = true
	_board.btn_rematch.text = tr("STR_GB_WAITING")
	rematch_deck_select.set_disabled(true)

	if rematch_deck_changed and not rematch_deck_name.is_empty():
		# Send deck data so opponent/host can apply it
		var data := DecklistManager.load_decklist(rematch_deck_name)
		var payload := JSON.stringify({
			"deck_name": rematch_deck_name,
			"monster": data.get("monster", []),
			"main": data.get("main", []),
		})
		RpcLogger.log_send("rematch_with_deck", payload.length())
		_board._sync._rpc_rematch_with_deck.rpc(payload)
	else:
		RpcLogger.log_send("rematch_requested", 0)
		_board._sync._rpc_rematch_requested.rpc()

	if opponent_rematch_requested and NetworkManager.is_host():
		_board._execute_rematch()
		RpcLogger.log_send("execute_rematch", 0)
		_board._sync._rpc_execute_rematch.rpc()


## Peer -> Peer: signal that this player wants a rematch
func rpc_rematch_requested() -> void:
	RpcLogger.log_receive("rematch_requested", 0)
	opponent_rematch_requested = true
	_board._on_log_message(GameLog.opponent_wants_rematch(false))

	if rematch_requested and NetworkManager.is_host():
		_board._execute_rematch()
		RpcLogger.log_send("execute_rematch", 0)
		_board._sync._rpc_execute_rematch.rpc()


## Peer -> Peer: rematch request with a changed deck
func rpc_rematch_with_deck(payload_json: String) -> void:
	RpcLogger.log_receive("rematch_with_deck", payload_json.length())
	var json := JSON.new()
	if json.parse(payload_json) != OK:
		push_warning("[Rematch] Failed to parse deck payload")
		return
	var payload: Dictionary = json.data
	var deck_name: String = payload.get("deck_name", "")
	var monster_entries: Array = payload.get("monster", [])
	var main_entries: Array = payload.get("main", [])

	# Validate the deck for the current game mode
	var errors := GameModeValidator.validate(NetworkManager.game_mode, monster_entries, main_entries)
	if not errors.is_empty():
		push_warning("[Rematch] Opponent's deck is invalid for mode '%s': %s" % [NetworkManager.game_mode, str(errors)])
		return

	# Determine sender's player_id from RPC sender peer
	var sender_peer := multiplayer.get_remote_sender_id()
	var sender_pid: int = -1
	for peer_id in NetworkManager.peer_player_map:
		if peer_id == sender_peer:
			sender_pid = NetworkManager.peer_player_map[peer_id]
			break
	if sender_pid == -1:
		push_warning("[Rematch] Could not determine sender player_id")
		return

	DecklistManager.set_player_deck_from_entries(sender_pid, deck_name, monster_entries, main_entries)
	opponent_rematch_requested = true
	_board._on_log_message(GameLog.opponent_wants_rematch(true))

	if rematch_requested and NetworkManager.is_host():
		_board._execute_rematch()
		RpcLogger.log_send("execute_rematch", 0)
		_board._sync._rpc_execute_rematch.rpc()


## Host -> Client: instruct client to execute the rematch reset
func rpc_execute_rematch() -> void:
	RpcLogger.log_receive("execute_rematch", 0)
	if NetworkManager.is_host():
		return
	_board._execute_rematch()


## Peer -> Peer: opponent declined rematch (chose Main Menu)
func rpc_rematch_declined() -> void:
	RpcLogger.log_receive("rematch_declined", 0)
	var win_label: Label = _board.end_game_panel.get_node_or_null("VBox/WinLabel")
	if win_label:
		win_label.text = win_label.text + "\nOpponent returned to menu."
	_board.btn_rematch.visible = false
	rematch_deck_select.visible = false


# --- Client-side game end + replay receive ---

func rpc_receive_game_ended(winner_id: int, reason_key: String) -> void:
	RpcLogger.log_receive("receive_game_ended", 4 + reason_key.length())
	SfxManager.play("game_win" if winner_id == _board.local_player_id else "game_lose")
	_board._action_pending = false
	_board._game_ended_by_disconnect = false
	_board.hide_ability_banner()
	rematch_requested = false
	opponent_rematch_requested = false
	_board.end_game_panel.visible = true
	var win_label: Label = _board.end_game_panel.get_node_or_null("VBox/WinLabel")
	if win_label:
		var reason_text := GameLog.render_reason(reason_key)
		win_label.text = tr("STR_GB_WINS_FMT").replace("{NAME}", GameLog.player_name(winner_id)) + "\n" + reason_text
	_show_rematch_controls(reason_key)
	_board._disable_all_buttons()
	RpcLogger.print_summary()


func rpc_receive_replay(compressed: PackedByteArray) -> void:
	RpcLogger.log_receive("receive_replay", compressed.size())
	var json_bytes := compressed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if json_bytes.is_empty():
		push_warning("[Replay] Failed to decompress replay data")
		return
	var json := JSON.new()
	if json.parse(json_bytes.get_string_from_utf8()) != OK:
		push_warning("[Replay] Failed to parse replay JSON")
		return
	var replay := ReplayData.new()
	replay.from_dict(json.data)
	if replay.timestamp_unix > 0.0:
		# Rewrite the host's local-time string into this client's timezone
		replay.timestamp = ReplayData.local_datetime_string_from_unix(replay.timestamp_unix)
	var ver := ReplayData._get_game_version()
	var fname := "replay_%s.json" % replay.timestamp.replace(" ", "_").replace(":", "").replace("-", "")
	var path := ReplayData.get_version_recent_dir(ver) + fname
	var err := ReplayData.save_to_file(replay, path)
	if err == OK:
		print("[Replay] Client saved replay to %s (%d snapshots)" % [path, replay.snapshots.size()])
		ReplayData.prune_recent(ver)
	else:
		push_warning("[Replay] Client failed to save replay (error %d)" % err)


# --- Stats upload ---

func upload_stats(winner_id: int, reason: String, is_disconnect: bool) -> void:
	# Only upload for online games, and only once per match
	if stats_uploaded:
		return
	if NetworkManager.mode != NetworkManager.Mode.ONLINE_HOST and NetworkManager.mode != NetworkManager.Mode.ONLINE_CLIENT:
		return
	# Host is primary reporter; client only reports on disconnect
	if not is_disconnect and not NetworkManager.is_host():
		return
	stats_uploaded = true

	# Host uses turn_manager directly; client reconstructs from synced state
	var gs: GameState
	if _session.turn_manager:
		gs = _session.turn_manager.game_state
	else:
		gs = GameState.new()
		gs.players = _session.client_players
		gs.current_player_id = _session.client_current_player_id
		gs.turn_number = _session.client_turn_number
		gs.current_phase = _session.client_phase
		gs.player_names = Array(GameLog.player_names) as Array[String]
		# Restore opponent's hand from stats snapshot
		var opponent_id: int = 1 - _board.local_player_id
		if not _session.client_stats_opponent_hand.is_empty():
			gs.players[opponent_id].hand.assign(StateCodec.ids_to_cards(_session.client_stats_opponent_hand))
		# Populate DecklistManager with synced decklist data
		for i in range(2):
			if _session.client_stats_decklists[i] != null and not DecklistManager.has_player_deck(i):
				var dl: Dictionary = _session.client_stats_decklists[i]
				DecklistManager._player_decks[i] = {
					"deck_name": _session.client_stats_deck_names[i],
					"monster_deck": dl.get("monster_deck", []),
					"main_entries": dl.get("main_entries", []),
				}
		# Use host-synced elapsed times
		_board._player_elapsed_ms = _session.client_stats_elapsed_ms.duplicate()
		_board._game_start_time_ms = _session.client_stats_game_start_ms
		_board._turn_start_time_ms = _session.client_stats_turn_start_ms

	# Finalize active player's elapsed time
	if _board._turn_start_time_ms > 0:
		var now := Time.get_ticks_msec()
		var active_pid: int = gs.current_player_id
		_board._player_elapsed_ms[active_pid] += now - _board._turn_start_time_ms
	var total_elapsed: int = Time.get_ticks_msec() - _board._game_start_time_ms if _board._game_start_time_ms > 0 else 0
	StatsUploader.upload_game_result(
		gs,
		winner_id,
		reason,
		_board._first_player_id,
		_board._player_elapsed_ms,
		total_elapsed,
		is_disconnect,
	)
