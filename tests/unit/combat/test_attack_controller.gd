extends "res://tests/test_case.gd"

## AC-05 / AC-06 — attack phase machine, cooldown gating, abort semantics.
## Driven deterministically through `advance()`; no physics and no scene tree.


## Inner spy: proves the "exactly one hit query per swing" rule (ADR-004).
class SpyDetector extends HitDetector:
	var query_count: int = 0

	func query_hits(
		_definition: AttackDefinition,
		_origin: Transform3D,
		_exclude_rids: Array[RID] = []
	) -> Array[HitCandidate]:
		query_count += 1
		return []


## Inner stub: returns hand-written candidates so rejection precedence can be tested
## without physics.
class ScriptedDetector extends HitDetector:
	var scripted: Array[HitCandidate] = []

	func query_hits(
		_definition: AttackDefinition,
		_origin: Transform3D,
		_exclude_rids: Array[RID] = []
	) -> Array[HitCandidate]:
		return scripted


func _make_definition(
	windup: float = 0.3,
	active_window: float = 0.1,
	recovery: float = 0.4,
	cooldown: float = 1.0
) -> AttackDefinition:
	var definition := AttackDefinition.new()
	definition.id = &"attack.test.basic"
	definition.damage = 12.0
	definition.reach = 2.0
	definition.hit_radius = 0.3
	definition.windup = windup
	definition.active_window = active_window
	definition.recovery = recovery
	definition.cooldown = cooldown
	return definition


func _make_controller(definition: AttackDefinition) -> AttackController:
	var controller := AttackController.new()
	controller.definition = definition
	controller.source_id = &"player"
	controller.auto_tick = false
	# Added to the tree so the runner frees it after the test (no leaked Nodes) and
	# so Node3D transforms are valid inside the tree.
	add_to_tree(controller)
	return controller


func _make_controller_with_detector(definition: AttackDefinition) -> Array:
	var controller := _make_controller(definition)
	var origin := Node3D.new()
	add_to_tree(origin)
	controller.hit_origin = origin
	var spy := SpyDetector.new()
	add_to_tree(spy)
	controller.hit_detector = spy
	return [controller, spy]


func _run_swing(controller: AttackController, step: float = 0.01, guard: int = 1000) -> void:
	## Advances until the controller returns to IDLE (bounded).
	for _i in guard:
		if controller.phase == AttackController.Phase.IDLE and _i_advanced(controller):
			return
		controller.advance(step)


func _i_advanced(controller: AttackController) -> bool:
	## IDLE is only "done" after the swing has actually happened.
	return controller.last_result() != null or controller.cooldown_remaining() > 0.0


func test_starts_idle_and_ready() -> void:
	var controller := _make_controller(_make_definition())
	assert_eq(controller.phase, AttackController.Phase.IDLE, "starts idle")
	assert_true(controller.can_attack(), "can attack")
	assert_false(controller.is_busy(), "not busy")
	assert_eq(controller.cooldown_remaining(), 0.0, "no cooldown")
	assert_null(controller.last_result(), "no result yet")


func test_request_attack_enters_windup() -> void:
	var controller := _make_controller(_make_definition())
	assert_true(controller.request_attack(), "first request accepted")
	assert_eq(controller.phase, AttackController.Phase.WINDUP, "windup phase")
	assert_false(controller.can_attack(), "busy while winding up")
	assert_false(controller.request_attack(), "a second request during the swing is rejected, not queued")


func test_phase_order_is_windup_active_recovery_idle() -> void:
	var controller := _make_controller(_make_definition())
	var observed: Array[int] = []
	controller.phase_changed.connect(func(phase: int) -> void: observed.append(phase))
	controller.request_attack()
	for _i in 200:
		controller.advance(0.05)
		if controller.phase == AttackController.Phase.IDLE and observed.size() >= 4:
			break
	assert_eq(observed.size(), 4, "four phase changes for one swing")
	assert_eq(observed[0], AttackController.Phase.WINDUP, "windup first")
	assert_eq(observed[1], AttackController.Phase.ACTIVE, "active second")
	assert_eq(observed[2], AttackController.Phase.RECOVERY, "recovery third")
	assert_eq(observed[3], AttackController.Phase.IDLE, "idle last")


func test_exactly_one_hit_query_per_swing() -> void:
	var pair := _make_controller_with_detector(_make_definition())
	var controller: AttackController = pair[0]
	var spy: SpyDetector = pair[1]
	controller.request_attack()
	for _i in 200:
		controller.advance(0.01)
		if controller.phase == AttackController.Phase.IDLE and spy.query_count > 0:
			break
	assert_eq(spy.query_count, 1, "one query per swing")
	assert_true(controller.can_attack() or controller.cooldown_remaining() > 0.0, "swing finished")


func test_swing_without_detector_resolves_as_no_target() -> void:
	var controller := _make_controller(_make_definition())
	var results: Array[DamageResult] = []
	controller.attack_resolved.connect(func(result: DamageResult) -> void: results.append(result))
	controller.request_attack()
	controller.advance(0.31)
	assert_eq(results.size(), 1, "one resolution")
	assert_false(results[0].applied, "no detector means no hit")
	assert_eq(results[0].miss_reason, DamageResult.REASON_NO_TARGET, "explicit reason")


func test_hit_frame_happens_on_the_first_tick_at_or_after_windup() -> void:
	var pair := _make_controller_with_detector(_make_definition(0.3, 0.1, 0.4, 1.0))
	var controller: AttackController = pair[0]
	var spy: SpyDetector = pair[1]
	controller.request_attack()
	# Just below the windup boundary: still no query.
	controller.advance(0.29)
	assert_eq(spy.query_count, 0, "no query before windup elapses")
	assert_eq(controller.phase, AttackController.Phase.WINDUP, "still winding up")
	# Crossing the boundary resolves the hit exactly at that tick.
	controller.advance(0.01)
	assert_eq(spy.query_count, 1, "query on the boundary tick")
	assert_eq(controller.phase, AttackController.Phase.ACTIVE, "active phase")


func test_zero_windup_attack_resolves_on_the_first_advance() -> void:
	var pair := _make_controller_with_detector(_make_definition(0.0, 0.1, 0.0, 0.5))
	var controller: AttackController = pair[0]
	var spy: SpyDetector = pair[1]
	controller.request_attack()
	assert_eq(controller.phase, AttackController.Phase.WINDUP, "windup starts immediately")
	controller.advance(0.0)
	assert_eq(spy.query_count, 1, "instant attacks resolve on the first tick")


func test_result_is_exposed_after_the_swing() -> void:
	var controller := _make_controller(_make_definition())
	controller.request_attack()
	controller.advance(0.5)
	assert_not_null(controller.last_result(), "last result stored for presentation/debug")
	assert_eq(controller.last_result().miss_reason, DamageResult.REASON_NO_TARGET, "miss without a detector")


func test_cooldown_gates_the_next_swing_until_it_elapses() -> void:
	var definition := _make_definition(0.1, 0.1, 0.1, 1.0)  # swing 0.3 s, cooldown 1.0 s
	var controller := _make_controller(definition)
	assert_true(controller.request_attack(), "first swing")
	for _i in 40:
		controller.advance(0.02)
	assert_eq(controller.phase, AttackController.Phase.IDLE, "back to idle")
	assert_false(controller.can_attack(), "cooldown still running (swing start was 0.9 s ago)")
	assert_false(controller.request_attack(), "request during cooldown rejected")
	controller.advance(0.2)
	assert_true(controller.can_attack(), "cooldown elapsed")


func test_cooldown_is_counted_from_swing_start() -> void:
	var definition := _make_definition(0.3, 0.1, 0.4, 1.0)  # swing 0.8 s, cooldown 1.0 s
	var controller := _make_controller(definition)
	controller.request_attack()
	for _i in 100:
		controller.advance(0.01)
		if controller.phase == AttackController.Phase.IDLE and controller.last_result() != null:
			break
	assert_almost_eq(controller.cooldown_remaining(), 0.2, 0.05, "remaining cooldown counts from swing start")


func test_abort_during_windup_skips_the_hit() -> void:
	var pair := _make_controller_with_detector(_make_definition())
	var controller: AttackController = pair[0]
	var spy: SpyDetector = pair[1]
	var results: Array[DamageResult] = []
	controller.attack_resolved.connect(func(result: DamageResult) -> void: results.append(result))
	controller.request_attack()
	controller.advance(0.1)
	controller.abort(&"dead")
	assert_eq(controller.phase, AttackController.Phase.IDLE, "abort returns to idle")
	assert_eq(spy.query_count, 0, "aborted swing never queries")
	assert_eq(results.size(), 0, "no resolution emitted")
	assert_eq(controller.abort_reason(), &"dead", "abort reason recorded")
	controller.advance(1.0)
	assert_eq(spy.query_count, 0, "no delayed hit after abort")


func test_abort_clears_the_cooldown_and_allows_a_new_swing() -> void:
	var controller := _make_controller(_make_definition())
	controller.request_attack()
	controller.abort(&"interrupted")
	assert_true(controller.can_attack(), "a cancelled swing does not block the next one")


func test_abort_while_idle_is_a_no_op() -> void:
	var controller := _make_controller(_make_definition())
	controller.abort(&"nothing")
	assert_eq(controller.phase, AttackController.Phase.IDLE, "still idle")
	assert_eq(controller.abort_reason(), &"", "no abort reason recorded")


func test_abort_during_recovery_ends_the_swing() -> void:
	var controller := _make_controller(_make_definition(0.1, 0.1, 1.0, 1.0))
	controller.request_attack()
	controller.advance(0.25)
	assert_eq(controller.phase, AttackController.Phase.RECOVERY, "in recovery")
	controller.abort(&"dead")
	assert_eq(controller.phase, AttackController.Phase.IDLE, "abort from recovery works")


func test_invalid_definition_blocks_attacks() -> void:
	var definition := _make_definition()
	definition.id = &""
	var controller := _make_controller(definition)
	assert_false(controller.can_attack(), "invalid data cannot be used")
	assert_false(controller.request_attack(), "no swing starts")
	assert_eq(controller.phase, AttackController.Phase.IDLE, "stays idle")


func test_missing_definition_blocks_attacks() -> void:
	var controller := _make_controller(null)
	assert_false(controller.can_attack(), "no data means no attack")
	assert_false(controller.request_attack(), "no swing starts")


func test_auto_tick_flag_controls_physics_processing() -> void:
	# `_make_controller` sets auto_tick = false before entering the tree, so this
	# asserts the _ready() wiring itself, not just the field value.
	var controller := _make_controller(_make_definition())
	assert_false(
		controller.is_physics_processing(),
		"auto_tick = false must disable _physics_process in _ready()"
	)
	var ticking := AttackController.new()
	ticking.definition = _make_definition()
	ticking.auto_tick = true
	add_to_tree(ticking)
	assert_true(ticking.is_physics_processing(), "auto_tick = true keeps _physics_process enabled")


func test_nearest_candidate_rejection_reason_is_reported() -> void:
	## ADR-004: attack_resolved carries the *closest* rejection reason. The nearest
	## candidate here is behind the attacker (outside the arc); the farther one is
	## straight ahead but beyond reach, so a "last rejection wins" bug would report
	## out_of_reach instead of out_of_arc.
	var controller := _make_controller(_make_definition(0.3, 0.1, 0.4, 1.0))
	var origin := Node3D.new()
	add_to_tree(origin)
	controller.hit_origin = origin
	var detector := ScriptedDetector.new()
	add_to_tree(detector)
	controller.hit_detector = detector
	var behind := Node3D.new()
	add_to_tree(behind)
	var far_ahead := Node3D.new()
	add_to_tree(far_ahead)
	detector.scripted = [
		HitCandidate.new(behind, Vector3(0, 0, 0.5), 0.5, false),
		HitCandidate.new(far_ahead, Vector3(0, 0, -9.0), 9.0, false),
	]
	controller.request_attack()
	controller.advance(0.31)
	assert_not_null(controller.last_result(), "the swing resolved")
	if controller.last_result() != null:
		assert_eq(
			controller.last_result().miss_reason,
			DamageResult.REASON_OUT_OF_ARC,
			"the nearest candidate's reason is reported"
		)


func test_abort_reason_describes_only_the_last_cancelled_swing() -> void:
	var controller := _make_controller(_make_definition(0.1, 0.1, 0.1, 0.5))
	controller.request_attack()
	controller.abort(&"dead")
	assert_eq(controller.abort_reason(), &"dead", "the cancel reason is recorded")
	for _i in 200:
		if controller.can_attack():
			break
		controller.advance(0.02)
	assert_true(controller.request_attack(), "a fresh swing starts")
	controller.advance(0.2)
	assert_eq(
		controller.abort_reason(),
		&"",
		"a later swing must not inherit a stale abort reason"
	)


func test_phase_name_is_stable_for_hud_and_debug() -> void:
	var controller := _make_controller(_make_definition(0.2, 0.1, 0.2, 0.5))
	assert_eq(controller.phase_name(), &"idle", "idle name")
	controller.request_attack()
	assert_eq(controller.phase_name(), &"windup", "windup name")
	controller.advance(0.25)
	assert_eq(controller.phase_name(), &"active", "active name")
	controller.advance(0.15)
	assert_eq(controller.phase_name(), &"recovery", "recovery name")
