extends GdUnitTestSuite

## CardSelectOverlayUI controller-experience guards:
## - Stacked pool: picking a copy out of a stack must NOT move the stack's
##   grid position (group order is anchored to the fixed source array, not
##   the mutated pool's first-seen order) and the pad cursor stays on the
##   stack while it drains (template-id focus restore).
## - Drained stack / emptied pool fall back to the clamped-index / Confirm
##   behavior (repeated A drains a pile, cursor falls onto the neighbor).
## - Non-stacked mode keeps the plain clamped-index restore.
## - The submitted instance id stays the FIRST matching source copy
##   (multiplayer/replay determinism).

const Cards := preload("res://tests/fixtures/cards.gd")
const OVERLAY_SCENE := preload("res://scenes/board/overlays/CardSelectOverlay.tscn")

var _parent: Control
var _overlay: CardSelectOverlayUI
var _was_gamepad: bool


func before_test() -> void:
	_was_gamepad = GamepadHelper._using_gamepad
	GamepadHelper._using_gamepad = true
	_parent = auto_free(Control.new())
	add_child(_parent)
	_parent.size = Vector2(1280, 720)
	_overlay = OVERLAY_SCENE.instantiate()
	_parent.add_child(_overlay)


func after_test() -> void:
	GamepadHelper._using_gamepad = _was_gamepad


## Template T's copies straddle the X copies — the layout that used to make
## the T stack jump behind X after the first pick.
func _pool() -> Array:
	return [
		Cards.battle(1, 5000, "GRP-T_1_0"),
		Cards.battle(1, 5000, "GRP-X_1_0"),
		Cards.battle(1, 5000, "GRP-X_1_1"),
		Cards.battle(1, 5000, "GRP-T_1_1"),
		Cards.battle(1, 5000, "GRP-T_1_2"),
	]


func _pool_cards() -> Array[Control]:
	return OverlayGridUtil.grid_cards(_overlay._pool_grid)


func _tid(card: Control) -> String:
	return OverlayGridUtil.get_card_template_id(card.card_data)


func _badge_text(card: Control) -> String:
	for child in card.get_children():
		if child is Label and (child as Label).text.begins_with("x") \
				and (child as Label).text.substr(1).is_valid_int():
			return (child as Label).text
	return ""


func _focus_owner() -> Control:
	return _overlay.get_viewport().gui_get_focus_owner()


func test_stacked_pick_keeps_stack_position_and_focus() -> void:
	var pool := _pool()
	_overlay.show_prompt(pool, pool, "t", 1, 3, Callable())
	await await_idle_frame()
	var cards := _pool_cards()
	assert_array(cards.map(_tid)).is_equal(["GRP-T", "GRP-X"])
	assert_str(_badge_text(cards[0])).is_equal("x3")
	cards[0].grab_focus()

	_overlay._on_pool_clicked(cards[0])
	await await_idle_frame()

	cards = _pool_cards()
	# The stack stays first (source-anchored order) with a decremented badge...
	assert_array(cards.map(_tid)).is_equal(["GRP-T", "GRP-X"])
	assert_str(_badge_text(cards[0])).is_equal("x2")
	# ...the cursor is still on it...
	assert_object(_focus_owner()).is_same(cards[0])
	# ...and the submitted instance is the first source copy.
	assert_str(_overlay._selected[0].get("id", "")).is_equal("GRP-T_1_0")

	# Rendered positions must match child order once the dying cards are gone —
	# the focus hover tween used to capture the transient rebuild layout and
	# pin the focused card in the wrong grid cell (card.gd _animate_hover).
	await await_idle_frame()
	await await_idle_frame()
	cards = _pool_cards()
	assert_float(cards[0].position.x).is_less(cards[1].position.x)
	assert_float(cards[0].position.x).is_equal(0.0)


func test_drained_stack_falls_back_to_clamped_index() -> void:
	var pool := _pool()
	_overlay.show_prompt(pool, pool, "t", 1, 3, Callable())
	await await_idle_frame()
	_pool_cards()[0].grab_focus()

	for i in range(3):
		_overlay._on_pool_clicked(_pool_cards()[0])
		await await_idle_frame()

	# The T stack is gone; the cursor falls onto the stack now in its slot.
	var cards := _pool_cards()
	assert_array(cards.map(_tid)).is_equal(["GRP-X"])
	assert_object(_focus_owner()).is_same(cards[0])


func test_emptied_pool_falls_back_to_confirm() -> void:
	var pool := _pool()
	_overlay.show_prompt(pool, pool, "t", 1, 5, Callable())
	await await_idle_frame()
	_pool_cards()[0].grab_focus()

	for i in range(5):
		_overlay._on_pool_clicked(_pool_cards()[0])
		await await_idle_frame()

	assert_array(_pool_cards()).is_empty()
	assert_object(_focus_owner()).is_same(_overlay._confirm)


func test_pick_in_scrollable_pool_keeps_scroll_and_cursor_visible() -> void:
	# Big pool: 20 unique templates, then the 3-copy stack below the fold.
	# follow_focus used to react to the transient rebuild layout (dying cards
	# still occupying cells) and scroll the cursor off-view on every pick.
	var pool: Array = []
	for i in range(20):
		pool.append(Cards.battle(1, 5000, "FILL-%02d_1_0" % i))
	pool.append(Cards.battle(1, 5000, "GRP-T_1_0"))
	pool.append(Cards.battle(1, 5000, "GRP-T_1_1"))
	pool.append(Cards.battle(1, 5000, "GRP-T_1_2"))
	_overlay.show_prompt(pool, pool, "t", 1, 3, Callable())
	await await_idle_frame()

	var scroll := OverlayGridUtil.scroll_ancestor(_overlay._pool_grid)
	assert_object(scroll).is_not_null()
	var cards := _pool_cards()
	var stack: Control = cards[cards.size() - 1]
	assert_str(_tid(stack)).is_equal("GRP-T")
	stack.grab_focus()
	scroll.ensure_control_visible(stack)
	await await_idle_frame()
	var scroll_before: int = scroll.scroll_vertical
	assert_int(scroll_before).is_greater(0) # the stack really is below the fold

	_overlay._on_pool_clicked(stack)
	for i in range(4):
		await await_idle_frame()

	# Scroll is exactly where the user left it and the cursor is in view.
	assert_int(scroll.scroll_vertical).is_equal(scroll_before)
	var owner: Control = _focus_owner()
	assert_str(_tid(owner)).is_equal("GRP-T")
	assert_bool(scroll.get_global_rect().intersects(owner.get_global_rect())).is_true()


func test_nonstacked_pick_keeps_clamped_index() -> void:
	var pool := _pool()
	_overlay.show_prompt(pool, pool, "t", 1, 3, Callable())
	await await_idle_frame()
	_overlay._stacked.button_pressed = false # per-instance tiles
	await await_idle_frame()
	var cards := _pool_cards()
	assert_int(cards.size()).is_equal(5)
	cards[0].grab_focus()

	_overlay._on_pool_clicked(cards[0])
	await await_idle_frame()

	# Plain clamped-index restore: the next card slides into the slot; no
	# template-follow yank to the later T copies.
	cards = _pool_cards()
	assert_int(cards.size()).is_equal(4)
	assert_object(_focus_owner()).is_same(cards[0])
	assert_str(_tid(cards[0])).is_equal("GRP-X")
