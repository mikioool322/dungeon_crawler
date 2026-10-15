class_name DungeonPanel
extends Control

## Hub dungeon-selection panel (ADR-012): presentation only.
##
## It reads `GameSession.progress` / `GameSession.dungeons` on every `rows()` call and
## caches no progression state, never mutates it and never travels on its own: a
## successful `select()` only emits `travel_requested`, and `WorldRouter` stays the
## owner of the travel gate.
##
## While it is open the panel owns the screen: the cursor is released through
## `PlayerController.mouse_captured` (the single owner of that flag) and look, move and
## attack input is suspended through `PlayerController.set_input_enabled()`. `ui_cancel`
## closes the panel; no new InputMap action is introduced.

## Emitted for a dungeon the session gate accepted; `GameHud` forwards it to
## `WorldRouter.request_travel()`, which may still refuse (busy, blocked, ...).
signal travel_requested(world_id: StringName, spawn_id: StringName)

## Row states of the view model, resolved in this order per dungeon.
const STATE_COMPLETED: StringName = &"completed"
const STATE_UNLOCKED: StringName = &"unlocked"
const STATE_LOCKED: StringName = &"locked"

const LABEL_ENTER: String = "ENTER"
const LABEL_COMPLETED: String = "COMPLETED"
const LABEL_LOCKED: String = "LOCKED"

var _session: GameSession = null
var _router: WorldRouter = null
var _registry: ContentRegistry = null
var _player: PlayerController = null
var _open: bool = false
var _layout_built: bool = false
var _list: VBoxContainer = null


func _ready() -> void:
	_ensure_layout()


## Stores the services the board reads. Builds nothing: the view model and the buttons
## are produced by `rows()`, `refresh()` and `open()`.
func bind(session: GameSession, router: WorldRouter, registry: ContentRegistry) -> void:
	_session = session
	_router = router
	_registry = registry


## Binds the rig whose input the panel suspends while it is open.
func bind_player(player: PlayerController) -> void:
	_player = player
	if _open:
		_set_player_input(false)


## View model of the board: one entry per registry dungeon, in manifest order.
## `state` and `reason` are derived from the session on every call, never cached.
func rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _session == null or _registry == null:
		return result
	for definition in _registry.all_dungeons():
		var state := _state_for(definition)
		result.append({
			"dungeon_id": definition.dungeon_id,
			"display_name": definition.display_name,
			"state": state,
			"reason": _reason_for(definition, state),
			"world_id": definition.world_id,
			"entry_spawn_id": definition.entry_spawn_id,
		})
	return result


## Shows the board, rebuilds it from live progress and suspends player input.
func open() -> void:
	_open = true
	visible = true
	refresh()
	_set_player_input(false)
	_focus_first_enabled()


## Hides the board and restores the cursor and player input. A no-op when closed, so a
## stray close() never captures a cursor the player had released.
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_set_player_input(true)


func is_open() -> bool:
	return _open


## Rebuilds one button per dungeon from the live session state. Safe to call while
## closed; locked dungeons get a disabled button and a reason in the tooltip.
func refresh() -> void:
	_ensure_layout()
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for row in rows():
		_list.add_child(_build_button(row))


## Button action and test entry point. Consults the session's entry gate first: a
## refusal is returned without travelling. Only `CODE_OK` resolves the definition and
## emits `travel_requested`.
func select(dungeon_id: StringName) -> StringName:
	if _session == null:
		return DungeonService.CODE_UNKNOWN_DUNGEON
	var code := _session.dungeons.can_enter(dungeon_id)
	if code != DungeonService.CODE_OK:
		return code
	var definition := _definition_for(dungeon_id)
	if definition == null:
		return DungeonService.CODE_UNKNOWN_DUNGEON
	travel_requested.emit(definition.world_id, definition.entry_spawn_id)
	return WorldRouter.CODE_TRAVEL_STARTED


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		if is_inside_tree():
			accept_event()


# --- view model ---------------------------------------------------------------

func _state_for(definition: DungeonDefinition) -> StringName:
	if _session.progress.is_completed(definition.dungeon_id):
		return STATE_COMPLETED
	if _session.progress.is_unlocked(definition.dungeon_id):
		return STATE_UNLOCKED
	return STATE_LOCKED


## Lock explanation built from the prerequisite display names, e.g. "Requires Dungeon 01".
func _reason_for(definition: DungeonDefinition, state: StringName) -> String:
	if state != STATE_LOCKED:
		return ""
	var names := PackedStringArray()
	for prerequisite in definition.prerequisites:
		var prereq := _registry.find_dungeon(prerequisite)
		if prereq != null and prereq.display_name != "":
			names.append(prereq.display_name)
		else:
			names.append(String(prerequisite))
	if names.is_empty():
		return "Not unlocked yet"
	return "Requires %s" % ", ".join(names)


func _definition_for(dungeon_id: StringName) -> DungeonDefinition:
	var registry := _registry
	if registry == null and _session != null:
		registry = _session.registry()
	if registry == null:
		return null
	return registry.find_dungeon(dungeon_id)


# --- input focus --------------------------------------------------------------

func _focus_player() -> PlayerController:
	if _player != null and is_instance_valid(_player):
		return _player
	if _router != null:
		return _router.current_player()
	return null


func _set_player_input(enabled: bool) -> void:
	var player := _focus_player()
	if player == null:
		return
	player.set_input_enabled(enabled)
	player.mouse_captured = enabled
	# The panel owns the screen: the interaction ray is suspended too, so `interact`
	# cannot reach a board, portal or shrine behind the open panel (ADR-008 UI focus).
	var controller := InteractionController.find_on(player)
	if controller != null:
		controller.set_enabled(enabled)


func _focus_first_enabled() -> void:
	if _list == null or not is_inside_tree():
		return
	for child in _list.get_children():
		var button := child as Button
		if button != null and not button.disabled:
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
	frame.custom_minimum_size = Vector2(360.0, 0.0)
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

	var title := Label.new()
	title.name = "Title"
	title.text = "Dungeons"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.add_theme_constant_override("separation", 6)
	column.add_child(_list)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close [Esc]"
	close_button.pressed.connect(close)
	column.add_child(close_button)


func _build_button(row: Dictionary) -> Button:
	var state: StringName = row["state"]
	var button := Button.new()
	button.name = "Dungeon_%s" % String(row["dungeon_id"]).replace(".", "_")
	button.text = "%s [%s]" % [row["display_name"], _action_label(state)]
	# The gate decides, not the visual state: a completed non-repeatable dungeon shows
	# COMPLETED but must not offer an entry that would silently do nothing (ADR-014).
	var enterable := (
		_session != null
		and _session.dungeons.can_enter(row["dungeon_id"]) == DungeonService.CODE_OK
	)
	button.disabled = not enterable
	button.set_meta(&"dungeon_id", row["dungeon_id"])
	if row["reason"] != "":
		button.tooltip_text = row["reason"]
	button.pressed.connect(select.bind(row["dungeon_id"]))
	return button


func _action_label(state: StringName) -> String:
	match state:
		STATE_COMPLETED:
			return LABEL_COMPLETED
		STATE_LOCKED:
			return LABEL_LOCKED
	return LABEL_ENTER
