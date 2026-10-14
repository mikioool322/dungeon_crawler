class_name DamageRequest
extends RefCounted

## Value object describing one damage application attempt (ADR-004).
##
## Invariants:
## - Runtime-only: never serialized, never persisted.
## - Carries stable StringName content ids, never Node references, so the domain
##   layer does not depend on the scene tree.
## - Treated as read-only after construction.

## Stable content id of the attack that caused this request (e.g. `attack.player.basic`).
var attack_id: StringName

## Stable content id of the attacker (e.g. `player`, `enemy.grunt`).
var source_id: StringName

## Requested damage before clamping to the target's remaining HP.
var amount: float

## World-space point where the attack connected.
var hit_position: Vector3

## World-space surface normal at the contact point.
var hit_normal: Vector3


func _init(
	p_attack_id: StringName = &"",
	p_source_id: StringName = &"",
	p_amount: float = 0.0,
	p_hit_position: Vector3 = Vector3.ZERO,
	p_hit_normal: Vector3 = Vector3.ZERO
) -> void:
	attack_id = p_attack_id
	source_id = p_source_id
	amount = p_amount
	hit_position = p_hit_position
	hit_normal = p_hit_normal


func _to_string() -> String:
	return "DamageRequest(attack=%s source=%s amount=%.2f)" % [attack_id, source_id, amount]
