class_name SystemMenuController
extends Node
## System-menu buttons: sound/music toggles, bug report, log export, save game, concede, return to main menu.
## Method bodies moved verbatim from game_board.gd (Phase 8 split);
## remaining board state/methods are reached via `_board`. The board
## keeps one-line delegates, so call sites, signal connections, and the
## session-layer `_board.*` contract are unchanged.

var _board: GameBoard

var _save_game_button: Button


func _ready() -> void:
	_board = get_parent() as GameBoard


func _setup_save_button() -> void:
	_save_game_button = Button.new()
	_save_game_button.text = tr("STR_GB_SAVE_GAME")
	_save_game_button.custom_minimum_size = Vector2(120, 36)
	_save_game_button.add_theme_font_size_override("font_size", 14)
	_save_game_button.pressed.connect(_board._on_save_game_pressed)
	_board.add_child(_save_game_button)
	# Position below concede button
	_save_game_button.position = Vector2(10, 90)


func _on_save_game_pressed() -> void:
	if not _board.turn_manager or not _board.turn_manager.game_state:
		return
	SfxManager.play("ui_click")
	var mode_str: String
	match NetworkManager.mode:
		NetworkManager.Mode.SOLO: mode_str = "solo"
		NetworkManager.Mode.SOLO_BOT: mode_str = "solo_bot"
		_: mode_str = "solo"
	var diff_str: String = BotConfig.Difficulty.keys()[NetworkManager.bot_difficulty] if _board.is_bot_game else ""
	var d_names: Array[String] = [
		DecklistManager.get_player_deck_name(0),
		DecklistManager.get_player_deck_name(1),
	]
	# Capture a seed from the current RNG state so loading this save produces
	# deterministic bot behavior (the original seed is stale — RNG has advanced).
	var save_seed: int = randi()
	print("[Save] Capturing game_seed=%d for save file" % save_seed)
	var data := GameSerializer.serialize_game_state(_board.turn_manager.game_state, _board._first_player_id, mode_str, diff_str, d_names, save_seed, _board.turn_manager.effect_handler)
	var path := GameSerializer.save_game_to_file(data)
	if not path.is_empty():
		_save_game_button.text = tr("STR_GB_SAVED")
		_save_game_button.disabled = true
		# Re-enable after 2 seconds
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(_save_game_button):
				_save_game_button.text = tr("STR_GB_SAVE_GAME")
				_save_game_button.disabled = false
		)


func _on_sound_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			GameSettings.sound_volume = (GameSettings.sound_volume + 1) % 5
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			GameSettings.sound_volume = (GameSettings.sound_volume + 4) % 5
		else:
			return
		GameSettings.save()
		_board._update_sound_button_text()
		SfxManager.play("ui_click")


func _on_sound_toggle_pressed() -> void:
	GameSettings.sound_volume = (GameSettings.sound_volume + 1) % 5
	GameSettings.save()
	_board._update_sound_button_text()


func _update_sound_button_text() -> void:
	var label: String = tr("STR_GB_SOUND_FMT").replace("{VAL}", tr(_board._VOLUME_VALUE_KEYS[GameSettings.sound_volume]))
	if _board.btn_sound_toggle:
		_board.btn_sound_toggle.text = label
	if _board._mobile._mobile_sound_button:
		_board._mobile._mobile_sound_button.text = label


# --- Music toggle ---


func _on_music_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			GameSettings.music_volume = (GameSettings.music_volume + 1) % 5
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			GameSettings.music_volume = (GameSettings.music_volume + 4) % 5
		else:
			return
		SfxManager.play("ui_click")
		GameSettings.save()
		MusicManager.set_volume(GameSettings.music_volume)
		_board._update_music_button_text()


func _on_music_toggle_pressed() -> void:
	GameSettings.music_volume = (GameSettings.music_volume + 1) % 5
	GameSettings.save()
	MusicManager.set_volume(GameSettings.music_volume)
	_board._update_music_button_text()


func _update_music_button_text() -> void:
	var label: String = tr("STR_GB_MUSIC_FMT").replace("{VAL}", tr(_board._VOLUME_VALUE_KEYS[GameSettings.music_volume]))
	if _board.btn_music_toggle:
		_board.btn_music_toggle.text = label
	if _board._mobile._mobile_music_button:
		_board._mobile._mobile_music_button.text = label


# --- Bug report ---


func _on_bug_report_pressed() -> void:
	var body := _board._build_bug_report_body()
	var url := "https://github.com/hunterdurbin/godzilla-sim/issues/new?labels=bug&title=Bug+Report&body=" + body.uri_encode()
	OS.shell_open(url)


func _build_bug_report_body() -> String:
	return BugReport.build_body(_board)


# --- Export game log ---


func _on_export_log_pressed() -> void:
	SfxManager.play("ui_click")
	var path := GameLogExport.export_log(_board._log_tokens)
	if path.is_empty():
		_board._log_chat.append_remote_entry("STR_LOG_EXPORT_FAILED")
		return
	# Local-only notification: append_remote_entry never enters the MP
	# broadcast buffer, so the opponent's log is unaffected.
	_board._log_chat.append_remote_entry(GameLog.log_exported(_board.local_player_id, path.get_file()))


# --- Concede / Main Menu ---


func _on_concede_pressed() -> void:
	_board._end_game.on_concede_pressed()


func _on_main_menu_pressed() -> void:
	_board._reconnect.hide_overlay()
	# Lobby-bot mode: keep the relay alive and return to PublicLobby instead of MainMenu.
	if _board._is_lobby_bot:
		NetworkManager.exit_lobby_bot_game()
		NetworkManager.change_scene("res://scenes/lobby/PublicLobby.tscn")
		return
	if _board.is_multiplayer_game:
		var connected := multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		if _board.end_game_panel.visible:
			# Game already over — notify rematch declined
			if connected:
				RpcLogger.log_send("rematch_declined", 0)
				_board._sync._rpc_rematch_declined.rpc()
		elif connected and _board.turn_manager and not _board.turn_manager.is_game_over:
			# Mid-game exit counts as concession
			if NetworkManager.is_host():
				var loser_id := _board.local_player_id
				var winner_id := 1 - loser_id
				_board.turn_manager._on_game_over(winner_id, GameLog.concede_reason_key(loser_id))
			else:
				RpcLogger.log_send("concede", 0)
				_board._sync._rpc_concede.rpc_id(NetworkManager.host_peer_id)
		GameSettings.clear_reconnect_session()
		NetworkManager.is_in_game = false
		NetworkManager.disconnect_game()
	NetworkManager.change_scene("res://scenes/menus/MainMenu.tscn")
