extends Control

@onready var watch_replay_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/WatchReplayButton
@onready var load_game_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/LoadGameButton
@onready var back_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton

var _replay_popup: PopupPanel = null
var _replay_list_vbox: VBoxContainer = null
var _replay_count_label: Label = null
var _filter_favorites_only: bool = false
var _filter_current_version: bool = false
var _all_replays: Array[Dictionary] = []

var _save_popup: PopupPanel = null
var _save_list_vbox: VBoxContainer = null
var _save_count_label: Label = null
var _save_filter_favorites_only: bool = false
var _save_filter_current_version: bool = false


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
	_filter_favorites_only = false
	_filter_current_version = false

	var popup := PopupPanel.new()
	popup.exclusive = true
	_replay_popup = popup

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 0)
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

	# Toolbar row
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)

	var open_folder_btn := Button.new()
	open_folder_btn.text = "Open Folder"
	open_folder_btn.custom_minimum_size = Vector2(110, 32)
	open_folder_btn.add_theme_font_size_override("font_size", 14)
	open_folder_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		OS.shell_open(ReplayData.get_replay_base_dir())
	)
	toolbar.add_child(open_folder_btn)

	var delete_all_btn := Button.new()
	delete_all_btn.text = "Delete All Recent"
	delete_all_btn.custom_minimum_size = Vector2(140, 32)
	delete_all_btn.add_theme_font_size_override("font_size", 14)
	delete_all_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	delete_all_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		_show_confirm("Delete all non-favorited replays?", func():
			ReplayData.delete_all_recent()
			_refresh_replay_list()
		)
	)
	toolbar.add_child(delete_all_btn)

	var fav_filter_btn := Button.new()
	fav_filter_btn.text = "Favorites Only"
	fav_filter_btn.toggle_mode = true
	fav_filter_btn.custom_minimum_size = Vector2(120, 32)
	fav_filter_btn.add_theme_font_size_override("font_size", 14)
	fav_filter_btn.toggled.connect(func(on: bool):
		SfxManager.play("ui_click")
		_filter_favorites_only = on
		_refresh_replay_list()
	)
	toolbar.add_child(fav_filter_btn)

	var ver_filter_btn := Button.new()
	ver_filter_btn.text = "Current Version"
	ver_filter_btn.toggle_mode = true
	ver_filter_btn.custom_minimum_size = Vector2(130, 32)
	ver_filter_btn.add_theme_font_size_override("font_size", 14)
	ver_filter_btn.toggled.connect(func(on: bool):
		SfxManager.play("ui_click")
		_filter_current_version = on
		_refresh_replay_list()
	)
	toolbar.add_child(ver_filter_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_replay_count_label = Label.new()
	_replay_count_label.add_theme_font_size_override("font_size", 14)
	_replay_count_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	toolbar.add_child(_replay_count_label)

	vbox.add_child(toolbar)

	# Scroll area
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 350)
	_replay_list_vbox = VBoxContainer.new()
	_replay_list_vbox.add_theme_constant_override("separation", 6)
	_replay_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	scroll.add_child(_replay_list_vbox)
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

	_populate_replay_list(replays)
	popup.popup_centered()


func _populate_replay_list(replays: Array[Dictionary]) -> void:
	_all_replays = replays

	var current_ver := ReplayData._get_game_version()

	# Apply filters
	var filtered: Array[Dictionary] = []
	for e in replays:
		if _filter_favorites_only and not e.get("is_favorite", false):
			continue
		if _filter_current_version and e.get("game_version", "") != current_ver:
			continue
		filtered.append(e)

	# Update count label
	var fav_count := 0
	for e in replays:
		if e.get("is_favorite", false):
			fav_count += 1
	_replay_count_label.text = "%d shown / %d total (%d favorited)" % [filtered.size(), replays.size(), fav_count]

	# Clear existing rows
	for child in _replay_list_vbox.get_children():
		child.queue_free()

	for entry in filtered:
		_replay_list_vbox.add_child(_build_replay_row(entry, current_ver))


func _build_replay_row(entry: Dictionary, current_ver: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	# Star button (favorite toggle)
	var is_fav: bool = entry.get("is_favorite", false)
	var star_btn := Button.new()
	star_btn.custom_minimum_size = Vector2(30, 30)
	star_btn.text = "*" if is_fav else "."
	star_btn.add_theme_font_size_override("font_size", 18)
	if is_fav:
		star_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	else:
		star_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	var path: String = entry["path"]
	star_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		ReplayData.toggle_favorite(path)
		_refresh_replay_list()
	)
	row.add_child(star_btn)

	# Info button — click to launch replay
	var info_btn := Button.new()
	info_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_btn.custom_minimum_size = Vector2(0, 44)
	info_btn.add_theme_font_size_override("font_size", 13)
	info_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var names: Array = entry.get("player_names", ["?", "?"])
	var winner: int = entry.get("winner_id", -1)
	var winner_name: String = str(names[winner]) if winner >= 0 and winner < names.size() else "?"
	var turns: int = entry.get("turns", 0)
	var ts: String = entry.get("timestamp", "")
	var decks: Array = entry.get("deck_names", ["", ""])
	var lbl: String = entry.get("label", "")
	var ver: String = entry.get("game_version", "")

	var line1 := ""
	if not lbl.is_empty():
		line1 = "[%s] " % lbl
	line1 += "%s  |  %s vs %s  |  %d turns  |  Winner: %s" % [ts, names[0], names[1], turns, winner_name]
	if not ver.is_empty() and ver != current_ver:
		line1 += "  (v%s)" % ver

	var line2 := ""
	if not str(decks[0]).is_empty() or not str(decks[1]).is_empty():
		line2 = "%s vs %s" % [str(decks[0]), str(decks[1])]

	info_btn.text = line1 if line2.is_empty() else line1 + "\n" + line2
	info_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		_replay_popup.hide()
		_launch_replay(path)
	)
	row.add_child(info_btn)

	# Label button
	var label_btn := Button.new()
	label_btn.text = "Label"
	label_btn.custom_minimum_size = Vector2(50, 30)
	label_btn.add_theme_font_size_override("font_size", 12)
	label_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		_show_label_dialog(path, lbl)
	)
	row.add_child(label_btn)

	# Delete button
	var del_btn := Button.new()
	del_btn.text = "X"
	del_btn.custom_minimum_size = Vector2(30, 30)
	del_btn.add_theme_font_size_override("font_size", 14)
	del_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	del_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		_show_confirm("Delete this replay?", func():
			ReplayData.delete_replay(path)
			_refresh_replay_list()
		)
	)
	row.add_child(del_btn)

	return row


func _refresh_replay_list() -> void:
	# Re-query when data changed (delete/favorite/label), reuse cache for filter-only changes
	var replays := ReplayData.list_replays()
	if replays.is_empty() and _replay_popup:
		_replay_popup.hide()
		_show_message("No replays found.")
		return
	_populate_replay_list(replays)


func _show_label_dialog(path: String, current_label: String) -> void:
	var popup := PopupPanel.new()
	popup.exclusive = true

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.12, 0.15, 1.0)
	ps.border_color = Color(0.3, 0.3, 0.35, 1.0)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", ps)

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 20)
	mg.add_theme_constant_override("margin_top", 20)
	mg.add_theme_constant_override("margin_right", 20)
	mg.add_theme_constant_override("margin_bottom", 20)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)

	var lbl := Label.new()
	lbl.text = "Set Label"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	vb.add_child(lbl)

	var line_edit := LineEdit.new()
	line_edit.text = current_label
	line_edit.placeholder_text = "Enter label..."
	line_edit.custom_minimum_size = Vector2(300, 36)
	line_edit.add_theme_font_size_override("font_size", 16)
	vb.add_child(line_edit)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 36)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.pressed.connect(func(): SfxManager.play("ui_click"); popup.hide())
	btn_row.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size = Vector2(100, 36)
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		ReplayData.update_label(path, line_edit.text.strip_edges())
		popup.hide()
		_refresh_replay_list()
	)
	btn_row.add_child(save_btn)

	vb.add_child(btn_row)
	mg.add_child(vb)
	panel.add_child(mg)
	popup.add_child(panel)
	add_child(popup)
	popup.popup_centered()
	line_edit.grab_focus()


func _show_confirm(text: String, on_confirm: Callable) -> void:
	var popup := PopupPanel.new()
	popup.exclusive = true

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.12, 0.15, 1.0)
	ps.border_color = Color(0.3, 0.3, 0.35, 1.0)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", ps)

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 24)
	mg.add_theme_constant_override("margin_top", 24)
	mg.add_theme_constant_override("margin_right", 24)
	mg.add_theme_constant_override("margin_bottom", 24)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	vb.add_child(lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 36)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.pressed.connect(func(): SfxManager.play("ui_click"); popup.hide())
	btn_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm"
	confirm_btn.custom_minimum_size = Vector2(100, 36)
	confirm_btn.add_theme_font_size_override("font_size", 16)
	confirm_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	confirm_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		popup.hide()
		on_confirm.call()
	)
	btn_row.add_child(confirm_btn)

	vb.add_child(btn_row)
	mg.add_child(vb)
	panel.add_child(mg)
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
	_save_filter_favorites_only = false
	_save_filter_current_version = false

	var popup := PopupPanel.new()
	popup.exclusive = true
	_save_popup = popup

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 0)
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

	# Toolbar row
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)

	var open_folder_btn := Button.new()
	open_folder_btn.text = "Open Folder"
	open_folder_btn.custom_minimum_size = Vector2(110, 32)
	open_folder_btn.add_theme_font_size_override("font_size", 14)
	open_folder_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		OS.shell_open(GameSerializer.get_save_base_dir())
	)
	toolbar.add_child(open_folder_btn)

	var delete_all_btn := Button.new()
	delete_all_btn.text = "Delete All Recent"
	delete_all_btn.custom_minimum_size = Vector2(140, 32)
	delete_all_btn.add_theme_font_size_override("font_size", 14)
	delete_all_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	delete_all_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		_show_confirm("Delete all non-favorited saves?", func():
			GameSerializer.delete_all_recent_saves()
			_refresh_save_list()
		)
	)
	toolbar.add_child(delete_all_btn)

	var fav_filter_btn := Button.new()
	fav_filter_btn.text = "Favorites Only"
	fav_filter_btn.toggle_mode = true
	fav_filter_btn.custom_minimum_size = Vector2(120, 32)
	fav_filter_btn.add_theme_font_size_override("font_size", 14)
	fav_filter_btn.toggled.connect(func(on: bool):
		SfxManager.play("ui_click")
		_save_filter_favorites_only = on
		_refresh_save_list()
	)
	toolbar.add_child(fav_filter_btn)

	var ver_filter_btn := Button.new()
	ver_filter_btn.text = "Current Version"
	ver_filter_btn.toggle_mode = true
	ver_filter_btn.custom_minimum_size = Vector2(130, 32)
	ver_filter_btn.add_theme_font_size_override("font_size", 14)
	ver_filter_btn.toggled.connect(func(on: bool):
		SfxManager.play("ui_click")
		_save_filter_current_version = on
		_refresh_save_list()
	)
	toolbar.add_child(ver_filter_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_save_count_label = Label.new()
	_save_count_label.add_theme_font_size_override("font_size", 14)
	_save_count_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	toolbar.add_child(_save_count_label)

	vbox.add_child(toolbar)

	# Scroll area
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 350)
	_save_list_vbox = VBoxContainer.new()
	_save_list_vbox.add_theme_constant_override("separation", 6)
	_save_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	scroll.add_child(_save_list_vbox)
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

	_populate_save_list(saves)
	popup.popup_centered()


func _populate_save_list(saves: Array[Dictionary]) -> void:
	var current_ver := GameSerializer._get_game_version()

	# Apply filters
	var filtered: Array[Dictionary] = []
	for e in saves:
		if _save_filter_favorites_only and not e.get("is_favorite", false):
			continue
		if _save_filter_current_version and e.get("game_version", "") != current_ver:
			continue
		filtered.append(e)

	# Update count label
	var fav_count := 0
	for e in saves:
		if e.get("is_favorite", false):
			fav_count += 1
	_save_count_label.text = "%d shown / %d total (%d favorited)" % [filtered.size(), saves.size(), fav_count]

	# Clear existing rows
	for child in _save_list_vbox.get_children():
		child.queue_free()

	for entry in filtered:
		_save_list_vbox.add_child(_build_save_row(entry, current_ver))


func _build_save_row(entry: Dictionary, current_ver: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	# Star button (favorite toggle)
	var is_fav: bool = entry.get("is_favorite", false)
	var star_btn := Button.new()
	star_btn.custom_minimum_size = Vector2(30, 30)
	star_btn.text = "*" if is_fav else "."
	star_btn.add_theme_font_size_override("font_size", 18)
	if is_fav:
		star_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	else:
		star_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	var path: String = entry["path"]
	star_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		GameSerializer.toggle_save_favorite(path)
		_refresh_save_list()
	)
	row.add_child(star_btn)

	# Info button — click to load game
	var info_btn := Button.new()
	info_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_btn.custom_minimum_size = Vector2(0, 44)
	info_btn.add_theme_font_size_override("font_size", 13)
	info_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var names: Array = entry.get("player_names", ["?", "?"])
	var turn: int = entry.get("turn_number", 0)
	var ts: String = entry.get("timestamp", "")
	var mode: String = entry.get("mode", "")
	var lbl: String = entry.get("label", "")
	var ver: String = entry.get("game_version", "")
	var decks: Array = entry.get("deck_names", ["", ""])

	var line1 := ""
	if not lbl.is_empty():
		line1 = "[%s] " % lbl
	line1 += "%s  |  %s vs %s  |  Turn %d  |  %s" % [ts, names[0], names[1], turn, mode]
	if not ver.is_empty() and ver != current_ver:
		line1 += "  (v%s)" % ver

	var line2 := ""
	if not str(decks[0]).is_empty() or not str(decks[1]).is_empty():
		line2 = "%s vs %s" % [str(decks[0]), str(decks[1])]

	info_btn.text = line1 if line2.is_empty() else line1 + "\n" + line2
	info_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		_save_popup.hide()
		_launch_load_game(path)
	)
	row.add_child(info_btn)

	# Label button
	var label_btn := Button.new()
	label_btn.text = "Label"
	label_btn.custom_minimum_size = Vector2(50, 30)
	label_btn.add_theme_font_size_override("font_size", 12)
	label_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		_show_save_label_dialog(path, lbl)
	)
	row.add_child(label_btn)

	# Delete button
	var del_btn := Button.new()
	del_btn.text = "X"
	del_btn.custom_minimum_size = Vector2(30, 30)
	del_btn.add_theme_font_size_override("font_size", 14)
	del_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	del_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		_show_confirm("Delete this save?", func():
			GameSerializer.delete_save(path)
			_refresh_save_list()
		)
	)
	row.add_child(del_btn)

	return row


func _refresh_save_list() -> void:
	var saves := GameSerializer.list_saves()
	if saves.is_empty() and _save_popup:
		_save_popup.hide()
		_show_message("No saved games found.")
		return
	_populate_save_list(saves)


func _show_save_label_dialog(path: String, current_label: String) -> void:
	var popup := PopupPanel.new()
	popup.exclusive = true

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.12, 0.15, 1.0)
	ps.border_color = Color(0.3, 0.3, 0.35, 1.0)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", ps)

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 20)
	mg.add_theme_constant_override("margin_top", 20)
	mg.add_theme_constant_override("margin_right", 20)
	mg.add_theme_constant_override("margin_bottom", 20)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)

	var lbl := Label.new()
	lbl.text = "Set Label"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	vb.add_child(lbl)

	var line_edit := LineEdit.new()
	line_edit.text = current_label
	line_edit.placeholder_text = "Enter label..."
	line_edit.custom_minimum_size = Vector2(300, 36)
	line_edit.add_theme_font_size_override("font_size", 16)
	vb.add_child(line_edit)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 36)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.pressed.connect(func(): SfxManager.play("ui_click"); popup.hide())
	btn_row.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size = Vector2(100, 36)
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		GameSerializer.update_save_label(path, line_edit.text.strip_edges())
		popup.hide()
		_refresh_save_list()
	)
	btn_row.add_child(save_btn)

	vb.add_child(btn_row)
	mg.add_child(vb)
	panel.add_child(mg)
	popup.add_child(panel)
	add_child(popup)
	popup.popup_centered()
	line_edit.grab_focus()


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
