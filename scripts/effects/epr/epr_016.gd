extends CardEffect

## EPR-016: KIJU Type 0 -G BREAKER- - Battle Rank 7 (White)
## At the beginning of your counter phase, you may place 1 <《Mech》>, <《Weapon》>,
## or <《GODZILLA THE RIDE》> battle card from your hand under this card. If you
## do, <Destroy> this card at the beginning of the end phase.
## If there is a card under this card, this card gains +5000 counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: The end-phase self-destroy keys off "has a card under
## this card" (stack size > 1) instead of a placed-this-turn member flag:
## CardEffect instances are cached per script path and shared across copies
## and players, so per-copy flags would leak between copies. The only way a
## card ends up under this one is its own counter-phase placement earlier the
## same turn, so the two readings coincide.


const TRIGGER_FILTERS = {
	# No "phase" key: this one method must fire at both COUNTER and END
	# starts, branching on the phase argument inside.
	"on_phase_start": {"own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	match phase:
		CardEnums.GamePhase.COUNTER:
			await _offer_place_under(ctx)
		CardEnums.GamePhase.END:
			await _destroy_if_loaded(ctx)


func _offer_place_under(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var selected := await ctx.effect_handler.take_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.is_battle(card) and CardUtils.has_any_trait(card, [
				CardEnums.CardTrait.MECH,
				CardEnums.CardTrait.WEAPON,
				CardEnums.CardTrait.GODZILLA_THE_RIDE,
			]),
		tr("STR_EFF_EPR_016_PROMPT"),
		true)

	if not selected.is_empty():
		ctx.effect_handler.place_card_under_zone(ctx.owner, selected, zone_idx)


func _destroy_if_loaded(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return
	if ctx.owner.get_zone_stack(zone_idx).size() <= 1:
		return
	await ctx.effect_handler.destroy_zones(ctx.owner, [zone_idx] as Array[int])


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	# Check if there's a card under this card (stack size > 1)
	if ctx.owner.get_zone_stack(zone_idx).size() > 1:
		return 5000
	return 0
