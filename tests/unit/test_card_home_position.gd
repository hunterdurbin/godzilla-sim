extends GdUnitTestSuite

## Card.set_home_position — the non-animated re-home used by CardManager
## layout passes (multiplayer resyncs, resizes). Regression: every board
## broadcast during the opponent's turn snapped hand cards to their slot
## position/z with a raw write, fighting the hover lift tween (visible
## jitter), teleporting dragged cards, and killing in-flight return
## animations. set_home_position reconciles with the card's interactive
## state instead of clobbering it.

const CARD_SCENE := preload("res://scenes/cards/Card.tscn")

var _card: Control


func before_test() -> void:
	_card = auto_free(CARD_SCENE.instantiate())
	_card.scale_duration = 0.05
	add_child(_card)


## Wait for the card's hover/return tween to settle
func _settle() -> void:
	await await_millis(150)


func test_snap_moves_idle_card() -> void:
	var home := Vector2(120, 40)
	_card.set_home_position(home, 3)
	assert_vector(_card.position).is_equal(home)
	assert_vector(_card._pre_hover_position).is_equal(home)
	assert_int(_card.z_index).is_equal(3)


func test_hovered_card_keeps_lift_and_z() -> void:
	_card.position = Vector2(100, 0)
	_card._on_mouse_entered()
	await _settle()
	var lifted: Vector2 = _card.position
	var hover_tween: Tween = _card.tween
	# Re-home to the SAME base (a no-op resync) — the jitter regression
	_card.set_home_position(Vector2(100, 0), 4)
	assert_vector(_card.position).is_equal(lifted)
	assert_int(_card.z_index).is_equal(50)
	assert_int(_card._pre_hover_z_index).is_equal(4)
	assert_object(_card.tween).is_same(hover_tween)


func test_hovered_card_glides_to_new_slot() -> void:
	_card.position = Vector2(100, 0)
	_card._on_mouse_entered()
	await _settle()
	var new_base := Vector2(160, 10)
	_card.set_home_position(new_base)
	# Never snaps to the base while hovered; glides to the lifted position
	assert_vector(_card.position).is_not_equal(new_base)
	await _settle()
	assert_vector(_card.position).is_equal(new_base + Vector2(0, -_card.hover_lift))
	assert_bool(_card._hover_active).is_true()
	_card._on_mouse_exited()
	await _settle()
	assert_vector(_card.position).is_equal(new_base)
	assert_int(_card.z_index).is_equal(_card._pre_hover_z_index)


func test_dragging_card_untouched() -> void:
	_card.is_dragging = true
	_card.position = Vector2(300, 300)
	_card.z_index = 100
	var pre_hover: Vector2 = _card._pre_hover_position
	_card.set_home_position(Vector2(50, 50), 3)
	assert_vector(_card.position).is_equal(Vector2(300, 300))
	assert_int(_card.z_index).is_equal(100)
	assert_vector(_card._pre_hover_position).is_equal(pre_hover)


func test_snap_previewing_card_untouched() -> void:
	_card.is_snap_previewing = true
	_card.position = Vector2(300, 300)
	_card.set_home_position(Vector2(50, 50), 3)
	assert_vector(_card.position).is_equal(Vector2(300, 300))


func test_inflight_return_to_same_target_preserved() -> void:
	_card.position = Vector2(200, 200)
	var target := Vector2(80, 20)
	_card.return_to_position(target, 0.3)
	var return_tween: Tween = _card.tween
	_card.set_home_position(target)
	assert_object(_card.tween).is_same(return_tween)
	assert_bool(return_tween.is_running()).is_true()
	# Mid-flight, not snapped
	assert_vector(_card.position).is_not_equal(target)
	await _settle()


func test_inflight_return_retargeted_on_new_target() -> void:
	_card.position = Vector2(200, 200)
	_card.return_to_position(Vector2(80, 20), 0.3)
	var return_tween: Tween = _card.tween
	var new_home := Vector2(140, 60)
	_card.set_home_position(new_home)
	assert_vector(_card.position).is_equal(new_home)
	assert_vector(_card._pre_hover_position).is_equal(new_home)
	assert_vector(_card.scale).is_equal(_card.original_scale)
	assert_bool(return_tween.is_running()).is_false()


func test_unhover_retarget_does_not_relift() -> void:
	_card.position = Vector2(100, 0)
	_card._on_mouse_entered()
	await _settle()
	_card._on_mouse_exited()
	# Return tween in flight, _hover_active still true until its callback
	var new_base := Vector2(160, 10)
	_card.set_home_position(new_base)
	await _settle()
	assert_vector(_card.position).is_equal(new_base)
	assert_bool(_card._hover_active).is_false()


func test_manager_resync_is_stable_for_hovered_card() -> void:
	var mgr: CardManager = auto_free(CardManager.new())
	mgr.layout_mode = CardManager.LayoutMode.HAND_ARC
	add_child(mgr)
	var cards: Array[Control] = []
	for i in range(3):
		var card: Control = CARD_SCENE.instantiate()
		card.scale_duration = 0.05
		mgr.add_card(card, false)
		cards.append(card)
	mgr.arrange_cards(false)
	var middle := cards[1]
	middle._on_mouse_entered()
	await _settle()
	var lifted: Vector2 = middle.position
	# Simulated board-state broadcasts while the opponent acts
	mgr.arrange_cards(false)
	assert_vector(middle.position).is_equal(lifted)
	assert_int(middle.z_index).is_equal(50)
	mgr.arrange_cards(false)
	assert_vector(middle.position).is_equal(lifted)


func test_gap_reopens_after_arrange_during_drag() -> void:
	var mgr: CardManager = auto_free(CardManager.new())
	add_child(mgr)
	var cards: Array[Control] = []
	for i in range(3):
		var card: Control = CARD_SCENE.instantiate()
		mgr.add_card(card, false)
		cards.append(card)
	mgr.dragged_card = cards[0]
	mgr._drag_preview_index = 1
	mgr.arrange_cards(false)
	assert_int(mgr._drag_preview_index).is_equal(-1)
	mgr.dragged_card = null
