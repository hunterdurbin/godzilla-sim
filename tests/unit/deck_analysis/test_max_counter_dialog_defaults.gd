extends GdUnitTestSuite

## MaxCounterDialog's per-deck default detection: decks whose monster deck
## runs EBP03-013 (grows strategy zones to 3 for the rest of the game) open
## the Max Counter Power preview with the 3-zone assumption pre-selected.
## Plus window/pad invariants: fixed (borderless) window, and the d-pad mesh
## covering exactly the param OptionButtons and the OK button.


func test_deck_with_ebp03_013_expands_strategy_zones() -> void:
	var monster_entries := [
		{"card_number": "EBP02-052", "quantity": 1},
		{"card_number": "EBP03-013", "quantity": 1},
	]
	assert_bool(MaxCounterDialog.deck_expands_strategy_zones(monster_entries)).is_true()


func test_deck_without_ebp03_013_keeps_two_zones() -> void:
	var monster_entries := [{"card_number": "EBP02-052", "quantity": 1}]
	assert_bool(MaxCounterDialog.deck_expands_strategy_zones(monster_entries)).is_false()
	assert_bool(MaxCounterDialog.deck_expands_strategy_zones([])).is_false()


func test_dialog_is_borderless_fixed_window() -> void:
	var dialog: MaxCounterDialog = auto_free(MaxCounterDialog.new())
	assert_bool(dialog.borderless).is_true()
	assert_bool(dialog.unresizable).is_true()


func test_pad_focus_mesh_links_params_and_ok() -> void:
	var dialog: MaxCounterDialog = auto_free(MaxCounterDialog.new())
	add_child(dialog)
	var ok := dialog.get_ok_button()

	# Hidden strategy option (deck without EBP03-013) is left out of the mesh:
	# ← from the first param wraps straight to the rage option.
	dialog._strategy_count_row.visible = false
	dialog._wire_pad_focus()
	var zone: OptionButton = dialog._zone_option
	assert_object(zone.get_node(zone.focus_neighbor_bottom)).is_same(ok)
	assert_object(zone.get_node(zone.focus_neighbor_left)).is_same(dialog._rage_option)
	assert_object(ok.get_node(ok.focus_neighbor_top)).is_same(zone)
	assert_object(ok.get_node(ok.focus_neighbor_bottom)).is_same(zone)
	# OK is a one-button band: it self-loops horizontally, pinning every
	# direction so the geometric fallback can't reach the card previews.
	assert_object(ok.get_node(ok.focus_neighbor_left)).is_same(ok)
	assert_object(ok.get_node(ok.focus_neighbor_right)).is_same(ok)

	# 3-strategy-zone decks re-wire with the fourth option in the row.
	dialog._strategy_count_row.visible = true
	dialog._wire_pad_focus()
	assert_object(zone.get_node(zone.focus_neighbor_left)).is_same(dialog._strategy_count_option)


func test_pad_back_closes_on_leading_pad_cancel() -> void:
	GamepadHelper._cancel_swallow_frame = -100  # no stale twin swallow
	var dialog: MaxCounterDialog = auto_free(MaxCounterDialog.new())
	add_child(dialog)
	dialog.show()

	# The LEADING pad_cancel closes (GamepadHelper.wire_pad_close)...
	var lead := InputEventAction.new()
	lead.action = &"pad_cancel"
	lead.pressed = true
	dialog.window_input.emit(lead)
	assert_bool(dialog.visible).is_false()

	# ...and the mirrored ui_cancel twin is stamped as spent, so it can't
	# leak to the deck builder's back handler underneath.
	var twin := InputEventAction.new()
	twin.action = &"ui_cancel"
	twin.pressed = true
	assert_bool(GamepadHelper.is_swallowed_cancel(twin)) \
		.override_failure_message("the close did not stamp the twin swallow").is_true()
