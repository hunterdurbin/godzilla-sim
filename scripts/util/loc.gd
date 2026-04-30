class_name Loc
## Translation helper for use in static contexts where the built-in `tr()` is unavailable.
## Use `Loc.t(key)` instead of `TranslationServer.translate(key)`.
## Method is `t` (not `tr`) to avoid colliding with Object.tr inherited via class_name.

static func t(key: String) -> String:
	return TranslationServer.translate(key)
