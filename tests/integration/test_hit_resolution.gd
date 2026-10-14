extends "res://tests/test_case.gd"

## AC-01 / AC-02 / AC-03 / AC-04 with real physics: a hit frame is resolved against
## live collision state, so stepping out of reach before that frame is a miss.
##
## Fixture: flat floor, an attacker body with an eye-height hit origin looking down
## -Z, and a humanoid target capsule on the enemy layer with a HealthComponent.

const TARGET_START := Vector3(0, 0, -1.5)

var _world: Node3D
var _attacker: CharacterBody3D
var _origin: Node3D
var _controller: AttackController
var _detector: HitDetector
var _definition: AttackDefinition


func setup() -> void:
	_definition = AttackDefinition.new()
	_definition.id = &"attack.test.basic"
	_definition.damage = 25.0
	_definition.reach = 1.7
	_definition.hit_radius = 0.25
	_definition.hit_arc_degrees = 60.0
	_definition.windup = 0.3
	_definition.active_window = 0.1
	_definition.recovery = 0.4
	_definition.cooldown = 1.0


func teardown() -> void:
	_world = null
	_attacker = null
	_origin = null
	_controller = null
	_detector = null


func _make_body(layer: int, radius: float, height: float) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	shape.shape = capsule
	body.add_child(shape)
	return body


func _build_world() -> void:
	_world = Node3D.new()
	add_to_tree(_world)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60, 1, 60)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	_world.add_child(floor_body)

	_attacker = _make_body(PhysicsLayers.PLAYER_BODY, 0.4, 1.8)
	# Real rigs are damageable; giving the fixture attacker HP makes the
	# self-exclusion test meaningful (see test_attacker_does_not_hit_itself).
	var attacker_health := HealthComponent.new()
	attacker_health.name = &"HealthComponent"
	attacker_health.max_health = 100.0
	attacker_health.actor_id = &"tester"
	_attacker.add_child(attacker_health)
	_world.add_child(_attacker)

	_origin = Node3D.new()
	_origin.position = Vector3(0, 1.6, 0)
	_attacker.add_child(_origin)

	_detector = HitDetector.new()
	_detector.target_mask = PhysicsLayers.ENEMY_BODY
	_detector.blocker_mask = PhysicsLayers.WORLD
	_world.add_child(_detector)

	_controller = AttackController.new()
	_controller.definition = _definition
	_controller.source_id = &"player"
	_controller.auto_tick = false
	_controller.hit_origin = _origin
	_controller.owner_body = _attacker
	_controller.hit_detector = _detector
	_world.add_child(_controller)

	await wait_physics_frames(2)


func _spawn_target(position: Vector3, health_max: float = 100.0, shapes: int = 1) -> CharacterBody3D:
	var target := _make_body(PhysicsLayers.ENEMY_BODY, 0.4, 1.8)
	target.position = position
	if shapes > 1:
		var extra_shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.4
		extra_shape.shape = sphere
		target.add_child(extra_shape)
	var health := HealthComponent.new()
	health.name = &"HealthComponent"
	health.max_health = health_max
	health.actor_id = &"enemy.grunt"
	target.add_child(health)
	_world.add_child(target)
	return target


func _add_wall(position: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	wall.position = position
	_world.add_child(wall)
	return wall


func _swing_and_resolve() -> DamageResult:
	## Waits out any cooldown, starts a fresh swing and returns its outcome.
	_wait_for_cooldown()
	_controller.request_attack()
	return _resolve_pending_swing()


func _resolve_pending_swing() -> DamageResult:
	## Advances the in-flight swing until its hit frame has been resolved.
	for _i in 200:
		if _controller.last_result() != null:
			break
		_controller.advance(0.01)
	var result := _controller.last_result()
	_finish_swing()
	return result


func _finish_swing() -> void:
	for _i in 200:
		if _controller.phase == AttackController.Phase.IDLE:
			return
		_controller.advance(0.02)


func _wait_for_cooldown() -> void:
	if _controller.is_busy():
		fail("_wait_for_cooldown called while a swing is in flight")
		return
	for _i in 400:
		if _controller.can_attack():
			return
		_controller.advance(0.02)


func _health_of(target: CharacterBody3D) -> HealthComponent:
	return target.get_node(^"HealthComponent") as HealthComponent


func test_in_reach_target_is_hit_once_for_the_definition_damage() -> void:
	await _build_world()
	var target := _spawn_target(TARGET_START)
	await wait_physics_frames(2)
	var result := _swing_and_resolve()
	assert_true(result.applied, "hit applied")
	assert_eq(result.damage_dealt, 25.0, "damage matches the definition")
	assert_eq(result.target_id, &"enemy.grunt", "result carries the stable id")
	assert_eq(_health_of(target).current_health, 75.0, "target HP reduced exactly once")
	assert_false(result.target_died, "target still alive")


func test_target_out_of_reach_is_missed_and_undamaged() -> void:
	await _build_world()
	var target := _spawn_target(Vector3(0, 0, -2.6))  # gate is 1.7 + 0.25 = 1.95 m
	await wait_physics_frames(2)
	var result := _swing_and_resolve()
	assert_false(result.applied, "no hit")
	assert_eq(result.miss_reason, DamageResult.REASON_OUT_OF_REACH, "explicit out_of_reach reason")
	assert_eq(_health_of(target).current_health, 100.0, "HP untouched")


func test_target_retreating_during_windup_is_missed() -> void:
	## AC-03 — the core sprint mechanic: backpedal out of reach before the hit frame.
	## The probe still finds the target, so the miss is explained as a range miss.
	await _build_world()
	var target := _spawn_target(TARGET_START)
	await wait_physics_frames(2)
	_controller.request_attack()
	_controller.advance(_definition.windup * 0.5)  # still winding up
	target.position = Vector3(0, 0, -2.4)  # walked backwards past the 1.95 m gate
	await wait_physics_frames(2)  # physics sees the new transform
	var result := _resolve_pending_swing()
	assert_false(result.applied, "walking backwards avoids the hit")
	assert_eq(
		result.miss_reason,
		DamageResult.REASON_OUT_OF_REACH,
		"reason is range, got %s" % result.miss_reason
	)
	assert_eq(_health_of(target).current_health, 100.0, "no damage dealt")


func test_target_far_out_of_reach_is_missed_as_no_target() -> void:
	## Retreating far beyond the probe volume is still a miss, reported as no_target.
	await _build_world()
	var target := _spawn_target(Vector3(0, 0, -6.0))
	await wait_physics_frames(2)
	var result := _swing_and_resolve()
	assert_false(result.applied, "a distant target is never hit")
	assert_eq(result.miss_reason, DamageResult.REASON_NO_TARGET, "no candidate was in the probe volume")
	assert_eq(_health_of(target).current_health, 100.0, "no damage dealt")


func test_target_that_stays_in_place_is_still_hit() -> void:
	## Control case for AC-03: same timing, no retreat.
	await _build_world()
	var target := _spawn_target(TARGET_START)
	await wait_physics_frames(2)
	_controller.request_attack()
	_controller.advance(_definition.windup * 0.5)
	await wait_physics_frames(4)
	var result := _resolve_pending_swing()
	assert_true(result.applied, "standing still inside reach gets hit")
	assert_eq(_health_of(target).current_health, 75.0, "damage applied")


func test_overlapping_collision_shapes_apply_damage_once() -> void:
	await _build_world()
	var target := _spawn_target(TARGET_START, 100.0, 2)  # two shapes at the same place
	await wait_physics_frames(2)
	var result := _swing_and_resolve()
	assert_true(result.applied, "hit applied")
	assert_eq(_health_of(target).current_health, 75.0, "two overlapping contacts deal one hit worth of damage")


func test_wall_blocks_the_attack() -> void:
	await _build_world()
	_add_wall(Vector3(0, 1.25, -0.9), Vector3(2.0, 2.5, 0.3))
	var target := _spawn_target(Vector3(0, 0, -1.6))
	await wait_physics_frames(3)
	var result := _swing_and_resolve()
	assert_false(result.applied, "no damage through a wall")
	assert_eq(result.miss_reason, DamageResult.REASON_OCCLUDED, "explicit occlusion reason")
	assert_eq(_health_of(target).current_health, 100.0, "HP untouched")


func test_target_behind_the_attacker_is_not_hit() -> void:
	await _build_world()
	var target := _spawn_target(Vector3(0, 0, 1.5))  # behind the -Z facing attacker
	await wait_physics_frames(2)
	var result := _swing_and_resolve()
	assert_false(result.applied, "the attack does not reach behind the attacker")
	assert_eq(result.miss_reason, DamageResult.REASON_OUT_OF_ARC, "explicit arc reason")
	assert_eq(_health_of(target).current_health, 100.0, "HP untouched")


func test_attacker_does_not_hit_itself() -> void:
	## The attacker is damageable here (like the real rig), so this test can only
	## pass because its own body RID is excluded from the hit query: without the
	## exclusion the swing would land on the attacker instead of the target.
	await _build_world()
	_detector.target_mask = PhysicsLayers.ENEMY_BODY | PhysicsLayers.PLAYER_BODY
	var target := _spawn_target(TARGET_START)
	await wait_physics_frames(2)
	var attacker_health := _health_of(_attacker)
	assert_eq(attacker_health.current_health, 100.0, "the attacker starts at full HP")
	var result := _swing_and_resolve()
	assert_true(result.applied, "the target in front is still hit")
	assert_eq(result.target_id, &"enemy.grunt", "the hit landed on the target, not on the attacker")
	assert_eq(attacker_health.current_health, 100.0, "the attacker's own body is excluded from its query")
	assert_eq(_health_of(target).current_health, 75.0, "the target took exactly one hit")


func test_dead_target_cannot_be_damaged_again() -> void:
	await _build_world()
	var target := _spawn_target(TARGET_START, 25.0)  # one hit kills
	await wait_physics_frames(2)
	var first := _swing_and_resolve()
	assert_true(first.target_died, "first swing is lethal")
	var second := _swing_and_resolve()
	assert_false(second.applied, "a corpse cannot be damaged again")
	assert_eq(second.miss_reason, DamageResult.REASON_TARGET_DEAD, "explicit reason")


func test_two_targets_both_take_one_hit_per_swing() -> void:
	await _build_world()
	var left := _spawn_target(Vector3(-0.5, 0, -1.4))
	var right := _spawn_target(Vector3(0.5, 0, -1.4))
	await wait_physics_frames(2)
	var result := _swing_and_resolve()
	assert_true(result.applied, "the nearest target is hit")
	assert_eq(_health_of(left).current_health, 75.0, "left target damaged once")
	assert_eq(_health_of(right).current_health, 75.0, "right target damaged once")


func test_aborted_swing_does_not_damage_a_target() -> void:
	await _build_world()
	var target := _spawn_target(TARGET_START)
	await wait_physics_frames(2)
	_controller.request_attack()
	_controller.advance(_definition.windup * 0.5)
	_controller.abort(&"dead")  # the attacker died mid-swing
	_controller.advance(1.0)
	assert_eq(_health_of(target).current_health, 100.0, "an aborted swing deals no damage")
	assert_null(_controller.last_result(), "no result was produced")
