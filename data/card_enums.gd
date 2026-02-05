class_name CardEnums


enum CardType { MONSTER, BATTLE, STRATEGY }

enum CardColor { RED, BLUE, WHITE, GREEN }

enum CardTrait { KAIJU, MECHA, ALIEN, MUTANT }

enum GamePhase { START, MAIN, COUNTER, END }

enum ActionType { PLAY_BATTLE, PLAY_STRATEGY, GAIN_RAGE, PLAY_MONSTER, INVADE, PASS }


static func rank_to_roman(rank: int) -> String:
	match rank:
		1: return "I"
		2: return "II"
		3: return "III"
		4: return "IV"
		_: return str(rank)


static func color_to_string(color: CardColor) -> String:
	match color:
		CardColor.RED: return "Red"
		CardColor.BLUE: return "Blue"
		CardColor.WHITE: return "White"
		CardColor.GREEN: return "Green"
		_: return "Unknown"


static func trait_to_string(t: CardTrait) -> String:
	match t:
		CardTrait.KAIJU: return "Kaiju"
		CardTrait.MECHA: return "Mecha"
		CardTrait.ALIEN: return "Alien"
		CardTrait.MUTANT: return "Mutant"
		_: return "Unknown"


static func type_to_string(t: CardType) -> String:
	match t:
		CardType.MONSTER: return "Monster"
		CardType.BATTLE: return "Battle"
		CardType.STRATEGY: return "Strategy"
		_: return "Unknown"


static func color_to_godot_color(color: CardColor) -> Color:
	match color:
		CardColor.RED: return Color(0.8, 0.2, 0.2)
		CardColor.BLUE: return Color(0.2, 0.3, 0.8)
		CardColor.WHITE: return Color(0.85, 0.85, 0.9)
		CardColor.GREEN: return Color(0.2, 0.7, 0.3)
		_: return Color(0.5, 0.5, 0.5)


static func phase_to_string(phase: GamePhase) -> String:
	match phase:
		GamePhase.START: return "Start Phase"
		GamePhase.MAIN: return "Main Phase"
		GamePhase.COUNTER: return "Counter Phase"
		GamePhase.END: return "End Phase"
		_: return "Unknown"
