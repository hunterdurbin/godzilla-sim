extends CardEffect

## EBP02-080: Joint Struggle - Strategy Rank 6 (White)
## Reveal the top 2 cards of your deck. If they differ in at least 1 trait, add them to
## your hand; otherwise, send them to the discard pile. (Example if one is <《Mech》> and
## the other is <《Mechagodzilla》> and <《Mech》> , you may add them to your hand.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.main_deck.size() >= 2


func on_enter(ctx: EffectContext) -> void:
	var revealed := await ctx.effect_handler.reveal_deck_top(ctx.owner.player_id, 2)
	if revealed.size() < 2:
		# Not enough cards — send whatever was revealed to discard
		ctx.effect_handler.discard_cards(ctx.owner.player_id, revealed)
		return

	# Check if they differ in at least 1 trait
	# A card with no traits (e.g. strategy) cannot "differ in a trait" — both go to discard
	var traits_a: Array = revealed[0].get("traits", [])
	var traits_b: Array = revealed[1].get("traits", [])

	var differ: bool = false
	if not traits_a.is_empty() and not traits_b.is_empty():
		for t in traits_a:
			if t not in traits_b:
				differ = true
				break
		if not differ:
			for t in traits_b:
				if t not in traits_a:
					differ = true
					break

	if differ:
		ctx.owner.hand.append_array(revealed)
		ctx.owner.hand_changed.emit()
	else:
		ctx.effect_handler.discard_cards(ctx.owner.player_id, revealed)
