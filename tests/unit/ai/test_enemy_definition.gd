extends "res://tests/test_case.gd"

## EnemyDefinition validation and the shipped content data (ADR-006, AC-09).
##
## Pure (no SceneTree): the definition is static data and must be usable without
## instantiating a scene. Loading the shipped .tres files here also proves they
## parse and are accepted by the same validation the runtime uses.

const ENEMY_GRUNT_PATH := "res://content/definitions/enemy_grunt.tres"
const ATTACK_ENEMY_BASIC_PATH := "res://content/definitions/attack_enemy_basic.tres"


func _make_attack() -> AttackDefinition:
	var attack := AttackDefinition.new()
	attack.id = &"attack.test.basic"
	return attack


func _make_definition() -> EnemyDefinition:
	var definition := EnemyDefinition.new()
	definition.id = &"enemy.test"
	definition.attack_definition = _make_attack()
	return definition


func _errors(definition: EnemyDefinition) -> String:
	return " | ".join(definition.validation_errors())


# --- validation --------------------------------------------------------------

func test_a_configured_definition_is_valid() -> void:
	var definition := _make_definition()
	assert_true(definition.is_valid(), "expected no errors, got: %s" % _errors(definition))


func test_empty_id_is_rejected() -> void:
	var definition := _make_definition()
	definition.id = &""
	assert_false(definition.is_valid(), "an empty id is not a stable content id")
	assert_true(_errors(definition).contains("id"), "the error names the field: %s" % _errors(definition))


func test_non_positive_max_health_is_rejected() -> void:
	var definition := _make_definition()
	definition.max_health = 0.0
	assert_false(definition.is_valid(), "max_health 0 is rejected")
	definition.max_health = -10.0
	assert_false(definition.is_valid(), "negative max_health is rejected")
	definition.max_health = 0.5
	assert_true(definition.is_valid(), "a small positive max_health is fine")


func test_negative_move_speed_is_rejected() -> void:
	var definition := _make_definition()
	definition.move_speed = -0.1
	assert_false(definition.is_valid(), "negative move_speed is rejected")
	definition.move_speed = 0.0
	assert_true(definition.is_valid(), "a stationary enemy is legal (move_speed 0)")


func test_non_positive_detection_radius_is_rejected() -> void:
	var definition := _make_definition()
	definition.detection_radius = 0.0
	assert_false(definition.is_valid(), "detection_radius must be > 0")


func test_lose_radius_below_detection_radius_is_rejected() -> void:
	var definition := _make_definition()
	definition.detection_radius = 12.0
	definition.lose_radius = 11.99
	assert_false(definition.is_valid(), "lose_radius < detection_radius breaks hysteresis")
	definition.lose_radius = 12.0
	assert_true(definition.is_valid(), "lose_radius == detection_radius is accepted (no band)")


func test_non_positive_attack_range_is_rejected() -> void:
	var definition := _make_definition()
	definition.attack_range = 0.0
	assert_false(definition.is_valid(), "attack_range must be > 0")


func test_stop_distance_must_be_positive_and_at_most_attack_range() -> void:
	var definition := _make_definition()
	definition.attack_range = 1.8
	definition.stop_distance = 0.0
	assert_false(definition.is_valid(), "stop_distance must be > 0")
	definition.stop_distance = 1.81
	assert_false(definition.is_valid(), "stopping outside attack_range would never attack")
	definition.stop_distance = 1.8
	assert_true(definition.is_valid(), "stop_distance == attack_range is accepted")


func test_missing_or_invalid_attack_definition_is_rejected() -> void:
	var definition := _make_definition()
	definition.attack_definition = null
	assert_false(definition.is_valid(), "an enemy without an attack is unusable")

	var broken_attack := AttackDefinition.new()  # empty id
	definition.attack_definition = broken_attack
	assert_false(definition.is_valid(), "an invalid attack definition is rejected")
	assert_true(
		_errors(definition).contains("attack_definition"),
		"the error names the nested field: %s" % _errors(definition)
	)


func test_validation_reports_every_broken_field() -> void:
	var definition := EnemyDefinition.new()  # no id, no attack
	definition.max_health = 0.0
	definition.move_speed = -1.0
	definition.detection_radius = 0.0
	definition.lose_radius = -1.0
	definition.attack_range = 0.0
	definition.stop_distance = 5.0
	var report := _errors(definition)
	for field in [
		"id",
		"max_health",
		"move_speed",
		"detection_radius",
		"lose_radius",
		"attack_range",
		"stop_distance",
		"attack_definition",
	]:
		assert_true(report.contains(field), "the report mentions %s: %s" % [field, report])


# --- shipped content ---------------------------------------------------------

func test_shipped_attack_definition_matches_the_sprint_values() -> void:
	var attack := load(ATTACK_ENEMY_BASIC_PATH) as AttackDefinition
	assert_not_null(attack, "attack_enemy_basic.tres loads as AttackDefinition")
	if attack == null:
		return
	assert_true(attack.is_valid(), "the shipped attack is valid: %s" % attack.validation_errors())
	assert_eq(attack.id, &"attack.enemy.basic")
	assert_almost_eq(attack.damage, 12.0)
	assert_almost_eq(attack.reach, 1.7)
	assert_almost_eq(attack.hit_radius, 0.25)
	assert_almost_eq(attack.hit_arc_degrees, 60.0)
	assert_almost_eq(attack.windup, 0.7, 0.0001, "the escape window")
	assert_almost_eq(attack.active_window, 0.15)
	assert_almost_eq(attack.recovery, 0.9)
	assert_almost_eq(attack.cooldown, 1.9)


func test_shipped_enemy_definition_matches_the_sprint_values() -> void:
	var definition := load(ENEMY_GRUNT_PATH) as EnemyDefinition
	assert_not_null(definition, "enemy_grunt.tres loads as EnemyDefinition")
	if definition == null:
		return
	assert_true(
		definition.is_valid(), "the shipped enemy is valid: %s" % definition.validation_errors()
	)
	assert_eq(definition.id, &"enemy.grunt")
	assert_almost_eq(definition.max_health, 100.0)
	assert_almost_eq(definition.move_speed, 3.2)
	assert_almost_eq(definition.detection_radius, 12.0)
	assert_almost_eq(definition.lose_radius, 16.0)
	assert_almost_eq(definition.attack_range, 1.8)
	assert_almost_eq(definition.stop_distance, 1.5)
	assert_not_null(definition.attack_definition, "the grunt carries its attack")
	if definition.attack_definition == null:
		return
	assert_eq(definition.attack_definition.id, &"attack.enemy.basic")
	assert_true(
		definition.lose_radius >= definition.detection_radius, "hysteresis band is non-negative"
	)
	assert_true(
		definition.stop_distance <= definition.attack_range,
		"the grunt stops inside its attack range"
	)
