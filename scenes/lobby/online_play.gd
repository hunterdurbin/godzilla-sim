extends Control


@onready var rumble_button: Button = $CenterContainer/VBoxContainer/RumbleButton
@onready var private_button: Button = $CenterContainer/VBoxContainer/PrivateButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	rumble_button.pressed.connect(_on_rumble_pressed)
	private_button.pressed.connect(_on_private_pressed)
	back_button.pressed.connect(_on_back_pressed)
	GamepadHelper.push_focus_context(self, func() -> Control: return rumble_button)


func _exit_tree() -> void:
	GamepadHelper.pop_focus_context(self)


func _on_rumble_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/lobby/PublicLobby.tscn")


func _on_private_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/lobby/OnlineLobby.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _on_back_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/menus/MainMenu.tscn")
