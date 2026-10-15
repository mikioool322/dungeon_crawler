extends "res://tests/test_case.gd"

## AC-38/39/40 — combat integration (ADR-016): the swing pins its profile and damage, the
## stats own the player's damage while an enemy keeps the profile's, mitigation happens on
## the receiver, and a max-HP change never heals.

const TARGET_START := Vector3(0, 0, -1.5)

var _world: Node3D = null
var _target: CharacterBody3D = null
var _target_health: HealthComponent = null
var _origin: Node3D = null
var _controller: AttackController = null
var _definition: AttackDefinition = null
var _stats: CharacterStats = null


func teardown() -> void:
	_world = null
	_target = null
	_target_health = null
	_origin = null
	_controller = null
	_definition = null
	_stats = null


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
	definition.id = &"player.test"
	definition.display_name = "Tester"
	definition.max_health = 100.0
	definition.attack_damage = 34.0
	definition.defense = 0.0
	definition.movement_speed = 4.0
	definition.attack_definition = _profile(&"attack.test.base", 34.0)
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
	_target_health.actor_id = &"enemy.test"
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

	_definition = _profile(&"attack.test.base", 34.0)
	_controller = AttackController.new()
	_controller.definition = _definition
	_controller.source_id = &"player"
	_controller.auto_tick = false
	_controller.hit_origin = _origin
	_controller.hit_detector = detector
	_world.add_child(_controller)

	await wait_physics_frames(2)


func _swing() -> DamageResult:
	_controller.request_attack()
	for _i in 200:
		if _controller.last_result() != null:
			break
		_controller.advance(0.01)
	return _controller.last_result()


func _finish_swing() -> void:
	for _i in 200:
		if _controller.phase == AttackController.Phase.IDLE:
			return
		_controller.advance(0.02)


# --- damage source ------------------------------------------------------------

func test_without_stats_the_profile_damage_applies() -> void:
	await _build_world()
	var result := _swing()
	assert_true(result.applied, "hit applied")
	assert_eq(result.damage_dealt, 34.0, "an actor without stats keeps the profile damage")


func test_with_stats_the_effective_attack_damage_applies() -> void:
	await _build_world()
	_stats = _make_stats(15.0)
	_controller.set_stats(_stats)
	var result := _swing()
	assert_true(result.applied, "hit applied")
	assert_eq(result.damage_dealt, 49.0, "34 base + 15 equipment")


func test_a_weapon_profile_overrides_reach() -> void:
	await _build_world()
	var short_profile := _profile(&"attack.test.short", 34.0, 1.0)
	_controller.set_attack_profile(short_profile)
	var result := _swing()
	assert_false(result.applied, "the shorter reach cannot touch the target")
	assert_eq(result.miss_reason, DamageResult.REASON_OUT_OF_REACH, "explicit range miss")


func test_an_invalid_weapon_profile_falls_back_to_the_base_definition() -> void:
	await _build_world()
	var broken := _profile(&"", 34.0)
	assert_false(broken.is_valid(), "the fixture profile is invalid (empty id)")
	_controller.set_attack_profile(broken)
	assert_eq(_controller.attack_profile(), _definition, "the base profile stays active")
	var result := _swing()
	assert_true(result.applied, "combat still works")


# --- swing snapshot -----------------------------------------------------------

func test_a_mid_swing_stat_change_cannot_alter_the_swing() -> void:
	await _build_world()
	_stats = _make_stats(15.0)
	_controller.set_stats(_stats)
	_controller.request_attack()
	_controller.advance(0.1)  # still winding up
	# The player swaps equipment mid-swing: the pinned damage must not follow.
	_stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 100.0})
	var result := _swing()
	assert_true(result.applied, "hit applied")
	assert_eq(result.damage_dealt, 49.0, "the swing keeps the damage pinned at its start")


func test_a_mid_swing_weapon_change_cannot_alter_reach_or_timing() -> void:
	await _build_world()
	_controller.request_attack()
	_controller.advance(0.1)
	_controller.set_attack_profile(_profile(&"attack.test.short", 5.0, 0.4))
	_controller.set_stats(_make_stats(500.0))
	var result := _swing()
	assert_true(result.applied, "the pinned profile still reaches the target")
	assert_eq(result.damage_dealt, 34.0, "and still uses the pinned damage")


func test_the_cooldown_comes_from_the_pinned_profile() -> void:
	await _build_world()
	var slow := _profile(&"attack.test.slow", 34.0, 1.7, 2.0)
	_controller.set_attack_profile(slow)
	_swing()
	_finish_swing()
	assert_false(_controller.can_attack(), "the long cooldown of the pinned profile is running")
	assert_true(_controller.cooldown_remaining() > 1.0, "and it is the profile's, not the base's")


# --- defense ------------------------------------------------------------------

func test_zero_defense_behaves_like_before() -> void:
	await _build_world()
	_target_health.set_defense_provider(_make_stats(0.0, 0.0))
	var result := _swing()
	assert_eq(result.damage_dealt, 34.0, "defense 0 leaves the damage untouched")


func test_defense_mitigates_softly_and_never_reaches_zero() -> void:
	await _build_world()
	_target_health.set_defense_provider(_make_stats(0.0, 100.0))
	var result := _swing()
	assert_true(result.applied, "the hit still lands")
	assert_almost_eq(result.damage_dealt, 17.0, 0.01, "defense 100 halves the damage")
	assert_true(result.damage_dealt > 0.0, "a positive hit never becomes zero")


func test_high_defense_still_takes_some_damage() -> void:
	await _build_world()
	_target_health.set_defense_provider(_make_stats(0.0, 10000.0))
	var result := _swing()
	assert_true(result.damage_dealt > 0.0, "no immunity exists")
	assert_true(result.damage_dealt < 1.0, "but the mitigation is strong")


# --- max health ---------------------------------------------------------------

func test_raising_max_health_does_not_heal() -> void:
	await _build_world()
	_target_health.apply_damage(DamageRequest.new(&"test", &"test", 40.0))
	assert_almost_eq(_target_health.current_health, 60.0, 0.0001, "damaged first")
	_target_health.set_max_health(150.0)
	assert_almost_eq(_target_health.max_health, 150.0, 0.0001, "the ceiling moved")
	assert_almost_eq(_target_health.current_health, 60.0, 0.0001, "no free healing")


func test_lowering_max_health_clamps_without_a_death_report() -> void:
	await _build_world()
	var deaths: Array[DamageRequest] = []
	_target_health.died.connect(func(request: DamageRequest) -> void: deaths.append(request))
	_target_health.set_max_health(25.0)
	assert_almost_eq(_target_health.current_health, 25.0, 0.0001, "clamped to the new ceiling")
	assert_eq(deaths.size(), 0, "a clamp is not a death")
	assert_true(_target_health.is_alive(), "and the actor is alive")


func test_a_non_finite_max_health_is_refused() -> void:
	await _build_world()
	_target_health.set_max_health(INF)
	assert_almost_eq(_target_health.max_health, 100.0, 0.0001, "the ceiling is unchanged")
