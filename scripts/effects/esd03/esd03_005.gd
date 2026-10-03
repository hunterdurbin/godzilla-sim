extends CardEffect

## ESD03-005: Godzilla(2026) - Monster Rank 4 (Red)
## If there is a rank IV monster card underneath this, add +15,000 threat.
## At the beginning of your end phase, if this has 3 or more <Rage>, you may
## advance 1 zone.
## <Awakening 8> This card gains +15,000 threat.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: "Underneath" checks the whole monster_stack, not just
##   the card directly below. The end-phase advance is skipped at zone 8
##   (same guard as EBP03-001).


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.END, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["advances_self", "boosts_threat"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, _effect_handler = null) -> bool:
	return owner.rage >= 3 and not owner.is_awakening(8)


func bot_can_fulfill_threat_level(owner: PlayerState, _opponent: PlayerState) -> bool:
	return _has_rank4_underneath(owner) or owner.is_awakening(8)


func get_threat_level_modifier(ctx: EffectContext) -> int:
	var bonus: int = 0
	if _has_rank4_underneath(ctx.owner):
		bonus += 15000
	if ctx.is_awakening(8):
		bonus += 15000
	return bonus


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if ctx.owner.rage < 3 or ctx.is_awakening(8):
		return
	var choice: int = await ctx.effect_handler.select_choice(
		ctx.owner.player_id,
		[tr("STR_EFF_BTN_YES"), tr("STR_EFF_BTN_NO")],
		tr("STR_EFF_ESD03_005_PROMPT"))
	if choice != 0:
		return
	await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, ctx.owner.monster_zone + 1)


func _has_rank4_underneath(owner: PlayerState) -> bool:
	for card in owner.monster_stack:
		if CardUtils.is_monster(card) and int(card.get("rank", 0)) == 4:
			return true
	return false
