extends "res://tests/test_case.gd"

## AC-35 — effective stats: base + one additive bucket per source, deterministic,
## clamped, and never accumulated by a repeated source.

func _definition(
	hp: float = 100.0, attack: float = 34.0, defense: float = 0.0, speed: float = 4.0
) -> PlayerDefinition:
	var definition := PlayerDefinition.new()
	definition.id = &"player.test"
	definition.display_name = "Tester"
	definition.max_health = hp
	definition.attack_damage = attack
	definition.defense = defense
	definition.movement_speed = speed
	var profile := AttackDefinition.new()
	profile.id = &"attack.test"
	definition.attack_definition = profile
	return definition


func _stats() -> CharacterStats:
	var stats := CharacterStats.new()
	stats.setup(_definition())
	return stats


func test_base_values_are_copied_and_effective_matches_them() -> void:
	var stats := _stats()
	assert_true(stats.is_ready(), "a valid definition readies the stats")
	for stat in CharacterStats.STATS:
		assert_almost_eq(stats.effective(stat), stats.base(stat), 0.0001, "no modifiers: %s" % stat)
	assert_almost_eq(stats.effective(CharacterStats.MAX_HEALTH), 100.0, 0.0001, "base HP")
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001, "base attack")
	assert_almost_eq(stats.effective(CharacterStats.MOVEMENT_SPEED), 4.0, 0.0001, "base speed")


func test_an_invalid_definition_leaves_the_stats_unready() -> void:
	var stats := CharacterStats.new()
	assert_false(stats.setup(null), "null is refused")
	assert_false(stats.is_ready(), "not ready")
	var broken := _definition()
	broken.id = &""
	assert_false(stats.setup(broken), "an invalid definition is refused")
	assert_false(stats.is_ready(), "still not ready")


func test_modifiers_add_to_the_base_and_are_visible_separately() -> void:
	var stats := _stats()
	var changed: Array[int] = []
	stats.changed.connect(func() -> void: changed.append(1))

	var changed_values := stats.set_modifiers(&"main_hand", {
		CharacterStats.ATTACK_DAMAGE: 15.0,
	})
	assert_true(changed_values, "the effective attack changed")
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001, "34 + 15")
	assert_almost_eq(stats.modifier_total(CharacterStats.ATTACK_DAMAGE), 15.0, 0.0001, "bonus shown")
	assert_almost_eq(stats.base(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001, "base untouched")
	assert_eq(changed.size(), 1, "one change notification")


func test_two_sources_stack_additively() -> void:
	var stats := _stats()
	stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0})
	stats.set_modifiers(&"chest_armor", {CharacterStats.DEFENSE: 5.0})
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001, "attack from the hand")
	assert_almost_eq(stats.effective(CharacterStats.DEFENSE), 5.0, 0.0001, "defense from the chest")
	assert_eq(stats.sources().size(), 2, "two buckets")


func test_replacing_a_bucket_never_accumulates() -> void:
	var stats := _stats()
	stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0})
	stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0})
	stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0})
	assert_almost_eq(
		stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001,
		"three identical equip calls still add 15 once"
	)
	assert_eq(stats.sources().size(), 1, "still one bucket")


func test_clearing_a_bucket_removes_its_bonus() -> void:
	var stats := _stats()
	stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0})
	assert_true(stats.clear_modifiers(&"main_hand"), "cleared")
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001, "back to base")
	assert_false(stats.clear_modifiers(&"main_hand"), "clearing twice reports no change")
	assert_false(stats.has_source(&"main_hand"), "the bucket is gone")


func test_empty_modifiers_remove_the_bucket() -> void:
	var stats := _stats()
	stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0})
	stats.set_modifiers(&"main_hand", {})
	assert_false(stats.has_source(&"main_hand"), "an empty bucket is removed")
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001, "base again")


func test_unknown_stats_and_non_finite_values_are_ignored() -> void:
	var stats := _stats()
	var changed := stats.set_modifiers(&"main_hand", {
		&"luck": 10.0,
		CharacterStats.ATTACK_DAMAGE: INF,
		CharacterStats.DEFENSE: NAN,
		CharacterStats.MAX_HEALTH: 20.0,
	})
	assert_true(changed, "the valid entry still applied")
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001, "INF ignored")
	assert_almost_eq(stats.effective(CharacterStats.DEFENSE), 0.0, 0.0001, "NAN ignored")
	assert_almost_eq(stats.effective(CharacterStats.MAX_HEALTH), 120.0, 0.0001, "valid entry applied")


func test_an_empty_source_id_is_refused() -> void:
	var stats := _stats()
	assert_false(stats.set_modifiers(&"", {CharacterStats.ATTACK_DAMAGE: 5.0}), "no anonymous buckets")
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001, "nothing applied")


func test_values_are_clamped_and_never_non_finite() -> void:
	var stats := _stats()
	stats.set_modifiers(&"cursed", {
		CharacterStats.ATTACK_DAMAGE: -500.0,
		CharacterStats.DEFENSE: -20.0,
		CharacterStats.MAX_HEALTH: -100.0,
		CharacterStats.MOVEMENT_SPEED: -10.0,
	})
	for stat in CharacterStats.STATS:
		var value: float = stats.effective(stat)
		assert_true(is_finite(value), "%s stays finite" % stat)
		assert_true(value >= float(CharacterStats.MINIMUM[stat]), "%s respects the floor" % stat)
	assert_almost_eq(stats.effective(CharacterStats.MOVEMENT_SPEED), 0.01, 0.0001, "speed floor")


func test_the_change_signal_fires_only_on_a_real_difference() -> void:
	var stats := _stats()
	var changed: Array[int] = []
	stats.changed.connect(func() -> void: changed.append(1))
	stats.set_modifiers(&"main_hand", {CharacterStats.DEFENSE: 0.0})
	assert_eq(changed.size(), 0, "a zero bonus changes nothing")
	stats.set_modifiers(&"main_hand", {CharacterStats.DEFENSE: 5.0})
	assert_eq(changed.size(), 1, "a real bonus notifies")
	stats.set_modifiers(&"main_hand", {CharacterStats.DEFENSE: 5.0})
	assert_eq(changed.size(), 1, "the same value does not notify again")
