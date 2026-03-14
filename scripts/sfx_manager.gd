extends Node

## Sound effect manager. Loads WAV files from assets/sfx/ and plays them
## through a small pool of AudioStreamPlayer nodes.
## To replace a sound, swap the corresponding .wav file in assets/sfx/.

const SFX_DIR := "res://assets/sfx/"
const POOL_SIZE := 4

const SOUND_NAMES := [
	"card_play",
	"card_draw",
	"card_discard",
	"deck_shuffle",
	"turn_start",
	"counter_success",
	"counter_fail",
	"game_start",
	"game_win",
	"game_lose",
	"monster_advance",
	"button_click",
	"ui_click",
	"action_required",
	"gain_rage",
]

var _sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)

	for sound_name in SOUND_NAMES:
		var path: String = SFX_DIR + sound_name + ".wav"
		var stream: AudioStream = load(path)
		if stream:
			_sounds[sound_name] = stream
		else:
			push_warning("SfxManager: failed to load %s" % path)


## Volume level (0-4) to dB mapping.
const _VOLUME_DB := [
	-80.0,  # 0 = OFF
	-12.0,  # 1 = 25%
	-6.0,   # 2 = 50%
	-3.0,   # 3 = 75%
	0.0,    # 4 = 100%
]


func play(sound_name: String) -> void:
	var vol: int = GameSettings.sound_volume
	if vol <= 0:
		return
	var stream: AudioStream = _sounds.get(sound_name)
	if stream == null:
		return
	var db: float = _VOLUME_DB[mini(vol, 4)]
	for player in _players:
		if not player.playing:
			player.stream = stream
			player.volume_db = db
			player.play()
			return
	# All players busy — skip this sound
