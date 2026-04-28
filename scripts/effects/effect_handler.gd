class_name EffectHandler
extends RefCounted

## Loads, caches, and dispatches card effect triggers across the game.
## Called by ActionHandler and TurnManager at appropriate trigger points.

## Emitted when a player must choose cards to discard from hand.
## Connect from presentation layer to show a selection UI.
## Call resolve_hand_discard() with the chosen hand indices when done.
signal hand_discard_requested(player_id: int, discard_count: int)

## Emitted internally after resolve_hand_discard() processes the selection.
signal _hand_discard_resolved()

## Emitted when a player must choose a card from their deck during a search effect.
## Connect from presentation layer to show a deck search selection UI.
## Call resolve_deck_search() with the chosen card when done.
signal deck_search_requested(player_id: int, matching_cards: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, allow_skip: bool)

## Emitted internally after resolve_deck_search() stores the selection.
signal _deck_search_resolved()

## Emitted when a player must choose a specific card from their hand.
## Connect from presentation layer to show hand selection UI.
## Call resolve_hand_card_selection() with the chosen hand index when done.
signal hand_card_selection_requested(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool)

## Emitted internally after resolve_hand_card_selection() stores the selection.
signal _hand_card_selection_resolved()

## Emitted when a player must choose a target zone on a player's board.
## Connect from presentation layer to show zone highlighting UI.
## Call resolve_zone_target() with the chosen zone index when done.
signal zone_target_requested(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool)

## Emitted internally after resolve_zone_target() stores the selection.
signal _zone_target_resolved()

## Emitted when a player must choose a strategy zone on a player's board.
## Connect from presentation layer to highlight strategy slots and allow clicking.
## Call resolve_strategy_target() with the chosen strategy index when done.
signal strategy_target_requested(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String)

## Emitted internally after resolve_strategy_target() stores the selection.
signal _strategy_target_resolved()

## Emitted when a player must choose from multiple text options (e.g. "Choose one").
## Connect from presentation layer to show a choice dialog.
## Call resolve_choice() with the chosen index when done.
signal choice_requested(player_id: int, options: Array[String], prompt: String)

## Emitted internally after resolve_choice() stores the selection.
signal _choice_resolved()

## Emitted when a player must arrange cards from their deck (reorder + optional discard).
## Connect from presentation layer to show a deck arrange overlay.
## Call resolve_deck_arrange() with the kept and discarded cards when done.
signal deck_arrange_requested(player_id: int, cards: Array[Dictionary], prompt: String)

## Emitted internally after resolve_deck_arrange() stores the result.
signal _deck_arrange_resolved()

## Emitted when a player must select cards from a pool (e.g. discard pile).
## Connect from presentation layer to show a card selection UI with pool + selection areas.
## Call resolve_card_select() with the chosen cards when done.
signal card_select_requested(player_id: int, matching_cards: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int)

## Emitted internally after resolve_card_select() stores the result.
signal _card_select_resolved()

## Emitted to highlight/unhighlight a zone card during effect resolution.
signal effect_zone_highlighted(player_id: int, zone_index: int)
signal effect_zone_unhighlighted(player_id: int, zone_index: int)

## Emitted to highlight/unhighlight the source card while awaiting a player decision.
signal effect_card_highlighted(player_id: int, card_id: String)
signal effect_card_unhighlighted(player_id: int, card_id: String)

## Emitted when an effect wants to show a set of cards to the player (e.g. cards placed under a monster).
## Connect from presentation layer to display an overlay. Call resolve_cards_revealed() when dismissed.
signal cards_revealed_requested(player_id: int, cards: Array[Dictionary], title: String)

## Emitted internally after resolve_cards_revealed() is called.
signal _cards_revealed_resolved()

## Emitted to send a message to the game log.
signal log_message(token: Dictionary)
signal card_evolved(player_id: int, card: Dictionary, zone_index: int)
signal card_destroyed(player_id: int, zone_index: int)

const _TriggerMap = preload("res://scripts/effects/trigger_map.gd")

var game_state: GameState
var action_handler  # ActionHandler reference (set by TurnManager)
var _effect_cache: Dictionary = {}  # script_path -> CardEffect instance
var _filters_cache: Dictionary = {}  # script_path -> TRIGGER_FILTERS dict (declarative trigger gating)
var _deck_search_result: Dictionary = {}
var _deck_arrange_keep: Array[Dictionary] = []
var _deck_arrange_discard: Array[Dictionary] = []
var _card_select_result: Array[Dictionary] = []
var _card_select_pool_filter: Callable = Callable()  # Optional: func(card, selection) -> bool
var _zone_target_result: int = -1
var pending_destroy_max_rank: int = -1  # Set before zone_target_requested for bot rank filtering
var _strategy_target_result: int = -1
var _hand_card_selection_result: int = -1
var _choice_result: int = -1

# Tracks which card's effect is currently executing (for decision highlighting)
var _active_effect_player_id: int = -1
var _active_effect_card: Dictionary = {}

# Standby resolution deferral: when true, newly triggered enter/monster_played
# effects are queued in _pending_standby_entries instead of resolving inline (10.4.3).
var _in_standby_resolution: bool = false
var _pending_standby_entries: Array = []


func setup(p_game_state: GameState) -> void:
	game_state = p_game_state


# --- Effect loading ---

func get_effect(card_data: Dictionary) -> CardEffect:
	## Load and cache a CardEffect for the given card. Returns null if no effect script.
	var script_path: String = card_data.get("effect_script", "")
	if script_path.is_empty():
		return null

	if _effect_cache.has(script_path):
		return _effect_cache[script_path]

	if not ResourceLoader.exists(script_path):
		push_warning("EffectHandler: Effect script not found: %s" % script_path)
		return null

	var script: GDScript = load(script_path)
	if script == null:
		push_warning("EffectHandler: Failed to load effect script: %s" % script_path)
		return null

	var effect: CardEffect = script.new()
	_effect_cache[script_path] = effect
	return effect


func has_trigger(card_data: Dictionary, method_name: String) -> bool:
	## Check if a card's effect script actually overrides the given trigger method.
	## Uses a pre-generated trigger map (source_code is stripped in export builds,
	## so runtime introspection cannot detect overrides reliably).
	## Regenerate the map: bash scripts/effects/generate_trigger_map.sh
	var script_path: String = card_data.get("effect_script", "")
	if script_path.is_empty():
		return false
	var triggers: Array = _TriggerMap.TRIGGERS.get(script_path, [])
	return method_name in triggers


func get_trigger_filter(card_data: Dictionary, method_name: String) -> Dictionary:
	## Read the per-method filter dict an effect script declares as a class-level
	## TRIGGER_FILTERS constant. Returns {} if the script has no filter for the method.
	## See card_effect.gd header for the supported filter keys and semantics.
	var script_path: String = card_data.get("effect_script", "")
	if script_path.is_empty():
		return {}
	if not _filters_cache.has(script_path):
		var script: Script = load(script_path)
		var consts: Dictionary = script.get_script_constant_map() if script else {}
		_filters_cache[script_path] = consts.get("TRIGGER_FILTERS", {})
	var all_filters: Dictionary = _filters_cache[script_path]
	return all_filters.get(method_name, {})


func _passes_trigger_filter(filter: Dictionary, player_id: int, old_value: int, new_value: int) -> bool:
	## Evaluate a TRIGGER_FILTERS entry against the current state. Empty dict = pass.
	## "phase" / "own_turn" check current phase + turn ownership; "direction" checks
	## old_value vs new_value (only meaningful for triggers that pass deltas, e.g.
	## on_rage_changed). Unknown direction values pass through.
	if filter.is_empty():
		return true
	if filter.has("phase") and filter.phase != game_state.current_phase:
		return false
	if filter.has("own_turn"):
		var is_own_turn: bool = (game_state.current_player_id == player_id)
		if filter.own_turn != is_own_turn:
			return false
	if filter.has("direction"):
		var dir: String = filter.direction
		if dir == "increase" and new_value <= old_value:
			return false
		if dir == "decrease" and new_value >= old_value:
			return false
	return true


func _build_context(owner_id: int, card_data: Dictionary) -> EffectContext:
	return EffectContext.create(game_state, owner_id, card_data, self)


# --- Active effect tracking (for decision highlighting) ---

func _set_active_effect(player_id: int, card_data: Dictionary) -> void:
	_active_effect_player_id = player_id
	_active_effect_card = card_data


func _clear_active_effect() -> void:
	# Defensive: emit unhighlight when clearing, in case the leaf function that
	# emitted the matching highlight didn't reach its own _unhighlight call.
	# UI side is idempotent — clearing an already-clear highlight is a no-op.
	_unhighlight_active_effect()
	_active_effect_player_id = -1
	_active_effect_card = {}


func _highlight_active_effect() -> void:
	if _active_effect_player_id >= 0:
		var card_id: String = _active_effect_card.get("id", "")
		if not card_id.is_empty():
			effect_card_highlighted.emit(_active_effect_player_id, card_id)


func _unhighlight_active_effect() -> void:
	if _active_effect_player_id >= 0:
		var card_id: String = _active_effect_card.get("id", "")
		if not card_id.is_empty():
			effect_card_unhighlighted.emit(_active_effect_player_id, card_id)


func _get_card_location_label(player_id: int, card_data: Dictionary) -> String:
	## Return a display label like "Card Name (Zone 3)" for standby choice prompts.
	## Uses a temporary marker key to find the exact dictionary reference, since
	## multiple cards can share the same ID (e.g. tokens).
	var player := game_state.players[player_id]
	var card_name: String = card_data.get("name", "Unknown")
	if not player.current_monster.is_empty() and player.current_monster.get("id", "") == card_data.get("id", ""):
		return card_name + " (Monster)"
	var _marker := "__ref_marker"
	card_data[_marker] = true
	for i in range(8):
		var top := player.get_zone_top_card(i)
		if not top.is_empty() and top.has(_marker):
			card_data.erase(_marker)
			return card_name + " (Zone %d)" % (i + 1)
	for i in range(player.strategy_zones.size()):
		if not player.strategy_zones[i].is_empty() and player.strategy_zones[i].has(_marker):
			card_data.erase(_marker)
			return card_name + " (Strategy %d)" % (i + 1)
	for discard_card in player.discard_pile:
		if discard_card.has(_marker):
			card_data.erase(_marker)
			return card_name + " (Discard)"
	card_data.erase(_marker)
	return card_name


func _resolve_standby_entries(entries: Array) -> void:
	## Resolve collected standby automatic abilities per rules 10.4.3 ordering.
	## entries: Array of { "player_id": int, "card_data": Dictionary, "callback": Callable }
	## Turn player's abilities resolve first (10.4.3.2), then non-turn player's (10.4.3.3).
	## Within each player, if multiple abilities are in standby, the player chooses
	## the resolution order (10.6.3.1). Rule actions checked before each ability (10.4.3.1).
	##
	## When a card enters play during standby resolution (via evolution, play_from_discard,
	## etc.), its triggered effects join the pending queue rather than resolving inline.
	## After each batch resolves, pending entries are drained and resolved in a new batch.
	if entries.is_empty():
		return

	# Re-entrancy guard: defer if already in standby resolution OR if an effect
	# callback is actively executing. The second case covers e.g. trigger_enter's
	# direct path, where _in_standby_resolution is false but _active_effect_card
	# is set — without this guard, a trigger called from within that callback
	# would run immediately instead of deferring behind the active effect's enter.
	if _in_standby_resolution or not _active_effect_card.is_empty():
		_pending_standby_entries.append_array(entries)
		return

	_in_standby_resolution = true
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
		await _resolve_player_standby(turn_pid, turn_entries)
		await _resolve_player_standby(1 - turn_pid, non_turn_entries)

		# Drain any entries that accumulated during this batch
		current_entries = _pending_standby_entries
		_pending_standby_entries = []

	_in_standby_resolution = false


func _resolve_player_standby(player_id: int, entries: Array) -> void:
	## Resolve one player's standby abilities, letting them choose order if multiple (10.6.3.1).
	## Playing is compulsory — cannot choose to skip (10.6.3.1).
	while not entries.is_empty():
		# Check rule actions before each ability (10.4.3.1)
		if action_handler:
			await action_handler.resolve_check_timing(game_state)

		var entry: Dictionary
		if entries.size() == 1:
			entry = entries.pop_back()
		else:
			# Multiple abilities in standby — player chooses order (10.6.3.1)
			var options: Array[String] = []
			for e in entries:
				options.append(_get_card_location_label(e.player_id, e.card_data))
			var chosen: int = await select_choice(player_id, options, tr("STR_EFF_CHOOSE_ABILITY"))
			if chosen < 0 or chosen >= entries.size():
				chosen = 0
			entry = entries.pop_at(chosen)

		var saved_player_id: int = _active_effect_player_id
		var saved_card: Dictionary = _active_effect_card
		_set_active_effect(entry.player_id, entry.card_data)
		await entry.callback.call()
		if saved_card.is_empty():
			_clear_active_effect()
		else:
			_set_active_effect(saved_player_id, saved_card)

		# Drain pending entries for this player into the current queue so the
		# player can choose resolution order among them (10.6.3.1).
		# Entries for the other player stay in _pending_standby_entries for the
		# outer _resolve_standby_entries loop to handle.
		var remaining: Array = []
		for p in _pending_standby_entries:
			if p.player_id == player_id:
				entries.append(p)
			else:
				remaining.append(p)
		_pending_standby_entries = remaining


# --- Trigger dispatchers ---

func _passes_enter_filter(card_data: Dictionary) -> bool:
	## Evaluate TRIGGER_FILTERS["on_enter"].
	## "played_from_hand": bool — gate by how the card entered play. true =
	##   only fire when played from hand (matches "if played from hand" rule
	##   text); false = only when entered via an effect (search / evolution /
	##   discard / etc.). Reads `card_data["played_from_effect"]` (set by
	##   trigger_enter) and inverts it for the filter API.
	var filter: Dictionary = get_trigger_filter(card_data, "on_enter")
	if filter.is_empty():
		return true
	if filter.has("played_from_hand"):
		var from_hand: bool = not card_data.get("played_from_effect", false)
		if filter.played_from_hand != from_hand:
			return false
	return true


func trigger_enter(player_id: int, card_data: Dictionary, from_effect: bool = false) -> void:
	## Trigger <Enter> effect on the card that just entered play.
	## If from_effect is true, marks the card so enter effects know it wasn't played from hand.
	## If inside standby resolution, defers the enter to the pending queue (10.4.3).
	if from_effect:
		card_data["played_from_effect"] = true
	if not has_trigger(card_data, "on_enter"):
		return
	if not _passes_enter_filter(card_data):
		return
	var effect := get_effect(card_data)
	if not effect:
		return

	# Defer if inside standby resolution or nested inside another effect's execution.
	# This ensures e.g. multiple evolutions from one effect all complete before any
	# of the evolved cards' enters resolve.
	if _in_standby_resolution or not _active_effect_card.is_empty():
		_pending_standby_entries.append({
			"player_id": player_id,
			"card_data": card_data,
			"callback": effect.on_enter.bind(_build_context(player_id, card_data))
		})
		return

	_set_active_effect(player_id, card_data)
	await effect.on_enter(_build_context(player_id, card_data))
	_clear_active_effect()

	# Drain any entries that accumulated during this enter effect (e.g. from
	# perform_evolution or play_from_discard called within on_enter).
	while not _pending_standby_entries.is_empty():
		var batch: Array = _pending_standby_entries
		_pending_standby_entries = []
		await _resolve_standby_entries(batch)


func trigger_when_invading(player_id: int, from_zone: int, to_zone: int) -> void:
	## Trigger <When Invading> on the current monster card.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		_set_active_effect(player_id, player.current_monster)
		await effect.on_when_invading(_build_context(player_id, player.current_monster), from_zone, to_zone)
		_clear_active_effect()


func collect_when_invading_entries(player_id: int, from_zone: int, to_zone: int) -> Array:
	## Collect <When Invading> entry for deferred resolution after movement completes.
	var entries: Array = []
	var player := game_state.players[player_id]
	if has_trigger(player.current_monster, "on_when_invading"):
		var effect := get_effect(player.current_monster)
		var ctx := _build_context(player_id, player.current_monster)
		# Capture zone state before crush resolves (for effects that check zone occupancy)
		var zone_idx := to_zone - 1
		if zone_idx >= 0 and zone_idx < 8:
			ctx.metadata["zone_had_card"] = player.zone_has_cards(zone_idx)
		entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": effect.on_when_invading.bind(ctx, from_zone, to_zone)})
	return entries


func trigger_crush(player_id: int, card_data: Dictionary) -> void:
	## Trigger crush effect on a card being destroyed by the crush rule.
	var effect := get_effect(card_data)
	if effect:
		var saved_player_id: int = _active_effect_player_id
		var saved_card: Dictionary = _active_effect_card
		_set_active_effect(player_id, card_data)
		await effect.on_crush(_build_context(player_id, card_data))
		if saved_card.is_empty():
			_clear_active_effect()
		else:
			_set_active_effect(saved_player_id, saved_card)


func trigger_revenge(player_id: int, card_data: Dictionary) -> void:
	## Trigger <Revenge> on a card being destroyed by an effect.
	var effect := get_effect(card_data)
	if effect and has_trigger(card_data, "on_revenge"):
		log_message.emit(GameLog.revenge_triggered(player_id, card_data.get("id", "")))
		var saved_player_id: int = _active_effect_player_id
		var saved_card: Dictionary = _active_effect_card
		_set_active_effect(player_id, card_data)
		await effect.on_revenge(_build_context(player_id, card_data))
		if saved_card.is_empty():
			_clear_active_effect()
		else:
			_set_active_effect(saved_player_id, saved_card)


func collect_crush_and_revenge_entries(player_id: int, card_data: Dictionary) -> Array:
	## Collect crush and revenge entries for deferred resolution after movement.
	## These entries use skip_active_check since the card is already in the discard pile.
	## When a card has both on_crush and on_revenge, they are merged into a single entry
	## so the card only appears once in standby choice prompts.
	var entries: Array = []
	var has_crush := has_trigger(card_data, "on_crush")
	var has_revenge := has_trigger(card_data, "on_revenge")
	if has_crush and has_revenge:
		var effect := get_effect(card_data)
		var ctx := _build_context(player_id, card_data)
		var combined_cb := func():
			await effect.on_crush(ctx)
			log_message.emit(GameLog.revenge_triggered(player_id, card_data.get("id", "")))
			await effect.on_revenge(ctx)
		entries.append({"player_id": player_id, "card_data": card_data, "callback": combined_cb, "skip_active_check": true})
	elif has_crush:
		var effect := get_effect(card_data)
		var ctx := _build_context(player_id, card_data)
		entries.append({"player_id": player_id, "card_data": card_data, "callback": effect.on_crush.bind(ctx), "skip_active_check": true})
	elif has_revenge:
		var effect := get_effect(card_data)
		var ctx := _build_context(player_id, card_data)
		var revenge_cb := func():
			log_message.emit(GameLog.revenge_triggered(player_id, card_data.get("id", "")))
			await effect.on_revenge(ctx)
		entries.append({"player_id": player_id, "card_data": card_data, "callback": revenge_cb, "skip_active_check": true})
	return entries


func _passes_discard_from_hand_filter(card_data: Dictionary, player_id: int) -> bool:
	## Evaluate TRIGGER_FILTERS["on_discard_from_hand"] for the discarded card's
	## self-trigger. The discard may happen on either player's turn, so the
	## relevant gate is who *caused* the discard, not whose turn it is.
	## "caused_by_opponent": bool — true = fire only when an opponent effect caused
	##   the discard (e.g. EBP04-046 Rodan); false = fire only when the owner's own
	##   effect caused it. Rules-based discards (no active effect) match neither
	##   value, so the trigger is skipped under either setting.
	## "own_turn": bool — secondary gate by the card owner's turn ownership.
	var filter: Dictionary = get_trigger_filter(card_data, "on_discard_from_hand")
	if filter.is_empty():
		return true
	if filter.has("caused_by_opponent"):
		var by_effect: bool = _active_effect_player_id >= 0
		var caused_by_opponent: bool = by_effect and _active_effect_player_id != player_id
		var caused_by_self: bool = by_effect and _active_effect_player_id == player_id
		if filter.caused_by_opponent and not caused_by_opponent:
			return false
		if not filter.caused_by_opponent and not caused_by_self:
			return false
	if filter.has("own_turn"):
		var is_own_turn: bool = (game_state.current_player_id == player_id)
		if filter.own_turn != is_own_turn:
			return false
	return true


func trigger_discard_from_hand(player_id: int, card_data: Dictionary) -> void:
	## Trigger discard-from-hand effect on the card being discarded.
	if not _passes_discard_from_hand_filter(card_data, player_id):
		return
	var effect := get_effect(card_data)
	if effect:
		var saved_player_id: int = _active_effect_player_id
		var saved_card: Dictionary = _active_effect_card
		_set_active_effect(player_id, card_data)
		await effect.on_discard_from_hand(_build_context(player_id, card_data))
		if saved_card.is_empty():
			_clear_active_effect()
		else:
			_set_active_effect(saved_player_id, saved_card)


func collect_discard_from_hand_entries(player_id: int, card_data: Dictionary) -> Array:
	## Collect discard-from-hand entry for deferred resolution (e.g. during invasion).
	var entries: Array = []
	if has_trigger(card_data, "on_discard_from_hand") and _passes_discard_from_hand_filter(card_data, player_id):
		var effect := get_effect(card_data)
		var ctx := _build_context(player_id, card_data)
		entries.append({"player_id": player_id, "card_data": card_data, "callback": effect.on_discard_from_hand.bind(ctx), "skip_active_check": true})
	return entries


func trigger_hand_cards_discarded_batch(player_id: int, cards: Array) -> void:
	## Standby-resolve on_discard_from_hand and on_hand_card_discarded for a
	## set of cards discarded simultaneously, per rule 10.4.3. Bundling all
	## entries into one batch lets the player choose resolution order when
	## multiple cards trigger at once (e.g. discarding two EBP04-046 Rodans
	## from hand).
	if cards.is_empty():
		return
	var entries: Array = []
	for card in cards:
		entries.append_array(collect_discard_from_hand_entries(player_id, card))
		entries.append_array(collect_hand_card_discarded_entries(player_id, card))
	if not entries.is_empty():
		await _resolve_standby_entries(entries)


func collect_discarded_for_invasion_entries(player_id: int, card_data: Dictionary) -> Array:
	## Collect discarded-for-invasion entry for deferred resolution during invasion.
	## The callback checks on_discarded_for_invasion and plays from discard if true.
	var entries: Array = []
	if has_trigger(card_data, "on_discarded_for_invasion"):
		entries.append({"player_id": player_id, "card_data": card_data, "callback": _resolve_discarded_for_invasion.bind(player_id, card_data), "skip_active_check": true})
	return entries


func _resolve_discarded_for_invasion(player_id: int, card_data: Dictionary) -> void:
	var effect := get_effect(card_data)
	if effect:
		var ctx := _build_context(player_id, card_data)
		if effect.on_discarded_for_invasion(ctx):
			await play_from_discard(player_id, card_data)


func trigger_burst_discard(player_id: int, card_data: Dictionary) -> void:
	## Trigger on_burst_discard on the Burst monster being discarded at end of turn.
	var effect := get_effect(card_data)
	if effect:
		_set_active_effect(player_id, card_data)
		await effect.on_burst_discard(_build_context(player_id, card_data))
		_clear_active_effect()


func trigger_rage_changed(player_id: int, old_rage: int, new_rage: int) -> void:
	## Trigger rage changed on all active cards for this player (monster + zones + strategies).
	## Collects all applicable effects, then resolves with rule action checks between each.
	## Each candidate is gated through TRIGGER_FILTERS (phase / own_turn / direction).
	var entries: Array = []
	var player := game_state.players[player_id]

	# Monster card
	if has_trigger(player.current_monster, "on_rage_changed"):
		var filter := get_trigger_filter(player.current_monster, "on_rage_changed")
		if _passes_trigger_filter(filter, player_id, old_rage, new_rage):
			var me := get_effect(player.current_monster)
			var ctx := _build_context(player_id, player.current_monster)
			entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_rage_changed.bind(ctx, old_rage, new_rage)})

	# Battle cards in zones (top card only — stacked cards are inactive per 12.7.3)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_rage_changed"):
			var filter := get_trigger_filter(zone_card, "on_rage_changed")
			if _passes_trigger_filter(filter, player_id, old_rage, new_rage):
				var ze := get_effect(zone_card)
				var ctx := _build_context(player_id, zone_card)
				entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_rage_changed.bind(ctx, old_rage, new_rage)})

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_rage_changed"):
			var filter := get_trigger_filter(sz_card, "on_rage_changed")
			if _passes_trigger_filter(filter, player_id, old_rage, new_rage):
				var se := get_effect(sz_card)
				var ctx := _build_context(player_id, sz_card)
				entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_rage_changed.bind(ctx, old_rage, new_rage)})

	# Also trigger on_opponent_rage_changed on the OTHER player's cards
	var opp_id: int = 1 - player_id
	var opp := game_state.players[opp_id]
	var opp_entries: Array = []

	if has_trigger(opp.current_monster, "on_opponent_rage_changed"):
		var filter := get_trigger_filter(opp.current_monster, "on_opponent_rage_changed")
		if _passes_trigger_filter(filter, opp_id, old_rage, new_rage):
			var me := get_effect(opp.current_monster)
			var ctx := _build_context(opp_id, opp.current_monster)
			opp_entries.append({"player_id": opp_id, "card_data": opp.current_monster, "callback": me.on_opponent_rage_changed.bind(ctx, old_rage, new_rage)})

	for i in range(8):
		var zone_card := opp.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_opponent_rage_changed"):
			var filter := get_trigger_filter(zone_card, "on_opponent_rage_changed")
			if _passes_trigger_filter(filter, opp_id, old_rage, new_rage):
				var ze := get_effect(zone_card)
				var ctx := _build_context(opp_id, zone_card)
				opp_entries.append({"player_id": opp_id, "card_data": zone_card, "callback": ze.on_opponent_rage_changed.bind(ctx, old_rage, new_rage)})

	for sz_card in opp.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_opponent_rage_changed"):
			var filter := get_trigger_filter(sz_card, "on_opponent_rage_changed")
			if _passes_trigger_filter(filter, opp_id, old_rage, new_rage):
				var se := get_effect(sz_card)
				var ctx := _build_context(opp_id, sz_card)
				opp_entries.append({"player_id": opp_id, "card_data": sz_card, "callback": se.on_opponent_rage_changed.bind(ctx, old_rage, new_rage)})

	entries.append_array(opp_entries)
	await _resolve_standby_entries(entries)


func is_rage_reduction_prevented(player_id: int) -> bool:
	## Check if a player's rage reduction is prevented by any active effect.
	var player := game_state.players[player_id]

	# Check monster card
	var me := get_effect(player.current_monster)
	if me and me.prevents_rage_reduction(_build_context(player_id, player.current_monster)):
		return true

	# Check battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze and ze.prevents_rage_reduction(_build_context(player_id, zone_card)):
				return true

	# Check strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se and se.prevents_rage_reduction(_build_context(player_id, sz_card)):
				return true

	return false


func apply_rage_reset(player_id: int) -> int:
	## Called at start phase rage reset. Returns new rage value (0 by default).
	## Effects can intercept by returning a non-zero value from on_rage_reset.
	var player := game_state.players[player_id]
	var candidates: Array = []
	var me := get_effect(player.current_monster)
	if me and has_trigger(player.current_monster, "on_rage_reset"):
		candidates.append({"card": player.current_monster, "effect": me})
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze and has_trigger(zone_card, "on_rage_reset"):
				candidates.append({"card": zone_card, "effect": ze})
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se and has_trigger(sz_card, "on_rage_reset"):
				candidates.append({"card": sz_card, "effect": se})
	for entry in candidates:
		var ctx := _build_context(player_id, entry.card)
		var result: int = await entry.effect.on_rage_reset(ctx)
		if result != 0:
			return result
	return 0


func reduce_rage(player_id: int, amount: int) -> int:
	## Reduce a player's rage by amount. Returns actual amount reduced.
	## Respects rage reduction prevention effects (e.g. EBP03-004).
	## Populates the player's transient pending_rage_markers bucket with one
	## RAGE-MARKER per point reduced so claiming effects (e.g. EBP04-089) can
	## pop them; whatever isn't claimed is banished after the trigger resolves.
	var player := game_state.players[player_id]
	if not player.has_rage() or amount <= 0:
		return 0
	if is_rage_reduction_prevented(player_id):
		return 0
	var old_rage: int = player.rage
	var actual: int = mini(amount, player.rage)
	player.rage -= actual
	player.rage_changed.emit(player.rage)
	player.push_pending_rage_markers(actual)
	await trigger_rage_changed(player_id, old_rage, player.rage)
	player.pending_rage_markers.clear()
	return actual


func gain_rage(player_id: int, amount: int, source_card_id: String = "") -> int:
	## Increase a player's rage by amount. Returns actual amount gained.
	## Mirror of reduce_rage — handles the old/new rage bookkeeping and trigger dispatch.
	## `source_card_id` (optional) attributes the rage gain to a card in the log.
	if amount <= 0:
		return 0
	var player := game_state.players[player_id]
	var old_rage: int = player.rage
	player.rage += amount
	player.rage_changed.emit(player.rage)
	log_message.emit(GameLog.rage_gained(player_id, amount, player.rage, source_card_id))
	await trigger_rage_changed(player_id, old_rage, player.rage)
	return amount


func trigger_monster_advance(player_id: int, from_zone: int, to_zone: int) -> void:
	## Trigger monster advance on all active cards for this player.
	## Collects all applicable effects, then resolves with rule action checks between each.
	var entries: Array = []
	var player := game_state.players[player_id]

	# Monster card itself
	if has_trigger(player.current_monster, "on_monster_advance"):
		var me := get_effect(player.current_monster)
		var ctx := _build_context(player_id, player.current_monster)
		entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_monster_advance.bind(ctx, from_zone, to_zone)})

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_monster_advance"):
			var ze := get_effect(zone_card)
			var ctx := _build_context(player_id, zone_card)
			entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_monster_advance.bind(ctx, from_zone, to_zone)})

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_monster_advance"):
			var se := get_effect(sz_card)
			var ctx := _build_context(player_id, sz_card)
			entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_monster_advance.bind(ctx, from_zone, to_zone)})

	await _resolve_standby_entries(entries)


func advance_monster_to_zone(player_id: int, target_zone: int) -> void:
	## Advance a player's monster to the target zone one step at a time,
	## crushing battle cards in each intermediate zone (rule 11.3) and
	## collecting on_monster_advance entries per step, resolving them
	## after all movement completes (deferred, like ActionHandler).
	## Effect-driven move — blocked by `prevents_opponent_monster_move`
	## (e.g. EBP04-076 Dormancy when caller is the opponent's effect).
	# Check if monster is blocked from advancing (e.g. Biollante Rose Form)
	if is_monster_advance_blocked(player_id):
		return
	if is_opponent_monster_move_blocked(player_id):
		return
	var player := game_state.players[player_id]
	var deferred_entries: Array = []
	while player.monster_zone < target_zone:
		var from_zone: int = player.monster_zone
		player.monster_zone += 1
		player.monster_changed.emit()
		deferred_entries.append_array(collect_monster_advance_entries(player_id, from_zone, player.monster_zone))
		if action_handler:
			await action_handler.check_crush_rule(game_state, deferred_entries)
	if not deferred_entries.is_empty():
		await resolve_deferred_entries(deferred_entries)


func retreat_monster_to_zone(player_id: int, target_zone: int) -> void:
	## Retreat a player's monster to the target zone one step at a time,
	## crushing battle cards in each intermediate zone (rule 11.3).
	## Retreat does NOT trigger on_monster_advance effects.
	## Crush/revenge effects are deferred until after all movement completes.
	## Effect-driven move — blocked by `prevents_opponent_monster_move`
	## (e.g. EBP04-076 Dormancy when caller is the opponent's effect).
	if is_opponent_monster_move_blocked(player_id):
		return
	var player := game_state.players[player_id]
	var deferred_entries: Array = []
	while player.monster_zone > target_zone:
		player.monster_zone -= 1
		player.monster_changed.emit()
		if action_handler:
			await action_handler.check_crush_rule(game_state, deferred_entries)
	if not deferred_entries.is_empty():
		await resolve_deferred_entries(deferred_entries)


func teleport_monster(player_id: int, target_zone: int) -> bool:
	## Move a player's monster directly to target_zone without crushing
	## intermediate-zone battle cards. Used for "move vertically" effects
	## (e.g. EBP04-078 Crawling Calamity) and the counter-retreat helper.
	## Effect-driven move — blocked by `prevents_opponent_monster_move`
	## (e.g. EBP04-076 Dormancy). Returns true if the move happened.
	if not action_handler:
		return false
	if is_opponent_monster_move_blocked(player_id):
		return false
	var player := game_state.players[player_id]
	if target_zone == player.monster_zone or target_zone < 1 or target_zone > 8:
		return false
	var old_zone: int = player.monster_zone
	player.monster_zone = target_zone
	action_handler.monster_advanced.emit(player_id, old_zone, player.monster_zone)
	player.monster_changed.emit()
	return true


func move_monster_as_countered(player_id: int) -> void:
	## Move a player's monster as though it were countered (rule 5.15.1.1):
	## a single-step teleport to the counter-retreat zone (8→3, 7→4, 6→5).
	## Does NOT crush intermediate zones and does NOT rank up — distinct from
	## retreat_monster_to_zone (which crushes step-by-step) and force_counter
	## (which also forces a rank-up). Used for "moves as though it were
	## countered" rule wording (e.g. EBP01-077 Oxygen Destroyer).
	## Effect-driven move — blocked by `prevents_opponent_monster_move`
	## (e.g. EBP04-076 Dormancy). The counter-immunity branch in
	## resolve_counter is a rule action and bypasses this helper.
	var player := game_state.players[player_id]
	var retreat_zone: int = ActionHandler.get_counter_retreat_zone(player.monster_zone)
	if retreat_zone == player.monster_zone:
		return
	teleport_monster(player_id, retreat_zone)


func collect_monster_advance_entries(player_id: int, from_zone: int, to_zone: int) -> Array:
	## Collect monster advance entries for deferred resolution after movement completes.
	var entries: Array = []
	var player := game_state.players[player_id]

	if has_trigger(player.current_monster, "on_monster_advance"):
		var me := get_effect(player.current_monster)
		var ctx := _build_context(player_id, player.current_monster)
		entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_monster_advance.bind(ctx, from_zone, to_zone)})

	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_monster_advance"):
			var ze := get_effect(zone_card)
			var ctx := _build_context(player_id, zone_card)
			entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_monster_advance.bind(ctx, from_zone, to_zone)})

	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_monster_advance"):
			var se := get_effect(sz_card)
			var ctx := _build_context(player_id, sz_card)
			entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_monster_advance.bind(ctx, from_zone, to_zone)})

	return entries


func trigger_phase_start(phase: CardEnums.GamePhase) -> void:
	## Trigger phase start on all active cards for both players.
	## Per 10.4.3.2-10.4.3.3: turn player's abilities resolve first.
	var entries: Array = []
	for player_id in range(2):
		entries.append_array(_collect_phase_entries(player_id, phase, true))
	await _resolve_standby_entries(entries)


func trigger_phase_end(phase: CardEnums.GamePhase) -> void:
	## Trigger phase end on all active cards for both players.
	## Per 10.4.3.2-10.4.3.3: turn player's abilities resolve first.
	var entries: Array = []
	for player_id in range(2):
		entries.append_array(_collect_phase_entries(player_id, phase, false))
	await _resolve_standby_entries(entries)


func _passes_phase_filter(card_data: Dictionary, method_name: String, player_id: int, phase: CardEnums.GamePhase) -> bool:
	## Check if a card's TRIGGER_FILTERS[method_name] entry matches the given
	## phase and turn ownership. method_name is "on_phase_start" or "on_phase_end".
	var filter: Dictionary = get_trigger_filter(card_data, method_name)
	if filter.is_empty():
		return true
	if filter.has("phase") and filter.phase != phase:
		return false
	if filter.has("own_turn"):
		var is_own_turn: bool = (game_state.current_player_id == player_id)
		if filter.own_turn != is_own_turn:
			return false
	return true


func _collect_phase_entries(player_id: int, phase: CardEnums.GamePhase, is_start: bool) -> Array:
	## Collect standby entries for phase triggers from all active cards of a player.
	## Only includes cards whose effect script overrides the method AND passes the phase filter.
	var entries: Array = []
	var player := game_state.players[player_id]
	var method_name: String = "on_phase_start" if is_start else "on_phase_end"

	# Monster card
	if has_trigger(player.current_monster, method_name):
		var me := get_effect(player.current_monster)
		if _passes_phase_filter(player.current_monster, method_name, player_id, phase):
			var ctx := _build_context(player_id, player.current_monster)
			var method: Callable = me.on_phase_start if is_start else me.on_phase_end
			entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": method.bind(ctx, phase)})

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, method_name):
			var ze := get_effect(zone_card)
			if _passes_phase_filter(zone_card, method_name, player_id, phase):
				var ctx := _build_context(player_id, zone_card)
				var method: Callable = ze.on_phase_start if is_start else ze.on_phase_end
				entries.append({"player_id": player_id, "card_data": zone_card, "callback": method.bind(ctx, phase)})

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, method_name):
			var se := get_effect(sz_card)
			if _passes_phase_filter(sz_card, method_name, player_id, phase):
				var ctx := _build_context(player_id, sz_card)
				var method: Callable = se.on_phase_start if is_start else se.on_phase_end
				entries.append({"player_id": player_id, "card_data": sz_card, "callback": method.bind(ctx, phase)})

	return entries


func _resolve_discard_play(player_id: int, card_data: Dictionary, is_optional: bool) -> void:
	if is_optional:
		var card_name: String = card_data.get("name", "Unknown")
		var options: Array[String] = [tr("STR_EFF_BTN_YES"), tr("STR_EFF_BTN_NO")]
		var chosen: int = await select_choice(player_id, options, tr("STR_EFF_PLAY_FROM_DISCARD_FMT") % card_name)
		if chosen == 1:
			return

	var placed_zone := await play_from_discard(player_id, card_data)
	if placed_zone >= 0:
		await trigger_battle_card_played(player_id, card_data, placed_zone)


func trigger_monster_played(player_id: int, old_monster: Dictionary, new_monster: Dictionary) -> void:
	## Trigger on_monster_played on all active cards for this player.
	## Collects all applicable effects, then resolves with rule action checks between each.
	var entries: Array = []
	var player := game_state.players[player_id]
	var triggered_ids: Array[String] = []

	# Battle cards in zones (top card only)
	# Track triggered IDs because effects can move cards to new zones during iteration.
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_monster_played"):
			var card_id: String = zone_card.get("id", "")
			if card_id in triggered_ids:
				continue
			triggered_ids.append(card_id)
			var ze := get_effect(zone_card)
			var ctx := _build_context(player_id, zone_card)
			entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_monster_played.bind(ctx, old_monster, new_monster)})

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_monster_played"):
			var se := get_effect(sz_card)
			var ctx := _build_context(player_id, sz_card)
			entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_monster_played.bind(ctx, old_monster, new_monster)})

	await _resolve_standby_entries(entries)

	# Check discard pile for cards that can play from discard on monster played.
	# These are treated as normal plays (triggering enter + battle card played),
	# but are NOT considered played from hand.
	# Collected as standby entries so they resolve with proper ordering and rule action checks.
	var discard_entries: Array = []
	var discard_copy: Array[Dictionary] = player.discard_pile.duplicate()
	for discard_card in discard_copy:
		var de := get_effect(discard_card)
		if de:
			var ctx := _build_context(player_id, discard_card)
			if de.can_play_from_discard_on_monster_played(ctx):
				var optional: bool = de.is_discard_play_optional()
				discard_entries.append({"player_id": player_id, "card_data": discard_card, "callback": _resolve_discard_play.bind(player_id, discard_card, optional)})

	await _resolve_standby_entries(discard_entries)


func _passes_battle_card_played_filter(card_data: Dictionary, watcher_player_id: int, played_player_id: int, played_from_deck: bool) -> bool:
	## Evaluate TRIGGER_FILTERS["on_battle_card_played"] for battle-card-played triggers.
	## "own_turn": bool — gate by watcher's turn ownership (false = opponent's turn).
	## "played_by_opponent": bool — gate by who played the card; true = only when
	##                              the watcher's opponent played it. Use this
	##                              instead of own_turn for "your opponent plays..."
	##                              wording, since opponents can play cards on
	##                              your turn via certain effects.
	## "played_from_deck": bool — true = only when the played card came from the deck;
	##                            false = only when NOT from the deck (i.e. from hand/discard).
	var filter: Dictionary = get_trigger_filter(card_data, "on_battle_card_played")
	if filter.is_empty():
		return true
	if filter.has("own_turn"):
		var is_own_turn: bool = (game_state.current_player_id == watcher_player_id)
		if filter.own_turn != is_own_turn:
			return false
	if filter.has("played_by_opponent"):
		var by_opponent: bool = played_player_id != watcher_player_id
		if filter.played_by_opponent != by_opponent:
			return false
	if filter.has("played_from_deck"):
		if filter.played_from_deck != played_from_deck:
			return false
	return true


func trigger_battle_card_played(player_id: int, card_data: Dictionary, zone_index: int, played_from_deck: bool = false) -> void:
	## Trigger on_battle_card_played on all active cards from both players.
	## played_from_deck: true when the card was played directly from the deck (e.g. via a deck-dig effect).
	## Both sides are checked so opponent-watching effects (e.g. EBP04-028 Gigan) fire correctly.
	var entries: Array = []
	var player := game_state.players[player_id]
	var opponent_id: int = 1 - player_id
	var opponent := game_state.players[opponent_id]
	var played_id: String = card_data.get("id", "")

	# Own monster card
	if has_trigger(player.current_monster, "on_battle_card_played"):
		if _passes_battle_card_played_filter(player.current_monster, player_id, player_id, played_from_deck):
			var me := get_effect(player.current_monster)
			var ctx := _build_context(player_id, player.current_monster)
			entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_battle_card_played.bind(ctx, zone_index, played_from_deck)})

	# Own strategy cards (e.g. EBP02-073 Bloody Chainsaw — <Your Turn> effect)
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_battle_card_played"):
			if _passes_battle_card_played_filter(sz_card, player_id, player_id, played_from_deck):
				var se := get_effect(sz_card)
				var ctx := _build_context(player_id, sz_card)
				entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_battle_card_played.bind(ctx, zone_index, played_from_deck)})

	# Own battle cards in zones (top card only, skip the card that was just played)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.get("id", "") != played_id and has_trigger(zone_card, "on_battle_card_played"):
			if _passes_battle_card_played_filter(zone_card, player_id, player_id, played_from_deck):
				var ze := get_effect(zone_card)
				var ctx := _build_context(player_id, zone_card)
				entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_battle_card_played.bind(ctx, zone_index, played_from_deck)})

	# Opponent monster card (e.g. EBP04-028 Gigan — <Opponent's Turn> effect)
	if has_trigger(opponent.current_monster, "on_battle_card_played"):
		if _passes_battle_card_played_filter(opponent.current_monster, opponent_id, player_id, played_from_deck):
			var ome := get_effect(opponent.current_monster)
			var octx := _build_context(opponent_id, opponent.current_monster)
			entries.append({"player_id": opponent_id, "card_data": opponent.current_monster, "callback": ome.on_battle_card_played.bind(octx, zone_index, played_from_deck)})

	# Opponent strategy cards
	for sz_card in opponent.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_battle_card_played"):
			if _passes_battle_card_played_filter(sz_card, opponent_id, player_id, played_from_deck):
				var se := get_effect(sz_card)
				var ctx := _build_context(opponent_id, sz_card)
				entries.append({"player_id": opponent_id, "card_data": sz_card, "callback": se.on_battle_card_played.bind(ctx, zone_index, played_from_deck)})

	# Opponent battle cards in zones (top card only)
	for i in range(8):
		var zone_card := opponent.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_battle_card_played"):
			if _passes_battle_card_played_filter(zone_card, opponent_id, player_id, played_from_deck):
				var ze := get_effect(zone_card)
				var ctx := _build_context(opponent_id, zone_card)
				entries.append({"player_id": opponent_id, "card_data": zone_card, "callback": ze.on_battle_card_played.bind(ctx, zone_index, played_from_deck)})

	await _resolve_standby_entries(entries)


func _passes_hand_discarded_filter(card_data: Dictionary, watcher_player_id: int, discarded_card: Dictionary) -> bool:
	## Evaluate TRIGGER_FILTERS["on_hand_card_discarded"] for hand-discard triggers.
	## "card_type": "battle" | "strategy" | "monster" — discarded card's type must match.
	## "own_turn": bool — gate by watcher's turn ownership (false = opponent's turn).
	var filter: Dictionary = get_trigger_filter(card_data, "on_hand_card_discarded")
	if filter.is_empty():
		return true
	if filter.has("card_type"):
		match String(filter.card_type):
			"battle":
				if not CardUtils.is_battle(discarded_card):
					return false
			"strategy":
				if not CardUtils.is_strategy(discarded_card):
					return false
			"monster":
				if not CardUtils.is_monster(discarded_card):
					return false
	if filter.has("own_turn"):
		var is_own_turn: bool = (game_state.current_player_id == watcher_player_id)
		if filter.own_turn != is_own_turn:
			return false
	return true


func trigger_hand_card_discarded(player_id: int, card_data: Dictionary) -> void:
	## Trigger on ALL active cards when a card is discarded from the owner's hand.
	## Collects all applicable effects, then resolves with rule action checks between each.
	await _resolve_standby_entries(collect_hand_card_discarded_entries(player_id, card_data))


func collect_hand_card_discarded_entries(player_id: int, card_data: Dictionary) -> Array:
	## Collect hand-card-discarded entries for deferred resolution (e.g. during invasion).
	var entries: Array = []
	var player := game_state.players[player_id]

	# Monster card
	if has_trigger(player.current_monster, "on_hand_card_discarded"):
		if _passes_hand_discarded_filter(player.current_monster, player_id, card_data):
			var me := get_effect(player.current_monster)
			var ctx := _build_context(player_id, player.current_monster)
			entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_hand_card_discarded.bind(ctx, card_data)})

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_hand_card_discarded"):
			if _passes_hand_discarded_filter(zone_card, player_id, card_data):
				var ze := get_effect(zone_card)
				var ctx := _build_context(player_id, zone_card)
				entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_hand_card_discarded.bind(ctx, card_data)})

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_hand_card_discarded"):
			if _passes_hand_discarded_filter(sz_card, player_id, card_data):
				var se := get_effect(sz_card)
				var ctx := _build_context(player_id, sz_card)
				entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_hand_card_discarded.bind(ctx, card_data)})

	return entries


func trigger_counter_success(counterer_player_id: int, countered_player_id: int) -> void:
	## Trigger when a counter succeeds (CP >= threat). Collects:
	##   - on_counter_success on all active cards for the counterer (the player whose
	##     CP overcame the opponent's threat — i.e. the turn player in this game)
	##   - on_self_countered on the countered player's monster card (the one whose
	##     monster retreats and ranks up — the opponent in this game)
	## Resolves with rule action checks between each ability.
	var entries: Array = []
	var counterer := game_state.players[counterer_player_id]

	# Counterer side — "When you successfully counter your opponent's monster" cards
	if has_trigger(counterer.current_monster, "on_counter_success"):
		var me := get_effect(counterer.current_monster)
		var ctx := _build_context(counterer_player_id, counterer.current_monster)
		entries.append({"player_id": counterer_player_id, "card_data": counterer.current_monster, "callback": me.on_counter_success.bind(ctx)})

	for i in range(8):
		var zone_card := counterer.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_counter_success"):
			var ze := get_effect(zone_card)
			var ctx := _build_context(counterer_player_id, zone_card)
			entries.append({"player_id": counterer_player_id, "card_data": zone_card, "callback": ze.on_counter_success.bind(ctx)})

	for sz_card in counterer.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_counter_success"):
			var se := get_effect(sz_card)
			var ctx := _build_context(counterer_player_id, sz_card)
			entries.append({"player_id": counterer_player_id, "card_data": sz_card, "callback": se.on_counter_success.bind(ctx)})

	# Countered side — only the monster card itself gets "countered" (battle cards aren't)
	var countered := game_state.players[countered_player_id]
	if has_trigger(countered.current_monster, "on_self_countered"):
		var cme := get_effect(countered.current_monster)
		var cctx := _build_context(countered_player_id, countered.current_monster)
		entries.append({"player_id": countered_player_id, "card_data": countered.current_monster, "callback": cme.on_self_countered.bind(cctx)})

	await _resolve_standby_entries(entries)


func _collect_strategy_discarded_entries_inner(player_id: int, strategy_card: Dictionary) -> Array:
	var entries: Array = []
	var player := game_state.players[player_id]
	var discarded_id: String = strategy_card.get("id", "")

	# Self-trigger: the card being discarded reacts to its own discard.
	# It's already in the discard pile so skip_active_check bypasses the
	# "card still in play" filter on standby resolution.
	if has_trigger(strategy_card, "on_strategy_discarded"):
		var ds := get_effect(strategy_card)
		var dctx := _build_context(player_id, strategy_card)
		entries.append({
			"player_id": player_id,
			"card_data": strategy_card,
			"callback": ds.on_strategy_discarded.bind(dctx, strategy_card),
			"skip_active_check": true,
		})

	# Monster card
	if has_trigger(player.current_monster, "on_strategy_discarded"):
		var me := get_effect(player.current_monster)
		var ctx := _build_context(player_id, player.current_monster)
		entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_strategy_discarded.bind(ctx, strategy_card)})

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_strategy_discarded"):
			var ze := get_effect(zone_card)
			var ctx := _build_context(player_id, zone_card)
			entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_strategy_discarded.bind(ctx, strategy_card)})

	# Strategy cards (skip the just-discarded card; it's already handled by self-trigger)
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("id", "") != discarded_id and has_trigger(sz_card, "on_strategy_discarded"):
			var se := get_effect(sz_card)
			var ctx := _build_context(player_id, sz_card)
			entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_strategy_discarded.bind(ctx, strategy_card)})

	return entries


func trigger_strategy_discarded(player_id: int, strategy_card: Dictionary) -> void:
	## Trigger on the discarded card itself + ALL active cards when a strategy
	## is sent from strategy zone to discard. Collects all applicable effects,
	## then resolves with rule action checks between each.
	await _resolve_standby_entries(_collect_strategy_discarded_entries_inner(player_id, strategy_card))


func collect_strategy_discarded_entries(player_id: int, strategy_card: Dictionary) -> Array:
	## Collect on_strategy_discarded entries for deferred resolution (e.g. during invasion).
	return _collect_strategy_discarded_entries_inner(player_id, strategy_card)


func _passes_invasion_observed_filter(card_data: Dictionary, player_id: int) -> bool:
	## Evaluate TRIGGER_FILTERS["on_invasion_observed"] for an observer card.
	## "own_turn": bool — gate by the watcher's turn ownership.
	var filter: Dictionary = get_trigger_filter(card_data, "on_invasion_observed")
	if filter.is_empty():
		return true
	if filter.has("own_turn"):
		var is_own_turn: bool = (game_state.current_player_id == player_id)
		if filter.own_turn != is_own_turn:
			return false
	return true


func trigger_invasion_observed(invading_player_id: int, from_zone: int, to_zone: int) -> void:
	## Trigger on ALL active cards for BOTH players when a monster invades.
	## Per 10.4.3.2-10.4.3.3: turn player's abilities resolve first.
	## Collects all applicable effects, then resolves with rule action checks between each.
	var entries: Array = []
	for pid in range(2):
		var player := game_state.players[pid]

		# Monster card
		if has_trigger(player.current_monster, "on_invasion_observed") \
				and _passes_invasion_observed_filter(player.current_monster, pid):
			var me := get_effect(player.current_monster)
			var ctx := _build_context(pid, player.current_monster)
			entries.append({"player_id": pid, "card_data": player.current_monster, "callback": me.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

		# Battle cards in zones (top card only)
		for i in range(8):
			var zone_card := player.get_zone_top_card(i)
			if not zone_card.is_empty() and has_trigger(zone_card, "on_invasion_observed") \
					and _passes_invasion_observed_filter(zone_card, pid):
				var ze := get_effect(zone_card)
				var ctx := _build_context(pid, zone_card)
				entries.append({"player_id": pid, "card_data": zone_card, "callback": ze.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

		# Strategy cards
		for sz_card in player.strategy_zones:
			if not sz_card.is_empty() and has_trigger(sz_card, "on_invasion_observed") \
					and _passes_invasion_observed_filter(sz_card, pid):
				var se := get_effect(sz_card)
				var ctx := _build_context(pid, sz_card)
				entries.append({"player_id": pid, "card_data": sz_card, "callback": se.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

	await _resolve_standby_entries(entries)


func collect_invasion_observed_entries(invading_player_id: int, from_zone: int, to_zone: int) -> Array:
	## Collect invasion observed entries for deferred resolution after movement completes.
	var entries: Array = []
	for pid in range(2):
		var player := game_state.players[pid]

		if has_trigger(player.current_monster, "on_invasion_observed") \
				and _passes_invasion_observed_filter(player.current_monster, pid):
			var me := get_effect(player.current_monster)
			var ctx := _build_context(pid, player.current_monster)
			entries.append({"player_id": pid, "card_data": player.current_monster, "callback": me.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

		for i in range(8):
			var zone_card := player.get_zone_top_card(i)
			if not zone_card.is_empty() and has_trigger(zone_card, "on_invasion_observed") \
					and _passes_invasion_observed_filter(zone_card, pid):
				var ze := get_effect(zone_card)
				var ctx := _build_context(pid, zone_card)
				entries.append({"player_id": pid, "card_data": zone_card, "callback": ze.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

		for sz_card in player.strategy_zones:
			if not sz_card.is_empty() and has_trigger(sz_card, "on_invasion_observed") \
					and _passes_invasion_observed_filter(sz_card, pid):
				var se := get_effect(sz_card)
				var ctx := _build_context(pid, sz_card)
				entries.append({"player_id": pid, "card_data": sz_card, "callback": se.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

	return entries


# --- Deferred movement resolution ---

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


func resolve_deferred_entries(entries: Array) -> void:
	## Filter entries for cards still in play after movement, then resolve via standby pattern.
	## Entries with skip_active_check (e.g. on_discard_from_hand) bypass the filter since
	## those cards are in the discard pile, not on the field.
	var active_entries: Array = []
	for entry in entries:
		if entry.get("skip_active_check", false) or is_card_still_active(entry.player_id, entry.card_data):
			active_entries.append(entry)
	await _resolve_standby_entries(active_entries)


# --- Player choice helpers ---

func discard_hand_to(player_id: int, target_count: int) -> void:
	## Force a player to discard cards until they have target_count remaining.
	## If hand_discard_requested is connected (UI present), the player chooses which cards.
	## Otherwise falls back to discarding from the back of hand.
	var player := game_state.players[player_id]
	var to_discard: int = player.hand.size() - target_count
	if to_discard <= 0:
		return

	if hand_discard_requested.get_connections().size() > 0:
		var saved_player_id: int = _active_effect_player_id
		var saved_card_id: String = _active_effect_card.get("id", "")
		_highlight_active_effect()
		hand_discard_requested.emit(player_id, to_discard)
		await _hand_discard_resolved
		if not saved_card_id.is_empty() and saved_player_id >= 0:
			effect_card_unhighlighted.emit(saved_player_id, saved_card_id)
	else:
		# Fallback: discard from back of hand
		var discarded_cards: Array[Dictionary] = []
		for i in range(to_discard):
			if player.hand.is_empty():
				break
			var card: Dictionary = player.hand.pop_back()
			player.discard_pile.append(card)
			discarded_cards.append(card)
		player.hand_changed.emit()
		player.discard_changed.emit()
		await trigger_hand_cards_discarded_batch(player_id, discarded_cards)


func resolve_hand_discard(player_id: int, hand_indices: Array[int]) -> void:
	## Called by the presentation layer after the player selects cards to discard.
	## hand_indices are the indices in the player's hand to discard (sorted descending internally).
	var player := game_state.players[player_id]
	var discarded_cards: Array[Dictionary] = []
	# Sort descending so removing doesn't shift indices
	var sorted_indices := hand_indices.duplicate()
	sorted_indices.sort()
	sorted_indices.reverse()
	for idx in sorted_indices:
		if idx >= 0 and idx < player.hand.size():
			var card: Dictionary = player.hand.pop_at(idx)
			player.discard_pile.append(card)
			discarded_cards.append(card)
	player.hand_changed.emit()
	player.discard_changed.emit()
	# Bundle all simultaneously-discarded triggers into one standby batch so
	# the player can choose resolution order when 2+ cards trigger (10.4.3).
	await trigger_hand_cards_discarded_batch(player_id, discarded_cards)
	_hand_discard_resolved.emit()


func search_deck(player_id: int, filter: Callable, prompt: String, allow_skip: bool = true) -> Dictionary:
	## Search a player's deck for cards matching filter. Shows UI for player choice.
	## Returns the selected card (already removed from deck, deck shuffled).
	## Returns empty dict if no matches found or (when allow_skip) player skips.
	var player := game_state.players[player_id]
	var matching: Array[Dictionary] = []
	for card in player.main_deck:
		if filter.call(card):
			matching.append(card)

	var selected: Dictionary = {}
	if deck_search_requested.get_connections().size() > 0:
		_highlight_active_effect()
		deck_search_requested.emit(player_id, matching, player.main_deck.duplicate(), prompt, allow_skip)
		await _deck_search_resolved
		_unhighlight_active_effect()
		selected = _deck_search_result
	else:
		# Fallback: auto-pick first match
		selected = matching[0]

	if not selected.is_empty():
		# Look up the original card from the deck (the resolved selection may have come
		# through JSON in multiplayer, which converts enums/ints to floats)
		var card_id: String = selected.get("id", "")
		for i in range(player.main_deck.size()):
			if player.main_deck[i].get("id") == card_id:
				selected = player.main_deck[i]
				player.main_deck.remove_at(i)
				break
	player.main_deck.shuffle()
	player.deck_changed.emit()
	return selected


func resolve_deck_search(selected_card: Dictionary) -> void:
	## Called by the presentation layer after the player selects a card from the search.
	_deck_search_result = selected_card
	_deck_search_resolved.emit()


func arrange_deck_cards(player_id: int, cards: Array[Dictionary], prompt: String) -> Dictionary:
	## Present cards to the player for reordering and optional discarding.
	## Returns {"keep": Array[Dictionary], "discard": Array[Dictionary]}.
	## "keep" is ordered: first element = top of deck.
	if cards.is_empty():
		return {"keep": [], "discard": []}

	if deck_arrange_requested.get_connections().size() > 0:
		_highlight_active_effect()
		deck_arrange_requested.emit(player_id, cards, prompt)
		await _deck_arrange_resolved
		_unhighlight_active_effect()
		return {"keep": _deck_arrange_keep, "discard": _deck_arrange_discard}
	else:
		# Fallback: keep all in original order
		return {"keep": cards, "discard": []}


func resolve_deck_arrange(keep: Array[Dictionary], discard: Array[Dictionary]) -> void:
	## Called by the presentation layer after the player arranges cards.
	_deck_arrange_keep = keep
	_deck_arrange_discard = discard
	_deck_arrange_resolved.emit()


func select_cards_from_pool(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int = -1, pool_filter: Callable = Callable()) -> Array[Dictionary]:
	## Ask a player to select between min_count and max_count cards from the matching pool.
	## If max_count == -1, it defaults to min_count (exact count required).
	## pool_filter is an optional Callable(card: Dictionary, selection: Array[Dictionary]) -> bool
	## that dynamically disables pool cards based on the current selection.
	## Player may skip (returns empty array) or must select within the count range to confirm.
	## Returns the selected cards, or empty array if skipped.
	## The caller is responsible for removing selected cards from their source.
	if max_count == -1:
		max_count = min_count
	if matching.size() < min_count:
		return []

	_card_select_pool_filter = pool_filter
	if card_select_requested.get_connections().size() > 0:
		_highlight_active_effect()
		card_select_requested.emit(player_id, matching, all_cards, prompt, min_count, max_count)
		await _card_select_resolved
		_unhighlight_active_effect()
		_card_select_pool_filter = Callable()
		return _card_select_result
	else:
		_card_select_pool_filter = Callable()
		# Fallback: auto-select first N matching
		var result: Array[Dictionary] = []
		for i in range(mini(min_count, matching.size())):
			result.append(matching[i])
		return result


func resolve_card_select(selected: Array[Dictionary]) -> void:
	## Called by the presentation layer after the player selects cards.
	_card_select_result = selected
	_card_select_resolved.emit()


func select_zone_target(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool = false) -> int:
	## Ask a player to choose one of the valid zones on the target player's board.
	## If allow_skip is true, the player can decline (returns -1).
	## Returns the chosen zone index, or -1 if no valid zones or skipped.
	if valid_zones.is_empty():
		return -1

	if zone_target_requested.get_connections().size() > 0:
		_highlight_active_effect()
		zone_target_requested.emit(player_id, target_player_id, valid_zones, prompt, allow_skip)
		await _zone_target_resolved
		_unhighlight_active_effect()
		return _zone_target_result
	else:
		# Fallback: auto-pick first valid zone
		return valid_zones[0]


func resolve_zone_target(zone_index: int) -> void:
	## Called by the presentation layer after the player selects a target zone.
	_zone_target_result = zone_index
	_zone_target_resolved.emit()


func select_strategy_target(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String) -> int:
	## Ask a player to choose one of the valid strategy zones on the target player's board.
	## Always prompts when at least one valid index exists so the player can see
	## which strategy is being targeted (no silent auto-pick on size==1).
	## Returns the chosen strategy index, or -1 if no valid indices.
	if valid_indices.is_empty():
		return -1

	if strategy_target_requested.get_connections().size() > 0:
		_highlight_active_effect()
		strategy_target_requested.emit(player_id, target_player_id, valid_indices, prompt)
		await _strategy_target_resolved
		_unhighlight_active_effect()
		return _strategy_target_result
	else:
		# Fallback (no UI listener, e.g. tests): auto-pick first valid index
		return valid_indices[0]


func resolve_strategy_target(strategy_index: int) -> void:
	## Called by the presentation layer after the player selects a strategy zone.
	_strategy_target_result = strategy_index
	_strategy_target_resolved.emit()


func search_discard(player_id: int, filter: Callable, prompt: String, allow_skip: bool = true) -> Dictionary:
	## Search a player's discard pile for cards matching filter. Shows UI for player choice.
	## Returns the selected card (already removed from discard pile).
	## Returns empty dict if no matches found or (when allow_skip) player skips.
	var player := game_state.players[player_id]
	var matching: Array[Dictionary] = []
	for card in player.discard_pile:
		if filter.call(card):
			matching.append(card)

	# Force skip when nothing is selectable so the player gets feedback that
	# the search ran but found no valid cards (instead of a soft-locked UI
	# with nothing to click).
	var effective_skip: bool = allow_skip or matching.is_empty()

	var selected: Dictionary = {}
	if deck_search_requested.get_connections().size() > 0:
		_highlight_active_effect()
		deck_search_requested.emit(player_id, matching, player.discard_pile.duplicate(), prompt, effective_skip)
		await _deck_search_resolved
		_unhighlight_active_effect()
		selected = _deck_search_result
	elif not matching.is_empty():
		# Fallback: auto-pick first match
		selected = matching[0]

	if not selected.is_empty():
		# Look up the original card from discard pile by ID
		var card_id: String = selected.get("id", "")
		for i in range(player.discard_pile.size()):
			if player.discard_pile[i].get("id") == card_id:
				selected = player.discard_pile[i]
				player.discard_pile.remove_at(i)
				break
	player.discard_changed.emit()
	return selected


func select_hand_card(player_id: int, filter: Callable, prompt: String, allow_skip: bool = false) -> Dictionary:
	## Ask a player to choose a card from their hand matching filter.
	## The selected card is removed from hand and added to discard pile.
	## Returns the selected card, or empty dict if no valid cards or player skips.
	var player := game_state.players[player_id]
	var valid_indices: Array[int] = []
	for i in range(player.hand.size()):
		if filter.call(player.hand[i]):
			valid_indices.append(i)

	if valid_indices.is_empty():
		return {}

	var chosen_index: int = -1
	if hand_card_selection_requested.get_connections().size() > 0:
		_highlight_active_effect()
		hand_card_selection_requested.emit(player_id, valid_indices, prompt, allow_skip)
		await _hand_card_selection_resolved
		_unhighlight_active_effect()
		chosen_index = _hand_card_selection_result
	else:
		# Fallback: auto-pick first valid
		chosen_index = valid_indices[0]

	if chosen_index < 0 or chosen_index >= player.hand.size():
		return {}

	var card: Dictionary = player.hand.pop_at(chosen_index)
	player.discard_pile.append(card)
	player.hand_changed.emit()
	player.discard_changed.emit()
	await trigger_discard_from_hand(player_id, card)
	await trigger_hand_card_discarded(player_id, card)
	return card


func resolve_hand_card_selection(hand_index: int) -> void:
	## Called by the presentation layer after the player selects a card from hand.
	_hand_card_selection_result = hand_index
	_hand_card_selection_resolved.emit()


func select_from_cards(player_id: int, options: Array[Dictionary], all_visible: Array[Dictionary], prompt: String, allow_skip: bool = true) -> Dictionary:
	## Present a set of revealed cards to the player and let them choose one.
	## Uses the deck_search UI but does NOT modify the deck or shuffle.
	## When `allow_skip` is false the player must pick a card unless `options`
	## is empty (then returns {}). Returns the chosen card, or empty dict if
	## no options or (allow_skip) the player skipped.
	if options.is_empty():
		return {}
	if deck_search_requested.get_connections().size() > 0:
		_highlight_active_effect()
		deck_search_requested.emit(player_id, options, all_visible, prompt, allow_skip)
		await _deck_search_resolved
		_unhighlight_active_effect()
		return _deck_search_result
	else:
		return options[0]


func select_choice(player_id: int, options: Array[String], prompt: String) -> int:
	## Present multiple text options to the player and let them choose one.
	## Returns the chosen index (0-based), or 0 as fallback if no UI connected.
	if options.is_empty():
		return -1

	if choice_requested.get_connections().size() > 0:
		_highlight_active_effect()
		choice_requested.emit(player_id, options, prompt)
		await _choice_resolved
		_unhighlight_active_effect()
		return _choice_result
	else:
		# Fallback: auto-pick first option
		return 0


func resolve_choice(index: int) -> void:
	## Called by the presentation layer after the player selects a choice option.
	_choice_result = index
	_choice_resolved.emit()


func reveal_cards(player_id: int, cards: Array[Dictionary], title: String) -> void:
	## Show a set of cards to the player and wait for them to dismiss the overlay.
	if cards.is_empty():
		return
	if cards_revealed_requested.get_connections().size() > 0:
		cards_revealed_requested.emit(player_id, cards, title)
		await _cards_revealed_resolved


func reveal_deck_top(player_id: int, count: int, title_key: String = "STR_EFF_REVEALED_FROM_DECK_TOP") -> Array[Dictionary]:
	## Pop up to `count` cards from the top of the player's deck and present them
	## with a reveal overlay. Returns the popped cards — caller decides disposition
	## (discard, partition, play, etc.).
	var player := game_state.players[player_id]
	var revealed: Array[Dictionary] = []
	for i in range(count):
		if player.main_deck.is_empty():
			break
		revealed.append(player.main_deck.pop_front())
	if revealed.is_empty():
		return revealed
	player.deck_changed.emit()
	await reveal_cards(player_id, revealed, tr(title_key))
	return revealed


func discard_cards(player_id: int, cards: Array[Dictionary]) -> void:
	## Append a batch of cards to the player's discard pile and emit discard_changed.
	## For tokens or mixed batches, use banish_or_discard per-card instead.
	if cards.is_empty():
		return
	var player := game_state.players[player_id]
	for card in cards:
		player.discard_pile.append(card)
	player.discard_changed.emit()


func search_and_discard_deck_top(player_id: int, count: int, filter: Callable, prompt: String) -> Dictionary:
	## Pop up to `count` cards from the top of the player's deck and present them
	## in a search prompt. Filter-matching cards are selectable by default; the
	## non-matching cards are accessible via the "Show All" toggle in the UI so
	## the player can see the full reveal. Everything not picked is discarded.
	## Returns the picked card, or {} if there were no matches or the player skipped.
	var player := game_state.players[player_id]
	var popped: Array[Dictionary] = []
	for _i in range(count):
		if player.main_deck.is_empty():
			break
		popped.append(player.main_deck.pop_front())
	if popped.is_empty():
		return {}
	player.deck_changed.emit()

	var matching: Array[Dictionary] = []
	for card in popped:
		if filter.call(card):
			matching.append(card)

	var picked: Dictionary = await select_from_cards(player_id, matching, popped, prompt)

	var rest: Array[Dictionary] = []
	if picked.is_empty():
		rest = popped
	else:
		# Resolve picked back to the actual popped instance (the result may have
		# been round-tripped through JSON in multiplayer, losing reference identity).
		var picked_id: String = picked.get("id", "")
		var matched_one: bool = false
		for card in popped:
			if not matched_one and card.get("id", "") == picked_id:
				picked = card
				matched_one = true
				continue
			rest.append(card)
	discard_cards(player_id, rest)
	return picked


func resolve_cards_revealed() -> void:
	## Called by the presentation layer when the player dismisses the revealed cards overlay.
	_cards_revealed_resolved.emit()


func perform_evolution(player_id: int, zone_idx: int) -> bool:
	## Perform Evolution on the battle card in the given zone.
	## Reads evolution_rank and evolution_trait from the zone's top card,
	## searches deck for a matching battle card, and stacks it on top.
	## Returns true if evolution occurred.
	var player := game_state.players[player_id]
	var zone_card := player.get_zone_top_card(zone_idx)
	if zone_card.is_empty():
		return false

	var evo_rank: int = zone_card.get("evolution_rank", -1)
	var evo_trait: int = zone_card.get("evolution_trait", -1)
	if evo_rank < 0 or evo_trait < 0:
		return false

	var selected := await search_deck(
		player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.BATTLE:
				return false
			if card.get("rank", 0) > evo_rank:
				return false
			var traits: Array = card.get("traits", [])
			return evo_trait in traits,
		tr("STR_EFF_SEARCH_EVOLVE_FMT") % evo_rank
	)

	if selected.is_empty():
		return false

	# Log the evolution
	log_message.emit(GameLog.evolution(player_id, zone_idx, evo_rank, zone_card.get("id", ""), selected.get("id", "")))

	card_evolved.emit(player_id, selected, zone_idx)
	# Mark as played through evolution for enter effects (e.g. ESD02-010)
	selected["played_through_evolution"] = true
	player.push_zone_card(zone_idx, selected)
	player.zones_changed.emit()
	await trigger_enter(player_id, selected, true)
	# Evolution pulls the card from the deck, so on_battle_card_played fires
	# with played_from_deck=true (e.g. EBP04-028 Gigan, EBP04-072 Sanda).
	await trigger_battle_card_played(player_id, selected, zone_idx, true)
	return true


func evolve_zones_in_order(player_id: int, eligible_zones: Array[int]) -> void:
	## Run perform_evolution over the given eligible zones, prompting the player to
	## choose order whenever 2+ remain. Single-eligible auto-resolves.
	var player := game_state.players[player_id]
	var remaining: Array[int] = eligible_zones.duplicate()
	while not remaining.is_empty():
		var zi: int
		if remaining.size() == 1:
			zi = remaining.pop_back()
		else:
			var options: Array[String] = []
			for ez in remaining:
				var card := player.get_zone_top_card(ez)
				options.append(tr("STR_EFF_ZONE_OPTION_FMT") % [ez + 1, card.get("name", "?")])
			var chosen: int = await select_choice(
				player_id, options, tr("STR_EFF_CHOOSE_EVOLVE_ZONE"))
			zi = remaining.pop_at(chosen)
		await perform_evolution(player_id, zi)


func highlight_zone_card(player_id: int, zone_index: int) -> void:
	## Highlight a zone's card to show its effect is being resolved.
	effect_zone_highlighted.emit(player_id, zone_index)


func unhighlight_zone_card(player_id: int, zone_index: int) -> void:
	## Remove highlight from a zone's card after effect resolution.
	effect_zone_unhighlighted.emit(player_id, zone_index)


func trigger_leave_play(player_id: int, leaving_card: Dictionary, zone_index: int) -> void:
	## Fire on_leave_play for a card that just left a zone for any reason
	## (destroyed, overloaded, banished, returned to hand/deck). Distinct from
	## on_destroy/on_revenge, which only fire for <Destroy> actions per the
	## rules. Used by linked-card effects (e.g. EBP04-067 ↔ token).
	if leaving_card.is_empty():
		return
	if not has_trigger(leaving_card, "on_leave_play"):
		return
	var effect := get_effect(leaving_card)
	if effect:
		await effect.on_leave_play(_build_context(player_id, leaving_card), zone_index)


static func banish_or_discard(player: PlayerState, stack: Array) -> void:
	## Route cards to banishment (tokens) or discard pile (non-tokens).
	## Tokens are removed from the game entirely; non-tokens go to discard pile.
	for card in stack:
		if not PlayerState.is_token(card):
			player.discard_pile.append(card)


func destroy_zone_target(player_id: int, target: PlayerState, filter: Callable, prompt: String) -> Dictionary:
	## Let a player choose one of the target player's battle cards matching filter to destroy.
	## filter receives (card_data: Dictionary) -> bool for each zone's top card.
	## Respects can_be_destroyed and on_would_be_destroyed replacement effects.
	## Returns the destroyed card data, or empty dict if nothing was destroyed.
	var valid_zones: Array[int] = []
	for i in range(8):
		var zone_card := target.get_zone_top_card(i)
		if not zone_card.is_empty() and filter.call(zone_card):
			# Check destroy prevention
			if not _can_destroy_card(target, zone_card):
				continue
			valid_zones.append(i)

	if valid_zones.is_empty():
		return {}

	var chosen: int = await select_zone_target(player_id, target.player_id, valid_zones, prompt)
	if chosen < 0:
		return {}

	var zone_card := target.get_zone_top_card(chosen)
	if zone_card.is_empty():
		return {}

	return await _execute_destroy_zone(target, chosen, zone_card)


func destroy_chosen_zone(player_id: int, target: PlayerState, valid_zones: Array[int], prompt: String) -> Dictionary:
	## Let a player choose one zone from a pre-computed list to destroy.
	## Like destroy_zone_target but with pre-computed valid zones instead of a filter.
	## Respects can_be_destroyed and on_would_be_destroyed replacement effects.
	## Returns the destroyed card data, or empty dict if nothing was destroyed.
	var destroyable: Array[int] = []
	for zi in valid_zones:
		if zi < 0 or zi >= 8 or not target.zone_has_cards(zi):
			continue
		var top_card := target.get_zone_top_card(zi)
		if _can_destroy_card(target, top_card):
			destroyable.append(zi)

	if destroyable.is_empty():
		return {}

	var chosen: int = await select_zone_target(player_id, target.player_id, destroyable, prompt)
	if chosen < 0:
		return {}

	var zone_card := target.get_zone_top_card(chosen)
	if zone_card.is_empty():
		return {}

	return await _execute_destroy_zone(target, chosen, zone_card)


func destroy_zones(target: PlayerState, zone_indices: Array[int]) -> Array[Dictionary]:
	## Destroy all occupied zones in the given list on the target player's board.
	## Respects can_be_destroyed and on_would_be_destroyed replacement effects.
	## Returns an array of the destroyed top cards.
	## Revenge triggers are collected as standby entries and resolved after all
	## zones are destroyed, per rules 10.4.3.
	var destroyed: Array[Dictionary] = []
	var deferred: Array = []
	for zi in zone_indices:
		if zi < 0 or zi >= 8 or not target.zone_has_cards(zi):
			continue
		var top_card := target.get_zone_top_card(zi)
		if not _can_destroy_card(target, top_card):
			continue
		var result: Dictionary = await _execute_destroy_zone(target, zi, top_card, deferred)
		if not result.is_empty():
			destroyed.append(result)

	if not destroyed.is_empty():
		target.zones_changed.emit()
		target.discard_changed.emit()
	if not deferred.is_empty():
		await resolve_deferred_entries(deferred)
	return destroyed


func destroy_zone_and_adjacent(player_id: int, target: PlayerState, valid_zones: Array[int], prompt: String, max_rank: int = -1) -> Array[Dictionary]:
	## Let a player choose a zone, then destroy all battle cards in that zone and adjacent zones.
	## If max_rank > 0, only cards with rank <= max_rank are destroyed.
	## valid_zones controls which zones can be chosen (e.g. all 8, or column-restricted).
	## Returns the array of destroyed card data.
	if valid_zones.is_empty():
		return []

	pending_destroy_max_rank = max_rank
	var chosen: int = await select_zone_target(player_id, target.player_id, valid_zones, prompt)
	pending_destroy_max_rank = -1
	if chosen < 0:
		return []

	var affected: Array[int] = [chosen]
	for adj in CardEffect.get_adjacent_zones(chosen):
		if adj not in affected:
			affected.append(adj)

	if max_rank > 0:
		var filtered: Array[int] = []
		for zi in affected:
			var card := target.get_zone_top_card(zi)
			if not card.is_empty() and get_effective_field_rank(card, target.player_id) <= max_rank:
				filtered.append(zi)
		return await destroy_zones(target, filtered)
	else:
		return await destroy_zones(target, affected)


func can_destroy_card(target: PlayerState, card_data: Dictionary) -> bool:
	return _can_destroy_card(target, card_data)


func _can_destroy_card(target: PlayerState, card_data: Dictionary) -> bool:
	## Check if a card can be destroyed (respects destroy prevention effects).
	## Scans the owner's monster, battle zones, and strategy zones for any
	## active card whose `protects_card_from_destruction` returns true.
	## `card_data` may be a battle card (zone_idx 0-7) or a strategy card
	## (zone_idx -1 since strategies don't sit in numbered zones).
	var effect := get_effect(card_data)
	if effect and not effect.can_be_destroyed(_build_context(target.player_id, card_data)):
		return false

	var card_id: String = card_data.get("id", "")
	var zone_idx: int = -1
	for i in range(8):
		if target.get_zone_top_card(i).get("id", "") == card_id:
			zone_idx = i
			break

	if not target.current_monster.is_empty():
		var m_effect := get_effect(target.current_monster)
		if m_effect and m_effect.protects_card_from_destruction(
				_build_context(target.player_id, target.current_monster), card_data, zone_idx):
			return false
	for i in range(8):
		var zc := target.get_zone_top_card(i)
		if not zc.is_empty():
			var ze := get_effect(zc)
			if ze and ze.protects_card_from_destruction(
					_build_context(target.player_id, zc), card_data, zone_idx):
				return false
	for sz_card in target.strategy_zones:
		if not sz_card.is_empty():
			var sz_effect := get_effect(sz_card)
			if sz_effect and sz_effect.protects_card_from_destruction(
					_build_context(target.player_id, sz_card), card_data, zone_idx):
				return false
	return true


func _execute_destroy_zone(target: PlayerState, zone_idx: int, top_card: Dictionary, deferred_entries: Variant = null) -> Dictionary:
	## Execute destruction of a single zone, handling replacement effects.
	## When deferred_entries is provided, revenge triggers are collected there
	## instead of resolving immediately (used when destroying multiple zones).
	## Returns the destroyed/replaced card, or empty dict on failure.
	var effect := get_effect(top_card)
	if effect and effect.on_would_be_destroyed(_build_context(target.player_id, top_card)):
		# Replacement: move to deck bottom instead of discard (skip revenge)
		var replaced_stack: Array = target.clear_zone(zone_idx)
		if replaced_stack.size() > 1:
			banish_or_discard(target, replaced_stack.slice(1))
		target.main_deck.append(top_card)
		target.zones_changed.emit()
		target.deck_changed.emit()
		target.discard_changed.emit()
		_log_destroy(target.player_id, zone_idx, top_card)
		card_destroyed.emit(target.player_id, zone_idx)
		return top_card

	var stack: Array = target.clear_zone(zone_idx)
	banish_or_discard(target, stack)
	target.zones_changed.emit()
	target.discard_changed.emit()
	target.cards_destroyed_this_turn.append(top_card)
	_log_destroy(target.player_id, zone_idx, top_card)
	card_destroyed.emit(target.player_id, zone_idx)
	if has_trigger(top_card, "on_destroy"):
		var d_effect := get_effect(top_card)
		await d_effect.on_destroy(_build_context(target.player_id, top_card), zone_idx)
	# Destroy is one way to leave play — fire the generic hook for linked-card
	# effects that don't care whether removal was via <Destroy> or overload.
	await trigger_leave_play(target.player_id, top_card, zone_idx)
	if deferred_entries != null:
		if has_trigger(top_card, "on_revenge"):
			var rev_effect := get_effect(top_card)
			var ctx := _build_context(target.player_id, top_card)
			var revenge_cb := func():
				log_message.emit(GameLog.revenge_triggered(target.player_id, top_card.get("id", "")))
				await rev_effect.on_revenge(ctx)
			deferred_entries.append({"player_id": target.player_id, "card_data": top_card, "callback": revenge_cb, "skip_active_check": true})
		deferred_entries.append_array(collect_ally_zone_card_destroyed_entries(target.player_id, top_card, zone_idx))
		deferred_entries.append_array(collect_opponent_zone_card_destroyed_entries(target.player_id, top_card, zone_idx))
	else:
		await trigger_revenge(target.player_id, top_card)
		await trigger_ally_zone_card_destroyed(target.player_id, top_card, zone_idx)
		await trigger_opponent_zone_card_destroyed(target.player_id, top_card, zone_idx)
	return top_card


func _log_destroy(target_player_id: int, zone_idx: int, destroyed_card: Dictionary) -> void:
	if not _active_effect_card.is_empty():
		log_message.emit(GameLog.effect_destroyed_card(
			_active_effect_player_id, _active_effect_card.get("id", ""),
			target_player_id, zone_idx, destroyed_card.get("id", "")
		))


func create_token_in_zone(player: PlayerState, token_id: String, zone_index: int) -> bool:
	## Create a token from CardData template and place it in the given zone.
	## Handles overload if zone is occupied. Returns true if token was placed.
	var token_data: Dictionary = CardData.get_card_by_id(token_id)
	if token_data.is_empty():
		push_warning("EffectHandler: Token not found: %s" % token_id)
		return false

	# Make a copy so each token instance is independent
	token_data = token_data.duplicate()

	var overloaded_top: Dictionary = {}
	if player.zone_has_cards(zone_index):
		overloaded_top = player.get_zone_top_card(zone_index)
		var destroyed_stack: Array = player.clear_zone(zone_index)
		banish_or_discard(player, destroyed_stack)
		player.discard_changed.emit()

	player.push_zone_card(zone_index, token_data)
	player.zones_changed.emit()
	await trigger_leave_play(player.player_id, overloaded_top, zone_index)
	await trigger_enter(player.player_id, token_data, true)
	# Tokens are treated as normal plays — trigger battle card played effects
	# (but not considered played from hand).
	if token_data.get("card_type") == CardEnums.CardType.BATTLE:
		await trigger_battle_card_played(player.player_id, token_data, zone_index)
	return true


func create_tokens_in_zones(player: PlayerState, token_id: String, count: int) -> int:
	## Let the player select zones to place up to count tokens.
	## Tokens can overload occupied zones. When placing multiple tokens from
	## one effect, each must go to a different zone.
	## Returns the number of tokens actually placed.
	var placed: int = 0
	var used_zones: Array[int] = []
	for _i in range(count):
		var valid: Array[int] = []
		for i in range(8):
			if i == player.monster_zone - 1:
				continue
			if i in used_zones:
				continue
			valid.append(i)
		if valid.is_empty():
			break
		var chosen: int = await select_zone_target(
			player.player_id, player.player_id, valid,
			tr("STR_EFF_TOKEN_ZONE_FMT") % (count - placed))
		if chosen < 0:
			break
		used_zones.append(chosen)
		if await create_token_in_zone(player, token_id, chosen):
			placed += 1
	return placed


func return_to_deck_bottom(player: PlayerState, card_data: Dictionary) -> void:
	## Move a card from discard pile to the bottom of the player's deck.
	## Used by cards with "place on bottom of deck instead of discard" effects.
	var card_id: String = card_data.get("id", "")
	for i in range(player.discard_pile.size() - 1, -1, -1):
		if player.discard_pile[i].get("id", "") == card_id:
			var card: Dictionary = player.discard_pile.pop_at(i)
			player.main_deck.append(card)
			player.deck_changed.emit()
			player.discard_changed.emit()
			return


func move_zone_card_to_deck_bottom(player: PlayerState, card_data: Dictionary) -> void:
	## Move a card from its zone to the bottom of the player's deck.
	## Finds the zone containing the card, removes it, and appends to deck.
	var card_id: String = card_data.get("id", "")
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if zone_card.get("id", "") == card_id:
			var stack: Array = player.clear_zone(i)
			if not stack.is_empty():
				player.main_deck.append(stack[0])
				# Place any cards under it into discard
				for j in range(1, stack.size()):
					EffectHandler.banish_or_discard(player, [stack[j]])
			player.zones_changed.emit()
			player.deck_changed.emit()
			return


func apply_play_cost(player_id: int, card_data: Dictionary, zone_index: int) -> bool:
	## Call the card's apply_play_cost hook. Returns true if play should proceed.
	var effect := get_effect(card_data)
	if not effect:
		return true
	if not has_trigger(card_data, "apply_play_cost"):
		return true
	var ctx := _build_context(player_id, card_data)
	return await effect.apply_play_cost(ctx, zone_index)


func can_monster_be_played_from_hand(player_id: int, card_data: Dictionary) -> bool:
	## Check if a monster card can be played via an alternate play cost.
	var effect := get_effect(card_data)
	if not effect or not has_trigger(card_data, "can_play_as_monster"):
		return false
	var ctx := _build_context(player_id, card_data)
	return effect.can_play_as_monster(ctx)


# --- Modifier queries ---

func get_counter_power_modifier(player_id: int) -> int:
	## Get total counter power modifier from all active effects (monster, zones + strategies).
	var total: int = 0
	var per_zone := get_zone_cp_modifiers(player_id)
	for mod in per_zone:
		total += mod

	total += get_monster_cp_modifier(player_id)

	# Strategy card flat CP modifiers (e.g. EBP02-017)
	var player := game_state.players[player_id]
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var effect := get_effect(sz_card)
			if effect:
				total += effect.get_total_cp_modifier(_build_context(player_id, sz_card))

	return total


func get_monster_cp_modifier(player_id: int) -> int:
	## Get counter power modifier from the active monster card effect (e.g. EFC01-001).
	var player := game_state.players[player_id]
	var monster_effect := get_effect(player.current_monster)
	if monster_effect:
		return monster_effect.get_counter_power_modifier(_build_context(player_id, player.current_monster))
	return 0


func get_strategy_cp_modifiers(player_id: int) -> Array[int]:
	## Get per-strategy-slot total CP modifiers from strategy card effects.
	var player := game_state.players[player_id]
	var modifiers: Array[int] = []
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var effect := get_effect(sz_card)
			if effect:
				modifiers.append(effect.get_total_cp_modifier(_build_context(player_id, sz_card)))
			else:
				modifiers.append(0)
		else:
			modifiers.append(0)
	return modifiers


func get_zone_cp_modifiers(player_id: int) -> Array[int]:
	## Get per-zone counter power modifiers from battle card effects.
	var player := game_state.players[player_id]
	var modifiers: Array[int] = []
	modifiers.resize(8)
	modifiers.fill(0)

	# Get engagement restrictions from opponent's monster
	var opponent_id: int = 1 - player_id
	var max_restricted_rank: int = get_engagement_restriction(opponent_id)

	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect:
				var ctx := _build_context(player_id, zone_card)
				var can_card_engage := effect.can_engage(ctx)
				# Check engagement restriction from opponent's monster
				if can_card_engage and max_restricted_rank >= 0:
					var card_rank: int = get_effective_field_rank(zone_card, player_id)
					if card_rank > 0 and card_rank <= max_restricted_rank:
						can_card_engage = false
				if can_card_engage:
					modifiers[i] += effect.get_counter_power_modifier(ctx)
				# Collect field modifiers (bonuses this card grants to other zones)
				var field_mods: Dictionary = effect.get_field_cp_modifiers(ctx)
				for zone_idx in field_mods:
					if zone_idx >= 0 and zone_idx < 8:
						modifiers[zone_idx] += field_mods[zone_idx]

	# Monster card field CP modifiers (e.g. EBP02-021, 041, 043)
	var monster_effect := get_effect(player.current_monster)
	if monster_effect:
		var monster_ctx := _build_context(player_id, player.current_monster)
		var monster_field_mods: Dictionary = monster_effect.get_field_cp_modifiers(monster_ctx)
		for zone_idx in monster_field_mods:
			if zone_idx >= 0 and zone_idx < 8:
				modifiers[zone_idx] += monster_field_mods[zone_idx]

	# Strategy card field CP modifiers (e.g. EBP04-082 X-Aliens' Mother Ship)
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		var sz_effect := get_effect(sz_card)
		if sz_effect == null:
			continue
		var sz_ctx := _build_context(player_id, sz_card)
		var sz_field_mods: Dictionary = sz_effect.get_field_cp_modifiers(sz_ctx)
		for zone_idx in sz_field_mods:
			if zone_idx >= 0 and zone_idx < 8:
				modifiers[zone_idx] += sz_field_mods[zone_idx]

	# Opponent's monster CP modifiers that affect this player's zones —
	# additive bonuses first, then doubling (so the doubling sees base + all
	# other modifiers and doubles the running total, not just base CP).
	var opp_monster_effect := get_effect(game_state.players[opponent_id].current_monster)
	if opp_monster_effect:
		var opp_ctx := _build_context(opponent_id, game_state.players[opponent_id].current_monster)
		var opp_mods: Dictionary = opp_monster_effect.get_opponent_zone_cp_modifiers(opp_ctx)
		for zone_idx in opp_mods:
			if zone_idx >= 0 and zone_idx < 8:
				modifiers[zone_idx] += opp_mods[zone_idx]
		var doubled_zones: Array[int] = opp_monster_effect.get_opponent_doubled_zones(opp_ctx)
		for zone_idx in doubled_zones:
			if zone_idx >= 0 and zone_idx < 8:
				var base_cp: int = player.get_zone_top_card(zone_idx).get("counter_power", 0)
				# Doubling total = 2 * (base + mod). Add the existing total to
				# turn modifier into base + 2 * modifier.
				modifiers[zone_idx] += base_cp + modifiers[zone_idx]

	return modifiers


func get_threat_level_modifier(player_id: int) -> int:
	## Get threat level modifier from all active effects (monster, zones, strategies).
	var total: int = 0
	var player := game_state.players[player_id]

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		total += me.get_threat_level_modifier(_build_context(player_id, player.current_monster))

	# Battle cards in zones (e.g. Crystal tokens grant +1000 TL)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				total += ze.get_threat_level_modifier(_build_context(player_id, zone_card))

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				total += se.get_threat_level_modifier(_build_context(player_id, sz_card))

	return total


func get_effective_threat_level(player_id: int) -> int:
	## Get the full effective threat level including base, rage, and all effect modifiers.
	var player := game_state.players[player_id]
	return player.get_threat_level() + get_threat_level_modifier(player_id)


func get_play_rank_modifier(player_id: int, card: Dictionary) -> int:
	## Get total play rank modifier for a card being played from hand.
	## Checks the card's own effect (self-modifier) and active strategy cards.
	var total: int = 0
	var player := game_state.players[player_id]

	# Check the card's own effect (self-modifier, e.g. EBP02-068)
	var card_effect := get_effect(card)
	if card_effect:
		var ctx := _build_context(player_id, card)
		# If the card uses zone stacking, its rank modifier is zone-specific
		# and handled by get_zone_play_rank_modifier instead of here.
		var uses_stacking := false
		for zi in range(8):
			if card_effect.stacks_on_play(ctx, zi):
				uses_stacking = true
				break
		if not uses_stacking:
			total += card_effect.get_play_rank_modifier_for_card(ctx, card)

	# Check active strategy cards (e.g. EBP02-039)
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var effect := get_effect(sz_card)
			if effect:
				total += effect.get_play_rank_modifier_for_card(_build_context(player_id, sz_card), card)

	return total


func should_stack_on_play(player_id: int, card: Dictionary, zone_index: int) -> bool:
	## Check if the card being played should stack on top of the existing zone card
	## instead of destroying it (overload).
	var effect := get_effect(card)
	if effect:
		return effect.stacks_on_play(_build_context(player_id, card), zone_index)
	return false


func get_zone_play_rank_modifier(player_id: int, card: Dictionary, zone_index: int) -> int:
	## Get zone-specific rank modifier for a card being played into a specific zone.
	var effect := get_effect(card)
	if not effect:
		return 0
	var ctx := _build_context(player_id, card)
	var zone_mod: int = effect.get_zone_play_rank_modifier(ctx, zone_index)
	# If the card stacks at this zone but no zone-specific modifier was returned,
	# fall back to the card's global self-modifier (handles stale script caches).
	if zone_mod == 0 and effect.stacks_on_play(ctx, zone_index):
		zone_mod = effect.get_play_rank_modifier_for_card(ctx, card)
	return zone_mod


func is_invasion_blocked(defender_player_id: int) -> bool:
	## Check if any of the defender's battle cards prevent the opponent from invading.
	var player := game_state.players[defender_player_id]
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect:
				var ctx := _build_context(defender_player_id, zone_card)
				if effect.prevents_opponent_invasion(ctx):
					return true
	return false


func get_engagement_restriction(attacker_player_id: int) -> int:
	## Get the engagement restriction from the attacker's monster and strategy effects.
	## Returns the max rank of opponent battle cards that cannot engage (-1 = no restriction).
	## If multiple sources restrict, the highest restriction wins.
	var player := game_state.players[attacker_player_id]
	var max_rank: int = -1

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		var r: int = me.get_engagement_restriction(_build_context(attacker_player_id, player.current_monster))
		if r > max_rank:
			max_rank = r

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				var r: int = se.get_engagement_restriction(_build_context(attacker_player_id, sz_card))
				if r > max_rank:
					max_rank = r

	return max_rank


func get_engagement_restricted_cp(defender_player_id: int) -> int:
	## Get the total base CP of the defender's cards that are restricted from engaging
	## by the attacker's monster effect. This amount should be subtracted from total CP.
	var attacker_id: int = 1 - defender_player_id
	var max_restricted_rank: int = get_engagement_restriction(attacker_id)
	if max_restricted_rank < 0:
		return 0
	var total_restricted: int = 0
	var defender := game_state.players[defender_player_id]
	for i in range(8):
		var zone_card := defender.get_zone_top_card(i)
		if not zone_card.is_empty():
			var card_rank: int = get_effective_field_rank(zone_card, defender_player_id)
			if card_rank > 0 and card_rank <= max_restricted_rank:
				total_restricted += zone_card.get("counter_power", 0)
	return total_restricted


func get_cards_that_can_engage(player_id: int) -> Array[int]:
	## Return zone indices of battle cards that can engage (not blocked by "cannot engage" effects
	## or engagement restrictions from the opponent's monster).
	## Used during counter phase to filter out restricted cards.
	var player := game_state.players[player_id]
	var opponent_id: int = 1 - player_id
	var max_restricted_rank: int = get_engagement_restriction(opponent_id)
	var engageable: Array[int] = []
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			# Check engagement restriction from opponent's monster
			if max_restricted_rank >= 0:
				var card_rank: int = get_effective_field_rank(zone_card, player_id)
				if card_rank > 0 and card_rank <= max_restricted_rank:
					continue
			var effect := get_effect(zone_card)
			if effect:
				if effect.can_engage(_build_context(player_id, zone_card)):
					engageable.append(i)
			else:
				engageable.append(i)
	return engageable


func get_opponent_blocked_zones(blocker_player_id: int) -> Array[int]:
	## Collect all opponent zone indices that the blocker's cards prevent placement in.
	## Queries monster card for get_blocked_opponent_zones().
	var player := game_state.players[blocker_player_id]
	var blocked: Array[int] = []

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		var monster_blocked: Array[int] = me.get_blocked_opponent_zones(_build_context(blocker_player_id, player.current_monster))
		for z in monster_blocked:
			if z not in blocked:
				blocked.append(z)

	# Zone cards
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				var zone_blocked: Array[int] = ze.get_blocked_opponent_zones(_build_context(blocker_player_id, zone_card))
				for z in zone_blocked:
					if z not in blocked:
						blocked.append(z)

	return blocked


func get_extra_end_phase_advance(player_id: int) -> int:
	## Get extra end phase advance zones from the current monster's effect.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.get_extra_end_phase_advance(_build_context(player_id, player.current_monster))
	return 0


func get_invasion_advance_bonus(player_id: int, invasion_icon: int) -> int:
	## Get extra invasion advance zones from the current monster's effect.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.get_invasion_advance_bonus(_build_context(player_id, player.current_monster), invasion_icon)
	return 0


func can_play_as_monster(player_id: int, card: Dictionary) -> bool:
	## Query a monster card's alternate play cost (e.g. EBP04-033/034 "play on top of Monster X").
	## Used by ActionHandler._rank_up_monster to bridge non-overlapping traits when an
	## alternate play condition is satisfied.
	var effect := get_effect(card)
	if effect == null:
		return false
	return effect.can_play_as_monster(_build_context(player_id, card))


func _passes_own_turn_filter(card_data: Dictionary, method_name: String, watcher_player_id: int) -> bool:
	## Generic own-turn filter check for query-style virtuals
	## (can_monster_advance / can_monster_invade). Empty/missing filter = pass.
	var filter: Dictionary = get_trigger_filter(card_data, method_name)
	if filter.is_empty():
		return true
	if filter.has("own_turn"):
		var is_own_turn: bool = (game_state.current_player_id == watcher_player_id)
		if filter.own_turn != is_own_turn:
			return false
	return true


func is_monster_advance_blocked(player_id: int) -> bool:
	## Check if the player's monster cannot advance. Queries the monster card
	## itself plus all active strategy cards (any can override
	## `can_monster_advance` to return false). TRIGGER_FILTERS supports
	## `own_turn` for turn-gated overrides.
	var player := game_state.players[player_id]
	if not player.current_monster.is_empty() \
			and _passes_own_turn_filter(player.current_monster, "can_monster_advance", player_id):
		var effect := get_effect(player.current_monster)
		if effect and not effect.can_monster_advance(_build_context(player_id, player.current_monster)):
			return true
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		if not _passes_own_turn_filter(sz_card, "can_monster_advance", player_id):
			continue
		var se := get_effect(sz_card)
		if se and not se.can_monster_advance(_build_context(player_id, sz_card)):
			return true
	return false


func is_own_invasion_blocked(player_id: int) -> bool:
	## Check if the player's monster cannot invade. Queries the monster card
	## itself plus all active strategy cards (any can override
	## `can_monster_invade` to return false). TRIGGER_FILTERS supports
	## `own_turn` for turn-gated overrides.
	var player := game_state.players[player_id]
	if not player.current_monster.is_empty() \
			and _passes_own_turn_filter(player.current_monster, "can_monster_invade", player_id):
		var effect := get_effect(player.current_monster)
		if effect and not effect.can_monster_invade(_build_context(player_id, player.current_monster)):
			return true
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		if not _passes_own_turn_filter(sz_card, "can_monster_invade", player_id):
			continue
		var se := get_effect(sz_card)
		if se and not se.can_monster_invade(_build_context(player_id, sz_card)):
			return true
	return false


func can_replace_invasion_cost(player_id: int) -> bool:
	## Check if the current monster can replace the invasion hand-discard cost
	## with an alternative (e.g. milling from deck).
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.can_replace_invasion_cost(_build_context(player_id, player.current_monster))
	return false


func get_counter_immunity_threshold(player_id: int) -> int:
	## Get the counter immunity threshold from the player's monster and strategy cards.
	## If defender's CP <= this value, monster retreats without rank up.
	## Returns the highest threshold found across monster + strategy effects.
	var player := game_state.players[player_id]
	var best: int = 0
	var effect := get_effect(player.current_monster)
	if effect:
		best = effect.get_counter_immunity_threshold(_build_context(player_id, player.current_monster))
	# Strategy card counter immunity (e.g. EBP01-066)
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				var val: int = se.get_counter_immunity_threshold(_build_context(player_id, sz_card))
				if val > best:
					best = val
	return best


func is_counter_prevented(player_id: int, total_cp: int) -> bool:
	## Returns true if the invader (player_id) has any effect fully preventing
	## the counter — counter doesn't happen at all (no retreat, no rank up).
	## `total_cp` is the defender's effective CP so effects can gate prevention
	## on a CP threshold (e.g. EBP04-014: prevented only when CP <= 30000).
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect and effect.prevents_counter(_build_context(player_id, player.current_monster), total_cp):
		return true
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		var se := get_effect(sz_card)
		if se and se.prevents_counter(_build_context(player_id, sz_card), total_cp):
			return true
	return false


func are_opponent_strategy_plays_blocked(player_id: int) -> bool:
	## Check if the opponent of the given player has cards that block strategy plays.
	## player_id is the player trying to play a strategy card.
	var opponent_id: int = 1 - player_id
	var opponent := game_state.players[opponent_id]

	# Check opponent's strategy cards
	for sz_card in opponent.strategy_zones:
		if not sz_card.is_empty():
			var effect := get_effect(sz_card)
			if effect:
				if effect.blocks_opponent_strategy_plays(_build_context(opponent_id, sz_card)):
					return true

	# Check opponent's zone cards
	for i in range(8):
		var zone_card := opponent.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				if ze.blocks_opponent_strategy_plays(_build_context(opponent_id, zone_card)):
					return true

	return false


func force_counter(target_player_id: int) -> void:
	## Force a successful counter against target_player_id's monster.
	## The target's monster retreats and ranks up; the other player is the winner.
	if action_handler:
		await action_handler.force_counter(game_state, target_player_id)


func get_strategy_discard_interceptor(player_id: int) -> int:
	## Check if any zone card can intercept strategy discards (e.g. EBP02-012 in zone 8).
	## Returns the zone index (0-indexed) of the intercepting card, or -1 if none.
	var player := game_state.players[player_id]
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect and effect.can_intercept_strategy_discard(_build_context(player_id, zone_card)):
				return i
	return -1


func destroy_strategy_zone(player: PlayerState, zone_index: int) -> Dictionary:
	## Effect-driven destroy of a strategy card. Thin wrapper over
	## discard_strategy_from_zone that takes a PlayerState (ergonomic for card
	## scripts holding ctx.owner / ctx.opponent) and uses default options:
	## interceptor + banish_or_discard + strategy_discarded triggers, with
	## destruction-protection (EBP04-048) honored. Use this instead of raw
	## strategy_zones[i] = {} + discard_pile.append patterns.
	return await discard_strategy_from_zone(player.player_id, zone_index)


func discard_strategy_from_zone(player_id: int, zone_index: int, deferred_entries: Variant = null, bypass_protection: bool = false) -> Dictionary:
	## Remove a strategy card from a strategy zone, applying replacement effects (10.2.1.3).
	## If an interceptor is active, stacks the card under it instead of discarding.
	## When deferred_entries is provided, strategy_discarded triggers are collected there
	## instead of resolving immediately (used during invasion movement).
	## When bypass_protection is true, skips the destruction-protection check —
	## set this for rule-driven moves (start phase discard, invasion-base destruction)
	## that aren't <Destroy> by an effect. Effect-driven destroys leave it false so
	## protectors like EBP04-048 (Little Godzilla) take effect.
	## Returns the removed card (empty dict if zone was already empty or protected).
	var player := game_state.players[player_id]
	var card: Dictionary = player.strategy_zones[zone_index]
	if card.is_empty():
		return {}
	if not bypass_protection and not _can_destroy_card(player, card):
		return {}
	player.strategy_zones[zone_index] = {}

	var intercept_zone := get_strategy_discard_interceptor(player_id)
	if intercept_zone >= 0:
		player.zones[intercept_zone].append(card)
		player.zones_changed.emit()
	else:
		banish_or_discard(player, [card])
		player.discard_changed.emit()
	player.strategy_zones_changed.emit()

	# Replacement means it wasn't truly discarded — skip discard triggers
	if intercept_zone < 0:
		if deferred_entries != null:
			deferred_entries.append_array(collect_strategy_discarded_entries(player_id, card))
		else:
			await trigger_strategy_discarded(player_id, card)
	return card


func get_opponent_field_rank_modifier(player_id: int) -> int:
	## Get the field rank reduction applied to opponent's in-play battle cards.
	## Queries the player's current monster effect.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.get_opponent_field_rank_modifier(_build_context(player_id, player.current_monster))
	return 0


func is_base_strategy(card_data: Dictionary) -> bool:
	## Check if a strategy card has the <Base> keyword (12.9).
	## Base strategies are exempt from the Start Phase discard rule (7.2.3).
	var effect := get_effect(card_data)
	if effect:
		return effect.is_base_strategy()
	return false


func prevents_self_start_phase_discard(player_id: int, card_data: Dictionary) -> bool:
	## Check if a strategy card has custom anti-discard text exempting it from the
	## Start Phase discard rule (7.2.3) without being a <Base> card.
	var effect := get_effect(card_data)
	if effect:
		return effect.prevents_self_start_phase_discard(_build_context(player_id, card_data))
	return false


func can_card_be_played(player_id: int, card_data: Dictionary) -> bool:
	## Check if a card's play restriction allows it to be played.
	## Returns true if the card has no restriction or the restriction is satisfied.
	var effect := get_effect(card_data)
	if effect:
		return effect.can_be_played(_build_context(player_id, card_data))
	return true


func get_card_required_play_zones(player_id: int, card_data: Dictionary) -> Array[int]:
	## Returns the zone indices this card is restricted to, or empty if unrestricted.
	var effect := get_effect(card_data)
	if effect:
		return effect.get_required_play_zones(_build_context(player_id, card_data))
	return []


func move_zone_stack(player: PlayerState, from_zone: int, to_zone: int) -> void:
	## Move a zone's full stack to another zone, overloading any existing
	## contents at the destination per rule 11.5. No-op if the source is empty
	## or from_zone == to_zone.
	if from_zone == to_zone:
		return
	if not player.zone_has_cards(from_zone):
		return
	var overloaded_top: Dictionary = {}
	if player.zone_has_cards(to_zone):
		overloaded_top = player.get_zone_top_card(to_zone)
		var overloaded: Array = player.clear_zone(to_zone)
		banish_or_discard(player, overloaded)
		player.discard_changed.emit()
	var moved_top: Dictionary = player.get_zone_top_card(from_zone)
	var stack: Array = player.zones[from_zone]
	player.zones[from_zone] = []
	player.zones[to_zone] = stack
	player.zones_changed.emit()
	# Fire on_destroy for the overloaded card, then on_zone_changed for the
	# moved card — mirrors the linked-card semantics used by swap_zones and
	# play_from_discard so cards like EBP04-067 can react to forced movement.
	await trigger_leave_play(player.player_id, overloaded_top, to_zone)
	if not moved_top.is_empty() and has_trigger(moved_top, "on_zone_changed"):
		var me := get_effect(moved_top)
		await me.on_zone_changed(_build_context(player.player_id, moved_top), from_zone, to_zone)


func swap_zones(player: PlayerState, zone_a: int, zone_b: int) -> void:
	## Swap two zone stacks and fire on_zone_changed for each top card that moved.
	var top_a: Dictionary = player.get_zone_top_card(zone_a)
	var top_b: Dictionary = player.get_zone_top_card(zone_b)
	var stack_a: Array = player.zones[zone_a].duplicate()
	var stack_b: Array = player.zones[zone_b].duplicate()
	player.zones[zone_a] = stack_b
	player.zones[zone_b] = stack_a
	player.zones_changed.emit()
	if not top_a.is_empty() and has_trigger(top_a, "on_zone_changed"):
		var eff := get_effect(top_a)
		await eff.on_zone_changed(_build_context(player.player_id, top_a), zone_a, zone_b)
	if not top_b.is_empty() and has_trigger(top_b, "on_zone_changed"):
		var eff := get_effect(top_b)
		await eff.on_zone_changed(_build_context(player.player_id, top_b), zone_b, zone_a)


func destroy_base_strategies_on_invasion(to_zone: int, deferred_entries: Variant = null) -> void:
	## Destroy all <Base> strategy cards when any monster invades into zones 6-8 (12.9.2).
	## Checks both players' strategy zones. Uses discard_strategy_from_zone for replacement effects.
	## When deferred_entries is provided, strategy_discarded triggers are collected there
	## instead of resolving immediately.
	if to_zone < 6:
		return
	for pid in range(2):
		var player := game_state.players[pid]
		for i in range(player.strategy_zones.size() - 1, -1, -1):
			if not player.strategy_zones[i].is_empty() and is_base_strategy(player.strategy_zones[i]):
				# Rule-driven invasion destruction (12.9.2) — bypass protection.
				await discard_strategy_from_zone(pid, i, deferred_entries, true)


func get_effective_field_rank(card_data: Dictionary, owner_player_id: int) -> int:
	## Get the effective rank of an in-play battle card, accounting for opponent field rank modifiers.
	var base_rank: int = card_data.get("rank", 0)
	var opponent_id: int = 1 - owner_player_id
	var modifier: int = get_opponent_field_rank_modifier(opponent_id)
	return maxi(0, base_rank + modifier)


func get_zones_in_rank_range(player_id: int, min_rank: int = -1, max_rank: int = -1) -> Array[int]:
	## Return occupied zone indices whose top battle card's effective field rank
	## falls within [min_rank, max_rank]. Use -1 for either bound to leave it unbounded.
	var result: Array[int] = []
	var player := game_state.players[player_id]
	for i in range(8):
		var top := player.get_zone_top_card(i)
		if top.is_empty():
			continue
		var rank: int = get_effective_field_rank(top, player_id)
		if min_rank >= 0 and rank < min_rank:
			continue
		if max_rank >= 0 and rank > max_rank:
			continue
		result.append(i)
	return result


func get_effective_zone_cp(player_id: int, zone_idx: int) -> int:
	## Get the effective counter power of the top battle card in a zone, including
	## per-zone CP modifiers from active effects. Returns 0 if the zone is empty.
	var top := game_state.players[player_id].get_zone_top_card(zone_idx)
	if top.is_empty():
		return 0
	var modifiers := get_zone_cp_modifiers(player_id)
	return top.get("counter_power", 0) + modifiers[zone_idx]


func get_zones_in_cp_range(player_id: int, min_cp: int = -1, max_cp: int = -1) -> Array[int]:
	## Return occupied zone indices whose top battle card's effective CP falls within
	## [min_cp, max_cp]. Use -1 for either bound to leave it unbounded. Mirrors
	## get_zones_in_rank_range; modifiers are computed once per call.
	var result: Array[int] = []
	var player := game_state.players[player_id]
	var modifiers := get_zone_cp_modifiers(player_id)
	for i in range(8):
		var top := player.get_zone_top_card(i)
		if top.is_empty():
			continue
		var cp: int = top.get("counter_power", 0) + modifiers[i]
		if min_cp >= 0 and cp < min_cp:
			continue
		if max_cp >= 0 and cp > max_cp:
			continue
		result.append(i)
	return result


func get_zone_rank_modifiers(player_id: int) -> Array:
	## Get per-zone rank modifier for display. Returns Array of 8 ints.
	## Each value is the difference between effective rank and base rank for the zone's card.
	var modifiers: Array = []
	modifiers.resize(8)
	modifiers.fill(0)
	var player := game_state.players[player_id]
	var opponent_id: int = 1 - player_id
	var rank_mod: int = get_opponent_field_rank_modifier(opponent_id)
	if rank_mod == 0:
		return modifiers
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var base_rank: int = zone_card.get("rank", 0)
			var effective: int = maxi(1, base_rank + rank_mod)
			modifiers[i] = effective - base_rank
	return modifiers


func count_monsters_in_discard(player: PlayerState) -> int:
	## Count monster cards in discard pile. Includes cards with counts_as_monster_in_discard flag.
	var count: int = 0
	for card in player.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER or card.get("counts_as_monster_in_discard", false):
			count += 1
	return count


# --- Helpers for card placement and movement ---

func play_from_discard(player_id: int, card_data: Dictionary, zone_idx: int = -1) -> int:
	## Remove a card from the discard pile and play it into a zone.
	## If zone_idx is -1, the player selects an available zone.
	## Returns the zone index where the card was placed, or -1 if cancelled.
	var player := game_state.players[player_id]

	# Remove from discard
	var card_id: String = card_data.get("id", "")
	for i in range(player.discard_pile.size() - 1, -1, -1):
		if player.discard_pile[i].get("id", "") == card_id:
			player.discard_pile.remove_at(i)
			break
	player.discard_changed.emit()

	# Select zone if not specified
	if zone_idx < 0:
		var valid_zones: Array[int] = []
		for i in range(8):
			if i != player.monster_zone - 1:  # Can't play in own monster zone
				valid_zones.append(i)
		var card_name: String = card_data.get("name", "card")
		zone_idx = await select_zone_target(player_id, player_id, valid_zones, tr("STR_EFF_PLAY_FROM_DISCARD_ZONE_FMT") % card_name)
		if zone_idx < 0:
			# Can't skip — put back in discard as fallback
			player.discard_pile.append(card_data)
			player.discard_changed.emit()
			return -1

	# Handle overload if zone occupied
	var overloaded_top: Dictionary = {}
	if player.zone_has_cards(zone_idx):
		overloaded_top = player.get_zone_top_card(zone_idx)
		var destroyed_stack: Array = player.clear_zone(zone_idx)
		banish_or_discard(player, destroyed_stack)
		player.discard_changed.emit()

	player.push_zone_card(zone_idx, card_data)
	player.zones_changed.emit()
	await trigger_leave_play(player_id, overloaded_top, zone_idx)
	await trigger_enter(player_id, card_data, true)
	return zone_idx


func play_from_discard_or_skip(player_id: int, card_data: Dictionary, prompt: String, zone_filter: Callable = Callable()) -> int:
	## 'May'-style helper: prompt the player for a zone (with skip), then play
	## the card from discard there. If the player skips or no zones are valid,
	## the card stays in discard and -1 is returned.
	## zone_filter is an optional Callable(zone_idx: int) -> bool to restrict
	## valid placement zones; if omitted, any non-monster zone is valid.
	var player := game_state.players[player_id]
	var monster_idx: int = player.monster_zone - 1
	var valid_zones: Array[int] = []
	for i in range(8):
		if i == monster_idx:
			continue
		if zone_filter.is_valid() and not zone_filter.call(i):
			continue
		valid_zones.append(i)
	if valid_zones.is_empty():
		return -1
	var zone_idx: int = await select_zone_target(
		player_id, player_id, valid_zones, prompt, true)
	if zone_idx < 0:
		return -1
	return await play_from_discard(player_id, card_data, zone_idx)


func play_battle_card_from_deck(player_id: int, card_data: Dictionary, zone_idx: int) -> void:
	## Place a battle card directly from the deck into a zone, then fire enter and
	## on_battle_card_played (with played_from_deck=true) in the correct order.
	## Handles zone overload. Use this instead of manual push+trigger_enter+trigger_battle_card_played
	## so that standby entry ordering is correct when called from within effect callbacks.
	var player := game_state.players[player_id]
	var overloaded_top: Dictionary = {}
	if player.zone_has_cards(zone_idx):
		overloaded_top = player.get_zone_top_card(zone_idx)
		var destroyed_stack: Array = player.clear_zone(zone_idx)
		banish_or_discard(player, destroyed_stack)
		player.discard_changed.emit()
	player.push_zone_card(zone_idx, card_data)
	player.zones_changed.emit()
	await trigger_leave_play(player_id, overloaded_top, zone_idx)
	await trigger_enter(player_id, card_data, true)
	await trigger_battle_card_played(player_id, card_data, zone_idx, true)


func place_card_under_zone(player: PlayerState, card: Dictionary, zone_idx: int) -> void:
	## Place a card under the top card of a zone (into the zone stack below the top).
	if zone_idx < 0 or zone_idx >= 8:
		return
	player.zones[zone_idx].append(card)
	player.zones_changed.emit()


func get_cards_under_top(player: PlayerState, zone_idx: int) -> Array:
	## Return the zone stack excluding the top card (cards stacked under).
	if zone_idx < 0 or zone_idx >= 8:
		return []
	var stack: Array = player.zones[zone_idx]
	if stack.size() <= 1:
		return []
	return stack.slice(1)


func place_card_under_strategy_zone(player: PlayerState, card: Dictionary, strat_idx: int) -> void:
	## Place a card under the top card of a strategy zone (into strategy_zone_stacks).
	## Used by EBP04-089 (Inherited Life) to track rage card placements.
	if strat_idx < 0 or strat_idx >= player.strategy_zone_stacks.size():
		return
	player.strategy_zone_stacks[strat_idx].append(card)
	player.strategy_zones_changed.emit()


func get_cards_under_strategy_top(player: PlayerState, strat_idx: int) -> Array:
	## Return cards stacked under a strategy zone's top card.
	if strat_idx < 0 or strat_idx >= player.strategy_zone_stacks.size():
		return []
	return player.strategy_zone_stacks[strat_idx]


# --- EBP04 new mechanism helpers ---

func is_opponent_end_phase_draw_blocked(drawing_player_id: int) -> bool:
	## Check if the drawing player is blocked from drawing during end phase.
	## Checks opponent's zone cards and monster for blocks_opponent_end_phase_draw.
	var opponent_id: int = 1 - drawing_player_id
	var opponent := game_state.players[opponent_id]
	var ctx_card := opponent.current_monster
	var effect := get_effect(ctx_card)
	if effect and effect.blocks_opponent_end_phase_draw(_build_context(opponent_id, ctx_card)):
		return true
	for i in range(8):
		var zone_card := opponent.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze and ze.blocks_opponent_end_phase_draw(_build_context(opponent_id, zone_card)):
				return true
	return false


func _passes_prevents_monster_move_filter(card_data: Dictionary, watcher_player_id: int) -> bool:
	## Evaluate TRIGGER_FILTERS["prevents_opponent_monster_move"] for the
	## passive-query protector. Even though this is a query (not a triggered
	## ability), authors can gate it by turn ownership or by who's causing
	## the move:
	## "own_turn": bool — gate by watcher's turn ownership.
	## "caused_by_opponent": bool — gate by `_active_effect_player_id`. true =
	##   only block when the opponent's active effect is moving the monster.
	var filter: Dictionary = get_trigger_filter(card_data, "prevents_opponent_monster_move")
	if filter.is_empty():
		return true
	if filter.has("own_turn"):
		var is_own_turn: bool = (game_state.current_player_id == watcher_player_id)
		if filter.own_turn != is_own_turn:
			return false
	if filter.has("caused_by_opponent"):
		var by_effect: bool = _active_effect_player_id >= 0
		var caused_by_opponent: bool = by_effect and _active_effect_player_id != watcher_player_id
		var caused_by_self: bool = by_effect and _active_effect_player_id == watcher_player_id
		if filter.caused_by_opponent and not caused_by_opponent:
			return false
		if not filter.caused_by_opponent and not caused_by_self:
			return false
	return true


func is_opponent_monster_move_blocked(target_player_id: int) -> bool:
	## Check if the target player's monster is protected from being moved by opponent effects.
	## Checks target player's strategy zones for prevents_opponent_monster_move.
	## TRIGGER_FILTERS keys: own_turn, caused_by_opponent.
	var player := game_state.players[target_player_id]
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		if not _passes_prevents_monster_move_filter(sz_card, target_player_id):
			continue
		var effect := get_effect(sz_card)
		if effect and effect.prevents_opponent_monster_move(_build_context(target_player_id, sz_card)):
			return true
	return false


func is_invade1_cost_blocked(invading_player_id: int) -> bool:
	## Check if the invading player is blocked from using invade1 cards as invasion cost.
	## Checks opponent's zone cards and monster for blocks_invade1_invasion_cost.
	var opponent_id: int = 1 - invading_player_id
	var opponent := game_state.players[opponent_id]
	var effect := get_effect(opponent.current_monster)
	if effect and effect.blocks_invade1_invasion_cost(_build_context(opponent_id, opponent.current_monster)):
		return true
	for i in range(8):
		var zone_card := opponent.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze and ze.blocks_invade1_invasion_cost(_build_context(opponent_id, zone_card)):
				return true
	return false


func get_strategy_hand_rank_modifier(player_id: int, card: Dictionary) -> int:
	## Sum rank modifiers applied to a strategy card while held in player_id's hand.
	## Queries all cards from both players so effects can target owner, opponent, or both.
	var total: int = 0
	for source_id in range(2):
		var source := game_state.players[source_id]
		var effect := get_effect(source.current_monster)
		if effect:
			total += effect.get_strategy_hand_rank_modifier(
				_build_context(source_id, source.current_monster), card, player_id)
		for i in range(8):
			var zone_card := source.get_zone_top_card(i)
			if not zone_card.is_empty():
				var ze := get_effect(zone_card)
				if ze:
					total += ze.get_strategy_hand_rank_modifier(
						_build_context(source_id, zone_card), card, player_id)
	return total


func trigger_all_monster_enter_abilities(player_id: int) -> void:
	## Re-trigger the on_enter ability of the topmost monster card. Used by EBP04-041 (New Gotengo).
	var player := game_state.players[player_id]
	if player.current_monster.is_empty():
		return
	await trigger_enter(player_id, player.current_monster)


func collect_ally_zone_card_destroyed_entries(player_id: int, destroyed_card: Dictionary, zone_idx: int) -> Array:
	## Collect standby entries for on_ally_zone_card_destroyed triggers.
	## Iterates the destroying player's zone cards for cards with this trigger.
	var entries: Array = []
	var player := game_state.players[player_id]
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if zone_card.get("id", "") == destroyed_card.get("id", ""):
			continue  # Skip the card that was just destroyed
		if not has_trigger(zone_card, "on_ally_zone_card_destroyed"):
			continue
		if not _passes_zone_destroyed_filter(zone_card, "on_ally_zone_card_destroyed", player, zone_idx, false):
			continue
		var effect := get_effect(zone_card)
		if effect:
			var ctx := _build_context(player_id, zone_card)
			entries.append({"player_id": player_id, "card_data": zone_card, "callback": effect.on_ally_zone_card_destroyed.bind(ctx, destroyed_card, zone_idx)})
	return entries


func trigger_ally_zone_card_destroyed(player_id: int, destroyed_card: Dictionary, zone_idx: int) -> void:
	## Fire on_ally_zone_card_destroyed triggers for the player whose card was destroyed.
	var entries := collect_ally_zone_card_destroyed_entries(player_id, destroyed_card, zone_idx)
	if not entries.is_empty():
		await _resolve_standby_entries(entries)


func collect_opponent_zone_card_destroyed_entries(destroyed_player_id: int, destroyed_card: Dictionary, zone_idx: int) -> Array:
	## Collect standby entries for on_opponent_zone_card_destroyed triggers.
	## Iterates the opponent of the destroyed card's owner (they react when opponent's card is destroyed).
	var entries: Array = []
	var watcher_id: int = 1 - destroyed_player_id
	var watcher := game_state.players[watcher_id]
	var monster := watcher.current_monster
	if not monster.is_empty() and has_trigger(monster, "on_opponent_zone_card_destroyed"):
		if _passes_zone_destroyed_filter(monster, "on_opponent_zone_card_destroyed", watcher, zone_idx, true):
			var effect := get_effect(monster)
			if effect:
				var ctx := _build_context(watcher_id, monster)
				entries.append({"player_id": watcher_id, "card_data": monster, "callback": effect.on_opponent_zone_card_destroyed.bind(ctx, destroyed_card, zone_idx)})
	for i in range(8):
		var zone_card := watcher.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if not has_trigger(zone_card, "on_opponent_zone_card_destroyed"):
			continue
		if not _passes_zone_destroyed_filter(zone_card, "on_opponent_zone_card_destroyed", watcher, zone_idx, true):
			continue
		var effect := get_effect(zone_card)
		if effect:
			var ctx := _build_context(watcher_id, zone_card)
			entries.append({"player_id": watcher_id, "card_data": zone_card, "callback": effect.on_opponent_zone_card_destroyed.bind(ctx, destroyed_card, zone_idx)})
	return entries


func _passes_zone_destroyed_filter(card_data: Dictionary, method_name: String, watcher: PlayerState, zone_idx: int, is_cross_board: bool) -> bool:
	## Evaluate TRIGGER_FILTERS[method_name] for zone-card-destroyed triggers.
	## `column: "monster"` — destroyed zone must be in the watcher's monster column.
	## `is_cross_board` distinguishes ally (false, same side) vs opponent (true, cross-board).
	var filter: Dictionary = get_trigger_filter(card_data, method_name)
	if filter.is_empty():
		return true
	if filter.has("column"):
		var anchor: int = watcher.monster_zone - 1
		if anchor < 0:
			return false
		match String(filter.column):
			"monster":
				var allowed: Array[int]
				if is_cross_board:
					allowed = CardEffect.get_opponent_column_zones(anchor)
				else:
					allowed = CardEffect.get_column_zones(anchor)
				if zone_idx not in allowed:
					return false
	return true


func trigger_opponent_zone_card_destroyed(destroyed_player_id: int, destroyed_card: Dictionary, zone_idx: int) -> void:
	## Fire on_opponent_zone_card_destroyed triggers on the opponent of the destroyed card's owner.
	var entries := collect_opponent_zone_card_destroyed_entries(destroyed_player_id, destroyed_card, zone_idx)
	if not entries.is_empty():
		await _resolve_standby_entries(entries)


func _passes_card_returned_filter(card_data: Dictionary, watcher_player_id: int, returning_player_id: int) -> bool:
	## Evaluate TRIGGER_FILTERS["on_card_returned_from_discard"].
	## "own_turn": bool — gate by watcher's turn ownership.
	## "returned_by_opponent": bool — true = only when the watcher's opponent
	##                                returned the card.
	var filter: Dictionary = get_trigger_filter(card_data, "on_card_returned_from_discard")
	if filter.is_empty():
		return true
	if filter.has("own_turn"):
		var is_own_turn: bool = (game_state.current_player_id == watcher_player_id)
		if filter.own_turn != is_own_turn:
			return false
	if filter.has("returned_by_opponent"):
		var by_opponent: bool = returning_player_id != watcher_player_id
		if filter.returned_by_opponent != by_opponent:
			return false
	return true


func collect_card_returned_from_discard_entries(returning_player_id: int, card: Dictionary) -> Array:
	## Collect standby entries for on_card_returned_from_discard triggers from
	## active cards on BOTH players. TRIGGER_FILTERS gates by turn / who returned.
	var entries: Array = []
	for pid in range(2):
		var observer := game_state.players[pid]
		for i in range(8):
			var zone_card := observer.get_zone_top_card(i)
			if zone_card.is_empty():
				continue
			if not has_trigger(zone_card, "on_card_returned_from_discard"):
				continue
			if not _passes_card_returned_filter(zone_card, pid, returning_player_id):
				continue
			var effect := get_effect(zone_card)
			if effect:
				var ctx := _build_context(pid, zone_card)
				entries.append({"callback": effect.on_card_returned_from_discard.bind(ctx, card), "player_id": pid, "card_data": zone_card})
	return entries


func trigger_card_returned_from_discard(returning_player_id: int, card: Dictionary) -> void:
	## Fire on_card_returned_from_discard triggers when a player returns a card from discard to hand.
	var entries := collect_card_returned_from_discard_entries(returning_player_id, card)
	if not entries.is_empty():
		await _resolve_standby_entries(entries)


func return_discard_to_hand(player_id: int, card: Dictionary) -> void:
	## Move a card from a player's discard pile to their hand and fire
	## on_card_returned_from_discard triggers. Safe to call when the card has already
	## been popped from discard (e.g. by search_discard) — the erase becomes a no-op.
	## Logs the return attributed to whichever effect is currently active.
	var player := game_state.players[player_id]
	var was_in_discard: bool = card in player.discard_pile
	if was_in_discard:
		player.discard_pile.erase(card)
		player.discard_changed.emit()
	player.hand.append(card)
	player.hand_changed.emit()
	var source_id: String = _active_effect_card.get("id", "") if not _active_effect_card.is_empty() else ""
	log_message.emit(GameLog.effect_returned_card_to_hand(player_id, source_id, card.get("id", "")))
	await trigger_card_returned_from_discard(player_id, card)
