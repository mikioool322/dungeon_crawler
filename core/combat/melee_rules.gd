class_name MeleeRules
extends RefCounted

## Pure range rules for melee attacks (ADR-004).
##
## This class is the authoritative range gate. `HitDetector` gathers physics
## candidates from a slightly wider volume so that "target stepped out of reach
## before the hit frame" still produces an explicit `out_of_reach` miss instead
## of silently finding nothing.
##
## Pure and stateless: no SceneTree, no physics, fully unit-testable.


## Maximum distance at which a contact still counts as a hit.
static func range_limit(reach: float, contact_tolerance: float) -> float:
	return maxf(reach, 0.0) + maxf(contact_tolerance, 0.0)


## Horizontal (XZ) distance between two points.
##
## Sprint 01 measures range horizontally: the physics query reports a target's
## body origin (at its feet), so using the full 3D distance would silently shrink
## every reach by the attacker's eye height. Combat happens on a flat arena;
## vertical separation between floors is out of scope and would need an ADR.
static func horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


## Inclusive hit test: contacting exactly at the limit counts as a hit.
static func within_reach(
	origin: Vector3,
	contact_point: Vector3,
	reach: float,
	contact_tolerance: float
) -> bool:
	return horizontal_distance(origin, contact_point) <= range_limit(reach, contact_tolerance)


## True when the contact point lies inside the frontal attack arc.
##
## `forward` is the attack direction (Godot convention: -Z of the hit origin).
## A full-circle attack passes `half_angle_degrees` >= 180.
static func within_arc(
	origin: Vector3,
	forward: Vector3,
	contact_point: Vector3,
	half_angle_degrees: float
) -> bool:
	var clamped_half_angle: float = clampf(half_angle_degrees, 0.0, 180.0)
	if clamped_half_angle >= 180.0:
		return true
	var to_target: Vector3 = contact_point - origin
	if to_target.length_squared() <= 0.000001:
		return true  # contact on the origin itself: no direction to test
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	var flat_to_target := Vector3(to_target.x, 0.0, to_target.z)
	if flat_forward.length_squared() <= 0.000001 or flat_to_target.length_squared() <= 0.000001:
		return true  # degenerate horizontal direction: accept, range still applies
	return rad_to_deg(flat_forward.normalized().angle_to(flat_to_target.normalized())) <= clamped_half_angle
