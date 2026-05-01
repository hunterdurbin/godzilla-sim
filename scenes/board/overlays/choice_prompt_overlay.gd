class_name ChoicePromptOverlay
extends Control

## Auto-registering scene-based version of the choice prompt. The legacy
## `class_name ChoiceOverlay` is a controller (extends Object) that
## game_board.gd builds dynamically — that path stays for the production
## scene. This component is the drop-in alternative for GameBoardTemplate
## variants: lives in DefaultOverlayPack, self-registers under
## `prompt_key = "choice"`, and presents the option list as a modal.
##
## To customize the visual: File → New Inherited Scene →
## ChoicePromptOverlay.tscn. Edit the buttons / panel styling — auto-bind
## still works because the script's logic is unchanged.

@export var prompt_key: String = "choice"
@export var auto_register: bool = true

@onready var _bg: ColorRect = $Bg
@onready var _panel: PanelContainer = $Panel
@onready var _prompt: Label = $Panel/VBox/Prompt
@onready var _buttons: VBoxContainer = $Panel/VBox/Buttons

var _resolve: Callable = Callable()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if auto_register:
		var router := BoardModule.find_router(self)
		if router:
			router.register_handler(prompt_key, _on_router_show)
			print("[ChoicePromptOverlay] Registered '%s' handler with router %s" % [prompt_key, router])
		else:
			push_warning("[ChoicePromptOverlay] No EffectUIRouter found — choice prompts will auto-pick option 0.")


func _on_router_show(options: Array, prompt: String, resolve_cb: Callable) -> void:
	print("[ChoicePromptOverlay] _on_router_show called with %d options: %s" % [options.size(), prompt])
	_resolve = resolve_cb
	_prompt.text = prompt
	# Clear any leftover buttons from a prior choice.
	for child in _buttons.get_children():
		child.queue_free()
	for i in range(options.size()):
		var btn := Button.new()
		btn.text = str(options[i])
		btn.custom_minimum_size = Vector2(280, 44)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_button_pressed.bind(i))
		_buttons.add_child(btn)
	visible = true


func _on_button_pressed(index: int) -> void:
	visible = false
	if _resolve.is_valid():
		var cb := _resolve
		_resolve = Callable()
		cb.call(index)
