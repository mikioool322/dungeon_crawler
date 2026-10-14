class_name AttackDefinition
extends Resource

## Static, editor-authored definition of one melee attack (ADR-004).
##
## Invariants:
## - Immutable at runtime: gameplay code reads these fields and never writes them.
##   Runtime state (phase, cooldown, remaining HP) lives in components, never here,
##   because a .tres resource is shared between all instances that load it.
## - All times are in seconds and are advanced by `_physics_process`, never by
##   animation playback.
## - `id` is a stable content id, not a display name or file path.

## Stable content id, e.g. `attack.player.basic`.
@export var id: StringName = &""

## Damage applied on a valid hit.
@export var damage: float = 10.0

## Maximum distance from the attack origin at which a contact counts as a hit (metres).
@export var reach: float = 2.0

## Radius of the physics probe sphere used to gather candidates (metres).
@export var hit_radius: float = 0.3

## Half-angle of the frontal attack arc, in degrees. Targets outside it are missed
## with reason `out_of_arc`; 180 means "any direction around the attacker".
@export var hit_arc_degrees: float = 60.0

## Time before the hit frame; the telegraph window.
@export var windup: float = 0.35

## Duration of the active window. Exactly one hit query happens on the first tick.
@export var active_window: float = 0.15

## Time after the active window before the attacker may act again.
@export var recovery: float = 0.45

## Minimum time between the start of two swings, counted from swing start.
@export var cooldown: float = 0.6


## Returns one message per invalid field; empty means the definition is usable.
func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if damage < 0.0:
		errors.append("damage must be >= 0 (got %f)" % damage)
	if reach <= 0.0:
		errors.append("reach must be > 0 (got %f)" % reach)
	if hit_radius <= 0.0:
		errors.append("hit_radius must be > 0 (got %f)" % hit_radius)
	if hit_arc_degrees <= 0.0 or hit_arc_degrees > 180.0:
		errors.append("hit_arc_degrees must be in (0, 180] (got %f)" % hit_arc_degrees)
	if windup < 0.0:
		errors.append("windup must be >= 0 (got %f)" % windup)
	if active_window <= 0.0:
		errors.append("active_window must be > 0 (got %f)" % active_window)
	if recovery < 0.0:
		errors.append("recovery must be >= 0 (got %f)" % recovery)
	if cooldown < 0.0:
		errors.append("cooldown must be >= 0 (got %f)" % cooldown)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


## Total time from swing start to the end of recovery.
func swing_duration() -> float:
	return windup + active_window + recovery


func _to_string() -> String:
	return "AttackDefinition(%s, damage=%.1f, reach=%.2f)" % [id, damage, reach]
