extends Control

@onready var player_name_edit: LineEdit = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/PlayerNameRow/PlayerNameEdit
@onready var auto_draw_check: CheckButton = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AutoDrawRow/AutoDrawCheck
@onready var auto_phase_check: CheckButton = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AutoPhaseRow/AutoPhaseCheck
@onready var back_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	player_name_edit.text = GameSettings.player_name
	auto_draw_check.button_pressed = GameSettings.auto_draw
	auto_phase_check.button_pressed = GameSettings.auto_phase_advance

	player_name_edit.text_changed.connect(_on_player_name_changed)
	auto_draw_check.toggled.connect(_on_auto_draw_toggled)
	auto_phase_check.toggled.connect(_on_auto_phase_toggled)
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


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
