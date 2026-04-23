extends CardEffect

## EBP02-039: Lake Ashi Monster - Strategy Rank 5 (Blue)
## <Your Turn> You can play battle cards with <Biollante> from your hand with
## their rank reduced by 3. (They return to their original rank after being played.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	# <Your Turn> — only active during owner's turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	# Only for battle cards
	if not CardUtils.is_battle(target_card):
		return 0
	# Only for cards with the Biollante trait
	if not CardUtils.has_trait(target_card, CardEnums.CardTrait.BIOLLANTE):
		return 0
	return -3
