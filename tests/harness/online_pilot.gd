extends Node

## Headful online-match smoke pilot. Parked under /root by OnlinePilot.tscn's
## boot scene so it survives the START scene change into the real GameBoard,
## then plays the match THROUGH the real UI: it presses the actual buttons,
## clicks the actual overlay cards and board slots, so every modal is exercised
## exactly as a mouse player would. Screenshots each modal kind on first
## appearance (SMOKE_SHOT_DIR or --shots=DIR).
##
## Flags (after --):
##   --create | --join          seat role (room code handed off via --codefile)
##   --port=N                   dedicated-server port (default 12191)
##   --seed=N                   RNG seed (joiner offsets by +1)
##   --rematches=N              rematch count after game 1 (default 2)
##   --codefile=PATH            room-code handoff file (default /tmp/gz_pilot_code.txt)
##   --drill=claimwin           joiner quits abruptly mid-game; creator claims win
##   --shots=DIR                screenshot dir (fallback: SMOKE_SHOT_DIR env)
##
## Every exit path prints a grep-able "[Pilot] PASS"/"[Pilot] FAIL" line BEFORE
## quitting — the orchestrator keys off the log line, never the exit code
## (macOS exit can wedge).

const DEFAULT_PORT := 12191
const DEFAULT_CODE_FILE := "/tmp/gz_pilot_code.txt"
const TICK_S := 0.25
const STALL_TIMEOUT_S := 90.0
const TURN_CAP := 100
const DRILL_DROP_ACTIONS := 6
const DRILL_DROP_TIMEOUT_S := 120.0

var is_creator := false
var server_port := DEFAULT_PORT
var rematches_target := 2
var code_file := DEFAULT_CODE_FILE
var drill_claimwin := false
var shot_dir := ""
var global_timeout_s := 1200.0
var rng := RandomNumberGenerator.new()

var board: Node = null
var sel: Node = null
var end_game: Node = null
var session: Node = null

var matches_done := 0
var _busy := false
var _finished := false
var _exiting := false
var _end_panel_seen := false
var _leave_drill_done := false
var _deck_change_done := false
var _claim_pressed := false
var _actions_this_match := 0
var _actions_total := 0
var _fallbacks := 0
var _shots_taken := {}
var _shot_counter := 0
var _start_ms := 0
var _board_hook_ms := 0
var _last_fingerprint := ""
var _last_progress_ms := 0
var _settings_shaped := false
var _final_wait_ticks := 0


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	is_creator = "--create" in args
	var seed_val := 42
	for arg in args:
		if arg.begins_with("--port="):
			server_port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seed="):
			seed_val = int(arg.get_slice("=", 1))
		elif arg.begins_with("--rematches="):
			rematches_target = maxi(0, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--codefile="):
			code_file = arg.get_slice("=", 1)
		elif arg.begins_with("--drill="):
			drill_claimwin = arg.get_slice("=", 1) == "claimwin"
		elif arg.begins_with("--shots="):
			shot_dir = arg.get_slice("=", 1)
	if shot_dir.is_empty():
		shot_dir = OS.get_environment("SMOKE_SHOT_DIR")
	if not shot_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(shot_dir)
	rng.seed = seed_val + (0 if is_creator else 1)
	if drill_claimwin:
		rematches_target = 0
		global_timeout_s = 600.0

	# Runtime-only quiet: bus mute is never persisted (GameSettings fields are
	# deliberately NOT touched — save_reconnect_session() writes the whole cfg).
	AudioServer.set_bus_mute(0, true)
	if GameSettings.use_mobile_layout:
		_log("WARNING: mobile layout is on in settings — board drive assumes desktop")

	if is_creator and FileAccess.file_exists(code_file):
		DirAccess.remove_absolute(code_file)

	NetworkManager.server_host = "127.0.0.1"
	NetworkManager.server_port = server_port
	NetworkManager.server_room_created.connect(_on_room_created)
	NetworkManager.server_seated.connect(_on_seated)
	NetworkManager.server_error.connect(_on_server_error)

	var err: Error = await NetworkManager.connect_to_server()
	if err != OK:
		_fail("connect_to_server failed: %d" % err)
		return
	_log("connected (%s)" % ("creator" if is_creator else "joiner"))

	if is_creator:
		NetworkManager.create_room(false, "")
	else:
		var code := await _wait_for_code_file()
		if code.is_empty():
			_fail("no room code file after timeout")
			return
		NetworkManager.join_room(code)

	var tick := Timer.new()
	tick.wait_time = TICK_S
	tick.timeout.connect(_tick)
	add_child(tick)
	tick.start()


func _log(msg: String) -> void:
	print("[Pilot %s] %s" % ["creator" if is_creator else "joiner", msg])


func _on_room_created(code: String) -> void:
	_log("room created: %s" % code)
	var f := FileAccess.open(code_file, FileAccess.WRITE)
	f.store_string(code)
	f.close()


func _on_server_error(code: String) -> void:
	if _finished or _exiting:
		return
	_fail("server error: %s" % code)


func _wait_for_code_file() -> String:
	for i in range(120):
		if FileAccess.file_exists(code_file):
			var f := FileAccess.open(code_file, FileAccess.READ)
			var code := f.get_as_text().strip_edges()
			f.close()
			if not code.is_empty():
				return code
		await get_tree().create_timer(0.25).timeout
	return ""


## Seat granted: submit a seeded-random VALIDATED deck (user decklists vary in
## legality — the server rejects invalid ones, so filter locally first).
func _on_seated(_room: String, pid: int) -> void:
	var deck := _pick_valid_deck("")
	if deck.is_empty():
		_fail("no valid decklist available")
		return
	DecklistManager.select_deck_for_player(pid, deck)
	NetworkManager.send_deck_to_server(deck)
	_log("seated as player %d, sent deck '%s'" % [pid, deck])


## Random decklist that passes GameModeValidator for the current mode,
## excluding `exclude`. Starter-deck fallback keeps the smoke running even if
## every user deck is off-format.
func _pick_valid_deck(exclude: String) -> String:
	var valid: Array[String] = []
	for deck_name in DecklistManager.get_all_decklists():
		if deck_name == exclude:
			continue
		var data := DecklistManager.load_decklist(deck_name)
		if data.is_empty():
			continue
		var errors := GameModeValidator.validate(
			NetworkManager.game_mode, data.get("monster", []), data.get("main", []))
		if errors.is_empty():
			valid.append(deck_name)
	if valid.is_empty():
		for fallback in ["ESD01 Starter", "ESD02 Starter"]:
			if fallback != exclude and DecklistManager.get_all_decklists().has(fallback):
				return fallback
		return ""
	return valid[rng.randi() % valid.size()]


# --- Tick loop -------------------------------------------------------------

func _tick() -> void:
	if _finished or _busy:
		return
	if Time.get_ticks_msec() - _start_ms > global_timeout_s * 1000.0:
		_fail("global timeout (%ds)" % int(global_timeout_s))
		return

	if board == null or not is_instance_valid(board):
		if _exiting:
			_check_exit_landed()
			return
		var b := get_node_or_null("/root/GameBoard")
		if b != null:
			board = b
			_hook_board()
		return

	_busy = true
	await _ladder()
	_busy = false


func _hook_board() -> void:
	sel = board._selection
	end_game = board._end_game
	session = board.get_node("GameSession")
	_board_hook_ms = Time.get_ticks_msec()
	_last_progress_ms = Time.get_ticks_msec()
	_shape_settings()
	_log("hooked GameBoard (local pid %d)" % board.local_player_id)


## In-memory prompt-settings shaping (tracker dicts are never persisted):
## autos ON so games move; creator keeps draw confirmations OFF-auto so the
## confirmation modal is guaranteed to appear at least once per turn. Retried
## from the ladder until the tracker has seeded its per-player dicts.
func _shape_settings() -> void:
	if _settings_shaped:
		return
	var settings: Array = board._player_settings
	var pid: int = board.local_player_id
	if pid < 0 or pid >= settings.size():
		return
	for key in settings[pid].keys():
		settings[pid][key] = true
	settings[pid]["confirm_main_phase_pass"] = false
	if is_creator:
		settings[pid]["auto_draw"] = false
	_settings_shaped = true


## Post-exit: wait for MainMenu to land, then PASS.
func _check_exit_landed() -> void:
	if get_node_or_null("/root/MainMenu") != null:
		_pass_and_quit()
	elif Time.get_ticks_msec() - _start_ms > global_timeout_s * 1000.0:
		_fail("never reached MainMenu after leaving the board")


# --- Priority ladder -------------------------------------------------------

func _ladder() -> void:
	# Rematch executed: panel hidden while we'd flagged it seen — reset per-match.
	if _end_panel_seen and not board.end_game_panel.visible and not _exiting:
		_end_panel_seen = false
		_actions_this_match = 0
		_log("rematch executing (starting match %d)" % (matches_done + 1))

	_shape_settings()
	await _watchdog()
	if _finished:
		return

	# Claim-win drill, joiner side: die abruptly mid-game (simulated crash).
	if drill_claimwin and not is_creator and not board.end_game_panel.visible:
		var alive_s := (Time.get_ticks_msec() - _board_hook_ms) / 1000.0
		if _actions_total >= DRILL_DROP_ACTIONS or alive_s > DRILL_DROP_TIMEOUT_S:
			_log("PASS (drill: dropping abruptly after %d actions)" % _actions_total)
			_finished = true
			get_tree().quit(0)
			return

	# 1. Reconnect overlay (drill: claim the win once the grace elapses)
	var reconnect: Node = board._reconnect
	if reconnect and reconnect.is_overlay_active():
		await _shot("reconnect_overlay")
		if reconnect._claim_btn and reconnect._claim_btn.visible and not _claim_pressed:
			_claim_pressed = true
			_log("pressing Claim Win")
			reconnect._claim_btn.pressed.emit()
		return

	# 2. End-game panel / rematch machine
	if board.end_game_panel.visible:
		await _handle_end_game()
		return

	# 3. First-player (coin flip) choice
	var fp_container: Node = board.action_panel.get_node_or_null("FirstPlayerContainer")
	if fp_container != null and board._first_player.choosing:
		var buttons: Array = []
		for child in fp_container.get_children():
			if child is Button:
				buttons.append(child)
		if buttons.size() >= 2:
			await _shot("first_player")
			var pick: int = rng.randi() % 2
			_log("first-player choice: %s" % ("go first" if pick == 0 else "go second"))
			buttons[pick].pressed.emit()
		return

	# 4. Deck search overlay
	if board.deck_search_overlay.visible:
		await _shot("deck_search")
		_drive_deck_search()
		return

	# 5. Deck arrange overlay (keep the given order — confirm)
	if board.deck_arrange_overlay.visible:
		await _shot("deck_arrange")
		if not board.deck_arrange_confirm.disabled:
			board.deck_arrange_confirm.pressed.emit()
		return

	# 6. Card select overlay
	if board.card_pool_select_overlay.visible:
		await _shot("card_select")
		await _drive_card_select()
		return

	# 7. Monster rank-up (mandatory pick inside the monster-deck viewer)
	if board.monster_deck_view_overlay.rankup_selecting:
		await _shot("monster_rankup")
		_drive_rankup()
		return

	# 8. Cards revealed (dismiss resolves the effect)
	if board.zone_stack_view_overlay.visible and board.zone_stack_view_overlay._revealed_active:
		await _shot("cards_revealed")
		board.zone_stack_view_overlay.try_close()
		return

	# 9. Choice buttons
	if sel._choice_selecting and not sel._choice_buttons.is_empty():
		await _shot("choice")
		var idx: int = rng.randi() % sel._choice_buttons.size()
		_log("choice: option %d of %d" % [idx, sel._choice_buttons.size()])
		sel._choice_buttons[idx].pressed.emit()
		return

	# 10. Hand discard (multi-select then confirm)
	if sel._discard_selecting:
		await _shot("hand_discard")
		await _drive_hand_discard()
		return

	# 11. Hand card selection (single click resolves; sometimes skip)
	if sel._hand_card_selecting:
		await _shot("hand_card_select")
		_drive_hand_card_select()
		return

	# 12. Zone target
	if sel._zone_target_selecting:
		await _shot("zone_target")
		_drive_zone_target()
		return

	# 13. Multi-zone target (toggle zones then confirm)
	if sel._zones_target_selecting:
		await _shot("zones_target")
		await _drive_zones_target()
		return

	# 14. Strategy target
	if sel._strategy_target_selecting:
		await _shot("strategy_target")
		_drive_strategy_target()
		return

	# 15. Confirmation (draw / next turn) — the board awaits btn_confirm
	if board._awaiting_confirmation and not board.btn_confirm.disabled:
		await _shot("confirmation")
		board.btn_confirm.pressed.emit()
		return

	# 16. Pass confirmation (only if the user's settings enable it)
	if sel._confirming_pass and not board.btn_confirm.disabled:
		board.btn_confirm.pressed.emit()
		return

	# 17. Mid-action leftovers from a previous tick
	if sel.waiting_for_zone_select:
		_finish_zone_placement()
		return
	if sel.waiting_for_card_select:
		await _pick_action_card()
		return

	# 18. Main/counter action context
	if board.btn_end_main.visible and not board.btn_end_main.disabled \
			and not board._action_pending \
			and NetworkManager.is_local_player_turn(board._get_current_pid()):
		await _take_action()
		return


## Stall watchdog: any observable progress resets the clock.
func _watchdog() -> void:
	var log_len: int = board.log_output.get_total_character_count() if board.log_output else 0
	var fingerprint := "%d|%d|%d|%d|%s%s%s%s%s|%s|%d" % [
		matches_done, _actions_total, session.client_turn_number, session.client_current_player_id,
		str(board.deck_search_overlay.visible), str(board.deck_arrange_overlay.visible),
		str(board.card_pool_select_overlay.visible), str(board.end_game_panel.visible),
		str(board.action_prompt_panel.visible),
		str(board.btn_end_main.disabled), log_len,
	]
	var now := Time.get_ticks_msec()
	if fingerprint != _last_fingerprint:
		_last_fingerprint = fingerprint
		_last_progress_ms = now
		return
	if now - _last_progress_ms > STALL_TIMEOUT_S * 1000.0:
		await _shot("stall_%d" % matches_done)
		_fail("stalled %ds; fingerprint=%s busy=%s sel=[cs=%s zs=%s ds=%s hcs=%s zt=%s zst=%s st=%s cp=%s] conf=%s" % [
			int(STALL_TIMEOUT_S), fingerprint, str(_busy),
			str(sel.waiting_for_card_select), str(sel.waiting_for_zone_select),
			str(sel._discard_selecting), str(sel._hand_card_selecting),
			str(sel._zone_target_selecting), str(sel._zones_target_selecting),
			str(sel._strategy_target_selecting), str(sel._choice_selecting),
			str(board._awaiting_confirmation),
		])


# --- Prompt drivers ---------------------------------------------------------

func _selectable_grid_cards(grid: Node) -> Array:
	var out: Array = []
	if grid == null:
		return out
	for child in grid.get_children():
		if "is_selectable" in child and child.is_selectable and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _drive_deck_search() -> void:
	var overlay: Node = board.deck_search_overlay
	var selectable := _selectable_grid_cards(overlay._grid)
	var can_skip: bool = board.deck_search_skip.visible
	if selectable.is_empty() or (can_skip and rng.randf() < 0.2):
		if can_skip:
			_log("deck search: skip")
			board.deck_search_skip.pressed.emit()
			return
	if selectable.is_empty():
		_log("deck search: nothing selectable and no skip — waiting")
		return
	var card: Control = selectable[rng.randi() % selectable.size()]
	_log("deck search: picking %s" % str(card.card_data.get("id", "?")))
	card.card_clicked.emit(card)


func _drive_card_select() -> void:
	var overlay: Node = board.card_pool_select_overlay
	var confirm: Button = board.card_pool_select_confirm
	var iterations := 0
	# The pool grid REBUILDS after every click — re-query children each pass.
	while overlay.visible and confirm.disabled and iterations < 24:
		iterations += 1
		var selectable := _selectable_grid_cards(overlay._pool_grid)
		if selectable.is_empty():
			break
		var card: Control = selectable[rng.randi() % selectable.size()]
		card.card_clicked.emit(card)
		await get_tree().process_frame
		await get_tree().process_frame
	if not overlay.visible:
		return
	if not confirm.disabled:
		_log("card select: confirm after %d picks" % iterations)
		confirm.pressed.emit()
	elif board.card_pool_select_skip.visible:
		_log("card select: skip (confirm never enabled)")
		board.card_pool_select_skip.pressed.emit()


func _drive_rankup() -> void:
	var selectable := _selectable_grid_cards(board.monster_deck_view_overlay._grid)
	if selectable.is_empty():
		return
	var card: Control = selectable[rng.randi() % selectable.size()]
	_log("rank-up: picking %s" % str(card.card_data.get("id", "?")))
	card.card_clicked.emit(card)


func _drive_hand_discard() -> void:
	var pid: int = sel._discard_player_id
	var hand_mgr: Node = board.player1_hand if pid == 0 else board.player2_hand
	var need: int = sel._discard_count
	var picked: Array[int] = []
	var guard := 0
	while board.btn_confirm.disabled and guard < need + 8:
		guard += 1
		var indices: Array = hand_mgr.selectable_indices.duplicate()
		indices.shuffle()
		var clicked := false
		for i in indices:
			if i not in picked:
				picked.append(i)
				hand_mgr.select_card_at(i)
				clicked = true
				break
		if not clicked:
			break
		await get_tree().process_frame
	if not board.btn_confirm.disabled:
		_log("hand discard: confirming %d cards" % picked.size())
		board.btn_confirm.pressed.emit()
	else:
		_log("hand discard: could not fill %d picks (hand of %d) — waiting" % [need, hand_mgr.selectable_indices.size()])


func _drive_hand_card_select() -> void:
	if sel._hand_card_allow_skip and rng.randf() < 0.25:
		_log("hand card select: skip")
		board.btn_confirm.pressed.emit()
		return
	var pid: int = sel._hand_card_player_id
	var hand_mgr: Node = board.player1_hand if pid == 0 else board.player2_hand
	var indices: Array = hand_mgr.selectable_indices
	if indices.is_empty():
		if sel._hand_card_allow_skip:
			board.btn_confirm.pressed.emit()
		return
	_log("hand card select: picking")
	hand_mgr.select_card_at(indices[rng.randi() % indices.size()])


func _drive_zone_target() -> void:
	if sel._zone_target_allow_skip and rng.randf() < 0.2:
		_log("zone target: skip")
		board.btn_confirm.pressed.emit()
		return
	var zones: Array = sel._zone_target_valid_zones
	if zones.is_empty():
		if sel._zone_target_allow_skip:
			board.btn_confirm.pressed.emit()
		return
	var target_board: Control = board.player1_board if sel._zone_target_board_pid == 0 else board.player2_board
	var idx: int = zones[rng.randi() % zones.size()]
	_log("zone target: zone %d on board %d" % [idx + 1, sel._zone_target_board_pid])
	target_board.zone_slots[idx].slot_clicked.emit(idx + 1, sel._zone_target_board_pid)


func _drive_zones_target() -> void:
	var target_board: Control = board.player1_board if sel._zones_target_board_pid == 0 else board.player2_board
	var want: int = sel._zones_target_count
	if sel._zones_target_up_to:
		want = clampi(1 + (rng.randi() % maxi(want, 1)), 1, want)
	var guard := 0
	while sel._zones_target_selected.size() < want and guard < want + 8:
		guard += 1
		var remaining: Array = []
		for z in sel._zones_target_valid_zones:
			if z not in sel._zones_target_selected:
				remaining.append(z)
		if remaining.is_empty():
			break
		var idx: int = remaining[rng.randi() % remaining.size()]
		target_board.zone_slots[idx].slot_clicked.emit(idx + 1, sel._zones_target_board_pid)
		await get_tree().process_frame
	if not board.btn_confirm.disabled:
		_log("zones target: confirming %d zones" % sel._zones_target_selected.size())
		board.btn_confirm.pressed.emit()


func _drive_strategy_target() -> void:
	var indices: Array = sel._strategy_target_valid_indices
	if indices.is_empty():
		return
	var target_board: Control = board.player1_board if sel._strategy_target_board_pid == 0 else board.player2_board
	var idx: int = indices[rng.randi() % indices.size()]
	_log("strategy target: slot %d" % idx)
	# Handler is bound with the strategy index; the two emitted args are unused.
	target_board.strategy_slots[idx].slot_clicked.emit(0, sel._strategy_target_board_pid)


# --- Main-phase / counter actions -------------------------------------------

func _take_action() -> void:
	await _shot("board_midgame_m%d" % (matches_done + 1))

	# Runaway-game valve: concede past the turn cap (creator only, so exactly
	# one side pulls the cord).
	if session.client_turn_number > TURN_CAP and is_creator:
		_log("turn cap reached — conceding")
		board.btn_concede.pressed.emit()
		return

	var playable: Dictionary = board._client_playable
	var candidates: Array = []
	if not board.btn_play_battle.disabled and not playable.get("battle_cards", []).is_empty():
		candidates.append(board.btn_play_battle)
	if not board.btn_play_strategy.disabled and not playable.get("strategy_cards", []).is_empty():
		candidates.append(board.btn_play_strategy)
	if not board.btn_gain_rage.disabled and not playable.get("rage_cards", []).is_empty():
		candidates.append(board.btn_gain_rage)
	if not board.btn_play_monster.disabled and not playable.get("monster_cards", []).is_empty():
		candidates.append(board.btn_play_monster)
	if not board.btn_invade.disabled and not playable.get("invade_cards", []).is_empty():
		candidates.append(board.btn_invade)

	# Rising pass chance so games converge instead of grinding value forever.
	var pass_chance := clampf(0.15 + 0.01 * _actions_this_match, 0.15, 0.9)
	if candidates.is_empty() or rng.randf() < pass_chance:
		board.btn_end_main.pressed.emit()
		_count_action()
		return

	var btn: Button = candidates[rng.randi() % candidates.size()]
	btn.pressed.emit()
	await get_tree().process_frame
	if not sel.waiting_for_card_select:
		# Gated out (turn raced away etc.) — pass next context instead of wedging.
		return
	await _pick_action_card()


func _pick_action_card() -> void:
	var active_board: Control = sel._get_active_player_board()
	if active_board == null or active_board.hand_manager == null:
		sel._on_cancel_pressed()
		return
	var hand_mgr: Node = active_board.hand_manager
	var indices: Array = hand_mgr.selectable_indices
	if indices.is_empty():
		sel._on_cancel_pressed()
		return
	hand_mgr.select_card_at(indices[rng.randi() % indices.size()])
	await get_tree().process_frame
	if sel.waiting_for_zone_select:
		_finish_zone_placement()
	_count_action()


func _finish_zone_placement() -> void:
	var zones: Array = sel._zone_select_valid
	if zones.is_empty():
		sel._on_cancel_pressed()
		return
	var zone: int = zones[rng.randi() % zones.size()]
	if not sel.play_selected_card_to_zone(zone):
		sel._on_cancel_pressed()


func _count_action() -> void:
	_actions_this_match += 1
	_actions_total += 1


# --- End-game / rematch machine ----------------------------------------------

func _handle_end_game() -> void:
	if _exiting:
		return
	if not _end_panel_seen:
		_end_panel_seen = true
		matches_done += 1
		_log("match %d ended (after %d actions this match)" % [matches_done, _actions_this_match])
		await _shot("end_game_panel")

	# Leave-dialog drill: pop the confirm, screenshot, CANCEL (must not leave).
	if is_creator and not _leave_drill_done and not drill_claimwin:
		_leave_drill_done = true
		board._leave_dialog.popup_centered()
		await get_tree().process_frame
		await get_tree().process_frame
		await _shot("leave_dialog")
		board._leave_dialog.get_cancel_button().pressed.emit()
		await get_tree().process_frame
		_log("leave dialog: opened + cancelled")

	# Opponent already left (or disconnect-ended game): capture and exit.
	if not board.btn_rematch.visible:
		await _shot("opponent_left")
		_exit_to_menu()
		return

	if matches_done > rematches_target:
		# Final match done. Joiner leaves first; creator waits for the
		# rematch-declined notice (btn_rematch hides) to screenshot it —
		# UNLESS the opponent is already gone (disconnect end / crash),
		# where no decline will ever arrive. Capped wait as a backstop.
		if is_creator:
			_final_wait_ticks += 1
			if board._game_ended_by_disconnect or not NetworkManager.opponent_connected \
					or _final_wait_ticks > 120:
				_exit_to_menu()
			return
		await get_tree().create_timer(2.0).timeout
		if _finished or _exiting or board == null or not is_instance_valid(board):
			return
		_exit_to_menu()
		return

	if board.btn_rematch.disabled:
		return # Already requested — waiting for the opponent.

	# Deck-change rematch: on the SECOND rematch request the creator swaps
	# decks through the real EndGamePanel deck select.
	if is_creator and matches_done == 2 and not _deck_change_done:
		await _drive_rematch_deck_change()
		_deck_change_done = true

	_log("requesting rematch (%d/%d)" % [matches_done, rematches_target])
	board.btn_rematch.pressed.emit()


func _drive_rematch_deck_change() -> void:
	var rds: Control = end_game.rematch_deck_select
	if rds == null or not rds.visible:
		_log("deck change: rematch deck select not available — skipping")
		return
	var current := DecklistManager.get_player_deck_name(board.local_player_id)
	var target := _pick_valid_deck(current)
	if target.is_empty():
		_log("deck change: no alternative valid deck — skipping")
		return

	# Open the real expanded picker for the screenshot, then select through it.
	var inner: Node = null
	if rds._picker_button != null:
		rds._picker_button.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		await _shot("rematch_deck_select")
		if rds._active_overlay != null:
			inner = _find_deck_list_view(rds._active_overlay, rds)
	if inner != null:
		_log("deck change: '%s' -> '%s' (via picker overlay)" % [current, target])
		inner.deck_selected.emit(target)
	else:
		_fallbacks += 1
		_log("FALLBACK deck change: '%s' -> '%s' (direct select_deck)" % [current, target])
		if rds._active_overlay != null:
			rds._active_overlay.queue_free()
		rds.select_deck(target)
		rds.deck_selected.emit(target)
	await get_tree().process_frame


func _find_deck_list_view(root: Node, exclude: Node) -> Node:
	for child in root.get_children():
		if child != exclude and child.has_method("select_deck") and child.has_signal("deck_selected"):
			return child
		var found := _find_deck_list_view(child, exclude)
		if found != null:
			return found
	return null


func _exit_to_menu() -> void:
	_exiting = true
	_log("leaving to main menu")
	board.btn_end_menu.pressed.emit()


# --- Screenshots / exit ------------------------------------------------------

func _shot(kind: String) -> void:
	if shot_dir.is_empty() or _shots_taken.has(kind):
		return
	_shots_taken[kind] = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shot_counter += 1
	var path := "%s/%s_%02d_%s.png" % [shot_dir, "creator" if is_creator else "joiner", _shot_counter, kind]
	img.save_png(path)
	_log("shot: %s" % path.get_file())


func _pass_and_quit() -> void:
	if _finished:
		return
	_finished = true
	_log("PASS (matches=%d actions=%d shots=%d fallbacks=%d)" % [
		matches_done, _actions_total, _shot_counter, _fallbacks])
	get_tree().quit(0)


func _fail(msg: String) -> void:
	if _finished:
		return
	_finished = true
	_log("FAIL: %s" % msg)
	get_tree().quit(1)
