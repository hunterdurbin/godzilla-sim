extends CardEffect

## EBP01-015: Godzilla(Fest Godzilla) - Monster Rank 4
## <Your Turn> <Enter> Reveal the top 5 cards of your deck and send them to your discard
## pile. For each monster card revealed this way, increase this card's <Rage> by 1. If a
## card with <Step2> is revealed this way, this card advances to zone 6.
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


func on_enter(ctx: EffectContext) -> void:
	if ctx.is_opponent_turn():
		return

	var revealed := await ctx.effect_handler.reveal_deck_top(ctx.owner.player_id, 5)
	if revealed.is_empty():
		return
	ctx.effect_handler.discard_cards(ctx.owner.player_id, revealed)

	var monster_count: int = 0
	var has_step2: bool = false
	for card in revealed:
		if CardUtils.is_monster(card):
			monster_count += 1
		if card.get("invasion_icon", 0) >= 2:
			has_step2 = true

	if monster_count > 0:
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, monster_count, ctx.card_data.get("id", ""))

	if has_step2 and not ctx.is_awakening(6):
		await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, 6)
