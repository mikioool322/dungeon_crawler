class_name PickupInteractable
extends Interactable

## A collectable drop: walking up to it and pressing `interact` applies its reward
## through `LootService` and removes it from the world (ADR-008, ADR-009).
##
## Invariants:
## - The base interaction system knows nothing about loot: the loot service, the
##   reward and the idempotency key arrive through `bind_loot()` from the world
##   host. An unbound pickup refuses with `not_configured` and stays in the world.
## - `LootService.grant()` is the only writer of gold/inventory/claimed keys, and
##   it validates the grant before mutating. An invalid or unknown item reward is
##   therefore refused with the loot code passed through verbatim (`invalid`,
##   `unknown_item`) instead of a second set of reward rules living here.
## - `grant_key` is the stable idempotency key built by
##   `LootGrant.key_for(world_id, loot_source_id)` - never a node name. A key that
##   was already claimed in this run (or restored from a save) reports
##   `ok("already_collected")`: succeeding is correct, because the drop is either a
##   stale duplicate or an already-collected key, and either way it must not award
##   anything twice.
## - The pickup is consumed (`queue_free()`) after a `granted` *or* `duplicate`
##   result; any other code leaves it in the world so the player can retry once the
##   content is fixed. `queue_free()` is deferred by the engine, so the base's
##   `interaction_completed` emission (which happens right after this returns)
##   still sees a valid node; the node disappears at the end of the frame.
## - Rewards are never stored back into `RewardDefinition`; the grant is a copy.

## Reward granted by this drop; may also be authored in the scene.
@export var reward: RewardDefinition = null

## Stable per-placement loot source id (`chest.a`, `enemy.a`, ...). Informational
## here: the host computes `grant_key` from it and the world id.
@export var loot_source_id: StringName = &""

## Idempotency key handed to `LootService`, set by `bind_loot()`.
var grant_key: StringName = &""

var _loot_service: LootService = null


## Wires the loot path. Called by the world host with
## `(reward, LootGrant.key_for(world_id, loot_source_id), loot_service)`.
##
## The parameters are underscored (like the inert base hook) because `reward` and
## `grant_key` are also member names; calls are positional.
func bind_loot(_reward: RewardDefinition, _grant_key: StringName, _loot: LootService) -> void:
	reward = _reward
	grant_key = _grant_key
	_loot_service = _loot


## True when a reward and a loot service are wired. The grant key is validated by
## `LootService` itself (an empty key yields `invalid`).
func is_bound() -> bool:
	return _loot_service != null and reward != null


func _perform_interact(_interactor: Node3D) -> InteractionResult:
	if not is_bound():
		return InteractionResult.rejected(
			&"not_configured",
			"Nothing is wired to this drop."
		)

	var grant := LootGrant.from_reward(grant_key, reward)
	var code := _loot_service.grant(grant)
	if code == LootService.CODE_GRANTED:
		queue_free()
		return InteractionResult.ok("granted")
	if code == LootService.CODE_DUPLICATE:
		queue_free()
		return InteractionResult.ok("already_collected")
	return InteractionResult.rejected(code, "This reward cannot be collected.")


func _to_string() -> String:
	return "PickupInteractable(%s, reward=%s, key=%s, bound=%s)" % [
		name, reward, grant_key, is_bound()
	]
