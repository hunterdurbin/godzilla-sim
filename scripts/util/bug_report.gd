class_name BugReport
extends RefCounted

## Builds the diagnostic body for the in-game bug report button: game mode,
## turn/phase, per-player board state, and the last 50 game-log lines.

static func build_body(board: Node) -> String:
	var lines: PackedStringArray = []

	lines.append("## Description")
	lines.append("<!-- Describe the bug -->")
	lines.append("")
	lines.append("## Steps to Reproduce")
	lines.append("1. ")
	lines.append("")
	lines.append("## Expected Behavior")
	lines.append("<!-- What should have happened -->")
	lines.append("")
	lines.append("## Actual Behavior")
	lines.append("<!-- What actually happened -->")
	lines.append("")
	lines.append("## Screenshots")
	lines.append("<!-- Drag and drop screenshots here -->")
	lines.append("")

	# Game state
	lines.append("## Game State")
	var mode_names := {
		NetworkManager.Mode.SOLO: "Solo",
		NetworkManager.Mode.SOLO_BOT: "Solo v Bot",
		NetworkManager.Mode.HOST: "LAN (Host)",
		NetworkManager.Mode.CLIENT: "LAN (Client)",
		NetworkManager.Mode.ONLINE_HOST: "Online (Host)",
		NetworkManager.Mode.ONLINE_CLIENT: "Online (Client)",
		NetworkManager.Mode.ONLINE: "Online (Dedicated)",
	}
	lines.append("- **Version:** %s" % NetworkManager.GAME_VERSION)
	lines.append("- **Mode:** %s" % mode_names.get(NetworkManager.mode, "Unknown"))
	if NetworkManager.mode == NetworkManager.Mode.SOLO_BOT:
		var diff_names := {BotConfig.Difficulty.EASY: "Easy", BotConfig.Difficulty.NORMAL: "Normal", BotConfig.Difficulty.HARD: "Hard", BotConfig.Difficulty.KAIJU: "Kaiju"}
		lines.append("- **Bot Difficulty:** %s" % diff_names.get(NetworkManager.bot_difficulty, "Unknown"))
		lines.append("- **Bot Seed:** %d" % NetworkManager.bot_seed)
	var gs: GameState = board.turn_manager.game_state if board.turn_manager else null
	var turn_num: int = gs.turn_number if gs else board._client_turn_number
	var phase: CardEnums.GamePhase = gs.current_phase if gs else board._client_phase
	var cur_pid: int = gs.current_player_id if gs else board._client_current_player_id
	lines.append("- **Turn:** Turn %d - %s" % [turn_num, GameLog.player_names[cur_pid]])
	lines.append("- **Phase:** %s" % CardEnums.phase_to_string(phase))
	lines.append("")

	for pid in range(2):
		var ps: PlayerState = board._get_player_state(pid)
		lines.append("### %s" % GameLog.player_names[pid])
		var monster_name: String = ps.current_monster.get("name", "None") if not ps.current_monster.is_empty() else "None"
		lines.append("- **Monster:** %s (Zone %d)" % [monster_name, ps.monster_zone])
		lines.append("- **Rage:** %d" % ps.rage)
		lines.append("- **Counter Power:** %d" % ps.get_total_counter_power())
		var threat_mod: int = board._threat_mod_for(pid)
		if threat_mod != 0:
			lines.append("- **Threat Level:** %d (%d + %d effects)" % [ps.get_threat_level() + threat_mod, ps.get_threat_level(), threat_mod])
		else:
			lines.append("- **Threat Level:** %d" % ps.get_threat_level())
		lines.append("- **Deck:** %d cards" % ps.main_deck.size())
		lines.append("- **Discard:** %d cards" % ps.discard_pile.size())
		lines.append("- **Hand:** %d cards" % ps.hand.size())

		# Battle zones (only occupied)
		var occupied: Array[String] = []
		for zi in range(8):
			if ps.zone_has_cards(zi):
				var top_card: Dictionary = ps.get_zone_top_card(zi)
				var stack_size: int = ps.get_zone_stack(zi).size()
				var entry := "Zone %d: %s" % [zi + 1, top_card.get("name", "?")]
				if stack_size > 1:
					entry += " (+%d under)" % (stack_size - 1)
				occupied.append(entry)
		if occupied.size() > 0:
			lines.append("- **Battle Zones:** %s" % ", ".join(occupied))
		else:
			lines.append("- **Battle Zones:** (empty)")

		# Strategy zones
		var strategies: Array[String] = []
		for si in range(ps.strategy_zones.size()):
			var strat: Dictionary = ps.strategy_zones[si]
			if not strat.is_empty():
				strategies.append("Slot %d: %s" % [si + 1, strat.get("name", "?")])
		if strategies.size() > 0:
			lines.append("- **Strategy Zones:** %s" % ", ".join(strategies))
		else:
			lines.append("- **Strategy Zones:** (empty)")
		lines.append("")

	# Game log (last 50 lines)
	if board._log_tokens.size() > 0:
		lines.append("<details>")
		lines.append("<summary>Game Log (last 50 lines)</summary>")
		lines.append("")
		lines.append("```")
		var start_idx := maxi(0, board._log_tokens.size() - 50)
		for i in range(start_idx, board._log_tokens.size()):
			var entry = board._log_tokens[i]
			if typeof(entry) == TYPE_DICTIONARY:
				lines.append(GameLog.render_plain(entry))
			else:
				lines.append(GameLog.to_plain_text(str(entry)))
		lines.append("```")
		lines.append("")
		lines.append("</details>")

	return "\n".join(lines)
