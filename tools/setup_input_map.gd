extends SceneTree

## Writes the Sprint 01 InputMap actions into `project.godot` (ADR-005).
##
## Run once after bootstrap or whenever the agreed action list changes:
##   <godot> --headless --path . -s res://tools/setup_input_map.gd
##
## Keeping this as a script (instead of hand-editing InputEvent objects) makes
## the action list reviewable, reproducible and free of serialization mistakes.

const DEADZONE: float = 0.2

const KEY_ACTIONS: Dictionary = {
	&"move_forward": KEY_W,
	&"move_back": KEY_S,
	&"move_left": KEY_A,
	&"move_right": KEY_D,
}

const MOUSE_ACTIONS: Dictionary = {
	&"attack_primary": MOUSE_BUTTON_LEFT,
}


func _initialize() -> void:
	for action: StringName in KEY_ACTIONS:
		_write_action(action, _make_key_event(KEY_ACTIONS[action]))
	for action: StringName in MOUSE_ACTIONS:
		_write_action(action, _make_mouse_event(MOUSE_ACTIONS[action]))
	var err := ProjectSettings.save()
	if err != OK:
		push_error("setup_input_map: ProjectSettings.save() failed with code %d" % err)
		quit(1)
		return
	for action: StringName in KEY_ACTIONS:
		print("input action: %s" % action)
	for action: StringName in MOUSE_ACTIONS:
		print("input action: %s" % action)
	print("setup_input_map: saved %d actions" % (KEY_ACTIONS.size() + MOUSE_ACTIONS.size()))
	quit(0)


func _write_action(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
	var events: Array[InputEvent] = [event]
	ProjectSettings.set_setting("input/%s" % action, {
		"deadzone": DEADZONE,
		"events": events,
	})


func _make_key_event(key: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	return event


func _make_mouse_event(button: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event
