extends "res://tests/test_case.gd"

## Contract tests for the W0 bootstrap decisions (ADR-002, ADR-005).
## These protect the cross-module API that scripts and scenes depend on.

const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"attack_primary",
	&"interact",
	&"inventory",
]

const EXPECTED_LAYER_NAMES: Dictionary = {
	"3d_physics/layer_1": "world",
	"3d_physics/layer_2": "player_body",
	"3d_physics/layer_3": "enemy_body",
	"3d_physics/layer_4": "hurtbox",
	"3d_physics/layer_5": "interactable",
}


func test_required_input_actions_exist() -> void:
	for action in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "missing InputMap action: %s" % action)


func test_required_input_actions_are_bound() -> void:
	for action in REQUIRED_ACTIONS:
		assert_eq(InputMap.action_get_events(action).size(), 1, "action %s must have exactly one event" % action)


func test_ui_cancel_still_available_for_mouse_release() -> void:
	assert_true(InputMap.has_action(&"ui_cancel"), "ui_cancel (built-in) is used to release the mouse")


func test_physics_layer_names_match_contract() -> void:
	for setting_key: String in EXPECTED_LAYER_NAMES:
		assert_eq(
			ProjectSettings.get_setting("layer_names/%s" % setting_key),
			EXPECTED_LAYER_NAMES[setting_key],
			"layer name mismatch for %s" % setting_key
		)


func test_physics_layer_constants_match_named_layers() -> void:
	assert_eq(PhysicsLayers.WORLD, 1 << 0, "WORLD must be layer 1")
	assert_eq(PhysicsLayers.PLAYER_BODY, 1 << 1, "PLAYER_BODY must be layer 2")
	assert_eq(PhysicsLayers.ENEMY_BODY, 1 << 2, "ENEMY_BODY must be layer 3")
	assert_eq(PhysicsLayers.HURTBOX, 1 << 3, "HURTBOX must be layer 4")
	assert_eq(PhysicsLayers.INTERACTABLE, 1 << 4, "INTERACTABLE must be layer 5")
	assert_eq(
		PhysicsLayers.movement_mask(PhysicsLayers.PLAYER_BODY),
		PhysicsLayers.WORLD | PhysicsLayers.ENEMY_BODY,
		"player movement mask"
	)
	assert_eq(
		PhysicsLayers.movement_mask(PhysicsLayers.ENEMY_BODY),
		PhysicsLayers.WORLD | PhysicsLayers.PLAYER_BODY,
		"enemy movement mask"
	)
	assert_eq(
		PhysicsLayers.movement_mask(PhysicsLayers.PLAYER_BODY) & PhysicsLayers.INTERACTABLE,
		0,
		"interactables never block movement (ADR-008)"
	)
