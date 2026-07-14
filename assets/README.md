# assets/ — art, audio, fonts

Buckets are **snake_case** and follow the same domain vocabulary as
`scripts/` and `scenes/`.

| Dir | Contents |
|---|---|
| `audio/music/` | Background music (`background.wav` — loaded by MusicManager) |
| `audio/sfx/` | Sound effects (`SfxManager` builds paths as `res://assets/audio/sfx/<name>.wav` — keep names in sync with its `SOUND_NAMES`) |
| `board/` | Playmat/board art |
| `cards/backs/` | Card back textures |
| `effects/icons/en/`, `effects/icons/ja/` | Per-locale effect/trait icons (`GameLog` builds paths under `res://assets/effects/icons/<locale>/…`) |
| `icons/` | App icons (`game_icon.png` referenced by export presets) |
| `icons/android/` | Android adaptive icons (referenced by the Android export preset) |
| `patreon/`, `rage/` | Misc UI art |
| `ui/buttons/` | Button textures |
| `ui/fonts/` | Fonts + `default_theme.tres` (project.godot `gui/theme/custom`) |

Rules:

- Every asset carries a `.import` sidecar — move it with the asset and run
  `<godot> --headless --path . --import` after out-of-editor moves.
- **Dynamic path builders exist** (SfxManager, MusicManager, GameLog) —
  renaming a bucket requires grepping for the prefix, not just full paths.
- Card artwork is NOT here — it downloads at runtime to
  `user://CardContent/Artwork/` (see `scripts/services/README.md`).
