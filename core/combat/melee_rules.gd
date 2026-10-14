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


## Inclusive hit test: contacting exactly at the limit counts as a hit.
static func within_reach(
	origin: Vector3,
	contact_point: Vector3,
	reach: float,
	contact_tolerance: float
) -> bool:
	return origin.distance_to(contact_point) <= range_limit(reach, contact_tolerance)
