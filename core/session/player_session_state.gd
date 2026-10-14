class_name PlayerSessionState
extends RefCounted

## Durable run state owned by `GameSession` (ADR-007, ADR-009).
##
## Invariants:
## - Never references a Node, PackedScene or Callable: every script variable is a
##   primitive, a `StringName`, a `Dictionary` of `StringName -> true`, or the
##   `Inventory` reference. The save path may therefore build JSON from this object
##   without a node-safety guard.
## - Writers: `GameSession` owns health and location, `LootService` owns gold, the
##   inventory and the claimed keys. Nothing else mutates these fields.
## - `claimed_reward_keys` is the persisted loot-idempotency record; its keys are
##   `LootGrant.key_for(world_id, loot_source_id)` values.
## - `spawn_id == &""` means "the world's default spawn".

## Current HP, copied from/into the live player rig by `GameSession`.
var health: float = 100.0

## Currency, owned by the session and never an inventory item.
var gold: int = 0

## The run's bag; `LootService` is its only writer.
var inventory: Inventory = Inventory.new()

## Stable content id of the world the run is in, e.g. `world.hub`.
var world_id: StringName = &"world.hub"

## Requested spawn id inside `world_id`; empty means the world's default spawn.
var spawn_id: StringName = &""

## Claimed loot keys: `StringName -> true`.
var claimed_reward_keys: Dictionary = {}


## Rebuilds the documented new-game defaults.
##
## Resets health, gold, the bag, the claimed keys and the location: a new game must
## not inherit the previous run's progress or its world. `default_health` is clamped
## to >= 0 and a non-finite value falls back to 0.0 (the caller applies the rig's
## real maximum, see `GameSession.apply_to_player`).
func reset_to_new_game(default_health: float) -> void:
	health = maxf(default_health, 0.0) if is_finite(default_health) else 0.0
	gold = 0
	if inventory == null:
		inventory = Inventory.new()
	else:
		inventory.clear()
	claimed_reward_keys = {}
	world_id = &"world.hub"
	spawn_id = &""


## Records `key` as claimed. Returns false when it was already claimed.
##
## An empty key is never recorded: it is not a valid loot key (see
## `LootGrant.key_for`) and recording it would silently block an unrelated grant.
func claim(key: StringName) -> bool:
	if key == &"":
		return false
	if claimed_reward_keys.has(key):
		return false
	claimed_reward_keys[key] = true
	return true


func is_claimed(key: StringName) -> bool:
	return claimed_reward_keys.has(key)


func _to_string() -> String:
	return "PlayerSessionState(hp=%.1f, gold=%d, %s, claimed=%d)" % [
		health, gold, inventory, claimed_reward_keys.size()
	]
