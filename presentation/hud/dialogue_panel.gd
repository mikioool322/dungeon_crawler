class_name DialoguePanel
extends Control

## NPC dialogue panel (Sprint 04 UI, ADR-017): one greeting line, an optional shop entry
## and a close button.
##
## Presentation only: it reads the `NpcDefinition` it is handed and never touches the
## session, gold, the bag, the save or the player. The transition into the shop is owned
## by `GameHud`, which listens to `shop_requested` and enforces the one-screen-owner rule.
##
## While it is open the panel owns the screen (ADR-008 UI focus): the cursor is released
## through `PlayerController.mouse_captured` and look/move/attack/interact input is
## suspended. `ui_cancel` closes the panel.

## Emitted when the player asks for the NPC's shop; carries the NPC's merchant.
signal shop_requested(merchant: MerchantDefinition)

var _npc: NpcDefinition = null
var _player: PlayerController = null
var _open: bool = false
var _layout_built: bool = false
var _name_label: Label = null
var _greeting_label: Label = null
var _shop_button: Button = null
var _close_button: Button = null


func _ready() -> void:
	_ensure_layout()


## Binds the rig whose input the panel suspends while it is open.
func bind_player(player: PlayerController) -> void:
	_player = player
	if _open:
		_set_player_input(false)


## Shows the greeting of `npc` and suspends player input. A null definition is a no-op,
## so a stray request can never open an empty panel.
func open(npc: NpcDefinition) -> void:
	if npc == null:
		return
	_ensure_layout()
	_npc = npc
	_open = true
	visible = true
	_update_text()
	_set_player_input(false)
	_focus_first_enabled()


## Hides the panel and restores the cursor and player input. A no-op when closed.
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_set_player_input(true)


func is_open() -> bool:
	return _open


## The NPC currently shown, or null.
func npc() -> NpcDefinition:
	return _npc


## True when the open NPC offers a shop and the button is actually shown.
func has_shop_button() -> bool:
	return _shop_button != null and _shop_button.visible


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		if is_inside_tree():
			accept_event()


# --- presentation -------------------------------------------------------------

func _update_text() -> void:
	if _name_label != null:
		_name_label.text = _npc.display_name if _npc != null else ""
	if _greeting_label != null:
		_greeting_label.text = _npc.greeting if _npc != null else ""
	if _shop_button != null:
		_shop_button.visible = _npc != null and _npc.has_shop()


func _on_shop_pressed() -> void:
	if _npc != null and _npc.merchant != null:
		shop_requested.emit(_npc.merchant)


# --- input focus --------------------------------------------------------------

func _set_player_input(enabled: bool) -> void:
	var player := _player
	if player == null or not is_instance_valid(player):
		return
	player.set_input_enabled(enabled)
	player.mouse_captured = enabled
	var controller := InteractionController.find_on(player)
	if controller != null:
		controller.set_enabled(enabled)


func _focus_first_enabled() -> void:
	if not is_inside_tree():
		return
	for button in [_shop_button, _close_button]:
		if button != null and button.visible and not button.disabled:
			button.grab_focus()
			return


# --- script-built chrome ------------------------------------------------------

## Builds the panel chrome once; the scene stays a bare full-rect Control.
func _ensure_layout() -> void:
	if _layout_built:
		return
	_layout_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.custom_minimum_size = Vector2(420.0, 0.0)
	center.add_child(frame)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	frame.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_name_label = Label.new()
	_name_label.name = "NpcName"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 20)
	column.add_child(_name_label)

	_greeting_label = Label.new()
	_greeting_label.name = "Greeting"
	_greeting_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_greeting_label.custom_minimum_size = Vector2(380.0, 0.0)
	_greeting_label.add_theme_font_size_override("font_size", 15)
	column.add_child(_greeting_label)

	_shop_button = Button.new()
	_shop_button.name = "ShopButton"
	_shop_button.text = "Shop"
	_shop_button.visible = false
	_shop_button.pressed.connect(_on_shop_pressed)
	column.add_child(_shop_button)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "Close [Esc]"
	_close_button.pressed.connect(close)
	column.add_child(_close_button)
