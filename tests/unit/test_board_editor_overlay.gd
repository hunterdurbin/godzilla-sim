extends GdUnitTestSuite

## BoardEditorOverlayUI logic guards: the debug/local-only gate, the
## per-click-target placement option lists, and applying placement ops
## through a real BoardEditor.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const OVERLAY_SCENE := preload("res://scenes/board/overlays/BoardEditorOverlay.tscn")


func _id_at(arr: Array, i: int) -> String:
	if i < 0 or i >= arr.size():
		return "<missing>"
	return str(arr[i].get("id", ""))


func _op_ids(options: Array) -> Array:
	var ids: Array = []
	for opt in options:
		ids.append(str(opt.get("op", "")))
	return ids


# --- Gate ---

func test_can_edit_requires_debug_local_running() -> void:
	assert_bool(BoardEditorOverlayUI.can_edit(true, false, true)).is_true()
	assert_bool(BoardEditorOverlayUI.can_edit(false, false, true)).is_false()
	assert_bool(BoardEditorOverlayUI.can_edit(true, true, true)).is_false()
	assert_bool(BoardEditorOverlayUI.can_edit(true, false, false)).is_false()


# --- Placement options ---

func test_zone_options_for_battle_card() -> void:
	var ids := _op_ids(BoardEditorOverlayUI.placement_options(CardEnums.CardType.BATTLE, "zone"))
	assert_array(ids).contains_exactly(["zone_top", "zone_under"])


func test_zone_options_for_monster_card_include_monster_ops() -> void:
	var ids := _op_ids(BoardEditorOverlayUI.placement_options(CardEnums.CardType.MONSTER, "zone"))
	assert_array(ids).contains(["monster_set_stack", "monster_set_discard", "monster_stack_below", "monster_stack_bottom", "zone_top"])


func test_strategy_options_by_card_type() -> void:
	var strat_ids := _op_ids(BoardEditorOverlayUI.placement_options(CardEnums.CardType.STRATEGY, "strategy"))
	assert_array(strat_ids).contains(["strategy_set", "strategy_under_top"])
	var battle_ids := _op_ids(BoardEditorOverlayUI.placement_options(CardEnums.CardType.BATTLE, "strategy"))
	assert_bool("strategy_set" in battle_ids).is_true()
	assert_bool("strategy_under_top" in battle_ids).is_true()


func test_monster_zone_click_offers_under_monster_stack_ops() -> void:
	# Clicking the monster's OWN zone stacks the card under the monster
	# (monster_stack) — never into the zone array (which the monster covers).
	var battle_ids := _op_ids(BoardEditorOverlayUI.placement_options(CardEnums.CardType.BATTLE, "monster_zone"))
	assert_array(battle_ids).contains_exactly(["monster_under_top", "monster_under_bottom"])
	var monster_ids := _op_ids(BoardEditorOverlayUI.placement_options(CardEnums.CardType.MONSTER, "monster_zone"))
	assert_array(monster_ids).contains(["monster_set_stack", "monster_set_discard", "monster_stack_below", "monster_stack_bottom"])
	assert_bool("zone_top" in monster_ids).is_false()


func test_apply_placement_under_monster_ops() -> void:
	var ctx := _overlay_with_editor()
	var overlay: BoardEditorOverlayUI = ctx["overlay"]
	var state: GameState = ctx["state"]
	await overlay.apply_placement("monster_under_bottom", 0, 0, Cards.battle(1, 5000, "BOTTOM"))
	await overlay.apply_placement("monster_under_top", 0, 0, Cards.battle(1, 5000, "TOP"))
	assert_str(_id_at(state.players[0].monster_stack, 0)).is_equal("TOP")
	assert_str(_id_at(state.players[0].monster_stack, 1)).is_equal("BOTTOM")
	assert_int(state.players[0].zones[state.players[0].monster_zone - 1].size()).is_equal(0)


func test_deck_discard_monster_deck_options() -> void:
	assert_array(_op_ids(BoardEditorOverlayUI.placement_options(CardEnums.CardType.BATTLE, "deck"))).contains_exactly(["deck_top", "deck_bottom"])
	assert_array(_op_ids(BoardEditorOverlayUI.placement_options(CardEnums.CardType.BATTLE, "discard"))).contains_exactly(["discard"])
	assert_array(_op_ids(BoardEditorOverlayUI.placement_options(CardEnums.CardType.MONSTER, "monster_deck"))).contains_exactly(["monster_deck"])


# --- Arming slots so EMPTY slots emit clicks while placing ---
# Slot only emits slot_clicked when it holds a card or in_selection_mode is
# set (slot.gd _on_gui_input) — the editor must arm slots like the
# SelectionController does, or placing onto empty zones silently no-ops.

const SLOT_SCENE := preload("res://scenes/slots/Slot.tscn")


func _left_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


func test_arm_slots_makes_empty_slot_emit_clicks() -> void:
	var slot: Slot = auto_free(SLOT_SCENE.instantiate())
	slot.zone_number = 3
	slot.player_id = 0
	add_child(slot)
	var hits: Array = []
	slot.slot_clicked.connect(func(z: int, p: int) -> void: hits.append([z, p]))

	slot._on_gui_input(_left_click())
	assert_int(hits.size()).is_equal(0)  # empty + unarmed: Slot swallows the click

	BoardEditorOverlayUI.arm_slots([slot], true)
	assert_bool(slot.in_selection_mode).is_true()
	slot._on_gui_input(_left_click())
	assert_int(hits.size()).is_equal(1)

	BoardEditorOverlayUI.arm_slots([slot], false)
	assert_bool(slot.in_selection_mode).is_false()
	slot._on_gui_input(_left_click())
	assert_int(hits.size()).is_equal(1)


func test_pool_grid_fits_three_columns_no_horizontal_scroll() -> void:
	# Cards must shrink to the panel: 3 columns exactly filling the scroll
	# width (aspect kept), and the ScrollContainer must never scroll
	# horizontally.
	var parent: Control = auto_free(Control.new())
	add_child(parent)
	var overlay: BoardEditorOverlayUI = OVERLAY_SCENE.instantiate()
	parent.add_child(overlay)
	assert_int(overlay._pool_scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	overlay._pool_scroll.size = Vector2(300, 400)
	var cell: Vector2 = overlay._pool_cell_size()
	# 3 columns + separations + scrollbar reserve fit inside 300.
	var h_sep: int = overlay._pool_grid.get_theme_constant("h_separation")
	assert_bool(cell.x * 3.0 + h_sep * 2 <= 300.0).is_true()
	assert_bool(cell.x > 60.0).is_true()  # sane, not collapsed
	assert_float(cell.y / cell.x).is_equal_approx(168.0 / 120.0, 0.01)
	overlay._refresh_pool()
	for card in OverlayGridUtil.grid_cards(overlay._pool_grid):
		assert_float(card.custom_minimum_size.x).is_equal_approx(cell.x, 0.5)


func test_pool_cards_use_contained_gallery_hover() -> void:
	# Pool cards live in a GridContainer: the default hover raise
	# (hover_lift 40 / scale 1.15) blows out of the cell — they must get
	# the gallery hover treatment like every other grid overlay.
	var parent: Control = auto_free(Control.new())
	add_child(parent)
	var overlay: BoardEditorOverlayUI = OVERLAY_SCENE.instantiate()
	parent.add_child(overlay)
	overlay._refresh_pool()
	var cards := OverlayGridUtil.grid_cards(overlay._pool_grid)
	assert_bool(cards.size() > 0).is_true()
	for card in cards:
		assert_float(card.hover_lift).is_equal(0.0)
		assert_float(card.hover_scale).is_equal(1.05)


# --- Applying ops through a real editor ---

func _overlay_with_editor() -> Dictionary:
	var state := States.make_state()
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())
	var parent: Control = auto_free(Control.new())
	add_child(parent)
	var overlay: BoardEditorOverlayUI = OVERLAY_SCENE.instantiate()
	parent.add_child(overlay)
	overlay._editor = BoardEditor.new(tm)
	return {"state": state, "overlay": overlay}


func test_apply_placement_zone_top() -> void:
	var ctx := _overlay_with_editor()
	var overlay: BoardEditorOverlayUI = ctx["overlay"]
	var state: GameState = ctx["state"]
	await overlay.apply_placement("zone_top", 1, 4, Cards.battle(1, 5000, "PLACED"))
	assert_str(_id_at(state.players[1].zones[4], 0)).is_equal("PLACED")


func test_apply_placement_monster_set_stack() -> void:
	var ctx := _overlay_with_editor()
	var overlay: BoardEditorOverlayUI = ctx["overlay"]
	var state: GameState = ctx["state"]
	var old_id: String = state.players[0].current_monster.get("id", "")
	await overlay.apply_placement("monster_set_stack", 0, 0, Cards.monster(2, 8000, [CardEnums.CardTrait.GODZILLA], "NEWMON"))
	assert_str(str(state.players[0].current_monster.get("id", ""))).is_equal("NEWMON")
	assert_str(_id_at(state.players[0].monster_stack, 0)).is_equal(old_id)


func test_apply_placement_monster_set_moves_monster_to_clicked_zone() -> void:
	# Clicking zone 6 with a "Set current" op both swaps the monster AND
	# positions it there (crushing that zone's stack through the engine).
	var ctx := _overlay_with_editor()
	var overlay: BoardEditorOverlayUI = ctx["overlay"]
	var state: GameState = ctx["state"]
	overlay._editor.add_to_zone(0, 5, Cards.battle(1, 5000, "SQUASHED"), true)
	await overlay.apply_placement("monster_set_discard", 0, 5, Cards.monster(2, 8000, [CardEnums.CardTrait.GODZILLA], "MOVER"))
	assert_str(str(state.players[0].current_monster.get("id", ""))).is_equal("MOVER")
	assert_int(state.players[0].monster_zone).is_equal(6)
	assert_int(state.players[0].zones[5].size()).is_equal(0)
	var ids: Array = state.players[0].discard_pile.map(func(c: Dictionary) -> String: return str(c.get("id", "")))
	assert_array(ids).contains(["SQUASHED"])


func test_apply_placement_deck_bottom_and_hand() -> void:
	var ctx := _overlay_with_editor()
	var overlay: BoardEditorOverlayUI = ctx["overlay"]
	var state: GameState = ctx["state"]
	await overlay.apply_placement("deck_top", 0, 0, Cards.battle(1, 5000, "D1"))
	await overlay.apply_placement("deck_bottom", 0, 0, Cards.battle(1, 5000, "D2"))
	await overlay.apply_placement("hand", 0, 0, Cards.battle(1, 5000, "H"))
	assert_str(_id_at(state.players[0].main_deck, 0)).is_equal("D1")
	assert_str(_id_at(state.players[0].main_deck, 1)).is_equal("D2")
	assert_str(_id_at(state.players[0].hand, 0)).is_equal("H")
