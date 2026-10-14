extends "res://tests/test_case.gd"

## AC-09 — attack definition data validation (pure, no scene).


func _make_valid_definition() -> AttackDefinition:
	var definition := AttackDefinition.new()
	definition.id = &"attack.test.basic"
	definition.damage = 12.0
	definition.reach = 1.8
	definition.hit_radius = 0.25
	definition.windup = 0.3
	definition.active_window = 0.1
	definition.recovery = 0.4
	definition.cooldown = 0.8
	return definition


func test_valid_definition_has_no_errors() -> void:
	var definition := _make_valid_definition()
	assert_eq(definition.validation_errors().size(), 0, "valid definition reports no errors")
	assert_true(definition.is_valid(), "is_valid agrees")


func test_empty_id_is_rejected() -> void:
	var definition := _make_valid_definition()
	definition.id = &""
	assert_false(definition.is_valid(), "empty id invalid")
	assert_true(_errors_mention(definition, "id"), "error names the id field")


func test_negative_damage_is_rejected() -> void:
	var definition := _make_valid_definition()
	definition.damage = -1.0
	assert_false(definition.is_valid(), "negative damage invalid")


func test_zero_damage_is_allowed() -> void:
	var definition := _make_valid_definition()
	definition.damage = 0.0
	assert_true(definition.is_valid(), "a zero-damage attack is data-valid (used for reads/feints later)")


func test_non_positive_reach_is_rejected() -> void:
	var definition := _make_valid_definition()
	definition.reach = 0.0
	assert_false(definition.is_valid(), "zero reach invalid")
	definition.reach = -2.0
	assert_false(definition.is_valid(), "negative reach invalid")


func test_non_positive_hit_radius_is_rejected() -> void:
	var definition := _make_valid_definition()
	definition.hit_radius = 0.0
	assert_false(definition.is_valid(), "zero hit radius invalid")


func test_negative_windup_and_recovery_are_rejected() -> void:
	var definition := _make_valid_definition()
	definition.windup = -0.1
	assert_false(definition.is_valid(), "negative windup invalid")
	definition = _make_valid_definition()
	definition.recovery = -0.1
	assert_false(definition.is_valid(), "negative recovery invalid")


func test_zero_windup_and_recovery_are_allowed() -> void:
	var definition := _make_valid_definition()
	definition.windup = 0.0
	definition.recovery = 0.0
	assert_true(definition.is_valid(), "instant attacks are data-valid")


func test_non_positive_active_window_is_rejected() -> void:
	var definition := _make_valid_definition()
	definition.active_window = 0.0
	assert_false(definition.is_valid(), "an attack needs a hit frame, so active_window must be > 0")


func test_negative_cooldown_is_rejected() -> void:
	var definition := _make_valid_definition()
	definition.cooldown = -0.5
	assert_false(definition.is_valid(), "negative cooldown invalid")


func test_swing_duration_sums_the_phases() -> void:
	var definition := _make_valid_definition()
	assert_almost_eq(definition.swing_duration(), 0.8, 0.0001, "windup + active + recovery")


func test_errors_are_reported_per_field() -> void:
	var definition := _make_valid_definition()
	definition.damage = -1.0
	definition.reach = 0.0
	definition.cooldown = -1.0
	assert_eq(definition.validation_errors().size(), 3, "one message per invalid field")


func test_definition_is_a_resource_and_defaults_are_valid_for_editing() -> void:
	var definition := AttackDefinition.new()
	assert_instance_of(definition, "Resource")
	# A fresh, editor-created definition only misses the id, which the author must supply.
	assert_eq(definition.validation_errors().size(), 1, "only the missing id is reported by default")
	assert_true(_errors_mention(definition, "id"), "and it is the id error")


func _errors_mention(definition: AttackDefinition, needle: String) -> bool:
	for message in definition.validation_errors():
		if message.contains(needle):
			return true
	return false
