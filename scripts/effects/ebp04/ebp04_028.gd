extends CardEffect
## EBP04-028: Gigan (2004) - Monster Rank 2 (Green)
## <Opponent's Turn> All strategy cards of your opponent gain +3 in rank. (After
## play, they are returned to their original ranks)
## <Opponent's Turn> Each time your opponent plays a battle card from their
## main deck, your opponent discards until they have 1 card remaining in their
## hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand", "weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_strategy_hand_rank_modifier(ctx: EffectContext, _card: Dictionary, target_player_id: int) -> int:
	# Only affects the opponent's strategies, only on the opponent's turn
	if ctx.is_owner(target_player_id):
		return 0
	if not ctx.is_turn(target_player_id):
		return 0
	return 3


func on_battle_card_played(ctx: EffectContext, _zone_index: int, played_from_deck: bool = false) -> void:
	# <Opponent's Turn> Each time opp plays a battle card from their main deck → discard to 1
	if ctx.is_own_turn():
		return
	if not played_from_deck:
		return
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 1)
