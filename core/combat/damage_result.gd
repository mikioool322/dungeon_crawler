class_name DamageResult
extends RefCounted

## Value object describing what actually happened to one target (ADR-004).
##
## Invariants:
## - Runtime-only: never serialized, never persisted.
## - `miss_reason` comes from the fixed vocabulary below; an applied hit uses
##   REASON_NONE, so callers can branch on `applied` alone.

const REASON_NONE: StringName = &""
const REASON_OUT_OF_ARC: StringName = &"out_of_arc"
const REASON_OUT_OF_REACH: StringName = &"out_of_reach"
const REASON_OCCLUDED: StringName = &"occluded"
const REASON_TARGET_DEAD: StringName = &"target_dead"
const REASON_DUPLICATE: StringName = &"duplicate"
const REASON_INVALID_AMOUNT: StringName = &"invalid_amount"
const REASON_INVALID_REQUEST: StringName = &"invalid_request"
const REASON_NO_TARGET: StringName = &"no_target"

var applied: bool = false
var damage_dealt: float = 0.0
var target_id: StringName = &""
var target_died: bool = false
var miss_reason: StringName = REASON_NONE


static func applied_hit(
	p_target_id: StringName,
	p_damage_dealt: float,
	p_target_died: bool
) -> DamageResult:
	var result := DamageResult.new()
	result.applied = true
	result.damage_dealt = p_damage_dealt
	result.target_id = p_target_id
	result.target_died = p_target_died
	result.miss_reason = REASON_NONE
	return result


static func miss(p_target_id: StringName, p_reason: StringName) -> DamageResult:
	var result := DamageResult.new()
	result.applied = false
	result.damage_dealt = 0.0
	result.target_id = p_target_id
	result.target_died = false
	result.miss_reason = p_reason if p_reason != REASON_NONE else REASON_NO_TARGET
	return result


func _to_string() -> String:
	if applied:
		return "DamageResult(HIT %s for %.1f, died=%s)" % [target_id, damage_dealt, target_died]
	return "DamageResult(MISS %s: %s)" % [target_id, miss_reason]
