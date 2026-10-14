class_name HitDetector
extends Node3D

## Gathers physics candidates for one hit frame (ADR-004).
##
## Responsibilities and invariants:
## - Stateless between swings: it never remembers targets and never applies damage.
## - One call per swing, on the first ACTIVE tick, made by `AttackController`.
## - Bodies on `target_mask` are damage candidates; bodies on `blocker_mask` block
##   the line of sight. A collider on both masks counts as a blocker.
## - The probe sphere is deliberately wider than the rule-based range gate
##   (`MeleeRules`): candidates that already stepped just beyond reach are still
##   reported so the swing can resolve to an explicit `out_of_reach` miss.
##
## Node that must exist before use: `HitDetector` has to be inside the scene tree
## (it uses the 3D world's direct space state).

## Extra probe radius beyond `reach + hit_radius`, in metres.
@export var probe_slack: float = 1.0

## Physics layer(s) that can be damaged.
@export var target_mask: int = PhysicsLayers.ENEMY_BODY

## Physics layer(s) that block attacks (walls, pillars, floors).
@export var blocker_mask: int = PhysicsLayers.WORLD

## Upper bound of reported candidates per query.
@export var max_candidates: int = 8

## Height above the reported contact point at which the line of sight is tested,
## in metres. The physics query reports a body's origin (feet), so aiming the
## occlusion ray at chest height keeps low cover from blocking a chest-height swing
## while tall geometry still blocks it.
@export var occlusion_probe_height: float = 1.0

## Distance tolerance when deciding whether a blocker is in front of a candidate.
const OCCLUSION_EPSILON: float = 0.05


## Returns damage candidates sorted by distance (nearest first).
func query_hits(
	definition: AttackDefinition,
	origin: Transform3D,
	exclude_rids: Array[RID] = []
) -> Array[HitCandidate]:
	var candidates: Array[HitCandidate] = []
	if definition == null:
		return candidates
	var space := get_world_3d().direct_space_state
	if space == null:
		return candidates

	var shape := SphereShape3D.new()
	shape.radius = MeleeRules.range_limit(definition.reach, definition.hit_radius) + maxf(probe_slack, 0.0)

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = origin
	params.collision_mask = target_mask | blocker_mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = exclude_rids

	var hits := space.intersect_shape(params, max_candidates)
	var nearest_by_collider: Dictionary = {}
	for hit: Dictionary in hits:
		var collider := hit.get("collider") as Node3D
		if collider == null:
			continue
		if collider.collision_layer & blocker_mask:
			continue  # world geometry is a blocker, not a damage candidate
		if not (collider.collision_layer & target_mask):
			continue
		var contact_point: Vector3 = hit.get("point", Vector3.ZERO)
		if contact_point.is_zero_approx():
			contact_point = collider.global_position
		var distance: float = origin.origin.distance_to(contact_point)
		var collider_id: int = hit.get("collider_id", collider.get_instance_id())
		var previous: Variant = nearest_by_collider.get(collider_id)
		if previous != null and (previous as HitCandidate).distance <= distance:
			continue
		nearest_by_collider[collider_id] = HitCandidate.new(collider, contact_point, distance, false)

	for value: Variant in nearest_by_collider.values():
		var candidate := value as HitCandidate
		var probe_point: Vector3 = candidate.contact_point + Vector3.UP * occlusion_probe_height
		candidate.occluded = _is_occluded(space, origin.origin, probe_point, exclude_rids)
		candidates.append(candidate)
	candidates.sort_custom(_nearest_first)
	return candidates


func _nearest_first(a: HitCandidate, b: HitCandidate) -> bool:
	return a.distance < b.distance


func _is_occluded(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	exclude_rids: Array[RID]
) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, blocker_mask, exclude_rids)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = false
	var result := space.intersect_ray(query)
	if result.is_empty():
		return false
	var blocker_position: Vector3 = result.get("position", from)
	var blocker_distance: float = from.distance_to(blocker_position)
	var target_distance: float = from.distance_to(to)
	return blocker_distance < target_distance - OCCLUSION_EPSILON
