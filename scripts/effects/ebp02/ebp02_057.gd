extends CardEffect

## EBP02-057: SpaceGodzilla Flying Form - Monster Rank 4 (Green)
## <Enter> Move 1 of your opponent's battle cards in the same column as this card
## to an unoccupied zone.
## Whenever this card's <Rage> is increased, play 2 "Crystals" tokens.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_rage_changed": {"direction": "increase"},
}


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var opp_columns := get_opponent_column_zones(monster_zone_idx)

	# Find opponent's battle cards in same column
	var targetable: Array[int] = []
	for zi in opp_columns:
		if ctx.opponent.zone_has_cards(zi):
			targetable.append(zi)

	if targetable.is_empty():
		return

	var source: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, targetable,
		tr("STR_EFF_MOVE_OPP_SAME_COLUMN"), true)
	if source < 0:
		return

	var empty := ctx.opponent.get_empty_zone_indices()
	if empty.is_empty():
		return

	var dest: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, empty,
		tr("STR_EFF_MOVE_UNOCCUPIED"))
	if dest < 0:
		return

	var stack: Array = ctx.opponent.zones[source]
	ctx.opponent.zones[source] = []
	ctx.opponent.zones[dest] = stack
	ctx.opponent.zones_changed.emit()


func on_rage_changed(ctx: EffectContext, _old_rage: int, _new_rage: int) -> void:
	await ctx.effect_handler.create_tokens_in_zones(ctx.owner, "EBP02-T03", 2)
