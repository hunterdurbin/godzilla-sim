extends CardEffect
## EBP04-012: Biollante Plant Beast Form - Monster Rank 3 (Blue)
## You may place 1 Rank III monster card from your monster deck underneath your
## Rank II <Biollante> card to play this card from your hand.
## <Enter> Place [Tentacle] tokens in every area adjacent to this card (Maximum
## is 3).
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func can_play_as_monster(ctx: EffectContext) -> bool:
	if ctx.card_data.get("played_from_effect", false):
		return false
	if ctx.owner.current_monster.get("rank", 0) != 2:
		return false
	if CardEnums.CardTrait.BIOLLANTE not in ctx.owner.current_monster.get("traits", []):
		return false
	for card in ctx.owner.monster_deck:
		if card.get("rank", 0) == 3:
			return true
	return false


func apply_play_cost(ctx: EffectContext, zone_index: int) -> bool:
	if zone_index != -1:
		return true # Not a monster alt-cost play
	var rank3_cards: Array[Dictionary] = []
	for card in ctx.owner.monster_deck:
		if card.get("rank", 0) == 3:
			rank3_cards.append(card)
	if rank3_cards.is_empty():
		return false
	var chosen := await ctx.effect_handler.select_cards_from_pool(
		ctx.owner.player_id, rank3_cards, rank3_cards,
		"Select a Rank III monster to place under Biollante:", 1)
	if chosen.is_empty():
		return false
	var placed: Dictionary = chosen[0]
	ctx.owner.monster_deck.erase(placed)
	ctx.owner.monster_stack.push_back(placed)
	return true


func on_enter(ctx: EffectContext) -> void:
	var monster_idx: int = ctx.owner.monster_zone - 1
	var adjacent := CardEffect.get_effect_play_adjacent_zones(ctx.owner, monster_idx)
	if adjacent.is_empty():
		return
	for zone_idx in adjacent:
		await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP02-T02", zone_idx)
