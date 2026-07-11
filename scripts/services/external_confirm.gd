class_name ExternalConfirm
extends RefCounted
## Confirmation gate for any action that leaves the game — opening a URL in
## the browser or a directory in the OS file manager. Applies to every input
## method (mouse, keyboard, gamepad); the dialog itself is a registered
## gamepad modal, so pad focus lands on Cancel, dpad reaches Open, and B
## closes without opening.
##
## `host` is the node the dialog is parented under. Screens pass `self`; a
## call site inside an already-open modal popup must pass that popup Window
## so the exclusive ConfirmationDialog nests as its child window (sibling
## exclusive windows are rejected — one exclusive child per parent).

## Test seam: unit tests swap this for a recording lambda so they never
## actually launch a browser or file manager.
static var _shell_open: Callable = Callable(OS, "shell_open")


static func open_url(host: Node, url: String) -> void:
	_confirm(host, url, _display_url(url),
			"STR_EXT_OPEN_URL_TITLE", "STR_EXT_OPEN_URL_PROMPT_FMT")


static func open_folder(host: Node, path: String) -> void:
	_confirm(host, path, path,
			"STR_EXT_OPEN_FOLDER_TITLE", "STR_EXT_OPEN_FOLDER_PROMPT_FMT")


## "https://discord.gg/xyz" -> "discord.gg". The prompt shows only the host:
## the bug-report URL carries a huge uri-encoded body that must never be
## dumped into a dialog.
static func _display_url(url: String) -> String:
	var stripped := url.get_slice("://", 1) if url.contains("://") else url
	return stripped.get_slice("/", 0)


static func _confirm(host: Node, target: String, display: String,
		title_key: String, prompt_key: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = Loc.t(title_key)
	dialog.dialog_text = Loc.t(prompt_key) % display
	dialog.ok_button_text = Loc.t("STR_EXT_OPEN_OK")
	dialog.cancel_button_text = Loc.t("STR_COMMON_CANCEL")
	dialog.confirmed.connect(func() -> void: _shell_open.call(target))
	# Per-invocation dialog: OK and Cancel both hide first, so freeing on
	# hide covers every close path (register_modal pops idempotently on both
	# hide and tree_exiting).
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free()
	)
	host.add_child(dialog)
	GamepadHelper.register_modal(dialog)
	GamepadHelper.wire_pad_close(dialog)
	dialog.popup_centered()
