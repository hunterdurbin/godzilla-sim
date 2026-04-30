extends CardEffect
## EBP04-028: Gigan (2004) - Monster Rank 2 (Green)
## <Opponent's Turn> All strategy cards of your opponent gain +3 in rank. (After
## play, they are returned to their original ranks)
## <Opponent's Turn> Each time your opponent plays a battle card from their
## main deck, your opponent discards 1 card from their hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_battle_card_played": {"own_turn": false, "played_by_opponent": true, "played_from_deck": true},
}


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


func on_battle_card_played(ctx: EffectContext, _zone_index: int, _played_from_deck: bool = false) -> void:
	# Discard exactly 1 card from opponent's hand. discard_hand_to handles the
	# "hand smaller than target" case (no-op if hand is empty).
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, ctx.opponent.hand.size() - 1)
