extends GdUnitTestSuite

## CardManager selection validity across reorders. Sorting the hand rewrites
## managed_cards order; the index-based selectable_indices list must remap
## to the surviving cards (controller navigation validates by index —
## regression: sorted hands navigated/validated against pre-sort indices).


class StubCard:
	extends Control
	signal card_clicked(card: Control)
	signal card_right_clicked(card: Control)
	var card_data: Dictionary = {}
	var is_selectable: bool = false
	var drag_enabled: bool = true

	func _to_string() -> String:
		return "StubCard(%s)" % card_data.get("id", "?")


var _mgr: CardManager
var _cards: Array[Control] = []


func before_test() -> void:
	_mgr = auto_free(CardManager.new())
	_mgr.arrange_duration = 0.0
	add_child(_mgr)
	_cards.clear()
	for i in range(5):
		var card := StubCard.new()
		card.card_data = {"id": "C%d" % i}
		_mgr.add_card(card, false)
		_cards.append(card)


func test_selectable_indices_remap_after_sort() -> void:
	_mgr.enter_selection_mode([0, 2] as Array[int]) # C0, C2 valid
	_mgr.managed_cards.reverse() # "sort": C4 C3 C2 C1 C0
	_mgr.arrange_cards(false)
	assert_that(_mgr.selectable_indices).is_equal([2, 4] as Array[int])
	# select_card_at validates against the fresh indices
	var picked: Array = []
	_mgr.card_selected.connect(func(card: Control, _i: int) -> void: picked.append(card))
	_mgr.select_card_at(2)
	assert_that(picked).is_equal([_cards[2]])
	# ...and rejects a now-invalid index that was valid pre-sort
	_mgr.select_card_at(0)
	assert_that(picked).is_equal([_cards[2]])


func test_removed_card_drops_out_of_validity() -> void:
	_mgr.enter_selection_mode([0, 2] as Array[int])
	_mgr.remove_card(_cards[0], false)
	_mgr.arrange_cards(false)
	assert_that(_mgr.selectable_indices).is_equal([1] as Array[int]) # C2 shifted left


func test_all_selectable_sentinel_survives_reorder() -> void:
	_mgr.enter_selection_mode([] as Array[int]) # empty = all
	_mgr.managed_cards.reverse()
	_mgr.arrange_cards(false)
	assert_that(_mgr.selectable_indices).is_equal([] as Array[int])
	var picked: Array = []
	_mgr.card_selected.connect(func(card: Control, _i: int) -> void: picked.append(card))
	_mgr.select_card_at(4)
	assert_that(picked).is_equal([_cards[0]])


func test_exit_selection_clears_refs() -> void:
	_mgr.enter_selection_mode([1] as Array[int])
	_mgr.exit_selection_mode()
	_mgr.managed_cards.reverse()
	_mgr.arrange_cards(false)
	assert_that(_mgr.selectable_indices).is_equal([] as Array[int])
