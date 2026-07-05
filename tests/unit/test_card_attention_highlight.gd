extends GdUnitTestSuite

## Card highlight overlays must survive a same-frame disable/re-enable.
## Moving the mouse between two pending-effect stack rows that resolve to the
## same board card fires set_attention_highlight(false) + (true) in one frame;
## when the disable path used queue_free(), the re-enable picked up the
## queued-for-deletion overlay and the looping pulse tween ended up targeting
## a dead node — Godot aborted it with "Infinite loop detected" (tween.cpp)
## and the highlight vanished. The overlays now hide instead of freeing.

const CARD_SCENE := preload("res://scenes/cards/Card.tscn")

var _card: Node


func before_test() -> void:
	_card = auto_free(CARD_SCENE.instantiate())
	add_child(_card)


func test_attention_highlight_survives_same_frame_toggle() -> void:
	_card.set_attention_highlight(true)
	_card.set_attention_highlight(false)
	_card.set_attention_highlight(true)
	await await_idle_frame()
	await await_idle_frame()
	var overlay: Panel = _card.get_node_or_null("AttentionOverlay")
	assert_object(overlay).is_not_null()
	assert_bool(overlay.is_queued_for_deletion()).is_false()
	assert_bool(overlay.visible).is_true()
	assert_object(_card._attention_tween).is_not_null()
	assert_bool(_card._attention_tween.is_running()).is_true()


func test_attention_highlight_disable_hides_and_stops_pulse() -> void:
	_card.set_attention_highlight(true)
	await await_idle_frame()
	_card.set_attention_highlight(false)
	var overlay: Panel = _card.get_node_or_null("AttentionOverlay")
	assert_object(overlay).is_not_null()
	assert_bool(overlay.visible).is_false()
	assert_float(overlay.modulate.a).is_equal(1.0)
	assert_object(_card._attention_tween).is_null()


func test_highlight_survives_same_frame_toggle() -> void:
	_card.set_highlight(true)
	_card.set_highlight(false)
	_card.set_highlight(true)
	await await_idle_frame()
	var overlay: Panel = _card.get_node_or_null("HighlightOverlay")
	assert_object(overlay).is_not_null()
	assert_bool(overlay.is_queued_for_deletion()).is_false()
	assert_bool(overlay.visible).is_true()
