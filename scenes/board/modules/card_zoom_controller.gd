class_name CardZoomController
extends Node
## Card zoom overlay + hover/long-press previews (normal and strategy), zoom source inference.
## Method bodies moved verbatim from game_board.gd (Phase 8 split);
## remaining board state/methods are reached via `_board`. The board
## keeps one-line delegates, so call sites, signal connections, and the
## session-layer `_board.*` contract are unchanged.

var _board: GameBoard


func _ready() -> void:
	_board = get_parent() as GameBoard


func _on_card_long_press_zoom(card: Control) -> void:
	if "card_data" in card and not card.card_data.is_empty():
		var mod: int = card.get_play_cost_modifier() if card.has_method("get_play_cost_modifier") else 0
		var power: int = card.get_power_preview() if card.has_method("get_power_preview") else 0
		_board._show_card_zoom(card.card_data, mod, {}, power)


func _on_hand_card_right_clicked(card: Control, hand_player_id: int) -> void:
	if "card_data" in card and not card.card_data.is_empty():
		var mod: int = card.get_play_cost_modifier() if card.has_method("get_play_cost_modifier") else 0
		var power: int = card.get_power_preview() if card.has_method("get_power_preview") else 0
		_board._show_card_zoom(card.card_data, mod, _board._hand_zoom_ctx(card.card_data, hand_player_id), power)


## Zoom shim — display lives on CardZoomOverlayUI (router hook + several
## long-press/right-click callers). Callers with board context pass zoom_ctx
## ({player_id, location: "zone"|"monster"|"strategy"|"hand", index}); the
## rest fall back to locating the exact copy by its per-copy instance id.


func _show_card_zoom(card_data: Dictionary, play_cost_modifier: int = 0, zoom_ctx: Dictionary = {}, power_preview: int = 0) -> void:
	if zoom_ctx.is_empty():
		zoom_ctx = _board._infer_zoom_ctx(card_data)
	var entries := _board._zoom_entries_for(zoom_ctx)
	# Variable printed bases ("counter power / threat level X"): surface the
	# resolved value as a badge on the zoomed card itself, not just as a
	# panel row. CP rides the power-preview badge (0 = hidden sentinel).
	var cp_base: int = ModifierBreakdown.variable_base(entries, "cp_var_base")
	if power_preview == 0 and cp_base > 0:
		power_preview = cp_base
	_board.card_zoom_overlay.show_card(card_data, play_cost_modifier, entries, power_preview,
		ModifierBreakdown.variable_base(entries, "threat_var_base"))


## PlayerState for zoom lookups that must not assume either mode is ready
## (returns null instead of indexing an unpopulated client cache).


func _zoom_player_state(pid: int) -> PlayerState:
	if pid < 0 or pid > 1:
		return null
	if _board.turn_manager and _board.turn_manager.game_state:
		return _board.turn_manager.game_state.players[pid]
	if pid < _board._client_players.size():
		return _board._client_players[pid]
	return null


func _hand_zoom_ctx(card_data: Dictionary, hand_player_id: int) -> Dictionary:
	var player := _board._zoom_player_state(hand_player_id)
	if player == null:
		return {}
	var card_id: String = card_data.get("id", "")
	for hi in range(player.hand.size()):
		if player.hand[hi].get("id", "") == card_id:
			return {"player_id": hand_player_id, "location": "hand", "index": hi}
	return {}


## Locate the zoomed copy for context-free callers (overlay grids, gallery,
## long-press). In-play locations are searched before hands: monster ids are
## bare template ids, so an in-play hit must win over a same-template hand
## copy. A miss means no modifiers apply to this exact copy (deck/discard/
## gallery duplicates) and the sources panel stays hidden.


func _infer_zoom_ctx(card_data: Dictionary) -> Dictionary:
	var card_id: String = card_data.get("id", "")
	if card_id.is_empty():
		return {}
	for pid in range(2):
		var player := _board._zoom_player_state(pid)
		if player == null:
			continue
		if player.current_monster.get("id", "") == card_id:
			return {"player_id": pid, "location": "monster"}
		for i in range(8):
			if player.get_zone_top_card(i).get("id", "") == card_id:
				return {"player_id": pid, "location": "zone", "index": i}
		for si in range(player.strategy_zones.size()):
			if player.strategy_zones[si].get("id", "") == card_id:
				return {"player_id": pid, "location": "strategy", "index": si}
	for pid in range(2):
		var player := _board._zoom_player_state(pid)
		if player == null:
			continue
		for hi in range(player.hand.size()):
			if player.hand[hi].get("id", "") == card_id:
				return {"player_id": pid, "location": "hand", "index": hi}
	return {}


## Modifier-panel row click: re-target the zoom onto the source card.
## Prefer the actual in-play copy (its own modifiers then show via the
## instance-id inference); fall back to the bare template for display.


func _zoom_to_source(template_id: String) -> void:
	for pid in range(2):
		var player := _board._zoom_player_state(pid)
		if player == null:
			continue
		var candidates: Array = [player.current_monster]
		for i in range(8):
			candidates.append(player.get_zone_top_card(i))
		for sz_card in player.strategy_zones:
			candidates.append(sz_card)
		for card in candidates:
			if not card.is_empty() and CardUtils.base_id(card) == template_id:
				_board._show_card_zoom(card)
				return
	var template: Dictionary = CardData.get_card_by_id(template_id)
	if not template.is_empty():
		_board._show_card_zoom(template.duplicate(true))


## Resolve a zoom context to modifier-source entries. Host/solo builds them
## on demand from the effect handler; clients read the breakdowns packed
## into the state broadcast (mirrors the threat_display host/client split).


func _zoom_entries_for(zoom_ctx: Dictionary) -> Array:
	if zoom_ctx.is_empty():
		return []
	var pid: int = zoom_ctx.get("player_id", -1)
	var location: String = zoom_ctx.get("location", "")
	var index: int = zoom_ctx.get("index", -1)
	var raw: Array
	if _board.turn_manager and _board.turn_manager.effect_handler:
		raw = _board._host_zoom_entries(pid, location, index)
	else:
		raw = ModifierBreakdown.collect(_board._session.client_modifier_breakdowns, pid, location, index)
	# Tag opponent-controlled sources for display (duplicate — the client
	# entries live in the synced cache and must not be mutated).
	var out: Array = []
	for e in raw:
		var tagged: Dictionary = e.duplicate()
		var owner_pid: int = int(e.get("owner", -1))
		tagged["opp"] = owner_pid >= 0 and owner_pid != pid
		out.append(tagged)
	_board._front_load_variable_base(out)
	return out


## Move a variable-base entry (resolved printed "X") to the front so it reads
## as the base line above the modifiers. Cards without a variable base get no
## base row — their printed stat is already on the card art.


func _front_load_variable_base(out: Array) -> void:
	for i in range(out.size()):
		var stat: String = str(out[i].get("stat", ""))
		if stat == "cp_var_base" or stat == "threat_var_base":
			if i > 0:
				out.insert(0, out.pop_at(i))
			return


func _host_zoom_entries(pid: int, location: String, index: int) -> Array:
	var eh: EffectHandler = _board.turn_manager.effect_handler
	var player: PlayerState = _board.turn_manager.game_state.players[pid]
	var out: Array = []
	match location:
		"zone":
			if index >= 0 and index < 8:
				out.append_array(eh.get_zone_cp_breakdown(pid)[index])
				out.append_array(eh.get_field_rank_breakdown(pid)[index])
		"monster":
			ModifierBreakdown.append(out, "cp", eh.get_monster_cp_modifier(pid), player.current_monster, -1, pid, "monster")
			out.append_array(eh.get_threat_level_breakdown(pid))
		"strategy":
			var mods: Array = eh.get_strategy_cp_modifiers(pid)
			if index >= 0 and index < mods.size() and index < player.strategy_zones.size():
				ModifierBreakdown.append(out, "cp", int(mods[index]), player.strategy_zones[index], -1, pid, "strategy")
		"hand":
			if index >= 0 and index < player.hand.size():
				out = ModifierBreakdown.hand_entries(eh, pid, player.hand[index])
	return out


## Overlay on_hidden hook: reset all slot input state so no timers or
## pending clicks carry over.


func _on_card_zoom_hidden() -> void:
	for board in [_board.player1_board, _board.player2_board]:
		for slot in board.zone_slots:
			slot.reset_input_state()

# --- Card hover preview ---


func _show_card_preview(data: Dictionary, play_cost_modifier: int = 0, power_preview: int = 0) -> void:
	if _board._is_mobile_layout:
		return # Mobile uses tap-to-zoom instead of hover preview
	if data.is_empty():
		return
	_board._preview_card.set_card_data_dict(data)
	if _board._preview_card.has_method("set_play_cost_modifier"):
		_board._preview_card.set_play_cost_modifier(play_cost_modifier)
	# Variable printed bases: slot hovers emit no power value, so locate the
	# hovered copy and pull the resolved X from its breakdown entries. -1
	# threat clears the persistent preview card's badge between hovers.
	var entries := _board._zoom_entries_for(_board._infer_zoom_ctx(data))
	var cp_base: int = ModifierBreakdown.variable_base(entries, "cp_var_base")
	if power_preview == 0 and cp_base > 0:
		power_preview = cp_base
	if _board._preview_card.has_method("set_power_preview"):
		_board._preview_card.set_power_preview(power_preview)
	if _board._preview_card.has_method("set_threat_preview"):
		_board._preview_card.set_threat_preview(ModifierBreakdown.variable_base(entries, "threat_var_base"))
	var is_strategy: bool = data.get("card_type", -1) == CardEnums.CardType.STRATEGY
	if is_strategy:
		_board._show_strategy_preview()
	else:
		_board._show_normal_preview()
	# Re-orient the badge after preview rotation/size was applied above.
	if _board._preview_card.has_method("update_play_cost_badge_layout"):
		_board._preview_card.update_play_cost_badge_layout()


func _show_normal_preview() -> void:
	# Position container at top-right for normal cards
	_board._preview_container.anchor_left = 0.75
	_board._preview_container.anchor_right = 0.995
	_board._preview_container.anchor_top = 0.05
	_board._preview_container.anchor_bottom = 0.75
	# Fit card (5:7 aspect) inside container while preserving ratio
	var container_size := _board._preview_container.size
	var card_ratio := 5.0 / 7.0
	var card_w := container_size.x
	var card_h := card_w / card_ratio
	if card_h > container_size.y:
		card_h = container_size.y
		card_w = card_h * card_ratio
	var card_pos := Vector2((container_size.x - card_w) / 2.0, (container_size.y - card_h) / 2.0)
	var padding := 6.0
	_board._preview_bg.position = card_pos - Vector2(padding, padding)
	_board._preview_bg.size = Vector2(card_w, card_h) + Vector2(padding * 2, padding * 2)
	_board._preview_card.size = Vector2(card_w, card_h)
	_board._preview_card.position = card_pos
	_board._preview_card.pivot_offset = Vector2(card_w, card_h) / 2.0
	_board._preview_card.scale = Vector2.ONE
	_board._preview_card.rotation = 0.0
	_board._preview_container.visible = true


func _show_strategy_preview() -> void:
	# Position container at right edge, between opponent board and player hand
	_board._preview_container.anchor_left = 0.6
	_board._preview_container.anchor_right = 1.0
	_board._preview_container.anchor_top = 0.47
	_board._preview_container.anchor_bottom = 0.88
	var container_size := _board._preview_container.size
	var card_ratio := 5.0 / 7.0
	# When rotated 90 CCW, visual width = card_h and visual height = card_w
	# Fit so the rotated card fills the container
	var visual_h := container_size.y
	var card_w := visual_h # un-rotated height becomes visual height
	var card_h := card_w / card_ratio # un-rotated width becomes visual width
	if card_h > container_size.x:
		card_h = container_size.x
		card_w = card_h * card_ratio
		visual_h = card_w
	var visual_w := card_h
	var card_pos := Vector2(
		container_size.x - visual_w,
		(container_size.y - visual_h) / 2.0
	)
	_board._preview_card.size = Vector2(card_w, card_h)
	_board._preview_card.pivot_offset = Vector2(card_w, card_h) / 2.0
	_board._preview_card.rotation = - PI / 2.0
	_board._preview_card.scale = Vector2.ONE
	_board._preview_card.position = card_pos + Vector2((visual_w - card_w) / 2.0, (visual_h - card_h) / 2.0)
	var padding := 6.0
	_board._preview_bg.position = card_pos - Vector2(padding, padding)
	_board._preview_bg.size = Vector2(visual_w, visual_h) + Vector2(padding * 2, padding * 2)
	_board._preview_container.visible = true


func _hide_card_preview() -> void:
	_board._preview_container.visible = false
