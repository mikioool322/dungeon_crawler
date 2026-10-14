extends "res://tests/test_case.gd"

## W3 scene contract for `actors/player/player.tscn` (ADR-005, ADR-006, AC-10).
##
## Headless: nothing here needs rendering or an input device. The scene is
## instantiated into the tree so node references resolve exactly as they do in
## the arena, and the combat wiring is checked against the live objects instead
## of against the .tscn text.

const PLAYER_SCENE_PATH := "res://actors/player/player.tscn"
const PLAYER_ATTACK_ID := &"attack.player.basic"
const EXPECTED_MAX_HEALTH := 100.0
const ATTACK_SCENE_PATH := "res://content/definitions/attack_player_basic.tres"

var _player: PlayerController


func teardown() -> void:
	_player = null


## Instantiates the player scene into the test tree. Returns null (with a
## recorded failure) when the scene cannot be loaded, so tests can bail out
## instead of crashing the whole runner.
func _spawn_player() -> PlayerController:
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	assert_not_null(packed, "player scene must load headlessly")
	if packed == null:
		return null
	var instance := packed.instantiate()
	assert_not_null(instance, "player scene must instantiate")
	if instance == null:
		return null
	assert_true(instance is PlayerController, "root node carries player_controller.gd")
	_player = instance as PlayerController
	if _player == null:
		return null
	add_to_tree(_player)
	return _player


func _attack() -> AttackController:
	return _player.get_node(^"AttackController") as AttackController


func test_scene_loads_and_instantiates_headlessly() -> void:
	## AC-10: no parser or script errors while loading the player scene.
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		fail("res://actors/player/player.tscn failed to load")
		return
	assert_true(packed.can_instantiate(), "the packed scene can be instantiated")
	var player := _spawn_player()
	if player == null:
		return
	assert_true(player.is_inside_tree(), "the player runs in the scene tree")
	assert_false(player.is_dead, "a fresh player is alive")


func test_required_children_exist_with_exact_names() -> void:
	## ADR-005: `HealthComponent` must be a DIRECT child with that exact name,
	## because `AttackController` resolves damage receivers by that name.
	var player := _spawn_player()
	if player == null:
		return

	var health := player.get_node_or_null(^"HealthComponent") as HealthComponent
	assert_not_null(health, "Player/HealthComponent exists (ADR-005)")
	if health != null:
		assert_eq(health.get_parent(), player, "HealthComponent is a direct child of the actor")

	var attack := player.get_node_or_null(^"AttackController") as AttackController
	assert_not_null(attack, "Player/AttackController exists")
	assert_not_null(player.get_node_or_null(^"HitDetector") as HitDetector, "Player/HitDetector exists")

	var shape := player.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	assert_not_null(shape, "Player/CollisionShape3D exists")
	if shape != null:
		var capsule := shape.shape as CapsuleShape3D
		assert_not_null(capsule, "the body shape is a capsule")
		if capsule != null:
			assert_almost_eq(capsule.radius, 0.4, 0.0001, "capsule radius")
			assert_almost_eq(capsule.height, 1.8, 0.0001, "capsule height")
		assert_almost_eq(shape.position.y, 0.9, 0.0001, "the capsule stands on the floor")

	var head := player.get_node_or_null(^"Head") as Node3D
	assert_not_null(head, "Player/Head exists")
	if head != null:
		assert_almost_eq(head.position.y, 1.6, 0.0001, "eye height")

	var camera := player.get_node_or_null(^"Head/Camera3D") as Camera3D
	assert_not_null(camera, "Player/Head/Camera3D exists")
	if camera != null:
		assert_true(camera.current, "the player camera is current")

	var viewmodel := player.get_node_or_null(^"Head/Camera3D/Viewmodel") as PlayerViewModel
	assert_not_null(viewmodel, "Player/Head/Camera3D/Viewmodel exists")
	if viewmodel == null:
		return
	for mesh_name in [&"Blade", &"Grip"]:
		var mesh_node := viewmodel.get_node_or_null(NodePath(mesh_name)) as MeshInstance3D
		assert_not_null(mesh_node, "viewmodel child %s exists" % mesh_name)
		if mesh_node != null:
			assert_not_null(mesh_node.mesh as BoxMesh, "%s uses a BoxMesh" % mesh_name)
			assert_not_null(
				mesh_node.material_override as StandardMaterial3D,
				"%s has the greybox material" % mesh_name
			)


func test_collision_layer_and_mask_match_physics_layers() -> void:
	var player := _spawn_player()
	if player == null:
		return
	assert_eq(player.collision_layer, PhysicsLayers.PLAYER_BODY, "player body layer")
	assert_eq(
		player.collision_mask,
		PhysicsLayers.WORLD | PhysicsLayers.ENEMY_BODY,
		"player movement mask: world + enemy bodies"
	)
	assert_eq(
		player.collision_mask,
		PhysicsLayers.movement_mask(PhysicsLayers.PLAYER_BODY),
		"mask matches the PhysicsLayers helper"
	)


func test_attack_definition_is_valid_and_matches_the_content_contract() -> void:
	var player := _spawn_player()
	if player == null:
		return
	var attack := _attack()
	if attack == null:
		fail("Player/AttackController missing")
		return
	var definition := attack.definition
	assert_not_null(definition, "the attack controller has a definition")
	if definition == null:
		return
	assert_true(definition is AttackDefinition, "definition is an AttackDefinition resource")
	assert_true(definition.is_valid(), "definition is valid: %s" % definition.validation_errors())
	assert_eq(definition.id, PLAYER_ATTACK_ID, "stable content id")
	assert_almost_eq(definition.damage, 34.0, 0.0001, "damage")
	assert_almost_eq(definition.reach, 2.0, 0.0001, "reach")
	assert_almost_eq(definition.hit_radius, 0.3, 0.0001, "hit radius")
	assert_almost_eq(definition.hit_arc_degrees, 60.0, 0.0001, "front arc")
	assert_almost_eq(definition.windup, 0.22, 0.0001, "windup")
	assert_almost_eq(definition.active_window, 0.1, 0.0001, "active window")
	assert_almost_eq(definition.recovery, 0.38, 0.0001, "recovery")
	assert_almost_eq(definition.cooldown, 0.6, 0.0001, "cooldown")
	assert_eq(
		load(ATTACK_SCENE_PATH),
		definition,
		"the scene uses content/definitions/%s" % ATTACK_SCENE_PATH.get_file()
	)


func test_attack_controller_is_wired_to_camera_body_and_detector() -> void:
	var player := _spawn_player()
	if player == null:
		return
	var attack := _attack()
	if attack == null:
		fail("Player/AttackController missing")
		return
	assert_eq(attack.source_id, &"player", "stable source id")
	assert_eq(
		attack.hit_origin,
		player.get_node(^"Head/Camera3D"),
		"hit_origin is the camera (the hit frame originates at eye height)"
	)
	assert_eq(attack.owner_body, player, "owner_body is excluded from its own hit query")
	assert_eq(attack.hit_detector, player.get_node(^"HitDetector"), "hit_detector is wired")
	if attack.hit_detector != null:
		assert_eq(
			attack.hit_detector.target_mask,
			PhysicsLayers.ENEMY_BODY,
			"the player only damages enemy bodies"
		)
		assert_eq(
			attack.hit_detector.blocker_mask,
			PhysicsLayers.WORLD,
			"world geometry occludes player attacks"
		)
	assert_true(attack.can_attack(), "a fresh player can attack")


func test_health_component_starts_alive_at_full_hp() -> void:
	var player := _spawn_player()
	if player == null:
		return
	var health := player.get_node(^"HealthComponent") as HealthComponent
	if health == null:
		fail("Player/HealthComponent missing")
		return
	assert_eq(health.max_health, EXPECTED_MAX_HEALTH, "max HP")
	assert_eq(health.current_health, EXPECTED_MAX_HEALTH, "starts at full HP")
	assert_true(health.is_alive(), "starts alive")
	assert_eq(health.actor_id, &"player", "stable actor id")


func test_viewmodel_follows_attack_phases_and_returns_to_rest() -> void:
	var player := _spawn_player()
	if player == null:
		return
	var viewmodel := player.get_node_or_null(^"Head/Camera3D/Viewmodel") as PlayerViewModel
	if viewmodel == null:
		fail("Player/Head/Camera3D/Viewmodel missing")
		return
	assert_eq(
		viewmodel.attack_controller,
		player.get_node(^"AttackController"),
		"the viewmodel reads the scene's attack controller"
	)
	var attack := _attack()
	if attack == null:
		return
	# Deterministic: phases are stepped by hand, never by the physics tick.
	attack.set_physics_process(false)
	var rest_position: Vector3 = viewmodel.position

	assert_true(attack.request_attack(), "a swing starts")
	assert_eq(attack.phase, AttackController.Phase.WINDUP, "phase is windup")
	await _settle_viewmodel(viewmodel)
	assert_true(
		viewmodel.position.distance_to(rest_position + viewmodel.windup_offset) < 0.01,
		"windup pulls the weapon off the rest pose"
	)

	attack.advance(attack.definition.windup + 0.001)
	assert_eq(attack.phase, AttackController.Phase.ACTIVE, "phase is active")
	await _settle_viewmodel(viewmodel)
	assert_true(
		viewmodel.position.distance_to(rest_position + viewmodel.active_offset) < 0.01,
		"the active window thrusts the weapon forward"
	)

	attack.advance(attack.definition.active_window + 0.001)
	assert_eq(attack.phase, AttackController.Phase.RECOVERY, "phase is recovery")
	await _settle_viewmodel(viewmodel)
	assert_true(
		viewmodel.position.distance_to(rest_position + viewmodel.recovery_offset) < 0.01,
		"recovery eases the weapon back"
	)

	attack.advance(attack.definition.recovery + 0.001)
	assert_eq(attack.phase, AttackController.Phase.IDLE, "the swing ends")
	await _settle_viewmodel(viewmodel)
	assert_true(
		viewmodel.position.distance_to(rest_position) < 0.01,
		"IDLE restores the rest pose"
	)


func test_removing_the_viewmodel_does_not_change_combat_behaviour() -> void:
	## The viewmodel is presentation only (ADR-001 layer 4). Deleting it must
	## leave phases, timing and hit resolution exactly as they were.
	var player := _spawn_player()
	if player == null:
		return
	var viewmodel := player.get_node_or_null(^"Head/Camera3D/Viewmodel")
	if viewmodel == null:
		fail("Player/Head/Camera3D/Viewmodel missing")
		return
	viewmodel.free()

	var attack := _attack()
	if attack == null:
		fail("Player/AttackController missing")
		return
	attack.set_physics_process(false)
	assert_true(attack.request_attack(), "a swing still starts without the viewmodel")
	attack.advance(attack.definition.windup + 0.001)
	assert_eq(attack.phase, AttackController.Phase.ACTIVE, "the hit frame still happens")
	assert_not_null(attack.last_result(), "the hit frame still resolves to a result")
	attack.advance(1.0)
	assert_eq(attack.phase, AttackController.Phase.IDLE, "the swing still completes")
	assert_true(attack.can_attack(), "and the next swing is available after cooldown")


## Runs `_process` with a fixed delta until the pose has converged. Deterministic:
## no wall-clock waiting.
func _settle_viewmodel(viewmodel: PlayerViewModel) -> void:
	for _i in 40:
		viewmodel._process(0.05)
	await wait_process_frames(1)
