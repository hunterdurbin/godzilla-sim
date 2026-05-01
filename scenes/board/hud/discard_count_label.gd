extends BoundLabel

@export var format_string: String = "Discard: %d"


func _refresh(_session: GameSession, player: PlayerState) -> void:
	text = format_string % player.discard_pile.size()
