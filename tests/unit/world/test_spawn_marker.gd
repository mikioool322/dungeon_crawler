extends "res://tests/test_case.gd"

## Spawn resolution is a pure rule (ADR-007): requested -> world default -> first by
## name -> null. Worlds own coordinates; definitions own only ids.

func _marker(spawn_id: StringName, node_name: String) -> SpawnMarker:
	var marker := SpawnMarker.new()
	marker.name = node_name
	marker.spawn_id = spawn_id
	add_to_tree(marker)
	return marker


func _markers() -> Array[SpawnMarker]:
	var list: Array[SpawnMarker] = []
	list.append(_marker(&"spawn.b", "Bravo"))
	list.append(_marker(&"spawn.a", "Alpha"))
	list.append(_marker(&"spawn.c", "Charlie"))
	return list


func test_requested_id_wins() -> void:
	var chosen := SpawnMarker.choose(_markers(), &"spawn.c", &"spawn.a")
	assert_eq(chosen.spawn_id, &"spawn.c", "the requested marker is used")
	assert_false(SpawnMarker.used_fallback(_markers(), &"spawn.c", &"spawn.a"), "no fallback reported")


func test_default_id_is_used_when_the_request_is_unknown() -> void:
	var chosen := SpawnMarker.choose(_markers(), &"spawn.missing", &"spawn.b")
	assert_eq(chosen.spawn_id, &"spawn.b", "the world default is used")
	assert_true(
		SpawnMarker.used_fallback(_markers(), &"spawn.missing", &"spawn.b"),
		"a substituted request is reported as a fallback"
	)


func test_first_marker_by_name_is_the_last_resort() -> void:
	var chosen := SpawnMarker.choose(_markers(), &"spawn.missing", &"spawn.also_missing")
	assert_eq(chosen.spawn_id, &"spawn.a", "fallback is deterministic: 'Alpha' sorts first")
	assert_eq(chosen.name, "Alpha", "and it is the alphabetically first marker")


func test_empty_request_resolves_to_the_default_without_a_fallback_report() -> void:
	var chosen := SpawnMarker.choose(_markers(), &"", &"spawn.b")
	assert_eq(chosen.spawn_id, &"spawn.b", "an empty request means 'the world default'")
	assert_false(
		SpawnMarker.used_fallback(_markers(), &"", &"spawn.b"),
		"using the default for an empty request is normal, not a fallback"
	)


func test_no_markers_means_no_spawn() -> void:
	var empty: Array[SpawnMarker] = []
	assert_null(SpawnMarker.choose(empty, &"spawn.a", &"spawn.b"), "empty world has no spawn")
	assert_true(SpawnMarker.used_fallback(empty, &"spawn.a", &"spawn.b"), "and reports a fallback")


func test_markers_without_ids_are_still_usable_as_a_last_resort() -> void:
	var list: Array[SpawnMarker] = []
	list.append(_marker(&"", "OnlyOne"))
	var chosen := SpawnMarker.choose(list, &"spawn.missing", &"spawn.also_missing")
	assert_not_null(chosen, "a marker without an id is still a position")
	assert_eq(chosen.name, "OnlyOne", "the only marker is used")
