extends "res://tests/test_case.gd"

## S04-QA — independent verification of the ADR-016 combat integration.
##
## Gaps this file closes:
## - the swing pin is checked while the change happens in WINDUP, in the ACTIVE window
##   and in RECOVERY (damage, reach and the cooldown that follows).
## - a weapon change while IDLE cannot bypass the cooldown of the finished swing.
## - mitigation is monotonic in defense, is exactly identity at defense 0, never zeroes
##   a positive hit, and a hostile negative modifier cannot amplify damage.
## - `set_max_health` never heals, clamps down without emitting `died`, refuses
##   non-finite input (NAN and both infinities) and does not report death on a clamp.

const TARGET_START := Vector3(0, 0, -1.5)

var _world: Node3D = null
var _target: CharacterBody3D = null
var _target_health: HealthComponent = null
var _origin: Node3D = null
var _controller: AttackController = null
var _definition: AttackDefinition = null


func teardown() -> void:
	_world = null
	_target = null
	_target_health = null
	_origin = null
	_controller = null
	_definition = null


func _profile(
	id: StringName, damage: float, reach: float = 1.7, cooldown: float = 1.0
) -> AttackDefinition:
	var profile := AttackDefinition.new()
	profile.id = id
	profile.damage = damage
	profile.reach = reach
	profile.hit_radius = 0.25
	profile.hit_arc_degrees = 60.0
	profile.windup = 0.3
	profile.active_window = 0.1
	profile.recovery = 0.4
	profile.cooldown = cooldown
	return profile


func _make_stats(attack_bonus: float = 0.0, defense: float = 0.0) -> CharacterStats:
	var definition := PlayerDefinition.new()
	definition.id = &"player.qa"
	definition.display_name = "QA Tester"
	definition.max_health = 100.0
	definition.attack_damage = 34.0
	definition.defense = 0.0
	definition.movement_speed = 4.0
	definition.attack_definition = _profile(&"attack.qa.base", 34.0)
	var stats := CharacterStats.new()
	stats.setup(definition)
	if attack_bonus != 0.0:
		stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: attack_bonus})
	if defense != 0.0:
		stats.set_modifiers(&"armor", {CharacterStats.DEFENSE: defense})
	return stats


func _build_world() -> void:
	_world = Node3D.new()
	add_to_tree(_world)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40, 1, 40)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	_world.add_child(floor_body)

	_target = CharacterBody3D.new()
	_target.collision_layer = PhysicsLayers.ENEMY_BODY
	_target.collision_mask = 0
	var target_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	target_shape.shape = capsule
	_target.add_child(target_shape)
	_target_health = HealthComponent.new()
	_target_health.name = &"HealthComponent"
	_target_health.max_health = 100.0
	_target_health.actor_id = &"enemy.qa"
	_target.add_child(_target_health)
	_target.position = TARGET_START
	_world.add_child(_target)

	_origin = Node3D.new()
	_origin.position = Vector3(0, 1.6, 0)
	_world.add_child(_origin)

	var detector := HitDetector.new()
	detector.target_mask = PhysicsLayers.ENEMY_BODY
	detector.blocker_mask = PhysicsLayers.WORLD
	_world.add_child(detector)

	_definition = _profile(&"attack.qa.base", 34.0)
	_controller = AttackController.new()
	_controller.definition = _definition
	_controller.source_id = &"player"
	_controller.auto_tick = false
	_controller.hit_origin = _origin
	_controller.hit_detector = detector
	_world.add_child(_controller)

	await wait_physics_frames(2)


func _start_swing() -> bool:
	var started := _controller.request_attack()
	for _i in 200:
		if _controller.last_result() != null:
			break
		_controller.advance(0.01)
	return started


## Advances until the first ACTIVE tick resolved the hit; the phase is then ACTIVE
## with the active window still ahead.
func _resolve_hit() -> void:
	for _i in 200:
		if _controller.last_result() != null:
			return
		_controller.advance(0.01)


func _finish_swing() -> void:
	for _i in 300:
		if _controller.phase == AttackController.Phase.IDLE:
			return
		_controller.advance(0.02)


func _weapon_swap(attack_bonus: float) -> void:
	# The worst case: a shorter reach, a tiny damage value and no cooldown at all.
	_controller.set_attack_profile(_profile(&"attack.qa.swapped", 5.0, 0.4, 0.0))
	_controller.set_stats(_make_stats(attack_bonus))


# --- swing pin ----------------------------------------------------------------

func test_a_change_during_windup_cannot_alter_the_swing() -> void:
	await _build_world()
	_controller.set_stats(_make_stats(15.0))
	assert_true(_controller.request_attack(), "the swing starts")
	_controller.advance(0.1)  # still winding up
	assert_eq(_controller.phase, AttackController.Phase.WINDUP, "still winding up")
	_weapon_swap(500.0)
	_resolve_hit()
	var result := _controller.last_result()
	assert_not_null(result, "the hit resolved")
	if result == null:
		return
	assert_true(result.applied, "the pinned reach still lands the hit")
	assert_eq(result.damage_dealt, 49.0, "the pinned damage (34 + 15), not the live 534")


func test_a_change_during_the_active_window_cannot_alter_the_swing_or_its_cooldown() -> void:
	await _build_world()
	_controller.set_stats(_make_stats(15.0))
	assert_true(_controller.request_attack(), "the swing starts")
	_resolve_hit()
	assert_eq(_controller.phase, AttackController.Phase.ACTIVE, "the hit resolved when ACTIVE began")
	if _controller.last_result() == null:
		return
	assert_eq(_controller.last_result().damage_dealt, 49.0, "the pinned damage landed")
	# The active window lasts 0.1 s: 0.05 leaves 0.05 s inside it.
	_controller.advance(0.05)
	assert_eq(_controller.phase, AttackController.Phase.ACTIVE, "inside the active window")
	_weapon_swap(500.0)
	_controller.advance(0.03)
	assert_eq(_controller.phase, AttackController.Phase.ACTIVE, "still inside the window after the swap")
	assert_eq(_controller.last_result().damage_dealt, 49.0, "the resolved hit is untouched")
	_finish_swing()
	assert_false(_controller.can_attack(), "the pinned cooldown is still running")
	assert_true(
		_controller.cooldown_remaining() > 0.0,
		"the swap to a 0-cooldown weapon did not erase the cooldown"
	)


func test_a_change_during_recovery_cannot_alter_the_cooldown() -> void:
	await _build_world()
	_controller.set_stats(_make_stats(15.0))
	assert_true(_controller.request_attack(), "the swing starts")
	_resolve_hit()
	_controller.advance(0.45)  # the 0.1 s active window ends and recovery runs
	assert_eq(_controller.phase, AttackController.Phase.RECOVERY, "the swing is recovering")
	_weapon_swap(500.0)
	_finish_swing()
	assert_false(_controller.can_attack(), "the pinned cooldown is still running")
	assert_almost_eq(
		_controller.cooldown_remaining(), 0.2, 0.05,
		"1.0 s pinned cooldown minus 0.8 s of swing"
	)


func test_a_weapon_change_cannot_bypass_the_cooldown() -> void:
	await _build_world()
	var slow := _profile(&"attack.qa.slow", 34.0, 1.7, 2.0)
	_controller.set_attack_profile(slow)
	_start_swing()
	_finish_swing()
	var remaining := _controller.cooldown_remaining()
	assert_true(remaining > 1.0, "the long pinned cooldown is running (%.2f s)" % remaining)

	# A fast weapon with no cooldown must not unlock the next swing.
	_controller.set_attack_profile(_profile(&"attack.qa.fast", 34.0, 1.7, 0.0))
	assert_false(_controller.can_attack(), "a weapon swap does not clear the running cooldown")
	assert_false(_controller.request_attack(), "and cannot start a swing")
	assert_eq(_controller.phase, AttackController.Phase.IDLE, "no phase was entered")
	_controller.advance(0.5)
	assert_false(_controller.can_attack(), "0.5 s later the pinned cooldown is still running")
	assert_almost_eq(_controller.cooldown_remaining(), remaining - 0.5, 0.05, "the cooldown kept ticking")
	_controller.advance(remaining)
	assert_true(_controller.can_attack(), "after the full pinned cooldown the next swing is allowed")
	assert_true(_controller.request_attack(), "and it starts")


# --- defense ------------------------------------------------------------------

func _damage_with_defense(defense: float) -> float:
	var stats := _make_stats(0.0, 0.0)
	stats.set_modifiers(&"qa", {CharacterStats.DEFENSE: defense})
	_target_health.set_defense_provider(stats)
	_target_health.restore(1.0e9)
	var result := _target_health.apply_damage(
		DamageRequest.new(&"attack.qa.probe", &"qa", 1000.0, Vector3.ZERO, Vector3.UP)
	)
	return result.damage_dealt


func test_mitigation_is_monotonic_identity_at_zero_and_never_zero() -> void:
	await _build_world()
	_target_health.set_max_health(1.0e9)
	var defenses: Array[float] = [0.0, 1.0, 10.0, 100.0, 1000.0, 10000.0, 1000000.0]
	var previous := INF
	for defense in defenses:
		var dealt := _damage_with_defense(defense)
		assert_true(dealt > 0.0, "defense %f still takes a positive hit" % defense)
		assert_true(dealt < previous, "defense %f deals less than the previous value" % defense)
		if defense == 0.0:
			assert_almost_eq(dealt, 1000.0, 0.0001, "defense 0 is exactly identity")
		previous = dealt


func test_a_hostile_negative_defense_modifier_cannot_amplify_damage() -> void:
	await _build_world()
	_target_health.set_max_health(1.0e9)
	var stats := _make_stats(0.0, 50.0)
	assert_almost_eq(stats.effective(CharacterStats.DEFENSE), 50.0, 0.0001, "base defense")
	stats.set_modifiers(&"curse", {CharacterStats.DEFENSE: -500.0})
	assert_almost_eq(
		stats.effective(CharacterStats.DEFENSE), 0.0, 0.0001,
		"a hostile modifier is clamped at the floor, never negative"
	)
	_target_health.set_defense_provider(stats)
	_target_health.restore(1.0e9)
	var result := _target_health.apply_damage(
		DamageRequest.new(&"attack.qa.probe", &"qa", 1000.0, Vector3.ZERO, Vector3.UP)
	)
	assert_almost_eq(result.damage_dealt, 1000.0, 0.0001, "the hostile modifier cannot amplify the hit")
	assert_true(result.damage_dealt <= 1000.0, "damage never exceeds the raw amount")

	stats.set_modifiers(&"curse", {CharacterStats.DEFENSE: -20.0})
	assert_almost_eq(stats.effective(CharacterStats.DEFENSE), 30.0, 0.0001, "a partial curse lowers defense")
	_target_health.restore(1.0e9)
	var partial := _target_health.apply_damage(
		DamageRequest.new(&"attack.qa.probe", &"qa", 1000.0, Vector3.ZERO, Vector3.UP)
	)
	assert_almost_eq(partial.damage_dealt, 1000.0 * (100.0 / 130.0), 0.01, "defense 30 mitigates softly")
	assert_true(partial.damage_dealt < 1000.0, "and still mitigates")


# --- max health ---------------------------------------------------------------

func test_set_max_health_never_heals_clamps_and_never_reports_death() -> void:
	await _build_world()
	var deaths: Array[DamageRequest] = []
	var health_events: Array[int] = []
	_target_health.died.connect(func(request: DamageRequest) -> void: deaths.append(request))
	_target_health.health_changed.connect(func(_c: float, _m: float) -> void: health_events.append(1))

	_target_health.apply_damage(
		DamageRequest.new(&"attack.qa.probe", &"qa", 70.0, Vector3.ZERO, Vector3.UP)
	)
	assert_almost_eq(_target_health.current_health, 30.0, 0.0001, "damaged to 30")

	_target_health.set_max_health(200.0)
	assert_almost_eq(_target_health.max_health, 200.0, 0.0001, "the ceiling rose")
	assert_almost_eq(_target_health.current_health, 30.0, 0.0001, "without healing")
	assert_eq(deaths.size(), 0, "and without a death report")

	_target_health.set_max_health(10.0)
	assert_almost_eq(_target_health.current_health, 10.0, 0.0001, "a lower ceiling clamps the current HP")
	assert_true(_target_health.is_alive(), "the actor is alive")
	assert_eq(deaths.size(), 0, "a clamp is not a death")

	_target_health.set_max_health(0.0)
	assert_almost_eq(_target_health.max_health, 0.0, 0.0001, "the ceiling is zero")
	assert_almost_eq(_target_health.current_health, 0.0, 0.0001, "and the current HP clamps to zero")
	assert_false(_target_health.is_alive(), "the actor reads dead")
	assert_eq(deaths.size(), 0, "without emitting died")

	var rejected := _target_health.apply_damage(
		DamageRequest.new(&"attack.qa.probe", &"qa", 5.0, Vector3.ZERO, Vector3.UP)
	)
	assert_eq(rejected.miss_reason, DamageResult.REASON_TARGET_DEAD, "damage is rejected after the clamp")
	assert_eq(deaths.size(), 0, "and still no death report")

	_target_health.set_max_health(100.0)
	assert_almost_eq(_target_health.max_health, 100.0, 0.0001, "the ceiling rose again")
	assert_almost_eq(_target_health.current_health, 0.0, 0.0001, "raising it never heals")

	_target_health.restore(50.0)
	assert_almost_eq(_target_health.current_health, 50.0, 0.0001, "an explicit restore revives the component")

	# An unchanged ceiling must not emit a redundant health_changed.
	var events_before := health_events.size()
	_target_health.set_max_health(100.0)
	assert_eq(health_events.size(), events_before, "the identical ceiling emits nothing")


func test_set_max_health_refuses_non_finite_input() -> void:
	await _build_world()
	_target_health.apply_damage(
		DamageRequest.new(&"attack.qa.probe", &"qa", 25.0, Vector3.ZERO, Vector3.UP)
	)
	for bad_value: float in [NAN, INF, -INF]:
		_target_health.set_max_health(bad_value)
		assert_almost_eq(_target_health.max_health, 100.0, 0.0001, "non-finite input is refused")
		assert_almost_eq(_target_health.current_health, 75.0, 0.0001, "and the current HP is untouched")
