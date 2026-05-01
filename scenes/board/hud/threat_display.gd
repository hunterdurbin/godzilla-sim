extends BoundLabel

## Drop-in threat-level display. Threat = base + rage*5000 + modifiers
## (per the rules engine). BoundLabel handles binding; we just render.

@export var format_string: String = "Threat: %d"


func _refresh(session: GameSession, player: PlayerState) -> void:
	var base_threat: int = player.current_monster.get("threat", 0) if not player.current_monster.is_empty() else 0
	var threat: int = base_threat + player.rage * 5000
	if session.is_running() and session.effect_handler:
		threat += session.effect_handler.get_threat_level_modifier(player.player_id)
	elif player.player_id < session.client_threat_modifiers.size():
		threat += int(session.client_threat_modifiers[player.player_id])
	text = format_string % threat
