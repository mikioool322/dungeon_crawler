extends "res://tests/test_case.gd"

## S04-QA — independent verification of the `CharacterStats` contract (ADR-015).
##
## Gaps this file closes (the shipped suites assert single calls, not long cycles):
## - `set_modifiers` replaces a bucket across hundreds of equip/unequip-style cycles and
##   two different sources keep stacking.
## - `changed` fires only when an effective value really differs (including a
##   zero-sum bucket pair and zero-valued buckets).
## - hostile/non-numeric modifier values can never produce NaN/Infinity or an effective
##   value below the documented floor.
## - an invalid `PlayerDefinition` leaves the stats inert (no value, no signal).

func _definition(
	hp: float = 100.0, attack: float = 34.0, defense: float = 0.0, speed: float = 4.0
) -> PlayerDefinition:
	var definition := PlayerDefinition.new()
	definition.id = &"player.qa"
	definition.display_name = "QA Tester"
	definition.max_health = hp
	definition.attack_damage = attack
	definition.defense = defense
	definition.movement_speed = speed
	var profile := AttackDefinition.new()
	profile.id = &"attack.qa"
	definition.attack_definition = profile
	return definition


func _stats() -> CharacterStats:
	var stats := CharacterStats.new()
	stats.setup(_definition())
	return stats


func test_replacement_survives_hundreds_of_equip_unequip_cycles() -> void:
	var stats := _stats()
	# A second, different slot must survive the churn of the first one.
	stats.set_modifiers(&"chest_armor", {CharacterStats.DEFENSE: 5.0})
	for cycle in 300:
		stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0})
		if cycle % 60 == 0:
			assert_almost_eq(
				stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001,
				"cycle %d: the same bucket never accumulates" % cycle
			)
		stats.clear_modifiers(&"main_hand")
		if cycle % 60 == 0:
			assert_almost_eq(
				stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001,
				"cycle %d: clearing restores the base" % cycle
			)
	assert_eq(stats.sources(), [&"chest_armor"] as Array[StringName], "only the armour bucket is left")
	assert_almost_eq(stats.effective(CharacterStats.DEFENSE), 5.0, 0.0001, "the armour bonus survived")


func test_swapping_the_same_bucket_never_accumulates() -> void:
	var stats := _stats()
	for _cycle in 200:
		stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0})
		stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 25.0})
	assert_eq(stats.sources().size(), 1, "still one hand bucket")
	assert_almost_eq(
		stats.effective(CharacterStats.ATTACK_DAMAGE), 59.0, 0.0001,
		"only the last weapon's bonus is counted (34 + 25)"
	)
	assert_almost_eq(
		stats.modifier_total(CharacterStats.ATTACK_DAMAGE), 25.0, 0.0001,
		"the bucket total is the last replacement, not a sum"
	)


func test_two_slots_still_stack_after_the_cycles() -> void:
	var stats := _stats()
	stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0})
	stats.set_modifiers(&"chest_armor", {CharacterStats.DEFENSE: 5.0})
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001, "hand bonus")
	assert_almost_eq(stats.effective(CharacterStats.DEFENSE), 5.0, 0.0001, "chest bonus")
	assert_eq(stats.sources().size(), 2, "two independent buckets")
	# Replacing one slot must not touch the other.
	stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 1.0})
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 35.0, 0.0001, "hand replaced")
	assert_almost_eq(stats.effective(CharacterStats.DEFENSE), 5.0, 0.0001, "chest untouched")


func test_changed_fires_only_when_an_effective_value_really_differs() -> void:
	var stats := _stats()
	var changes: Array[int] = []
	stats.changed.connect(func() -> void: changes.append(1))

	assert_true(
		stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0}),
		"a real bonus reports a change"
	)
	assert_eq(changes.size(), 1, "one notification")
	assert_false(
		stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0}),
		"the identical bucket reports no change"
	)
	assert_false(
		stats.set_modifiers(&"main_hand", {
			CharacterStats.ATTACK_DAMAGE: 15.0,
			CharacterStats.DEFENSE: 0.0,
		}),
		"adding a zero-valued stat to the same bucket reports no change"
	)
	assert_eq(changes.size(), 1, "still one notification")

	# A bucket whose values are all ignored is stored empty and changes nothing.
	assert_false(
		stats.set_modifiers(&"ignored", {CharacterStats.ATTACK_DAMAGE: NAN}),
		"a bucket with no usable value reports no change"
	)
	assert_true(stats.has_source(&"ignored"), "the empty bucket is tracked")
	assert_false(
		stats.clear_modifiers(&"ignored"),
		"removing an empty bucket changes no effective value"
	)
	assert_eq(changes.size(), 1, "still one notification")

	assert_true(
		stats.set_modifiers(&"main_hand", {}),
		"clearing the hand bucket really changes the effective attack"
	)
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001, "back to base")
	assert_eq(changes.size(), 2, "and notifies")
	assert_false(stats.clear_modifiers(&"main_hand"), "clearing the missing bucket reports no change")
	assert_false(stats.clear_modifiers(&"never_registered"), "clearing an unknown source reports no change")
	assert_eq(changes.size(), 2, "no further notifications")


func test_zero_valued_buckets_are_stored_but_never_change_anything() -> void:
	var stats := _stats()
	var changes: Array[int] = []
	stats.changed.connect(func() -> void: changes.append(1))
	assert_false(stats.set_modifiers(&"main_hand", {CharacterStats.DEFENSE: 0.0}), "zero bonus, no change")
	assert_true(stats.has_source(&"main_hand"), "the empty bucket is tracked")
	assert_almost_eq(stats.modifier_total(CharacterStats.DEFENSE), 0.0, 0.0001, "and contributes nothing")
	assert_eq(changes.size(), 0, "and emits nothing")


func test_hostile_values_cannot_poison_any_stat() -> void:
	var stats := _stats()
	var changes: Array[int] = []
	stats.changed.connect(func() -> void: changes.append(1))
	stats.set_modifiers(&"hostile", {
		CharacterStats.ATTACK_DAMAGE: NAN,
		CharacterStats.DEFENSE: -INF,
		CharacterStats.MAX_HEALTH: INF,
		CharacterStats.MOVEMENT_SPEED: NAN,
		&"luck": 10.0,
		"text": "not a number",
		"null": null,
	})
	# Every non-finite/unknown value is ignored: no value moved at all.
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001, "NAN ignored")
	assert_almost_eq(stats.effective(CharacterStats.DEFENSE), 0.0, 0.0001, "-INF ignored")
	assert_almost_eq(stats.effective(CharacterStats.MAX_HEALTH), 100.0, 0.0001, "INF ignored")
	assert_almost_eq(stats.effective(CharacterStats.MOVEMENT_SPEED), 4.0, 0.0001, "NAN ignored")
	assert_eq(changes.size(), 0, "no effective value changed")
	for stat in CharacterStats.STATS:
		var value: float = stats.effective(stat)
		assert_true(is_finite(value), "%s stays finite" % stat)
		assert_true(value >= float(CharacterStats.MINIMUM[stat]), "%s respects the floor" % stat)

	# A huge hostile modifier clamps at the floor and still never leaves the range.
	stats.set_modifiers(&"hostile", {
		CharacterStats.ATTACK_DAMAGE: -1.0e12,
		CharacterStats.DEFENSE: -1.0e12,
		CharacterStats.MAX_HEALTH: -1.0e12,
		CharacterStats.MOVEMENT_SPEED: -1.0e12,
	})
	for stat in CharacterStats.STATS:
		var value: float = stats.effective(stat)
		assert_true(is_finite(value), "%s stays finite under a huge hostile value" % stat)
		assert_almost_eq(value, float(CharacterStats.MINIMUM[stat]), 0.0001, "%s sits on the floor" % stat)
	assert_true(stats.effective(CharacterStats.MOVEMENT_SPEED) > 0.0, "the player is never frozen")


func test_an_invalid_definition_leaves_the_stats_inert() -> void:
	var stats := CharacterStats.new()
	var changes: Array[int] = []
	stats.changed.connect(func() -> void: changes.append(1))

	assert_false(stats.setup(null), "a null definition is refused")
	assert_false(stats.is_ready(), "the stats are not ready")
	# Inert means: no values and no way to move them.
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 0.0, 0.0001, "no effective attack")
	assert_false(
		stats.set_modifiers(&"main_hand", {CharacterStats.ATTACK_DAMAGE: 15.0}),
		"an unready source cannot change anything"
	)
	assert_almost_eq(stats.effective(CharacterStats.ATTACK_DAMAGE), 0.0, 0.0001, "still no value")
	assert_eq(changes.size(), 0, "and never emits changed")

	var broken := _definition()
	broken.id = &""
	assert_false(stats.setup(broken), "an invalid definition is refused")
	assert_false(stats.is_ready(), "still not ready")
	assert_almost_eq(stats.effective(CharacterStats.MAX_HEALTH), 0.0, 0.0001, "still inert")
