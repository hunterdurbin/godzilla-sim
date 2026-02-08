extends CardEffect

## EBP01-012: Godzilla(Fest Godzilla) - Monster Rank 2
## At the beginning of your end phase, if this card invaded this turn,
## advance your opponent's monster card by 1 zone.


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.END:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	if not ctx.owner.has_invaded_this_turn:
		return
	if ctx.opponent.monster_zone < 8:
		ctx.opponent.monster_zone += 1
		ctx.opponent.monster_changed.emit()
