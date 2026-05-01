extends "res://scenes/board/game_board_template.gd"

## Stub controller for the EnhancedGameBoard test scene. Inherits all
## bootstrap (TurnManager, RPCs, EffectUIRouter, overlay registration,
## menu button wiring, ActionPanel detection, PlayerBoard binding) from
## GameBoardTemplate. Designers add visual-update overrides here:
##
##   func _on_phase_started(phase: CardEnums.GamePhase) -> void:
##       # play a phase-change banner animation
##
##   func _on_turn_started(player_id: int) -> void:
##       # highlight whose turn it is
##
##   func _on_log_message(token) -> void:
##       # custom log handler (template's LogPanel still receives it)
##
## See game_board_base.gd for the full list of override hooks.
