extends "res://tests/test_case.gd"

## W6 whole-loop encounter tests (AC-01/AC-03/AC-06/AC-07 at rig level).
##
## Every scenario runs the **real** `res://world/prototype/proto_arena.tscn` with the
## real `actors/player/player.tscn` and `actors/enemies/enemy.tscn` fighting each
## other: no synthetic bodies. The synthetic-body coverage of the same rules lives in
## `tests/integration/test_hit_resolution.gd` / `test_enemy_brain.gd`.
##
## Determinism: attack timing is stepped by the real physics tick (`auto_tick = true`,
## as shipped), movement uses real `CharacterBody3D` physics, and every wait is
## counted in physics frames. The enemy is yawed at placement so no assertion depends
## on how fast it turns; in the melee scenarios the rigs start inside `stop_distance`,
## so they close no distance before the hit frame and the geometry asserted below is
## the geometry the hit frame sees.
##
## Geometry used throughout (the player's facing is -Z, the enemy faces +Z):
##   player (0, 0.05, 0)  --facing-->  enemy (0, 0.05, -1.2)
## The enemy's `Muzzle` is 0.6 m in front of its origin, so the shipped range gate
## (`reach 1.7 + hit_radius 0.25 = 1.95 m`) is measured from (0, 1.35, -0.6).

const ARENA_SCENE_PATH := "res://world/prototype/proto_arena.tscn"

const PLAYER_ORIGIN := Vector3(0.0, 0.05, 0.0)
const ENEMY_IN_FRONT := Vector3(0.0, 0.05, -1.2)

const PLAYER_MAX_HEALTH := 100.0
const ENEMY_MAX_HEALTH := 100.0
const ENEMY_DAMAGE := 12.0
const PLAYER_DAMAGE := 34.0

## Horizontal gate the enemy swing has to beat (attack_enemy_basic.tres).
const ENEMY_RANGE_GATE := 1.95

## Frames budgeted for one enemy swing to resolve (0.7 s windup + slack at 60 Hz).
const FRAMES_FOR_SWING := 90

const HELD_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"attack_primary",
]

var _arena: Node3D
var _state_log: Array[Vector2i] = []
## Number of `attack_resolved` emissions seen on the enemy's controller.
var _enemy_swings_resolved: int = 0


func teardown() -> void:
	# Never leak a virtual action press into the next test.
	for action: StringName in HELD_ACTIONS:
		Input.action_release(action)
	_arena = null
	_state_log.clear()
	_enemy_swings_resolved = 0


# --- fixture -----------------------------------------------------------------

func _instantiate_arena() -> bool:
	## Instantiates the shipped arena into the runner's tree and connects the enemy's
	## FSM log. Returns false (with a recorded failure) when the scene cannot load.
	var scene := load(ARENA_SCENE_PATH) as PackedScene
	assert_not_null(scene, "the arena scene loads: %s" % ARENA_SCENE_PATH)
	if scene == null:
		return false
	_arena = scene.instantiate() as Node3D
	assert_not_null(_arena, "the arena scene instantiates as Node3D")
	if _arena == null:
		return false
	add_to_tree(_arena)
	var enemy := _enemy()
	if enemy == null:
		fail("arena/Enemy is missing or does not use EnemyBrain")
		return false
	enemy.state_changed.connect(_on_enemy_state_changed)
	var attack := _enemy_attack()
	if attack != null:
		attack.attack_resolved.connect(_on_enemy_attack_resolved)
	return true


func _on_enemy_attack_resolved(_result: DamageResult) -> void:
	_enemy_swings_resolved += 1


func _player() -> PlayerController:
	return _arena.get_node_or_null(^"Player") as PlayerController


func _enemy() -> EnemyBrain:
	return _arena.get_node_or_null(^"Enemy") as EnemyBrain


func _player_health() -> HealthComponent:
	return _player().get_node_or_null(^"HealthComponent") as HealthComponent


func _enemy_health() -> HealthComponent:
	return _enemy().get_node_or_null(^"HealthComponent") as HealthComponent


func _player_attack() -> AttackController:
	return _player().get_node_or_null(^"AttackController") as AttackController


func _enemy_attack() -> AttackController:
	return _enemy().get_node_or_null(^"AttackController") as AttackController


## The player rig's attack definition, with a recorded failure instead of a null
## dereference (a runtime error would silently truncate a test's assertions).
func _player_attack_definition() -> AttackDefinition:
	var attack := _player_attack()
	if attack == null or attack.definition == null:
		fail("the player rig has no attack definition")
		return AttackDefinition.new()
	return attack.definition


## One of the arena HUD's labels, so death feedback is asserted at rig level too.
func _hud_label(node_path: NodePath) -> Label:
	var hud := _arena.get_node_or_null(^"Hud") as ArenaDebugHud
	if hud == null:
		fail("arena/Hud is missing")
		return null
	return hud.get_node_or_null(node_path) as Label


## Yaw that makes `from` face `to` on the horizontal plane (same formula as the
## actors themselves use), so the hit origin points at the target from frame 0.
func _yaw_to(from: Vector3, to: Vector3) -> float:
	var direction := to - from
	direction.y = 0.0
	if direction.length_squared() <= 0.000001:
		return 0.0
	direction = direction.normalized()
	return atan2(-direction.x, -direction.z)


## Places both real rigs and lets physics settle. The enemy is yawed immediately so
## the swing geometry never depends on `EnemyBrain.TURN_SPEED`.
func _place_and_settle(player_position: Vector3, enemy_position: Vector3) -> bool:
	var player := _player()
	var enemy := _enemy()
	if player == null or enemy == null:
		fail("arena is missing Player or Enemy")
		return false
	player.position = player_position
	player.rotation.y = _yaw_to(player_position, enemy_position)
	enemy.position = enemy_position
	enemy.rotation.y = _yaw_to(enemy_position, player_position)
	await wait_physics_frames(3)
	return true


func _on_enemy_state_changed(previous: int, next: int) -> void:
	_state_log.append(Vector2i(previous, next))


func _wait_until(condition: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		if condition.call():
			return true
		await wait_physics_frames(1)
	return condition.call()


func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _horizontal_delta(from: Vector3, to: Vector3) -> Vector2:
	return Vector2(to.x - from.x, to.z - from.z)


func _gate_distance_to_player() -> float:
	return MeleeRules.horizontal_distance(
		_enemy_attack().hit_origin.global_position, _player().global_position
	)


# --- A. the enemy's damage lands on the real player rig (AC-01) --------------

func test_a_enemy_swing_damages_the_player_rig_exactly_once() -> void:
	if not await _instantiate_arena():
		return
	if not await _place_and_settle(PLAYER_ORIGIN, ENEMY_IN_FRONT):
		return
	var enemy := _enemy()
	var attack := _enemy_attack()
	var health := _player_health()
	assert_almost_eq(health.current_health, PLAYER_MAX_HEALTH, 0.0001, "player starts at full HP")

	var started := await _wait_until(
		func() -> bool: return attack.phase == AttackController.Phase.WINDUP, 20
	)
	assert_true(started, "the enemy telegraphs a swing while the player stands inside reach")
	assert_almost_eq(health.current_health, PLAYER_MAX_HEALTH, 0.0001, "no damage before the hit frame")
	assert_true(
		_gate_distance_to_player() <= ENEMY_RANGE_GATE,
		"the standing player is inside the %.2f m gate at the windup (%.2f m)" % [
			ENEMY_RANGE_GATE, _gate_distance_to_player()
		]
	)

	var resolved := await _wait_until(
		func() -> bool: return attack.last_result() != null, FRAMES_FOR_SWING
	)
	assert_true(resolved, "the swing resolves at its hit frame")
	var result := attack.last_result()
	assert_not_null(result, "the swing produced a DamageResult")
	if result != null:
		assert_true(result.applied, "the standing player rig takes the hit (%s)" % result)
		assert_almost_eq(result.damage_dealt, ENEMY_DAMAGE, 0.0001, "damage matches the definition")
		assert_eq(result.target_id, &"player", "the hit resolved the player's HealthComponent")
	assert_almost_eq(
		health.current_health,
		PLAYER_MAX_HEALTH - ENEMY_DAMAGE,
		0.0001,
		"exactly one definition worth of damage: 100 -> 88"
	)
	assert_false(_player().is_dead, "one grunt swing never kills the player")

	var chased := await _wait_until(
		func() -> bool: return enemy.fsm_state == EnemyFsm.State.CHASE, FRAMES_FOR_SWING
	)
	assert_true(chased, "the enemy returns to CHASE after the swing (damaged-target flow)")
	assert_true(
		_state_log.has(Vector2i(EnemyFsm.State.ATTACK, EnemyFsm.State.CHASE)),
		"the FSM log shows ATTACK -> CHASE, transitions: %s" % [_state_log]
	)


# --- B + C. backpedal evasion and its control (AC-03, headline criterion) ----

## One scenario body shared by B and C: they differ *only* in the movement input.
## Returns the observed outcome so both tests can assert their own contract.
func _run_swing_against_player(retreat: bool) -> Dictionary:
	var attack := _enemy_attack()
	var health := _player_health()
	var player := _player()
	var health_before := health.current_health
	var start_position := player.global_position

	var started := await _wait_until(
		func() -> bool: return attack.phase == AttackController.Phase.WINDUP, 20
	)
	# The retreat is triggered by the telegraph, exactly like a human reaction.
	if retreat and started:
		Input.action_press(&"move_back", 1.0)
	var resolved := await _wait_until(
		func() -> bool: return attack.last_result() != null, FRAMES_FOR_SWING
	)
	var travelled := _horizontal_delta(start_position, player.global_position).length()
	var outcome := {
		"started": started,
		"resolved": resolved,
		"result": attack.last_result(),
		"abort_reason": attack.abort_reason(),
		"health_before": health_before,
		"health_after": health.current_health,
		"travelled": travelled,
		"gate_distance": MeleeRules.horizontal_distance(
			attack.hit_origin.global_position, player.global_position
		),
	}
	Input.action_release(&"move_back")
	return outcome


func test_b_backpedalling_from_the_telegraph_avoids_the_swing() -> void:
	## The sprint's headline criterion with the real player rig: walking out of reach
	## after the telegraph makes the swing a MISS. The enemy must not cancel it.
	if not await _instantiate_arena():
		return
	if not await _place_and_settle(PLAYER_ORIGIN, ENEMY_IN_FRONT):
		return
	var outcome := await _run_swing_against_player(true)

	assert_true(outcome["started"], "the enemy swing started (B is not a 'nothing happened' pass)")
	assert_true(outcome["resolved"], "the swing still resolved at its hit frame")
	assert_true(
		outcome["travelled"] > 2.0,
		"move_back really moved the rig during the windup (%.2f m)" % outcome["travelled"]
	)
	assert_true(
		outcome["gate_distance"] > ENEMY_RANGE_GATE,
		"the retreating player left the %.2f m gate (%.2f m)" % [
			ENEMY_RANGE_GATE, outcome["gate_distance"]
		]
	)
	var result: DamageResult = outcome["result"]
	assert_not_null(result, "the swing produced a result")
	if result != null:
		assert_false(result.applied, "backpedalling avoids the hit (%s)" % result)
		assert_true(
			result.miss_reason == DamageResult.REASON_OUT_OF_REACH
			or result.miss_reason == DamageResult.REASON_NO_TARGET,
			"the miss is a range/target miss, not an occlusion or duplicate: %s" % result.miss_reason
		)
	assert_eq(
		outcome["abort_reason"],
		&"",
		"a retreating target is a miss, never a cancellation (abort_reason must stay empty)"
	)
	assert_almost_eq(
		outcome["health_after"],
		outcome["health_before"],
		0.0001,
		"the player's HP is untouched by the avoided swing"
	)
	assert_false(_player().is_dead, "the player survives the avoided swing")


func test_c_control_standing_still_in_the_same_window_takes_the_hit() -> void:
	## Control for B: identical setup and timing, no movement input. Only the input
	## differs, so B cannot pass because the swing never had a chance to land.
	if not await _instantiate_arena():
		return
	if not await _place_and_settle(PLAYER_ORIGIN, ENEMY_IN_FRONT):
		return
	var outcome := await _run_swing_against_player(false)

	assert_true(outcome["started"], "the enemy swing started in the control case")
	assert_true(outcome["resolved"], "the control swing resolved")
	assert_true(
		outcome["travelled"] < 0.05,
		"the control rig never moved (%.3f m), so B and C differ only in the input" % outcome["travelled"]
	)
	var result: DamageResult = outcome["result"]
	assert_not_null(result, "the control swing produced a result")
	if result != null:
		assert_true(result.applied, "standing still inside reach takes the hit (%s)" % result)
		assert_almost_eq(result.damage_dealt, ENEMY_DAMAGE, 0.0001, "control damage matches the definition")
	assert_almost_eq(
		outcome["health_after"],
		PLAYER_MAX_HEALTH - ENEMY_DAMAGE,
		0.0001,
		"the control player's HP drops by exactly one grunt hit"
	)
	assert_eq(outcome["abort_reason"], &"", "the control swing was never cancelled either")


# --- D. geometry stops damage -------------------------------------------------

func test_d1_pillar_blocks_line_of_sight_so_the_encounter_never_starts() -> void:
	## `PillarEast` stands between the two rigs, 3.4 m apart and well inside the 12 m
	## detection radius: without occlusion the enemy would chase. It must stay IDLE
	## and never swing.
	if not await _instantiate_arena():
		return
	var pillar := _arena.get_node_or_null(^"PillarEast") as StaticBody3D
	assert_not_null(pillar, "the arena ships PillarEast as the occlusion obstacle")
	if pillar == null:
		return
	assert_eq(pillar.collision_layer, PhysicsLayers.WORLD, "the pillar is world geometry")
	# PillarEast spans x in [2.5, 4.5] at z = 0: one rig on each side, both clear of it.
	if not await _place_and_settle(Vector3(5.1, 0.05, 0.0), Vector3(1.7, 0.05, 0.0)):
		return
	var enemy := _enemy()
	var attack := _enemy_attack()
	assert_true(
		MeleeRules.horizontal_distance(enemy.global_position, _player().global_position) < 6.0,
		"the rigs are close enough that distance alone cannot explain a lack of detection"
	)

	await wait_physics_frames(120)  # 2 s: long enough to detect, chase, swing and hit
	assert_eq(enemy.fsm_state, EnemyFsm.State.IDLE, "a pillared line of sight leaves the enemy IDLE")
	assert_eq(_state_log.size(), 0, "the enemy never even entered CHASE, transitions: %s" % [_state_log])
	assert_eq(attack.phase, AttackController.Phase.IDLE, "no swing is started through the pillar")
	assert_null(attack.last_result(), "no hit was resolved through the pillar")
	assert_almost_eq(
		_player_health().current_health, PLAYER_MAX_HEALTH, 0.0001, "the player takes no damage"
	)


func test_d2_pending_swing_is_resolved_as_occluded_when_geometry_appears() -> void:
	## The stronger half of D: the swing starts with a clear line of sight and a wall
	## is raised before the hit frame. Occlusion must be judged at the hit frame, so
	## the pending attack resolves as a miss instead of damaging through the wall.
	if not await _instantiate_arena():
		return
	if not await _place_and_settle(Vector3(0.0, 0.05, 1.2), Vector3(0.0, 0.05, -0.6)):
		return
	var attack := _enemy_attack()
	var health := _player_health()
	var started := await _wait_until(
		func() -> bool: return attack.phase == AttackController.Phase.WINDUP, 20
	)
	assert_true(started, "the swing starts while the line of sight is clear")

	_add_world_wall(Vector3(0.0, 1.25, 0.5), Vector3(2.0, 2.5, 0.2))
	await wait_physics_frames(2)

	var resolved := await _wait_until(
		func() -> bool: return attack.last_result() != null, FRAMES_FOR_SWING
	)
	assert_true(resolved, "the pending swing still resolves at its hit frame")
	var result := attack.last_result()
	assert_not_null(result, "the pending swing produced a result")
	if result != null:
		assert_false(result.applied, "no damage through geometry (%s)" % result)
		assert_eq(
			result.miss_reason,
			DamageResult.REASON_OCCLUDED,
			"the miss is attributed to the wall, got %s" % result.miss_reason
		)
	assert_almost_eq(health.current_health, PLAYER_MAX_HEALTH, 0.0001, "HP is untouched")
	assert_eq(attack.abort_reason(), &"", "the swing was occluded, not cancelled")
	assert_false(_player().is_dead, "the player is unharmed")


## Raises a thin wall on `PhysicsLayers.WORLD`, owned by the test (freed in teardown).
func _add_world_wall(position: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.name = &"TestWall"
	wall.collision_layer = PhysicsLayers.WORLD
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	wall.position = position
	add_to_tree(wall)


# --- E. the player kills the enemy (AC-06 at rig level) ----------------------

## Sends `attack_primary` through the documented seam and waits for its hit frame.
func _player_swing_until_hit(max_frames: int = FRAMES_FOR_SWING) -> DamageResult:
	var attack := _player_attack()
	var ready := await _wait_until(func() -> bool: return attack.can_attack(), max_frames)
	if not ready:
		fail("the player never became able to swing again (cooldown/phase)")
		return null
	_player()._unhandled_input(_action_event(&"attack_primary", true))
	if not attack.is_busy():
		fail("attack_primary did not start a swing on the real player rig")
		return null
	var resolved := await _wait_until(func() -> bool: return attack.last_result() != null, max_frames)
	if not resolved:
		fail("the player's swing never resolved")
		return null
	return attack.last_result()


func test_e_player_kills_the_enemy_rig_in_three_swings() -> void:
	if not await _instantiate_arena():
		return
	if not await _place_and_settle(PLAYER_ORIGIN, Vector3(0.0, 0.05, -1.7)):
		return
	var enemy := _enemy()
	var enemy_health := _enemy_health()
	var enemy_attack := _enemy_attack()
	var player := _player()
	assert_almost_eq(enemy_health.current_health, ENEMY_MAX_HEALTH, 0.0001, "enemy starts at full HP")
	# Explicit geometry: the player faces -Z at its yaw 0, the enemy stands in front of
	# it inside the player's 2.0 + 0.3 m gate, and the swings below land on that alone.
	assert_true(
		player.rotation.y == 0.0, "the player faces -Z (the direction the enemy was placed in)"
	)
	assert_true(
		MeleeRules.horizontal_distance(player.global_position, enemy.global_position)
			<= MeleeRules.range_limit(
				_player_attack_definition().reach, _player_attack_definition().hit_radius
			),
		"the enemy stands inside the player's reach (%.2f m)" % MeleeRules.horizontal_distance(
			player.global_position, enemy.global_position
		)
	)

	var health_after_each_swing: Array[float] = []
	for swing in 3:
		var health_before_swing := enemy_health.current_health
		var result := await _player_swing_until_hit()
		assert_not_null(result, "swing %d resolved" % (swing + 1))
		if result == null:
			return
		assert_true(result.applied, "swing %d landed on the enemy rig (%s)" % [swing + 1, result])
		assert_true(
			result.damage_dealt <= PLAYER_DAMAGE + 0.0001,
			"swing %d never deals more than the definition damage (%.1f)" % [
				swing + 1, result.damage_dealt
			]
		)
		assert_almost_eq(
			health_before_swing - enemy_health.current_health,
			result.damage_dealt,
			0.0001,
			"swing %d: the HP drop equals the reported damage" % (swing + 1)
		)
		health_after_each_swing.append(enemy_health.current_health)
		if swing < 2:
			assert_true(
				enemy_health.is_alive(),
				"the grunt survives swing %d (100 HP, 34 per hit)" % (swing + 1)
			)
		else:
			assert_false(enemy_health.is_alive(), "the third swing kills the grunt")

	if health_after_each_swing.size() == 3:
		assert_almost_eq(health_after_each_swing[0], 66.0, 0.0001, "enemy HP 100 -> 66 after one hit")
		assert_almost_eq(health_after_each_swing[1], 32.0, 0.0001, "enemy HP 66 -> 32 after two hits")
		assert_almost_eq(health_after_each_swing[2], 0.0, 0.0001, "enemy HP 32 -> 0 (clamped) after three")

	assert_false(enemy_health.is_alive(), "the enemy's HealthComponent is dead")
	assert_eq(enemy.fsm_state, EnemyFsm.State.DEAD, "the FSM reports DEAD")
	assert_eq(enemy_attack.phase, AttackController.Phase.IDLE, "the corpse has no swing in flight")
	assert_true(
		enemy.velocity.length() < 0.05,
		"the corpse keeps zero velocity (%.3f m/s)" % enemy.velocity.length()
	)
	await wait_process_frames(2)
	var enemy_status := _hud_label(^"Status/EnemyStatus")
	assert_not_null(enemy_status, "the enemy HUD label exists")
	if enemy_status != null:
		assert_true(
			enemy_status.text.contains("state dead"),
			"the debug HUD reports the corpse state, got '%s'" % enemy_status.text
		)

	# AC-06: a dead enemy deals no further damage for the next two simulated seconds.
	var player_hp_at_death := _player_health().current_health
	await wait_physics_frames(120)
	assert_almost_eq(
		_player_health().current_health,
		player_hp_at_death,
		0.0001,
		"the dead enemy deals no damage in the 2 s after its death (HP %.1f)" % player_hp_at_death
	)
	assert_eq(enemy_attack.phase, AttackController.Phase.IDLE, "no new swing from the corpse")
	assert_almost_eq(enemy_health.current_health, 0.0, 0.0001, "the corpse is never damaged back up")
	assert_false(player.is_dead, "the player survives the whole exchange")


# --- F. the enemy gives up (AC-07) -------------------------------------------

func test_f_moving_beyond_the_lose_radius_returns_the_enemy_to_idle() -> void:
	if not await _instantiate_arena():
		return
	if not await _place_and_settle(PLAYER_ORIGIN, Vector3(0.0, 0.05, -8.0)):
		return
	var enemy := _enemy()
	var attack := _enemy_attack()
	var chased := await _wait_until(
		func() -> bool: return enemy.fsm_state == EnemyFsm.State.CHASE, 20
	)
	assert_true(chased, "the enemy detects the player at 8 m (inside the 12 m detection radius)")

	_player().position = Vector3(0.0, 0.05, 19.0)  # 27 m away: past lose_radius = 16 m
	var gave_up := await _wait_until(
		func() -> bool: return enemy.fsm_state == EnemyFsm.State.IDLE, 30
	)
	assert_true(gave_up, "a target beyond the lose radius returns the enemy to IDLE")
	assert_true(
		_state_log.has(Vector2i(EnemyFsm.State.CHASE, EnemyFsm.State.IDLE)),
		"the FSM log shows CHASE -> IDLE, transitions: %s" % [_state_log]
	)

	var stopped_at := enemy.global_position
	await wait_physics_frames(60)
	assert_almost_eq(enemy.global_position.x, stopped_at.x, 0.02, "the enemy stops in place (x)")
	assert_almost_eq(enemy.global_position.z, stopped_at.z, 0.02, "the enemy stops in place (z)")
	assert_true(
		enemy.velocity.length() < 0.05,
		"the idle enemy keeps zero horizontal velocity (%.3f m/s)" % enemy.velocity.length()
	)
	assert_eq(attack.phase, AttackController.Phase.IDLE, "no swing is started at 27 m")
	assert_null(attack.last_result(), "the enemy never resolved a swing after giving up")
	assert_almost_eq(
		_player_health().current_health, PLAYER_MAX_HEALTH, 0.0001, "the player takes no damage"
	)


# --- G. player death freezes the rig ----------------------------------------

func test_g_player_death_freezes_the_rig_and_stops_the_enemy() -> void:
	if not await _instantiate_arena():
		return
	if not await _place_and_settle(PLAYER_ORIGIN, ENEMY_IN_FRONT):
		return
	var enemy := _enemy()
	var attack := _enemy_attack()
	var health := _player_health()
	var player := _player()
	var swinging := await _wait_until(
		func() -> bool: return attack.phase == AttackController.Phase.WINDUP, 20
	)
	assert_true(swinging, "the enemy is mid-windup when the player is killed")

	# The natural 9-hit route would take ~15 s of simulated frames; the lethality of
	# the damage path itself is covered by the HP unit tests, so this applies the
	# lethal request directly through the real component.
	var lethal := DamageRequest.new(
		&"tests.w6.lethal",
		&"tests.w6",
		health.max_health + 1.0,
		player.global_position,
		Vector3.UP
	)
	var result := health.apply_damage(lethal)
	assert_true(result.target_died, "the lethal request kills the player")
	assert_true(player.is_dead, "PlayerController.is_dead is set by the real death signal")
	assert_almost_eq(health.current_health, 0.0, 0.0001, "HP clamps at zero")
	await wait_process_frames(2)
	var player_status := _hud_label(^"Status/PlayerHp")
	assert_not_null(player_status, "the player HUD label exists")
	if player_status != null:
		assert_true(
			player_status.text.contains("DEAD"),
			"the debug HUD reports the death, got '%s'" % player_status.text
		)

	var before := player.global_position
	Input.action_press(&"move_back", 1.0)
	await wait_physics_frames(20)
	Input.action_release(&"move_back")
	assert_true(
		_horizontal_delta(before, player.global_position).length() < 0.01,
		"held movement input no longer moves the dead rig (%.4f m)" % _horizontal_delta(
			before, player.global_position
		).length()
	)
	player._unhandled_input(_action_event(&"attack_primary", true))
	assert_eq(_player_attack().phase, AttackController.Phase.IDLE, "a dead player cannot swing")

	var resolved := await _wait_until(
		func() -> bool: return attack.last_result() != null, FRAMES_FOR_SWING
	)
	assert_true(resolved, "the in-flight enemy swing still resolves against the dead rig")
	var swing_result := attack.last_result()
	if swing_result != null:
		assert_false(swing_result.applied, "a corpse cannot be damaged (%s)" % swing_result)
		assert_eq(
			swing_result.miss_reason,
			DamageResult.REASON_TARGET_DEAD,
			"the miss is attributed to the dead target, got %s" % swing_result.miss_reason
		)
	assert_almost_eq(health.current_health, 0.0, 0.0001, "HP stays at zero")

	var calmed := await _wait_until(
		func() -> bool: return enemy.fsm_state == EnemyFsm.State.IDLE, 30
	)
	assert_true(calmed, "the enemy drops a dead target and returns to IDLE")
	var swing_ended := await _wait_until(
		func() -> bool: return attack.phase == AttackController.Phase.IDLE, 150
	)
	assert_true(swing_ended, "the in-flight swing finishes (phase returns to IDLE)")
	assert_eq(_enemy_swings_resolved, 1, "exactly one swing was ever resolved (the pre-death one)")

	await wait_physics_frames(120)  # 2 s standing next to a corpse
	assert_eq(attack.phase, AttackController.Phase.IDLE, "the enemy never starts a new swing at a corpse")
	assert_eq(_enemy_swings_resolved, 1, "no further swing resolves after the player died")
	assert_eq(enemy.fsm_state, EnemyFsm.State.IDLE, "the enemy stays IDLE with no living target")
	assert_almost_eq(health.current_health, 0.0, 0.0001, "no damage is applied after death")


# --- input seam evidence ------------------------------------------------------

func test_attack_input_parsed_by_the_input_singleton_reaches_the_controller() -> void:
	## Evidence for the manual/graphical path: the OS-level event route used by a real
	## click (`Input.parse_input_event`) reaches `PlayerController._unhandled_input`
	## in a headless run, not just the direct method call the other tests use.
	if not await _instantiate_arena():
		return
	var attack := _player_attack()
	var ready := await _wait_until(func() -> bool: return attack.can_attack(), 20)
	assert_true(ready, "a fresh arena player can swing")
	var event := _action_event(&"attack_primary", true)
	Input.parse_input_event(event)
	await wait_process_frames(2)
	await wait_physics_frames(2)
	assert_true(
		Input.is_action_pressed(&"attack_primary"),
		"the parsed event updated the InputMap action state headless"
	)
	assert_eq(
		attack.phase,
		AttackController.Phase.WINDUP,
		"Input.parse_input_event reached PlayerController._unhandled_input headless"
	)
	Input.action_release(&"attack_primary")
