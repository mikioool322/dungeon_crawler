class_name HitCandidate
extends RefCounted

## One physics candidate returned by `HitDetector.query_hits()` (ADR-004).
##
## This is the only combat object that holds a runtime Node reference. It never
## leaves the attack frame: `AttackController` resolves the candidate into a
## `DamageRequest`/`DamageResult` pair and drops it.

## Collided body (its layer decides target vs blocker; see HitDetector).
var collider: Node3D = null

## World-space contact point reported by the physics query.
var contact_point: Vector3 = Vector3.ZERO

## Distance from the attack origin to the contact point (metres).
var distance: float = 0.0

## True when world geometry blocks the line from the attack origin to the contact point.
var occluded: bool = false


func _init(
	p_collider: Node3D = null,
	p_contact_point: Vector3 = Vector3.ZERO,
	p_distance: float = 0.0,
	p_occluded: bool = false
) -> void:
	collider = p_collider
	contact_point = p_contact_point
	distance = p_distance
	occluded = p_occluded


func _to_string() -> String:
	return "HitCandidate(%s, distance=%.2f, occluded=%s)" % [collider, distance, occluded]
