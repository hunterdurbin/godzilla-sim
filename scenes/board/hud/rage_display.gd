extends BoundLabel

## Drop-in rage display. Subscribes via BoundLabel's auto-bind to the
## seat-resolved player's PlayerState and refreshes on any change.

@export var format_string: String = "Rage: %d"


func _refresh(_session: GameSession, player: PlayerState) -> void:
	text = format_string % player.rage
