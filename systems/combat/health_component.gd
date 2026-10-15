class_name HealthComponent
extends Node

## Owns the hit points of exactly one actor (ADR-001). This component reports
## state; it never decides consequences: the owning actor reacts to `died`.
##
## Invariants:
## - Mutation points: `apply_damage()` (combat) and `restore()` (a fresh rig on
##   world load, ADR-007); nothing else writes HP.
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

## Defense divisor for the soft mitigation formula (ADR-016): `defense == DEFENSE_SOFTNESS`
## halves incoming damage; defense 0 leaves it untouched.
const DEFENSE_SOFTNESS: float = 100.0

## Optional stat source for damage mitigation (the player rig). Enemies leave it null and
## therefore keep the pre-Sprint-04 behaviour exactly.
var _defense_provider: CharacterStats = null

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


## Sets HP to `value`, clamped to [0, max_health], and emits `health_changed`.
##
## This is the world-load seam (ADR-007): a freshly instantiated rig is restored to
## the persisted life *after* `add_child()`, because `_ready()` starts it at full HP.
## It is never used for damage - `apply_damage()` owns that path.
##
## Death bookkeeping follows the resulting value: a restored 0 HP reads as already
## dead (`died` is NOT emitted here, and damage is rejected as target-dead until a
## positive value is restored), while any positive value re-arms `died` for the next
## lethal hit. Owners still cache the transition themselves (`EnemyBrain` keeps its
## terminal DEAD state), so restoring HP revives a component, not an actor.
##
## Non-finite input can never poison `current_health`: NAN is treated as 0, infinities
## clamp like any other out-of-range value.
func restore(value: float) -> void:
	var safe_value := value if not is_nan(value) else 0.0
	current_health = clampf(safe_value, 0.0, maxf(max_health, 0.0))
	_death_reported = current_health <= 0.0
	health_changed.emit(current_health, max_health)


func is_alive() -> bool:
	return current_health > 0.0


## Binds the stat source used for defense mitigation. Null (the default, and every enemy)
## means "no mitigation".
func set_defense_provider(stats: CharacterStats) -> void:
	_defense_provider = stats


func defense_provider() -> CharacterStats:
	return _defense_provider


## Applies a new maximum (equipment changes, ADR-015): the ceiling moves, the current HP is
## clamped down when needed and is never healed upward, and `died` is not emitted — a lower
## ceiling may leave the actor at 0 HP, which is a clamp, not a new death event.
func set_max_health(value: float) -> void:
	if not is_finite(value):
		push_warning("HealthComponent: ignoring a non-finite max_health (%s)" % value)
		return
	var next: float = maxf(0.0, value)
	if is_equal_approx(next, max_health):
		return
	max_health = next
	current_health = clampf(current_health, 0.0, max_health)
	health_changed.emit(current_health, max_health)


func health_fraction() -> float:
	if max_health <= 0.0:
		return 0.0
	return clampf(current_health / max_health, 0.0, 1.0)


## Only entry point that changes HP. Returns what actually happened.
##
## Damage mitigation lives here, on the *receiver* (ADR-016): when a defense provider is
## set, `effective(defense)` is subtracted from the incoming amount and the result is
## clamped at zero. An actor without stats (every enemy) keeps today's behaviour, so no
## existing combat test changes.
func apply_damage(request: DamageRequest) -> DamageResult:
	if request == null:
		return DamageResult.miss(target_id(), DamageResult.REASON_INVALID_REQUEST)
	if not is_finite(request.amount) or request.amount <= 0.0:
		return DamageResult.miss(target_id(), DamageResult.REASON_INVALID_AMOUNT)
	if not is_alive():
		return DamageResult.miss(target_id(), DamageResult.REASON_TARGET_DEAD)

	var amount := request.amount
	if _defense_provider != null and _defense_provider.is_ready():
		var defense: float = maxf(0.0, _defense_provider.effective(CharacterStats.DEFENSE))
		if defense > 0.0:
			# Soft mitigation (ADR-016): monotonic, deterministic, and never reduces a
			# positive hit to zero. defense == 0 is identical to the previous behaviour.
			amount = amount * (DEFENSE_SOFTNESS / (DEFENSE_SOFTNESS + defense))

	var health_before: float = current_health
	current_health = maxf(0.0, current_health - amount)
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
