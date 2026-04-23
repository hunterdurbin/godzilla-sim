extends CardEffect

## ESD01-014: Godzilla Emerges - Strategy Rank 6
## If your monster card has 2 or more <Rage>, search your deck for up to 1 battle card
## named Godzilla(2023), play it, then shuffle your deck.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.rage >= 2


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.rage < 2:
		return

	var player := ctx.owner

	var selected := await ctx.effect_handler.search_deck(
		player.player_id,
		func(card: Dictionary) -> bool:
			return card.get("name", "") == "Godzilla(2023)" \
				and CardUtils.is_battle(card),
		"Search for a Godzilla(2023) battle card to play"
	)
	if not selected.is_empty():
		var valid_zones := CardEffect.get_effect_play_zones(player)

		var target_zone: int = await ctx.effect_handler.select_zone_target(
			player.player_id, player.player_id, valid_zones,
			"Choose a zone to play the searched card:")
		if target_zone < 0:
			return

		await ctx.effect_handler.play_battle_card_from_deck(player.player_id, selected, target_zone)
