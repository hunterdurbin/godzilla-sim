extends RefCounted

## Builders for GameState/PlayerState test fixtures.

const Cards := preload("res://tests/fixtures/cards.gd")
const _BoolAssert := preload("res://addons/gdUnit4/src/asserts/GdUnitBoolAssertImpl.gd")


## Build a two-player GameState in the MAIN phase. Options (all optional):
##   current_player_id: int (default 0)
##   turn_number: int (default 1)
##   p0/p1: Dictionary of per-player options:
##     hand: Array[Dictionary]
##     monster_zone: int (default 1) — zone index monster_zone-1 holds the
##       monster; a card placed there is crushed at the next check timing
##     current_monster: Dictionary (default rank-1 GODZILLA test monster)
##     monster_deck: Array[Dictionary] (default empty)
##     main_deck: Array[Dictionary] (default empty)
##     rage: int (default 0)
##     zone_cards: Dictionary of zone_index -> card (placed as zone top)
##     strategy_zones: Array (entries assigned in order)
##     has_invaded_this_turn / has_played_monster_this_turn: bool
##   allow_illegal: bool (default false) — the state must be legal: a card in
##     a zone its player's monster occupies fails the test (the next check
##     timing would crush it, 11.3). Set true only to test the crush itself.
static func make_state(opts: Dictionary = {}) -> GameState:
	var state := GameState.new()
	state.current_player_id = opts.get("current_player_id", 0)
	state.current_phase = CardEnums.GamePhase.MAIN
	state.turn_number = opts.get("turn_number", 1)
	for pid in range(2):
		_apply_player_opts(state.players[pid], opts.get("p%d" % pid, {}))
	if not opts.get("allow_illegal", false):
		_assert_legal(state)
	return state


static func _assert_legal(state: GameState) -> void:
	## Fail the running test when a card shares a zone with its player's
	## monster. gdUnit asserts report to the current test from any caller.
	for player in state.players:
		var zone: int = player.monster_zone
		var occupied: bool = zone >= 1 and zone <= 8 and player.zone_has_cards(zone - 1)
		var message := ("States.make_state: p%d has a card in zone %d, where its monster is. "
				+ "The next check timing crushes it (11.3): move the card or monster_zone, "
				+ "or pass allow_illegal: true to test the crush.") % [player.player_id, zone]
		_BoolAssert.new(occupied).override_failure_message(message).is_false()


## Build a RulesEngine wired with a real EffectQueries over the given state
## (and a fresh EffectHandler with the supplied or default PlayerInput).
## Fixture cards carry no effect scripts, so all modifiers are neutral.
static func make_rules(state: GameState, input: PlayerInput = null) -> RulesEngine:
	var handler := EffectHandler.new()
	handler.setup(state, input if input else PlayerInput.new())
	var rules := RulesEngine.new()
	rules.queries = handler.queries
	return rules


## Build a fully wired logic stack over the given state (the same wiring
## TurnManager.setup performs, minus deck construction): EffectHandler,
## ActionHandler with resolvers, GameEvents, RulesEngine.
## Returns {"action_handler", "effect_handler", "events", "input", "rules"}.
static func make_session(state: GameState, input: PlayerInput = null) -> Dictionary:
	var the_input: PlayerInput = input if input else ScriptedPlayerInput.new()
	var effect_handler := EffectHandler.new()
	effect_handler.setup(state, the_input)
	var action_handler := ActionHandler.new()
	var events := GameEvents.new()
	action_handler.effect_handler = effect_handler
	action_handler.input = the_input
	action_handler.events = events
	effect_handler.events = events
	effect_handler.action_handler = action_handler
	var rules := RulesEngine.new()
	rules.queries = effect_handler.queries
	return {
		"action_handler": action_handler,
		"effect_handler": effect_handler,
		"events": events,
		"input": the_input,
		"rules": rules,
	}


## Build a TurnManager over the given state with the full logic stack wired
## (mirrors MatchFactory minus deck construction / printing / opening draw),
## so flow tests can drive whole turns with a ScriptedPlayerInput.
static func make_turn_manager(state: GameState, input: PlayerInput = null) -> TurnManager:
	var session := make_session(state, input)
	var tm := TurnManager.new()
	tm.game_state = state
	tm.rules_engine = session["rules"]
	tm.action_handler = session["action_handler"]
	tm.effect_handler = session["effect_handler"]
	tm.events = session["events"]
	tm.player_input = session["input"]
	state.game_over.connect(tm._on_game_over)
	for player in state.players:
		player.hand_changed.connect(tm._on_hand_changed)
	return tm


static func _apply_player_opts(player: PlayerState, opts: Dictionary) -> void:
	player.current_monster = opts.get("current_monster", Cards.monster())
	player.monster_zone = opts.get("monster_zone", 1)
	player.rage = opts.get("rage", 0)
	player.has_invaded_this_turn = opts.get("has_invaded_this_turn", false)
	player.has_played_monster_this_turn = opts.get("has_played_monster_this_turn", false)
	for card: Dictionary in opts.get("hand", []):
		player.hand.append(card)
	for card: Dictionary in opts.get("monster_deck", []):
		player.monster_deck.append(card)
	for card: Dictionary in opts.get("main_deck", []):
		player.main_deck.append(card)
	var zone_cards: Dictionary = opts.get("zone_cards", {})
	for zone_idx: int in zone_cards:
		player.push_zone_card(zone_idx, zone_cards[zone_idx])
	var strategies: Array = opts.get("strategy_zones", [])
	for i in range(strategies.size()):
		player.strategy_zones[i] = strategies[i]
