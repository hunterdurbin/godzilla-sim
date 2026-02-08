extends CardEffect

## EBP02-080: Joint Struggle - Strategy Rank 6 (White)
## Reveal the top 2 cards of your deck. If they differ in at least 1 trait,
## add them to your hand; otherwise, send them to the discard pile.


func on_enter(ctx: EffectContext) -> void:
	var revealed: Array[Dictionary] = []
	for _i in range(2):
		if ctx.owner.main_deck.is_empty():
			break
		revealed.append(ctx.owner.main_deck.pop_front())
	ctx.owner.deck_changed.emit()

	if revealed.size() < 2:
		# Not enough cards — send whatever was revealed to discard
		if not revealed.is_empty():
			ctx.owner.discard_pile.append_array(revealed)
			ctx.owner.discard_changed.emit()
		return

	# Check if they differ in at least 1 trait
	var traits_a: Array = revealed[0].get("traits", [])
	var traits_b: Array = revealed[1].get("traits", [])

	var differ: bool = false
	# Check if either card has a trait the other doesn't
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
		ctx.owner.discard_pile.append_array(revealed)
		ctx.owner.discard_changed.emit()
