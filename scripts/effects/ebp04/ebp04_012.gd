extends CardEffect
## EBP04-012: Biollante Plant Beast Form - Monster Rank 3 (Blue)
## You may play this card from your hand by placing 1 rank III card from your monster
## deck under one of your rank II  《Biollante》 monster cards. (You may play this card
## from rank II.)
## <Enter> Play “Tentacles” tokens in all zones adjacent to this card. (Tokens are
## prepared separately from your deck and must be played as many as possible. Maximum of
## 3.)
##
## Tested: Yes
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
	if not CardUtils.has_trait(ctx.owner.current_monster, CardEnums.CardTrait.BIOLLANTE):
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
		ctx.owner.player_id, rank3_cards, ctx.owner.monster_deck,
		tr("STR_EFF_EBP04_012_PROMPT"), 1)
	if chosen.is_empty():
		return false
	var placed: Dictionary = chosen[0]
	ctx.owner.monster_deck.erase(placed)
	ctx.owner.monster_stack.push_back(placed)
	return true


func on_enter(ctx: EffectContext) -> void:
	var monster_idx: int = ctx.owner.monster_zone - 1
	var valid_adjacent := CardEffect.get_effect_play_adjacent_zones(ctx.owner, monster_idx)
	if valid_adjacent.is_empty():
		return
	# Player chooses an adjacent zone for each Tentacles token (max 3, capped by
	# the natural adjacency count). Mirrors the pattern in EBP02-035.
	var to_place: int = mini(valid_adjacent.size(), 3)
	for _i in range(to_place):
		if valid_adjacent.is_empty():
			break
		var remaining: int = to_place - _i
		var chosen: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, valid_adjacent,
			tr("STR_EFF_EBP02_035_TOKEN_FMT") % remaining)
		if chosen < 0:
			break
		await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP02-T02", chosen)
		# Rule 5.11.1.3: must play to different zones if possible
		valid_adjacent.erase(chosen)
