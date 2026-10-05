extends CardEffect

## ESD03-007: Godzilla(2026) - Battle Rank 6 (Red)
## <Awakening 6> This card gains +3000 counter power.
## <Overwhelm> If your monster card invaded this turn, you may play this card
## from your hand with its rank reduced by 1. (After being played, this card is
## rank 6.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: <Overwhelm> = ctx.is_overwhelm() (own monster zone
##   >= opponent's). Rank reduction is a self play-rank modifier (EBP01-033
##   style), so it only applies while the card is played from hand.

## CP modifier is placement-independent — safe to preview while in hand.
const HAND_CP_PREVIEW := true


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func bot_can_fulfill_counter_power(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.is_awakening(6)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.is_awakening(6):
		return 3000
	return 0


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	# Only modifies self
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	if ctx.owner.has_invaded_this_turn and ctx.is_overwhelm():
		return -1
	return 0
