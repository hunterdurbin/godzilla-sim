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


func _make_meta_grid(count: int, cols: int) -> GridContainer:
	# Deck-builder-style grid: plain wrappers opted in via GRID_CARD_META.
	var grid := GridContainer.new()
	grid.columns = cols
	for i in range(count):
		var wrapper := PanelContainer.new()
		wrapper.set_meta(OverlayGridUtil.GRID_CARD_META, true)
		grid.add_child(wrapper)
	_root.add_child(grid)
	return grid


func test_grid_cards_accepts_meta_marked_wrappers() -> void:
	var grid := _make_meta_grid(3, 3)
	grid.add_child(Label.new()) # filler stays excluded
	assert_int(OverlayGridUtil.grid_cards(grid).size()).is_equal(3)


func test_band_stack_row_grid_row_cycle() -> void:
	# header(2) / grid [0 1 2]/[3 4] / footer(1), wrapped.
	var header := [_make_button(), _make_button()] as Array[Control]
	var grid := _make_meta_grid(5, 3)
	var footer := [_make_button()] as Array[Control]
	OverlayGridUtil.wire_band_stack([
		{"row": header}, {"grid": grid}, {"row": footer},
	])
	var cards := OverlayGridUtil.grid_cards(grid)
	# Header enters the grid's top row column-wise; ↑ wraps onto the footer.
	assert_object(_neighbor(header[0], "down")).is_same(cards[0])
	assert_object(_neighbor(header[1], "down")).is_same(cards[1])
	assert_object(_neighbor(header[1], "up")).is_same(footer[0])
	# Grid exits: top row ↑ header (clamped), bottom row ↓ footer.
	assert_object(_neighbor(cards[0], "up")).is_same(header[0])
	assert_object(_neighbor(cards[2], "up")).is_same(header[1]) # col clamped
	assert_object(_neighbor(cards[3], "down")).is_same(footer[0])
	assert_object(_neighbor(cards[2], "down")).is_same(footer[0]) # short last row
	# Footer: ↑ grid bottom row, ↓ wraps to header.
	assert_object(_neighbor(footer[0], "up")).is_same(cards[3])
	assert_object(_neighbor(footer[0], "down")).is_same(header[0])
	# Interior grid edges untouched; rows mesh horizontally with wrap.
	assert_object(_neighbor(cards[1], "down")).is_same(cards[4])
	assert_object(_neighbor(header[1], "right")).is_same(header[0])


func test_band_stack_two_grids_share_middle_row() -> void:
	# The deck-builder shape: header / deck grid / filter row / pool grid.
	var header := [_make_button()] as Array[Control]
	var deck := _make_meta_grid(2, 3)
	var filter := [_make_button(), _make_button()] as Array[Control]
	var pool := _make_meta_grid(4, 3)
	OverlayGridUtil.wire_band_stack([
		{"row": header}, {"grid": deck}, {"row": filter}, {"grid": pool},
	])
	var d := OverlayGridUtil.grid_cards(deck)
	var p := OverlayGridUtil.grid_cards(pool)
	# The shared filter row bridges both grids without overwritten links.
	assert_object(_neighbor(d[0], "down")).is_same(filter[0])
	assert_object(_neighbor(d[1], "down")).is_same(filter[1])
	assert_object(_neighbor(filter[0], "up")).is_same(d[0])
	assert_object(_neighbor(filter[1], "down")).is_same(p[1])
	assert_object(_neighbor(p[2], "up")).is_same(filter[1]) # col clamped
	# Pool bottom row wraps onto the header.
	assert_object(_neighbor(p[3], "down")).is_same(header[0])
	assert_object(_neighbor(p[1], "down")).is_same(header[0]) # short last row
	assert_object(_neighbor(header[0], "up")).is_same(p[3])


func test_band_stack_skips_empty_bands() -> void:
	var header := [_make_button()] as Array[Control]
	var empty_grid := _make_meta_grid(0, 3)
	var hidden := [_make_button(false)] as Array[Control]
	var footer := [_make_button()] as Array[Control]
	OverlayGridUtil.wire_band_stack([
		{"row": header}, {"grid": empty_grid}, {"row": hidden}, {"row": footer},
	])
	assert_object(_neighbor(header[0], "down")).is_same(footer[0])
	assert_object(_neighbor(footer[0], "up")).is_same(header[0])


func test_band_stack_rows_only_without_wrap() -> void:
	# Left-panel shape: button rows, outer edges pinned (self-loop, no wrap).
	var top := [_make_button()] as Array[Control]
	var mid := [_make_button(), _make_button()] as Array[Control]
	var bottom := [_make_button()] as Array[Control]
	OverlayGridUtil.wire_band_stack([
		{"row": top}, {"row": mid}, {"row": bottom},
	], false)
	assert_object(_neighbor(top[0], "up")).is_same(top[0]) # pinned edge
	assert_object(_neighbor(top[0], "down")).is_same(mid[0])
	assert_object(_neighbor(mid[1], "up")).is_same(top[0]) # col clamped
	assert_object(_neighbor(mid[1], "down")).is_same(bottom[0])
	assert_object(_neighbor(bottom[0], "down")).is_same(bottom[0]) # pinned edge
	assert_object(_neighbor(mid[0], "right")).is_same(mid[1])


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
