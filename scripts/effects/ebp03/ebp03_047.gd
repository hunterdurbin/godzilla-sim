extends CardEffect
# Garuda (Battle R5)
# At the beginning of your counter phase, if this card is in the same column as your
# opponent’s monster card, you may discard 1 battle card with <《Weapon》> or <《Mech》>
# from your hand. If you do, search your deck for up to 1 battle card named “Super
# Mechagodzilla”, play it on top of this card, then shuffle your deck.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "plays_other_cards", "column_dependent_monster"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	if opp_monster_idx not in get_opponent_column_zones(zone_idx):
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card):
			if not CardUtils.is_battle(card):
				return false
			return CardUtils.has_any_trait(card, [CardEnums.CardTrait.WEAPON, CardEnums.CardTrait.MECH]),
		tr("STR_EFF_EBP03_047_PROMPT"),
		true
	)
	if selected.is_empty():
		return

	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card): return card.get("name", "") == "Super Mechagodzilla" and CardUtils.is_battle(card),
		tr("STR_EFF_EBP03_047_SEARCH")
	)
	if found.is_empty():
		return

	# Play on top of this card in the same zone (intentional stack — no overload)
	ctx.owner.push_zone_card(zone_idx, found)
	ctx.owner.zones_changed.emit()
	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, found, true)
	await ctx.effect_handler.trigger_battle_card_played(ctx.owner.player_id, found, zone_idx, true)
	# Note: trigger_enter defers on_enter to pending queue; trigger_battle_card_played
	# also defers — both resolve correctly after this callback via _resolve_standby_entries.
