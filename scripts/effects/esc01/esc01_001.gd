extends CardEffect

## ESC01-001: Godzilla(1954) - Battle Rank 8 (Red)
## When playing this from your hand, if you discard a <Godzilla> card from your hand
## you can play this card at a -4 rank. (Afterwards it's a Rank 8).
## If this is in the same column as your opponent's Monster card this gains +3000 counter power.
## When you successfully counter your opponent's Monster card, place this at the bottom of your deck.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "column_dependent_monster", "heals_deck"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	# Only modifies self
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	# Offer -4 rank if player has another Godzilla card in hand to discard
	if _has_godzilla_in_hand(ctx):
		return -4
	return 0


func apply_play_cost(ctx: EffectContext, _zone_index: int) -> bool:
	# If the card can be played at base rank (8) without the cost, skip the prompt
	# Only prompt if the rank reduction is needed (player chose a zone requiring it)
	# The rank reduction is always -4, so effective rank is 4
	# If opponent monster zone >= 8, the card is playable without cost
	if ctx.card_data.get("rank", 99) <= ctx.opponent.monster_zone:
		return true
	# Need the -4 reduction — must discard a Godzilla card
	if not _has_godzilla_in_hand(ctx):
		return false
	var filter := func(card: Dictionary) -> bool:
		return CardEnums.CardTrait.GODZILLA in card.get("traits", [])
	var discarded := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id, filter, tr("STR_EFF_ESC01_001_PROMPT"), true)
	# If player skipped or no valid card, cancel the play
	return not discarded.is_empty()


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if _is_in_opponent_monster_column(ctx):
		return 3000
	return 0


func on_counter_success(ctx: EffectContext) -> void:
	# Place this card at the bottom of your deck
	ctx.effect_handler.move_zone_card_to_deck_bottom(ctx.owner, ctx.card_data)


func _has_godzilla_in_hand(ctx: EffectContext) -> bool:
	# Check if the player has a Godzilla card in hand (not counting this card itself)
	var self_id: String = ctx.card_data.get("id", "")
	for card in ctx.owner.hand:
		if card.get("id", "") == self_id:
			continue
		if CardEnums.CardTrait.GODZILLA in card.get("traits", []):
			return true
	return false


func _is_in_opponent_monster_column(ctx: EffectContext) -> bool:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return false
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	if opp_monster_idx < 0:
		return false
	var facing_zones := get_opponent_column_zones(zone_idx)
	return opp_monster_idx in facing_zones
