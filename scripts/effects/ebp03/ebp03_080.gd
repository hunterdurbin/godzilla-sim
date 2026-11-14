extends CardEffect
# Odo Island (Strategy R6)
# <Base> When any monster card invades into zones 6–8, <Destroy> this card. (Cards with
# Base are not sent to the discard pile at the start phase.)
# <Your Turn> At the beginning of your counter phase, you may play up to 1 <《Godzilla》>
# battle card from your hand.
#
# Tested: Yes
# Known issues: None
# Edge cases:
#   A chosen card must pass all play restrictions (e.g. EBP01-073 can be played if and only if the card requirement is met)
# Rules: None
# Interactions: Any rank battle card can be played from this effect.
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, effect_handler = null) -> bool:
	var valid_zones := CardEffect.get_effect_play_zones(owner)
	if valid_zones.is_empty():
		return false
	for card in owner.hand:
		if CardUtils.is_battle(card) \
			and CardUtils.has_trait(card, CardEnums.CardTrait.GODZILLA):
			if effect_handler and not effect_handler.can_card_be_played(owner.player_id, card):
				continue
			return true
	return false


func is_base_strategy() -> bool:
	return true


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	# Find Godzilla battle cards in hand (respecting play restrictions)
	var selected := await ctx.effect_handler.choose_hand_card(
		ctx.owner.player_id,
		func(card):
			if not CardUtils.is_battle(card):
				return false
			if not CardUtils.has_trait(card, CardEnums.CardTrait.GODZILLA):
				return false
			return ctx.effect_handler.can_card_be_played(ctx.owner.player_id, card),
		tr("STR_EFF_EBP03_080_PROMPT"),
		true
	)
	if selected.is_empty():
		return

	var valid_zones := CardEffect.get_effect_play_zones(ctx.owner)
	var dest := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		tr("STR_EFF_PLAY_BATTLE_ZONE"), false, CardUtils.base_id(selected))
	if dest < 0:
		return

	# The engine moves it hand -> zone, overloads an occupied zone (11.5) and
	# fires <Enter> + on_battle_card_played.
	ctx.effect_handler.play_battle_card_from_hand(ctx.owner.player_id, selected, dest)
