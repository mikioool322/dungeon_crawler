class_name PlayerDefinition
extends Resource

## Static, editor-authored definition of the player character (ADR-015): the single
## source of the *base* stats and the default attack profile. Immutable at runtime;
## equipment never writes here (it contributes additive modifiers to `CharacterStats`).

## Stable content id, e.g. `player.default`.
@export var id: StringName = &"player.default"

## Shown in the character panel.
@export var display_name: String = "Wanderer"

## Base hit points before equipment.
@export var max_health: float = 100.0

## Base attack damage before equipment. The shipped value keeps the Sprint 01/02 swing
## damage (34) identical when nothing is equipped.
@export var attack_damage: float = 34.0

## Base damage mitigation before equipment.
@export var defense: float = 0.0

## Base walking speed in metres per second before equipment.
@export var movement_speed: float = 4.0

## Attack profile used when no weapon overrides it (reach, radius, timings).
@export var attack_definition: AttackDefinition = null


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if display_name == "":
		errors.append("display_name must not be empty")
	if not is_finite(max_health) or max_health <= 0.0:
		errors.append("max_health must be finite and > 0 (got %f)" % max_health)
	if not is_finite(attack_damage) or attack_damage < 0.0:
		errors.append("attack_damage must be finite and >= 0 (got %f)" % attack_damage)
	if not is_finite(defense) or defense < 0.0:
		errors.append("defense must be finite and >= 0 (got %f)" % defense)
	if not is_finite(movement_speed) or movement_speed <= 0.0:
		errors.append("movement_speed must be finite and > 0 (got %f)" % movement_speed)
	if attack_definition == null:
		errors.append("attack_definition must not be null")
	elif not attack_definition.is_valid():
		for problem in attack_definition.validation_errors():
			errors.append("attack_definition: %s" % problem)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func _to_string() -> String:
	return "PlayerDefinition(%s, hp=%.0f, atk=%.0f, def=%.0f, spd=%.1f)" % [
		id, max_health, attack_damage, defense, movement_speed
	]
