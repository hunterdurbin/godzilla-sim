@tool
class_name GlyphDB
extends RefCounted
## Static lookup for controller button glyph textures and default bindings.
##
## Glyph files live in assets/ui/input_glyphs/<type>/<button>.png and are named
## by PHYSICAL button position (SDL layout), not label — the Switch A/B swap is
## baked into the asset slice (see assets/ui/input_glyphs/ATTRIBUTION.md).
##
## This class is @tool-safe and touches no autoloads so ControllerGlyph can
## preview real textures inside the editor.

const BASE_PATH := "res://assets/ui/input_glyphs"
const TYPES: Array[String] = ["xbox", "playstation", "switch", "generic"]

## Physical controller_* action -> glyph filename.
const FILE_FOR_PHYSICAL := {
	&"controller_face_south": "face_south.png",
	&"controller_face_east": "face_east.png",
	&"controller_face_west": "face_west.png",
	&"controller_face_north": "face_north.png",
	&"controller_dpad_up": "dpad_up.png",
	&"controller_dpad_down": "dpad_down.png",
	&"controller_dpad_left": "dpad_left.png",
	&"controller_dpad_right": "dpad_right.png",
	&"controller_bumper_l": "bumper_l.png",
	&"controller_bumper_r": "bumper_r.png",
	&"controller_trigger_l": "trigger_l.png",
	&"controller_trigger_r": "trigger_r.png",
	&"controller_start": "start.png",
	&"controller_select": "select.png",
	&"controller_stick_press_l": "stick_press_l.png",
	&"controller_lstick": "lstick.png",
}

## Physical actions the rebind capture accepts (glyph-able buttons only;
## sticks and dpad stay reserved for navigation).
const REBIND_CAPTURABLE: Array[StringName] = [
	&"controller_face_south", &"controller_face_east", &"controller_face_west",
	&"controller_face_north", &"controller_bumper_l", &"controller_bumper_r",
	&"controller_trigger_l", &"controller_trigger_r", &"controller_start",
	&"controller_select", &"controller_stick_press_l",
]


static func get_texture(type: String, physical: StringName) -> Texture2D:
	var file: String = FILE_FOR_PHYSICAL.get(physical, "")
	if file.is_empty():
		return null
	var path := "%s/%s/%s" % [BASE_PATH, type if type in TYPES else "generic", file]
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## Controller vendor USB ids — used to see through Steam Input's virtual
## gamepad, which masks the joy name but not (always) the hardware ids.
const VENDOR_SONY := 0x054C
const VENDOR_NINTENDO := 0x057E
const VENDOR_MICROSOFT := 0x045E


## Joypad device name -> glyph set. Mirrors spire's joy-name string matching.
## joy_info is Input.get_joy_info(device); under Steam Input the name becomes
## "Steam Virtual Gamepad" etc., so the vendor id is the tiebreaker there.
static func detect_type(joy_name: String, joy_info: Dictionary = {}) -> String:
	var lower := joy_name.to_lower()
	if lower.contains("steam deck"):
		return "generic" # the generic art IS the Kenney Steam Deck set
	if lower.contains("steam"):
		# Steam Virtual Gamepad / Steam Controller: recover the real hardware
		# from the vendor id; otherwise assume xbox — Steam emulates XInput,
		# so xbox prompts are what the emulation layer presents.
		match int(joy_info.get("vendor_id", 0)):
			VENDOR_SONY:
				return "playstation"
			VENDOR_NINTENDO:
				return "switch"
			VENDOR_MICROSOFT:
				return "xbox"
		return "xbox"
	if lower.contains("xbox") or lower.contains("xinput"):
		return "xbox"
	if lower.contains("ps5") or lower.contains("ps4") or lower.contains("ps3") \
			or lower.contains("dualshock") or lower.contains("dualsense") \
			or lower.contains("playstation") or lower.contains("sony"):
		return "playstation"
	if lower.contains("switch") or lower.contains("joy-con") or lower.contains("joycon") \
			or lower.contains("pro controller") or lower.contains("nintendo"):
		return "switch"
	return "generic"


## Default logical pad_* action -> physical controller_* action.
static func default_map() -> Dictionary:
	return {
		&"pad_confirm": &"controller_face_south",
		&"pad_cancel": &"controller_face_east",
		&"pad_inspect": &"controller_face_north",
		&"pad_end_main": &"controller_face_west",
		&"pad_region_prev": &"controller_bumper_l",
		&"pad_region_next": &"controller_bumper_r",
		&"pad_play_card_rage": &"controller_trigger_l",
		&"pad_play_card_invasion": &"controller_trigger_r",
		&"pad_menu": &"controller_start",
		&"pad_chat": &"controller_select",
	}
