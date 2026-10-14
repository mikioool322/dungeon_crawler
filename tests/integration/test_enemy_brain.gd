extends "res://tests/test_case.gd"

## Physics-level behaviour of the enemy rig: the shipped `actors/enemies/enemy.tscn`
## driven by its `EnemyBrain` adapter against a synthetic target (ADR-005, ADR-006,
## AC-06, AC-07 and the sprint escape window).
##
## The player scene belongs to another work item and is deliberately not used: the
## target here is a bare `CharacterBody3D` on `PhysicsLayers.PLAYER_BODY` with a
## direct child named "HealthComponent", which is the entire hit-resolution scene
## contract the enemy needs.
##
## Frame budgets are in physics frames (60 Hz by default). The shipped windup is
## 0.7 s (~42 frames), so a "the swing lands" assertion needs ~45 frames and the
## per-scenario budget below stays under two simulated seconds.

const ENEMY_SCENE_PATH := "res://actors/enemies/enemy.tscn"
const TARGET_MAX_HEALTH := 100.0
const ATTACK_DAMAGE := 12.0

## Plausible backpedal speed used by the escape test (m/s).
const RETREAT_SPEED := 4.0

const FRAMES_FOR_STATE := 10
const FRAMES_FOR_DAMAGE := 90
const FRAMES_FOR_SETTLE := 20

var _world: Node3D
var _enemy: EnemyBrain
var _enemy_health: HealthComponent
var _attack: AttackController
var _target: CharacterBody3D
var _target_health: HealthComponent
var _state_log: Array[Vector2i] = []


func teardown() -> void:
	_world = null
	_enemy = null
	_enemy_health = null
	_attack = null
	_target = null
	_target_health = null
	_state_log.clear()


# --- fixture -----------------------------------------------------------------

func _build_world(
	target_offset: Vector3, spawn_target: bool = true, with_wall: bool = false
) -> void:
	_world = Node3D.new()
	_world.name = &"GreyboxWorld"
	add_to_tree(_world)
	_add_floor()
	if with_wall:
		_add_wall(Vector3(0, 1.25, -0.9), Vector3(2.0, 2.5, 0.3))

	var scene := load(ENEMY_SCENE_PATH) as PackedScene
	assert_not_null(scene, "the enemy scene loads")
	if scene == null:
		return
	_enemy = scene.instantiate() as EnemyBrain
	assert_not_null(_enemy, "the enemy scene root uses EnemyBrain")
	if _enemy == null:
		return
	_world.add_child(_enemy)
	_enemy.state_changed.connect(_on_enemy_state_changed)
	_enemy_health = _enemy.get_node(^"HealthComponent") as HealthComponent
	_attack = _enemy.get_node(^"AttackController") as AttackController

	if spawn_target:
		_target = _make_target(target_offset)
		_world.add_child(_target)
		_enemy.set_target(_target)
	await wait_physics_frames(2)


func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = &"Floor"
	floor_body.collision_layer = PhysicsLayers.WORLD
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	_world.add_child(floor_body)


func _add_wall(position: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.name = &"Wall"
	wall.collision_layer = PhysicsLayers.WORLD
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	wall.position = position
	_world.add_child(wall)


func _make_target(offset: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = &"SyntheticTarget"
	body.collision_layer = PhysicsLayers.PLAYER_BODY
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	body.add_child(shape)
	var health := HealthComponent.new()
	health.name = &"HealthComponent"  # ADR-005 scene contract
	health.max_health = TARGET_MAX_HEALTH
	health.actor_id = &"player.synthetic"
	body.add_child(health)
	body.position = offset
	_target_health = health
	return body


func _on_enemy_state_changed(previous: int, next: int) -> void:
	_state_log.append(Vector2i(previous, next))


func _wait_until(condition: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		if condition.call():
			return true
		await wait_physics_frames(1)
	return condition.call()


func _horizontal_distance_to_target() -> float:
	return MeleeRules.horizontal_distance(_enemy.global_position, _target.global_position)


# --- scene contract ----------------------------------------------------------

func test_scene_wires_the_combat_components_and_owns_its_material() -> void:
	await _build_world(Vector3(0, 0, -5))
	assert_not_null(_enemy.definition, "definition wired on the scene root")
	assert_eq(_enemy.definition.id, &"enemy.grunt", "the shipped grunt is used")
	assert_not_null(_attack, "AttackController present")
	if _attack != null:
		assert_not_null(_attack.definition, "attack definition wired")
		assert_not_null(_attack.hit_origin, "hit origin wired (Muzzle)")
		assert_not_null(_attack.hit_detector, "hit detector wired")
		assert_eq(_attack.owner_body, _enemy, "owner body is the enemy itself")
		assert_eq(_attack.source_id, &"enemy.grunt", "stable attacker id")
		if _attack.hit_detector != null:
			assert_eq(
				_attack.hit_detector.target_mask,
				PhysicsLayers.PLAYER_BODY,
				"enemy hit queries target the player body layer"
			)
			assert_eq(
				_attack.hit_detector.blocker_mask,
				PhysicsLayers.WORLD,
				"world geometry occludes enemy hits"
			)
	assert_eq(_enemy.collision_layer, PhysicsLayers.ENEMY_BODY, "enemy body layer")
	assert_eq(
		_enemy.collision_mask,
		PhysicsLayers.WORLD | PhysicsLayers.PLAYER_BODY,
		"enemy movement mask"
	)
	assert_eq(_enemy_health.max_health, 100.0, "HP is driven by the definition")
	assert_eq(_enemy_health.actor_id, &"enemy.grunt", "the actor id is driven by the definition")

	var body := _enemy.get_node(^"Body") as MeshInstance3D
	assert_not_null(body.material_override, "each enemy installs its own telegraph material")
	var second_scene := load(ENEMY_SCENE_PATH) as PackedScene
	var second := second_scene.instantiate() as EnemyBrain
	_world.add_child(second)
	var second_body := second.get_node(^"Body") as MeshInstance3D
	assert_ne(
		body.material_override,
		second_body.material_override,
		"two enemies never share one material instance"
	)


# --- detection, movement and loss -------------------------------------------

func test_no_target_stays_idle_and_still() -> void:
	await _build_world(Vector3.ZERO, false)
	var start := _enemy.global_position
	await wait_physics_frames(FRAMES_FOR_SETTLE)
	assert_eq(_enemy.fsm_state, EnemyFsm.State.IDLE, "no target -> IDLE")
	assert_almost_eq(_enemy.global_position.x, start.x, 0.01, "no horizontal drift on x")
	assert_almost_eq(_enemy.global_position.z, start.z, 0.01, "no horizontal drift on z")
	assert_eq(_state_log.size(), 0, "IDLE never announces a state change")


func test_visible_target_is_chased_and_the_distance_closes() -> void:
	await _build_world(Vector3(0, 0, -5))
	var chased := await _wait_until(
		func() -> bool: return _enemy.fsm_state == EnemyFsm.State.CHASE, FRAMES_FOR_STATE
	)
	assert_true(chased, "a visible target inside detection_radius starts the chase")
	assert_true(
		_state_log.has(Vector2i(EnemyFsm.State.IDLE, EnemyFsm.State.CHASE)),
		"state_changed reports IDLE -> CHASE for the HUD"
	)
	var distance_before := _horizontal_distance_to_target()
	await wait_physics_frames(20)
	var distance_after := _horizontal_distance_to_target()
	assert_true(
		distance_after < distance_before - 0.8,
		"the enemy closes the distance (%.2f -> %.2f)" % [distance_before, distance_after]
	)
	assert_eq(_enemy.fsm_state, EnemyFsm.State.CHASE, "still chasing at ~3.5 m")


func test_lost_target_returns_the_enemy_to_idle_and_stops_it() -> void:
	await _build_world(Vector3(0, 0, -5))
	var chased := await _wait_until(
		func() -> bool: return _enemy.fsm_state == EnemyFsm.State.CHASE, FRAMES_FOR_STATE
	)
	assert_true(chased, "chasing first")
	_target.position = Vector3(0, 0, -25)  # far beyond lose_radius (16 m)
	var gave_up := await _wait_until(
		func() -> bool: return _enemy.fsm_state == EnemyFsm.State.IDLE, FRAMES_FOR_STATE
	)
	assert_true(gave_up, "a target beyond lose_radius returns the enemy to IDLE")
	var stopped_at := _enemy.global_position
	await wait_physics_frames(FRAMES_FOR_SETTLE)
	assert_almost_eq(_enemy.global_position.z, stopped_at.z, 0.02, "the enemy stops moving")
	assert_almost_eq(_enemy.velocity.x, 0.0, 0.01, "no horizontal velocity on x")
	assert_almost_eq(_enemy.velocity.z, 0.0, 0.01, "no horizontal velocity on z")


func test_freed_target_returns_the_enemy_to_idle_without_errors() -> void:
	await _build_world(Vector3(0, 0, -5))
	var chased := await _wait_until(
		func() -> bool: return _enemy.fsm_state == EnemyFsm.State.CHASE, FRAMES_FOR_STATE
	)
	assert_true(chased, "chasing first")
	_target.queue_free()
	var gave_up := await _wait_until(
		func() -> bool: return _enemy.fsm_state == EnemyFsm.State.IDLE, FRAMES_FOR_STATE + 5
	)
	assert_true(gave_up, "a freed target returns the enemy to IDLE")
	assert_almost_eq(_enemy.velocity.x, 0.0, 0.01, "no horizontal velocity on x")
	assert_almost_eq(_enemy.velocity.z, 0.0, 0.01, "no horizontal velocity on z")


# --- the telegraphed swing ---------------------------------------------------

func test_in_range_target_is_telegraphed_then_damaged_while_standing_still() -> void:
	await _build_world(Vector3(0, 0, -1.6))
	var started := await _wait_until(
		func() -> bool: return _attack.phase != AttackController.Phase.IDLE, FRAMES_FOR_STATE
	)
	assert_true(started, "the enemy starts a swing inside attack_range")
	assert_eq(_enemy.fsm_state, EnemyFsm.State.ATTACK, "the FSM reports ATTACK during the swing")
	assert_almost_eq(
		_target_health.current_health, TARGET_MAX_HEALTH, 0.0001, "no damage during the windup"
	)

	var damaged := await _wait_until(
		func() -> bool: return _target_health.current_health < TARGET_MAX_HEALTH, FRAMES_FOR_DAMAGE
	)
	assert_true(damaged, "standing still inside reach takes the hit")
	assert_almost_eq(
		_target_health.current_health,
		TARGET_MAX_HEALTH - ATTACK_DAMAGE,
		0.0001,
		"one swing deals the definition damage"
	)
	var result := _attack.last_result()
	assert_not_null(result, "the swing produced a result")
	if result != null:
		assert_true(result.applied, "that result is an applied hit")
		assert_almost_eq(result.damage_dealt, ATTACK_DAMAGE, 0.0001, "damage matches the definition")
		assert_eq(result.target_id, &"player.synthetic", "the hit resolved the target's HealthComponent")


func test_target_backpedalling_during_the_windup_escapes_the_swing() -> void:
	## The sprint criterion: walking out of reach before the hit frame avoids all
	## damage. The swipe is never cancelled (no iframes, no dodge) - it simply
	## resolves as a miss against live physics state.
	await _build_world(Vector3(0, 0, -1.6))
	var started := await _wait_until(
		func() -> bool: return _attack.phase != AttackController.Phase.IDLE, FRAMES_FOR_STATE
	)
	assert_true(started, "the swing starts")
	var step_seconds := _world.get_physics_process_delta_time()
	for _i in 24:  # 0.4 s of backpedalling, well inside the 0.7 s windup
		_target.position.z -= RETREAT_SPEED * step_seconds
		await wait_physics_frames(1)

	var resolved := await _wait_until(
		func() -> bool: return _attack.last_result() != null, FRAMES_FOR_DAMAGE
	)
	assert_true(resolved, "the swing still resolves at its hit frame")
	var result := _attack.last_result()
	if result != null:
		assert_false(result.applied, "backpedalling out of reach avoids the hit")
		assert_eq(
			result.miss_reason,
			DamageResult.REASON_OUT_OF_REACH,
			"the miss is a range miss, got %s" % result.miss_reason
		)
	assert_almost_eq(_target_health.current_health, TARGET_MAX_HEALTH, 0.0001, "HP is untouched")
	assert_eq(_attack.abort_reason(), &"", "the swing was never cancelled")


func test_wall_between_enemy_and_target_blocks_the_attack() -> void:
	await _build_world(Vector3(0, 0, -1.6), true, true)
	await wait_physics_frames(FRAMES_FOR_SETTLE)
	assert_eq(_enemy.fsm_state, EnemyFsm.State.IDLE, "no line of sight -> never detects")
	assert_eq(_attack.phase, AttackController.Phase.IDLE, "no swing is started through the wall")
	assert_null(_attack.last_result(), "no hit was resolved")
	assert_almost_eq(_target_health.current_health, TARGET_MAX_HEALTH, 0.0001, "HP is untouched")
	await wait_physics_frames(60)
	assert_eq(_enemy.fsm_state, EnemyFsm.State.IDLE, "still idle after a simulated second")
	assert_almost_eq(
		_target_health.current_health, TARGET_MAX_HEALTH, 0.0001, "still untouched after a second"
	)


# --- death -------------------------------------------------------------------

func test_lethal_damage_aborts_the_swing_and_prevents_further_attacks() -> void:
	await _build_world(Vector3(0, 0, -1.6))
	var swinging := await _wait_until(
		func() -> bool: return _attack.phase == AttackController.Phase.WINDUP, FRAMES_FOR_STATE
	)
	assert_true(swinging, "a windup is in flight")
	_enemy_health.apply_damage(
		DamageRequest.new(&"test.lethal", &"test.runner", _enemy_health.max_health)
	)

	assert_false(_enemy_health.is_alive(), "the enemy is dead")
	assert_eq(_enemy.fsm_state, EnemyFsm.State.DEAD, "death enters DEAD immediately")
	assert_eq(_attack.phase, AttackController.Phase.IDLE, "the in-flight swing is aborted")
	assert_eq(_attack.abort_reason(), &"dead", "the abort is attributed to death")
	assert_true(
		_state_log.has(Vector2i(EnemyFsm.State.ATTACK, EnemyFsm.State.DEAD)),
		"state_changed reports the death transition"
	)

	await wait_physics_frames(FRAMES_FOR_DAMAGE)
	assert_eq(_enemy.fsm_state, EnemyFsm.State.DEAD, "the dead stay dead")
	assert_eq(_attack.phase, AttackController.Phase.IDLE, "no new swing after death")
	assert_almost_eq(
		_target_health.current_health,
		TARGET_MAX_HEALTH,
		0.0001,
		"the target standing in range is never hit"
	)
	assert_true(_enemy.velocity.length() < 0.05, "the corpse keeps zero velocity")
