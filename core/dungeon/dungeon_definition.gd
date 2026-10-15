class_name DungeonDefinition
extends Resource

## Static definition of one dungeon (ADR-012). Immutable at runtime.
##
## Invariants:
## - References the world through a stable `world_id` and never duplicates
##   `WorldDefinition` (scene, spawn markers and geometry stay world content).
## - `dungeon_id`, `world_id`, `entry_spawn_id` and `completion_objective` are stable
##   content ids, never display names, node names or asset paths.
## - Rewards are referenced by id and resolved through `ContentRegistry`; a definition
##   never holds an inventory or a bag.
## - `repeatable = false` means "cannot be entered again once completed"; the generic
##   progression code reads the flag, it never special-cases a dungeon id.
##
## The registry adds the cross-reference validation that needs the whole manifest
## (unknown world, unknown prerequisite, unknown unlock target, unknown reward,
## unreachable dungeon).

## Stable dungeon id, e.g. `dungeon.proto01`.
@export var dungeon_id: StringName = &""

## Name shown in the hub list.
@export var display_name: String = ""

## World that contains this dungeon; must be listed in the manifest.
@export var world_id: StringName = &""

## Spawn marker inside that world where the run starts.
@export var entry_spawn_id: StringName = &""

## Dungeons that must be completed before this one can be entered. Empty means
## "available from the start of a new game".
@export var prerequisites: Array[StringName] = []

## Dungeons unlocked the first time this one is completed.
@export var first_clear_unlocks: Array[StringName] = []

## When false, the dungeon cannot be entered again after its first completion.
@export var repeatable: bool = true

## Objective id that must be reported during an active run to complete this dungeon.
@export var completion_objective: StringName = &""

## Reward granted on every completion (per-run scope).
@export var regular_reward_id: StringName = &""

## Reward granted exactly once, on the first completion (persistent scope).
@export var first_clear_reward_id: StringName = &""


## One message per invalid field; empty means the definition is usable on its own.
## Cross-references are validated by `ContentRegistry.build()`.
func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if dungeon_id == &"":
		errors.append("dungeon_id must not be empty")
	if display_name == "":
		errors.append("display_name must not be empty")
	if world_id == &"":
		errors.append("world_id must not be empty")
	if entry_spawn_id == &"":
		errors.append("entry_spawn_id must not be empty")
	if completion_objective == &"":
		errors.append("completion_objective must not be empty")
	_append_id_list_errors(errors, "prerequisites", prerequisites)
	_append_id_list_errors(errors, "first_clear_unlocks", first_clear_unlocks)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


## True when the dungeon needs no earlier completion (a new-game dungeon).
func is_start_dungeon() -> bool:
	return prerequisites.is_empty()


func _append_id_list_errors(errors: PackedStringArray, field: String, ids: Array[StringName]) -> void:
	var seen: Dictionary = {}
	for id in ids:
		if id == &"":
			errors.append("%s must not contain an empty id" % field)
			continue
		if id == dungeon_id:
			errors.append("%s must not reference this dungeon itself (%s)" % [field, id])
			continue
		if seen.has(id):
			errors.append("%s repeats '%s'" % [field, id])
			continue
		seen[id] = true


func _to_string() -> String:
	return "DungeonDefinition(%s -> %s@%s)" % [dungeon_id, world_id, entry_spawn_id]
