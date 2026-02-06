class_name EffectContext
extends RefCounted

## Context bundle passed to all CardEffect trigger methods.
## Provides access to game state, the card's owner, opponent, and the triggering card.

var game_state: GameState
var owner: PlayerState
var opponent: PlayerState
var card_data: Dictionary
var effect_handler: EffectHandler


static func create(
	p_game_state: GameState,
	owner_id: int,
	p_card_data: Dictionary,
	p_effect_handler: EffectHandler
) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.game_state = p_game_state
	ctx.owner = p_game_state.players[owner_id]
	ctx.opponent = p_game_state.players[1 - owner_id]
	ctx.card_data = p_card_data
	ctx.effect_handler = p_effect_handler
	return ctx
