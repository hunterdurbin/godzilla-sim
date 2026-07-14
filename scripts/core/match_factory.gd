class_name MatchFactory
extends RefCounted

## Builds and wires a match: constructs the logic components (GameState,
## RulesEngine, ActionHandler, EffectHandler, GameEvents, PlayerInput) and
## populates the starting state — from a deck selection (setup) or a saved
## snapshot (setup_from_save). TurnManager keeps thin entry points that
## delegate here, so session callers are unaffected.


static func setup(tm: TurnManager, card_data_node: Node, config: SessionConfig = null) -> void:
	tm.session_config = config if config else SessionConfig.from_singletons()
	_build_components(tm)

	for i in range(2):
		tm.game_state.player_names[i] = str(tm.session_config.player_names[i])

	# Set up each player's deck (per-player selection or fallback)
	for i in range(2):
		var player := tm.game_state.players[i]
		var deck: Dictionary = tm.session_config.decks[i]
		if not deck.is_empty():
			player.monster_deck = deck["monster_deck"].duplicate(true)
			player.main_deck = deck["main_deck"].duplicate(true)
		else:
			player.monster_deck = card_data_node.get_monster_deck(CardEnums.CardTrait.GODZILLA)
			player.main_deck = card_data_node.get_main_deck(i)
		player.main_deck.shuffle()

	# Apply per-format card printing (e.g. Rumble East uses the JP traits). Resolved
	# here, per-match, because the active format isn't known when decks are built.
	var printing := CardData.printing_for_mode(tm.session_config.game_mode)
	for player in tm.game_state.players:
		for c in player.monster_deck:
			CardData.apply_printing(c, printing)
		for c in player.main_deck:
			CardData.apply_printing(c, printing)

	# Place Rank I monsters as invading monsters at zone 1
	for player in tm.game_state.players:
		for m in player.monster_deck:
			if m.get("rank") == 1:
				player.current_monster = m
				player.monster_deck.erase(m)
				break
		player.monster_zone = player.current_monster.get("start_zone", 1)
		player.rage = 0

	# Draw 5 cards each
	for player in tm.game_state.players:
		player.draw_cards(5)

	_connect_turn_manager(tm)


static func setup_from_save(tm: TurnManager, data: Dictionary) -> void:
	## Restore a game from a saved state dictionary.
	_build_components(tm)

	# Restore game-level state
	tm.game_state.turn_number = data.get("turn_number", 1)
	tm.game_state.current_player_id = data.get("current_player_id", 0)
	tm.game_state.current_phase = data.get("current_phase", CardEnums.GamePhase.START) as CardEnums.GamePhase
	tm.game_state.current_sub_phase = data.get("current_sub_phase", 0)
	var pn: Array = data.get("player_names", ["Player 1", "Player 2"])
	tm.game_state.player_names = [str(pn[0]) if pn.size() > 0 else "Player 1", str(pn[1]) if pn.size() > 1 else "Player 2"]

	# Restore player states
	var players_data: Array = data.get("players", [])
	for i in range(2):
		if i < players_data.size():
			tm.game_state.players[i] = GameSerializer.deserialize_to_player_state(players_data[i])

	# Register effects for all cards currently on the field, restoring any
	# serialized turn-scoped effect member state (see CardEffect.serialize_state).
	for i in range(2):
		var player := tm.game_state.players[i]
		var effect_state: Dictionary = players_data[i].get("effect_state", {}) if i < players_data.size() else {}
		for zone_stack in player.zones:
			for card in zone_stack:
				_register_field_effect(tm, card, effect_state)
		for strat in player.strategy_zones:
			if strat is Dictionary and not strat.is_empty():
				_register_field_effect(tm, strat, effect_state)
		if not player.current_monster.is_empty():
			_register_field_effect(tm, player.current_monster, effect_state)

	_connect_turn_manager(tm)


static func _register_field_effect(tm: TurnManager, card: Dictionary, effect_state: Dictionary) -> void:
	var effect: CardEffect = tm.effect_handler.get_effect(card)
	if effect == null:
		return
	var saved: Variant = effect_state.get(card.get("id", ""), {})
	if saved is Dictionary and not (saved as Dictionary).is_empty():
		effect.restore_state(saved)


static func _build_components(tm: TurnManager) -> void:
	tm.game_state = GameState.new()
	tm.rules_engine = RulesEngine.new()
	tm.action_handler = ActionHandler.new()
	tm.effect_handler = EffectHandler.new()
	if tm.player_input == null:
		tm.player_input = SignalPlayerInput.new()
	tm.events = GameEvents.new()
	tm.effect_handler.setup(tm.game_state, tm.player_input)
	tm.effect_handler.action_handler = tm.action_handler
	tm.action_handler.effect_handler = tm.effect_handler
	tm.action_handler.input = tm.player_input
	tm.action_handler.events = tm.events
	tm.effect_handler.events = tm.events
	tm.rules_engine.queries = tm.effect_handler.queries


static func _connect_turn_manager(tm: TurnManager) -> void:
	tm.game_state.game_over.connect(tm._on_game_over)
	# Recheck valid actions when hand changes during main phase
	for player in tm.game_state.players:
		player.hand_changed.connect(tm._on_hand_changed)
	tm.game_started.emit()
