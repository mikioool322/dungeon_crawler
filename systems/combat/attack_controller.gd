class_name AttackController
extends Node

## Owns the attack phases and cooldown of exactly one attacker (ADR-001, ADR-004).
##
## Invariants:
## - One swing at a time. `request_attack()` during a swing returns false and is
##   never queued.
## - Exactly one hit query per swing: on the first tick where the phase is ACTIVE.
## - Range, occlusion and the single-hit-per-target rule are decided there, using
##   live physics state, so a target that already stepped away is a miss.
## - This node never owns HP: it asks `HealthComponent.apply_damage()` on the
##   resolved target and reports the outcome through `attack_resolved`.
## - Timings come from `AttackDefinition` in seconds and are advanced by
##   `_physics_process` (or explicitly by `advance()` in tests). Animation is
##   never the authority.
##
## Scene contract (ADR-005): damageable actors expose a direct child named
## "HealthComponent"; the hit origin is a Node3D in front of the attacker.

signal phase_changed(phase: Phase)

## Emitted once per swing with the primary outcome. A single swing may damage
## several targets; this carries the nearest applied hit, or the closest rejection
## reason when nothing was hit.
signal attack_resolved(result: DamageResult)

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }

## Upper bound of phase transitions processed inside a single `advance()` call.
const MAX_PHASE_TRANSITIONS_PER_ADVANCE: int = 8

## Name of the damage receiver node on a target actor (ADR-005).
## Kept as String because Node lookups require a NodePath-convertible value.
const HEALTH_NODE_NAME: String = "HealthComponent"

## Static attack data; must be a valid definition to allow attacks.
@export var definition: AttackDefinition

## Stable content id of this attacker, e.g. `player` or `enemy.grunt`.
@export var source_id: StringName = &"player"

## Transform used as the attack origin (eye height for the player, weapon tip for
## enemies). Must be a descendant of `owner_body` or be given one explicitly.
@export var hit_origin: Node3D

## Collision object of the attacker; its RID is excluded from hit queries.
@export var owner_body: CollisionObject3D

## Hit query node. Required for hits; without it every swing resolves as a miss.
@export var hit_detector: HitDetector

## When true, `_physics_process` advances the state machine. Tests set this false
## and call `advance(delta)` with exact deltas.
@export var auto_tick: bool = true

var phase: Phase = Phase.IDLE

var _state_time: float = 0.0
var _swing_elapsed: float = 0.0
var _cooldown_remaining: float = 0.0
var _registry: HitRegistry = null
var _last_result: DamageResult = null
var _abort_reason: StringName = &""


func _ready() -> void:
	set_physics_process(auto_tick)


func _physics_process(delta: float) -> void:
	advance(delta)


## Advances the state machine by `delta` seconds. Public for deterministic tests.
##
## Phase transitions carry over: a delta larger than the remaining phase time
## continues into the next phase in the same call, so a frame hitch cannot stall
## the attack (phases are time-based, never animation-based).
func advance(delta: float) -> void:
	var remaining: float = maxf(delta, 0.0)
	var guard: int = 0
	var first_pass: bool = true
	while (remaining > 0.0 or first_pass) and guard < MAX_PHASE_TRANSITIONS_PER_ADVANCE:
		guard += 1
		first_pass = false
		var consumed: float = _advance_phase(remaining)
		remaining = maxf(0.0, remaining - consumed)


## Advances the current phase and returns how much time it consumed before a
## transition happened (or all of `delta` when the phase did not end).
func _advance_phase(delta: float) -> float:
	match phase:
		Phase.IDLE:
			_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
			return delta
		Phase.WINDUP:
			return _advance_timed_phase(delta, _definition_windup(), Phase.ACTIVE)
		Phase.ACTIVE:
			return _advance_timed_phase(delta, _definition_active_window(), Phase.RECOVERY)
		Phase.RECOVERY:
			var consumed := _advance_timed_phase(delta, _definition_recovery(), Phase.IDLE)
			if phase == Phase.IDLE:
				_cooldown_remaining = maxf(0.0, _definition_cooldown() - _swing_elapsed)
			return consumed
	return delta


func _advance_timed_phase(delta: float, duration: float, next: Phase) -> float:
	var remaining_in_phase: float = maxf(0.0, duration - _state_time)
	var consumed: float = minf(delta, remaining_in_phase)
	_state_time += consumed
	_swing_elapsed += consumed
	if _state_time >= duration:
		_enter_phase(next)
		if next == Phase.ACTIVE:
			_resolve_hit()
	return consumed


## True when a new swing can start right now.
func can_attack() -> bool:
	return (
		definition != null
		and definition.is_valid()
		and phase == Phase.IDLE
		and _cooldown_remaining <= 0.0
	)


## Starts one swing. Returns false (without queueing) when busy or on cooldown.
func request_attack() -> bool:
	if not can_attack():
		return false
	_registry = HitRegistry.new()
	_swing_elapsed = 0.0
	_last_result = null
	_enter_phase(Phase.WINDUP)
	return true


## Cancels the current swing (owner decision only, e.g. the attacker died).
func abort(reason: StringName = &"") -> void:
	if phase == Phase.IDLE:
		return
	_registry = null
	_enter_phase(Phase.IDLE)
	_cooldown_remaining = 0.0
	_abort_reason = reason


func abort_reason() -> StringName:
	return _abort_reason


func is_busy() -> bool:
	return phase != Phase.IDLE


func cooldown_remaining() -> float:
	return _cooldown_remaining


## Result of the most recent swing (null before the first one).
func last_result() -> DamageResult:
	return _last_result


func phase_name() -> StringName:
	match phase:
		Phase.IDLE:
			return &"idle"
		Phase.WINDUP:
			return &"windup"
		Phase.ACTIVE:
			return &"active"
		Phase.RECOVERY:
			return &"recovery"
	return &"unknown"


# --- internals ---------------------------------------------------------------

func _enter_phase(next: Phase) -> void:
	if phase == next:
		return
	phase = next
	_state_time = 0.0
	phase_changed.emit(phase)


## The single hit query of this swing. Called once, on the first ACTIVE tick.
func _resolve_hit() -> void:
	var result := _query_and_apply()
	_last_result = result
	attack_resolved.emit(result)


func _query_and_apply() -> DamageResult:
	if hit_detector == null or hit_origin == null:
		return DamageResult.miss(&"", DamageResult.REASON_NO_TARGET)
	var origin: Vector3 = hit_origin.global_transform.origin
	var candidates := hit_detector.query_hits(
		definition, hit_origin.global_transform, _excluded_rids()
	)
	if candidates.is_empty():
		return DamageResult.miss(&"", DamageResult.REASON_NO_TARGET)

	var rejection: StringName = DamageResult.REASON_NO_TARGET
	var forward: Vector3 = -hit_origin.global_transform.basis.z
	var primary: DamageResult = null
	for candidate in candidates:
		if not MeleeRules.within_arc(
			origin, forward, candidate.contact_point, definition.hit_arc_degrees
		):
			rejection = DamageResult.REASON_OUT_OF_ARC
			continue
		if not MeleeRules.within_reach(
			origin, candidate.contact_point, definition.reach, definition.hit_radius
		):
			rejection = DamageResult.REASON_OUT_OF_REACH
			continue
		if candidate.occluded:
			rejection = DamageResult.REASON_OCCLUDED
			continue
		var health := _resolve_health(candidate.collider)
		if health == null:
			continue
		if not health.is_alive():
			rejection = DamageResult.REASON_TARGET_DEAD
			continue
		if not _register_once(candidate.collider):
			rejection = DamageResult.REASON_DUPLICATE
			continue
		var request := DamageRequest.new(
			definition.id,
			source_id,
			definition.damage,
			candidate.contact_point,
			Vector3.UP
		)
		var result := health.apply_damage(request)
		if result.applied and primary == null:
			primary = result
		elif not result.applied:
			rejection = result.miss_reason
	if primary != null:
		return primary
	return DamageResult.miss(&"", rejection)


func _register_once(collider: Node3D) -> bool:
	if _registry == null:
		_registry = HitRegistry.new()
	return _registry.register_once(collider.get_instance_id())


func _resolve_health(collider: Node3D) -> HealthComponent:
	var node := collider.get_node_or_null(HEALTH_NODE_NAME)
	if node is HealthComponent:
		return node as HealthComponent
	return null


func _excluded_rids() -> Array[RID]:
	var body := owner_body
	if body == null:
		body = _find_owner_body()
	if body == null:
		return []
	return [body.get_rid()]


func _find_owner_body() -> CollisionObject3D:
	var node: Node = hit_origin
	while node != null:
		if node is CollisionObject3D:
			return node as CollisionObject3D
		node = node.get_parent()
	return null


func _definition_windup() -> float:
	return definition.windup if definition != null else 0.0


func _definition_active_window() -> float:
	return definition.active_window if definition != null else 0.0


func _definition_recovery() -> float:
	return definition.recovery if definition != null else 0.0


func _definition_cooldown() -> float:
	return definition.cooldown if definition != null else 0.0
