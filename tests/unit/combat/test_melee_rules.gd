extends "res://tests/test_case.gd"

## AC-02 — range is decided by a pure rule at the hit frame, independent of physics.


func test_hit_inside_reach_is_accepted() -> void:
	var origin := Vector3.ZERO
	assert_true(MeleeRules.within_reach(origin, Vector3(1.5, 0, 0), 2.0, 0.3), "1.5 m vs reach 2.0")


func test_hit_exactly_at_limit_is_inclusive() -> void:
	var origin := Vector3.ZERO
	var reach := 2.0
	var tolerance := 0.3
	assert_true(
		MeleeRules.within_reach(origin, Vector3(reach + tolerance, 0, 0), reach, tolerance),
		"contact exactly at reach + tolerance must count as a hit"
	)


func test_hit_just_beyond_limit_is_rejected() -> void:
	var origin := Vector3.ZERO
	var contact := Vector3(2.301, 0, 0)
	assert_false(MeleeRules.within_reach(origin, contact, 2.0, 0.3), "2.301 m vs limit 2.3")


func test_far_target_is_out_of_reach() -> void:
	assert_false(MeleeRules.within_reach(Vector3.ZERO, Vector3(10, 0, 0), 2.0, 0.3), "10 m")


func test_backpedal_target_crossing_the_limit_misses() -> void:
	var origin := Vector3.ZERO
	var reach := 1.7
	var tolerance := 0.25
	var in_range := Vector3(1.9, 0, 0)
	var after_backpedal := Vector3(2.4, 0, 0)
	assert_true(MeleeRules.within_reach(origin, in_range, reach, tolerance), "inside the gate before retreat")
	assert_false(
		MeleeRules.within_reach(origin, after_backpedal, reach, tolerance),
		"walking backwards out of reach avoids the hit"
	)


func test_distance_is_three_dimensional() -> void:
	# A target right below the origin does not count as "in front".
	assert_false(MeleeRules.within_reach(Vector3(0, 5, 0), Vector3(0, 0, 0), 2.0, 0.3), "5 m below")


func test_negative_inputs_are_clamped() -> void:
	assert_eq(MeleeRules.range_limit(-1.0, -1.0), 0.0, "negative reach/tolerance clamp to zero")
	assert_false(MeleeRules.within_reach(Vector3.ZERO, Vector3(0.01, 0, 0), -1.0, -1.0), "empty gate never hits")
