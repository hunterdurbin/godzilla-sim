# Input Prompts

Button glyphs from **Kenney Input Prompts 1.5** — https://kenney.nl/assets/input-prompts

License: **Creative Commons CC0 1.0** (public domain).

Slicing convention: files are named by **physical button position** (SDL layout), not label:

- `face_south/east/west/north` — face buttons (Xbox A/B/X/Y, PS ✕/○/□/△, Switch B/A/Y/X — the Switch label swap is baked into which source file was copied)
- `dpad_up/down/left/right`, `bumper_l/r`, `trigger_l/r`
- `start` (Menu/Options/+), `select` (View/Share/−)
- `lstick` (left stick), `stick_press_l` (L3)

Source folders used: `Xbox Series/Default`, `PlayStation Series/Default`,
`Nintendo Switch/Default`, `Steam Deck/Default` (as the `generic` set).

See `scripts/input/glyph_db.gd` for the physical-action → filename table.
