extends CardEffect

## EBP02-014: Cabinet Helicopter - Battle Rank 6 (Red)
## <Enter> Send the top card of your deck to your discard pile.
## If it is a monster card, advance your monster card to zone 6.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self", "advances_self"]


func get_bot_max_advance_zone(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func get_bot_advance_reliability(owner: PlayerState, _opponent: PlayerState) -> int:
	if owner.main_deck.is_empty():
		return 0
	var monster_count: int = 0
	for card in owner.main_deck:
		if CardUtils.is_monster(card):
			monster_count += 1
	return int(float(monster_count) / float(owner.main_deck.size()) * 100.0)


func on_enter(ctx: EffectContext) -> void:
	var card := await ctx.mill_one()
	if card.is_empty():
		return

	if CardUtils.is_monster(card):
		if ctx.owner.monster_zone < 6:
			await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, 6)
