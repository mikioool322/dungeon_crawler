extends "res://tests/test_case.gd"

## AC-01 / AC-08 — damage application, clamping, single death report.


func _make_health(max_health: float) -> HealthComponent:
	var health := HealthComponent.new()
	health.max_health = max_health
	health.actor_id = &"test.dummy"
	health.reset()
	return health


func _request(amount: float) -> DamageRequest:
	return DamageRequest.new(&"attack.test", &"tester", amount, Vector3.ZERO, Vector3.UP)


func test_health_starts_full() -> void:
	var health := _make_health(100.0)
	assert_eq(health.current_health, 100.0, "fresh life is full")
	assert_true(health.is_alive(), "alive at full HP")
	assert_eq(health.health_fraction(), 1.0, "fraction is 1.0")


func test_damage_reduces_hp_by_the_requested_amount() -> void:
	var health := _make_health(100.0)
	var result := health.apply_damage(_request(25.0))
	assert_true(result.applied, "hit applied")
	assert_eq(result.damage_dealt, 25.0, "reported damage equals the applied amount")
	assert_eq(health.current_health, 75.0, "HP reduced")
	assert_eq(result.target_id, &"test.dummy", "result carries the stable actor id")
	assert_false(result.target_died, "still alive")


func test_hp_is_clamped_and_overkill_is_reported_truthfully() -> void:
	var health := _make_health(50.0)
	var result := health.apply_damage(_request(120.0))
	assert_eq(health.current_health, 0.0, "HP clamps at zero")
	assert_eq(result.damage_dealt, 50.0, "only the remaining HP is reported as dealt")
	assert_true(result.target_died, "lethal hit reports death")


func test_hp_never_goes_negative() -> void:
	var health := _make_health(10.0)
	health.apply_damage(_request(9999.0))
	assert_true(health.current_health >= 0.0, "no negative HP")
	assert_eq(health.health_fraction(), 0.0, "fraction clamps at zero")


func test_death_is_reported_exactly_once() -> void:
	var health := _make_health(30.0)
	# GDScript lambdas capture primitives by value; use an Array to observe calls.
	var death_requests: Array[DamageRequest] = []
	health.died.connect(func(request: DamageRequest) -> void: death_requests.append(request))
	health.apply_damage(_request(30.0))
	assert_eq(death_requests.size(), 1, "first lethal hit reports death once")
	var after_death := health.apply_damage(_request(30.0))
	assert_eq(death_requests.size(), 1, "damage after death must not report death again")
	assert_false(after_death.applied, "damage after death is rejected")
	assert_eq(after_death.miss_reason, DamageResult.REASON_TARGET_DEAD, "explicit reason")
	assert_eq(health.current_health, 0.0, "HP stays at zero")
	assert_not_null(death_requests[0], "died signal carries the killing request")


func test_partial_hits_do_not_report_death() -> void:
	var health := _make_health(100.0)
	var death_requests: Array[DamageRequest] = []
	health.died.connect(func(request: DamageRequest) -> void: death_requests.append(request))
	health.apply_damage(_request(30.0))
	health.apply_damage(_request(30.0))
	health.apply_damage(_request(30.0))
	assert_eq(death_requests.size(), 0, "three non-lethal hits")
	assert_true(health.is_alive(), "10 HP left")
	health.apply_damage(_request(10.0))
	assert_eq(death_requests.size(), 1, "the fourth hit is lethal")


func test_invalid_amounts_are_rejected_without_changing_hp() -> void:
	var health := _make_health(100.0)
	for invalid in [0.0, -5.0, NAN, INF]:
		var result := health.apply_damage(_request(invalid))
		assert_false(result.applied, "invalid amount %s rejected" % invalid)
		assert_eq(result.miss_reason, DamageResult.REASON_INVALID_AMOUNT, "reason for %s" % invalid)
	assert_eq(health.current_health, 100.0, "HP untouched by invalid requests")


func test_null_request_is_rejected() -> void:
	var health := _make_health(100.0)
	var result := health.apply_damage(null)
	assert_false(result.applied, "null request rejected")
	assert_eq(result.miss_reason, DamageResult.REASON_INVALID_REQUEST, "explicit reason")
	assert_eq(health.current_health, 100.0, "HP untouched")


func test_health_changed_reports_current_and_maximum() -> void:
	var health := _make_health(80.0)
	var snapshots: Array[Vector2] = []
	health.health_changed.connect(func(current: float, maximum: float) -> void:
		snapshots.append(Vector2(current, maximum))
	)
	health.apply_damage(_request(20.0))
	assert_eq(snapshots.size(), 1, "one notification per applied hit")
	assert_eq(snapshots[0], Vector2(60.0, 80.0), "current and maximum are reported")


func test_signal_order_is_change_then_damage_then_death() -> void:
	var health := _make_health(20.0)
	var order: PackedStringArray = PackedStringArray()
	health.health_changed.connect(func(_c: float, _m: float) -> void: order.append("changed"))
	health.damaged.connect(func(_r: DamageRequest, _res: DamageResult) -> void: order.append("damaged"))
	health.died.connect(func(_r: DamageRequest) -> void: order.append("died"))
	health.apply_damage(_request(20.0))
	assert_eq(order.size(), 3, "all three signals fired")
	assert_eq(order[0], "changed", "health_changed first")
	assert_eq(order[1], "damaged", "damaged second")
	assert_eq(order[2], "died", "died last")


func test_reset_restores_a_full_life() -> void:
	var health := _make_health(40.0)
	health.apply_damage(_request(40.0))
	assert_false(health.is_alive(), "dead before reset")
	health.reset()
	assert_true(health.is_alive(), "alive after reset")
	assert_eq(health.current_health, 40.0, "full HP after reset")
	var death_requests: Array[DamageRequest] = []
	health.died.connect(func(request: DamageRequest) -> void: death_requests.append(request))
	health.apply_damage(_request(40.0))
	assert_eq(death_requests.size(), 1, "death can be reported again after reset")


func test_ready_initializes_health_on_a_tree_attached_component() -> void:
	var host := Node3D.new()
	host.name = "DummyActor"
	add_to_tree(host)
	var health := HealthComponent.new()
	health.max_health = 55.0
	host.add_child(health)
	await wait_process_frames(1)
	assert_eq(health.current_health, 55.0, "_ready() fills HP to max")
	assert_eq(health.target_id(), &"DummyActor", "falls back to the host node name when actor_id is empty")


func test_zero_max_health_actor_is_not_alive() -> void:
	var health := _make_health(0.0)
	assert_false(health.is_alive(), "an actor with no HP cannot be alive")
	var result := health.apply_damage(_request(10.0))
	assert_eq(result.miss_reason, DamageResult.REASON_TARGET_DEAD, "already-dead actor rejects damage")
