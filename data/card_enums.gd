class_name CardEnums


enum CardType {MONSTER, BATTLE, STRATEGY}

enum CardColor {RED, BLUE, WHITE, GREEN}

enum CardTrait {KAIJU, MECHA, ALIEN, MUTANT, ANGUIRUS, BABY_GODZILLA, BARAGON, BATTRA, BIOLLANTE, BOAT, CHIBI, CHIBI_GODZILLA_RAIDS_AGAIN, CITY, CRYSTAL, DAGAHRA, DESGHIDORAH, DESTOROYAH, DORAT, EBIRAH, FEST, FESTIVAL_GODZILLA, FINAL_WARS, FOURTH_FORM, GABARA, GHIDORAH, GHOGO, GIANT_CONDOR, GIGAN, GODZILLA, GODZILLASAURUS, GODZILLA_JR, GOROSAURUS, HEDORAH, JET_JAGUAR, KAMACURAS, KING_CAESAR, KING_GHIDORAH, KUMONGA, LITTLE_GODZILLA, MANDA, MECH, MECHAGODZILLA, MEGAGUIRUS, MEGALON, MEGANULA, MINILLA, MOGUERA, MONSTER_X, MOTHRA, ORGA, RODAN, SACRED_GUARDIAN_BEASTS, SECOND_FORM, SPACEGODZILLA, SUPER_X, THIRD_FORM, TITANOSAURUS, TOKEN, TWENTY_THIRD_CENTURY, VARAN, WEAPON, ZILLA, GODZILLA_EARTH, HIGHER_DIMENSIONAL, TENTACLE, VALKYRIE, KAISER_GHIDORAH, SANDA, GAIRA, GEZORA, GANIMES, KAMOEBAS, SERVUM}

enum GamePhase {START, MAIN, COUNTER, END}

enum ActionType {PLAY_BATTLE, PLAY_STRATEGY, GAIN_RAGE, PLAY_MONSTER, INVADE, PASS}

enum EffectCategory {ONE_SHOT, CONTINUOUS, REPLACEMENT, ACTIVATED}


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
		CardTrait.ANGUIRUS: return "Anguirus"
		CardTrait.BABY_GODZILLA: return "Baby Godzilla"
		CardTrait.BARAGON: return "Baragon"
		CardTrait.BATTRA: return "Battra"
		CardTrait.BIOLLANTE: return "Biollante"
		CardTrait.BOAT: return "Boat"
		CardTrait.CHIBI: return "Chibi"
		CardTrait.CHIBI_GODZILLA_RAIDS_AGAIN: return "Chibi Godzilla Raids Again"
		CardTrait.CITY: return "City"
		CardTrait.CRYSTAL: return "Crystal"
		CardTrait.DAGAHRA: return "Dagahra"
		CardTrait.DESGHIDORAH: return "Desghidorah"
		CardTrait.DESTOROYAH: return "Destoroyah"
		CardTrait.DORAT: return "Dorat"
		CardTrait.EBIRAH: return "Ebirah"
		CardTrait.FEST: return "Fest"
		CardTrait.FESTIVAL_GODZILLA: return "Festival Godzilla"
		CardTrait.FINAL_WARS: return "Final Wars"
		CardTrait.FOURTH_FORM: return "4th Form"
		CardTrait.GABARA: return "Gabara"
		CardTrait.GHIDORAH: return "Ghidorah"
		CardTrait.GHOGO: return "Ghogo"
		CardTrait.GIANT_CONDOR: return "Giant Condor"
		CardTrait.GIGAN: return "Gigan"
		CardTrait.GODZILLA: return "Godzilla"
		CardTrait.GODZILLASAURUS: return "Godzillasaurus"
		CardTrait.GODZILLA_JR: return "Godzilla Jr."
		CardTrait.GOROSAURUS: return "Gorosaurus"
		CardTrait.HEDORAH: return "Hedorah"
		CardTrait.JET_JAGUAR: return "Jet Jaguar"
		CardTrait.KAMACURAS: return "Kamacuras"
		CardTrait.KING_CAESAR: return "King Caesar"
		CardTrait.KING_GHIDORAH: return "King Ghidorah"
		CardTrait.KUMONGA: return "Kumonga"
		CardTrait.LITTLE_GODZILLA: return "Little Godzilla"
		CardTrait.MANDA: return "Manda"
		CardTrait.MECH: return "Mech"
		CardTrait.MECHAGODZILLA: return "Mechagodzilla"
		CardTrait.MEGAGUIRUS: return "Megaguirus"
		CardTrait.MEGALON: return "Megalon"
		CardTrait.MEGANULA: return "Meganula"
		CardTrait.MINILLA: return "Minilla"
		CardTrait.MOGUERA: return "Moguera"
		CardTrait.MONSTER_X: return "Monster X"
		CardTrait.MOTHRA: return "Mothra"
		CardTrait.ORGA: return "Orga"
		CardTrait.RODAN: return "Rodan"
		CardTrait.SACRED_GUARDIAN_BEASTS: return "Sacred Guardian Beasts"
		CardTrait.SECOND_FORM: return "2nd Form"
		CardTrait.SPACEGODZILLA: return "SpaceGodzilla"
		CardTrait.SUPER_X: return "Super X"
		CardTrait.THIRD_FORM: return "3rd Form"
		CardTrait.TITANOSAURUS: return "Titanosaurus"
		CardTrait.TOKEN: return "Token"
		CardTrait.TWENTY_THIRD_CENTURY: return "23rd century"
		CardTrait.VARAN: return "Varan"
		CardTrait.WEAPON: return "Weapon"
		CardTrait.ZILLA: return "Zilla"
		CardTrait.GODZILLA_EARTH: return "Godzilla Earth"
		CardTrait.HIGHER_DIMENSIONAL: return "Higher Dimensional"
		CardTrait.TENTACLE: return "Tentacle"
		CardTrait.VALKYRIE: return "Valkyrie"
		CardTrait.KAISER_GHIDORAH: return "Kaiser Ghidorah"
		CardTrait.SANDA: return "Sanda"
		CardTrait.GAIRA: return "Gaira"
		CardTrait.GEZORA: return "Gezora"
		CardTrait.GANIMES: return "Ganimes"
		CardTrait.KAMOEBAS: return "Kamoebas"
		CardTrait.SERVUM: return "Servum"
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
