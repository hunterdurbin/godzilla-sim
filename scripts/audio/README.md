# scripts/audio/ — sound & music

| File | Role |
|---|---|
| `sfx_manager.gd` | **Autoload `SfxManager`** — preloads the WAVs named in `SOUND_NAMES` into a 4-player pool; `play(sound_name)` / `stop_all()`; per-sound gain in `_VOLUME_DB`; volume from `GameSettings.sound_volume`. Also flushes audio gracefully on window close (calls `MusicManager.stop_playback()`). |
| `music_manager.gd` | **Autoload `MusicManager`** — one looping background track across scenes; `set_volume(level)` / `stop_playback()`; volume from `GameSettings.music_volume`. |

Asset locations (paths are built dynamically — keep in sync if assets move):

- SFX: `SFX_DIR = "res://assets/sfx/"` + `sound_name + ".wav"`
- Music: `MUSIC_PATH = "res://assets/music/background.wav"`

Adding a sound: drop the `.wav` in the sfx dir, add its base name to
`SOUND_NAMES` (+ optional `_VOLUME_DB` entry), call `SfxManager.play("name")`
— typically from a GameEvents subscription, not from engine code.
