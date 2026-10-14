class_name ChestInteractable
extends Interactable

## A chest: same grant path as a pickup, but the chest itself stays in the world
## (ADR-008, ADR-009). Opening it once marks it used; a re-open is refused by the
## base's one-shot guard.
##
## Invariants:
## - `one_shot` defaults to true (set in `_init()`, so an authored `false` still
##   wins): a chest is opened once and then reads as empty. It is *not* freed -
##   removing the geometry would delete level furniture, not loot.
## - A grant whose key was already claimed (a fresh chest after re-entering the
##   world, or a restored save) reports `ok("already_collected")`. That is a
##   *success*: the player opened a chest that has nothing left, and
##   `LootService` guarantees no second award.
## - The grant logic is deliberately duplicated from `PickupInteractable` instead
##   of inheriting from it: the two share the grant call but differ in the whole
##   lifecycle (consumed vs. permanent), and making one a special case of the other
##   would encode "a chest is a pickup that survives" in the type system.
## - Same binding contract as the pickup: services arrive through `bind_loot()`
##   from the world host, an unbound chest refuses with `not_configured`.

## Reward granted by this chest; may also be authored in the scene.
@export var reward: RewardDefinition = null

## Stable per-placement loot source id (`chest.a`). Informational here: the host
## computes `grant_key` from it and the world id.
@export var loot_source_id: StringName = &""

## Idempotency key handed to `LootService`, set by `bind_loot()`.
var grant_key: StringName = &""

var _loot_service: LootService = null


func _init() -> void:
	one_shot = true


## Wires the loot path. Called by the world host with
## `(reward, LootGrant.key_for(world_id, loot_source_id), loot_service)`.
func bind_loot(_reward: RewardDefinition, _grant_key: StringName, _loot: LootService) -> void:
	reward = _reward
	grant_key = _grant_key
	_loot_service = _loot


## True when a reward and a loot service are wired.
func is_bound() -> bool:
	return _loot_service != null and reward != null


func _perform_interact(_interactor: Node3D) -> InteractionResult:
	if not is_bound():
		return InteractionResult.rejected(
			&"not_configured",
			"Nothing is wired to this chest."
		)

	var grant := LootGrant.from_reward(grant_key, reward)
	var code := _loot_service.grant(grant)
	if code == LootService.CODE_GRANTED:
		return InteractionResult.ok("granted")
	if code == LootService.CODE_DUPLICATE:
		return InteractionResult.ok("already_collected")
	return InteractionResult.rejected(code, "This chest cannot be opened.")


func _to_string() -> String:
	return "ChestInteractable(%s, reward=%s, key=%s, bound=%s)" % [
		name, reward, grant_key, is_bound()
	]
