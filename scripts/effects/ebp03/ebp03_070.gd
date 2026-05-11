extends CardEffect
# Mechagodzilla Hangar (Strategy R5)
# <Base> When any monster card invades into zones 6–8, <Destroy> this card. (Cards with
# Base are not sent to the discard pile at the start phase.)
# <Your Turn> At the beginning of your counter phase, search your deck for up to 1
# battle card with <《Weapon》> or <《Mech》> , reveal it, add it to your hand, then
# shuffle your deck.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["searches_deck"]


func is_base_strategy() -> bool:
	return true


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card):
			if not CardUtils.is_battle(card):
				return false
			return CardUtils.has_any_trait(card, [CardEnums.CardTrait.WEAPON, CardEnums.CardTrait.MECH]),
		tr("STR_EFF_EBP03_070_SEARCH")
	)
	if not found.is_empty():
		ctx.owner.hand.append(found)
		ctx.owner.hand_changed.emit()
