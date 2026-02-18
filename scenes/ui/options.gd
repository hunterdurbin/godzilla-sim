extends Control

@onready var player_name_edit: LineEdit = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/PlayerNameRow/PlayerNameEdit
@onready var automation_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AutomationButton
@onready var customize_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CustomizeButton
@onready var back_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	player_name_edit.text = GameSettings.player_name
	player_name_edit.text_changed.connect(_on_player_name_changed)
	automation_button.pressed.connect(_on_automation_pressed)
	customize_button.pressed.connect(_on_customize_pressed)
	back_button.pressed.connect(_on_back_pressed)


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

func _on_customize_pressed() -> void:
	var parts := _create_modal("Customize")
	var popup: PopupPanel = parts[0]
	var vbox: VBoxContainer = parts[1]

	_add_toggle_row(vbox, "Custom Playmat", "custom_playmat_enabled")
	_add_toggle_row(vbox, "Apply Playmat to Opponent", "custom_playmat_opponent")

	var playmat_hint := Label.new()
	playmat_hint.text = "Image must be named: default.png (or .jpg, .jpeg, .webp)"
	playmat_hint.add_theme_font_size_override("font_size", 12)
	playmat_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	vbox.add_child(playmat_hint)

	var playmat_folder_row := HBoxContainer.new()
	playmat_folder_row.alignment = BoxContainer.ALIGNMENT_END
	var playmat_folder_btn := Button.new()
	playmat_folder_btn.text = "Open Playmat Folder"
	playmat_folder_btn.add_theme_font_size_override("font_size", 14)
	playmat_folder_btn.pressed.connect(_on_open_folder.bind("user://custom/playmat"))
	playmat_folder_row.add_child(playmat_folder_btn)
	vbox.add_child(playmat_folder_row)

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
	art_hint.text = "Place images as: <SET>/<CARD_NUMBER>.png (e.g. ESD01/ESD01-008.png)"
	art_hint.add_theme_font_size_override("font_size", 12)
	art_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	vbox.add_child(art_hint)

	var art_folder_row := HBoxContainer.new()
	art_folder_row.alignment = BoxContainer.ALIGNMENT_END
	var art_folder_btn := Button.new()
	art_folder_btn.text = "Open Card Art Folder"
	art_folder_btn.add_theme_font_size_override("font_size", 14)
	art_folder_btn.pressed.connect(_on_open_folder.bind("user://custom/cardArt"))
	art_folder_row.add_child(art_folder_btn)
	vbox.add_child(art_folder_row)

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
	back_hint.text = "Image must be named: default.png (or .jpg, .jpeg, .webp)"
	back_hint.add_theme_font_size_override("font_size", 12)
	back_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	vbox.add_child(back_hint)

	var back_folder_row := HBoxContainer.new()
	back_folder_row.alignment = BoxContainer.ALIGNMENT_END
	var back_folder_btn := Button.new()
	back_folder_btn.text = "Open Card Back Folder"
	back_folder_btn.add_theme_font_size_override("font_size", 14)
	back_folder_btn.pressed.connect(_on_open_folder.bind("user://custom/cardBack"))
	back_folder_row.add_child(back_folder_btn)
	vbox.add_child(back_folder_row)

	_add_close_button(vbox, popup)
	_show_modal(popup)


const CARD_ART_PATH := "user://custom/cardArt"
const CARD_ART_SETS := ["EBP01", "EBP02", "EBP03", "EPR", "ESD01", "ESD02"]


func _on_open_folder(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	if path == CARD_ART_PATH:
		for set_id in CARD_ART_SETS:
			DirAccess.make_dir_recursive_absolute(path.path_join(set_id))
	OS.shell_open(ProjectSettings.globalize_path(path))


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
