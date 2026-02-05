extends Control

@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	start_button.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/board/GameBoard.tscn")
