class_name StandbyResolver
extends RefCounted

## Resolves standby automatic abilities per rules 10.4.3 / 10.6.3.1:
## turn player's abilities first, player chooses the order within their own
## batch, rule actions checked before each ability, and entries spawned
## mid-resolution drain into follow-up batches.
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
## callback is executing, the current player's remaining orderable batch, and
## the other player's batch waiting behind it (aliases of the live arrays —
## rows are composed fresh at each publish).
var _stack_active: Dictionary = {}
var _stack_remaining: Array = []
var _other_player_batch: Array = []


func resolve_entries(entries: Array) -> void:
	## Resolve collected standby automatic abilities per rules 10.4.3 ordering.
	## entries: Array of { "player_id": int, "card_data": Dictionary, "callback": Callable }
	## Turn player's abilities resolve first (10.4.3.2), then non-turn player's (10.4.3.3).
	if entries.is_empty():
		return

	# Re-entrancy guard: defer if already in standby resolution OR if an effect
	# callback is actively executing. The second case covers e.g. trigger_enter's
	# direct path, where in_standby_resolution is false but an active card is
	# set — without this guard, a trigger called from within that callback
	# would run immediately instead of deferring behind the active effect's enter.
	if exec.should_defer():
		exec.pending_standby_entries.append_array(entries)
		_publish_stack()
		return

	exec.in_standby_resolution = true
	var current_entries: Array = entries

	while not current_entries.is_empty():
		var turn_pid: int = game_state.current_player_id

		# Separate by player: turn player first, non-turn player second (10.4.3.2-10.4.3.3)
		var turn_entries: Array = []
		var non_turn_entries: Array = []
		for entry in current_entries:
			if entry.player_id == turn_pid:
				turn_entries.append(entry)
			else:
				non_turn_entries.append(entry)

		# Resolve turn player's abilities first (10.4.3.2), then non-turn player's (10.4.3.3)
		_other_player_batch = non_turn_entries
		await _resolve_player_standby(turn_pid, turn_entries)
		_other_player_batch = []
		await _resolve_player_standby(1 - turn_pid, non_turn_entries)

		# Drain any entries that accumulated during this batch
		current_entries = exec.pending_standby_entries
		exec.pending_standby_entries = []

	exec.in_standby_resolution = false
	_stack_active = {}
	_stack_remaining = []
	_other_player_batch = []
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
	##   instance_id, base_id, label }. index is 0-based (-1 when kind has no
	## index). Uses a temporary marker key to find the exact dictionary
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


func _resolve_player_standby(player_id: int, entries: Array) -> void:
	## Resolve one player's standby abilities, letting them choose order if multiple (10.6.3.1).
	## Playing is compulsory — cannot choose to skip (10.6.3.1).
	while not entries.is_empty():
		# Check rule actions before each ability (10.4.3.1)
		if handler.action_handler:
			await handler.action_handler.resolve_check_timing(game_state)

		# Publish the full batch as pending so the stack UI shows it during
		# the order-choice prompt.
		_stack_active = {}
		_stack_remaining = entries
		_publish_stack()

		var entry: Dictionary
		if entries.size() == 1:
			entry = entries.pop_back()
		else:
			# Multiple abilities in standby — player chooses order (10.6.3.1)
			var options: Array[String] = []
			var option_card_ids: Array[String] = []
			var source_refs: Array[Dictionary] = []
			for e in entries:
				var ref := card_location_ref(game_state, e.player_id, e.card_data)
				options.append(ref["label"])
				option_card_ids.append(CardUtils.base_id(e.card_data))
				source_refs.append(ref)
			handler.choice_source_refs = source_refs
			var chosen: int = await handler.select_choice(player_id, options, tr("STR_EFF_CHOOSE_ABILITY"), option_card_ids)
			if chosen < 0 or chosen >= entries.size():
				chosen = 0
			entry = entries.pop_at(chosen)

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

		# Drain pending entries for this player into the current queue so the
		# player can choose resolution order among them (10.6.3.1).
		# Entries for the other player stay in pending_standby_entries for the
		# outer resolve_entries loop to handle.
		var remaining: Array = []
		for p in exec.pending_standby_entries:
			if p.player_id == player_id:
				entries.append(p)
			else:
				remaining.append(p)
		exec.pending_standby_entries = remaining

		_stack_active = {}
		_publish_stack()


func _publish_stack() -> void:
	## Emit the current pending-effect stack (resolving entry first) via
	## GameEvents so the UI can keep the player informed mid-resolution.
	## Pure notification — nothing awaits it; no-op without a wired bus.
	if handler == null or handler.events == null:
		return
	var rows: Array = []
	if not _stack_active.is_empty():
		rows.append(_stack_row(_stack_active, "resolving"))
	for e in _stack_remaining:
		rows.append(_stack_row(e, "pending"))
	for e in _other_player_batch:
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
