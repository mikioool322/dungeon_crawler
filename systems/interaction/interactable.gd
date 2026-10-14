class_name Interactable
extends Area3D

## An object the player can walk up to and use with the `interact` action
## (ADR-008). The base owns the guards, the one-shot bookkeeping and the single
## `interaction_completed` emission; subclasses only implement
## `_perform_interact()` and stay domain-free above it.
##
## Invariants:
## - `interact()` is final: it checks `can_interact()`, refuses a re-entrant call,
##   marks a used one-shot, and emits `interaction_completed` at most once per
##   successful action. Subclasses must not override it.
## - Synchronous: `interact()` never awaits, never defers and returns its result
##   directly, so the caller always knows the outcome in the same frame.
## - `_perform_interact()` returning `null` is treated as `unavailable` instead of
##   crashing the caller.
## - A *failed* action neither marks the interactable used nor emits
##   `interaction_completed`; a reusable (`one_shot == false`) interactable is
##   never blocked by `mark_used()`.
## - The base knows nothing about loot, travel, save or presentation. Services are
##   injected per subclass by the world host; `bind_loot()` exists only as the
##   documented, inert injection hook for the loot subclasses (ADR-008).
##
## Scene contract (ADR-005 addendum, enforced in `_ready()`): an interactable is
## an `Area3D` on `PhysicsLayers.INTERACTABLE` only, with a `collision_mask` of 0
## and `monitoring = false`. It is never a damage receiver, never a blocker and
## never part of a movement mask; a script or scene cannot accidentally widen that
## because the values are re-applied when the node enters the tree.
##
## Node contract: the collision shape is an ordinary `CollisionShape3D` child (the
## base does not care how many), and (unlike a damageable actor) the node name is
## irrelevant - `InteractionController` finds interactables by physics query, not
## by name.

## Emitted exactly once per successful action, after the interactable is
## consistent (a used one-shot is already marked when this fires).
signal interaction_completed(interactor: Node3D, result: InteractionResult)

## Player-facing prompt text; the controller only publishes it, the HUD draws it.
@export var prompt: String = "Interact"

## When false the interactable cannot be used (and is never a focus).
@export var enabled: bool = true

## When true, the first successful action marks the interactable used, after which
## `can_interact()` is false forever.
@export var one_shot: bool = false

var _used: bool = false

## Re-entrancy guard: true while `_perform_interact()` is running, so a subclass or
## a signal handler that calls `interact()` again cannot run a second action.
var _in_flight: bool = false


func _ready() -> void:
	# ADR-005 addendum: query-only area on layer 5. Re-applied on every tree entry
	# so an authored scene cannot turn an interactable into a blocker or a target.
	collision_layer = PhysicsLayers.INTERACTABLE
	collision_mask = 0
	monitoring = false


## True when the interactable may be used right now.
func can_interact() -> bool:
	if not enabled:
		return false
	if one_shot and _used:
		return false
	return true


## True once a successful one-shot action marked this interactable used.
func is_used() -> bool:
	return _used


## Records the interactable as used. Irrelevant while `one_shot` is false.
func mark_used() -> void:
	_used = true


## Final, synchronous entry point. Guards, performs once, bookkeeps and emits.
##
## Returns `unavailable` when the interactable is disabled, already used or
## currently performing; otherwise it returns whatever `_perform_interact()`
## produced (a `null` return becomes `unavailable`). Only a successful result
## marks a one-shot used and emits `interaction_completed`.
func interact(interactor: Node3D) -> InteractionResult:
	if _in_flight:
		return InteractionResult.unavailable()
	if not can_interact():
		return InteractionResult.unavailable()

	_in_flight = true
	var result: InteractionResult = _perform_interact(interactor)
	_in_flight = false

	if result == null:
		result = InteractionResult.unavailable()
	if not result.succeeded():
		return result

	if one_shot:
		mark_used()
	interaction_completed.emit(interactor, result)
	return result


## The one virtual a subclass implements. The default refuses: an interactable
## that forgot its behaviour must not look like it worked.
func _perform_interact(_interactor: Node3D) -> InteractionResult:
	return InteractionResult.unavailable()


## Inert injection hook for the loot subclasses (ADR-008): the world host calls it
## with `(reward, LootGrant.key_for(world_id, loot_source_id), LootService)`, so
## the world knows about loot while this base does not. Only
## `PickupInteractable`/`ChestInteractable` override it.
func bind_loot(_reward: RewardDefinition, _grant_key: StringName, _loot: LootService) -> void:
	pass


func _to_string() -> String:
	return "Interactable(%s, enabled=%s, one_shot=%s, used=%s)" % [
		name, enabled, one_shot, _used
	]
