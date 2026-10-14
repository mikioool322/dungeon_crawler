extends "res://tests/test_case.gd"

## Transition-table coverage for the pure enemy FSM (ADR-006, AC-06, AC-07).
##
## Pure and deterministic: no SceneTree, no physics, no timers. Every row of the
## table documented in `systems/ai/enemy_fsm.gd` has a dedicated test, boundary
## values are asserted explicitly, and the sprint rule (a target that retreats
## during the windup turns the swing into a miss but never cancels it) is pinned
## down here without any engine state.


func _params(
	detection_radius: float = 12.0, lose_radius: float = 16.0, attack_range: float = 1.8
) -> EnemyFsm.Params:
	var params := EnemyFsm.Params.new()
	params.detection_radius = detection_radius
	params.lose_radius = lose_radius
	params.attack_range = attack_range
	return params


func _inputs(
	has_target: bool = true,
	distance: float = 5.0,
	has_line_of_sight: bool = true,
	attack_ready: bool = false,
	attack_in_progress: bool = false,
	is_alive: bool = true
) -> EnemyFsm.Inputs:
	var inputs := EnemyFsm.Inputs.new()
	inputs.has_target = has_target
	inputs.distance = distance
	inputs.has_line_of_sight = has_line_of_sight
	inputs.attack_ready = attack_ready
	inputs.attack_in_progress = attack_in_progress
	inputs.is_alive = is_alive
	return inputs


func _assert_dead_decision(state: EnemyFsm.State) -> void:
	var decision := EnemyFsm.step(state, _inputs(true, 0.5, true, true, true, false), _params())
	var label := EnemyFsm.state_name(state)
	assert_eq(decision.next, EnemyFsm.State.DEAD, "%s + not alive -> DEAD" % label)
	assert_true(decision.force_stop, "%s + not alive -> force_stop" % label)
	assert_false(decision.want_attack, "%s + not alive -> never attack" % label)


# --- DEAD row ----------------------------------------------------------------

func test_not_alive_reaches_dead_from_every_state() -> void:
	_assert_dead_decision(EnemyFsm.State.IDLE)
	_assert_dead_decision(EnemyFsm.State.CHASE)
	_assert_dead_decision(EnemyFsm.State.ATTACK)
	_assert_dead_decision(EnemyFsm.State.DEAD)


func test_dead_is_terminal_and_never_attacks() -> void:
	var tempting := _inputs(true, 0.5, true, true, true, true)
	var decision := EnemyFsm.step(EnemyFsm.State.DEAD, tempting, _params())
	assert_eq(decision.next, EnemyFsm.State.DEAD, "DEAD never leaves DEAD")
	assert_true(decision.force_stop, "DEAD never moves")
	assert_false(decision.want_attack, "DEAD never attacks")


# --- IDLE rows ---------------------------------------------------------------

func test_idle_requires_target_radius_and_line_of_sight() -> void:
	var params := _params()
	var detected := EnemyFsm.step(EnemyFsm.State.IDLE, _inputs(true, 5.0, true), params)
	assert_eq(detected.next, EnemyFsm.State.CHASE, "in radius with line of sight -> CHASE")
	assert_false(detected.force_stop, "a chasing enemy is allowed to move")
	assert_false(detected.want_attack, "detection never starts an attack")

	var out_of_radius := EnemyFsm.step(EnemyFsm.State.IDLE, _inputs(true, 20.0, true), params)
	assert_eq(out_of_radius.next, EnemyFsm.State.IDLE, "beyond detection_radius -> IDLE")
	assert_true(out_of_radius.force_stop, "an idle enemy stands still")

	var blocked := EnemyFsm.step(EnemyFsm.State.IDLE, _inputs(true, 5.0, false), params)
	assert_eq(blocked.next, EnemyFsm.State.IDLE, "no line of sight -> IDLE")
	assert_true(blocked.force_stop, "an enemy without line of sight stands still")

	var targetless := EnemyFsm.step(EnemyFsm.State.IDLE, _inputs(false, 5.0, true), params)
	assert_eq(targetless.next, EnemyFsm.State.IDLE, "no target -> IDLE")
	assert_true(targetless.force_stop, "a targetless enemy stands still")


func test_detection_boundary_is_inclusive() -> void:
	var params := _params()
	var exactly := _inputs(true, params.detection_radius, true)
	assert_eq(
		EnemyFsm.step(EnemyFsm.State.IDLE, exactly, params).next,
		EnemyFsm.State.CHASE,
		"exactly at detection_radius is detected"
	)
	var past := _inputs(true, params.detection_radius + 0.01, true)
	assert_eq(
		EnemyFsm.step(EnemyFsm.State.IDLE, past, params).next,
		EnemyFsm.State.IDLE,
		"just beyond detection_radius is not detected"
	)


# --- CHASE rows --------------------------------------------------------------

func test_hysteresis_between_detection_and_lose_radius() -> void:
	## Between the two radii the enemy keeps chasing: that gap is the hysteresis
	## band that stops a target on the detection edge from flickering IDLE/CHASE.
	var params := _params(12.0, 16.0, 1.8)
	var inputs := _inputs(true, 14.0, true)
	var decision := EnemyFsm.step(EnemyFsm.State.CHASE, inputs, params)
	assert_eq(decision.next, EnemyFsm.State.CHASE, "detection lost, but not yet lose_radius")
	assert_false(decision.force_stop, "the chase continues")

	var still_idle := EnemyFsm.step(EnemyFsm.State.IDLE, _inputs(true, 14.0, true), params)
	assert_eq(still_idle.next, EnemyFsm.State.IDLE, "the same distance never re-detects")


func test_chase_gives_up_beyond_lose_radius_with_force_stop() -> void:
	var params := _params(12.0, 16.0, 1.8)
	var boundary := EnemyFsm.step(EnemyFsm.State.CHASE, _inputs(true, 16.0, true), params)
	assert_eq(boundary.next, EnemyFsm.State.CHASE, "exactly at lose_radius still chases")

	var past := EnemyFsm.step(EnemyFsm.State.CHASE, _inputs(true, 16.01, true), params)
	assert_eq(past.next, EnemyFsm.State.IDLE, "beyond lose_radius -> IDLE")
	assert_true(past.force_stop, "giving up stops the enemy")

	var targetless := EnemyFsm.step(EnemyFsm.State.CHASE, _inputs(false, 3.0, true), params)
	assert_eq(targetless.next, EnemyFsm.State.IDLE, "a freed target -> IDLE")
	assert_true(targetless.force_stop, "losing the target stops the enemy")


func test_chase_attacks_only_in_range_ready_and_with_target_and_sight() -> void:
	var params := _params()
	var in_range := EnemyFsm.step(EnemyFsm.State.CHASE, _inputs(true, 1.5, true, true), params)
	assert_eq(in_range.next, EnemyFsm.State.ATTACK, "in range + ready + sight + target -> ATTACK")
	assert_true(in_range.want_attack, "the transition requests one swing")

	var far := EnemyFsm.step(EnemyFsm.State.CHASE, _inputs(true, 3.0, true, true), params)
	assert_eq(far.next, EnemyFsm.State.CHASE, "out of attack_range -> keep chasing")
	assert_false(far.want_attack, "no swing while out of range")

	var cooling := EnemyFsm.step(EnemyFsm.State.CHASE, _inputs(true, 1.5, true, false), params)
	assert_eq(cooling.next, EnemyFsm.State.CHASE, "attack on cooldown -> keep chasing")
	assert_false(cooling.want_attack, "no swing while on cooldown")

	var blocked := EnemyFsm.step(EnemyFsm.State.CHASE, _inputs(true, 1.5, false, true), params)
	assert_eq(blocked.next, EnemyFsm.State.CHASE, "no line of sight -> never attacks")
	assert_false(blocked.want_attack, "no swing through a wall")


func test_attack_range_boundary_is_inclusive() -> void:
	var params := _params(12.0, 16.0, 1.8)
	var exactly := _inputs(true, params.attack_range, true, true)
	assert_eq(
		EnemyFsm.step(EnemyFsm.State.CHASE, exactly, params).next,
		EnemyFsm.State.ATTACK,
		"exactly at attack_range may attack"
	)
	var past := _inputs(true, params.attack_range + 0.01, true, true)
	assert_eq(
		EnemyFsm.step(EnemyFsm.State.CHASE, past, params).next,
		EnemyFsm.State.CHASE,
		"just beyond attack_range keeps chasing"
	)


# --- ATTACK rows -------------------------------------------------------------

func test_want_attack_is_an_edge_not_a_level() -> void:
	var params := _params()
	var entering := EnemyFsm.step(EnemyFsm.State.CHASE, _inputs(true, 1.5, true, true), params)
	assert_true(entering.want_attack, "the entering tick requests the swing")

	var mid_swing := EnemyFsm.step(
		EnemyFsm.State.ATTACK, _inputs(true, 1.5, true, false, true), params
	)
	assert_eq(mid_swing.next, EnemyFsm.State.ATTACK, "the swing keeps the state")
	assert_false(mid_swing.want_attack, "an in-flight swing is never re-requested")

	var still_swinging := EnemyFsm.step(
		EnemyFsm.State.ATTACK, _inputs(true, 1.5, true, false, true), params
	)
	assert_false(still_swinging.want_attack, "want_attack is not a level")


func test_target_retreating_during_the_windup_does_not_cancel_the_swing() -> void:
	## The sprint mechanic: no cancellation, no iframes. The swing keeps running
	## and simply misses at the hit frame because the target left the reach.
	var params := _params(12.0, 16.0, 1.8)
	var retreating := _inputs(true, 10.0, true, false, true)
	var decision := EnemyFsm.step(EnemyFsm.State.ATTACK, retreating, params)
	assert_eq(decision.next, EnemyFsm.State.ATTACK, "out of reach, still swinging")
	assert_false(decision.want_attack, "no second swing")
	assert_true(decision.force_stop, "the swing plants the enemy's feet")

	var targetless := EnemyFsm.step(EnemyFsm.State.ATTACK, _inputs(false, 1.5, true, false, true), params)
	assert_eq(
		targetless.next,
		EnemyFsm.State.IDLE,
		"a freed target stops the chase (the in-flight swing still resolves as a miss)"
	)
	assert_true(targetless.force_stop, "a stopped enemy plants its feet")


func test_attack_returns_to_chase_when_the_swing_finishes() -> void:
	var params := _params(12.0, 16.0, 1.8)
	var decision := EnemyFsm.step(EnemyFsm.State.ATTACK, _inputs(true, 3.0, true, false, false), params)
	assert_eq(decision.next, EnemyFsm.State.CHASE, "swing finished inside lose_radius -> CHASE")
	assert_false(decision.want_attack, "the finished swing is not repeated")
	assert_false(decision.force_stop, "the chase resumes movement")


func test_attack_beyond_lose_radius_returns_to_idle() -> void:
	var params := _params(12.0, 16.0, 1.8)
	var decision := EnemyFsm.step(EnemyFsm.State.ATTACK, _inputs(true, 16.01, true, false, true), params)
	assert_eq(decision.next, EnemyFsm.State.IDLE, "swinging target escaped past lose_radius -> IDLE")
	assert_true(decision.force_stop, "giving up stops the enemy")
	assert_false(decision.want_attack, "no attack after giving up")


# --- safety and helpers ------------------------------------------------------

func test_step_without_inputs_or_params_stops_safely() -> void:
	var no_inputs := EnemyFsm.step(EnemyFsm.State.CHASE, null, _params())
	assert_true(no_inputs.force_stop, "missing inputs -> stop")

	var no_params := EnemyFsm.step(EnemyFsm.State.CHASE, _inputs(), null)
	assert_true(no_params.force_stop, "missing params -> stop")


func test_params_factory_mirrors_the_definition() -> void:
	var definition := EnemyDefinition.new()
	definition.id = &"enemy.test"
	definition.detection_radius = 7.5
	definition.lose_radius = 9.0
	definition.attack_range = 2.25
	definition.stop_distance = 2.0
	var attack := AttackDefinition.new()
	attack.id = &"attack.test"
	definition.attack_definition = attack

	var params := EnemyFsm.Params.from_definition(definition)
	assert_almost_eq(params.detection_radius, 7.5, 0.0001, "detection radius is copied")
	assert_almost_eq(params.lose_radius, 9.0, 0.0001, "lose radius is copied")
	assert_almost_eq(params.attack_range, 2.25, 0.0001, "attack range is copied")

	var fallback := EnemyFsm.Params.from_definition(null)
	assert_almost_eq(fallback.detection_radius, 0.0, 0.0001, "no definition -> inert radii")
	assert_almost_eq(fallback.lose_radius, 0.0, 0.0001, "no definition -> inert radii")
	assert_almost_eq(fallback.attack_range, 0.0, 0.0001, "no definition -> inert attack range")


func test_state_names_are_stable() -> void:
	assert_eq(EnemyFsm.state_name(EnemyFsm.State.IDLE), &"idle")
	assert_eq(EnemyFsm.state_name(EnemyFsm.State.CHASE), &"chase")
	assert_eq(EnemyFsm.state_name(EnemyFsm.State.ATTACK), &"attack")
	assert_eq(EnemyFsm.state_name(EnemyFsm.State.DEAD), &"dead")
