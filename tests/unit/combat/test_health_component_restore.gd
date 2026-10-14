extends "res://tests/test_case.gd"

## AC-26 — `HealthComponent.restore()` applies a persisted life to a fresh rig
## without changing `apply_damage()` / `reset()` behaviour (ADR-007 seam).
##
## The component itself is the only state owner here: `restore()` makes the
## component usable again, but an owner that caches the transition (for example
## `EnemyBrain` and its terminal DEAD state) still decides what to do with it.


func _make_health(max_health: float) -> HealthComponent:
	var health := HealthComponent.new()
	# Attached to the tree so the test runner frees it afterwards (no leaked Nodes).
	add_to_tree(health)
	health.max_health = max_health
	health.actor_id = &"test.dummy"
	health.reset()
	return health


func _request(amount: float) -> DamageRequest:
	return DamageRequest.new(&"attack.test", &"tester", amount, Vector3.ZERO, Vector3.UP)


func test_restore_sets_hp_and_emits_health_changed() -> void:
	var health := _make_health(100.0)
	var changes: Array[Vector2] = []
	health.health_changed.connect(func(current: float, maximum: float) -> void:
		changes.append(Vector2(current, maximum))
	)
	health.restore(75.0)
	assert_eq(health.current_health, 75.0, "the restored value becomes the current HP")
	assert_true(health.is_alive(), "75 of 100 HP is alive")
	assert_eq(health.health_fraction(), 0.75, "the fraction follows the restored value")
	assert_eq(changes.size(), 1, "restore() emits health_changed exactly once")
	assert_eq(changes[0], Vector2(75.0, 100.0), "the signal carries current and maximum")


func test_restore_can_lower_and_raise_hp() -> void:
	var health := _make_health(100.0)
	health.apply_damage(_request(60.0))
	assert_eq(health.current_health, 40.0, "damage first")
	health.restore(90.0)
	assert_eq(health.current_health, 90.0, "restore() may raise HP above the damaged value")
	health.restore(10.0)
	assert_eq(health.current_health, 10.0, "and lower it again")


func test_restore_clamps_to_the_maximum() -> void:
	var health := _make_health(100.0)
	health.apply_damage(_request(60.0))
	health.restore(500.0)
	assert_eq(health.current_health, 100.0, "values above max_health clamp to max")
	assert_eq(health.health_fraction(), 1.0, "the fraction is capped at 1.0")


func test_restore_clamps_negative_values_to_zero_without_a_death_report() -> void:
	var health := _make_health(100.0)
	# GDScript lambdas capture primitives by value; use an Array to observe calls.
	var death_requests: Array[DamageRequest] = []
	health.died.connect(func(request: DamageRequest) -> void: death_requests.append(request))
	health.restore(-5.0)
	assert_eq(health.current_health, 0.0, "negative values clamp to zero")
	assert_false(health.is_alive(), "0 HP reads as not alive")
	assert_eq(death_requests.size(), 0, "restore() never reports a death by itself")
	# Documented resulting state: the component is dead with no `died` emitted, so a
	# later hit is rejected as target-dead instead of killing it a second time. The
	# owner (GameSession) turns restored 0 HP into a full-HP spawn before this state
	# can reach a live rig.
	var rejected := health.apply_damage(_request(10.0))
	assert_false(rejected.applied, "damage on a restored 0 HP component is rejected")
	assert_eq(rejected.miss_reason, DamageResult.REASON_TARGET_DEAD, "explicit reason")
	assert_eq(death_requests.size(), 0, "still no death report")


func test_restore_treats_non_finite_values_as_zero() -> void:
	var health := _make_health(50.0)
	health.restore(NAN)
	assert_eq(health.current_health, 0.0, "NAN cannot poison current_health")
	assert_false(health.is_alive(), "a NAN restore reads as dead")
	health.restore(INF)
	assert_eq(health.current_health, 50.0, "INF clamps to max_health")
	health.restore(-INF)
	assert_eq(health.current_health, 0.0, "-INF clamps to zero")


func test_restore_after_a_lethal_hit_re_arms_exactly_one_death() -> void:
	var health := _make_health(40.0)
	var death_requests: Array[DamageRequest] = []
	health.died.connect(func(request: DamageRequest) -> void: death_requests.append(request))
	health.apply_damage(_request(40.0))
	assert_eq(death_requests.size(), 1, "the first lethal hit reports death once")

	health.restore(25.0)
	assert_true(health.is_alive(), "restore() re-arms a usable life on the component")
	assert_eq(health.current_health, 25.0, "the restored value is applied")

	health.apply_damage(_request(10.0))
	assert_eq(death_requests.size(), 1, "a non-lethal hit after restore() does not report death")
	var lethal := health.apply_damage(_request(40.0))
	assert_true(lethal.target_died, "overkill still reports death")
	assert_eq(health.current_health, 0.0, "HP clamps at zero again")
	assert_eq(death_requests.size(), 2, "the next lethal hit reports death exactly once")


func test_restore_of_zero_after_a_lethal_hit_stays_silent() -> void:
	var health := _make_health(30.0)
	var death_requests: Array[DamageRequest] = []
	health.died.connect(func(request: DamageRequest) -> void: death_requests.append(request))
	health.apply_damage(_request(30.0))
	health.restore(0.0)
	assert_eq(death_requests.size(), 1, "a restored 0 does not emit a second death")
	assert_false(health.is_alive(), "0 HP stays dead")
	health.apply_damage(_request(10.0))
	assert_eq(death_requests.size(), 1, "and cannot die again until a positive value is restored")


func test_apply_damage_and_reset_are_unchanged() -> void:
	# Sprint 01 regression fence (AC-33): restore() must not alter the damage path.
	var health := _make_health(30.0)
	var result := health.apply_damage(_request(12.5))
	assert_true(result.applied, "damage is still applied")
	assert_eq(result.damage_dealt, 12.5, "the dealt amount is reported")
	assert_eq(health.current_health, 17.5, "HP follows the damage")
	assert_eq(
		health.apply_damage(null).miss_reason,
		DamageResult.REASON_INVALID_REQUEST,
		"a null request is still rejected"
	)
	assert_eq(
		health.apply_damage(_request(0.0)).miss_reason,
		DamageResult.REASON_INVALID_AMOUNT,
		"an invalid amount is still rejected"
	)
	assert_eq(health.current_health, 17.5, "rejected requests still change nothing")

	health.apply_damage(_request(99.0))
	assert_eq(health.current_health, 0.0, "HP still clamps at zero")
	assert_false(health.is_alive(), "overkill still kills")

	health.reset()
	assert_eq(health.current_health, 30.0, "reset() still restores a full life")
	var death_requests: Array[DamageRequest] = []
	health.died.connect(func(request: DamageRequest) -> void: death_requests.append(request))
	health.apply_damage(_request(30.0))
	assert_eq(death_requests.size(), 1, "reset() still allows death to be reported again")


func test_restore_applies_after_ready_on_a_tree_attached_component() -> void:
	var host := Node3D.new()
	host.name = "ReloadedActor"
	add_to_tree(host)
	var health := HealthComponent.new()
	health.max_health = 100.0
	host.add_child(health)
	await wait_process_frames(1)
	assert_eq(health.current_health, 100.0, "_ready() fills a fresh rig to max HP")
	health.restore(33.0)
	assert_eq(health.current_health, 33.0, "the persisted life is applied after add_child()")
	assert_eq(health.target_id(), &"ReloadedActor", "the actor id lookup still works")
