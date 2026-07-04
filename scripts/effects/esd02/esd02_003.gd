extends CardEffect

## ESD02-003: Godzilla(1992) - Monster Rank 3
## <Enter> :Play 2 rank 4 or lower battle cards with <Evolution> from your discard pile
## in zones adjacent to this card.
## (For example, if this card is in zone 7, the adjacent zones are 4, 6, and 8.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	var monster_zone_idx: int = owner.monster_zone - 1
	var valid_adjacent := CardEffect.get_effect_play_adjacent_zones(owner, monster_zone_idx)
	if valid_adjacent.is_empty():
		return false
	for card in owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.BATTLE \
			and CardUtils.rank_at_most(card, 4) \
			and card.has("evolution_rank"):
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var player := ctx.owner
	var monster_zone_idx: int = player.monster_zone - 1

	var valid_adjacent := CardEffect.get_effect_play_adjacent_zones(player, monster_zone_idx)

	if valid_adjacent.is_empty():
		return

	# Play up to 2 matching cards from discard pile
	for _i in range(2):
		# Search discard for rank 4 or lower battle cards with Evolution
		var selected := await ctx.effect_handler.search_discard(
			player.player_id,
			func(card: Dictionary) -> bool:
				if card.get("card_type") != CardEnums.CardType.BATTLE:
					return false
				if card.get("rank", 0) > 4:
					return false
				return card.has("evolution_rank"),
			tr("STR_EFF_ESD02_003_DISCARD_PROMPT")
		)
		if selected.is_empty():
			break

		# Let player choose which adjacent zone to place it in (each card in a
		# different zone per rule 5.11.1.3), listing the still-available zones.
		var zone_list: String = ", ".join(valid_adjacent.map(func(z): return str(z + 1)))
		var target_zone: int = await ctx.effect_handler.select_zone_target(
			player.player_id, player.player_id, valid_adjacent,
			tr("STR_EFF_ESD02_003_PROMPT") + " " + tr("STR_EFF_AVAILABLE_ZONES_FMT") % zone_list,
			false, CardUtils.base_id(selected))
		if target_zone < 0:
			break

		# play_from_discard handles overload (incl. leave-play triggers) and enter.
		await ctx.effect_handler.play_from_discard(player.player_id, selected, target_zone)
		valid_adjacent.erase(target_zone)
