extends Control


@onready var rumble_button: Button = $CenterContainer/VBoxContainer/RumbleButton
@onready var private_button: Button = $CenterContainer/VBoxContainer/PrivateButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	rumble_button.pressed.connect(_on_rumble_pressed)
	private_button.pressed.connect(_on_private_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _on_rumble_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/PublicLobby.tscn")


func _on_private_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/OnlineLobby.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
