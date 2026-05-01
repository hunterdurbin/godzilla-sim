extends Control


## Directory scanned by the 🧪 test buttons. Any *GameBoard.tscn file
## here (excluding the entries in TEST_BOARD_EXCLUDE) becomes a launch
## target. Drop a new variant in the folder → it appears in the menu
## without code edits. Each scene must satisfy the cross-scene
## multiplayer contract: root node named "GameBoard" with a
## GameSession/MultiplayerSync subtree. See docs/new_game_board.md.
const TEST_BOARD_DIR := "res://scenes/board/"
const TEST_BOARD_EXCLUDE := [
	"GameBoardBase.tscn",       # minimal engine-only base
	"GameBoardTemplate.tscn",   # populated starter; designer inherits
	"GameBoard.tscn",           # legacy production scene
	"NewGameBoard.tscn",        # phase-6 GameSession smoke test
]

@onready var start_button: Button = $CenterContainer/VBoxContainer/SoloSelfRow/StartButton
@onready var test_self_button: Button = $CenterContainer/VBoxContainer/SoloSelfRow/TestSelfButton
@onready var solo_bot_button: Button = $CenterContainer/VBoxContainer/SoloBotRow/SoloBotButton
@onready var test_bot_button: Button = $CenterContainer/VBoxContainer/SoloBotRow/TestBotButton
@onready var bot_config_button: Button = $CenterContainer/VBoxContainer/SoloBotRow/BotConfigButton
@onready var test_board_row: HBoxContainer = $CenterContainer/VBoxContainer/TestBoardRow
@onready var test_board_picker: OptionButton = $CenterContainer/VBoxContainer/TestBoardRow/TestBoardPicker

var _test_board_paths: Array[String] = []
@onready var lan_button: Button = $CenterContainer/VBoxContainer/LanButton
@onready var online_button: Button = $CenterContainer/VBoxContainer/OnlineButton
@onready var deck_builder_button: Button = $CenterContainer/VBoxContainer/DeckBuilderButton
@onready var extras_button: Button = $ExtrasButton
@onready var options_button: Button = $OptionsButton
@onready var sound_button: Button = $SoundButton
@onready var music_button: Button = $MusicButton
@onready var patreon_button: TextureButton = $PatreonButton
@onready var discord_button: TextureButton = $DiscordButton
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
	test_self_button.pressed.connect(_on_test_self_pressed)
	test_self_button.disabled = true
	test_bot_button.pressed.connect(_on_test_bot_pressed)
	test_bot_button.disabled = true
	test_board_picker.item_selected.connect(_on_test_board_picker_changed)
	_scan_test_boards()
	_configure_test_buttons()
	bot_config_button.pressed.connect(_on_bot_config_pressed)
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
	discord_button.pressed.connect(_on_discord_pressed)

	version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "")

	# Check for updates
	update_button.visible = false
	UpdateChecker.update_available.connect(_on_update_available)
	if not UpdateChecker.pending_update.is_empty():
		var u := UpdateChecker.pending_update
		_on_update_available(u["current"], u["new_version"], u["download_url"], u["release_url"])

	DecklistManager.clear_selections()

	deck_select_p1.set_header(tr("STR_DS_P1_DECK"))
	deck_select_p2.set_header(tr("STR_DS_P2_DECK"))

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
	var ready: bool = _p1_ready and _p2_ready
	start_button.disabled = not ready
	solo_bot_button.disabled = not ready
	var test_scene_present: bool = not _test_board_paths.is_empty()
	test_self_button.disabled = not (ready and test_scene_present)
	test_bot_button.disabled = not (ready and test_scene_present)
	if not start_button.disabled:
		start_button.grab_focus()


## Scan TEST_BOARD_DIR (recursive) for *GameBoard.tscn files (minus
## exclusions). Populates the picker dropdown and restores the last
## persisted choice. Hides the picker row when only 0 or 1 scene
## exists (keeps menu tidy).
func _scan_test_boards() -> void:
	_test_board_paths.clear()
	test_board_picker.clear()
	_scan_test_boards_in(TEST_BOARD_DIR)
	_test_board_paths.sort()
	for path in _test_board_paths:
		test_board_picker.add_item(path.get_file().trim_suffix(".tscn"))
	# Restore persisted selection.
	var persisted := GameSettings.last_test_board_path
	var idx: int = _test_board_paths.find(persisted)
	if idx >= 0:
		test_board_picker.select(idx)
	# Picker visible only when 2+ scenes exist (single scene needs no choice).
	test_board_row.visible = _test_board_paths.size() >= 2


## Recursive helper: walks `dir_path` (a `res://...` directory) and
## appends any *GameBoard.tscn whose filename isn't in TEST_BOARD_EXCLUDE.
## Designer can drop a variant into a subfolder (e.g. `scenes/board/designer/`)
## without code changes — it'll appear in the picker.
func _scan_test_boards_in(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir() and not fname.begins_with("."):
			_scan_test_boards_in(dir_path.path_join(fname))
		elif fname.ends_with("GameBoard.tscn") and fname not in TEST_BOARD_EXCLUDE:
			_test_board_paths.append(dir_path.path_join(fname))
		fname = dir.get_next()
	dir.list_dir_end()


func _current_test_board_path() -> String:
	if _test_board_paths.is_empty():
		return ""
	var idx: int = test_board_picker.selected
	if idx < 0 or idx >= _test_board_paths.size():
		idx = 0
	return _test_board_paths[idx]


func _on_test_board_picker_changed(idx: int) -> void:
	if idx >= 0 and idx < _test_board_paths.size():
		GameSettings.last_test_board_path = _test_board_paths[idx]
		GameSettings.save()
	_configure_test_buttons()


func _configure_test_buttons() -> void:
	# Wire tooltips per state so a missing scene is debuggable from the UI.
	if _test_board_paths.is_empty():
		var msg := "Drop a *GameBoard.tscn into %s to enable" % TEST_BOARD_DIR
		test_self_button.tooltip_text = msg
		test_bot_button.tooltip_text = msg
	else:
		var fname := _current_test_board_path().get_file()
		test_self_button.tooltip_text = "Test Solo v Self in %s" % fname
		test_bot_button.tooltip_text = "Test Solo v Bot in %s" % fname


func _on_start_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.mode = NetworkManager.Mode.SOLO
	# Reset seat in case a previous load-save session set it to 1 — without this
	# the new solo game inherits the stale id and the board renders mirrored.
	NetworkManager.local_player_id = 0
	NetworkManager.change_scene("res://scenes/board/GameBoard.tscn")


func _on_solo_bot_pressed() -> void:
	SfxManager.play("ui_click")
	# Reconcile saved deck weights against the current on-disk deck list.
	# Catches the case where a deck was added or deleted directly via the
	# filesystem without the gear modal being reopened.
	_reconcile_bot_deck_weights()
	# Apply persisted bot settings
	NetworkManager.set_bot_difficulty(GameSettings.bot_difficulty)
	if GameSettings.bot_speed_value > 0:
		NetworkManager.bot_config.action_delay = GameSettings.bot_speed_value * 0.1
	NetworkManager.bot_config.forced_playstyle = GameSettings.bot_playstyle_value - 1
	var seed_text := GameSettings.bot_seed_text.strip_edges()
	NetworkManager.bot_seed = seed_text.to_int() if seed_text.is_valid_int() else -1
	# Random deck override (replaces P2 dropdown selection if a deck pool is configured)
	if GameSettings.bot_random_deck_enabled:
		var picked := _pick_weighted_random_deck()
		if not picked.is_empty():
			DecklistManager.select_deck_for_player(1, picked)
	NetworkManager.mode = NetworkManager.Mode.SOLO_BOT
	NetworkManager.local_player_id = 0
	NetworkManager.change_scene("res://scenes/board/GameBoard.tscn")


func _on_bot_config_pressed() -> void:
	SfxManager.play("ui_click")
	_show_bot_config_popup()


func _on_test_self_pressed() -> void:
	var path := _current_test_board_path()
	if path.is_empty():
		return
	SfxManager.play("ui_click")
	NetworkManager.mode = NetworkManager.Mode.SOLO
	NetworkManager.local_player_id = 0
	NetworkManager.change_scene(path)


func _on_test_bot_pressed() -> void:
	var path := _current_test_board_path()
	if path.is_empty():
		return
	SfxManager.play("ui_click")
	_reconcile_bot_deck_weights()
	NetworkManager.set_bot_difficulty(GameSettings.bot_difficulty)
	if GameSettings.bot_speed_value > 0:
		NetworkManager.bot_config.action_delay = GameSettings.bot_speed_value * 0.1
	NetworkManager.bot_config.forced_playstyle = GameSettings.bot_playstyle_value - 1
	var seed_text := GameSettings.bot_seed_text.strip_edges()
	NetworkManager.bot_seed = seed_text.to_int() if seed_text.is_valid_int() else -1
	if GameSettings.bot_random_deck_enabled:
		var picked := _pick_weighted_random_deck()
		if not picked.is_empty():
			DecklistManager.select_deck_for_player(1, picked)
	NetworkManager.mode = NetworkManager.Mode.SOLO_BOT
	NetworkManager.local_player_id = 0
	NetworkManager.change_scene(path)


const _WEIGHT_MIN := 1
const _WEIGHT_MAX := 100


static func _read_weight(input: LineEdit) -> int:
	var t := input.text.strip_edges()
	if not t.is_valid_int():
		return _WEIGHT_MIN
	return clampi(t.to_int(), _WEIGHT_MIN, _WEIGHT_MAX)


static func _write_weight(input: LineEdit, val: int) -> void:
	input.text = str(clampi(val, _WEIGHT_MIN, _WEIGHT_MAX))


func _reconcile_bot_deck_weights() -> void:
	# Prune entries pointing at decks that no longer exist on disk so the
	# saved cfg stays in sync with the actual deck list.
	var current := {}
	for d in DecklistManager.get_all_decklists():
		current[d] = true
	var changed := false
	for key in GameSettings.bot_deck_weights.keys():
		if not current.has(key):
			GameSettings.bot_deck_weights.erase(key)
			changed = true
	if changed:
		GameSettings.save()


func _pick_weighted_random_deck() -> String:
	var all_decks := DecklistManager.get_all_decklists()
	var pool: Array = []
	var total := 0
	for d in all_decks:
		var w := int(GameSettings.bot_deck_weights.get(d, 1))
		if w > 0:
			pool.append({"name": d, "weight": w})
			total += w
	if total <= 0 or pool.is_empty():
		return ""
	var r := randi() % total
	var acc := 0
	for entry in pool:
		acc += entry["weight"]
		if r < acc:
			return entry["name"]
	return pool[-1]["name"]


func _show_bot_config_popup() -> void:
	var popup := PopupPanel.new()
	popup.exclusive = true

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
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
	title.text = tr("STR_MENU_BOT_CONFIG")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.1, 1))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Two-column body: left = bot tuning, right = deck pool
	var columns_hbox := HBoxContainer.new()
	columns_hbox.add_theme_constant_override("separation", 24)
	columns_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 16)
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 8)
	columns_hbox.add_child(left_col)
	columns_hbox.add_child(VSeparator.new())
	columns_hbox.add_child(right_col)
	vbox.add_child(columns_hbox)

	# Seed input (with Clear button)
	var seed_row := HBoxContainer.new()
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seed_row.add_theme_constant_override("separation", 6)
	var seed_label := Label.new()
	seed_label.text = tr("STR_MENU_SEED")
	seed_label.add_theme_font_size_override("font_size", 16)
	seed_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	seed_row.add_child(seed_label)
	var seed_input := LineEdit.new()
	seed_input.placeholder_text = tr("STR_MENU_SEED_PLACEHOLDER")
	seed_input.custom_minimum_size = Vector2(180, 0)
	seed_input.add_theme_font_size_override("font_size", 16)
	seed_input.text = GameSettings.bot_seed_text
	seed_row.add_child(seed_input)
	var seed_clear_btn := Button.new()
	seed_clear_btn.text = tr("STR_COMMON_CLEAR")
	seed_clear_btn.add_theme_font_size_override("font_size", 14)
	seed_clear_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		seed_input.text = ""
	)
	seed_row.add_child(seed_clear_btn)

	# Action speed slider
	var speed_row := VBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	var speed_label := Label.new()
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.add_theme_font_size_override("font_size", 16)
	speed_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	speed_row.add_child(speed_label)
	var speed_slider := HSlider.new()
	speed_slider.min_value = 0
	speed_slider.max_value = 10
	speed_slider.step = 1
	speed_slider.value = GameSettings.bot_speed_value
	speed_slider.custom_minimum_size = Vector2(280, 0)
	var update_speed_label := func(val: float):
		if val == 0:
			speed_label.text = tr("STR_MENU_BOT_SPEED_AUTO")
		else:
			speed_label.text = tr("STR_MENU_BOT_SPEED_FMT") % (val * 0.1)
	speed_slider.value_changed.connect(update_speed_label)
	update_speed_label.call(speed_slider.value)
	speed_row.add_child(speed_slider)

	# Playstyle slider
	var playstyle_row := VBoxContainer.new()
	playstyle_row.add_theme_constant_override("separation", 4)
	var playstyle_label := Label.new()
	playstyle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playstyle_label.add_theme_font_size_override("font_size", 16)
	playstyle_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	playstyle_row.add_child(playstyle_label)
	var playstyle_keys := ["STR_MENU_PLAYSTYLE_AUTOMATIC", "STR_MENU_PLAYSTYLE_INVASION", "STR_MENU_PLAYSTYLE_COUNTER", "STR_MENU_PLAYSTYLE_BALANCED"]
	var playstyle_slider := HSlider.new()
	playstyle_slider.min_value = 0
	playstyle_slider.max_value = 3
	playstyle_slider.step = 1
	playstyle_slider.value = GameSettings.bot_playstyle_value
	playstyle_slider.custom_minimum_size = Vector2(280, 0)
	var update_ps_label := func(val: float):
		playstyle_label.text = tr("STR_MENU_PLAYSTYLE_FMT") % tr(playstyle_keys[int(val)])
	playstyle_slider.value_changed.connect(update_ps_label)
	update_ps_label.call(playstyle_slider.value)
	playstyle_row.add_child(playstyle_slider)

	# Difficulty selector (toggle group)
	var diff_label := Label.new()
	diff_label.text = tr("STR_MENU_BOT_DIFFICULTY")
	diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diff_label.add_theme_font_size_override("font_size", 16)
	diff_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 8)
	var diff_group := ButtonGroup.new()
	var difficulties: Array = [
		[tr("STR_MENU_DIFFICULTY_EASY"), BotConfig.Difficulty.EASY, Color(0.3, 0.8, 0.3)],
		[tr("STR_MENU_DIFFICULTY_NORMAL"), BotConfig.Difficulty.NORMAL, Color(0.9, 0.7, 0.1)],
		[tr("STR_MENU_DIFFICULTY_HARD"), BotConfig.Difficulty.HARD, Color(0.9, 0.3, 0.1)],
	]
	var diff_buttons: Array[Button] = []
	for entry in difficulties:
		var btn := Button.new()
		btn.text = entry[0]
		btn.toggle_mode = true
		btn.button_group = diff_group
		btn.custom_minimum_size = Vector2(110, 40)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", entry[2])
		var difficulty: int = entry[1]
		btn.set_meta("difficulty", difficulty)
		if difficulty == GameSettings.bot_difficulty:
			btn.button_pressed = true
		btn.pressed.connect(func(): SfxManager.play("ui_click"))
		diff_row.add_child(btn)
		diff_buttons.append(btn)

	# Assemble left column in display order: difficulty → speed → playstyle → seed
	left_col.add_child(diff_label)
	left_col.add_child(diff_row)
	left_col.add_child(speed_row)
	left_col.add_child(playstyle_row)
	left_col.add_child(seed_row)

	# Bot deck section (right column)
	var deck_header_row := HBoxContainer.new()
	deck_header_row.add_theme_constant_override("separation", 8)
	var deck_header_label := Label.new()
	deck_header_label.text = tr("STR_MENU_BOT_DECK")
	deck_header_label.add_theme_font_size_override("font_size", 16)
	deck_header_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.1))
	deck_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_header_row.add_child(deck_header_label)
	var random_deck_check := CheckBox.new()
	random_deck_check.text = tr("STR_MENU_BOT_DECK_RANDOM")
	random_deck_check.button_pressed = GameSettings.bot_random_deck_enabled
	deck_header_row.add_child(random_deck_check)
	right_col.add_child(deck_header_row)

	# Select/Unselect-all + Reset Weights buttons (right-aligned, above the scrolling list)
	var select_all_row := HBoxContainer.new()
	select_all_row.alignment = BoxContainer.ALIGNMENT_END
	select_all_row.add_theme_constant_override("separation", 6)
	var select_all_btn := Button.new()
	select_all_btn.add_theme_font_size_override("font_size", 14)
	select_all_row.add_child(select_all_btn)
	var reset_weights_btn := Button.new()
	reset_weights_btn.text = tr("STR_MENU_DECK_RESET_WEIGHTS")
	reset_weights_btn.add_theme_font_size_override("font_size", 14)
	select_all_row.add_child(reset_weights_btn)
	right_col.add_child(select_all_row)

	var deck_scroll := ScrollContainer.new()
	deck_scroll.custom_minimum_size = Vector2(0, 280)
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var deck_list := VBoxContainer.new()
	deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_list.add_theme_constant_override("separation", 4)

	# Per-deck rows (CheckBox + [−] [input] [+] stepper for mobile-friendly tapping)
	var deck_rows: Array = []
	for deck_name in DecklistManager.get_all_decklists():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var has_entry: bool = GameSettings.bot_deck_weights.has(deck_name)
		var saved_weight: int = int(GameSettings.bot_deck_weights.get(deck_name, 1))
		var enabled: bool = (not has_entry) or saved_weight > 0
		var weight: int = saved_weight if (has_entry and saved_weight > 0) else max(saved_weight, 1)

		var row_check := CheckBox.new()
		row_check.text = deck_name
		row_check.tooltip_text = deck_name
		row_check.button_pressed = enabled
		row_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_check.clip_text = true
		row.add_child(row_check)

		var stepper := HBoxContainer.new()
		stepper.add_theme_constant_override("separation", 2)

		var dec_btn := Button.new()
		dec_btn.text = "−"
		dec_btn.custom_minimum_size = Vector2(36, 36)
		dec_btn.add_theme_font_size_override("font_size", 18)
		stepper.add_child(dec_btn)

		var weight_input := LineEdit.new()
		weight_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
		weight_input.custom_minimum_size = Vector2(50, 36)
		weight_input.add_theme_font_size_override("font_size", 14)
		weight_input.max_length = 3
		_write_weight(weight_input, weight)
		stepper.add_child(weight_input)

		var inc_btn := Button.new()
		inc_btn.text = "+"
		inc_btn.custom_minimum_size = Vector2(36, 36)
		inc_btn.add_theme_font_size_override("font_size", 18)
		stepper.add_child(inc_btn)

		dec_btn.pressed.connect(func():
			SfxManager.play("ui_click")
			_write_weight(weight_input, _read_weight(weight_input) - 1)
		)
		inc_btn.pressed.connect(func():
			SfxManager.play("ui_click")
			_write_weight(weight_input, _read_weight(weight_input) + 1)
		)
		# Re-clamp typed input on commit / focus loss
		weight_input.text_submitted.connect(func(_t): _write_weight(weight_input, _read_weight(weight_input)))
		weight_input.focus_exited.connect(func(): _write_weight(weight_input, _read_weight(weight_input)))

		row.add_child(stepper)
		deck_list.add_child(row)
		deck_rows.append({"name": deck_name, "check": row_check, "input": weight_input, "dec": dec_btn, "inc": inc_btn})

	deck_scroll.add_child(deck_list)
	right_col.add_child(deck_scroll)

	# Select/Unselect-all logic — label flips based on whether every row is checked
	var refresh_select_all_label := func():
		var all_checked := true
		for r in deck_rows:
			if not r["check"].button_pressed:
				all_checked = false
				break
		select_all_btn.text = tr("STR_MENU_DECK_UNSELECT_ALL") if all_checked else tr("STR_MENU_DECK_SELECT_ALL")
	select_all_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		var any_unchecked := false
		for r in deck_rows:
			if not r["check"].button_pressed:
				any_unchecked = true
				break
		var new_state: bool = any_unchecked  # any unchecked → select all; else unselect all
		for r in deck_rows:
			r["check"].set_pressed_no_signal(new_state)
		refresh_select_all_label.call()
	)
	for r in deck_rows:
		r["check"].toggled.connect(func(_v): refresh_select_all_label.call())
	refresh_select_all_label.call()

	# Reset all per-deck weights back to 1
	reset_weights_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		for r in deck_rows:
			_write_weight(r["input"], 1)
	)

	# Enable/disable deck row widgets + helper buttons in sync with master toggle
	var update_deck_widgets := func():
		var on: bool = random_deck_check.button_pressed
		select_all_btn.disabled = not on
		reset_weights_btn.disabled = not on
		for r in deck_rows:
			r["check"].disabled = not on
			r["input"].editable = on
			r["dec"].disabled = not on
			r["inc"].disabled = not on
	random_deck_check.toggled.connect(func(_v): update_deck_widgets.call())
	update_deck_widgets.call()

	vbox.add_child(HSeparator.new())

	# Save / Cancel buttons
	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 12)

	var save_btn := Button.new()
	save_btn.text = tr("STR_COMMON_SAVE")
	save_btn.custom_minimum_size = Vector2(140, 40)
	save_btn.add_theme_font_size_override("font_size", 18)
	save_btn.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	save_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		# Difficulty
		var pressed_diff_btn := diff_group.get_pressed_button()
		if pressed_diff_btn != null:
			GameSettings.bot_difficulty = int(pressed_diff_btn.get_meta("difficulty"))
		# Seed / speed / playstyle
		GameSettings.bot_seed_text = seed_input.text.strip_edges()
		GameSettings.bot_speed_value = int(speed_slider.value)
		GameSettings.bot_playstyle_value = int(playstyle_slider.value)
		# Deck weights
		GameSettings.bot_random_deck_enabled = random_deck_check.button_pressed
		var weights := {}
		for r in deck_rows:
			var w := _read_weight(r["input"]) if r["check"].button_pressed else 0
			weights[r["name"]] = w
		GameSettings.bot_deck_weights = weights
		GameSettings.save()
		popup.hide()
	)
	btn_box.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("STR_COMMON_CANCEL")
	cancel_btn.custom_minimum_size = Vector2(140, 40)
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


func _on_discord_pressed() -> void:
	SfxManager.play("ui_click")
	OS.shell_open("https://discord.gg/fwCaYzWbPw")


const _VOLUME_LABELS := ["STR_VOL_OFF", "25%", "50%", "75%", "100%"]


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
	sound_button.text = tr("STR_MENU_SOUND_FMT").replace("{VAL}", tr(_VOLUME_LABELS[GameSettings.sound_volume]))


func _update_music_button() -> void:
	music_button.text = tr("STR_MENU_MUSIC_FMT").replace("{VAL}", tr(_VOLUME_LABELS[GameSettings.music_volume]))


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
	title.text = tr("STR_MENU_UPDATE_AVAILABLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	vbox.add_child(title)

	var info := Label.new()
	info.text = tr("STR_MENU_UPDATE_VERSIONS_FMT") % [current, new_version]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 18)
	vbox.add_child(info)

	vbox.add_child(HSeparator.new())

	var btn_box := VBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 8)

	var update_btn := Button.new()
	update_btn.text = tr("STR_MENU_UPDATE_NOW")
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
	skip_btn.text = tr("STR_MENU_UPDATE_SKIP")
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
	later_btn.text = tr("STR_MENU_UPDATE_LATER")
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
	title.text = tr("STR_MENU_RECONNECT_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.1, 1))
	vbox.add_child(title)

	var info := Label.new()
	info.text = tr("STR_MENU_RECONNECT_PROMPT")
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
	reconnect_btn.text = tr("STR_MENU_RECONNECT")
	reconnect_btn.custom_minimum_size = Vector2(200, 45)
	reconnect_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reconnect_btn.add_theme_font_size_override("font_size", 20)
	reconnect_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		reconnect_btn.disabled = true
		reconnect_btn.text = tr("STR_MENU_CONNECTING")
		status_label.text = tr("STR_MENU_RECONNECT_CONNECTING")
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
				status_label.text = tr("STR_MENU_RECONNECT_VERIFYING")
				var elapsed := 0.0
				while elapsed < NetworkManager.VERSION_TIMEOUT and not NetworkManager.version_verified:
					await get_tree().create_timer(0.1).timeout
					elapsed += 0.1
			print("[Reconnect] version_verified=%s" % NetworkManager.version_verified)
			if NetworkManager.version_verified:
				popup.hide()
				NetworkManager.change_scene("res://scenes/board/GameBoard.tscn")
			else:
				status_label.text = tr("STR_MENU_RECONNECT_VERSION_MISMATCH")
				reconnect_btn.text = tr("STR_MENU_RECONNECT")
				reconnect_btn.disabled = false
				GameSettings.clear_reconnect_session()
				NetworkManager.disconnect_game()
		else:
			var err_msg := tr("STR_MENU_ERR_TIMEOUT") if err == ERR_TIMEOUT else tr("STR_MENU_ERR_CODE_FMT") % err
			status_label.text = tr("STR_MENU_RECONNECT_FAILED_FMT") % err_msg
			print("[Reconnect] Connection failed: %s" % err_msg)
			reconnect_btn.text = tr("STR_MENU_RETRY")
			reconnect_btn.disabled = false
	)
	btn_box.add_child(reconnect_btn)

	var dismiss_btn := Button.new()
	dismiss_btn.text = tr("STR_MENU_DISMISS")
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
