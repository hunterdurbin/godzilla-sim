extends Node

## Controller navigation regression test for the replay viewer — drives it
## with PHYSICAL joypad events over a synthetic 3-snapshot replay:
##   - the pointer->gamepad flip lands on Play/Pause without toggling
##     autoplay; the dpad walks the transport row into the sliders;
##   - → on the focused turn slider steps the snapshot and the hand-row
##     re-mesh keeps the slider focused;
##   - ↑ reaches a hand card (preview mirrors hover), Y zooms it, the dpad is
##     swallowed under the zoom, and B closes only the zoom;
##   - the gallery overlay is a focus context landing on its first card; the
##     stacked toggle rebuilds the grid without losing the toggle's focus and
##     B restores the focus that opened the gallery.
##
## Run:
##   godot --headless --quit-after 3000 res://tests/ui/ReplayViewerPadNavTest.tscn

func _tick(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _press_button(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	await _tick(3)
	var up := InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	await _tick(2)


func _press_trigger(axis: JoyAxis) -> void:
	var down := InputEventJoypadMotion.new()
	down.axis = axis
	down.axis_value = 1.0
	Input.parse_input_event(down)
	await _tick(3)
	var up := InputEventJoypadMotion.new()
	up.axis = axis
	up.axis_value = 0.0
	Input.parse_input_event(up)
	await _tick(2)


func _ids_of_type(card_type: int, count: int) -> Array[String]:
	var ids: Array = CardData.CARD_TEMPLATES.keys()
	ids.sort()
	var found: Array[String] = []
	for id: String in ids:
		if CardData.CARD_TEMPLATES[id].get("card_type", -1) == card_type:
			found.append(id)
			if found.size() == count:
				return found
	assert(false, "fewer than %d cards of type %d in CardData" % [count, card_type])
	return found


func _first_id_of_type(card_type: int) -> String:
	return _ids_of_type(card_type, 1)[0]


func _make_player_dict(pid: int, hand_size: int) -> Dictionary:
	var ps := PlayerState.new(pid)
	var battle_id := _first_id_of_type(CardEnums.CardType.BATTLE)
	for i in range(hand_size):
		ps.hand.append(GameSerializer.id_to_card("%s_%d_%d" % [battle_id, pid, i]))
	ps.current_monster = GameSerializer.id_to_card(
			"%s_%d_9" % [_first_id_of_type(CardEnums.CardType.MONSTER), pid])
	ps.monster_zone = 1
	return GameSerializer.serialize_player_state(ps)


func _make_replay() -> ReplayData:
	var replay := ReplayData.new()
	replay.player_names = ["Alice", "Bob"] as Array[String]
	var players := [_make_player_dict(0, 3), _make_player_dict(1, 2)]
	for i in range(3):
		replay.snapshots.append({
			"turn_number": 1 if i < 2 else 2,
			"current_player_id": 0,
			"phase": 0,
			"players": players,
			"log_lines": [],
			"is_boundary": true,
		})
	return replay


func _ready() -> void:
	# Hermetic bindings: a connected controller loads the USER'S persisted
	# rebinds (user://settings.cfg) — the walk assumes the default map.
	# In-memory only; never touches the saved config.
	GamepadInput._map = GlyphDB.default_map()
	await get_tree().process_frame
	ReplayData.pending_replay = _make_replay()
	var viewer: Control = load("res://scenes/replay/ReplayViewer.tscn").instantiate()
	get_tree().root.add_child(viewer)
	await _tick(10)
	assert(viewer._replay != null and viewer._replay.snapshots.size() == 3,
		"synthetic replay did not load")

	# Flip to gamepad mode; the flipping A press must not toggle autoplay.
	await _press_button(JOY_BUTTON_A)
	assert(GamepadHelper.is_using_gamepad(), "joypad press did not enter gamepad mode")
	assert(not viewer._auto_playing, "the mode-flipping press toggled autoplay")
	await _tick(2)
	assert(viewer.play_pause_button.has_focus(),
		"provider did not land on Play/Pause: %s" % str(get_viewport().gui_get_focus_owner()))
	assert(viewer._pad_hint_row.visible, "hint row hidden in gamepad mode")
	assert(viewer._pad_hint_row.get_child_count() > 0, "hint row is empty")

	# Transport walk: right reaches the boundary-enabled Play From Here; the
	# sliders sit in their own bands below (they consume ←/→ for their value,
	# so ↑/↓ is the only way on and off them).
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(viewer.next_button.has_focus(), "dpad right did not reach Next")
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(viewer.play_from_here_button.has_focus(),
		"dpad right did not reach Play From Here: %s" % str(get_viewport().gui_get_focus_owner()))
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(viewer.speed_slider.has_focus(), "dpad down did not reach the speed slider")
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(viewer.turn_slider.has_focus(), "dpad down did not reach the turn slider")

	# → on the focused turn slider steps the snapshot; the hand rows rebuild
	# but the slider (not rebuilt) keeps focus through the re-mesh.
	assert(viewer._snapshot_index == 0, "unexpected snapshot before the slider step")
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	await _tick(2)
	assert(viewer._snapshot_index == 1, "→ on the turn slider did not step the snapshot")
	assert(viewer.turn_slider.has_focus(), "the snapshot re-mesh stole the slider focus")

	# Bumpers step one snapshot, triggers jump a whole turn — from anywhere,
	# without moving focus. (Snapshots: turn 1, turn 1, turn 2.)
	await _press_button(JOY_BUTTON_RIGHT_SHOULDER)
	assert(viewer._snapshot_index == 2, "RB did not step forward")
	await _press_button(JOY_BUTTON_LEFT_SHOULDER)
	assert(viewer._snapshot_index == 1, "LB did not step back")
	await _press_trigger(JOY_AXIS_TRIGGER_RIGHT)
	assert(viewer._snapshot_index == 2, "RT did not jump to the next turn")
	await _press_trigger(JOY_AXIS_TRIGGER_LEFT)
	assert(viewer._snapshot_index == 1, "LT did not jump back a turn")
	assert(viewer.turn_slider.has_focus(), "transport shortcuts moved the pad focus")

	# ↑ climbs back through the sliders and the transport row into the P1 hand.
	await _press_button(JOY_BUTTON_DPAD_UP)
	assert(viewer.speed_slider.has_focus(), "dpad up did not return to the speed slider")
	await _press_button(JOY_BUTTON_DPAD_UP)
	assert(viewer.prev_turn_button.has_focus(),
		"dpad up did not re-enter the transport row: %s" % str(get_viewport().gui_get_focus_owner()))
	await _press_button(JOY_BUTTON_DPAD_UP)
	var hand_card: Control = get_viewport().gui_get_focus_owner()
	assert(hand_card != null and hand_card.get_parent() == viewer.p1_hand_grid,
		"dpad up did not enter the P1 hand: %s" % str(hand_card))
	assert(viewer._preview_container.visible, "hand-card focus did not show the preview")

	# Y zooms the focused card; the dpad is swallowed while the zoom is up
	# (the card behind still holds real focus); B closes only the zoom.
	await _press_button(JOY_BUTTON_Y)
	await _tick(2)
	assert(viewer._zoom_overlay.visible, "Y did not open the card zoom")
	assert(GamepadHelper.is_top_context(viewer._zoom_overlay),
		"the zoom overlay did not take the focus context")
	await _press_button(JOY_BUTTON_DPAD_LEFT)
	assert(get_viewport().gui_get_focus_owner() == hand_card,
		"the dpad crawled the mesh under the zoom")
	var zoom_snapshot: int = viewer._snapshot_index
	await _press_button(JOY_BUTTON_RIGHT_SHOULDER)
	assert(viewer._snapshot_index == zoom_snapshot,
		"RB stepped the replay while the zoom overlay was up")
	await _press_button(JOY_BUTTON_B)
	await _tick(2)
	assert(not viewer._zoom_overlay.visible, "B did not close the zoom")
	assert(is_instance_valid(viewer) and viewer.is_inside_tree(),
		"the B that closed the zoom leaked into the exit handler")
	assert(GamepadHelper.is_top_context(viewer),
		"closing the zoom did not return the focus context to the viewer")
	assert(hand_card.has_focus(), "closing the zoom moved the hand-card focus")

	# Gallery overlay: context lands on the first card; the stacked toggle
	# rebuilds the grid without losing its own focus; B restores the opener.
	# 3 distinct templates x 2 copies: the stacked toggle groups by base id.
	var gallery_ids := _ids_of_type(CardEnums.CardType.BATTLE, 3)
	var gallery_cards: Array = []
	for i in range(6):
		gallery_cards.append(GameSerializer.id_to_card("%s_G_%d" % [gallery_ids[i % 3], i]))
	viewer._show_gallery("Test", gallery_cards, true)
	await _tick(4)
	assert(GamepadHelper.is_top_context(viewer._gallery_overlay),
		"the gallery did not take the focus context")
	var grid_cards := OverlayGridUtil.grid_cards(viewer._gallery_grid)
	assert(get_viewport().gui_get_focus_owner() == grid_cards[0],
		"gallery focus not on the first card: %s" % str(get_viewport().gui_get_focus_owner()))
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(get_viewport().gui_get_focus_owner() == grid_cards[1],
		"dpad right did not walk the gallery grid")
	await _press_button(JOY_BUTTON_DPAD_UP)
	assert(viewer._gallery_stacked_toggle.has_focus(),
		"dpad up did not reach the stacked toggle: %s" % str(get_viewport().gui_get_focus_owner()))
	await _press_button(JOY_BUTTON_A)
	await _tick(3)
	assert(viewer._gallery_stacked_toggle.button_pressed, "A did not toggle Stacked")
	assert(OverlayGridUtil.grid_cards(viewer._gallery_grid).size() == 3,
		"stacked rebuild did not group the 6 cards into 3")
	assert(viewer._gallery_stacked_toggle.has_focus(),
		"the stacked rebuild stole the toggle focus")
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(OverlayGridUtil.grid_cards(viewer._gallery_grid).has(
			get_viewport().gui_get_focus_owner()),
		"dpad down did not re-enter the rebuilt grid")
	await _press_button(JOY_BUTTON_B)
	await _tick(3)
	assert(not viewer._gallery_overlay.visible, "B did not close the gallery")
	assert(GamepadHelper.is_top_context(viewer),
		"closing the gallery did not return the focus context to the viewer")
	assert(hand_card.has_focus(),
		"closing the gallery did not restore the opener focus: %s"
			% str(get_viewport().gui_get_focus_owner()))

	print("REPLAY_VIEWER_PAD_NAV_TEST_PASS")
	get_tree().quit(0)
