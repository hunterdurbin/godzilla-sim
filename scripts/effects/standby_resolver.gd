class_name StandbyResolver
extends RefCounted

## Resolves standby automatic abilities per rules 10.4.3 / 10.6.3.1 as ONE
## pool: after every ability, rule actions are performed (10.4.3.1); then the
## turn player, if they have any abilities in standby, picks one of ALL of
## theirs (10.4.3.2), otherwise the non-turn player picks one of theirs
## (10.4.3.3); repeat until none remain (10.4.3.4). Entries spawned while an
## ability resolves join the pool immediately.
##
## Dependencies (wired by EffectHandler.setup):
##  - game_state: turn ownership + card location labels
##  - exec: shared EffectExecutionState (re-entrancy guard + pending queue)
##  - handler: the EffectHandler facade, used for the order-choice prompt
##    (select_choice) and active-effect set/clear (highlight choreography
##    stays with the facade's signals)
##  - handler.action_handler: rule-action check timing between abilities

var game_state: GameState
var exec: EffectExecutionState
var handler: EffectHandler

## Snapshot state for the effect_stack_changed notification: the entry whose
## callback is executing and the rest of the live pool (alias of the live
## array — rows are composed fresh at each publish).
var _stack_active: Dictionary = {}
var _stack_pool: Array = []


func resolve_entries(entries: Array) -> void:
	## Resolve collected standby automatic abilities per rules 10.4.3.
	## entries: Array of { "player_id": int, "card_data": Dictionary, "callback": Callable }
	## Optional keys: "still_applies" (Callable gate, 10.6.3), "skip_active_check".
	if entries.is_empty():
		return

	# Re-entrancy guard: defer if already in standby resolution OR if an effect
	# callback is actively executing. Deferred entries land in
	# pending_standby_entries, which the running pass merges into its live
	# pool after the current ability (or trigger_enter drains after the
	# active <Enter>).
	if exec.should_defer():
		exec.pending_standby_entries.append_array(entries)
		_publish_stack()
		return

	exec.in_standby_resolution = true
	var pool: Array = entries.duplicate()
	_stack_pool = pool

	while true:
		# 10.4.3.1: perform rule actions. Abilities they trigger (crush) defer
		# into pending and join the pool below.
		if handler.action_handler:
			await handler.action_handler.resolve_check_timing(game_state)
		_merge_pending(pool)

		# 10.6.3: an ability in standby that can no longer be played ceases to
		# exist — drop it before the order prompt so it never shows as a no-op.
		_drop_inapplicable(pool)
		if pool.is_empty():
			break

		# 10.4.3.2 / 10.4.3.3: turn player first, else non-turn player.
		var turn_pid: int = game_state.current_player_id
		var chooser: int = turn_pid if _has_entries_for(pool, turn_pid) else 1 - turn_pid
		var entry: Dictionary = await _choose_entry(chooser, pool)

		# Keep the chosen entry visible as "resolving" through any nested
		# prompts its callback opens.
		_stack_active = entry
		_publish_stack()

		var saved_player_id: int = exec.active_player_id
		var saved_card: Dictionary = exec.active_card
		handler._set_active_effect(entry.player_id, entry.card_data)
		await entry.callback.call()
		if saved_card.is_empty():
			handler._clear_active_effect()
		else:
			handler._set_active_effect(saved_player_id, saved_card)

		_stack_active = {}
		_merge_pending(pool)
		_publish_stack()

	exec.in_standby_resolution = false
	_stack_active = {}
	_stack_pool = []
	_publish_stack()


func resolve_deferred_entries(entries: Array) -> void:
	## Filter entries for cards still in play after movement, then resolve via standby pattern.
	## Entries with skip_active_check (e.g. on_discard_from_hand) bypass the filter since
	## those cards are in the discard pile, not on the field.
	var active_entries: Array = []
	for entry in entries:
		if entry.get("skip_active_check", false) or is_card_still_active(entry.player_id, entry.card_data):
			active_entries.append(entry)
	await resolve_entries(active_entries)


func is_card_still_active(player_id: int, card_data: Dictionary) -> bool:
	## Check if a card is still in an active position (monster, zone top, or strategy zone).
	var player := game_state.players[player_id]
	if is_same(card_data, player.current_monster):
		return true
	for i in range(8):
		if is_same(player.get_zone_top_card(i), card_data):
			return true
	for sz_card in player.strategy_zones:
		if is_same(sz_card, card_data):
			return true
	return false


static func card_location_label(state: GameState, player_id: int, card_data: Dictionary) -> String:
	## Return a display label like "Card Name (Zone 3)" for standby choice prompts.
	return card_location_ref(state, player_id, card_data)["label"]


static func card_location_ref(state: GameState, player_id: int, card_data: Dictionary) -> Dictionary:
	## Locate a card's current position as a structured ref for the UI:
	## { player_id, kind: "monster"|"zone"|"strategy"|"discard"|"", index,
	##   instance_id, base_id, label, covered }. index is 0-based (-1 when kind
	## has no index). covered = the card sits under its zone's top card (an
	## ability already in standby still resolves after its card is evolved
	## over, 10.6.7). Uses a temporary marker key to find the exact dictionary
	## reference, since multiple cards can share the same ID (e.g. tokens).
	var player := state.players[player_id]
	var card_name: String = card_data.get("name", "Unknown")
	var ref := {
		"player_id": player_id,
		"kind": "",
		"index": -1,
		"instance_id": card_data.get("id", ""),
		"base_id": CardUtils.base_id(card_data),
		"label": card_name,
		"covered": false,
	}
	if not player.current_monster.is_empty() and player.current_monster.get("id", "") == card_data.get("id", ""):
		ref["kind"] = "monster"
		ref["label"] = card_name + " (Monster)"
		return ref
	var _marker := "__ref_marker"
	card_data[_marker] = true
	for i in range(8):
		var top := player.get_zone_top_card(i)
		if not top.is_empty() and top.has(_marker):
			card_data.erase(_marker)
			ref["kind"] = "zone"
			ref["index"] = i
			ref["label"] = card_name + " (Zone %d)" % (i + 1)
			return ref
	for i in range(8):
		for under in player.get_zone_stack(i).slice(1):
			if under.has(_marker):
				card_data.erase(_marker)
				ref["kind"] = "zone"
				ref["index"] = i
				ref["covered"] = true
				ref["label"] = card_name + " (Zone %d, covered)" % (i + 1)
				return ref
	for i in range(player.strategy_zones.size()):
		if not player.strategy_zones[i].is_empty() and player.strategy_zones[i].has(_marker):
			card_data.erase(_marker)
			ref["kind"] = "strategy"
			ref["index"] = i
			ref["label"] = card_name + " (Strategy %d)" % (i + 1)
			return ref
	for discard_card in player.discard_pile:
		if discard_card.has(_marker):
			card_data.erase(_marker)
			ref["kind"] = "discard"
			ref["label"] = card_name + " (Discard)"
			return ref
	card_data.erase(_marker)
	return ref


func _choose_entry(player_id: int, pool: Array) -> Dictionary:
	## Remove and return the ability `player_id` resolves next. Playing is
	## compulsory (10.6.3.1); with several, the player chooses which.
	var indices: Array[int] = []
	for i in range(pool.size()):
		if pool[i].player_id == player_id:
			indices.append(i)
	if indices.size() == 1:
		return pool.pop_at(indices[0])

	# Publish the pool as pending so the stack UI shows it during the prompt.
	_stack_active = {}
	_publish_stack()

	var options: Array[String] = []
	var option_card_ids: Array[String] = []
	var source_refs: Array[Dictionary] = []
	for i in indices:
		var e: Dictionary = pool[i]
		var ref := card_location_ref(game_state, e.player_id, e.card_data)
		options.append(ref["label"])
		option_card_ids.append(CardUtils.base_id(e.card_data))
		source_refs.append(ref)
	handler.choice_source_refs = source_refs
	var chosen: int = await handler.select_choice(player_id, options, tr("STR_EFF_CHOOSE_ABILITY"), option_card_ids)
	if chosen < 0 or chosen >= indices.size():
		chosen = 0
	return pool.pop_at(indices[chosen])


func _merge_pending(pool: Array) -> void:
	## Move abilities that entered standby while the pool was busy into it.
	if exec.pending_standby_entries.is_empty():
		return
	pool.append_array(exec.pending_standby_entries)
	exec.pending_standby_entries = []


static func _has_entries_for(pool: Array, player_id: int) -> bool:
	for e in pool:
		if e.player_id == player_id:
			return true
	return false


func _publish_stack() -> void:
	## Emit the current pending-effect stack (resolving entry first) via
	## GameEvents so the UI can keep the player informed mid-resolution.
	## Pure notification — nothing awaits it; no-op without a wired bus.
	if handler == null or handler.events == null:
		return
	var rows: Array = []
	if not _stack_active.is_empty():
		rows.append(_stack_row(_stack_active, "resolving"))
	for e in _stack_pool:
		rows.append(_stack_row(e, "pending"))
	for e in exec.pending_standby_entries:
		rows.append(_stack_row(e, "pending"))
	handler.events.effect_stack_changed.emit(rows)


func _stack_row(entry: Dictionary, status: String) -> Dictionary:
	var loc := card_location_ref(game_state, entry.player_id, entry.card_data)
	return {
		"player_id": entry.player_id,
		"base_id": loc["base_id"],
		"label": loc["label"],
		"status": status,
		"location": loc,
	}


static func _drop_inapplicable(entries: Array) -> void:
	## Remove (in place) entries whose optional "still_applies" Callable
	## reports false at resolution time (10.6.3).
	for i in range(entries.size() - 1, -1, -1):
		var gate: Variant = entries[i].get("still_applies")
		if gate is Callable and (gate as Callable).is_valid() and not bool((gate as Callable).call()):
			entries.remove_at(i)
