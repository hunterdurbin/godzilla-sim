extends Node

const SETTINGS_PATH := "user://settings.cfg"

var player_name: String = ""
var auto_draw: bool = true
var auto_phase_advance: bool = true
var auto_discard_strategies: bool = true
var auto_reset_rage: bool = true
var auto_counter_check: bool = true
var auto_advance: bool = true
var confirm_main_phase_pass: bool = false
var hand_sort_type_order: int = 0  # 0-5 index into type permutations
var hand_sort_rank_ascending: bool = true

# Visual settings
var custom_playmat_enabled: bool = false
var custom_playmat_opponent: bool = false
var color_overlay_mode: int = 3  # 0=none, 1=self only, 2=opponent only, 3=both
var custom_card_art_enabled: bool = false
var custom_card_back_mode: int = 0  # 0=disabled, 1=myself only, 2=both players

# Update settings
var skipped_version: String = ""


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
	config.set_value("gameplay", "confirm_main_phase_pass", confirm_main_phase_pass)
	config.set_value("gameplay", "hand_sort_type_order", hand_sort_type_order)
	config.set_value("gameplay", "hand_sort_rank_ascending", hand_sort_rank_ascending)
	config.set_value("visual", "custom_playmat_enabled", custom_playmat_enabled)
	config.set_value("visual", "custom_playmat_opponent", custom_playmat_opponent)
	config.set_value("visual", "color_overlay_mode", color_overlay_mode)
	config.set_value("visual", "custom_card_art_enabled", custom_card_art_enabled)
	config.set_value("visual", "custom_card_back_mode", custom_card_back_mode)
	config.set_value("updates", "skipped_version", skipped_version)
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
	confirm_main_phase_pass = config.get_value("gameplay", "confirm_main_phase_pass", false)
	hand_sort_type_order = config.get_value("gameplay", "hand_sort_type_order", 0)
	hand_sort_rank_ascending = config.get_value("gameplay", "hand_sort_rank_ascending", true)
	custom_playmat_enabled = config.get_value("visual", "custom_playmat_enabled", false)
	custom_playmat_opponent = config.get_value("visual", "custom_playmat_opponent", false)
	color_overlay_mode = config.get_value("visual", "color_overlay_mode", 3)
	custom_card_art_enabled = config.get_value("visual", "custom_card_art_enabled", false)
	custom_card_back_mode = config.get_value("visual", "custom_card_back_mode", 0)
	skipped_version = config.get_value("updates", "skipped_version", "")
