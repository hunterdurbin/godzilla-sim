extends CardEffect

## EBP02-052: SpaceGodzilla Flying Form - Monster Rank 1 (Green)
## <When Invading> You may discard 1 card from your hand, if you do, play 1 “Crystals”
## token. (Tokens are prepared separately from your deck.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if ctx.owner.hand.is_empty():
		return

	# Let the player choose a card to discard (any card, optional)
	var selected: Dictionary = await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(_card: Dictionary) -> bool: return true,
		tr("STR_EFF_EBP02_052_PROMPT"),
		true)

	if selected.is_empty():
		return

	# Place a Crystals token in an empty zone
	await ctx.effect_handler.create_tokens_in_zones(ctx.owner, "EBP02-T03", 1)
