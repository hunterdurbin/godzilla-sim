extends BoundLabel

@export var format_string: String = "Deck: %d"


func _refresh(_session: GameSession, player: PlayerState) -> void:
	text = format_string % player.main_deck.size()
