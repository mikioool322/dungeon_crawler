extends "res://tests/test_case.gd"

## W3 movement, look and death behaviour with real physics (ADR-006).
##
## Fixture: a flat floor on `PhysicsLayers.WORLD` plus the real
## `actors/player/player.tscn`. All timing comes from `wait_physics_frames()`,
## never from wall-clock time, so the results are deterministic.

const PLAYER_SCENE_PATH := "res://actors/player/player.tscn"
const SPAWN_HEIGHT := 0.02
## Melee reach gate the backpedal has to beat: 1.7 m reach + 0.25 m tolerance.
const MELEE_REACH_GATE := 1.95
## Evasion budget: one full second of walking backwards at 4.0 m/s.
const ESCAPE_DISTANCE := 2.5

const HELD_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
]

var _world: Node3D
var _player: PlayerController


func teardown() -> void:
	# Never leak a virtual action press into the next test.
	for action: StringName in HELD_ACTIONS:
		Input.action_release(action)
	_world = null
	_player = null


## Physics time covered by `frames` physics steps, in seconds.
func _physics_seconds(frames: int) -> float:
	return float(frames) / float(Engine.physics_ticks_per_second)


func _horizontal_delta(from: Vector3, to: Vector3) -> Vector2:
	return Vector2(to.x - from.x, to.z - from.z)


func _mouse_motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event


func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _head() -> Node3D:
	return _player.get_node(^"Head") as Node3D


func _attack() -> AttackController:
	return _player.get_node(^"AttackController") as AttackController


func _health() -> HealthComponent:
	return _player.get_node(^"HealthComponent") as HealthComponent


## Builds the floor + player fixture and waits for it to settle. Returns false
## (with a recorded failure) when the scene cannot be loaded.
func _build_world() -> bool:
	_world = Node3D.new()
	add_to_tree(_world)

	var floor_body := StaticBody3D.new()
	floor_body.name = &"Floor"
	floor_body.collision_layer = PhysicsLayers.WORLD
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 1.0, 40.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_world.add_child(floor_body)

	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		fail("res://actors/player/player.tscn failed to load")
		return false
	_player = packed.instantiate() as PlayerController
	if _player == null:
		fail("player scene did not instantiate as PlayerController")
		return false
	_player.position = Vector3(0.0, SPAWN_HEIGHT, 0.0)
	_world.add_child(_player)
	await wait_physics_frames(5)
	return true


func test_player_lands_on_the_world_floor() -> void:
	## Control case for every test below: gravity resolves against `world`, so the
	## player really is standing on a floor while it walks.
	var built: bool = await _build_world()
	if not built:
		return
	assert_true(_player.is_on_floor(), "the player lands on PhysicsLayers.WORLD geometry")
	assert_true(
		absf(_player.global_position.y) < 0.05,
		"the capsule bottom rests on the floor (y=%.3f)" % _player.global_position.y
	)


func test_backpedal_moves_away_from_facing_at_move_speed() -> void:
	var frames := 40
	var built: bool = await _build_world()
	if not built:
		return
	var start := _player.global_position
	Input.action_press(&"move_back", 1.0)
	await wait_physics_frames(frames)
	Input.action_release(&"move_back")

	var delta := _horizontal_delta(start, _player.global_position)
	assert_true(
		delta.y > 0.0,
		"move_back moves away from the facing direction (-Z): delta=%s" % delta
	)
	assert_almost_eq(delta.x, 0.0, 0.05, "no sideways drift while backpedalling")
	var travelled: float = delta.length()
	var expected: float = _player.move_speed * _physics_seconds(frames)
	assert_almost_eq(
		travelled,
		expected,
		expected * 0.2,
		"backpedal distance ~= move_speed * time (%.2f m in %.2f s)" % [travelled, _physics_seconds(frames)]
	)


func test_one_second_of_backpedal_escapes_a_melee_reach() -> void:
	## AC-03's player half: the only evasion in Sprint 01 is physically leaving
	## reach (ADR-003). One second of backpedalling must clear the 1.95 m gate.
	var built: bool = await _build_world()
	if not built:
		return
	var start := _player.global_position
	Input.action_press(&"move_back", 1.0)
	await wait_physics_frames(Engine.physics_ticks_per_second)
	Input.action_release(&"move_back")

	var travelled: float = _horizontal_delta(start, _player.global_position).length()
	assert_true(
		travelled >= ESCAPE_DISTANCE,
		"one second of backpedal covers >= %.1f m (got %.2f m, melee gate %.2f m)" % [
			ESCAPE_DISTANCE, travelled, MELEE_REACH_GATE
		]
	)


func test_mouse_look_yaws_the_body_and_pitches_the_head() -> void:
	var built: bool = await _build_world()
	if not built:
		return
	assert_false(_player.mouse_captured, "a headless run never captures the OS cursor")
	var sensitivity: float = _player.mouse_sensitivity
	var head := _head()
	if head == null:
		fail("Player/Head missing")
		return

	# Not captured: motion must not move the view (the cursor is on the desktop).
	_player._unhandled_input(_mouse_motion(Vector2(200.0, 0.0)))
	assert_almost_eq(_player.rotation.y, 0.0, 0.0001, "look is gated on the cursor being captured")

	# Headless: this only flips the controller's flag, never the OS cursor.
	_player.mouse_captured = true
	_player._unhandled_input(_mouse_motion(Vector2(200.0, 0.0)))
	assert_almost_eq(
		_player.rotation.y,
		-200.0 * sensitivity,
		0.0001,
		"horizontal mouse motion yaws the body"
	)
	assert_almost_eq(head.rotation.x, 0.0, 0.0001, "horizontal motion does not pitch the head")

	_player._unhandled_input(_mouse_motion(Vector2(0.0, 120.0)))
	assert_almost_eq(
		head.rotation.x,
		-120.0 * sensitivity,
		0.0001,
		"vertical mouse motion pitches the head"
	)
	assert_almost_eq(
		_player.rotation.y,
		-200.0 * sensitivity,
		0.0001,
		"vertical motion does not change the body yaw"
	)


func test_pitch_is_clamped_so_the_camera_never_flips() -> void:
	var built: bool = await _build_world()
	if not built:
		return
	_player.mouse_captured = true
	var head := _head()
	if head == null:
		fail("Player/Head missing")
		return
	var limit: float = deg_to_rad(_player.pitch_limit_degrees)
	assert_almost_eq(limit, deg_to_rad(89.0), 0.0001, "the configured pitch limit is 89 degrees")

	for _i in 10:
		_player._unhandled_input(_mouse_motion(Vector2(0.0, -100000.0)))
	assert_almost_eq(head.rotation.x, limit, 0.0001, "upward pitch clamps at +89 degrees")
	assert_true(absf(head.rotation.x) <= limit + 0.0001, "pitch never exceeds the limit")

	for _i in 10:
		_player._unhandled_input(_mouse_motion(Vector2(0.0, 100000.0)))
	assert_almost_eq(head.rotation.x, -limit, 0.0001, "downward pitch clamps at -89 degrees")
	assert_true(absf(head.rotation.x) <= limit + 0.0001, "pitch never exceeds the limit")


func test_attack_starts_a_swing_and_movement_keeps_working_during_it() -> void:
	var built: bool = await _build_world()
	if not built:
		return
	var attack := _attack()
	if attack == null:
		fail("Player/AttackController missing")
		return
	# Deterministic: the phase machine is stepped by hand, never by the physics tick.
	attack.set_physics_process(false)

	_player._unhandled_input(_action_event(&"attack_primary", true))
	assert_eq(attack.phase, AttackController.Phase.WINDUP, "attack_primary starts a swing")
	assert_true(attack.is_busy(), "the swing is in progress")

	var start := _player.global_position
	Input.action_press(&"move_back", 1.0)
	await wait_physics_frames(10)
	Input.action_release(&"move_back")
	var travelled: float = _horizontal_delta(start, _player.global_position).length()

	assert_eq(attack.phase, AttackController.Phase.WINDUP, "the swing is still winding up")
	assert_true(
		travelled > 0.2,
		"movement is never locked by a swing (moved %.3f m mid-swing)" % travelled
	)

	# Close the swing deterministically; phase timing itself is W2's subject.
	attack.advance(attack.definition.windup + attack.definition.active_window + attack.definition.recovery + 0.01)
	assert_eq(attack.phase, AttackController.Phase.IDLE, "the swing completes")


func test_lethal_damage_sets_is_dead_aborts_the_swing_and_freezes_input() -> void:
	var built: bool = await _build_world()
	if not built:
		return
	var attack := _attack()
	var health := _health()
	if attack == null or health == null:
		fail("Player/AttackController or Player/HealthComponent missing")
		return
	attack.set_physics_process(false)
	assert_true(attack.request_attack(), "the player starts a swing")
	attack.advance(0.05)
	assert_eq(attack.phase, AttackController.Phase.WINDUP, "the swing is mid-windup")

	var lethal := DamageRequest.new(
		&"attack.test.lethal",
		&"enemy.grunt",
		health.max_health + 1.0,
		_player.global_position,
		Vector3.UP
	)
	var result := health.apply_damage(lethal)
	assert_true(result.target_died, "the lethal request kills the player")
	assert_true(_player.is_dead, "is_dead is set")
	assert_eq(attack.phase, AttackController.Phase.IDLE, "the in-flight swing is aborted")
	assert_eq(attack.abort_reason(), &"dead", "the abort reason is dead")

	var before := _player.global_position
	var yaw_before: float = _player.rotation.y
	Input.action_press(&"move_back", 1.0)
	await wait_physics_frames(20)
	Input.action_release(&"move_back")
	var moved: float = _horizontal_delta(before, _player.global_position).length()
	assert_true(moved < 0.01, "movement input is ignored after death (moved %.4f m)" % moved)

	_player._unhandled_input(_mouse_motion(Vector2(500.0, 0.0)))
	assert_almost_eq(_player.rotation.y, yaw_before, 0.0001, "look input is ignored after death")

	_player._unhandled_input(_action_event(&"attack_primary", true))
	assert_eq(attack.phase, AttackController.Phase.IDLE, "a dead player cannot start a swing")
