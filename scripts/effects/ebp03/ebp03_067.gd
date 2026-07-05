extends CardEffect

## EBP03-067: Monster X - Battle Rank 5 (White)
## <Your Turn> When this card is discarded from your hand, if there are 2 or more colors
## among battle cards in your zones, play this card and <Destroy> up to 1 of your
## opponent’s lowest ranked battle cards in their zones.
## This card’s counter power X is equal to 3000 multiplied by the number of different
## colors among other battle cards in your zones. (White also counts as a color.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: The 2-color condition is checked once, at the moment this card is
##   discarded (e.g. as an invasion cost) — it is NOT re-checked after invasion
##   movement/crush. Only the counter power X reads the board continuously.
## Interactions: None
## Implementation notes: Trigger-time gate lives in discard_from_hand_condition
##   (collect-time hook); the play/destroy body still resolves post-movement.
##   Counter power X is a variable BASE stat (get_variable_counter_power), not
##   a modifier — it shows as "Base power" in breakdowns and is not
##   engagement-gated.


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard", "destroys_zone", "boosts_cp"]


func discard_from_hand_condition(ctx: EffectContext) -> bool:
	# <Your Turn> + 2-color check, evaluated once at discard time (e.g. as
	# invasion cost); not re-checked after invasion movement/crush.
	return ctx.is_own_turn() and _count_zone_colors(ctx) >= 2


func on_discard_from_hand(ctx: EffectContext) -> void:
	# Play self from discard
	await ctx.effect_handler.play_from_discard(ctx.owner.player_id, ctx.card_data)

	# Destroy up to 1 of opponent's lowest ranked battle cards
	var lowest_rank: int = 99
	for i in range(8):
		var zone_card := ctx.opponent.get_zone_top_card(i)
		if not zone_card.is_empty():
			var rank: int = ctx.field_rank(zone_card, ctx.opponent.player_id)
			if rank < lowest_rank:
				lowest_rank = rank

	if lowest_rank < 99:
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) == lowest_rank,
			tr("STR_EFF_DESTROY_OPP_LOWEST_OR_SKIP"))


func get_variable_counter_power(ctx: EffectContext) -> int:
	# CP = 3000 * number of different colors among OTHER battle cards in zones
	var colors: Array[int] = []
	var my_zone: int = find_zone_of_card(ctx)
	for i in range(8):
		if i == my_zone:
			continue
		var zone_card := ctx.owner.get_zone_top_card(i)
		if not zone_card.is_empty() and CardUtils.is_battle(zone_card):
			for c: int in zone_card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return 3000 * colors.size()


func _count_zone_colors(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if not zone_card.is_empty() and CardUtils.is_battle(zone_card):
			for c: int in zone_card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return colors.size()
