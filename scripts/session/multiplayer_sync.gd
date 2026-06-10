class_name MultiplayerSync
extends Node

## Owns the multiplayer RPC contract and host<->client state sync for the
## game board. Lives at a stable NodePath (GameBoard/GameSession/MultiplayerSync)
## so RPC dispatch works on host and client without depending on the
## presentation script.
##
## Owns outright: state broadcast (debounced, versioned, delta+gzip encoded
## via StateCodec), client-side receive/apply, resync + pending-interaction
## replay, and action submission. Effect-prompt RPCs are still forwarders
## into game_board.gd until the overlay extraction lands; presentation
## updates on receive go through small _board hooks (_append_log_entry,
## _apply_remote_player_names, _update_turn_tracker, ...).

const RESYNC_COOLDOWN_MS: int = 2000

var _board: Node
var _session: GameSession

# Host broadcast state
var _state_version: int = 0 # Incremented on each broadcast (host only)
var _broadcast_pending: bool = false # Debounce flag for frame-based coalescing
var _last_sent_state: Dictionary = {} # Host: last serialized state sent to client
var _last_sent_version: int = 0 # Host: version of _last_sent_state
# Host: in-flight prompt the client must answer, replayed on resync.
# {method: String, args: Array}
var _pending_interaction: Dictionary = {}

# Client receive state
var _client_state_version: int = 0 # Last received version (client only)
var _client_full_state: Dictionary = {} # Client: accumulated full state from deltas
var _last_resync_request_ms: int = 0 # Client: rate-limit resync requests


func _ready() -> void:
	_session = get_parent()
	if _session:
		_board = _session.get_parent()


# --- State broadcast (host) ---

## Queue a state broadcast for the end of the current frame. Multiple calls
## per frame coalesce into one packet.
func broadcast_state() -> void:
	if not _board.is_multiplayer_game or not NetworkManager.is_host():
		return
	if not _session.turn_manager or not _session.turn_manager.game_state:
		return
	if not _broadcast_pending:
		_broadcast_pending = true
		_do_broadcast.call_deferred()


## Force any pending broadcast to send immediately.
## Call before sending RPCs that depend on the client having up-to-date state.
func flush_broadcast() -> void:
	if _broadcast_pending:
		_do_broadcast()


func _do_broadcast() -> void:
	_broadcast_pending = false
	if not _board.is_multiplayer_game or not NetworkManager.is_host():
		return
	if not _session.turn_manager or not _session.turn_manager.game_state:
		return

	_state_version += 1
	for peer_id in NetworkManager.peer_player_map:
		if peer_id == 1:
			continue # Don't send to self (server peer ID is 1)
		var viewer_id: int = NetworkManager.peer_player_map[peer_id]
		var state_dict := _serialize_game_state(viewer_id)

		var envelope: Dictionary
		if _last_sent_state.is_empty():
			# First broadcast or after resync: send full state
			envelope = {"v": _state_version, "bv": - 1, "d": state_dict}
		else:
			var delta := StateCodec.compute_delta(_last_sent_state, state_dict)
			if delta.is_empty() and _board._pending_log_tokens.is_empty() and _board._pending_sound_events.is_empty():
				# Nothing changed, no logs, no sounds — skip broadcast entirely
				_state_version -= 1
				continue
			envelope = {"v": _state_version, "bv": _last_sent_version, "d": delta}

		# Piggyback buffered log tokens on the envelope (dicts + legacy strings)
		if not _board._pending_log_tokens.is_empty():
			envelope["log"] = _board._pending_log_tokens.duplicate()

		# Piggyback buffered sound events on the envelope
		if not _board._pending_sound_events.is_empty():
			envelope["sfx"] = Array(_board._pending_sound_events)

		_last_sent_state = state_dict.duplicate(true)
		_last_sent_version = _state_version

		var raw_bytes := var_to_bytes(envelope)
		if raw_bytes.size() > 32768:
			push_warning("[BROADCAST] Large state packet: %d bytes (v=%d, full=%s)" % [
				raw_bytes.size(), _state_version, str(_last_sent_state.is_empty())])
		var wire_bytes := StateCodec.wrap_state_payload(raw_bytes)
		RpcLogger.log_send("receive_state", wire_bytes.size())
		_rpc_receive_state.rpc_id(peer_id, wire_bytes)
	_board._pending_log_tokens.clear()
	_board._pending_sound_events.clear()


func _serialize_game_state(viewer_id: int) -> Dictionary:
	var tm: TurnManager = _session.turn_manager
	var gs := tm.game_state
	var eh := tm.effect_handler
	var zone_cp_0: Array = eh.get_zone_cp_modifiers(0) if eh else []
	var zone_cp_1: Array = eh.get_zone_cp_modifiers(1) if eh else []
	var strat_cp_0: Array = eh.get_strategy_cp_modifiers(0) if eh else []
	var strat_cp_1: Array = eh.get_strategy_cp_modifiers(1) if eh else []
	var cp_total_0: int = eh.get_monster_cp_modifier(0) if eh else 0
	var cp_total_1: int = eh.get_monster_cp_modifier(1) if eh else 0
	for v in zone_cp_0: cp_total_0 += v
	for v in zone_cp_1: cp_total_1 += v
	for v in strat_cp_0: cp_total_0 += v
	for v in strat_cp_1: cp_total_1 += v
	var data := {
		"state_version": _state_version,
		"current_player_id": gs.current_player_id,
		"current_phase": int(gs.current_phase),
		"current_sub_phase": _board._current_sub_phase,
		"turn_number": gs.turn_number,
		"is_game_over": tm.is_game_over,
		"players": [],
		"cp_modifiers": [cp_total_0, cp_total_1],
		"threat_modifiers": [eh.get_threat_level_modifier(0) if eh else 0, eh.get_threat_level_modifier(1) if eh else 0],
		"zone_cp_modifiers": [zone_cp_0, zone_cp_1],
		"strategy_cp_modifiers": [strat_cp_0, strat_cp_1],
		"zone_rank_modifiers": [eh.get_zone_rank_modifiers(0) if eh else [], eh.get_zone_rank_modifiers(1) if eh else []],
		"hand_rank_modifiers": [_session.compute_hand_rank_mods(gs.players[0]) if eh else [], _session.compute_hand_rank_mods(gs.players[1]) if eh else []],
		"monster_cp_modifiers": [eh.get_monster_cp_modifier(0) if eh else 0, eh.get_monster_cp_modifier(1) if eh else 0],
		"player_names": Array(gs.player_names),
		"first_player_id": _board._first_player_id,
	}
	for i in range(2):
		var pd := StateCodec.serialize_player_state(gs.players[i])
		if i != viewer_id:
			# Strip hand and monster deck data for opponent — only send counts
			# (full hand kept in stats_opponent_hand for disconnect reporting)
			pd["stats_hand"] = pd["hand"].duplicate(true)
			pd.erase("hand")
			pd["monster_deck_count"] = pd["monster_deck"].size()
			pd.erase("monster_deck")
		data["players"].append(pd)
	# Stats data for client disconnect reporting
	data["stats_elapsed_ms"] = Array(_board._player_elapsed_ms)
	data["stats_game_start_ms"] = _board._game_start_time_ms
	data["stats_turn_start_ms"] = _board._turn_start_time_ms
	for i in range(2):
		var deck_name := DecklistManager.get_player_deck_name(i)
		data["players"][i]["stats_deck_name"] = deck_name
		var deck_data = DecklistManager._player_decks[i]
		if deck_data != null:
			data["players"][i]["stats_decklist"] = {
				"main_entries": deck_data["main_entries"],
				"monster_deck": deck_data["monster_deck"],
			}
	# Include hash of shared game state for desync detection
	data["state_hash"] = StateCodec.compute_state_hash(gs)
	return data


func compute_playable_data() -> Dictionary:
	var gs := _session.turn_manager.game_state
	var player := gs.get_current_player()
	var opponent := gs.get_opponent_of_current()
	var rules := _session.turn_manager.rules_engine
	var playable_battle := rules.get_playable_battle_cards(player, opponent)
	var battle_zones_per_card: Dictionary = {}
	for idx in playable_battle:
		var card: Dictionary = player.hand[idx]
		var card_id: String = card.get("id", "")
		if not card_id.is_empty():
			battle_zones_per_card[card_id] = rules.get_valid_zones_for_card(card, player, opponent)
	return {
		"valid_actions": rules.get_valid_actions(gs),
		"battle_cards": playable_battle,
		"battle_zones": battle_zones_per_card,
		"strategy_cards": rules.get_playable_strategy_cards(player),
		"monster_cards": rules.get_playable_monsters(player),
		"rage_cards": rules.get_monster_cards_for_rage(player),
		"invade_cards": rules.get_discardable_cards_for_invade(player, opponent),
	}


# --- Reset / resync helpers ---

## Reset all sync state for a rematch (host and client paths).
func reset_for_rematch() -> void:
	_state_version = 0
	_client_state_version = 0
	_broadcast_pending = false
	_last_sent_state = {}
	_last_sent_version = 0
	_client_full_state = {}
	_pending_interaction = {}


## Client: reset the delta stream so the next broadcast must be a full state
## (used after a reconnect re-established the peer).
func reset_client_stream() -> void:
	_client_full_state = {}
	_client_state_version = 0
	_last_resync_request_ms = 0


## Host: force the next broadcast to carry full state, and send it now.
func force_full_broadcast() -> void:
	_last_sent_state = {}
	_last_sent_version = 0
	broadcast_state()
	flush_broadcast()


## Host: full-state resync for a (re)connected client, replaying the
## in-flight prompt if the host was waiting on client input, otherwise
## re-prompting whoever's turn it is.
func resync_client(peer_id: int) -> void:
	force_full_broadcast()
	if not _pending_interaction.is_empty():
		if peer_id > 0:
			_resend_pending_interaction(peer_id)
	elif _session.turn_manager and not _session.turn_manager.is_game_over:
		# (_on_awaiting_action handles both host and client turn cases)
		var valid_actions := _session.turn_manager.rules_engine.get_valid_actions(_session.turn_manager.game_state)
		if not valid_actions.is_empty():
			_board._on_awaiting_action(valid_actions)


func _resend_pending_interaction(peer_id: int) -> void:
	var method: String = _pending_interaction.get("method", "")
	var args: Array = _pending_interaction.get("args", [])
	match method:
		"action_context":
			RpcLogger.log_send("receive_action_context", args[0].length() + args[1].length())
			_rpc_receive_action_context.rpc_id(peer_id, args[0], args[1])
		"deck_search":
			RpcLogger.log_send("deck_search_requested", args[0].length() + args[1].length() + args[2].length())
			_rpc_deck_search_requested.rpc_id(peer_id, args[0], args[1], args[2], args[3])
		"deck_arrange":
			RpcLogger.log_send("deck_arrange_requested", args[0].length() + args[1].length())
			_rpc_deck_arrange_requested.rpc_id(peer_id, args[0], args[1])
		"card_select":
			RpcLogger.log_send("card_select_requested", args[0].length() + args[1].length() + args[2].length())
			_rpc_card_select_requested.rpc_id(peer_id, args[0], args[1], args[2], args[3], args[4])
		"hand_discard":
			RpcLogger.log_send("hand_discard_requested", 4)
			_rpc_hand_discard_requested.rpc_id(peer_id, args[0])
		"hand_card_selection":
			RpcLogger.log_send("hand_card_selection_requested", args[0].length() + args[1].length() + 1)
			_rpc_hand_card_selection_requested.rpc_id(peer_id, args[0], args[1], args[2])
		"zone_target":
			RpcLogger.log_send("zone_target_requested", 4 + args[1].length() + args[2].length() + 1)
			_rpc_zone_target_requested.rpc_id(peer_id, args[0], args[1], args[2], args[3])
		"strategy_target":
			RpcLogger.log_send("strategy_target_requested", 4 + args[1].length() + args[2].length())
			_rpc_strategy_target_requested.rpc_id(peer_id, args[0], args[1], args[2])
		"choice":
			RpcLogger.log_send("choice_requested", args[0].length() + args[1].length())
			_rpc_choice_requested.rpc_id(peer_id, args[0], args[1], args[2] if args.size() > 2 else "[]")
		"confirmation":
			RpcLogger.log_send("confirmation_requested", args[0].length() + args[1].length())
			_rpc_confirmation_requested.rpc_id(peer_id, args[0], args[1])
		"monster_rankup":
			RpcLogger.log_send("monster_rankup_requested", args[0].length() + args[1].length() + args[2].length())
			_rpc_monster_rankup_requested.rpc_id(peer_id, args[0], args[1], args[2])


## Rate-limited resync request (client only). Prevents flooding the host with
## resync RPCs when multiple deltas fail in quick succession.
func _request_resync_throttled() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_resync_request_ms < RESYNC_COOLDOWN_MS:
		return # Too soon — skip this resync request
	_last_resync_request_ms = now
	RpcLogger.log_send("request_resync", 0)
	_rpc_request_resync.rpc_id(NetworkManager.host_peer_id)


# --- First-player choice ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_first_player_waiting() -> void:
	if _board:
		_board._rpc_first_player_waiting()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_first_player_choice_requested() -> void:
	if _board:
		_board._rpc_first_player_choice_requested()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_first_player_choice_resolved(chosen_id: int) -> void:
	if _board:
		_board._rpc_first_player_choice_resolved(chosen_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_cleanup_first_player() -> void:
	if _board:
		_board._rpc_cleanup_first_player()


# --- Concede / rematch ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_concede() -> void:
	if _board:
		_board._rpc_concede()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rematch_requested() -> void:
	if _board:
		_board._rpc_rematch_requested()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rematch_with_deck(payload_json: String) -> void:
	if _board:
		_board._rpc_rematch_with_deck(payload_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_execute_rematch() -> void:
	if _board:
		_board._rpc_execute_rematch()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rematch_declined() -> void:
	if _board:
		_board._rpc_rematch_declined()


# --- Action submission and state sync (real bodies live here) ---

## Client -> Host: submit an action
@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_action(action_type: int, params_json: String) -> void:
	RpcLogger.log_receive("submit_action", 4 + params_json.length())
	if not NetworkManager.is_host() or not _session.turn_manager:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var sender_player_id: int = NetworkManager.peer_player_map.get(sender_id, -1)
	if sender_player_id != _session.turn_manager.game_state.current_player_id:
		return # Not their turn
	_pending_interaction = {}

	var action: CardEnums.ActionType = action_type as CardEnums.ActionType
	var params: Dictionary = {}
	if not params_json.is_empty():
		params = JSON.parse_string(params_json)
		# JSON parses ints as floats — convert known fields
		if params.has("hand_index"):
			params["hand_index"] = int(params["hand_index"])
		if params.has("zone_index"):
			params["zone_index"] = int(params["zone_index"])

	_session.turn_manager.submit_action(action, params)


## Host -> Client: full or delta game state update
@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_state(state_bytes: PackedByteArray) -> void:
	RpcLogger.log_receive("receive_state", state_bytes.size())
	if state_bytes.is_empty():
		return
	var raw_bytes := StateCodec.unwrap_state_payload(state_bytes)
	if raw_bytes.is_empty():
		push_warning("[STATE] Payload unwrap failed (wire size=%d)" % state_bytes.size())
		_request_resync_throttled()
		return
	var decoded: Variant = bytes_to_var(raw_bytes)
	if decoded == null or not decoded is Dictionary:
		push_warning("[STATE] bytes_to_var failed or returned non-Dictionary (raw size=%d)" % raw_bytes.size())
		_request_resync_throttled()
		return
	var envelope: Dictionary = decoded
	if envelope.is_empty():
		return

	# Extract piggybacked log entries (tokens rendered in local locale)
	if envelope.has("log"):
		for entry in envelope["log"]:
			_board._append_log_entry(entry)

	# Play piggybacked sound events from host
	if envelope.has("sfx"):
		for sfx_name in envelope["sfx"]:
			SfxManager.play(str(sfx_name))

	var version: int = int(envelope.get("v", 0))
	var base_version: int = int(envelope.get("bv", -1))
	var payload: Dictionary = envelope.get("d", {})

	# Unwrap envelope: full state or delta
	var data: Dictionary
	if base_version == -1:
		# Full state
		data = payload
		_client_full_state = data.duplicate(true)
	else:
		if _client_state_version != base_version:
			push_warning("[DELTA] Base version mismatch: have %d, got bv=%d. Requesting resync." % [_client_state_version, base_version])
			_request_resync_throttled()
			return
		_client_full_state = StateCodec.apply_delta(_client_full_state, payload)
		data = _client_full_state

	# Validate that the data has required fields before processing
	if not data.has("current_player_id") or not data.has("players"):
		push_warning("[STATE] Received state missing required fields — requesting resync")
		_request_resync_throttled()
		return

	# Track state version for desync detection
	if version > 0 and _client_state_version > 0 and version < _client_state_version:
		push_warning("[DESYNC] Received state version %d but already at %d — out-of-order delivery" % [version, _client_state_version])
	_client_state_version = version

	_session.client_current_player_id = int(data["current_player_id"])
	_session.client_turn_number = int(data.get("turn_number", 0))
	_session.client_phase = int(data.get("current_phase", 0)) as CardEnums.GamePhase
	_board._first_player_id = int(data.get("first_player_id", 0))

	# Extract effect modifiers
	if data.has("cp_modifiers"):
		_session.client_cp_modifiers = data["cp_modifiers"]
		for j in range(_session.client_cp_modifiers.size()):
			_session.client_cp_modifiers[j] = int(_session.client_cp_modifiers[j])
	if data.has("threat_modifiers"):
		_session.client_threat_modifiers = data["threat_modifiers"]
		for j in range(_session.client_threat_modifiers.size()):
			_session.client_threat_modifiers[j] = int(_session.client_threat_modifiers[j])
	if data.has("zone_cp_modifiers"):
		_session.client_zone_cp_mods = data["zone_cp_modifiers"]
		for i in range(_session.client_zone_cp_mods.size()):
			var arr: Array = _session.client_zone_cp_mods[i]
			for j in range(arr.size()):
				arr[j] = int(arr[j])
	if data.has("strategy_cp_modifiers"):
		_session.client_strategy_cp_mods = data["strategy_cp_modifiers"]
		for i in range(_session.client_strategy_cp_mods.size()):
			var arr: Array = _session.client_strategy_cp_mods[i]
			for j in range(arr.size()):
				arr[j] = int(arr[j])
	if data.has("zone_rank_modifiers"):
		_session.client_zone_rank_mods = data["zone_rank_modifiers"]
		for i in range(_session.client_zone_rank_mods.size()):
			var arr: Array = _session.client_zone_rank_mods[i]
			for j in range(arr.size()):
				arr[j] = int(arr[j])
	if data.has("hand_rank_modifiers"):
		_session.client_hand_rank_mods = data["hand_rank_modifiers"]
		for i in range(_session.client_hand_rank_mods.size()):
			var arr: Array = _session.client_hand_rank_mods[i]
			for j in range(arr.size()):
				arr[j] = int(arr[j])
	if data.has("monster_cp_modifiers"):
		_session.client_monster_cp_mods = data["monster_cp_modifiers"]
		for j in range(_session.client_monster_cp_mods.size()):
			_session.client_monster_cp_mods[j] = int(_session.client_monster_cp_mods[j])

	# Reconstruct PlayerState objects
	var players_data: Array = data["players"]
	if players_data.size() < 2:
		push_warning("[STATE] players array too small: %d" % players_data.size())
		_request_resync_throttled()
		return
	for i in range(2):
		var pd: Dictionary = players_data[i]
		_session.client_players[i] = StateCodec.dict_to_player_state(pd, i == _board.local_player_id)
		# Store stats fields for disconnect reporting
		if pd.has("stats_deck_name"):
			_session.client_stats_deck_names[i] = str(pd["stats_deck_name"])
		if pd.has("stats_decklist"):
			_session.client_stats_decklists[i] = pd["stats_decklist"]
		if pd.has("stats_hand") and i != _board.local_player_id:
			_session.client_stats_opponent_hand = pd["stats_hand"]

	# Stats timing from host
	if data.has("stats_elapsed_ms"):
		var arr: Array = data["stats_elapsed_ms"]
		_session.client_stats_elapsed_ms = [int(arr[0]), int(arr[1])] as Array[int]
	if data.has("stats_game_start_ms"):
		_session.client_stats_game_start_ms = int(data["stats_game_start_ms"])
	if data.has("stats_turn_start_ms"):
		_session.client_stats_turn_start_ms = int(data["stats_turn_start_ms"])

	# Apply monster color gradient and send player name on first state receive
	if not _session.client_gradients_applied:
		_session.client_gradients_applied = true
		_board._apply_client_monster_gradients()
		RpcLogger.log_send("send_player_name", GameSettings.player_name.length())
		_rpc_send_player_name.rpc_id(NetworkManager.host_peer_id, GameSettings.player_name)

	# Sync player names from host (disambiguate from client's perspective)
	_board._apply_remote_player_names(data.get("player_names", []))

	# Desync detection: compare state hash from host with locally reconstructed state
	if data.has("state_hash"):
		var host_hash: int = int(data["state_hash"])
		var local_hash: int = StateCodec.compute_client_state_hash(
			_session.client_players,
			int(data.get("turn_number", 0)),
			_session.client_current_player_id,
			int(data.get("current_phase", 0)))
		if host_hash != local_hash:
			push_warning("[DESYNC] State hash mismatch at version %d (turn %d, phase %d) — host=%d local=%d" % [
				_client_state_version,
				int(data.get("turn_number", 0)),
				int(data.get("current_phase", 0)),
				host_hash, local_hash])
			# Auto-resync if this was a delta (full state hash mismatch is a real desync)
			if base_version >= 0:
				push_warning("[DELTA] Hash mismatch after delta apply — requesting resync")
				_request_resync_throttled()

	# Update UI
	var client_phase := int(data["current_phase"]) as CardEnums.GamePhase
	var client_sub_phase: int = int(data.get("current_sub_phase", 0))
	_board._update_turn_tracker(_session.client_current_player_id, client_phase, client_sub_phase)
	_board._sync_boards()
	_board._update_hand_visibility(_session.client_current_player_id)

	# First successful apply: session is ready for client-side module binding
	_session.mark_client_started()
	_session.client_state_applied.emit()


## Client -> Host: request full state resend (delta base version mismatch or
## hash mismatch). Replays the in-flight prompt if one is pending.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_resync() -> void:
	if not NetworkManager.is_host():
		return
	RpcLogger.log_receive("request_resync", 0)
	resync_client(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_action_context(actions_json: String, playable_json: String) -> void:
	if _board:
		_board._rpc_receive_action_context(actions_json, playable_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_log(text: String) -> void:
	if _board:
		_board._rpc_receive_log(text)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_chat(sender_player_id: int, text: String) -> void:
	if _board:
		_board._rpc_receive_chat(sender_player_id, text)


# --- Effect overlay request/resolve pairs ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_search_requested(matching_json: String, all_json: String, prompt: String, allow_skip: bool = true) -> void:
	if _board:
		_board._rpc_deck_search_requested(matching_json, all_json, prompt, allow_skip)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_search_resolved(selected_json: String) -> void:
	if _board:
		_board._rpc_deck_search_resolved(selected_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_arrange_requested(cards_json: String, prompt: String) -> void:
	if _board:
		_board._rpc_deck_arrange_requested(cards_json, prompt)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_arrange_resolved(keep_json: String, discard_json: String) -> void:
	if _board:
		_board._rpc_deck_arrange_resolved(keep_json, discard_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_card_select_requested(matching_json: String, all_json: String, prompt: String, min_count: int, max_count: int) -> void:
	if _board:
		_board._rpc_card_select_requested(matching_json, all_json, prompt, min_count, max_count)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_card_select_resolved(selected_json: String) -> void:
	if _board:
		_board._rpc_card_select_resolved(selected_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_card_selection_requested(indices_json: String, prompt: String, allow_skip: bool) -> void:
	if _board:
		_board._rpc_hand_card_selection_requested(indices_json, prompt, allow_skip)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_card_selection_resolved(hand_index: int) -> void:
	if _board:
		_board._rpc_hand_card_selection_resolved(hand_index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_confirmation_requested(prompt: String, setting: String) -> void:
	if _board:
		_board._rpc_confirmation_requested(prompt, setting)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_confirmation_resolved() -> void:
	if _board:
		_board._rpc_confirmation_resolved()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_player_name(pname: String) -> void:
	if _board:
		_board._rpc_send_player_name(pname)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_discard_requested(discard_count: int) -> void:
	if _board:
		_board._rpc_hand_discard_requested(discard_count)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_discard_resolved(indices_json: String) -> void:
	if _board:
		_board._rpc_hand_discard_resolved(indices_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_zone_target_requested(target_player_id: int, zones_json: String, prompt: String, allow_skip: bool) -> void:
	if _board:
		_board._rpc_zone_target_requested(target_player_id, zones_json, prompt, allow_skip)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_zone_target_resolved(zone_index: int) -> void:
	if _board:
		_board._rpc_zone_target_resolved(zone_index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_strategy_target_requested(target_player_id: int, indices_json: String, prompt: String) -> void:
	if _board:
		_board._rpc_strategy_target_requested(target_player_id, indices_json, prompt)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_strategy_target_resolved(strategy_index: int) -> void:
	if _board:
		_board._rpc_strategy_target_resolved(strategy_index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_choice_requested(options_json: String, prompt: String, card_ids_json: String = "[]") -> void:
	if _board:
		_board._rpc_choice_requested(options_json, prompt, card_ids_json)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_choice_resolved(index: int) -> void:
	if _board:
		_board._rpc_choice_resolved(index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_monster_rankup_requested(monsters_json: String, indices_json: String, prompt: String) -> void:
	if _board:
		_board._rpc_monster_rankup_requested(monsters_json, indices_json, prompt)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_monster_rankup_resolved(index: int) -> void:
	if _board:
		_board._rpc_monster_rankup_resolved(index)


# --- Effect highlights ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_zone_highlighted(pid: int, zone_index: int) -> void:
	if _board:
		_board._rpc_effect_zone_highlighted(pid, zone_index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_zone_unhighlighted(pid: int, zone_index: int) -> void:
	if _board:
		_board._rpc_effect_zone_unhighlighted(pid, zone_index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_card_highlighted(pid: int, card_id: String) -> void:
	if _board:
		_board._rpc_effect_card_highlighted(pid, card_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_card_unhighlighted(pid: int, card_id: String) -> void:
	if _board:
		_board._rpc_effect_card_unhighlighted(pid, card_id)


# --- Game end / replay ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_game_ended(winner_id: int, reason_key: String) -> void:
	if _board:
		_board._rpc_receive_game_ended(winner_id, reason_key)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_replay(compressed: PackedByteArray) -> void:
	if _board:
		_board._rpc_receive_replay(compressed)
