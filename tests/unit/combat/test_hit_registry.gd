extends "res://tests/test_case.gd"

## AC-04 — one damage application per target per swing.


func test_first_registration_wins_and_second_is_rejected() -> void:
	var registry := HitRegistry.new()
	assert_true(registry.register_once(101), "first contact applies damage")
	assert_false(registry.register_once(101), "duplicate contact in the same swing is rejected")
	assert_eq(registry.count(), 1, "registry tracks one target")


func test_distinct_targets_are_independent() -> void:
	var registry := HitRegistry.new()
	assert_true(registry.register_once(1), "target 1")
	assert_true(registry.register_once(2), "target 2")
	assert_eq(registry.count(), 2, "two distinct targets")


func test_has_registered_reflects_state() -> void:
	var registry := HitRegistry.new()
	assert_false(registry.has_registered(7), "unknown before registration")
	registry.register_once(7)
	assert_true(registry.has_registered(7), "known after registration")


func test_clear_starts_a_new_swing() -> void:
	var registry := HitRegistry.new()
	registry.register_once(42)
	registry.clear()
	assert_eq(registry.count(), 0, "cleared")
	assert_true(registry.register_once(42), "the same target can be hit by a later swing")


func test_many_duplicates_apply_once() -> void:
	var registry := HitRegistry.new()
	var applied := 0
	for _i in 25:
		if registry.register_once(5):
			applied += 1
	assert_eq(applied, 1, "25 overlapping contacts still apply damage once")
