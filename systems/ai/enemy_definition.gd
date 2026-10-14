class_name EnemyDefinition
extends Resource

## Static, editor-authored definition of one enemy archetype (ADR-001, ADR-006).
##
## Invariants:
## - Immutable at runtime: gameplay reads these fields and never writes them.
##   Runtime state (FSM state, HP, velocity) lives in `EnemyBrain`,
##   `HealthComponent` and `AttackController`, because a .tres is shared by every
##   instance that loads it.
## - `id` is a stable content id (`enemy.grunt`), never a display name or a path.
## - `lose_radius >= detection_radius`: the gap is the hysteresis band that keeps
##   an enemy on the edge of its detection radius from flickering IDLE/CHASE.
## - `stop_distance <= attack_range`: the enemy stops inside the range at which it
##   can actually start a swing.

## Stable content id, e.g. `enemy.grunt`.
@export var id: StringName = &""

## HP for one full life; copied into the actor's `HealthComponent`.
@export var max_health: float = 100.0

## Horizontal movement speed in metres per second.
@export var move_speed: float = 3.2

## Distance at which an idle enemy notices a target (metres).
@export var detection_radius: float = 12.0

## Distance beyond which a chasing enemy gives up (metres).
@export var lose_radius: float = 16.0

## Distance at which the enemy may start a swing (metres).
@export var attack_range: float = 1.8

## Distance the enemy keeps from its target once close enough (metres).
@export var stop_distance: float = 1.5

## Optional base surface for the greybox body. `EnemyBrain` duplicates it before
## applying any telegraph colour, so a material loaded from here is never mutated.
@export var body_material: StandardMaterial3D = null

## Attack used by this enemy; must be a valid `AttackDefinition`.
@export var attack_definition: AttackDefinition = null

## Optional reward dropped when this archetype dies (ADR-009). A placement can carry
## a different `loot_source_id` to make each drop claimable exactly once; the reward
## payload itself is archetype data. Null means "drops nothing".
@export var reward: RewardDefinition = null


## Returns one message per invalid field; empty means the definition is usable.
##
## Non-finite values (INF/NAN) are rejected as well: they pass ordinary range
## comparisons and would make the enemy effectively unkillable or permanently
## unaware, with no author-facing message.
func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if not is_finite(max_health) or max_health <= 0.0:
		errors.append("max_health must be finite and > 0 (got %f)" % max_health)
	if not is_finite(move_speed) or move_speed < 0.0:
		errors.append("move_speed must be finite and >= 0 (got %f)" % move_speed)
	if not is_finite(detection_radius) or detection_radius <= 0.0:
		errors.append("detection_radius must be finite and > 0 (got %f)" % detection_radius)
	if not is_finite(lose_radius) or lose_radius < detection_radius:
		errors.append(
			"lose_radius must be finite and >= detection_radius (got %f < %f)"
			% [lose_radius, detection_radius]
		)
	if not is_finite(attack_range) or attack_range <= 0.0:
		errors.append("attack_range must be finite and > 0 (got %f)" % attack_range)
	if not is_finite(stop_distance) or stop_distance <= 0.0 or stop_distance > attack_range:
		errors.append(
			"stop_distance must be finite and in (0, attack_range] (got %f, attack_range %f)"
			% [stop_distance, attack_range]
		)
	if attack_definition == null:
		errors.append("attack_definition must not be null")
	elif not attack_definition.is_valid():
		for problem in attack_definition.validation_errors():
			errors.append("attack_definition: %s" % problem)
	if reward != null and not reward.is_valid():
		for problem in reward.validation_errors():
			errors.append("reward: %s" % problem)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func _to_string() -> String:
	return "EnemyDefinition(%s, hp=%.1f, speed=%.2f)" % [id, max_health, move_speed]
