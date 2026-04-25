class_name EffectContext
extends RefCounted

## Context bundle passed to all CardEffect trigger methods.
## Provides access to game state, the card's owner, opponent, and the triggering card.

var game_state: GameState
var owner: PlayerState
var opponent: PlayerState
var card_data: Dictionary
var effect_handler: EffectHandler
var metadata: Dictionary = {}  ## Extra data set at collection time for deferred resolution


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


func field_rank(p_card_data: Dictionary, owner_player_id: int) -> int:
	## Get the effective rank of an in-play battle card, accounting for field rank modifiers.
	return effect_handler.get_effective_field_rank(p_card_data, owner_player_id)


# --- Player identity ---

func is_owner(p_player_id: int) -> bool:
	return p_player_id == owner.player_id


func is_opponent(p_player_id: int) -> bool:
	return p_player_id == opponent.player_id


# --- Turn ownership ---

func is_own_turn() -> bool:
	return game_state.current_player_id == owner.player_id


func is_opponent_turn() -> bool:
	return game_state.current_player_id == opponent.player_id


# --- Awakening (rule-text shorthand for owner.monster_zone >= threshold) ---

func is_awakening(threshold: int) -> bool:
	return owner.is_awakening(threshold)


# --- Monster stack ---

func has_monster_stack(min_count: int) -> bool:
	return owner.has_monster_stack(min_count)


# --- Rage ---

func has_rage() -> bool:
	return owner.has_rage()


func opponent_has_rage() -> bool:
	return opponent.has_rage()
