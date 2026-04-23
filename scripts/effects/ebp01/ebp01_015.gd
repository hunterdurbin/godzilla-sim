extends CardEffect

## EBP01-015: Godzilla(Fest Godzilla) - Monster Rank 4
## <Your Turn> <Enter> Reveal the top 5 cards of your deck and send them to your discard pile.
## For each monster card revealed this way, increase this card's <Rage> by 1.
## If a card with <Step2> (invasion_icon >= 2) is revealed this way, this card advances to zone 6.
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
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var revealed: Array[Dictionary] = []
	for _i in range(5):
		if ctx.owner.main_deck.is_empty():
			break
		revealed.append(ctx.owner.main_deck.pop_front())
	ctx.owner.deck_changed.emit()

	if revealed.is_empty():
		return

	# Show revealed cards to the player
	await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, revealed, revealed,
		"Revealed from deck (select any to confirm):")

	# Send all revealed to discard
	ctx.owner.discard_pile.append_array(revealed)
	ctx.owner.discard_changed.emit()

	var monster_count: int = 0
	var has_step2: bool = false
	for card in revealed:
		if CardUtils.is_monster(card):
			monster_count += 1
		if card.get("invasion_icon", 0) >= 2:
			has_step2 = true

	if monster_count > 0:
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, monster_count)

	if has_step2 and ctx.owner.monster_zone < 6:
		await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, 6)
