extends "res://tests/test_case.gd"

## AC-44 — save v3: the equipment section round-trips, a v2 file migrates to v3 without
## losing anything, the v1 -> v2 -> v3 chain still works, and nothing new is invented for
## an old player.

const SIBLING_SUFFIXES: Array[String] = ["", ".tmp", ".bak", ".corrupt"]

var _path: String = ""
var _manager: SaveManager = null
var _case_index: int = 0


func setup() -> void:
	_case_index += 1
	_path = "user://w2_save_v3_%d.json" % _case_index
	_remove_files()
	_manager = SaveManager.new()
	_manager.setup(_path)


func teardown() -> void:
	_remove_files()


func _remove_files() -> void:
	for suffix in SIBLING_SUFFIXES:
		var candidate := _path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _write_raw(data: Dictionary) -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	assert_not_null(file, "the fixture file opens for writing")
	if file == null:
		return
	file.store_string(JSON.stringify(data))
	file.close()


func _read_raw() -> Dictionary:
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _v2_file() -> Dictionary:
	return {
		"version": 2,
		"health": 73.5,
		"gold": 42,
		"items": [{"id": "item.minor_salve", "count": 2}],
		"world_id": "world.hub",
		"spawn_id": "spawn.hub.shrine",
		"claimed_reward_keys": ["world.dungeon.proto01/enemy.a"],
		"dungeon_progress": {
			"completed": ["dungeon.01"],
			"unlocked": ["dungeon.01", "dungeon.02"],
			"first_clear_claimed": ["dungeon.01"],
			"story_flags": [],
		},
	}


# --- the current format -------------------------------------------------------

func test_the_current_version_is_three() -> void:
	assert_eq(SaveSnapshot.CURRENT_VERSION, 3, "v3 since ADR-015 added equipment")


func test_equipment_round_trips_through_the_file() -> void:
	var snapshot := SaveSnapshot.new()
	snapshot.health = 90.0
	snapshot.gold = 5
	snapshot.items = [{"id": "item.iron_sword", "count": 1}]
	snapshot.equipment = {"main_hand": "item.iron_sword", "chest_armor": "item.leather_vest"}
	var save_result := _manager.save(snapshot)
	assert_true(save_result.ok(), "the save succeeded: %s" % save_result.message)

	var load_result := _manager.load_snapshot()
	assert_true(load_result.ok(), "the load succeeded: %s" % load_result.message)
	assert_not_null(load_result.snapshot, "a snapshot came back")
	if load_result.snapshot == null:
		return
	assert_eq(load_result.snapshot.equipment.get("main_hand"), "item.iron_sword", "hand survived")
	assert_eq(load_result.snapshot.equipment.get("chest_armor"), "item.leather_vest", "chest survived")
	assert_eq(load_result.snapshot.equipment.size(), 2, "nothing extra was written")


func test_an_empty_equipment_map_is_written_and_read_back() -> void:
	var snapshot := SaveSnapshot.new()
	snapshot.health = 100.0
	snapshot.gold = 0
	var save_result := _manager.save(snapshot)
	assert_true(save_result.ok(), "the save succeeded: %s" % save_result.message)
	var load_result := _manager.load_snapshot()
	assert_true(load_result.ok(), "the load succeeded: %s" % load_result.message)
	if load_result.snapshot == null:
		return
	assert_eq(load_result.snapshot.equipment.size(), 0, "an unarmoured player saves an empty map")


func test_a_missing_equipment_key_reads_as_empty() -> void:
	# Hand-written v3 shape without the section (a future optional field must not crash).
	var data := _v2_file()
	data["version"] = 3
	_write_raw(data)
	var result := _manager.load_snapshot()
	assert_true(result.ok(), "the load succeeded: %s" % result.message)
	if result.snapshot == null:
		return
	assert_eq(result.snapshot.equipment.size(), 0, "no equipment, no crash")


func test_a_malformed_equipment_value_reads_as_empty() -> void:
	for bad_value in ["not a dictionary", 42, []]:
		var data := _v2_file()
		data["version"] = 3
		data["equipment"] = bad_value
		_write_raw(data)
		var result := _manager.load_snapshot()
		assert_true(result.ok(), "a %s section is tolerated" % type_string(typeof(bad_value)))
		if result.snapshot != null:
			assert_eq(result.snapshot.equipment.size(), 0, "and reads as empty")


# --- migrations ---------------------------------------------------------------

func test_a_v2_file_migrates_to_v3_with_an_empty_equipment_map() -> void:
	_write_raw(_v2_file())
	var result := _manager.load_snapshot()
	assert_true(result.ok(), "the load succeeded: %s" % result.message)
	assert_not_null(result.snapshot, "a snapshot came back")
	if result.snapshot == null:
		return
	assert_eq(result.snapshot.version, 3, "migrated to v3")
	assert_eq(result.snapshot.equipment.size(), 0, "an old player starts unarmoured")
	assert_almost_eq(result.snapshot.health, 73.5, 0.0001, "health survived")
	assert_eq(result.snapshot.gold, 42, "gold survived")
	assert_eq(result.snapshot.items, [{"id": "item.minor_salve", "count": 2}], "items survived")
	assert_eq(result.snapshot.world_id, &"world.hub", "location survived")
	assert_eq(result.snapshot.spawn_id, &"spawn.hub.shrine", "spawn survived")
	assert_eq(
		result.snapshot.claimed_reward_keys.size(), 1, "first-clear claims survived"
	)


func test_a_v2_file_keeps_its_dungeon_progress() -> void:
	_write_raw(_v2_file())
	var result := _manager.load_snapshot()
	if result.snapshot == null:
		return
	assert_eq(
		result.snapshot.dungeon_progress.get("completed"), ["dungeon.01"],
		"completed dungeons survived the migration"
	)
	assert_eq(
		result.snapshot.dungeon_progress.get("unlocked"), ["dungeon.01", "dungeon.02"],
		"unlocks survived the migration"
	)
	assert_eq(
		result.snapshot.dungeon_progress.get("first_clear_claimed"), ["dungeon.01"],
		"the story claim survived the migration"
	)


func test_a_v1_file_runs_the_whole_chain_to_v3() -> void:
	_write_raw({
		"version": 1,
		"health": 55.0,
		"gold": 9,
		"items": [{"id": "item.rusty_dagger", "count": 1}],
		"world_id": "world.hub",
		"spawn_id": "spawn.hub.shrine",
		"claimed_rewards": ["world.dungeon.proto01/enemy.a", "world.dungeon.proto01/enemy.b"],
	})
	var result := _manager.load_snapshot()
	assert_true(result.ok(), "the load succeeded: %s" % result.message)
	if result.snapshot == null:
		return
	assert_eq(result.snapshot.version, 3, "v1 reached v3")
	assert_eq(result.snapshot.gold, 9, "gold survived the chain")
	assert_almost_eq(result.snapshot.health, 55.0, 0.0001, "health survived the chain")
	assert_eq(result.snapshot.items, [{"id": "item.rusty_dagger", "count": 1}], "items survived")
	assert_eq(result.snapshot.equipment.size(), 0, "and the old player is unarmoured")


func test_the_migration_never_invents_an_equipped_item() -> void:
	_write_raw(_v2_file())
	var result := _manager.load_snapshot()
	if result.snapshot == null:
		return
	assert_false(
		result.snapshot.equipment.has("main_hand"),
		"a v2 player does not silently gain a weapon"
	)
	assert_false(
		result.snapshot.equipment.has("chest_armor"),
		"nor armour"
	)


func test_an_unknown_item_id_in_the_equipment_section_does_not_crash_the_load() -> void:
	var snapshot := SaveSnapshot.new()
	snapshot.health = 100.0
	snapshot.equipment = {"main_hand": "item.does_not_exist", "boots": "item.ghost"}
	_manager.save(snapshot)
	var result := _manager.load_snapshot()
	assert_true(result.ok(), "the load succeeded: %s" % result.message)
	if result.snapshot == null:
		return
	# The snapshot is a faithful record; the session filters unknown ids into warnings.
	assert_eq(
		result.snapshot.equipment.get("main_hand"), "item.does_not_exist",
		"the record is preserved for the session to filter"
	)


func test_a_future_version_is_refused_without_touching_the_file() -> void:
	var data := _v2_file()
	data["version"] = 99
	_write_raw(data)
	var before := _read_raw()
	var result := _manager.load_snapshot()
	assert_false(result.ok(), "a future version is refused")
	assert_eq(_read_raw(), before, "the file on disk is untouched")


func test_a_corrupt_file_does_not_crash_and_quarantines() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file != null:
		file.store_string("{ this is not json")
		file.close()
	var result := _manager.load_snapshot()
	assert_false(result.ok(), "a corrupt file is refused")
	assert_false(_manager.snapshot_exists(), "and the bad file is moved aside")
