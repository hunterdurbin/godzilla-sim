extends GdUnitTestSuite

## OverlayGridUtil focus meshes — the controller navigation of the board
## overlays: grid-internal row-major wrap, chrome rows joining the vertical
## cycle, hidden-chrome filtering, two-grid cross links, focus index capture
## and restore, and the deck-arrange pile math statics.

class StubCard:
	extends Control
	@warning_ignore("unused_signal")
	signal card_clicked(card: Control)
	var is_selectable: bool = true


var _root: Control


func before_test() -> void:
	_root = Control.new()
	add_child(_root)


func after_test() -> void:
	_root.queue_free()


func _make_grid(count: int, cols: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = cols
	for i in range(count):
		grid.add_child(StubCard.new())
	_root.add_child(grid)
	return grid


func _make_button(button_visible: bool = true) -> Button:
	var button := Button.new()
	button.visible = button_visible
	_root.add_child(button)
	return button


func _neighbor(from: Control, side: String) -> Control:
	var path: NodePath
	match side:
		"left": path = from.focus_neighbor_left
		"right": path = from.focus_neighbor_right
		"up": path = from.focus_neighbor_top
		"down": path = from.focus_neighbor_bottom
	if path.is_empty():
		return null
	return from.get_node_or_null(path)


func test_grid_cards_skips_non_cards() -> void:
	var grid := _make_grid(2, 3)
	grid.add_child(Label.new()) # e.g. the empty-pile label
	assert_int(OverlayGridUtil.grid_cards(grid).size()).is_equal(2)


func test_legacy_wrap_without_chrome() -> void:
	# 5 cards, 3 columns: [0 1 2] / [3 4]
	var grid := _make_grid(5, 3)
	OverlayGridUtil.wire_overlay_focus(grid, [], [])
	var cards := OverlayGridUtil.grid_cards(grid)
	assert_object(_neighbor(cards[0], "right")).is_same(cards[1])
	assert_object(_neighbor(cards[2], "right")).is_same(cards[0]) # row wrap
	assert_object(_neighbor(cards[0], "left")).is_same(cards[2])
	assert_object(_neighbor(cards[0], "down")).is_same(cards[3])
	assert_object(_neighbor(cards[0], "up")).is_same(cards[3]) # vertical wrap
	assert_object(_neighbor(cards[2], "up")).is_same(cards[4]) # clamped col
	assert_object(_neighbor(cards[4], "down")).is_same(cards[1])


func test_bottom_chrome_joins_vertical_cycle() -> void:
	var grid := _make_grid(5, 3)
	var close := _make_button()
	OverlayGridUtil.wire_overlay_focus(grid, [], [close])
	var cards := OverlayGridUtil.grid_cards(grid)
	# Bottom row exits down into the chrome, top row exits up into it (a lone
	# chrome row serves both directions), chrome re-enters the grid.
	assert_object(_neighbor(cards[3], "down")).is_same(close)
	assert_object(_neighbor(cards[2], "down")).is_same(close) # short last row
	assert_object(_neighbor(cards[0], "up")).is_same(close)
	assert_object(_neighbor(close, "up")).is_same(cards[3]) # bottom row
	assert_object(_neighbor(close, "down")).is_same(cards[0]) # top row
	# Interior vertical edges are untouched.
	assert_object(_neighbor(cards[0], "down")).is_same(cards[3])


func test_top_and_bottom_chrome_cycle() -> void:
	var grid := _make_grid(4, 4)
	var toggle := _make_button()
	var view_board := _make_button()
	var skip := _make_button()
	OverlayGridUtil.wire_overlay_focus(grid, [toggle, view_board], [skip])
	var cards := OverlayGridUtil.grid_cards(grid)
	assert_object(_neighbor(cards[0], "up")).is_same(toggle)
	assert_object(_neighbor(cards[1], "up")).is_same(view_board) # clamped idx
	assert_object(_neighbor(cards[3], "up")).is_same(view_board)
	assert_object(_neighbor(cards[0], "down")).is_same(skip)
	# Chrome rows link to each other, closing the cycle.
	assert_object(_neighbor(toggle, "up")).is_same(skip)
	assert_object(_neighbor(skip, "down")).is_same(toggle)
	assert_object(_neighbor(toggle, "down")).is_same(cards[0])
	assert_object(_neighbor(skip, "up")).is_same(cards[0]) # last row start
	# Chrome wraps horizontally within its row.
	assert_object(_neighbor(toggle, "right")).is_same(view_board)
	assert_object(_neighbor(view_board, "right")).is_same(toggle)
	assert_object(_neighbor(toggle, "left")).is_same(view_board)


func test_hidden_chrome_is_filtered() -> void:
	var grid := _make_grid(2, 3)
	var hidden_skip := _make_button(false)
	OverlayGridUtil.wire_overlay_focus(grid, [], [hidden_skip])
	var cards := OverlayGridUtil.grid_cards(grid)
	# Behaves exactly like the no-chrome wrap.
	assert_object(_neighbor(cards[0], "down")).is_same(cards[0])
	assert_bool(hidden_skip.focus_neighbor_top.is_empty()).is_true()


func test_empty_grid_cycles_chrome_only() -> void:
	var grid := _make_grid(0, 3)
	var toggle := _make_button()
	var close := _make_button()
	OverlayGridUtil.wire_overlay_focus(grid, [toggle], [close])
	assert_object(_neighbor(toggle, "down")).is_same(close)
	assert_object(_neighbor(toggle, "up")).is_same(close)
	assert_object(_neighbor(close, "up")).is_same(toggle)
	assert_object(_neighbor(close, "down")).is_same(toggle)


func test_two_grid_cross_links() -> void:
	# Left: [0 1 2] / [3 4] — Right: [0 1]
	var left := _make_grid(5, 3)
	var right := _make_grid(2, 3)
	var confirm := _make_button()
	OverlayGridUtil.wire_two_grid_focus(left, right, [], [confirm])
	var l := OverlayGridUtil.grid_cards(left)
	var r := OverlayGridUtil.grid_cards(right)
	# Right edge of a left row crosses into the right grid (row-clamped)...
	assert_object(_neighbor(l[2], "right")).is_same(r[0])
	assert_object(_neighbor(l[4], "right")).is_same(r[0]) # row 1 clamps to 0
	# ...and the horizontal cycle closes through both grids.
	assert_object(_neighbor(r[1], "right")).is_same(l[0])
	assert_object(_neighbor(l[0], "left")).is_same(r[1])
	assert_object(_neighbor(r[0], "left")).is_same(l[2])
	# Both grids exit vertically into the shared chrome.
	assert_object(_neighbor(l[3], "down")).is_same(confirm)
	assert_object(_neighbor(r[0], "down")).is_same(confirm)
	# Chrome anchors onto the left (non-empty) grid.
	assert_object(_neighbor(confirm, "up")).is_same(l[3])


func test_two_grid_with_empty_side_keeps_own_wrap() -> void:
	var left := _make_grid(3, 3)
	var right := _make_grid(0, 3)
	OverlayGridUtil.wire_two_grid_focus(left, right, [], [])
	var l := OverlayGridUtil.grid_cards(left)
	assert_object(_neighbor(l[2], "right")).is_same(l[0])


func test_focused_index_tracks_focus_owner() -> void:
	var grid := _make_grid(3, 3)
	OverlayGridUtil.wire_overlay_focus(grid, [], [])
	var cards := OverlayGridUtil.grid_cards(grid)
	assert_int(OverlayGridUtil.focused_index(grid)).is_equal(-1)
	cards[1].grab_focus()
	assert_int(OverlayGridUtil.focused_index(grid)).is_equal(1)


func test_focus_index_clamps_and_falls_back() -> void:
	var was_gamepad: bool = GamepadHelper._using_gamepad
	GamepadHelper._using_gamepad = true
	var grid := _make_grid(2, 3)
	OverlayGridUtil.wire_overlay_focus(grid, [], [])
	var cards := OverlayGridUtil.grid_cards(grid)
	OverlayGridUtil.focus_index(grid, 5) # out of range -> clamps to last
	await await_idle_frame()
	assert_object(grid.get_viewport().gui_get_focus_owner()).is_same(cards[1])

	var fallback := _make_button()
	fallback.focus_mode = Control.FOCUS_ALL
	var empty := _make_grid(0, 3)
	OverlayGridUtil.focus_index(empty, 0, fallback)
	await await_idle_frame()
	assert_object(empty.get_viewport().gui_get_focus_owner()).is_same(fallback)
	GamepadHelper._using_gamepad = was_gamepad


func test_focus_index_noop_in_pointer_mode() -> void:
	var was_gamepad: bool = GamepadHelper._using_gamepad
	GamepadHelper._using_gamepad = false
	var grid := _make_grid(1, 3)
	OverlayGridUtil.wire_overlay_focus(grid, [], [])
	OverlayGridUtil.focus_index(grid, 0)
	await await_idle_frame()
	assert_object(grid.get_viewport().gui_get_focus_owner()).is_null()
	GamepadHelper._using_gamepad = was_gamepad


# --- Deck-arrange pad pile math ---------------------------------------------

func test_pad_toggle_moves_between_piles() -> void:
	var keep: Array[Dictionary] = [{"id": "a"}, {"id": "b"}]
	var discard: Array[Dictionary] = [{"id": "c"}]
	assert_bool(DeckArrangeOverlayUI.pad_toggle(keep, discard, "keep", 0)).is_true()
	assert_array(keep).is_equal([{"id": "b"}] as Array[Dictionary])
	assert_array(discard).is_equal([{"id": "c"}, {"id": "a"}] as Array[Dictionary])
	assert_bool(DeckArrangeOverlayUI.pad_toggle(keep, discard, "discard", 1)).is_true()
	assert_array(keep).is_equal([{"id": "b"}, {"id": "a"}] as Array[Dictionary])
	assert_bool(DeckArrangeOverlayUI.pad_toggle(keep, discard, "keep", 7)).is_false()


func test_pad_shift_reorders_within_keep() -> void:
	var keep: Array[Dictionary] = [{"id": "a"}, {"id": "b"}, {"id": "c"}]
	assert_int(DeckArrangeOverlayUI.pad_shift(keep, 0, 1)).is_equal(1)
	assert_array(keep).is_equal([{"id": "b"}, {"id": "a"}, {"id": "c"}] as Array[Dictionary])
	assert_int(DeckArrangeOverlayUI.pad_shift(keep, 0, -1)).is_equal(-1) # edge
	assert_int(DeckArrangeOverlayUI.pad_shift(keep, 2, 1)).is_equal(-1) # edge
	assert_int(DeckArrangeOverlayUI.pad_shift(keep, 9, 1)).is_equal(-1) # bad idx
