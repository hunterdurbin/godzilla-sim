extends CardEffect

## EBP02-077: Chibi Godzilla - Battle Rank 6 (White)
## At the beginning of your main phase, send the top 2 cards of your deck to your
## discard pile.
## If a <《Godzilla》> card was sent to your discard pile this way, <Destroy> this card
## and play a “Chibi Godzilla 2nd Form” token. (Tokens are prepared separately from your
## deck.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.MAIN, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["mill_self", "plays_other_cards"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var milled_cards := await ctx.mill(2)
	var found_godzilla: bool = false
	for card in milled_cards:
		if CardUtils.has_trait(card, CardEnums.CardTrait.GODZILLA):
			found_godzilla = true
			break

	if not found_godzilla:
		return

	# Destroy self (this card is a normal battle card, goes to discard)
	var stack: Array = ctx.owner.clear_zone(zone_idx)
	EffectHandler.banish_or_discard(ctx.owner, stack)
	ctx.owner.zones_changed.emit()
	ctx.owner.discard_changed.emit()

	# Player picks any non-monster zone for the token (defaults to the now-
	# empty zone if no UI is wired up).
	var monster_idx: int = ctx.owner.monster_zone - 1
	var valid_zones: Array[int] = []
	for i in range(8):
		if i != monster_idx:
			valid_zones.append(i)
	var target_zone: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		tr("STR_EFF_EBP02_T04_PROMPT"), false, "EBP02-T04")
	if target_zone < 0:
		target_zone = zone_idx
	await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP02-T04", target_zone)
