extends GdUnitTestSuite

## CardGridViewerUI (MonsterDeckViewOverlay) presentation guards:
## - show_rankup()/show_cards() re-assert full-rect geometry, repairing the
##   degenerate-rect state observed in an exported build (overlay visible but
##   0x0: no dim layer, panel collapsed to the top-left corner).
## - show_cards() must never overwrite a pending mandatory rank-up pick
##   (reachable by clicking the monster deck while the prompt is minimized) —
##   that used to hide every control that could resolve or restore it.

const Cards := preload("res://tests/fixtures/cards.gd")
const OVERLAY_SCENE := preload("res://scenes/board/overlays/MonsterDeckViewOverlay.tscn")
const ZOOM_SCENE := preload("res://scenes/board/overlays/CardZoomOverlay.tscn")

var _parent: Control
var _overlay: CardGridViewerUI


func before_test() -> void:
	_parent = auto_free(Control.new())
	add_child(_parent)
	_parent.size = Vector2(1280, 720)
	_overlay = OVERLAY_SCENE.instantiate()
	_parent.add_child(_overlay)


func _corrupt_rect() -> void:
	# Reproduce the degenerate state: anchors/offsets collapsed to 0x0.
	_overlay.anchor_right = 0.0
	_overlay.anchor_bottom = 0.0
	_overlay.size = Vector2.ZERO


func _monsters() -> Array:
	return [Cards.monster(2, 6000, [CardEnums.CardTrait.GODZILLA], "T-MON-R2")]


func test_show_rankup_repairs_degenerate_rect() -> void:
	_corrupt_rect()
	_overlay.show_rankup(_monsters(), [0] as Array[int], "Choose monster", Callable())
	await await_idle_frame()
	assert_bool(_overlay.visible).is_true()
	assert_vector(_overlay.size).is_equal(_parent.size)


func test_show_cards_repairs_degenerate_rect() -> void:
	_corrupt_rect()
	_overlay.show_cards(_monsters(), "Monster Deck")
	await await_idle_frame()
	assert_bool(_overlay.visible).is_true()
	assert_vector(_overlay.size).is_equal(_parent.size)


func test_show_cards_cannot_overwrite_pending_rankup() -> void:
	_overlay.show_rankup(_monsters(), [0] as Array[int], "Choose monster", Callable())
	await await_idle_frame()
	# Minimized via View Board, then the player clicks their monster deck.
	_overlay.visible = false
	_overlay.show_cards(_monsters(), "Monster Deck")
	await await_idle_frame()
	# The blocking prompt is restored untouched: still in rank-up mode, the
	# View Board minimize button available, and the pick still selectable.
	assert_bool(_overlay.visible).is_true()
	assert_bool(_overlay.rankup_selecting).is_true()
	assert_bool(_overlay._view_board.visible).is_true()
	assert_str(_overlay._title.text).is_equal("Choose monster")
	var grid_cards := _overlay._grid.get_children().filter(
			func(c: Node) -> bool: return not c.is_queued_for_deletion())
	assert_int(grid_cards.size()).is_equal(1)
	assert_bool(grid_cards[0].is_selectable).is_true()


func test_zoom_show_card_repairs_degenerate_rect() -> void:
	var zoom: CardZoomOverlayUI = ZOOM_SCENE.instantiate()
	_parent.add_child(zoom)
	zoom.anchor_right = 0.0
	zoom.anchor_bottom = 0.0
	zoom.size = Vector2.ZERO
	zoom.show_card(Cards.monster(2))
	await await_idle_frame()
	assert_bool(zoom.visible).is_true()
	assert_vector(zoom.size).is_equal(_parent.size)
