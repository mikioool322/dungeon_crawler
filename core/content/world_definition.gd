class_name WorldDefinition
extends Resource

## Static, editor-authored definition of one loadable world (ADR-007, ADR-011).
##
## Invariants:
## - Immutable at runtime: `WorldRouter` reads these fields and never writes them.
## - Coordinates never live here. Positions belong to `SpawnMarker` nodes inside the
##   scene; the definition only names the scene and the id of the default marker.
## - `id` and `default_spawn_id` are stable content ids (`world.hub`,
##   `spawn.hub.start`), never node names, display names or asset paths.
## - `display_name` is presentation only and may stay empty.

## Stable content id, e.g. `world.hub`.
@export var id: StringName = &""

## Optional player-facing name; presentation only.
@export var display_name: String = ""

## Scene loaded by the router; must be a PackedScene whose root is a `WorldHost`.
@export var scene: PackedScene = null

## Spawn id used when a travel request asks for no explicit spawn.
@export var default_spawn_id: StringName = &""


## Returns one message per invalid field; empty means the definition is usable.
func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors.append("id must not be empty")
	if scene == null:
		errors.append("scene must not be null")
	if default_spawn_id == &"":
		errors.append("default_spawn_id must not be empty")
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func _to_string() -> String:
	return "WorldDefinition(%s, scene=%s, default_spawn_id=%s)" % [
		id, scene, default_spawn_id
	]
