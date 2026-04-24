extends Control

@onready var player_name_edit: LineEdit = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/PlayerNameRow/PlayerNameEdit
@onready var automation_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AutomationButton
@onready var customize_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CustomizeButton
@onready var advanced_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AdvancedButton
@onready var audio_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AudioButton
@onready var language_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/LanguageButton
@onready var back_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton

const _LOCALE_CYCLE := ["en", "ja"]


func _ready() -> void:
	player_name_edit.text = GameSettings.player_name
	player_name_edit.text_changed.connect(_on_player_name_changed)
	automation_button.pressed.connect(_on_automation_pressed)
	customize_button.pressed.connect(_on_customize_pressed)
	advanced_button.pressed.connect(_on_advanced_pressed)
	audio_button.pressed.connect(_on_audio_pressed)
	language_button.pressed.connect(_on_language_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_refresh_language_button()


func _refresh_language_button() -> void:
	var lang_key := "STR_LANG_" + GameSettings.locale.to_upper()
	language_button.text = tr("STR_OPTIONS_LANGUAGE_FMT").replace("{LANG}", tr(lang_key))


func _on_language_pressed() -> void:
	SfxManager.play("ui_click")
	var idx := _LOCALE_CYCLE.find(GameSettings.locale)
	var next: String = _LOCALE_CYCLE[(idx + 1) % _LOCALE_CYCLE.size()] if idx >= 0 else _LOCALE_CYCLE[0]
	GameSettings.set_locale(next)
	_refresh_language_button()
	if GameSettings.card_art_locale != next:
		_prompt_card_art_switch(next)


func _prompt_card_art_switch(target_locale: String) -> void:
	var parts := _create_modal(tr("STR_OPTIONS_ART_MATCH_TITLE"))
	var popup: PopupPanel = parts[0]
	var vbox: VBoxContainer = parts[1]

	var lang_name := tr("STR_LANG_" + target_locale.to_upper())
	var prompt := Label.new()
	prompt.text = tr("STR_OPTIONS_ART_MATCH_PROMPT_FMT").replace("{LANG}", lang_name)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.add_theme_font_size_override("font_size", 16)
	vbox.add_child(prompt)

	var cached: int = ArtworkDownloader.get_cached_count(target_locale)
	var status := Label.new()
	if cached > 0:
		status.text = tr("STR_OPTIONS_ART_STATUS_CACHED_FMT").replace("{N}", str(cached))
	else:
		status.text = tr("STR_OPTIONS_ART_STATUS_NONE")
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(status)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)

	var no_btn := Button.new()
	no_btn.text = tr("STR_OPTIONS_ART_MATCH_NO")
	no_btn.custom_minimum_size = Vector2(140, 40)
	no_btn.add_theme_font_size_override("font_size", 16)
	no_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		popup.hide())
	btn_row.add_child(no_btn)

	var yes_btn := Button.new()
	yes_btn.text = tr("STR_OPTIONS_ART_MATCH_YES")
	yes_btn.custom_minimum_size = Vector2(140, 40)
	yes_btn.add_theme_font_size_override("font_size", 16)
	yes_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		GameSettings.card_art_locale = target_locale
		GameSettings.save()
		_CardScript.clear_texture_cache()
		popup.hide()
		# If art isn't cached yet, jump to LoadingScreen so it downloads now.
		if ArtworkDownloader.get_cached_count(target_locale) == 0:
			NetworkManager.change_scene("res://scenes/ui/LoadingScreen.tscn"))
	btn_row.add_child(yes_btn)

	vbox.add_child(btn_row)
	_show_modal(popup)


func _on_player_name_changed(new_text: String) -> void:
	GameSettings.player_name = new_text
	GameSettings.save()


func _on_setting_toggled(enabled: bool, setting: String) -> void:
	GameSettings.set(setting, enabled)
	GameSettings.save()


func _on_sort_type_order_selected(index: int) -> void:
	GameSettings.hand_sort_type_order = index
	GameSettings.save()


func _on_sort_rank_order_selected(index: int) -> void:
	GameSettings.hand_sort_rank_ascending = (index == 0)
	GameSettings.save()


func _on_color_overlay_selected(index: int) -> void:
	GameSettings.color_overlay_mode = index
	GameSettings.save()


func _on_custom_card_back_selected(index: int) -> void:
	GameSettings.custom_card_back_mode = index
	GameSettings.save()


# --- Shared modal helpers ---

func _create_modal(title_text: String, min_width: float = 460.0) -> Array:
	var popup := PopupPanel.new()

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0)
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
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	vbox.add_child(title)

	margin.add_child(vbox)
	panel.add_child(margin)
	popup.add_child(panel)

	return [popup, vbox]


func _add_toggle_row(vbox: VBoxContainer, label_text: String, setting: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 18)
	var check := CheckButton.new()
	check.button_pressed = GameSettings.get(setting)
	check.toggled.connect(_on_setting_toggled.bind(setting))
	row.add_child(label)
	row.add_child(check)
	vbox.add_child(row)


func _add_close_button(vbox: VBoxContainer, popup: PopupPanel) -> void:
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(popup.hide)
	vbox.add_child(close_btn)


func _show_modal(popup: PopupPanel) -> void:
	add_child(popup)
	popup.popup_centered()


# --- Automation modal ---

func _on_automation_pressed() -> void:
	SfxManager.play("ui_click")
	var parts := _create_modal("Automation")
	var popup: PopupPanel = parts[0]
	var vbox: VBoxContainer = parts[1]

	_add_toggle_row(vbox, "Auto Draw", "auto_draw")
	_add_toggle_row(vbox, "Auto Phase Advance", "auto_phase_advance")
	_add_toggle_row(vbox, "Auto Discard Strategies", "auto_discard_strategies")
	_add_toggle_row(vbox, "Auto Reset Rage", "auto_reset_rage")
	_add_toggle_row(vbox, "Auto Counter Check", "auto_counter_check")
	_add_toggle_row(vbox, "Auto Advance", "auto_advance")
	_add_toggle_row(vbox, "Confirm Main Phase Pass", "confirm_main_phase_pass")

	vbox.add_child(HSeparator.new())

	_add_toggle_row(vbox, "Default Stacked View", "stacked_view")

	vbox.add_child(HSeparator.new())

	# Hand sort - type order
	var type_row := HBoxContainer.new()
	var type_label := Label.new()
	type_label.text = "Hand Sort Type Order"
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_label.add_theme_font_size_override("font_size", 18)
	var type_option := OptionButton.new()
	type_option.custom_minimum_size = Vector2(220, 0)
	for item in ["Monster, Battle, Strategy", "Monster, Strategy, Battle",
			"Battle, Monster, Strategy", "Battle, Strategy, Monster",
			"Strategy, Monster, Battle", "Strategy, Battle, Monster"]:
		type_option.add_item(item)
	type_option.selected = GameSettings.hand_sort_type_order
	type_option.item_selected.connect(_on_sort_type_order_selected)
	type_row.add_child(type_label)
	type_row.add_child(type_option)
	vbox.add_child(type_row)

	# Hand sort - rank order
	var rank_row := HBoxContainer.new()
	var rank_label := Label.new()
	rank_label.text = "Hand Sort Rank Order"
	rank_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_label.add_theme_font_size_override("font_size", 18)
	var rank_option := OptionButton.new()
	rank_option.custom_minimum_size = Vector2(220, 0)
	rank_option.add_item("Ascending")
	rank_option.add_item("Descending")
	rank_option.selected = 0 if GameSettings.hand_sort_rank_ascending else 1
	rank_option.item_selected.connect(_on_sort_rank_order_selected)
	rank_row.add_child(rank_label)
	rank_row.add_child(rank_option)
	vbox.add_child(rank_row)

	_add_close_button(vbox, popup)
	_show_modal(popup)


# --- Customize modal ---

const CARD_ART_SETS := ["EBP01", "EBP02", "EBP03", "EPR", "ESD01", "ESD02"]
const _CardScript := preload("res://scenes/cards/card.gd")
var _image_filters := PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Image Files"])
var _pending_card_art_src: String = ""  # Holds picked file path while waiting for card number input


func _on_customize_pressed() -> void:
	SfxManager.play("ui_click")
	var parts := _create_modal("Customize")
	var popup: PopupPanel = parts[0]
	var vbox: VBoxContainer = parts[1]
	var is_ios := OS.get_name() == "iOS"
	var is_mobile := OS.get_name() in ["Android", "iOS"]

	_add_toggle_row(vbox, "Custom Playmat", "custom_playmat_enabled")
	_add_toggle_row(vbox, "Apply Playmat to Opponent", "custom_playmat_opponent")

	var playmat_hint := Label.new()
	if is_ios:
		playmat_hint.text = "Use the Files app to add images (named default.png)"
	elif is_mobile:
		playmat_hint.text = "Import any image to use as your playmat background"
	else:
		playmat_hint.text = "Image must be named: default.png (or .jpg, .jpeg, .webp)"
	playmat_hint.add_theme_font_size_override("font_size", 12)
	playmat_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	vbox.add_child(playmat_hint)

	var playmat_btn_row := HBoxContainer.new()
	playmat_btn_row.alignment = BoxContainer.ALIGNMENT_END
	playmat_btn_row.add_theme_constant_override("separation", 8)
	if is_ios:
		var playmat_instructions_btn := Button.new()
		playmat_instructions_btn.text = "How to Add Files"
		playmat_instructions_btn.add_theme_font_size_override("font_size", 14)
		playmat_instructions_btn.pressed.connect(_show_ios_file_instructions.bind("playmat"))
		playmat_btn_row.add_child(playmat_instructions_btn)
	elif is_mobile:
		var playmat_import_btn := Button.new()
		playmat_import_btn.text = "Import Image"
		playmat_import_btn.add_theme_font_size_override("font_size", 14)
		playmat_import_btn.pressed.connect(_on_import_playmat)
		playmat_btn_row.add_child(playmat_import_btn)
	else:
		var playmat_folder_btn := Button.new()
		playmat_folder_btn.text = "Open Playmat Folder"
		playmat_folder_btn.add_theme_font_size_override("font_size", 14)
		playmat_folder_btn.pressed.connect(_on_open_folder.bind("playmat"))
		playmat_btn_row.add_child(playmat_folder_btn)
	vbox.add_child(playmat_btn_row)

	var overlay_row := HBoxContainer.new()
	var overlay_label := Label.new()
	overlay_label.text = "Color Overlay"
	overlay_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_label.add_theme_font_size_override("font_size", 18)
	var overlay_option := OptionButton.new()
	overlay_option.custom_minimum_size = Vector2(200, 0)
	for item in ["Do Not Apply", "Only Myself", "Only Opponent", "Both Players"]:
		overlay_option.add_item(item)
	overlay_option.selected = GameSettings.color_overlay_mode
	overlay_option.item_selected.connect(_on_color_overlay_selected)
	overlay_row.add_child(overlay_label)
	overlay_row.add_child(overlay_option)
	vbox.add_child(overlay_row)

	vbox.add_child(HSeparator.new())

	_add_toggle_row(vbox, "Custom Card Art", "custom_card_art_enabled")

	var art_hint := Label.new()
	art_hint.text = "Files must be named <CARD_NUMBER>.png (e.g. ESD01-008.png)"
	art_hint.add_theme_font_size_override("font_size", 12)
	art_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	vbox.add_child(art_hint)

	var art_btn_row := HBoxContainer.new()
	art_btn_row.alignment = BoxContainer.ALIGNMENT_END
	art_btn_row.add_theme_constant_override("separation", 8)
	if is_ios:
		var art_clear_btn := Button.new()
		art_clear_btn.text = "Delete All"
		art_clear_btn.add_theme_font_size_override("font_size", 14)
		art_clear_btn.pressed.connect(_show_delete_all_card_art_confirm)
		art_btn_row.add_child(art_clear_btn)
		var art_remove_btn := Button.new()
		art_remove_btn.text = "Remove Art"
		art_remove_btn.add_theme_font_size_override("font_size", 14)
		art_remove_btn.pressed.connect(_show_remove_card_art_prompt)
		art_btn_row.add_child(art_remove_btn)
		var art_instructions_btn := Button.new()
		art_instructions_btn.text = "How to Add Files"
		art_instructions_btn.add_theme_font_size_override("font_size", 14)
		art_instructions_btn.pressed.connect(_show_ios_file_instructions.bind("cardArt"))
		art_btn_row.add_child(art_instructions_btn)
	elif is_mobile:
		var art_clear_btn := Button.new()
		art_clear_btn.text = "Delete All"
		art_clear_btn.add_theme_font_size_override("font_size", 14)
		art_clear_btn.pressed.connect(_show_delete_all_card_art_confirm)
		art_btn_row.add_child(art_clear_btn)
		var art_remove_btn := Button.new()
		art_remove_btn.text = "Remove Art"
		art_remove_btn.add_theme_font_size_override("font_size", 14)
		art_remove_btn.pressed.connect(_show_remove_card_art_prompt)
		art_btn_row.add_child(art_remove_btn)
		var art_import_btn := Button.new()
		art_import_btn.text = "Import Images"
		art_import_btn.add_theme_font_size_override("font_size", 14)
		art_import_btn.pressed.connect(_on_import_card_art)
		art_btn_row.add_child(art_import_btn)
	else:
		var art_folder_btn := Button.new()
		art_folder_btn.text = "Open Card Art Folder"
		art_folder_btn.add_theme_font_size_override("font_size", 14)
		art_folder_btn.pressed.connect(_on_open_folder.bind("cardArt"))
		art_btn_row.add_child(art_folder_btn)
	vbox.add_child(art_btn_row)

	vbox.add_child(HSeparator.new())

	var back_row := HBoxContainer.new()
	var back_label := Label.new()
	back_label.text = "Custom Card Back"
	back_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_label.add_theme_font_size_override("font_size", 18)
	var back_option := OptionButton.new()
	back_option.custom_minimum_size = Vector2(200, 0)
	for item in ["Disabled", "Enabled (myself)", "Enabled (both)"]:
		back_option.add_item(item)
	back_option.selected = GameSettings.custom_card_back_mode
	back_option.item_selected.connect(_on_custom_card_back_selected)
	back_row.add_child(back_label)
	back_row.add_child(back_option)
	vbox.add_child(back_row)

	var back_hint := Label.new()
	if is_ios:
		back_hint.text = "Use the Files app to add images (named default.png)"
	elif is_mobile:
		back_hint.text = "Import any image to use as your card back"
	else:
		back_hint.text = "Image must be named: default.png (or .jpg, .jpeg, .webp)"
	back_hint.add_theme_font_size_override("font_size", 12)
	back_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	vbox.add_child(back_hint)

	var back_btn_row := HBoxContainer.new()
	back_btn_row.alignment = BoxContainer.ALIGNMENT_END
	back_btn_row.add_theme_constant_override("separation", 8)
	if is_ios:
		var back_instructions_btn := Button.new()
		back_instructions_btn.text = "How to Add Files"
		back_instructions_btn.add_theme_font_size_override("font_size", 14)
		back_instructions_btn.pressed.connect(_show_ios_file_instructions.bind("cardBack"))
		back_btn_row.add_child(back_instructions_btn)
	elif is_mobile:
		var back_import_btn := Button.new()
		back_import_btn.text = "Import Image"
		back_import_btn.add_theme_font_size_override("font_size", 14)
		back_import_btn.pressed.connect(_on_import_card_back)
		back_btn_row.add_child(back_import_btn)
	else:
		var back_folder_btn := Button.new()
		back_folder_btn.text = "Open Card Back Folder"
		back_folder_btn.add_theme_font_size_override("font_size", 14)
		back_folder_btn.pressed.connect(_on_open_folder.bind("cardBack"))
		back_btn_row.add_child(back_folder_btn)
	vbox.add_child(back_btn_row)

	_add_close_button(vbox, popup)
	_show_modal(popup)


func _on_open_folder(subfolder: String) -> void:
	var path := GameSettings.get_custom_base_path().path_join(subfolder)
	DirAccess.make_dir_recursive_absolute(path)
	if subfolder == "cardArt":
		for set_id in CARD_ART_SETS:
			DirAccess.make_dir_recursive_absolute(path.path_join(set_id))
	OS.shell_open(path)


func _ensure_custom_dirs(subfolder: String) -> void:
	var path := GameSettings.get_custom_base_path().path_join(subfolder)
	DirAccess.make_dir_recursive_absolute(path)
	if subfolder == "cardArt":
		for set_id in CARD_ART_SETS:
			DirAccess.make_dir_recursive_absolute(path.path_join(set_id))


func _show_ios_file_instructions(subfolder: String) -> void:
	_ensure_custom_dirs(subfolder)
	var app_name: String = ProjectSettings.get_setting("application/config/name", "this app")
	var instructions := ""
	match subfolder:
		"playmat":
			instructions = "1. Open the Files app on your device\n"
			instructions += "2. Go to: On My iPhone > %s > custom > playmat\n" % app_name
			instructions += "3. Copy an image named default.png\n"
			instructions += "   (also supports .jpg, .jpeg, .webp)\n"
			instructions += "4. Return to this app and enable Custom Playmat"
		"cardArt":
			instructions = "1. Open the Files app on your device\n"
			instructions += "2. Go to: On My iPhone > %s > custom > cardArt > [SET]\n" % app_name
			instructions += "3. Copy images named [SET]-[NUMBER].png\n"
			instructions += "   (e.g. ESD01-008.png, EBP02-045.png)\n"
			instructions += "4. Sets: %s\n" % ", ".join(CARD_ART_SETS)
			instructions += "5. Return to this app and enable Custom Card Art"
		"cardBack":
			instructions = "1. Open the Files app on your device\n"
			instructions += "2. Go to: On My iPhone > %s > custom > cardBack\n" % app_name
			instructions += "3. Copy an image named default.png\n"
			instructions += "   (also supports .jpg, .jpeg, .webp)\n"
			instructions += "4. Return to this app and enable Custom Card Back"

	var modal_parts := _create_modal("How to Add Files", 500.0)
	var popup: PopupPanel = modal_parts[0]
	var vbox: VBoxContainer = modal_parts[1]

	var body := Label.new()
	body.text = instructions
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	vbox.add_child(body)

	var note := Label.new()
	note.text = "The folders have been created for you."
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5, 1.0))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(note)

	_add_close_button(vbox, popup)
	_show_modal(popup)


# --- Import handlers ---

## Loads an image from src and saves as PNG to dest.
## Falls back to raw file copy if Image decoding fails.
func _copy_as_png(src: String, dest: String) -> Error:
	var image := Image.load_from_file(src)
	if image != null:
		return image.save_png(dest)
	# Fallback: raw copy (keeps original format, caller must handle extension)
	print("[Import] Image.load_from_file failed, trying raw copy")
	var file := FileAccess.open(src, FileAccess.READ)
	if file == null:
		print("[Import] FileAccess.open failed: %s" % FileAccess.get_open_error())
		return FileAccess.get_open_error()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var out := FileAccess.open(dest, FileAccess.WRITE)
	if out == null:
		print("[Import] FileAccess.open (write) failed: %s" % FileAccess.get_open_error())
		return FileAccess.get_open_error()
	out.store_buffer(bytes)
	out.close()
	return OK


func _on_import_playmat() -> void:
	DisplayServer.file_dialog_show("Import Playmat Image", "", "", false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, _image_filters,
		_on_playmat_file_selected)


func _on_playmat_file_selected(status: bool, paths: PackedStringArray, _idx: int) -> void:
	print("[Import] playmat callback: status=%s paths=%s" % [status, paths])
	if not status or paths.is_empty():
		return
	var src := paths[0]
	var target := GameSettings.get_custom_base_path().path_join("playmat")
	print("[Import] playmat target dir: %s" % target)
	DirAccess.make_dir_recursive_absolute(target)
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var old := target.path_join("default.%s" % ext)
		if FileAccess.file_exists(old):
			DirAccess.remove_absolute(old)
	var dest := target.path_join("default.png")
	var err := _copy_as_png(src, dest)
	print("[Import] playmat result: %s (exists=%s)" % [err, FileAccess.file_exists(dest)])


func _on_import_card_art() -> void:
	var is_mobile := OS.get_name() in ["Android", "iOS"]
	# Android returns content URIs without real filenames, so pick one at a time
	# and prompt for the card number after selection.
	var mode := DisplayServer.FILE_DIALOG_MODE_OPEN_FILE if is_mobile \
		else DisplayServer.FILE_DIALOG_MODE_OPEN_FILES
	DisplayServer.file_dialog_show("Import Card Art", "", "", false,
		mode, _image_filters, _on_card_art_files_selected)


func _on_card_art_files_selected(status: bool, paths: PackedStringArray, _idx: int) -> void:
	print("[Import] card art callback: status=%s paths=%s" % [status, paths])
	if not status or paths.is_empty():
		return
	var base := GameSettings.get_custom_base_path().path_join("cardArt")
	for path in paths:
		var filename := path.get_file().get_basename()
		var parts := filename.split("-")
		if parts.size() >= 2 and parts[0] in CARD_ART_SETS:
			# Real filename with set prefix — save directly
			var set_id := parts[0]
			var target_dir := base.path_join(set_id)
			DirAccess.make_dir_recursive_absolute(target_dir)
			var dest := target_dir.path_join("%s.png" % filename)
			var err := _copy_as_png(path, dest)
			print("[Import] card art: %s -> %s (err=%s)" % [filename, dest, err])
		else:
			# Content URI or unrecognized name — prompt for card number
			print("[Import] can't parse filename '%s', showing card number prompt" % filename)
			_pending_card_art_src = path
			_show_card_number_prompt()
			return  # Handle one at a time when prompting
	_CardScript.clear_texture_cache()


func _show_card_number_prompt() -> void:
	var popup := PopupPanel.new()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
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
	title.text = "Enter Card Number"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "e.g. ESD01-008, EBP02-045"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var line_edit := LineEdit.new()
	line_edit.placeholder_text = "ESD01-008"
	line_edit.add_theme_font_size_override("font_size", 18)
	line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(line_edit)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 36)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.pressed.connect(func():
		_pending_card_art_src = ""
		popup.hide()
		popup.queue_free())
	btn_row.add_child(cancel_btn)
	var ok_btn := Button.new()
	ok_btn.text = "OK"
	ok_btn.custom_minimum_size = Vector2(100, 36)
	ok_btn.add_theme_font_size_override("font_size", 16)
	ok_btn.pressed.connect(func():
		_confirm_card_art_import(line_edit.text.strip_edges())
		popup.hide()
		popup.queue_free())
	btn_row.add_child(ok_btn)
	vbox.add_child(btn_row)

	line_edit.text_submitted.connect(func(_text: String):
		_confirm_card_art_import(line_edit.text.strip_edges())
		popup.hide()
		popup.queue_free())

	margin.add_child(vbox)
	panel.add_child(margin)
	popup.add_child(panel)
	add_child(popup)
	popup.popup_centered()
	line_edit.grab_focus()


func _confirm_card_art_import(card_number: String) -> void:
	if card_number.is_empty() or _pending_card_art_src.is_empty():
		_pending_card_art_src = ""
		return
	var parts := card_number.split("-")
	if parts.size() < 2:
		print("[Import] invalid card number format: %s" % card_number)
		_pending_card_art_src = ""
		return
	var set_id := parts[0]
	var base := GameSettings.get_custom_base_path().path_join("cardArt")
	var target_dir := base.path_join(set_id)
	DirAccess.make_dir_recursive_absolute(target_dir)
	var dest := target_dir.path_join("%s.png" % card_number)
	var err := _copy_as_png(_pending_card_art_src, dest)
	print("[Import] card art (prompted): %s -> %s (err=%s)" % [card_number, dest, err])
	_pending_card_art_src = ""
	_CardScript.clear_texture_cache()


func _show_delete_all_card_art_confirm() -> void:
	var popup := PopupPanel.new()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
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
	title.text = "Delete All Custom Card Art?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "This will remove all imported card art images.\nThis cannot be undone."
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 36)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.pressed.connect(func():
		popup.hide()
		popup.queue_free())
	btn_row.add_child(cancel_btn)
	var delete_btn := Button.new()
	delete_btn.text = "Delete All"
	delete_btn.custom_minimum_size = Vector2(100, 36)
	delete_btn.add_theme_font_size_override("font_size", 16)
	delete_btn.pressed.connect(func():
		_execute_delete_all_card_art()
		popup.hide()
		popup.queue_free())
	btn_row.add_child(delete_btn)
	vbox.add_child(btn_row)

	margin.add_child(vbox)
	panel.add_child(margin)
	popup.add_child(panel)
	add_child(popup)
	popup.popup_centered()


func _execute_delete_all_card_art() -> void:
	var base := GameSettings.get_custom_base_path().path_join("cardArt")
	for set_id in CARD_ART_SETS:
		var set_dir := base.path_join(set_id)
		var dir := DirAccess.open(set_dir)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	_CardScript.clear_texture_cache()


func _show_remove_card_art_prompt() -> void:
	var popup := PopupPanel.new()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
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
	title.text = "Remove Card Art"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Enter the card number to remove (e.g. ESD01-008)"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var line_edit := LineEdit.new()
	line_edit.placeholder_text = "ESD01-008"
	line_edit.add_theme_font_size_override("font_size", 18)
	line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(line_edit)

	var status_label := Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.visible = false
	vbox.add_child(status_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(100, 36)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(func():
		popup.hide()
		popup.queue_free())
	btn_row.add_child(close_btn)
	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.custom_minimum_size = Vector2(100, 36)
	remove_btn.add_theme_font_size_override("font_size", 16)
	remove_btn.pressed.connect(func():
		_execute_remove_card_art(line_edit.text.strip_edges(), status_label))
	btn_row.add_child(remove_btn)
	vbox.add_child(btn_row)

	line_edit.text_submitted.connect(func(_text: String):
		_execute_remove_card_art(line_edit.text.strip_edges(), status_label))

	margin.add_child(vbox)
	panel.add_child(margin)
	popup.add_child(panel)
	add_child(popup)
	popup.popup_centered()
	line_edit.grab_focus()


func _execute_remove_card_art(card_number: String, status_label: Label) -> void:
	if card_number.is_empty():
		return
	var parts := card_number.split("-")
	if parts.size() < 2:
		status_label.text = "Invalid format. Use SET-NUMBER (e.g. ESD01-008)"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
		status_label.visible = true
		return
	var set_id := parts[0]
	var base := GameSettings.get_custom_base_path().path_join("cardArt")
	var target := base.path_join(set_id).path_join("%s.png" % card_number)
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
		status_label.text = "Removed %s" % card_number
		status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
		status_label.visible = true
		_CardScript.clear_texture_cache()
	else:
		status_label.text = "No custom art found for %s" % card_number
		status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4, 1.0))
		status_label.visible = true


func _on_import_card_back() -> void:
	DisplayServer.file_dialog_show("Import Card Back Image", "", "", false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, _image_filters,
		_on_card_back_file_selected)


func _on_card_back_file_selected(status: bool, paths: PackedStringArray, _idx: int) -> void:
	print("[Import] card back callback: status=%s paths=%s" % [status, paths])
	if not status or paths.is_empty():
		return
	var src := paths[0]
	var target := GameSettings.get_custom_base_path().path_join("cardBack")
	print("[Import] card back target dir: %s" % target)
	DirAccess.make_dir_recursive_absolute(target)
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var old := target.path_join("default.%s" % ext)
		if FileAccess.file_exists(old):
			DirAccess.remove_absolute(old)
	var dest := target.path_join("default.png")
	var err := _copy_as_png(src, dest)
	print("[Import] card back result: %s (exists=%s)" % [err, FileAccess.file_exists(dest)])
	_CardScript.clear_texture_cache()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


# --- Advanced modal ---

func _on_advanced_pressed() -> void:
	SfxManager.play("ui_click")
	var parts := _create_modal("Advanced")
	var popup: PopupPanel = parts[0]
	var vbox: VBoxContainer = parts[1]

	_add_toggle_row(vbox, "Use Mobile Layout", "use_mobile_layout")

	vbox.add_child(HSeparator.new())

	var redownload_btn := Button.new()
	redownload_btn.text = "Re-download Card Assets"
	redownload_btn.custom_minimum_size = Vector2(200, 40)
	redownload_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	redownload_btn.add_theme_font_size_override("font_size", 18)
	redownload_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		popup.hide()
		_show_redownload_confirm()
	)
	vbox.add_child(redownload_btn)

	_add_close_button(vbox, popup)
	_show_modal(popup)


const _ART_LOCALES := ["en", "ja"]


func _show_redownload_confirm() -> void:
	var modal_parts := _create_modal("Re-download Card Assets")
	var popup: PopupPanel = modal_parts[0]
	var vbox: VBoxContainer = modal_parts[1]

	var prompt := Label.new()
	prompt.text = tr("STR_OPTIONS_ART_PICK_LANGUAGE")
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 16)
	vbox.add_child(prompt)

	for art_locale in _ART_LOCALES:
		vbox.add_child(_build_locale_row(art_locale, popup))

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var cancel_btn := Button.new()
	cancel_btn.text = tr("STR_GB_CANCEL")
	cancel_btn.custom_minimum_size = Vector2(120, 40)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.add_theme_font_size_override("font_size", 18)
	cancel_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		popup.hide())
	btn_row.add_child(cancel_btn)
	vbox.add_child(btn_row)

	_show_modal(popup)


func _build_locale_row(art_locale: String, popup: PopupPanel) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var lang_label := Label.new()
	lang_label.text = tr("STR_LANG_" + art_locale.to_upper())
	lang_label.custom_minimum_size = Vector2(100, 0)
	lang_label.add_theme_font_size_override("font_size", 18)
	row.add_child(lang_label)

	var cached_count: int = ArtworkDownloader.get_cached_count(art_locale)
	var status_label := Label.new()
	if cached_count > 0:
		status_label.text = tr("STR_OPTIONS_ART_STATUS_CACHED_FMT").replace("{N}", str(cached_count))
	else:
		status_label.text = tr("STR_OPTIONS_ART_STATUS_NONE")
	status_label.custom_minimum_size = Vector2(180, 0)
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	row.add_child(status_label)

	var action_btn := Button.new()
	action_btn.text = tr("STR_OPTIONS_ART_REDOWNLOAD") if cached_count > 0 else tr("STR_OPTIONS_ART_DOWNLOAD")
	action_btn.custom_minimum_size = Vector2(140, 36)
	action_btn.add_theme_font_size_override("font_size", 16)
	action_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		GameSettings.card_art_locale = art_locale
		GameSettings.save()
		ArtworkDownloader.clear_downloaded_artwork(art_locale)
		_CardScript.clear_texture_cache()
		popup.hide()
		NetworkManager.change_scene("res://scenes/ui/LoadingScreen.tscn"))
	row.add_child(action_btn)

	return row


func _on_audio_pressed() -> void:
	SfxManager.play("ui_click")
	var parts := _create_modal("Audio")
	var popup: PopupPanel = parts[0]
	var vbox: VBoxContainer = parts[1]

	# Sound volume slider (OFF, 25%, 50%, 75%, 100%)
	var sound_row := HBoxContainer.new()
	var sound_label := Label.new()
	sound_label.text = "Sound Effects"
	sound_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_label.add_theme_font_size_override("font_size", 18)
	sound_row.add_child(sound_label)
	var sound_volume_labels := ["OFF", "25%", "50%", "75%", "100%"]
	var sound_value_label := Label.new()
	sound_value_label.text = sound_volume_labels[GameSettings.sound_volume]
	sound_value_label.custom_minimum_size = Vector2(40, 0)
	sound_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sound_value_label.add_theme_font_size_override("font_size", 16)
	var sound_slider := HSlider.new()
	sound_slider.min_value = 0
	sound_slider.max_value = 4
	sound_slider.step = 1
	sound_slider.value = GameSettings.sound_volume
	sound_slider.custom_minimum_size = Vector2(140, 0)
	sound_slider.value_changed.connect(func(val: float):
		GameSettings.sound_volume = int(val)
		GameSettings.save()
		sound_value_label.text = sound_volume_labels[int(val)]
	)
	sound_row.add_child(sound_slider)
	sound_row.add_child(sound_value_label)
	vbox.add_child(sound_row)

	# Music volume slider (OFF, 25%, 50%, 75%, 100%)
	var music_row := HBoxContainer.new()
	var music_label := Label.new()
	music_label.text = "Music"
	music_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_label.add_theme_font_size_override("font_size", 18)
	music_row.add_child(music_label)
	var music_volume_labels := ["OFF", "25%", "50%", "75%", "100%"]
	var music_value_label := Label.new()
	music_value_label.text = music_volume_labels[GameSettings.music_volume]
	music_value_label.custom_minimum_size = Vector2(40, 0)
	music_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_value_label.add_theme_font_size_override("font_size", 16)
	var music_slider := HSlider.new()
	music_slider.min_value = 0
	music_slider.max_value = 4
	music_slider.step = 1
	music_slider.value = GameSettings.music_volume
	music_slider.custom_minimum_size = Vector2(140, 0)
	music_slider.value_changed.connect(func(val: float):
		GameSettings.music_volume = int(val)
		GameSettings.save()
		MusicManager.set_volume(int(val))
		music_value_label.text = music_volume_labels[int(val)]
	)
	music_row.add_child(music_slider)
	music_row.add_child(music_value_label)
	vbox.add_child(music_row)

	_add_close_button(vbox, popup)
	_show_modal(popup)


func _on_back_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")
