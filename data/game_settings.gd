extends Node

const SETTINGS_PATH := "user://settings.cfg"

var player_name: String = ""
var auto_draw: bool = true
var auto_phase_advance: bool = true


func _ready() -> void:
	_load()
	if player_name.is_empty():
		player_name = "Player%06d" % (randi() % 1000000)
		_save()


func save() -> void:
	_save()


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("gameplay", "player_name", player_name)
	config.set_value("gameplay", "auto_draw", auto_draw)
	config.set_value("gameplay", "auto_phase_advance", auto_phase_advance)
	config.save(SETTINGS_PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	player_name = config.get_value("gameplay", "player_name", "")
	auto_draw = config.get_value("gameplay", "auto_draw", true)
	auto_phase_advance = config.get_value("gameplay", "auto_phase_advance", true)
