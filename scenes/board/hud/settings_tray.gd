extends VBoxContainer

## Drop-in settings tray. Renders a row of toggleable auto-behaviors
## (auto draw, auto phase advance, auto counter check, etc.) bound to
## GameSettings. Click a toggle to flip the value — persists via
## GameSettings.save().
##
## Each setting is exposed via the inspector as an @export bool so a
## designer can hide a row by setting its corresponding flag to false.

const _SETTINGS: Array[Dictionary] = [
	{"key": "auto_draw", "label": "STR_GS_AUTO_DRAW"},
	{"key": "auto_phase_advance", "label": "STR_GS_AUTO_PHASE"},
	{"key": "auto_discard_strategies", "label": "STR_GS_AUTO_DISCARD"},
	{"key": "auto_reset_rage", "label": "STR_GS_AUTO_RESET_RAGE"},
	{"key": "auto_counter_check", "label": "STR_GS_AUTO_COUNTER"},
	{"key": "auto_advance", "label": "STR_GS_AUTO_ADVANCE"},
	{"key": "confirm_main_phase_pass", "label": "STR_GS_CONFIRM_PASS"},
]

@export_group("Visible settings")
@export var show_auto_draw: bool = true
@export var show_auto_phase_advance: bool = true
@export var show_auto_discard_strategies: bool = true
@export var show_auto_reset_rage: bool = true
@export var show_auto_counter_check: bool = true
@export var show_auto_advance: bool = true
@export var show_confirm_main_phase_pass: bool = true
@export_group("")

var _checks: Dictionary = {}  # setting_key → CheckBox


func _ready() -> void:
	_build_rows()
	_refresh_all()


func _build_rows() -> void:
	for entry in _SETTINGS:
		var key: String = entry["key"]
		if not _is_visible_for(key):
			continue
		var cb := CheckBox.new()
		cb.text = tr(entry["label"]) if entry["label"].begins_with("STR_") else entry["label"]
		cb.toggled.connect(_on_toggled.bind(key))
		add_child(cb)
		_checks[key] = cb


func _is_visible_for(key: String) -> bool:
	match key:
		"auto_draw": return show_auto_draw
		"auto_phase_advance": return show_auto_phase_advance
		"auto_discard_strategies": return show_auto_discard_strategies
		"auto_reset_rage": return show_auto_reset_rage
		"auto_counter_check": return show_auto_counter_check
		"auto_advance": return show_auto_advance
		"confirm_main_phase_pass": return show_confirm_main_phase_pass
	return false


func _refresh_all() -> void:
	for key in _checks:
		var cb: CheckBox = _checks[key]
		cb.set_pressed_no_signal(bool(GameSettings.get(key)))


func _on_toggled(button_pressed: bool, key: String) -> void:
	GameSettings.set(key, button_pressed)
	GameSettings.save()
