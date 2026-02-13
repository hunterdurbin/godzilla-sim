extends CardEffect

## EBP02-028: Biollante Plant Beast Form - Monster Rank 4 (Blue)
## <Enter> Play as many rank 4 or lower battle cards with <Evolution> from your
## discard pile to each of this card's adjacent zones. (You must play as many as
## possible and you may play the battle cards in zones already occupied by other
## battle cards. Maximum of 3 cards.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


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
		if card.get("card_type") != CardEnums.CardType.BATTLE:
			continue
		if card.get("rank", 99) > 4:
			continue
		if card.get("evolution_rank", -1) < 0:
			continue
		matching.append(card)

	if matching.is_empty():
		return

	# Play as many as possible to adjacent zones (max 3)
	var placed: int = 0
	for zi in adjacent:
		if placed >= 3 or matching.is_empty():
			break
		var card: Dictionary = matching.pop_front()
		await ctx.effect_handler.play_from_discard(ctx.owner.player_id, card, zi)
		placed += 1
