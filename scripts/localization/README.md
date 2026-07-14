# scripts/localization/ — translation helper

One file: `loc.gd` — `Loc.t(key)` wraps `TranslationServer.translate()` for
static contexts where a Node's `tr()` isn't available (validators, static
log/token code).

The translation DATA lives at the repo root in `translations/` (CSV sources
compiled to `.translation`, registered in project.godot) — see
[translations/README.md](../../translations/README.md) for the full
workflow, including regenerating card text with `generate_card_csv.py`.

Key families: `STR_*` UI strings, `STR_LOG_*` game-log strings,
`CARD_<id>_NAME` / `CARD_<id>_DESC` card text. Locales: `en`, `ja`
(set via `GameSettings.set_locale()`).
