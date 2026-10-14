class_name HealthComponent
extends Node

## Owns the hit points of exactly one actor (ADR-001). This component reports
## state; it never decides consequences: the owning actor reacts to `died`.
##
## Invariants:
## - Single mutation point: `apply_damage()` is the only way HP changes.
## - HP is clamped to [0, max_health].
## - `died` is emitted exactly once per life; damage after death is rejected with
##   `DamageResult.REASON_TARGET_DEAD` and never re-emits.
## - `reset()` restores a full life (used by scene tests and restarts).
##
## Scene contract (ADR-005): a damageable actor exposes this component as a
## direct child node named "HealthComponent"; hit resolution relies on that name.
## The name and the lookup live here, with the component that the contract is about.

signal health_changed(current: float, maximum: float)
signal damaged(request: DamageRequest, result: DamageResult)
signal died(request: DamageRequest)

## Required child node name for a damageable actor (ADR-005).
const NODE_NAME: String = "HealthComponent"


## Finds the damage receiver of an actor, or null when the scene breaks the
## ADR-005 contract. This is the single place that owns the node lookup.
static func find_on(actor: Node) -> HealthComponent:
	if actor == null:
		return null
	var node := actor.get_node_or_null(NODE_NAME)
	if node is HealthComponent:
		return node as HealthComponent
	return null

## Maximum HP for one full life.
@export var max_health: float = 100.0

## Stable content id of this actor (e.g. `player`, `enemy.grunt`). Must not be a
## display name or an asset path. Falls back to the parent node name when empty.
@export var actor_id: StringName = &""

var current_health: float = 0.0

var _death_reported: bool = false


func _init() -> void:
	current_health = maxf(max_health, 0.0)


func _ready() -> void:
	reset()


## Restores a full life and allows `died` to be emitted again.
##
## Intended for scene restarts (a fresh arena) and tests. In-place revive is NOT
## supported: owners cache the transition (for example `EnemyBrain` keeps the FSM
## in its terminal DEAD state), so a revived actor stays inert until it is
## recreated. A revive feature needs its own decision record.
func reset() -> void:
	current_health = maxf(max_health, 0.0)
	_death_reported = false
	health_changed.emit(current_health, max_health)


func is_alive() -> bool:
	return current_health > 0.0


func health_fraction() -> float:
	if max_health <= 0.0:
		return 0.0
	return clampf(current_health / max_health, 0.0, 1.0)


## Only entry point that changes HP. Returns what actually happened.
func apply_damage(request: DamageRequest) -> DamageResult:
	if request == null:
		return DamageResult.miss(target_id(), DamageResult.REASON_INVALID_REQUEST)
	if not is_finite(request.amount) or request.amount <= 0.0:
		return DamageResult.miss(target_id(), DamageResult.REASON_INVALID_AMOUNT)
	if not is_alive():
		return DamageResult.miss(target_id(), DamageResult.REASON_TARGET_DEAD)

	var health_before: float = current_health
	current_health = maxf(0.0, current_health - request.amount)
	var damage_dealt: float = health_before - current_health
	var died_now: bool = current_health <= 0.0

	health_changed.emit(current_health, max_health)
	var result := DamageResult.applied_hit(target_id(), damage_dealt, died_now)
	damaged.emit(request, result)
	if died_now and not _death_reported:
		_death_reported = true
		died.emit(request)
	return result


## Stable content id used in DamageResult / logs.
func target_id() -> StringName:
	if actor_id != &"":
		return actor_id
	var parent := get_parent()
	if parent != null:
		return StringName(parent.name)
	return &"unnamed"
