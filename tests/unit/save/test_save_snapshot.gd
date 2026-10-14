extends "res://tests/test_case.gd"

## AC-23 — `SaveSnapshot` is the only (de)serialisation point of the durable run
## state (ADR-010): JSON-compatible values, shape-strict parsing, version-agnostic.


func _full_snapshot() -> SaveSnapshot:
	var snapshot := SaveSnapshot.new()
	snapshot.version = SaveSnapshot.CURRENT_VERSION
	snapshot.health = 42.5
	snapshot.gold = 17
	snapshot.items = [
		{"id": "item.rusty_dagger", "count": 1},
		{"id": "item.minor_salve", "count": 3},
	]
	snapshot.world_id = &"world.dungeon.proto01"
	snapshot.spawn_id = &"spawn.dungeon.entry"
	snapshot.claimed_reward_keys = PackedStringArray([
		"world.dungeon.proto01/enemy.a",
		"world.dungeon.proto01/chest.a",
	])
	return snapshot


## Fails when `value` (or anything nested in it) is not JSON-compatible.
func _assert_json_compatible(value: Variant, path: String) -> void:
	if value is Object:
		fail("%s must not contain an Object (got %s)" % [path, value])
		return
	if value is Dictionary:
		for key: Variant in value:
			_assert_json_compatible(value[key], "%s.%s" % [path, key])
		return
	if value is Array or value is PackedStringArray:
		for i in value.size():
			_assert_json_compatible(value[i], "%s[%d]" % [path, i])
		return
	assert_true(
		value is StringName or value is String or value is int or value is float
			or value is bool or value == null,
		"%s is a JSON-compatible value (got %s)" % [path, type_string(typeof(value))]
	)


func test_default_snapshot_is_a_new_game() -> void:
	var snapshot := SaveSnapshot.new()
	assert_eq(snapshot.version, SaveSnapshot.CURRENT_VERSION, "new snapshots carry the current version")
	assert_eq(snapshot.health, 0.0, "health starts empty: the session fills it")
	assert_eq(snapshot.gold, 0, "gold starts at zero")
	assert_true(snapshot.items.is_empty(), "no items by default")
	assert_eq(snapshot.claimed_reward_keys.size(), 0, "no claimed keys by default")


func test_round_trip_preserves_every_field() -> void:
	var original := _full_snapshot()
	var restored := SaveSnapshot.from_dict(original.to_dict())
	assert_not_null(restored, "a full snapshot parses back")
	if restored == null:
		return
	assert_eq(restored.version, original.version, "version")
	assert_eq(restored.health, original.health, "health")
	assert_eq(restored.gold, original.gold, "gold")
	assert_eq(restored.items, original.items, "items, including their order")
	assert_eq(restored.world_id, original.world_id, "world id")
	assert_eq(restored.spawn_id, original.spawn_id, "spawn id")
	assert_eq(restored.claimed_reward_keys, original.claimed_reward_keys, "claimed loot keys")
	assert_eq(restored.to_dict(), original.to_dict(), "a second serialisation is stable")


func test_json_text_round_trip_matches() -> void:
	var original := _full_snapshot()
	var parsed: Variant = JSON.parse_string(JSON.stringify(original.to_dict()))
	assert_true(parsed is Dictionary, "the snapshot serialises to a JSON object")
	if not parsed is Dictionary:
		return
	var restored := SaveSnapshot.from_dict(parsed)
	assert_not_null(restored, "the parsed JSON is a usable snapshot")
	if restored == null:
		return
	assert_eq(restored.to_dict(), original.to_dict(), "JSON does not lose or retype any field")


func test_to_dict_contains_no_objects() -> void:
	var data := _full_snapshot().to_dict()
	_assert_json_compatible(data, "snapshot")
	assert_true(data.has("version") and data.has("health"), "the dictionary is self-describing")
	assert_ne(JSON.stringify(data), "", "the dictionary serialises to JSON text")
	assert_eq(
		typeof(data["items"][0]["count"]),
		TYPE_INT,
		"item counts stay integers through the dictionary"
	)
	assert_eq(typeof(data["items"][0]["id"]), TYPE_STRING, "item ids are plain strings")


func test_from_dict_rejects_missing_keys() -> void:
	var full := _full_snapshot().to_dict()
	for key: Variant in SaveSnapshot.REQUIRED_KEYS:
		var partial: Dictionary = full.duplicate()
		partial.erase(key)
		assert_null(SaveSnapshot.from_dict(partial), "a snapshot without '%s' is unusable" % key)
	assert_null(SaveSnapshot.from_dict({}), "an empty dictionary is unusable")


func test_from_dict_rejects_wrong_types() -> void:
	var mutations: Array[Dictionary] = [
		{"key": "version", "value": "1"},
		{"key": "version", "value": 1.5},
		{"key": "version", "value": null},
		{"key": "health", "value": "42.5"},
		{"key": "health", "value": null},
		{"key": "gold", "value": "17"},
		{"key": "gold", "value": 2.5},
		{"key": "items", "value": {}},
		{"key": "items", "value": ["item.minor_salve"]},
		{"key": "world_id", "value": 3},
		{"key": "spawn_id", "value": false},
		{"key": "claimed_reward_keys", "value": 3},
		{"key": "claimed_reward_keys", "value": [1]},
	]
	for mutation: Dictionary in mutations:
		var data := _full_snapshot().to_dict()
		data[mutation["key"]] = mutation["value"]
		assert_null(
			SaveSnapshot.from_dict(data),
			"%s = %s must be rejected" % [mutation["key"], mutation["value"]]
		)


func test_from_dict_rejects_malformed_item_entries() -> void:
	var cases: Array = [
		[{"id": "item.minor_salve"}],
		[{"count": 2}],
		[{"id": "item.minor_salve", "count": "2"}],
		[{"id": 7, "count": 2}],
		[{"id": "item.minor_salve", "count": 2}, "not an entry"],
	]
	for entries: Variant in cases:
		var data := _full_snapshot().to_dict()
		data["items"] = entries
		assert_null(SaveSnapshot.from_dict(data), "malformed item entries are rejected: %s" % [entries])


func test_a_newer_version_is_preserved_not_clamped() -> void:
	var data := _full_snapshot().to_dict()
	data["version"] = SaveSnapshot.CURRENT_VERSION + 98
	var snapshot := SaveSnapshot.from_dict(data)
	assert_not_null(snapshot, "an unknown version still has a readable shape")
	if snapshot == null:
		return
	assert_eq(
		snapshot.version,
		SaveSnapshot.CURRENT_VERSION + 98,
		"the version is preserved so the loader can refuse it explicitly"
	)
	assert_eq(snapshot.to_dict()["version"], SaveSnapshot.CURRENT_VERSION + 98, "and survives to_dict")


func test_version_of_probes_a_raw_dictionary() -> void:
	assert_eq(SaveSnapshot.version_of({"version": 2}), 2, "an integer version is read")
	assert_eq(SaveSnapshot.version_of({"version": 2.0}), 2, "an integral float is read")
	assert_null(SaveSnapshot.version_of({"version": "2"}), "a string is not a version")
	assert_null(SaveSnapshot.version_of({"version": 2.5}), "a fractional version is not a version")
	assert_null(SaveSnapshot.version_of({}), "a missing version is null")
	assert_null(SaveSnapshot.version_of({"version": null}), "a null version is null")
