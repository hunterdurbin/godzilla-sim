# Phase 5 — assets/ normalization + root icons/ merge

**Goal:** snake_case, domain-sliced asset buckets; one icons location.

## Moves (git mv; move `.import` sidecars with every asset)

- [x] `assets/cardBacks/` → `assets/cards/backs/`
- [x] `assets/effectIcons/` → `assets/effects/icons/` (keeps `en/`/`ja/` subdirs)
- [x] `assets/music/` → `assets/audio/music/`
- [x] `assets/sfx/` → `assets/audio/sfx/`
- [x] `assets/buttons/` → `assets/ui/buttons/`
- [x] `assets/fonts/` → `assets/ui/fonts/` (contains `default_theme.tres` —
      referenced by project.godot `gui/theme/custom`)
- [x] root `icons/` (Android adaptive icons) → `assets/icons/android/`;
      delete root `icons/`
- [x] unchanged: `assets/board/`, `assets/icons/`, `assets/patreon/`, `assets/rage/`

## Config/path fixes

- [x] `project.godot`: `gui/theme/custom` → `res://assets/ui/fonts/default_theme.tres`
      (verify exact key by grepping `assets/fonts` in project.godot).
- [x] `export_presets.cfg`: 3× `res://icons/*.png` →
      `res://assets/icons/android/*.png` (Android preset);
      `res://assets/icons/game_icon.png` unchanged.
- [x] **Dynamically built paths** — full-literal greps MISS these:
      `sfx_manager.gd` / `music_manager.gd` concatenate
      `"res://assets/sfx/" + name`-style strings. Read both files and fix
      every prefix. Check for other builders:
      `grep -rn '"res://assets/' scripts scenes --include='*.gd'`.
- [x] `.tscn`/`.tres` ext_resource `path=` fallbacks (uid carries; fix text):
      `grep -rn 'assets/cardBacks\|assets/effectIcons\|assets/music\|assets/sfx\|assets/buttons\|assets/fonts' scenes scripts tests --include='*.tscn' --include='*.tres' --include='*.gd'`.

## Grep sweep (zero hits)

```bash
grep -rn 'cardBacks\|effectIcons\|res://icons/\|assets/music\|assets/sfx\|assets/buttons\|assets/fonts' . \
  --include='*.gd' --include='*.tscn' --include='*.tres' --include='*.cfg' \
  --include='*.godot' --include='*.sh' --include='*.yml' --include='*.md' \
  --exclude-dir=build --exclude-dir=.godot --exclude-dir=.git --exclude-dir=restructure
```

## Gate (full + visual)

- Open the project once in the editor (or run headless with a scene load) so
  Godot reimports moved assets, then standard gate.
- Headful screenshot check (`verify` skill): board + menu render — missing
  textures fail SILENTLY (pink/blank), sounds fail silently; toggle a sound
  in Options.
- Optional extra: local `--export-debug` of one preset to prove
  export_presets.cfg is intact.

## Docs to write this phase

`assets/README.md` (bucket naming = domain vocabulary, snake_case rule,
`.import` sidecar note, icon inventory: app vs android), `docs/README.md`
(index of docs/: graphs regeneration note, bot-decisioning-paths, combos,
ios-sideloading, restructure/).

## Commit

`restructure(phase-5): normalize assets/ to snake_case domain buckets`
