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
## Implementation notes: "If you do, <Destroy>…" is per-copy state, but
## CardEffect instances are cached per script path (shared across copies and
## players), so the used-my-ability flag lives on the card dict itself
## (per-copy, serialized/synced with the zone — same pattern as
## played_from_effect), stamped with the turn number so a stale flag on a
## copy destroyed before its end phase and later replayed is inert. Keying
## off stack size instead would misfire if a future effect tucks cards under
## other cards.


const TRIGGER_FILTERS = {
	# No "phase" key: this one method must fire at both COUNTER and END
	# starts, branching on the phase argument inside.
	"on_phase_start": {"own_turn": true},
}

## Card-dict key: turn number in which this copy tucked a card via its own
## ability — the end-phase destroy trigger only exists while it matches.
const _DESTROY_TURN_KEY := "pending_end_phase_destroy_turn"


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func phase_start_applies(ctx: EffectContext, phase: CardEnums.GamePhase) -> bool:
	## "If you do, <Destroy>…" — the end-phase trigger only exists for a copy
	## whose ability tucked a card this turn; any other copy must not show up
	## in the standby batch (pending-effects list / order-choice prompt).
	if phase != CardEnums.GamePhase.END:
		return true
	return _used_ability_this_turn(ctx)


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
		ctx.card_data[_DESTROY_TURN_KEY] = ctx.game_state.turn_number


func _used_ability_this_turn(ctx: EffectContext) -> bool:
	# int() coercion: card dicts may round-trip through JSON (multiplayer).
	return int(ctx.card_data.get(_DESTROY_TURN_KEY, -1)) == ctx.game_state.turn_number


func _destroy_if_loaded(ctx: EffectContext) -> void:
	if not _used_ability_this_turn(ctx):
		return
	ctx.card_data.erase(_DESTROY_TURN_KEY)
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
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
