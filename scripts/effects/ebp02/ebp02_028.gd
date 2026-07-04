extends CardEffect

## EBP02-028: Biollante Plant Beast Form - Monster Rank 4 (Blue)
## <Enter> Play as many rank 4 or lower battle cards with <Evolution> from your
## discard pile to each of this card's adjacent zones. (You must play as many as
## possible and you may play the battle cards in zones already occupied by other
## battle cards. Maximum of 3 cards.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard"]


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	if monster_zone_idx < 0:
		return

	var adjacent := get_adjacent_zones(monster_zone_idx)
	if adjacent.is_empty():
		return

	# Collect rank 4 or lower battle cards with Evolution from discard pile
	var matching: Array[Dictionary] = []
	for card in ctx.owner.discard_pile:
		if not CardUtils.is_battle(card):
			continue
		if card.get("rank", 99) > 4:
			continue
		if card.get("evolution_rank", -1) < 0:
			continue
		matching.append(card)

	if matching.is_empty():
		return

	# Play as many as possible (max 3) from discard into adjacent zones, each in a
	# different zone per rule 5.11.1.3.
	await ctx.effect_handler.play_battle_cards_in_zones(
		ctx.owner, matching, tr("STR_EFF_EBP02_028_SELECT"), adjacent, true, 3)
