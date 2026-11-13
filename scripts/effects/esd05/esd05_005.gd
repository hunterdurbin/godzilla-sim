extends CardEffect

## ESD05-005: Constructed Future - Strategy Rank 6 (Green)
## In order from lowest rank, <Destroy> 3 battle cards in your zones. If you
## <Destroy> 3, play 1 of the highest rank battle cards from your discard pile.
##
## Tested: Yes
## Known issues: None
## Edge cases:
##   - The owner always marks the cards (multi-zone prompt, picks turn red),
##     even when the choice is forced. Only the lowest-rank unpicked cards are
##     pickable (ZoneSelectConstraints.lowest_first, effective field rank); a
##     higher rank unlocks once the lower rank is fully marked.
##   - Fewer than 3 battle cards → mark them all; they're destroyed and
##     nothing is played.
##   - Cards that can't be destroyed stay IN the ordering (they can be the
##     lowest rank) — marking one spends a slot, it survives, and with fewer
##     than 3 truly destroyed the play-back doesn't happen. (As of ESD05 every
##     printed protection is "by your opponent's effects", so none stops this
##     card; the path exists for future cards.)
##   - A replacement effect (e.g. "put this on the bottom of your deck
##     instead" — ESD01-011/012, EBP03-041, ESC01-004) resolves immediately;
##     that card wasn't destroyed, so it doesn't count. Tokens (Crystals)
##     destroyed this way DO count.
## Rules: Automatic abilities triggered by the batch (revenge, ally /
##   opponent zone-card-destroyed, EBP04-067's leave link) enter standby and
##   resolve at the check timing after the whole effect — i.e. after the
##   play-back (10.4.3). Replacement effects resolve mid-destruction.
## Interactions: Cards this destroys are already in the discard pile when the
##   highest-rank card is chosen, so they're eligible.
## Implementation notes: destroy_zones_reporting_destroyed reports only true
##   destructions; its triggers queue behind this active effect like any
##   destroy_zones call.

const _TriggerMap = preload("res://scripts/effects/trigger_map.gd")

const DESTROY_COUNT := 3


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	## Cast only when the forced lowest-rank 3 will all really be destroyed
	## and the play-back beats the best of what we're giving up. Uses printed
	## ranks — the bot hook has no field-modifier access.
	var zones := owner.get_battle_card_zone_indices()
	if zones.size() < DESTROY_COUNT:
		return false
	var cards: Array[Dictionary] = []
	for zi in zones:
		cards.append(owner.get_zone_top_card(zi))
	cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("rank", 0)) < int(b.get("rank", 0)))
	var cutoff: int = int(cards[DESTROY_COUNT - 1].get("rank", 0))
	var best_given_up: int = 0
	for card in cards:
		if int(card.get("rank", 0)) > cutoff:
			break
		# Anything that might not die (or protects others) can stall the 3 —
		# any card in the cutoff tier could be among the marked ones.
		if _may_resist_destruction(card):
			return false
		best_given_up = maxi(best_given_up, int(card.get("rank", 0)))
	for card in cards:
		if _protects_others(card):
			return false
	if _protects_others(owner.current_monster):
		return false
	for card in owner.strategy_zones:
		if _protects_others(card):
			return false
	for card in owner.discard_pile:
		if CardUtils.is_battle(card) and int(card.get("rank", 0)) > best_given_up:
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var handler: EffectHandler = ctx.effect_handler
	var pid: int = ctx.owner.player_id
	var zones := ctx.owner.get_battle_card_zone_indices()
	if zones.is_empty():
		return
	var weights: Dictionary = {}
	for zi in zones:
		weights[zi] = ctx.field_rank(ctx.owner.get_zone_top_card(zi), pid)
	var constraints := ZoneSelectConstraints.lowest_first(weights)
	var count: int = mini(DESTROY_COUNT, zones.size())

	var picked: Array[int] = await handler.select_zones_target(
		pid, pid, zones, count, tr("STR_EFF_ESD05_005_DESTROY_PROMPT"), false, constraints)
	if not _is_legal_pick(picked, zones, count, constraints):
		picked = _forced_pick(zones, count, constraints)  # Defensive

	var destroyed: Array[Dictionary] = await handler.destroy_zones_reporting_destroyed(ctx.owner, picked)
	if destroyed.size() >= DESTROY_COUNT:
		await _play_highest_from_discard(ctx)


func _play_highest_from_discard(ctx: EffectContext) -> void:
	var top_rank: int = -1
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card):
			top_rank = maxi(top_rank, int(card.get("rank", 0)))
	if top_rank < 0:
		return
	var found := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.is_battle(card) and int(card.get("rank", 0)) == top_rank,
		tr("STR_EFF_ESD05_005_PLAY_PROMPT"),
		false)
	if found.is_empty():
		return
	await ctx.effect_handler.play_from_discard(ctx.owner.player_id, found)


func _is_legal_pick(picked: Array[int], zones: Array[int], count: int, constraints: Dictionary) -> bool:
	if picked.size() != count:
		return false
	var seen := {}
	for z in picked:
		if z not in zones or seen.has(z):
			return false
		seen[z] = true
	return ZoneSelectConstraints.is_valid(constraints, picked)


func _forced_pick(zones: Array[int], count: int, constraints: Dictionary) -> Array[int]:
	var out: Array[int] = []
	while out.size() < count:
		var added: bool = false
		for z in zones:
			if z not in out and ZoneSelectConstraints.can_add(constraints, out, z):
				out.append(z)
				added = true
				break
		if not added:
			break
	return out


func _may_resist_destruction(card: Dictionary) -> bool:
	return _hook_applies_to_own_effects(card, "can_be_destroyed") \
		or _hook_applies_to_own_effects(card, "on_would_be_destroyed")


func _protects_others(card: Dictionary) -> bool:
	return _hook_applies_to_own_effects(card, "protects_card_from_destruction")


func _hook_applies_to_own_effects(card: Dictionary, method_name: String) -> bool:
	## True when `card` implements a destroy-gate hook that isn't limited to
	## the opponent's effects ("caused_by_opponent") — i.e. it can stop or
	## replace a destruction this card causes on its own board.
	if card.is_empty():
		return false
	var path: String = str(card.get("effect_script", ""))
	var triggers: Array = _TriggerMap.TRIGGERS.get(path, [])
	if not triggers.has(method_name):
		return false
	var script_res := load(path) as GDScript
	if script_res == null:
		return true
	var filters: Dictionary = script_res.get_script_constant_map().get("TRIGGER_FILTERS", {})
	var gate: Dictionary = filters.get(method_name, {})
	return not bool(gate.get("caused_by_opponent", false))
