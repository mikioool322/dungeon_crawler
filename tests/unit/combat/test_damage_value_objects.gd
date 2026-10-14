extends "res://tests/test_case.gd"

## Value-object hygiene: combat domain objects must not hold scene references,
## because they are exchanged across module boundaries and could leak into
## persistence or presentation code later (AGENTS.md architecture invariants).

const ALLOWED_PROPERTY_TYPES: Array[int] = [
	TYPE_STRING_NAME,
	TYPE_STRING,
	TYPE_FLOAT,
	TYPE_INT,
	TYPE_BOOL,
	TYPE_VECTOR3,
	TYPE_NIL,
]


func test_damage_request_holds_only_value_data() -> void:
	var request := DamageRequest.new(&"attack.test", &"tester", 10.0, Vector3(1, 2, 3), Vector3.UP)
	_assert_value_object(DamageRequest.new(&"attack.test", &"tester", 10.0, Vector3(1, 2, 3), Vector3.UP))
	assert_eq(request.amount, 10.0, "amount round-trips")
	assert_eq(request.hit_position, Vector3(1, 2, 3), "position round-trips")


func test_damage_result_holds_only_value_data() -> void:
	_assert_value_object(DamageResult.applied_hit(&"target", 10.0, false))
	_assert_value_object(DamageResult.miss(&"target", DamageResult.REASON_OUT_OF_REACH))


func test_applied_hit_constructor_sets_the_expected_fields() -> void:
	var result := DamageResult.applied_hit(&"enemy.grunt", 12.5, true)
	assert_true(result.applied, "applied")
	assert_eq(result.damage_dealt, 12.5, "damage")
	assert_eq(result.target_id, &"enemy.grunt", "target id")
	assert_true(result.target_died, "death flag")
	assert_eq(result.miss_reason, DamageResult.REASON_NONE, "no miss reason on a hit")


func test_miss_constructor_never_reports_damage() -> void:
	var result := DamageResult.miss(&"enemy.grunt", DamageResult.REASON_OCCLUDED)
	assert_false(result.applied, "not applied")
	assert_eq(result.damage_dealt, 0.0, "zero damage on a miss")
	assert_false(result.target_died, "a miss never kills")
	assert_eq(result.miss_reason, DamageResult.REASON_OCCLUDED, "reason preserved")


func test_miss_without_a_reason_falls_back_to_no_target() -> void:
	var result := DamageResult.miss(&"", DamageResult.REASON_NONE)
	assert_eq(result.miss_reason, DamageResult.REASON_NO_TARGET, "a miss always explains itself")


func test_miss_reason_vocabulary_matches_the_contract() -> void:
	assert_eq(DamageResult.REASON_OUT_OF_REACH, &"out_of_reach", "out_of_reach")
	assert_eq(DamageResult.REASON_OCCLUDED, &"occluded", "occluded")
	assert_eq(DamageResult.REASON_TARGET_DEAD, &"target_dead", "target_dead")
	assert_eq(DamageResult.REASON_DUPLICATE, &"duplicate", "duplicate")
	assert_eq(DamageResult.REASON_INVALID_AMOUNT, &"invalid_amount", "invalid_amount")
	assert_eq(DamageResult.REASON_INVALID_REQUEST, &"invalid_request", "invalid_request")
	assert_eq(DamageResult.REASON_NO_TARGET, &"no_target", "no_target")


func test_melee_rules_is_pure_and_needs_no_scene() -> void:
	assert_true(MeleeRules.within_reach(Vector3.ZERO, Vector3(1, 0, 0), 2.0, 0.25), "pure call works outside a tree")


func _assert_value_object(value: Object) -> void:
	for property in value.get_property_list():
		var usage: int = property.get("usage", 0)
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var type: int = property.get("type", TYPE_NIL)
		assert_true(
			ALLOWED_PROPERTY_TYPES.has(type),
			"%s.%s must be a value type, got type %d" % [value.get_class(), property.get("name", "?"), type]
		)
