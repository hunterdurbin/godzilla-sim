class_name CheckTiming
extends RefCounted

## The single owner of check timing (10.4.3): rule actions, the standby pool,
## and which ability is currently resolving.
##
## A check timing (10.4.3.1–10.4.3.4) performs every rule action until none
## remain — the crush rule first (11.3, interrupt, 11.1.2.1), then illegal
## cards (11.4) — and then resolves the abilities in standby as ONE pool:
## after every ability rule actions run again; the turn player, if they have
## any abilities in standby, picks one of ALL of theirs (10.4.3.2), otherwise
## the non-turn player picks one of theirs (10.4.3.3); repeat until none
## remain (10.4.3.4). Abilities triggered while one resolves join the pool.
##
## Overload (11.5) has no step here: the engine performs it when a card is
## placed (docs/adr/0001-overload-at-placement.md).
##
## Trigger sources only submit StandbyEntry objects; nothing resolves on the
## spot. Entries resolve at the next check timing — after the current action
## or phase step (TurnManager calls resolve, 10.4.4.1 / 7.x), or between two
## abilities of a running pass. Per 10.6.7 an entry resolves even after its
## card changes areas; only its still_applies gate drops it (10.6.3.2).
##
## Running an ability goes through run_effect: it marks the ability active
## (read-only via active_player_id / active_card).
##
## Dependencies (wired by EffectHandler.setup): game_state, and the facade `h`
## for the trigger collectors, destroy replacement, the order-choice prompt,
## the GameEvents bus and the highlight signals.

var game_state: GameState
var h: EffectHandler

## Player whose ability is currently resolving (-1 = none).
var active_player_id: int:
	get: return _active_player_id
## Card whose ability is currently resolving ({} = none).
var active_card: Dictionary:
	get: return _active_card

var _active_player_id: int = -1
var _active_card: Dictionary = {}
## True while a standby pass is running.
var _in_resolution: bool = false
## Abilities submitted while a pass or an ability was running (10.4.3).
var _pending: Array = []

## Snapshot state for the effect_stack_changed notification: the entry whose
## callback is executing and the rest of the live pool (alias of the live
## array — rows are composed fresh at each publish).
var _stack_active: StandbyEntry = null
var _stack_pool: Array = []


func teardown() -> void:
	## Break the cycle back to the facade. Pending entries hold Callables that
	## capture effects/contexts. Idempotent.
	_pending.clear()
	_stack_pool = []
	_stack_active = null
	h = null
	game_state = null


# --- Active ability ---

func has_active_effect() -> bool:
	return not _active_card.is_empty()


func has_pending() -> bool:
	return not _pending.is_empty()


func run_effect(player_id: int, card: Dictionary, callback: Callable) -> void:
	## Resolve one ability: mark it active, announce it, await it, then
	## restore the ability that was active before (or clear). Abilities
	## submitted meanwhile queue for the next check timing.
	var saved_player_id: int = _active_player_id
	var saved_card: Dictionary = _active_card
	_active_player_id = player_id
	_active_card = card
	h.note_effect_resolving(player_id, card)
	await callback.call()
	if saved_card.is_empty():
		_clear_active()
	else:
		_active_player_id = saved_player_id
		_active_card = saved_card


func _clear_active() -> void:
	# Defensive: emit unhighlight when clearing, in case the leaf function that
	# emitted the matching highlight didn't reach its own unhighlight call.
	# UI side is idempotent — clearing an already-clear highlight is a no-op.
	if _active_player_id >= 0:
		var card_id: String = _active_card.get("id", "")
		if not card_id.is_empty():
			h.effect_card_unhighlighted.emit(_active_player_id, card_id)
	_active_player_id = -1
	_active_card = {}


# --- Check timing: rule actions (10.4.3.1, 11.x) ---

func resolve() -> void:
	## Perform a check timing (10.4.3): resolve all rule actions (10.4.3.1,
	## 11.1.2 — interrupt crush first, repeated until none remain), then play
	## every ability in standby as one pool (10.4.3.2–10.4.3.4).
	## When a standby pass is already running (this check timing sits between
	## two of its abilities) or an ability is resolving, only the rule actions
	## run: their abilities join the standby the running pass drains.
	_perform_rule_actions()
	if _in_resolution or has_active_effect():
		return
	await _run_pass()
	# Rage markers a decrease left for its triggers to claim (EBP04-089) last
	# only until those triggers resolved: drop the unclaimed ones.
	for player in game_state.players:
		player.clear_pending_rage_markers()


func _perform_rule_actions() -> void:
	## 10.4.3.1: every rule action until none remain; the abilities they
	## trigger enter standby.
	var triggered: Array = []
	var changed := true
	while changed:
		changed = false
		# Interrupt rule actions first (11.1.2.1): crush rule (11.3)
		if _check_crush_for_player(game_state.current_player_id, triggered):
			changed = true
		if _check_crush_for_player(1 - game_state.current_player_id, triggered):
			changed = true
		# Non-interrupt rule actions
		for pid in range(2):
			if _resolve_illegal_cards(game_state.players[pid]):
				changed = true
	submit(triggered)


func check_crush_rule(triggered: Array) -> void:
	## Interrupt type rule action (11.3): destroy battle cards sharing a zone
	## with a monster. Per 11.1.2.1.1: turn player's interrupt rule actions
	## resolve first. The single crush path: the crushed cards' leave-play,
	## crush and <Revenge> abilities are appended to `triggered` — never
	## resolved here. The caller submits them to standby (10.6.2) once its
	## movement / check timing is done.
	## Emits battle_card_crushed (GameEvents) and the crushed player's
	## zones_changed / discard_changed.
	_check_crush_for_player(game_state.current_player_id, triggered)
	_check_crush_for_player(1 - game_state.current_player_id, triggered)


func crush_now(player_id: int = -1) -> void:
	## Perform the crush rule immediately (interrupt rule action, 11.1.2.1)
	## for one player (or both, turn player first, when player_id < 0) and
	## submit the triggered abilities to standby — for callers that move a
	## monster outside movement/check-timing loops (teleport, board editor).
	## Same signals as check_crush_rule; the abilities wait in standby for the
	## next check timing.
	var triggered: Array = []
	if player_id < 0:
		check_crush_rule(triggered)
	else:
		_check_crush_for_player(player_id, triggered)
	submit(triggered)


func _check_crush_for_player(player_id: int, triggered: Array) -> bool:
	## Crush this player's battle card sharing a zone with their monster.
	## Returns true if a card left the field. Triggered abilities are
	## collected into `triggered` (see check_crush_rule).
	var player := game_state.players[player_id]

	# Monsters and battle cards occupy the SAME player's zones.
	# The crush rule (11.3): if a battle card is in the same zone as the monster, destroy it.
	var monster_zone_idx: int = player.monster_zone - 1  # 0-indexed
	if monster_zone_idx < 0 or monster_zone_idx >= 8 or not player.zone_has_cards(monster_zone_idx):
		return false
	# Crush is <Destroy> (11.3.3), so on_would_be_destroyed replacements apply
	# at the moment of the crush (10.2.1.3); a replaced card never counts as
	# destroyed and fires no crush/<Revenge>, but its leave-play still triggers.
	var top_card := player.get_zone_top_card(monster_zone_idx)
	var replaced: bool = h.try_destroy_replacement(player, monster_zone_idx)
	if not replaced:
		var crushed_stack: Array = player.clear_zone(monster_zone_idx)
		EffectHandler.banish_or_discard(player, crushed_stack)
		player.cards_destroyed_this_turn.append(crushed_stack[0])
		if h.events:
			h.events.battle_card_crushed.emit(player_id, monster_zone_idx, crushed_stack[0])
		player.zones_changed.emit()
		player.discard_changed.emit()
	triggered.append_array(h.collect_leave_play_entries(player_id, top_card, monster_zone_idx))
	if not replaced:
		triggered.append_array(h.collect_crush_and_revenge_entries(player_id, top_card))
	return true


func _resolve_illegal_cards(player: PlayerState) -> bool:
	## Rule 11.4 - Illegal Cards (non-interrupt rule action).
	## Strategy cards in zones that are not stacked under a battle/monster card → discard.
	## Non-strategy cards in strategy zones → discard.
	var changed := false

	# Check zones: strategy cards not stacked under another card are illegal
	for i in range(8):
		if player.is_zone_empty(i):
			continue
		var top_card := player.get_zone_top_card(i)
		if top_card.get("card_type") == CardEnums.CardType.STRATEGY:
			var stack: Array = player.clear_zone(i)
			EffectHandler.banish_or_discard(player, stack)
			changed = true

	# Check strategy zones: non-strategy cards are illegal
	for i in range(2):
		if player.strategy_zones[i].is_empty():
			continue
		if player.strategy_zones[i].get("card_type") != CardEnums.CardType.STRATEGY:
			EffectHandler.banish_or_discard(player, [player.strategy_zones[i]])
			player.strategy_zones[i] = {}
			changed = true

	if changed:
		player.zones_changed.emit()
		player.strategy_zones_changed.emit()
		player.discard_changed.emit()
	return changed


# --- Standby (10.4.3.2–10.4.3.4, 10.6) ---

func submit(entries: Array) -> void:
	## Submit StandbyEntry abilities to standby (10.6.2). Nothing resolves on
	## the spot: they wait for the next check timing — the one after the
	## current action or phase step (resolve), or, inside a running pass, the
	## one after the ability now resolving. Per 10.6.7 an entry still resolves
	## after its card changes areas; only its still_applies gate can drop it
	## (10.6.3.2). Publishes GameEvents.effect_stack_changed.
	if entries.is_empty():
		return
	_pending.append_array(entries)
	_publish_stack()


func _run_pass() -> void:
	## Play the abilities in standby as one pool until none remain
	## (10.4.3.2–10.4.3.4), performing rule actions before each one
	## (10.4.3.1). May prompt (choose_option via select_choice) when a player
	## has 2+ abilities in the pool.
	if _pending.is_empty():
		return
	_in_resolution = true
	var pool: Array = []
	_stack_pool = pool

	while true:
		# 10.4.3.1: perform rule actions. Abilities they trigger (crush) join
		# the pool below, with everything submitted meanwhile.
		_perform_rule_actions()
		_merge_pending(pool)

		# 10.6.3.2: an ability in standby that can no longer be played ceases
		# to exist — drop it before the order prompt so it never shows as a no-op.
		_drop_inapplicable(pool)
		if pool.is_empty():
			break

		# 10.4.3.2 / 10.4.3.3: turn player first, else non-turn player.
		var turn_pid: int = game_state.current_player_id
		var chooser: int = turn_pid if _has_entries_for(pool, turn_pid) else 1 - turn_pid
		var entry: StandbyEntry = await _choose_entry(chooser, pool)

		# Keep the chosen entry visible as "resolving" through any nested
		# prompts its callback opens.
		_stack_active = entry
		_publish_stack()

		await run_effect(entry.player_id, entry.card, entry.callback)

		_stack_active = null
		_publish_stack()

	_in_resolution = false
	_stack_active = null
	_stack_pool = []
	_publish_stack()


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


func _choose_entry(player_id: int, pool: Array) -> StandbyEntry:
	## Remove and return the ability `player_id` resolves next. Playing is
	## compulsory (10.6.3.1); with several, the player chooses which.
	var indices: Array[int] = []
	for i in range(pool.size()):
		if pool[i].player_id == player_id:
			indices.append(i)
	if indices.size() == 1:
		return pool.pop_at(indices[0])

	# Publish the pool as pending so the stack UI shows it during the prompt.
	_stack_active = null
	_publish_stack()

	var options: Array[String] = []
	var option_card_ids: Array[String] = []
	var source_refs: Array[Dictionary] = []
	for i in indices:
		var e: StandbyEntry = pool[i]
		var ref := card_location_ref(game_state, e.player_id, e.card)
		options.append(ref["label"])
		option_card_ids.append(CardUtils.base_id(e.card))
		source_refs.append(ref)
	h.choice_source_refs = source_refs
	var chosen: int = await h.select_choice(player_id, options, tr("STR_EFF_CHOOSE_ABILITY"), option_card_ids)
	if chosen < 0 or chosen >= indices.size():
		chosen = 0
	return pool.pop_at(indices[chosen])


func _merge_pending(pool: Array) -> void:
	## Move abilities that entered standby while the pool was busy into it.
	if _pending.is_empty():
		return
	pool.append_array(_pending)
	_pending = []


static func _has_entries_for(pool: Array, player_id: int) -> bool:
	for e: StandbyEntry in pool:
		if e.player_id == player_id:
			return true
	return false


func _publish_stack() -> void:
	## Emit the current pending-effect stack (resolving entry first) via
	## GameEvents so the UI can keep the player informed mid-resolution.
	## Pure notification — nothing awaits it; no-op without a wired bus.
	if h == null or h.events == null:
		return
	var rows: Array = []
	if _stack_active != null:
		rows.append(_stack_row(_stack_active, "resolving"))
	for e: StandbyEntry in _stack_pool:
		rows.append(_stack_row(e, "pending"))
	for e: StandbyEntry in _pending:
		rows.append(_stack_row(e, "pending"))
	h.events.effect_stack_changed.emit(rows)


func _stack_row(entry: StandbyEntry, status: String) -> Dictionary:
	var loc := card_location_ref(game_state, entry.player_id, entry.card)
	return {
		"player_id": entry.player_id,
		"base_id": loc["base_id"],
		"label": loc["label"],
		"status": status,
		"location": loc,
	}


static func _drop_inapplicable(entries: Array) -> void:
	## Remove (in place) entries whose still_applies gate reports false at
	## resolution time (10.6.3).
	for i in range(entries.size() - 1, -1, -1):
		if not (entries[i] as StandbyEntry).applies():
			entries.remove_at(i)
