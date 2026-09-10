class_name BoardEditor
extends RefCounted

## Free-form debug mutation engine behind the F4 board editor overlay.
##
## Mutates PlayerState containers directly with NO rules validation — the
## editor exists to force states no real game reaches (effects whose on-play
## triggers never fired, illegal stacks, arbitrary rage). Only structural
## invariants hold: minted cards are deep copies with unique instance ids,
## and any card landing on the field gets its CardEffect registered (the
## same guarantee MatchFactory.setup_from_save provides on load).
##
## Every public method ends by emitting the PlayerState signals for the
## containers it touched — GameBoard listens to those for a full resync.
## Local (SOLO / SOLO_BOT) games only; the overlay enforces the gate.

var _tm: TurnManager

static var _ed_serial: int = 0


func _init(tm: TurnManager) -> void:
	_tm = tm


func _player(pid: int) -> PlayerState:
	return _tm.game_state.players[clampi(pid, 0, 1)]


## Deep-copy a template and stamp a unique editor instance id. The "_ed_"
## suffix survives the first-underscore split in CardUtils.base_id and
## GameSerializer.id_to_card (base ids contain "-", never "_").
func mint_card(base_id: String) -> Dictionary:
	var template: Dictionary = CardData.CARD_TEMPLATES.get(base_id, {})
	if template.is_empty():
		return {}
	var card: Dictionary = template.duplicate(true)
	card["id"] = "%s_ed_%d" % [base_id, _ed_serial]
	_ed_serial += 1
	return card


## Field cards need a live CardEffect (cached per script path; re-calls are
## no-ops). Mirrors MatchFactory._register_field_effect.
func _register(card: Dictionary) -> void:
	if not card.is_empty():
		_tm.effect_handler.get_effect(card)


# --- Battle zones (0-based zone index; stack index 0 = top) ---

func add_to_zone(pid: int, zone: int, card: Dictionary, on_top: bool) -> void:
	if zone < 0 or zone >= 8 or card.is_empty():
		return
	var player := _player(pid)
	if on_top:
		player.zones[zone].push_front(card)
	else:
		player.zones[zone].append(card)
	_register(card)
	player.zones_changed.emit()


func remove_from_zone(pid: int, zone: int, stack_index: int) -> Dictionary:
	var player := _player(pid)
	if zone < 0 or zone >= 8 or stack_index < 0 or stack_index >= player.zones[zone].size():
		return {}
	var card: Dictionary = player.zones[zone].pop_at(stack_index)
	player.zones_changed.emit()
	return card


func move_zone_card(pid: int, zone: int, from_index: int, to_index: int) -> void:
	var player := _player(pid)
	var stack: Array = player.zones[zone]
	if from_index < 0 or from_index >= stack.size():
		return
	var card: Dictionary = stack.pop_at(from_index)
	stack.insert(clampi(to_index, 0, stack.size()), card)
	player.zones_changed.emit()


func move_zone_stack(pid: int, from_zone: int, to_zone: int, on_top: bool) -> void:
	if from_zone == to_zone:
		return
	var player := _player(pid)
	var stack: Array = player.zones[from_zone]
	if stack.is_empty():
		return
	player.zones[from_zone] = []
	if on_top:
		player.zones[to_zone] = stack + player.zones[to_zone]
	else:
		player.zones[to_zone].append_array(stack)
	player.zones_changed.emit()


# --- Strategy zones (slot 0-1; under-stack index 0 = top) ---

## PlayerBoard renders 3 strategy slots but the engine has only 2 zones —
## out-of-range slot indices must no-op, not crash.
func _strategy_slot_ok(player: PlayerState, slot: int) -> bool:
	return slot >= 0 and slot < player.strategy_zones.size()


## Set the slot's strategy card. Returns the evicted old card + its
## under-stack (caller decides where they go).
func set_strategy(pid: int, slot: int, card: Dictionary) -> Array:
	var player := _player(pid)
	if not _strategy_slot_ok(player, slot):
		return []
	var evicted: Array = _take_strategy(player, slot)
	player.strategy_zones[slot] = card
	player.strategy_zone_turn_placed[slot] = _tm.game_state.turn_number
	_register(card)
	player.strategy_zones_changed.emit()
	return evicted


func clear_strategy(pid: int, slot: int) -> Array:
	var player := _player(pid)
	if not _strategy_slot_ok(player, slot):
		return []
	var cleared: Array = _take_strategy(player, slot)
	player.strategy_zones_changed.emit()
	return cleared


func _take_strategy(player: PlayerState, slot: int) -> Array:
	var taken: Array = []
	var old: Dictionary = player.strategy_zones[slot]
	if not old.is_empty():
		taken.append(old)
	taken.append_array(player.strategy_zone_stacks[slot])
	player.strategy_zones[slot] = {}
	player.strategy_zone_stacks[slot] = []
	return taken


func add_under_strategy(pid: int, slot: int, card: Dictionary, on_top: bool) -> void:
	if card.is_empty():
		return
	var player := _player(pid)
	if not _strategy_slot_ok(player, slot):
		return
	if on_top:
		player.strategy_zone_stacks[slot].push_front(card)
	else:
		player.strategy_zone_stacks[slot].append(card)
	_register(card)
	player.strategy_zones_changed.emit()


func remove_under_strategy(pid: int, slot: int, index: int) -> Dictionary:
	var player := _player(pid)
	if not _strategy_slot_ok(player, slot):
		return {}
	var stack: Array = player.strategy_zone_stacks[slot]
	if index < 0 or index >= stack.size():
		return {}
	var card: Dictionary = stack.pop_at(index)
	player.strategy_zones_changed.emit()
	return card


# --- Monster (monster_stack index 0 = directly below current) ---

## Replace the current monster ({} = remove). old_to routes the displaced
## monster: "stack_top" (directly below the new top), "discard", "remove"
## (returned only). Returns the displaced monster.
func set_current_monster(pid: int, card: Dictionary, old_to: String) -> Dictionary:
	var player := _player(pid)
	var old: Dictionary = player.current_monster
	player.current_monster = card
	_register(card)
	if not old.is_empty():
		match old_to:
			"stack_top":
				player.monster_stack.push_front(old)
			"discard":
				player.discard_pile.append(old)
				player.discard_changed.emit()
			_:
				pass
	player.monster_changed.emit()
	return old


func stack_under_monster(pid: int, card: Dictionary, index: int = -1) -> void:
	if card.is_empty():
		return
	var player := _player(pid)
	if index < 0 or index >= player.monster_stack.size():
		player.monster_stack.append(card)
	else:
		player.monster_stack.insert(index, card)
	player.monster_changed.emit()


func remove_from_monster_stack(pid: int, index: int) -> Dictionary:
	var player := _player(pid)
	if index < 0 or index >= player.monster_stack.size():
		return {}
	var card: Dictionary = player.monster_stack.pop_at(index)
	player.monster_changed.emit()
	return card


func promote_from_stack(pid: int, index: int, old_to: String) -> void:
	var card: Dictionary = remove_from_monster_stack(pid, index)
	if card.is_empty():
		return
	set_current_monster(pid, card, old_to)


## Move the monster the way the engine would: cards under the monster live
## in monster_stack and travel with it implicitly; battle cards at the
## destination are crushed through the engine's rule action (rule 11.3 —
## destroy replacements, leave-play and crush/revenge triggers all
## resolve). Only the MOVING player's zone is crush-checked, so cards
## sharing the opponent's stationary monster's zone are untouched.
## Residual cards in the departed zone stay behind, engine-style.
## Coroutine: crush resolution can raise real input prompts.
func set_monster_zone(pid: int, zone_number: int) -> void:
	var player := _player(pid)
	var target: int = clampi(zone_number, 1, 8)
	if target == player.monster_zone:
		return
	player.monster_zone = target
	player.monster_changed.emit()
	if _tm.action_handler:
		await _tm.action_handler.rule_actions._check_crush_for_player(_tm.game_state, player.player_id)


# --- Hand / deck / discard (deck index 0 = top; -1 = bottom) ---

func add_to_hand(pid: int, card: Dictionary) -> void:
	if card.is_empty():
		return
	var player := _player(pid)
	player.hand.append(card)
	player.hand_changed.emit()


func remove_from_hand(pid: int, index: int) -> Dictionary:
	var player := _player(pid)
	if index < 0 or index >= player.hand.size():
		return {}
	var card: Dictionary = player.hand.pop_at(index)
	player.hand_changed.emit()
	return card


func add_to_deck(pid: int, card: Dictionary, index: int = 0) -> void:
	if card.is_empty():
		return
	var player := _player(pid)
	if index < 0:
		player.main_deck.append(card)
	else:
		player.main_deck.insert(clampi(index, 0, player.main_deck.size()), card)
	player.deck_changed.emit()


func remove_from_deck(pid: int, index: int) -> Dictionary:
	var player := _player(pid)
	if index < 0 or index >= player.main_deck.size():
		return {}
	var card: Dictionary = player.main_deck.pop_at(index)
	player.deck_changed.emit()
	return card


## Replace the deck order. Rejects anything that isn't a permutation of the
## current deck (same instance-id multiset), so cards can't be conjured or
## lost through a reorder.
func reorder_deck(pid: int, new_order: Array) -> bool:
	var player := _player(pid)
	if _id_multiset(new_order) != _id_multiset(player.main_deck):
		return false
	player.main_deck.assign(new_order)
	player.deck_changed.emit()
	return true


func _id_multiset(cards: Array) -> Array:
	var ids: Array = []
	for card in cards:
		ids.append(str(card.get("id", "")))
	ids.sort()
	return ids


func add_to_discard(pid: int, card: Dictionary) -> void:
	if card.is_empty():
		return
	var player := _player(pid)
	player.discard_pile.append(card)
	player.discard_changed.emit()


func remove_from_discard(pid: int, index: int) -> Dictionary:
	var player := _player(pid)
	if index < 0 or index >= player.discard_pile.size():
		return {}
	var card: Dictionary = player.discard_pile.pop_at(index)
	player.discard_changed.emit()
	return card


func add_to_monster_deck(pid: int, card: Dictionary) -> void:
	if card.is_empty():
		return
	var player := _player(pid)
	player.monster_deck.append(card)
	# No dedicated signal — monster_changed resyncs the MonsterInfo count.
	player.monster_changed.emit()


func remove_from_monster_deck(pid: int, index: int) -> Dictionary:
	var player := _player(pid)
	if index < 0 or index >= player.monster_deck.size():
		return {}
	var card: Dictionary = player.monster_deck.pop_at(index)
	player.monster_changed.emit()
	return card


# --- Counters / flags ---

## Deliberately bypasses EffectHandler.gain_rage / reduce_rage (prevention
## effects, rage-marker claim buckets) — the editor is free-form.
func set_rage(pid: int, value: int) -> void:
	var player := _player(pid)
	player.rage = maxi(0, value)
	player.rage_changed.emit(player.rage)


func adjust_rage(pid: int, delta: int) -> void:
	set_rage(pid, _player(pid).rage + delta)


func set_turn_flag(pid: int, flag: String, value: bool) -> void:
	var player := _player(pid)
	match flag:
		"has_invaded_this_turn":
			player.has_invaded_this_turn = value
		"has_played_monster_this_turn":
			player.has_played_monster_this_turn = value
		_:
			return
	# No dedicated signal for flags — nudge a board resync.
	player.monster_changed.emit()


# --- Cross-container mover ---

## Move one card between containers. src/dst descriptors:
##   {pid, container: "zone"|"strategy"|"strategy_under"|"hand"|"deck"|
##    "discard"|"monster"|"monster_stack", zone, slot, index, on_top, old_to}
## Composed from the remove/add primitives so signals and effect
## registration are always right. A "strategy" destination discards any
## evicted card + under-stack; a "strategy" source takes only the strategy
## card and leaves its under-stack in place.
func move_card(src: Dictionary, dst: Dictionary) -> void:
	var card: Dictionary = _remove_desc(src)
	if card.is_empty():
		return
	_add_desc(dst, card)


func _remove_desc(src: Dictionary) -> Dictionary:
	var pid: int = src.get("pid", 0)
	var index: int = src.get("index", 0)
	match str(src.get("container", "")):
		"zone":
			return remove_from_zone(pid, src.get("zone", 0), index)
		"strategy":
			var player := _player(pid)
			var slot: int = src.get("slot", 0)
			if not _strategy_slot_ok(player, slot):
				return {}
			var card: Dictionary = player.strategy_zones[slot]
			player.strategy_zones[slot] = {}
			player.strategy_zones_changed.emit()
			return card
		"strategy_under":
			return remove_under_strategy(pid, src.get("slot", 0), index)
		"hand":
			return remove_from_hand(pid, index)
		"deck":
			return remove_from_deck(pid, index)
		"discard":
			return remove_from_discard(pid, index)
		"monster":
			return set_current_monster(pid, {}, "remove")
		"monster_stack":
			return remove_from_monster_stack(pid, index)
		"monster_deck":
			return remove_from_monster_deck(pid, index)
	return {}


func _add_desc(dst: Dictionary, card: Dictionary) -> void:
	var pid: int = dst.get("pid", 0)
	var on_top: bool = dst.get("on_top", true)
	match str(dst.get("container", "")):
		"zone":
			add_to_zone(pid, dst.get("zone", 0), card, on_top)
		"strategy":
			for evicted in set_strategy(pid, dst.get("slot", 0), card):
				add_to_discard(pid, evicted)
		"strategy_under":
			add_under_strategy(pid, dst.get("slot", 0), card, on_top)
		"hand":
			add_to_hand(pid, card)
		"deck":
			add_to_deck(pid, card, dst.get("index", 0))
		"discard":
			add_to_discard(pid, card)
		"monster":
			set_current_monster(pid, card, str(dst.get("old_to", "stack_top")))
		"monster_stack":
			stack_under_monster(pid, card, dst.get("index", -1))
		"monster_deck":
			add_to_monster_deck(pid, card)


# --- Snapshot patch (Turn... dialog) ---

## Override only the flow fields of a serialized game-state dict. Jumping
## phase without an explicit sub-phase restarts the phase from sub-phase 0.
static func patch_snapshot(data: Dictionary, patch: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	for key in ["current_phase", "current_player_id", "turn_number", "current_sub_phase"]:
		if patch.has(key):
			out[key] = patch[key]
	if patch.has("current_phase") and not patch.has("current_sub_phase"):
		out["current_sub_phase"] = 0
	return out
