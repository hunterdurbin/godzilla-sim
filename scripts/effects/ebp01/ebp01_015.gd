extends CardEffect

## EBP01-015: Godzilla(Fest Godzilla) - Monster Rank 4
## <Your Turn> <Enter> Reveal the top 5 cards of your deck and send them to your discard pile.
## For each monster card revealed this way, increase this card's <Rage> by 1.
## If a card with <Step2> (invasion_icon >= 2) is revealed this way, this card advances to zone 6.


func on_enter(ctx: EffectContext) -> void:
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var milled: Array[Dictionary] = ctx.owner.mill_cards(5)
	var monster_count: int = 0
	var has_step2: bool = false
	for card in milled:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			monster_count += 1
		if card.get("invasion_icon", 0) >= 2:
			has_step2 = true

	if monster_count > 0:
		ctx.owner.rage += monster_count
		ctx.owner.rage_changed.emit(ctx.owner.rage)

	if has_step2 and ctx.owner.monster_zone < 6:
		ctx.owner.monster_zone = 6
		ctx.owner.monster_changed.emit()
