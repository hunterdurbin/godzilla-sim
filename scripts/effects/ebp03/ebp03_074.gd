extends CardEffect

## EBP03-074: A Journey of 130 Million Years - Strategy Rank 6 (Blue)
## If your monster card is rank III or lower, play 1 monster card from your monster deck
## that shares a trait with it, whose rank is 1 higher than your monster card's current rank.
## (This play does not increase Rage.)


func on_enter(ctx: EffectContext) -> void:
	var cur_rank: int = ctx.owner.current_monster.get("rank", 0)
	if cur_rank > 3:
		return

	var cur_traits: Array = ctx.owner.current_monster.get("traits", [])
	var next_rank: int = cur_rank + 1

	# Find the next rank monster sharing a trait in the monster deck
	var found_monster: Dictionary = {}
	for m in ctx.owner.monster_deck:
		if m.get("rank") == next_rank:
			for t in m.get("traits", []):
				if t in cur_traits:
					found_monster = m
					break
		if not found_monster.is_empty():
			break

	if found_monster.is_empty():
		return

	# Play monster from effect (no rage increase)
	if ctx.effect_handler.action_handler:
		await ctx.effect_handler.action_handler.play_monster_from_effect(
			ctx.game_state, ctx.owner.player_id, found_monster)
