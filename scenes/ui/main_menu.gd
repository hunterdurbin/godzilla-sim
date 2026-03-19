extends Control


@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var solo_bot_button: Button = $CenterContainer/VBoxContainer/SoloBotButton
@onready var lan_button: Button = $CenterContainer/VBoxContainer/LanButton
@onready var online_button: Button = $CenterContainer/VBoxContainer/OnlineButton
@onready var deck_builder_button: Button = $CenterContainer/VBoxContainer/DeckBuilderButton
@onready var extras_button: Button = $ExtrasButton
@onready var options_button: Button = $OptionsButton
@onready var sound_button: Button = $SoundButton
@onready var music_button: Button = $MusicButton
@onready var patreon_button: TextureButton = $PatreonButton
@onready var version_label: Label = $VersionLabel
@onready var update_button: Button = $UpdateButton
@onready var deck_select_p1: VBoxContainer = $CenterContainer/VBoxContainer/DeckRow/DeckSelectP1
@onready var deck_select_p2: VBoxContainer = $CenterContainer/VBoxContainer/DeckRow/DeckSelectP2

var _p1_ready: bool = false
var _p2_ready: bool = false


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	start_button.disabled = true
	solo_bot_button.pressed.connect(_on_solo_bot_pressed)
	solo_bot_button.disabled = true
	lan_button.pressed.connect(_on_lan_pressed)
	online_button.pressed.connect(_on_online_pressed)
	deck_builder_button.pressed.connect(_on_deck_builder_pressed)
	extras_button.pressed.connect(_on_extras_pressed)
	options_button.pressed.connect(_on_options_pressed)
	sound_button.gui_input.connect(_on_sound_gui_input)
	music_button.gui_input.connect(_on_music_gui_input)
	_update_sound_button()
	_update_music_button()
	patreon_button.pressed.connect(_on_patreon_pressed)

	version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "")

	# Check for updates
	update_button.visible = false
	UpdateChecker.update_available.connect(_on_update_available)
	if not UpdateChecker.pending_update.is_empty():
		var u := UpdateChecker.pending_update
		_on_update_available(u["current"], u["new_version"], u["download_url"], u["release_url"])

	DecklistManager.clear_selections()

	deck_select_p1.set_header("PLAYER 1 DECK")
	deck_select_p2.set_header("PLAYER 2 DECK")

	deck_select_p1.deck_selected.connect(_on_p1_deck_selected)
	deck_select_p2.deck_selected.connect(_on_p2_deck_selected)

	# DeckSelect's _ready fires before ours, so it may have already selected a deck
	if not deck_select_p1.current_selection.is_empty():
		_on_p1_deck_selected(deck_select_p1.current_selection)
	if not deck_select_p2.current_selection.is_empty():
		_on_p2_deck_selected(deck_select_p2.current_selection)

	# Check for saved reconnect session (client only — host has no saved game state after restart)
	if GameSettings.has_valid_reconnect_session() and not GameSettings.reconnect_is_host:
		_show_reconnect_dialog()


func _on_p1_deck_selected(deck_name: String) -> void:
	_p1_ready = not deck_name.is_empty() and DecklistManager.select_deck_for_player(0, deck_name)
	_update_start_button()


func _on_p2_deck_selected(deck_name: String) -> void:
	_p2_ready = not deck_name.is_empty() and DecklistManager.select_deck_for_player(1, deck_name)
	_update_start_button()


func _update_start_button() -> void:
	start_button.disabled = not (_p1_ready and _p2_ready)
	solo_bot_button.disabled = not (_p1_ready and _p2_ready)
	if not start_button.disabled:
		start_button.grab_focus()


func _on_start_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.mode = NetworkManager.Mode.SOLO
	NetworkManager.change_scene("res://scenes/board/GameBoard.tscn")


func _on_solo_bot_pressed() -> void:
	SfxManager.play("ui_click")
	_show_difficulty_popup()


func _show_difficulty_popup() -> void:
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

	var title := Label.new()
	title.text = "Bot Difficulty"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.1, 1))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Seed input (debug: paste a seed number to replay an exact game)
	var seed_row := HBoxContainer.new()
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var seed_label := Label.new()
	seed_label.text = "Seed:"
	seed_label.add_theme_font_size_override("font_size", 16)
	seed_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	seed_row.add_child(seed_label)
	var seed_input := LineEdit.new()
	seed_input.placeholder_text = "random"
	seed_input.custom_minimum_size = Vector2(160, 0)
	seed_input.add_theme_font_size_override("font_size", 16)
	seed_row.add_child(seed_input)
	vbox.add_child(seed_row)

	# Action speed slider
	var speed_row := VBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	var speed_label := Label.new()
	speed_label.text = "Bot Speed: Automatic"
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.add_theme_font_size_override("font_size", 16)
	speed_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	speed_row.add_child(speed_label)
	var speed_slider := HSlider.new()
	speed_slider.min_value = 0
	speed_slider.max_value = 10
	speed_slider.step = 1
	speed_slider.value = 0
	speed_slider.custom_minimum_size = Vector2(280, 0)
	speed_slider.value_changed.connect(func(val: float):
		if val == 0:
			speed_label.text = "Bot Speed: Automatic"
		else:
			speed_label.text = "Bot Speed: %.1fs" % (val * 0.1)
	)
	speed_row.add_child(speed_slider)
	vbox.add_child(speed_row)

	# Playstyle slider
	var playstyle_row := VBoxContainer.new()
	playstyle_row.add_theme_constant_override("separation", 4)
	var playstyle_label := Label.new()
	playstyle_label.text = "Playstyle: Automatic"
	playstyle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playstyle_label.add_theme_font_size_override("font_size", 16)
	playstyle_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	playstyle_row.add_child(playstyle_label)
	var playstyle_names := ["Automatic", "Invasion", "Counter", "Balanced"]
	var playstyle_slider := HSlider.new()
	playstyle_slider.min_value = 0
	playstyle_slider.max_value = 3
	playstyle_slider.step = 1
	playstyle_slider.value = 0
	playstyle_slider.custom_minimum_size = Vector2(280, 0)
	playstyle_slider.value_changed.connect(func(val: float):
		playstyle_label.text = "Playstyle: %s" % playstyle_names[int(val)]
	)
	playstyle_row.add_child(playstyle_slider)
	vbox.add_child(playstyle_row)

	vbox.add_child(HSeparator.new())

	var btn_box := VBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 8)

	var difficulties: Array = [
		["Easy", BotConfig.Difficulty.EASY, Color(0.3, 0.8, 0.3)],
		["Normal", BotConfig.Difficulty.NORMAL, Color(0.9, 0.7, 0.1)],
		["Hard", BotConfig.Difficulty.HARD, Color(0.9, 0.3, 0.1)],
	]

	for entry in difficulties:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(200, 45)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", 22)
		btn.add_theme_color_override("font_color", entry[2])
		var difficulty: BotConfig.Difficulty = entry[1]
		btn.pressed.connect(func():
			SfxManager.play("ui_click")
			var seed_text: String = seed_input.text.strip_edges()
			if seed_text.is_valid_int():
				NetworkManager.bot_seed = seed_text.to_int()
			else:
				NetworkManager.bot_seed = -1
			NetworkManager.set_bot_difficulty(difficulty)
			# Apply speed override if not automatic
			if speed_slider.value > 0:
				NetworkManager.bot_config.action_delay = speed_slider.value * 0.1
			# Apply playstyle override (0=auto, 1=invasion, 2=counter, 3=balanced)
			var ps_val := int(playstyle_slider.value)
			NetworkManager.bot_config.forced_playstyle = ps_val - 1 # -1=auto, 0=inv, 1=ctr, 2=bal
			NetworkManager.mode = NetworkManager.Mode.SOLO_BOT
			NetworkManager.local_player_id = 0
			popup.hide()
			NetworkManager.change_scene("res://scenes/board/GameBoard.tscn")
		)
		btn_box.add_child(btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(200, 40)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.add_theme_font_size_override("font_size", 18)
	cancel_btn.pressed.connect(func(): SfxManager.play("ui_click"); popup.hide())
	btn_box.add_child(cancel_btn)

	vbox.add_child(btn_box)
	margin.add_child(vbox)
	panel.add_child(margin)
	popup.add_child(panel)

	add_child(popup)
	popup.popup_centered()


func _on_lan_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/ui/LanLobby.tscn")


func _on_online_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/ui/OnlinePlay.tscn")


func _on_deck_builder_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/ui/DeckBuilder.tscn")


func _on_extras_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/ui/Extras.tscn")


func _on_patreon_pressed() -> void:
	SfxManager.play("ui_click")
	OS.shell_open("https://www.patreon.com/cw/sodabomber/membership")


const _VOLUME_LABELS := ["OFF", "25%", "50%", "75%", "100%"]


func _on_sound_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			GameSettings.sound_volume = (GameSettings.sound_volume + 1) % 5
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			GameSettings.sound_volume = (GameSettings.sound_volume + 4) % 5
		else:
			return
		GameSettings.save()
		_update_sound_button()
		SfxManager.play("ui_click")


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
		_update_music_button()


func _update_sound_button() -> void:
	sound_button.text = "Sound: %s" % _VOLUME_LABELS[GameSettings.sound_volume]


func _update_music_button() -> void:
	music_button.text = "Music: %s" % _VOLUME_LABELS[GameSettings.music_volume]


func _on_options_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/ui/Options.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and OS.get_name() == "Android":
		get_tree().quit()


# -- Update dialog ------------------------------------------------------------

func _on_update_available(_current: String, new_version: String, download_url: String, release_url: String) -> void:
	var is_skipped := new_version == GameSettings.skipped_version
	if is_skipped or UpdateChecker.later_dismissed:
		_show_update_button(new_version, download_url, release_url)
		return
	_show_update_dialog(new_version, download_url, release_url)


func _show_update_button(new_version: String, download_url: String, release_url: String) -> void:
	update_button.visible = true
	# Reconnect in case this is called multiple times
	if update_button.pressed.is_connected(_on_update_button_pressed):
		update_button.pressed.disconnect(_on_update_button_pressed)
	update_button.pressed.connect(_on_update_button_pressed.bind(new_version, download_url, release_url))


func _on_update_button_pressed(new_version: String, download_url: String, release_url: String) -> void:
	SfxManager.play("ui_click")
	_show_update_dialog(new_version, download_url, release_url)


func _show_update_dialog(new_version: String, download_url: String, release_url: String) -> void:
	var current: String = ProjectSettings.get_setting("application/config/version", "")
	var popup := PopupPanel.new()
	popup.exclusive = true

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
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

	var title := Label.new()
	title.text = "Update Available"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	vbox.add_child(title)

	var info := Label.new()
	info.text = "Current version: v%s\nNew version: %s" % [current, new_version]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 18)
	vbox.add_child(info)

	vbox.add_child(HSeparator.new())

	var btn_box := VBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 8)

	var update_btn := Button.new()
	update_btn.text = "Update Now"
	update_btn.custom_minimum_size = Vector2(200, 45)
	update_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	update_btn.add_theme_font_size_override("font_size", 20)
	update_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		OS.shell_open(download_url if not download_url.is_empty() else release_url)
		popup.hide()
	)
	btn_box.add_child(update_btn)

	var skip_btn := Button.new()
	skip_btn.text = "Skip This Version"
	skip_btn.custom_minimum_size = Vector2(200, 40)
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_btn.add_theme_font_size_override("font_size", 18)
	skip_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		GameSettings.skipped_version = new_version
		GameSettings.save()
		_show_update_button(new_version, download_url, release_url)
		popup.hide()
	)
	btn_box.add_child(skip_btn)

	var later_btn := Button.new()
	later_btn.text = "Later"
	later_btn.custom_minimum_size = Vector2(200, 40)
	later_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	later_btn.add_theme_font_size_override("font_size", 18)
	later_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		UpdateChecker.later_dismissed = true
		popup.hide()
	)
	btn_box.add_child(later_btn)

	vbox.add_child(btn_box)
	margin.add_child(vbox)
	panel.add_child(margin)
	popup.add_child(panel)

	add_child(popup)
	popup.popup_centered()


# -- Reconnect dialog ----------------------------------------------------------

func _show_reconnect_dialog() -> void:
	var saved_code := GameSettings.reconnect_room_code

	var popup := PopupPanel.new()
	popup.exclusive = true

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
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

	var title := Label.new()
	title.text = "Game In Progress"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.1, 1))
	vbox.add_child(title)

	var info := Label.new()
	info.text = "You were disconnected from a game.\nWould you like to reconnect?"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 18)
	vbox.add_child(info)

	vbox.add_child(HSeparator.new())

	var btn_box := VBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 8)

	var status_label := Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	status_label.visible = false
	vbox.add_child(status_label)

	var reconnect_btn := Button.new()
	reconnect_btn.text = "Reconnect"
	reconnect_btn.custom_minimum_size = Vector2(200, 45)
	reconnect_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reconnect_btn.add_theme_font_size_override("font_size", 20)
	reconnect_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		reconnect_btn.disabled = true
		reconnect_btn.text = "Connecting..."
		status_label.text = "Connecting to relay server..."
		status_label.visible = true
		print("[Reconnect] Attempting join_online('%s')" % saved_code)
		# Restore game mode/public state before joining
		NetworkManager.game_mode = GameSettings.reconnect_game_mode
		NetworkManager.is_public_room = GameSettings.reconnect_is_public
		var err: Error = await NetworkManager.join_online(saved_code)
		print("[Reconnect] join_online returned: %d, version_verified=%s" % [err, NetworkManager.version_verified])
		if err == OK:
			NetworkManager.is_in_game = true
			# Version exchange happens during join_online. Poll briefly
			# in case the host's response arrives on the next frame.
			if not NetworkManager.version_verified:
				status_label.text = "Connected! Verifying game version..."
				var elapsed := 0.0
				while elapsed < NetworkManager.VERSION_TIMEOUT and not NetworkManager.version_verified:
					await get_tree().create_timer(0.1).timeout
					elapsed += 0.1
			print("[Reconnect] version_verified=%s" % NetworkManager.version_verified)
			if NetworkManager.version_verified:
				popup.hide()
				NetworkManager.change_scene("res://scenes/board/GameBoard.tscn")
			else:
				status_label.text = "Version mismatch. Cannot reconnect."
				reconnect_btn.text = "Reconnect"
				reconnect_btn.disabled = false
				GameSettings.clear_reconnect_session()
				NetworkManager.disconnect_game()
		else:
			var err_msg := "timeout" if err == ERR_TIMEOUT else "error %d" % err
			status_label.text = "Failed to connect (%s).\nRoom may no longer exist." % err_msg
			print("[Reconnect] Connection failed: %s" % err_msg)
			reconnect_btn.text = "Retry"
			reconnect_btn.disabled = false
	)
	btn_box.add_child(reconnect_btn)

	var dismiss_btn := Button.new()
	dismiss_btn.text = "Dismiss"
	dismiss_btn.custom_minimum_size = Vector2(200, 40)
	dismiss_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dismiss_btn.add_theme_font_size_override("font_size", 18)
	dismiss_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		GameSettings.clear_reconnect_session()
		popup.hide()
	)
	btn_box.add_child(dismiss_btn)

	vbox.add_child(btn_box)
	margin.add_child(vbox)
	panel.add_child(margin)
	popup.add_child(panel)

	add_child(popup)
	popup.popup_centered()
