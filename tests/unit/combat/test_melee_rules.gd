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


func test_range_is_measured_horizontally_in_sprint_01() -> void:
	# Documented Sprint 01 metric: the physics query reports a target's body origin
	# at its feet, so reach is compared against the horizontal (XZ) distance.
	var eye := Vector3(0, 1.6, 0)
	var feet := Vector3(0, 0, -1.5)
	assert_almost_eq(MeleeRules.horizontal_distance(eye, feet), 1.5, 0.0001, "height is ignored")
	assert_true(MeleeRules.within_reach(eye, feet, 2.0, 0.3), "1.5 m ahead is inside a 2.0 m reach")


func test_horizontal_distance_ignores_only_the_vertical_axis() -> void:
	assert_almost_eq(MeleeRules.horizontal_distance(Vector3.ZERO, Vector3(3, 9, 4)), 5.0, 0.0001, "3-4-5 triangle")


func test_target_behind_the_attacker_is_outside_the_arc() -> void:
	var origin := Vector3.ZERO
	var forward := Vector3(0, 0, -1)  # Godot forward
	assert_true(MeleeRules.within_arc(origin, forward, Vector3(0, 0, -1.5), 60.0), "straight ahead")
	assert_true(MeleeRules.within_arc(origin, forward, Vector3(1.2, 0, -1.2), 60.0), "45 degrees off axis")
	assert_false(MeleeRules.within_arc(origin, forward, Vector3(0, 0, 1.5), 60.0), "directly behind")
	assert_false(MeleeRules.within_arc(origin, forward, Vector3(1.5, 0, 1.0), 60.0), "behind and to the side")


func test_arc_boundary_is_inclusive_and_clamped() -> void:
	var origin := Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	# Avoid asserting on an exact floating-point 60.000 degrees: test just inside/outside.
	var just_inside := Vector3(-sin(deg_to_rad(59.9)), 0, -cos(deg_to_rad(59.9))) * 2.0
	var just_outside := Vector3(-sin(deg_to_rad(60.1)), 0, -cos(deg_to_rad(60.1))) * 2.0
	assert_true(MeleeRules.within_arc(origin, forward, just_inside, 60.0), "59.9 degrees is inside")
	assert_false(MeleeRules.within_arc(origin, forward, just_outside, 60.0), "60.1 degrees is outside")
	assert_true(MeleeRules.within_arc(origin, forward, Vector3(0, 0, 1.0), 180.0), "180 degrees is a full circle")
	assert_true(MeleeRules.within_arc(origin, forward, Vector3(0, 0, 1.0), 720.0), "oversized arc clamps to full circle")
	assert_false(MeleeRules.within_arc(origin, forward, Vector3(0, 0, 1.0), 0.0), "zero arc hits nothing")


func test_target_directly_above_or_below_is_not_excluded_by_the_arc() -> void:
	# The arc is a horizontal test; vertical positioning is handled by range only.
	var origin := Vector3.ZERO
	assert_true(MeleeRules.within_arc(origin, Vector3(0, 0, -1), Vector3(0, 5, 0), 60.0), "degenerate direction accepted")


func test_negative_inputs_are_clamped() -> void:
	assert_eq(MeleeRules.range_limit(-1.0, -1.0), 0.0, "negative reach/tolerance clamp to zero")
	assert_false(MeleeRules.within_reach(Vector3.ZERO, Vector3(0.01, 0, 0), -1.0, -1.0), "empty gate never hits")
