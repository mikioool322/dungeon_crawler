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

## Name of the damage receiver node on a target actor (ADR-005). The lookup and
## the name live with the component itself; scenes that break the contract are
## reported by `_query_and_apply()` instead of failing silently.

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
	_abort_reason = &""
	_swing_profile = _active_profile()
	_swing_damage = _effective_damage(_swing_profile)
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


## Optional stat source (the player rig): when set and ready, the swing damage comes from
## `effective(attack_damage)` instead of the profile (ADR-016).
var _stats: CharacterStats = null

## Optional weapon profile (reach/arc/timings) that overrides `definition` while equipped.
var _attack_profile: AttackDefinition = null

## The swing's pinned profile and damage, taken at `request_attack()`: a weapon change in
## the middle of a swing cannot alter reach, timings, the hit-frame damage or the cooldown.
var _swing_profile: AttackDefinition = null
var _swing_damage: float = 0.0


## Binds the stat source; null keeps the profile's own damage (enemies).
func set_stats(stats: CharacterStats) -> void:
	_stats = stats


## Binds the equipped weapon's attack profile; null falls back to `definition`.
func set_attack_profile(profile: AttackDefinition) -> void:
	_attack_profile = profile


func attack_profile() -> AttackDefinition:
	return _active_profile()
func _resolve_hit() -> void:
	var result := _query_and_apply()
	_last_result = result
	attack_resolved.emit(result)


func _query_and_apply() -> DamageResult:
	if hit_detector == null or hit_origin == null:
		return DamageResult.miss(&"", DamageResult.REASON_NO_TARGET)
	# The swing's pinned profile and damage (ADR-016): resolution never re-reads the
	# equipped weapon, so a mid-swing change cannot alter this swing.
	var profile := _swing_profile if _swing_profile != null else definition
	if profile == null:
		return DamageResult.miss(&"", DamageResult.REASON_NO_TARGET)
	var origin: Vector3 = hit_origin.global_transform.origin
	var candidates := hit_detector.query_hits(
		profile, hit_origin.global_transform, _excluded_rids()
	)
	if candidates.is_empty():
		return DamageResult.miss(&"", DamageResult.REASON_NO_TARGET)

	var rejection: StringName = &""
	var forward: Vector3 = -hit_origin.global_transform.basis.z
	var primary: DamageResult = null
	for candidate in candidates:
		if not MeleeRules.within_arc(
			origin, forward, candidate.contact_point, profile.hit_arc_degrees
		):
			rejection = _first_rejection(rejection, DamageResult.REASON_OUT_OF_ARC)
			continue
		if not MeleeRules.within_reach(
			origin, candidate.contact_point, profile.reach, profile.hit_radius
		):
			rejection = _first_rejection(rejection, DamageResult.REASON_OUT_OF_REACH)
			continue
		if candidate.occluded:
			rejection = _first_rejection(rejection, DamageResult.REASON_OCCLUDED)
			continue
		var health := HealthComponent.find_on(candidate.collider)
		if health == null:
			# A collider inside the gate without a HealthComponent breaks the ADR-005
			# scene contract; report it instead of silently resolving as "no target".
			push_warning(
				"[AttackController] %s hit a target without a %s child: %s"
				% [source_id, HealthComponent.NODE_NAME, candidate.collider.name]
			)
			continue
		if not health.is_alive():
			rejection = _first_rejection(rejection, DamageResult.REASON_TARGET_DEAD)
			continue
		if not _register_once(candidate.collider):
			rejection = _first_rejection(rejection, DamageResult.REASON_DUPLICATE)
			continue
		var request := DamageRequest.new(
			profile.id,
			source_id,
			_swing_damage,
			candidate.contact_point,
			Vector3.UP
		)
		var result := health.apply_damage(request)
		if result.applied and primary == null:
			primary = result
		elif not result.applied:
			rejection = _first_rejection(rejection, result.miss_reason)
	if primary != null:
		return primary
	return DamageResult.miss(&"", rejection if rejection != &"" else DamageResult.REASON_NO_TARGET)


## Keeps the rejection of the nearest candidate; the first rejection wins because
## `HitDetector` reports candidates nearest-first and ADR-004 documents
## `attack_resolved` as carrying the *closest* rejection reason.
func _first_rejection(current: StringName, candidate_reason: StringName) -> StringName:
	return current if current != &"" else candidate_reason


func _register_once(collider: Node3D) -> bool:
	if _registry == null:
		_registry = HitRegistry.new()
	return _registry.register_once(collider.get_instance_id())


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


## The profile a new swing would use: the equipped weapon's, else the base definition.
## Only a valid profile can be pinned, so a broken weapon resource cannot break combat.
func _active_profile() -> AttackDefinition:
	if _attack_profile != null and _attack_profile.is_valid():
		return _attack_profile
	return definition


## Damage for one swing: the stats owner's effective attack damage, else the profile's own
## (ADR-016). Always finite and >= 0.
func _effective_damage(profile: AttackDefinition) -> float:
	var base: float = profile.damage if profile != null else 0.0
	if _stats == null or not _stats.is_ready():
		return maxf(0.0, base)
	var value: float = _stats.effective(CharacterStats.ATTACK_DAMAGE)
	if not is_finite(value):
		return maxf(0.0, base)
	return maxf(0.0, value)


func _definition_windup() -> float:
	var profile := _swing_profile if _swing_profile != null else definition
	return profile.windup if profile != null else 0.0


func _definition_active_window() -> float:
	var profile := _swing_profile if _swing_profile != null else definition
	return profile.active_window if profile != null else 0.0


func _definition_recovery() -> float:
	var profile := _swing_profile if _swing_profile != null else definition
	return profile.recovery if profile != null else 0.0


func _definition_cooldown() -> float:
	var profile := _swing_profile if _swing_profile != null else definition
	return profile.cooldown if profile != null else 0.0
