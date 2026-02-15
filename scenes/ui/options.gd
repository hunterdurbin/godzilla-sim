extends Control

@onready var player_name_edit: LineEdit = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/PlayerNameRow/PlayerNameEdit
@onready var auto_draw_check: CheckButton = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AutoDrawRow/AutoDrawCheck
@onready var auto_phase_check: CheckButton = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AutoPhaseRow/AutoPhaseCheck
@onready var auto_discard_strategies_check: CheckButton = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AutoDiscardStrategiesRow/Check
@onready var auto_reset_rage_check: CheckButton = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AutoResetRageRow/Check
@onready var auto_counter_check_check: CheckButton = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AutoCounterCheckRow/Check
@onready var auto_advance_check: CheckButton = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AutoAdvanceRow/Check
@onready var confirm_main_phase_pass_check: CheckButton = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ConfirmMainPhasePassRow/Check
@onready var sort_type_order_option: OptionButton = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SortTypeOrderRow/SortTypeOrderOption
@onready var sort_rank_order_option: OptionButton = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SortRankOrderRow/SortRankOrderOption
@onready var back_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	player_name_edit.text = GameSettings.player_name
	auto_draw_check.button_pressed = GameSettings.auto_draw
	auto_phase_check.button_pressed = GameSettings.auto_phase_advance
	auto_discard_strategies_check.button_pressed = GameSettings.auto_discard_strategies
	auto_reset_rage_check.button_pressed = GameSettings.auto_reset_rage
	auto_counter_check_check.button_pressed = GameSettings.auto_counter_check
	auto_advance_check.button_pressed = GameSettings.auto_advance

	player_name_edit.text_changed.connect(_on_player_name_changed)
	auto_draw_check.toggled.connect(_on_auto_draw_toggled)
	auto_phase_check.toggled.connect(_on_auto_phase_toggled)
	auto_discard_strategies_check.toggled.connect(_on_setting_toggled.bind("auto_discard_strategies"))
	auto_reset_rage_check.toggled.connect(_on_setting_toggled.bind("auto_reset_rage"))
	auto_counter_check_check.toggled.connect(_on_setting_toggled.bind("auto_counter_check"))
	auto_advance_check.toggled.connect(_on_setting_toggled.bind("auto_advance"))
	confirm_main_phase_pass_check.button_pressed = GameSettings.confirm_main_phase_pass
	confirm_main_phase_pass_check.toggled.connect(_on_setting_toggled.bind("confirm_main_phase_pass"))
	sort_type_order_option.selected = GameSettings.hand_sort_type_order
	sort_rank_order_option.selected = 0 if GameSettings.hand_sort_rank_ascending else 1
	sort_type_order_option.item_selected.connect(_on_sort_type_order_selected)
	sort_rank_order_option.item_selected.connect(_on_sort_rank_order_selected)
	back_button.pressed.connect(_on_back_pressed)


func _on_player_name_changed(new_text: String) -> void:
	GameSettings.player_name = new_text
	GameSettings.save()


func _on_auto_draw_toggled(enabled: bool) -> void:
	GameSettings.auto_draw = enabled
	GameSettings.save()


func _on_auto_phase_toggled(enabled: bool) -> void:
	GameSettings.auto_phase_advance = enabled
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


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
