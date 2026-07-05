extends GdUnitTestSuite

## Menu/lobby scenes must instantiate cleanly with the gamepad wiring in
## place (ControllerGlyph ext_resource in MainMenu.tscn, focus-context calls
## in the scripts). Instantiation compiles every attached script — a broken
## reference fails here instead of at first launch.

const SCENES: Array[String] = [
	"res://scenes/menus/MainMenu.tscn",
	"res://scenes/menus/Options.tscn",
	"res://scenes/lobby/LanLobby.tscn",
	"res://scenes/lobby/OnlineLobby.tscn",
	"res://scenes/lobby/OnlinePlay.tscn",
	"res://scenes/lobby/PublicLobby.tscn",
]


func test_scenes_instantiate() -> void:
	for path in SCENES:
		var packed: PackedScene = load(path)
		assert_object(packed).override_failure_message("Failed to load " + path).is_not_null()
		var inst: Node = auto_free(packed.instantiate())
		assert_object(inst).override_failure_message("Failed to instantiate " + path).is_not_null()


func test_main_menu_has_confirm_glyph() -> void:
	var packed: PackedScene = load("res://scenes/menus/MainMenu.tscn")
	var menu: Node = auto_free(packed.instantiate())
	var glyph := menu.get_node("CenterContainer/VBoxContainer/StartButton/ConfirmGlyph")
	assert_object(glyph).is_not_null()
	assert_bool(glyph is ControllerGlyph).is_true()
	assert_that((glyph as ControllerGlyph).action).is_equal(&"pad_confirm")
