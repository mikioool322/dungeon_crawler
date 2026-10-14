class_name SpawnMarker
extends Node3D

## Named player start position inside a world scene (ADR-007).
##
## Spawn coordinates live in the scene that owns the geometry, never in a
## `WorldDefinition` and never in portal logic. The router picks a marker only
## through `choose()`, so the fallback rule is one pure, testable function.

## Stable spawn id, e.g. `spawn.hub.start`. Must be unique inside one world.
@export var spawn_id: StringName = &""


## Resolves which marker to use: the requested id, else the world's default id,
## else the first marker by name; null when the world has no markers at all.
static func choose(
	markers: Array[SpawnMarker], requested: StringName, default_id: StringName
) -> SpawnMarker:
	var ordered := _sorted(markers)
	if requested != &"":
		for marker in ordered:
			if marker.spawn_id == requested:
				return marker
	if default_id != &"":
		for marker in ordered:
			if marker.spawn_id == default_id:
				return marker
	if ordered.is_empty():
		return null
	return ordered[0]


## True when `requested` could not be satisfied and a fallback was used.
static func used_fallback(
	markers: Array[SpawnMarker], requested: StringName, default_id: StringName
) -> bool:
	var chosen := choose(markers, requested, default_id)
	return chosen == null or chosen.spawn_id != requested


static func _sorted(markers: Array[SpawnMarker]) -> Array[SpawnMarker]:
	var ordered: Array[SpawnMarker] = []
	for marker in markers:
		if marker != null and is_instance_valid(marker):
			ordered.append(marker)
	ordered.sort_custom(func(a: SpawnMarker, b: SpawnMarker) -> bool:
		return String(a.name) < String(b.name)
	)
	return ordered
