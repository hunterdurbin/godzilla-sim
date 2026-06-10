class_name HeadlessBoard
extends Node

## Server-side stand-in for game_board.gd. Sits on the room's node named
## "GameBoard" (the name is part of the cross-scene RPC contract) and
## implements the `_board` surface MultiplayerSync touches, plus the host
## game-flow logic ported from game_board.gd — with every UI concern removed.
## Both human players run the regular client code path; this board only ever
## executes the host path.
##
## TODO(M2): sound-event buffering (BoardSfx parity), stats upload, replay
## send, rematch flow.

## Set by GameRoom right after instantiation.
var room: Node

# --- `_board` surface MultiplayerSync reads ---
var is_multiplayer_game: bool = true
var is_bot_game: bool = false
var local_player_id: int = -1 # No local player — every prompt routes remote
var _current_sub_phase: int = 0
var _first_player_id: int = 0
var _pending_log_tokens: Array = []
var _pending_sound_events: PackedStringArray = []
var _player_elapsed_ms: Array[int] = [0, 0]
var _turn_start_time_ms: int = 0
var _game_start_time_ms: int = 0

var _session: GameSession
var _sync: MultiplayerSync
var _first_player_result: int = -1
var _first_player_chooser_peer: int = -1


func _ready() -> void:
	_session = get_node("GameSession")
	_sync = get_node("GameSession/MultiplayerSync")


## Build the authoritative session and run the match. Called by GameRoom once
## both seats are filled and decks are in.
func start_match(config: SessionConfig) -> void:
	# Router hooks (the presentation scene sets these in production): flush
	# buffered state before each prompt RPC so the client answers against
	# fresh state, and record router prompts for resync replay.
	var router: EffectUIRouter = get_node("GameSession/EffectUIRouter")
	router.on_pre_remote_dispatch = func() -> void:
		_sync.broadcast_state()
		_sync.flush_broadcast()
	router.on_pending_interaction = func(method: String, args: Array, player_id: int) -> void:
		_sync._pending_interaction = {"method": method, "args": args, "player": player_id}

	var tm := _session.start_host_session(CardData, -1, {}, config)

	tm.phase_started.connect(_on_phase_started)
	tm.phase_ended.connect(_on_phase_ended)
	tm.sub_phase_changed.connect(_on_sub_phase_changed)
	tm.awaiting_player_action.connect(_on_awaiting_action)
	tm.turn_started.connect(_on_turn_started)
	tm.confirmation_requested.connect(_on_confirmation_requested)
	tm.game_ended.connect(_on_game_ended)
	tm.log_message.connect(_on_log_message)

	for player in tm.game_state.players:
		player.hand_changed.connect(_on_state_changed)
		player.zones_changed.connect(_on_state_changed)
		player.rage_changed.connect(_on_state_changed.unbind(1))
		player.monster_changed.connect(_on_state_changed)
		player.discard_changed.connect(_on_state_changed)
		player.deck_changed.connect(_on_state_changed)
		player.strategy_zones_changed.connect(_on_state_changed)

	_start_stall_watchdog()
	await _start_first_player_flow()


## Diagnostics: if the engine goes quiet for a long stretch mid-match, log
## its await-state flags so a stuck await is identifiable from server logs.
var _last_activity_ms: int = 0

func _start_stall_watchdog() -> void:
	_last_activity_ms = Time.get_ticks_msec()
	var timer := Timer.new()
	timer.wait_time = 30.0
	timer.timeout.connect(_check_stall)
	add_child(timer)
	timer.start()


func _check_stall() -> void:
	var tm: TurnManager = _session.turn_manager
	if tm == null or tm.is_game_over:
		return
	var quiet_s := (Time.get_ticks_msec() - _last_activity_ms) / 1000.0
	if quiet_s < 60.0:
		return
	print("[HeadlessBoard %s] Quiet %.0fs: phase=%d processing=%s waiting_input=%s confirm_pending=%s pending=%s" % [
		room.code if room else "?", quiet_s,
		int(tm.game_state.current_phase),
		tm._processing_action, tm._waiting_for_input, tm._confirmation_pending,
		str(_sync._pending_interaction).left(160)])


## Coin flip + remote first-player choice (ported from game_board's
## multiplayer branch — the server is never the chooser).
func _start_first_player_flow() -> void:
	var chooser_id := randi() % 2
	_on_log_message(GameLog.coin_flip_won(chooser_id))
	_first_player_result = -1

	_sync.broadcast_state()
	_sync.flush_broadcast()
	var chooser_peer: int = room.peer_for_player(chooser_id)
	var other_peer: int = room.peer_for_player(1 - chooser_id)
	_first_player_chooser_peer = chooser_peer
	if other_peer > 0:
		_sync._rpc_first_player_waiting.rpc_id(other_peer)
	if chooser_peer > 0:
		_sync._rpc_first_player_choice_requested.rpc_id(chooser_peer)

	while _first_player_result < 0:
		await get_tree().process_frame

	_sync._rpc_cleanup_first_player.rpc()
	_first_player_id = _first_player_result
	_on_log_message(GameLog.first_player_chose(_first_player_result, true))
	_session.turn_manager.start_game(_first_player_result)


# --- TurnManager signal handlers (host flow, broadcast-only) ---

func _on_phase_started(_phase: CardEnums.GamePhase) -> void:
	_sync.broadcast_state()


func _on_phase_ended(_phase: CardEnums.GamePhase) -> void:
	_sync.broadcast_state()


func _on_sub_phase_changed(sub_index: int) -> void:
	_current_sub_phase = sub_index
	_sync.broadcast_state()


func _on_turn_started(player_id: int) -> void:
	# Stats: accumulate previous player's think time and start new timer
	var now := Time.get_ticks_msec()
	if _game_start_time_ms == 0:
		_game_start_time_ms = now
	elif _turn_start_time_ms > 0:
		var prev_player := 1 - player_id
		_player_elapsed_ms[prev_player] += now - _turn_start_time_ms
	_turn_start_time_ms = now


func _on_state_changed() -> void:
	_last_activity_ms = Time.get_ticks_msec()
	_sync.broadcast_state()


func _on_log_message(message) -> void:
	_pending_log_tokens.append(message)
	_sync.broadcast_state()


## Action context must arrive at the active player after fresh state.
## Also the replay target for resync_client() when no prompt is pending.
func _on_awaiting_action(valid_actions: Array) -> void:
	_sync.broadcast_state()
	_sync.flush_broadcast()
	var active_id: int = _session.turn_manager.game_state.current_player_id
	var playable := _sync.compute_playable_data()
	var actions_json := JSON.stringify(valid_actions)
	var playable_json := JSON.stringify(playable)
	_sync._pending_interaction = {"method": "action_context", "args": [actions_json, playable_json], "player": active_id}
	var peer: int = room.peer_for_player(active_id)
	print("[HeadlessBoard %s] action context -> player %d (peer %d)" % [room.code, active_id, peer])
	if peer > 0:
		RpcLogger.log_send("receive_action_context", actions_json.length() + playable_json.length())
		_sync._rpc_receive_action_context.rpc_id(peer, actions_json, playable_json)


func _on_confirmation_requested(prompt: String, setting: String) -> void:
	_sync.flush_broadcast()
	var current_pid: int = _session.turn_manager.game_state.current_player_id
	_sync._pending_interaction = {"method": "confirmation", "args": [prompt, setting], "player": current_pid}
	var peer: int = room.peer_for_player(current_pid)
	if peer > 0:
		RpcLogger.log_send("confirmation_requested", prompt.length() + setting.length())
		_sync._rpc_confirmation_requested.rpc_id(peer, prompt, setting)


func _on_game_ended(winner_id: int, reason_key: String) -> void:
	_sync._pending_interaction = {}
	_sync.broadcast_state()
	_sync.flush_broadcast()
	_sync._rpc_receive_game_ended.rpc(winner_id, reason_key)
	if room and room.has_method("on_match_ended"):
		room.on_match_ended(winner_id, reason_key)


# --- RPC handlers forwarded from MultiplayerSync ---

## Chooser's client answered the first-player prompt.
func _rpc_first_player_choice_resolved(chosen_id: int) -> void:
	if _sync.multiplayer.get_remote_sender_id() != _first_player_chooser_peer:
		push_warning("[HeadlessBoard] Rejected first-player choice: sender is not the chooser")
		return
	if chosen_id == 0 or chosen_id == 1:
		_first_player_result = chosen_id
		_first_player_chooser_peer = -1


## Claim-win validation — delegates to the room's seat/grace state.
func can_claim_win(sender_conn_id: int) -> bool:
	return room != null and room.can_claim_win(sender_conn_id)


## Client conceded mid-game.
func _rpc_concede() -> void:
	var sender_id: int = _sync.multiplayer.get_remote_sender_id()
	var loser_id: int = room.player_for_peer(sender_id)
	if loser_id < 0:
		return
	if _session.turn_manager == null or _session.turn_manager.is_game_over:
		return
	_session.turn_manager._on_game_over(1 - loser_id, GameLog.concede_reason_key(loser_id))


# --- Client-display RPCs that can land on the server (broadcasts, or a
# misbehaving client targeting peer 1). All no-ops; M4 adds sender checks. ---

func _rpc_first_player_waiting() -> void: pass
func _rpc_first_player_choice_requested() -> void: pass
func _rpc_cleanup_first_player() -> void: pass
func _rpc_receive_action_context(_a: String, _b: String) -> void: pass
func _rpc_receive_log(_text: String) -> void: pass
func _rpc_receive_chat(_pid: int, _text: String) -> void: pass
func _rpc_deck_search_requested(_a: String, _b: String, _c: String, _d: bool = true) -> void: pass
func _rpc_deck_arrange_requested(_a: String, _b: String) -> void: pass
func _rpc_card_select_requested(_a: String, _b: String, _c: String, _d: int, _e: int) -> void: pass
func _rpc_hand_card_selection_requested(_a: String, _b: String, _c: bool) -> void: pass
func _rpc_confirmation_requested(_a: String, _b: String) -> void: pass
func _rpc_hand_discard_requested(_a: int) -> void: pass
func _rpc_zone_target_requested(_a: int, _b: String, _c: String, _d: bool) -> void: pass
func _rpc_strategy_target_requested(_a: int, _b: String, _c: String) -> void: pass
func _rpc_choice_requested(_a: String, _b: String, _c: String = "[]") -> void: pass
func _rpc_monster_rankup_requested(_a: String, _b: String, _c: String) -> void: pass
func _rpc_effect_zone_highlighted(_a: int, _b: int) -> void: pass
func _rpc_effect_zone_unhighlighted(_a: int, _b: int) -> void: pass
func _rpc_effect_card_highlighted(_a: int, _b: String) -> void: pass
func _rpc_effect_card_unhighlighted(_a: int, _b: String) -> void: pass
func _rpc_receive_game_ended(_a: int, _b: String) -> void: pass
func _rpc_receive_replay(_a: PackedByteArray) -> void: pass
# TODO(M2): real rematch flow on the dedicated server
func _rpc_rematch_requested() -> void: pass
func _rpc_rematch_with_deck(_payload: String) -> void: pass
func _rpc_execute_rematch() -> void: pass
func _rpc_rematch_declined() -> void: pass
