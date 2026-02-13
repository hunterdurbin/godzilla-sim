class_name GameState
extends RefCounted

signal phase_changed(phase: CardEnums.GamePhase)
signal turn_changed(player_id: int)
signal game_over(winner_id: int, reason: String)

var players: Array[PlayerState] = []
var current_player_id: int = 0
var current_phase: CardEnums.GamePhase = CardEnums.GamePhase.START
var turn_number: int = 0
var player_names: Array[String] = ["Player 1", "Player 2"]


func _init() -> void:
	players = [PlayerState.new(0), PlayerState.new(1)]


func get_current_player() -> PlayerState:
	return players[current_player_id]


func get_opponent_of_current() -> PlayerState:
	return players[1 - current_player_id]


func get_opponent(player_id: int) -> PlayerState:
	return players[1 - player_id]
