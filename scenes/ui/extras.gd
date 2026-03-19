extends Control

@onready var watch_replay_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/WatchReplayButton
@onready var load_game_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/LoadGameButton
@onready var back_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	watch_replay_button.pressed.connect(_on_watch_replay_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")


func _on_watch_replay_pressed() -> void:
	SfxManager.play("ui_click")
	var replays := ReplayData.list_replays()
	if replays.is_empty():
		_show_message("No replays found.")
		return
	_show_replay_list(replays)


func _on_load_game_pressed() -> void:
	SfxManager.play("ui_click")
	var saves := GameSerializer.list_saves()
	if saves.is_empty():
		_show_message("No saved games found.")
		return
	_show_save_list(saves)


func _show_message(text: String) -> void:
	var popup := PopupPanel.new()
	popup.exclusive = true
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 1.0)
	panel_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(label)

	var ok_btn := Button.new()
	ok_btn.text = "OK"
	ok_btn.custom_minimum_size = Vector2(120, 40)
	ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok_btn.add_theme_font_size_override("font_size", 18)
	ok_btn.pressed.connect(func(): popup.hide())
	vbox.add_child(ok_btn)

	margin.add_child(vbox)
	panel.add_child(margin)
	popup.add_child(panel)
	add_child(popup)
	popup.popup_centered()


func _show_replay_list(replays: Array[Dictionary]) -> void:
	var popup := PopupPanel.new()
	popup.exclusive = true

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 1.0)
	panel_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Select Replay"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.1, 1))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	var list_vbox := VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 8)
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for entry in replays:
		var btn := Button.new()
		var names: Array = entry.get("player_names", ["?", "?"])
		var winner: int = entry.get("winner_id", -1)
		var winner_name: String = str(names[winner]) if winner >= 0 and winner < names.size() else "?"
		var turns: int = entry.get("turns", 0)
		var ts: String = entry.get("timestamp", "")
		var decks: Array = entry.get("deck_names", ["", ""])
		var deck_info := ""
		if not str(decks[0]).is_empty() or not str(decks[1]).is_empty():
			deck_info = "\n%s vs %s" % [str(decks[0]), str(decks[1])]
		btn.text = "%s  |  %s vs %s  |  %d turns  |  Winner: %s%s" % [ts, names[0], names[1], turns, winner_name, deck_info]
		btn.custom_minimum_size = Vector2(460, 50)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 14)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var path: String = entry["path"]
		btn.pressed.connect(func():
			SfxManager.play("ui_click")
			popup.hide()
			_launch_replay(path)
		)
		list_vbox.add_child(btn)

	scroll.add_child(list_vbox)
	vbox.add_child(scroll)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(200, 40)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.add_theme_font_size_override("font_size", 18)
	cancel_btn.pressed.connect(func(): SfxManager.play("ui_click"); popup.hide())
	vbox.add_child(cancel_btn)

	margin.add_child(vbox)
	panel.add_child(margin)
	popup.add_child(panel)
	add_child(popup)
	popup.popup_centered()


func _launch_replay(path: String) -> void:
	var replay := ReplayData.load_from_file(path)
	if not replay:
		_show_message("Failed to load replay.")
		return
	ReplayData.pending_replay = replay
	NetworkManager.change_scene("res://scenes/ui/ReplayViewer.tscn")


func _show_save_list(saves: Array[Dictionary]) -> void:
	var popup := PopupPanel.new()
	popup.exclusive = true

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 1.0)
	panel_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Load Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.1, 1))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	var list_vbox := VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 8)
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for entry in saves:
		var btn := Button.new()
		var names: Array = entry.get("player_names", ["?", "?"])
		var turn: int = entry.get("turn_number", 0)
		var ts: String = entry.get("timestamp", "")
		var mode: String = entry.get("mode", "")
		btn.text = "%s  |  %s vs %s  |  Turn %d  |  %s" % [ts, names[0], names[1], turn, mode]
		btn.custom_minimum_size = Vector2(460, 45)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 14)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var path: String = entry["path"]
		btn.pressed.connect(func():
			SfxManager.play("ui_click")
			popup.hide()
			_launch_load_game(path)
		)
		list_vbox.add_child(btn)

	scroll.add_child(list_vbox)
	vbox.add_child(scroll)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(200, 40)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.add_theme_font_size_override("font_size", 18)
	cancel_btn.pressed.connect(func(): SfxManager.play("ui_click"); popup.hide())
	vbox.add_child(cancel_btn)

	margin.add_child(vbox)
	panel.add_child(margin)
	popup.add_child(panel)
	add_child(popup)
	popup.popup_centered()


func _launch_load_game(path: String) -> void:
	var data := GameSerializer.load_save_file(path)
	if data.is_empty():
		_show_message("Failed to load save file.")
		return
	GameSerializer.pending_load = data
	# Set network mode based on saved game mode
	var mode: String = data.get("mode", "solo")
	match mode:
		"solo": NetworkManager.mode = NetworkManager.Mode.SOLO
		"solo_bot":
			NetworkManager.mode = NetworkManager.Mode.SOLO_BOT
			var diff_str: String = data.get("bot_difficulty", "NORMAL")
			var diff := BotConfig.Difficulty.NORMAL
			match diff_str:
				"EASY": diff = BotConfig.Difficulty.EASY
				"HARD": diff = BotConfig.Difficulty.HARD
			NetworkManager.set_bot_difficulty(diff)
		_: NetworkManager.mode = NetworkManager.Mode.SOLO
	NetworkManager.local_player_id = 0
	NetworkManager.change_scene("res://scenes/board/GameBoard.tscn")
