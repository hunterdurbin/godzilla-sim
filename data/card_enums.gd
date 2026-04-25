class_name CardEnums


enum CardType {MONSTER, BATTLE, STRATEGY}

enum CardColor {RED, BLUE, WHITE, GREEN}

enum CardTrait {KAIJU, MECHA, ALIEN, MUTANT, ANGUIRUS, BABY_GODZILLA, BARAGON, BATTRA, BIOLLANTE, BOAT, CHIBI, CHIBI_GODZILLA_RAIDS_AGAIN, CITY, CRYSTAL, DAGAHRA, DESGHIDORAH, DESTOROYAH, DORAT, EBIRAH, FEST, FINAL_WARS, FOURTH_FORM, GABARA, GHIDORAH, GHOGO, GIANT_CONDOR, GIGAN, GODZILLA, GODZILLASAURUS, GODZILLA_JR, GOROSAURUS, HEDORAH, JET_JAGUAR, KAMACURAS, KING_CAESAR, KING_GHIDORAH, KUMONGA, LITTLE_GODZILLA, MANDA, MECH, MECHAGODZILLA, MEGAGUIRUS, MEGALON, MEGANULA, MINILLA, MOGUERA, MONSTER_X, MOTHRA, ORGA, RODAN, SACRED_GUARDIAN_BEASTS, SECOND_FORM, SPACEGODZILLA, SUPER_X, THIRD_FORM, TITANOSAURUS, TOKEN, TWENTY_THIRD_CENTURY, VARAN, WEAPON, ZILLA, GODZILLA_EARTH, HIGHER_DIMENSIONAL, TENTACLE, VALKYRIE, KAISER_GHIDORAH, SANDA, GAIRA, GEZORA, GANIMES, KAMOEBAS, SERVUM}

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
	return TranslationServer.translate(color_to_key(color))


static func color_to_key(color: CardColor) -> StringName:
	match color:
		CardColor.RED: return &"STR_COLOR_RED"
		CardColor.BLUE: return &"STR_COLOR_BLUE"
		CardColor.WHITE: return &"STR_COLOR_WHITE"
		CardColor.GREEN: return &"STR_COLOR_GREEN"
		_: return &"STR_UNKNOWN"


static func trait_to_string(t: CardTrait) -> String:
	return TranslationServer.translate(trait_to_key(t))


static func trait_to_key(t: CardTrait) -> StringName:
	match t:
		CardTrait.KAIJU: return &"STR_TRAIT_KAIJU"
		CardTrait.MECHA: return &"STR_TRAIT_MECHA"
		CardTrait.ALIEN: return &"STR_TRAIT_ALIEN"
		CardTrait.MUTANT: return &"STR_TRAIT_MUTANT"
		CardTrait.ANGUIRUS: return &"STR_TRAIT_ANGUIRUS"
		CardTrait.BABY_GODZILLA: return &"STR_TRAIT_BABY_GODZILLA"
		CardTrait.BARAGON: return &"STR_TRAIT_BARAGON"
		CardTrait.BATTRA: return &"STR_TRAIT_BATTRA"
		CardTrait.BIOLLANTE: return &"STR_TRAIT_BIOLLANTE"
		CardTrait.BOAT: return &"STR_TRAIT_BOAT"
		CardTrait.CHIBI: return &"STR_TRAIT_CHIBI"
		CardTrait.CHIBI_GODZILLA_RAIDS_AGAIN: return &"STR_TRAIT_CHIBI_GODZILLA_RAIDS_AGAIN"
		CardTrait.CITY: return &"STR_TRAIT_CITY"
		CardTrait.CRYSTAL: return &"STR_TRAIT_CRYSTAL"
		CardTrait.DAGAHRA: return &"STR_TRAIT_DAGAHRA"
		CardTrait.DESGHIDORAH: return &"STR_TRAIT_DESGHIDORAH"
		CardTrait.DESTOROYAH: return &"STR_TRAIT_DESTOROYAH"
		CardTrait.DORAT: return &"STR_TRAIT_DORAT"
		CardTrait.EBIRAH: return &"STR_TRAIT_EBIRAH"
		CardTrait.FEST: return &"STR_TRAIT_FEST"
		CardTrait.FINAL_WARS: return &"STR_TRAIT_FINAL_WARS"
		CardTrait.FOURTH_FORM: return &"STR_TRAIT_FOURTH_FORM"
		CardTrait.GABARA: return &"STR_TRAIT_GABARA"
		CardTrait.GHIDORAH: return &"STR_TRAIT_GHIDORAH"
		CardTrait.GHOGO: return &"STR_TRAIT_GHOGO"
		CardTrait.GIANT_CONDOR: return &"STR_TRAIT_GIANT_CONDOR"
		CardTrait.GIGAN: return &"STR_TRAIT_GIGAN"
		CardTrait.GODZILLA: return &"STR_TRAIT_GODZILLA"
		CardTrait.GODZILLASAURUS: return &"STR_TRAIT_GODZILLASAURUS"
		CardTrait.GODZILLA_JR: return &"STR_TRAIT_GODZILLA_JR"
		CardTrait.GOROSAURUS: return &"STR_TRAIT_GOROSAURUS"
		CardTrait.HEDORAH: return &"STR_TRAIT_HEDORAH"
		CardTrait.JET_JAGUAR: return &"STR_TRAIT_JET_JAGUAR"
		CardTrait.KAMACURAS: return &"STR_TRAIT_KAMACURAS"
		CardTrait.KING_CAESAR: return &"STR_TRAIT_KING_CAESAR"
		CardTrait.KING_GHIDORAH: return &"STR_TRAIT_KING_GHIDORAH"
		CardTrait.KUMONGA: return &"STR_TRAIT_KUMONGA"
		CardTrait.LITTLE_GODZILLA: return &"STR_TRAIT_LITTLE_GODZILLA"
		CardTrait.MANDA: return &"STR_TRAIT_MANDA"
		CardTrait.MECH: return &"STR_TRAIT_MECH"
		CardTrait.MECHAGODZILLA: return &"STR_TRAIT_MECHAGODZILLA"
		CardTrait.MEGAGUIRUS: return &"STR_TRAIT_MEGAGUIRUS"
		CardTrait.MEGALON: return &"STR_TRAIT_MEGALON"
		CardTrait.MEGANULA: return &"STR_TRAIT_MEGANULA"
		CardTrait.MINILLA: return &"STR_TRAIT_MINILLA"
		CardTrait.MOGUERA: return &"STR_TRAIT_MOGUERA"
		CardTrait.MONSTER_X: return &"STR_TRAIT_MONSTER_X"
		CardTrait.MOTHRA: return &"STR_TRAIT_MOTHRA"
		CardTrait.ORGA: return &"STR_TRAIT_ORGA"
		CardTrait.RODAN: return &"STR_TRAIT_RODAN"
		CardTrait.SACRED_GUARDIAN_BEASTS: return &"STR_TRAIT_SACRED_GUARDIAN_BEASTS"
		CardTrait.SECOND_FORM: return &"STR_TRAIT_SECOND_FORM"
		CardTrait.SPACEGODZILLA: return &"STR_TRAIT_SPACEGODZILLA"
		CardTrait.SUPER_X: return &"STR_TRAIT_SUPER_X"
		CardTrait.THIRD_FORM: return &"STR_TRAIT_THIRD_FORM"
		CardTrait.TITANOSAURUS: return &"STR_TRAIT_TITANOSAURUS"
		CardTrait.TOKEN: return &"STR_TRAIT_TOKEN"
		CardTrait.TWENTY_THIRD_CENTURY: return &"STR_TRAIT_TWENTY_THIRD_CENTURY"
		CardTrait.VARAN: return &"STR_TRAIT_VARAN"
		CardTrait.WEAPON: return &"STR_TRAIT_WEAPON"
		CardTrait.ZILLA: return &"STR_TRAIT_ZILLA"
		CardTrait.GODZILLA_EARTH: return &"STR_TRAIT_GODZILLA_EARTH"
		CardTrait.HIGHER_DIMENSIONAL: return &"STR_TRAIT_HIGHER_DIMENSIONAL"
		CardTrait.TENTACLE: return &"STR_TRAIT_TENTACLE"
		CardTrait.VALKYRIE: return &"STR_TRAIT_VALKYRIE"
		CardTrait.KAISER_GHIDORAH: return &"STR_TRAIT_KAISER_GHIDORAH"
		CardTrait.SANDA: return &"STR_TRAIT_SANDA"
		CardTrait.GAIRA: return &"STR_TRAIT_GAIRA"
		CardTrait.GEZORA: return &"STR_TRAIT_GEZORA"
		CardTrait.GANIMES: return &"STR_TRAIT_GANIMES"
		CardTrait.KAMOEBAS: return &"STR_TRAIT_KAMOEBAS"
		CardTrait.SERVUM: return &"STR_TRAIT_SERVUM"
		_: return &"STR_UNKNOWN"


static func type_to_string(t: CardType) -> String:
	return TranslationServer.translate(type_to_key(t))


static func type_to_key(t: CardType) -> StringName:
	match t:
		CardType.MONSTER: return &"STR_TYPE_MONSTER"
		CardType.BATTLE: return &"STR_TYPE_BATTLE"
		CardType.STRATEGY: return &"STR_TYPE_STRATEGY"
		_: return &"STR_UNKNOWN"


static func color_to_godot_color(color: CardColor) -> Color:
	match color:
		CardColor.RED: return Color(0.8, 0.2, 0.2)
		CardColor.BLUE: return Color(0.2, 0.3, 0.8)
		CardColor.WHITE: return Color(0.85, 0.85, 0.9)
		CardColor.GREEN: return Color(0.2, 0.7, 0.3)
		_: return Color(0.5, 0.5, 0.5)


static func phase_to_string(phase: GamePhase) -> String:
	return TranslationServer.translate(phase_to_key(phase))


static func phase_to_key(phase: GamePhase) -> StringName:
	match phase:
		GamePhase.START: return &"STR_PHASE_START"
		GamePhase.MAIN: return &"STR_PHASE_MAIN"
		GamePhase.COUNTER: return &"STR_PHASE_COUNTER"
		GamePhase.END: return &"STR_PHASE_END"
		_: return &"STR_UNKNOWN"
