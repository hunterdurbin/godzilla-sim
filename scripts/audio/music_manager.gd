extends Node

## Background music manager. Plays a looping track across all scenes.
## Respects GameSettings.music_volume and responds to changes at runtime.

const MUSIC_PATH := "res://assets/audio/music/background.wav"

## Volume level (0-4) to dB mapping.
const _VOLUME_DB := [
	-80.0,  # 0 = OFF
	-18.0,  # 1 = 25%
	-12.0,  # 2 = 50%
	-6.0,   # 3 = 75%
	-3.0,   # 4 = 100%
]

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)

	var stream: AudioStream = load(MUSIC_PATH)
	if stream:
		_player.stream = stream
	else:
		push_warning("MusicManager: failed to load %s" % MUSIC_PATH)
		return

	if GameSettings.music_volume > 0:
		_player.volume_db = _VOLUME_DB[GameSettings.music_volume]
		_player.play()


func stop_playback() -> void:
	# Called by SfxManager's window-close handler (and _exit_tree as a
	# fallback) so the playback isn't reported as leaked at exit.
	if _player:
		_player.stop()
		_player.stream = null


func _exit_tree() -> void:
	stop_playback()


func set_volume(level: int) -> void:
	if level <= 0:
		_player.stop()
	elif _player.stream:
		_player.volume_db = _VOLUME_DB[mini(level, 4)]
		if not _player.playing:
			_player.play()
