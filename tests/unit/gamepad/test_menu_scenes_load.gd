extends GdUnitTestSuite

## Menu/lobby scenes must instantiate cleanly with the gamepad wiring in
## place (focus-context calls in the scripts, the main menu's hint row).
## Instantiation compiles every attached script — a broken reference fails
## here instead of at first launch.

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


func test_main_menu_has_confirm_hint_row() -> void:
	var packed: PackedScene = load("res://scenes/menus/MainMenu.tscn")
	var menu: Control = auto_free(packed.instantiate())
	add_child(menu)  # hint row is built in _ready
	var row: OverlayHintRow = menu._pad_hint_row
	assert_object(row).is_not_null()
	var glyph: ControllerGlyph = null
	for child in row.get_children():
		if child is ControllerGlyph:
			glyph = child
			break
	assert_object(glyph).override_failure_message("no glyph in the hint row").is_not_null()
	assert_that(glyph.action).is_equal(&"pad_confirm")
	# The old on-button glyph is gone.
	assert_object(menu.start_button.get_node_or_null("ConfirmGlyph")).is_null()
