extends Node

const SETTINGS_PATH := "user://settings.cfg"

var player_name: String = ""
var auto_draw: bool = true
var auto_phase_advance: bool = true
var auto_discard_strategies: bool = true
var auto_reset_rage: bool = true
var auto_counter_check: bool = true
var auto_advance: bool = true


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
	config.set_value("gameplay", "auto_discard_strategies", auto_discard_strategies)
	config.set_value("gameplay", "auto_reset_rage", auto_reset_rage)
	config.set_value("gameplay", "auto_counter_check", auto_counter_check)
	config.set_value("gameplay", "auto_advance", auto_advance)
	config.save(SETTINGS_PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	player_name = config.get_value("gameplay", "player_name", "")
	auto_draw = config.get_value("gameplay", "auto_draw", true)
	auto_phase_advance = config.get_value("gameplay", "auto_phase_advance", true)
	auto_discard_strategies = config.get_value("gameplay", "auto_discard_strategies", true)
	auto_reset_rage = config.get_value("gameplay", "auto_reset_rage", true)
	auto_counter_check = config.get_value("gameplay", "auto_counter_check", true)
	auto_advance = config.get_value("gameplay", "auto_advance", true)
