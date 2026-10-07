extends CardEffect

## ESD03-006: Godzilla(2023) - Battle Rank 3 (Red)
## <Enter> Reduce your opponent's rank I monster card's <Rage> by 1.
## <Overwhelm> This card gains +3000 counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: Opponent's monster rank II+ → the enter effect does nothing.
## Rules: None
## Interactions: None
## Implementation notes: <Overwhelm> = ctx.is_overwhelm().

## CP modifier is placement-independent — safe to preview while in hand.
const HAND_CP_PREVIEW := true


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "weakens_opponent"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.get_monster_rank() == 1 and opponent.has_rage()


func bot_can_fulfill_counter_power(owner: PlayerState, opponent: PlayerState) -> bool:
	return owner.monster_zone >= opponent.monster_zone


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.get_monster_rank() == 1:
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	return 3000 if ctx.is_overwhelm() else 0
