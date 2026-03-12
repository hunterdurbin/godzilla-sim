extends CardEffect

## EBP02-042: Gigan(1972) - Monster Rank 2 (Green)
## <Enter> You may discard a card with <King Ghidorah> or <Megalon> from your hand
## to reduce your opponent's <Rage> by 2.
## At the beginning of your end phase, if your opponent's monster card is in zone 1-5,
## increase this card's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "weakens_opponent"]


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			var traits: Array = card.get("traits", [])
			return CardEnums.CardTrait.KING_GHIDORAH in traits or CardEnums.CardTrait.MEGALON in traits,
		"Discard a King Ghidorah or Megalon card to reduce opponent's rage by 2 (or skip):",
		true)

	if not selected.is_empty():
		if ctx.opponent.rage > 0:
			var old_rage: int = ctx.opponent.rage
			ctx.opponent.rage = max(0, ctx.opponent.rage - 2)
			ctx.opponent.rage_changed.emit(ctx.opponent.rage)
			await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.END, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.END:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	if ctx.opponent.monster_zone <= 5:
		var old_rage: int = ctx.owner.rage
		ctx.owner.rage += 1
		ctx.owner.rage_changed.emit(ctx.owner.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
